#!/usr/bin/env python3
"""The figures, the bars and the default of issue #295's comparison, as
pre-registered in .decisions/issue-295.md, from what run.sh wrote.

Usage:
  summarize.py [--dir <dir>] [--plugin <dir>]           print KEY=VALUE figures
  summarize.py [--dir <dir>] [--plugin <dir>] --write   also write summary.md and summary.json
  summarize.py [--dir <dir>] [--plugin <dir>] --check ac1|ac2|ac4

--dir is where run.sh wrote its files (default: this directory); --plugin is
the plugin whose settings.json, references/system-one.md and client --check
reads (default: the plugin this file is in).

For each set (goal, review) and send X, an item's p is the p its record
holds; an item with no answer has none. Against A1 (the first send of each
item alone):
  crossings C(X, t)  items answered in both whose p falls on different sides
                     of t (p >= t against p < t)
  lost(X)            items answered in A1 and not in X
  median |dp|(X)     median of |p_X - p_A1| over items answered in both
  agree(X)           goal set: items whose p >= 0.5 matches the label
Lines: goal 0.5, 0.75, 0.8; review 0.5, 0.05.

Bars, for each layout L (S = items-in-state, Q = items-in-questions):
  1  goal, each line: C(L, t) <= C(A2, t) + 3
  2  goal: agree(L) >= agree(A1) - 3
  3  review, each line: C(L, t) <= C(A2, t) + 2
  4  each set: lost(L) <= 2
  5  each set: median |dp|(L) <= median |dp|(A2) + 0.02
Default: the layout that passes; if both pass, the one with fewer crossings
at 0.5 over both sets; on a tie, items-in-questions; if neither, off.

Exit: 0 with figures, or for --check when the criterion holds; 1 when a
--check does not hold; 2 on input that is missing, incomplete or not in the
shape run.sh writes (a message on stderr, never a traceback).
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import json  # noqa: E402
import re  # noqa: E402
import statistics  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SETS = {"goal": (0.5, 0.75, 0.8), "review": (0.5, 0.05)}
SENDS = ("A1", "A2", "S", "Q")
LAYOUTS = {"S": "items-in-state", "Q": "items-in-questions"}
BATCH_SITES = ("goal.judge", "goal.warn-evidence", "review.confidence")
PER_ITEM_SITES = ("review.challenge", "review.dedup", "address.category", "address.still_applies")
SECTION = "### Asking about several items at once"


class BadInput(Exception):
    pass


def read_jsonl(path):
    if not os.path.isfile(path):
        raise BadInput("missing: %s" % path)
    out = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                v = json.loads(line)
            except ValueError:
                raise BadInput("%s line %d is not JSON" % (path, n))
            if not isinstance(v, dict):
                raise BadInput("%s line %d is not an object" % (path, n))
            out.append(v)
    return out


def need(obj, field, kind, where):
    v = obj.get(field)
    if kind is float:
        ok = isinstance(v, (int, float)) and not isinstance(v, bool)
    else:
        ok = isinstance(v, kind) and not (kind is int and isinstance(v, bool))
    if not ok:
        raise BadInput("%s: %s is not %s" % (where, field, kind.__name__))
    return v


def load(d, which):
    run_path = os.path.join(d, "run-%s.json" % which)
    if not os.path.isfile(run_path):
        raise BadInput("no run-%s.json: the %s run did not finish" % (which, which))
    try:
        with open(run_path, encoding="utf-8") as f:
            run = json.load(f)
    except ValueError:
        raise BadInput("run-%s.json is not JSON" % which)
    if not isinstance(run, dict):
        raise BadInput("run-%s.json is not an object" % which)
    inputs = read_jsonl(os.path.join(d, "inputs-%s.jsonl" % which))
    if not inputs:
        raise BadInput("inputs-%s.jsonl is empty" % which)
    by_ref = {}
    for i, it in enumerate(inputs, 1):
        w = "inputs-%s line %d" % (which, i)
        for f in ("group", "key", "ref", "sha256"):
            need(it, f, str, w)
        if which == "goal" and it.get("label") not in ("supported", "not_supported"):
            raise BadInput("%s: label must be supported or not_supported" % w)
        if it["ref"] in by_ref:
            raise BadInput("%s: ref %s appears twice" % (w, it["ref"]))
        by_ref[it["ref"]] = it
    records = {}
    for s in SENDS:
        rows = read_jsonl(os.path.join(d, "records-%s-%s.jsonl" % (which, s)))
        recs = {}
        for i, r in enumerate(rows, 1):
            w = "records-%s-%s line %d" % (which, s, i)
            ref = need(r, "ref", str, w)
            need(r, "result", str, w)
            if ref not in by_ref:
                raise BadInput("%s: ref %s is not an input" % (w, ref))
            if r.get("state_sha256") != by_ref[ref]["sha256"]:
                raise BadInput("%s: state_sha256 is not the digest of the input %s" % (w, ref))
            a = r.get("answer")
            if a is not None:
                if not isinstance(a, dict):
                    raise BadInput("%s: answer is not an object" % w)
                need(a, "p", float, w)
            if s in ("S", "Q") and "batch" in r and r["batch"] is not None:
                b = r["batch"]
                if not isinstance(b, dict):
                    raise BadInput("%s: batch is not an object" % w)
                need(b, "id", str, w)
                need(b, "index", int, w)
                if b.get("layout") != LAYOUTS[s]:
                    raise BadInput("%s: batch.layout is not %s" % (w, LAYOUTS[s]))
            if ref in recs:
                raise BadInput("%s: a second record for %s" % (w, ref))
            recs[ref] = r
        records[s] = recs
    meta = read_jsonl(os.path.join(d, "meta-%s.jsonl" % which))
    for i, m in enumerate(meta, 1):
        w = "meta-%s line %d" % (which, i)
        if m.get("send") not in SENDS:
            raise BadInput("%s: send is not one of %s" % (w, ", ".join(SENDS)))
        need(m, "ms", int, w)
        need(m, "rc", int, w)
    return run, inputs, records, meta


def p_of(rec):
    if rec is None or not isinstance(rec.get("answer"), dict):
        return None
    return float(rec["answer"]["p"])


def nearest_rank(values, q):
    if not values:
        return None
    v = sorted(values)
    k = max(1, -(-len(v) * q // 100))
    return v[int(k) - 1]


def figures(which, inputs, records, meta):
    lines = SETS[which]
    refs = [it["ref"] for it in inputs]
    p = {s: {r: p_of(records[s].get(r)) for r in refs} for s in SENDS}
    out = {"items": len(refs), "sends": {}}
    for s in SENDS:
        f = {"answered": sum(1 for r in refs if p[s][r] is not None)}
        if s != "A1":
            both = [r for r in refs if p["A1"][r] is not None and p[s][r] is not None]
            f["crossings"] = {str(t): sum(1 for r in both if (p["A1"][r] >= t) != (p[s][r] >= t)) for t in lines}
            f["lost"] = sum(1 for r in refs if p["A1"][r] is not None and p[s][r] is None)
            f["median_abs_dp"] = round(statistics.median([abs(p[s][r] - p["A1"][r]) for r in both]), 6) if both else None
        if which == "goal":
            lab = {it["ref"]: it["label"] == "supported" for it in inputs}
            f["agree"] = sum(1 for r in refs if p[s][r] is not None and (p[s][r] >= 0.5) == lab[r])
        recs = list(records[s].values())
        if s in ("A1", "A2"):
            f["requests"] = sum(1 for m in meta if m["send"] == s and m.get("call") == "ask")
        else:
            ids = {r["batch"]["id"] for r in recs if isinstance(r.get("batch"), dict)}
            f["requests"] = len(ids) + sum(1 for r in recs if not isinstance(r.get("batch"), dict))
            pos = {}
            for r in recs:
                b = r.get("batch")
                if not isinstance(b, dict) or p["A1"].get(r["ref"]) is None or p_of(r) is None:
                    continue
                k = str(b["index"])
                c = pos.setdefault(k, [0, 0])
                c[0] += 1
                c[1] += int((p["A1"][r["ref"]] >= 0.5) != (p_of(r) >= 0.5))
            f["crossings_0.5_by_position"] = {k: {"items": v[0], "crossings": v[1]} for k, v in sorted(pos.items(), key=lambda kv: int(kv[0]))}
        ms = [m["ms"] for m in meta if m["send"] == s]
        f["calls"] = len(ms)
        f["ms_per_call_median"] = statistics.median(ms) if ms else None
        f["ms_per_call_p95"] = nearest_rank(ms, 95)
        f["ms_total"] = sum(ms)
        f["timeouts"] = sum(1 for r in recs if r.get("result") == "timeout")
        out["sends"][s] = f
    return out


def bars(fig):
    res = {}
    for x, layout in LAYOUTS.items():
        g, r = fig["goal"]["sends"], fig["review"]["sends"]
        b = {}
        b["1"] = all(g[x]["crossings"][str(t)] <= g["A2"]["crossings"][str(t)] + 3 for t in SETS["goal"])
        b["2"] = g[x]["agree"] >= g["A1"]["agree"] - 3
        b["3"] = all(r[x]["crossings"][str(t)] <= r["A2"]["crossings"][str(t)] + 2 for t in SETS["review"])
        b["4"] = g[x]["lost"] <= 2 and r[x]["lost"] <= 2
        b["5"] = all(s[x]["median_abs_dp"] is not None and s["A2"]["median_abs_dp"] is not None
                     and round(s[x]["median_abs_dp"] - s["A2"]["median_abs_dp"], 6) <= 0.02 for s in (g, r))
        res[layout] = {"bars": b, "pass": all(b.values()),
                       "crossings_0.5_both_sets": g[x]["crossings"]["0.5"] + r[x]["crossings"]["0.5"]}
    passing = [k for k, v in res.items() if v["pass"]]
    if not passing:
        default = "off"
    elif len(passing) == 1:
        default = passing[0]
    else:
        a, b = (res[k]["crossings_0.5_both_sets"] for k in ("items-in-state", "items-in-questions"))
        default = "items-in-state" if a < b else "items-in-questions"
    return res, default


TIMING_SENDS = ("alone", "items-in-state", "items-in-questions")


def timing(d, which):
    """Time per request from time_requests.py, or None when it was not run."""
    path = os.path.join(d, "timing-%s.jsonl" % which)
    run_path = os.path.join(d, "timing-run-%s.json" % which)
    if not os.path.isfile(path) and not os.path.isfile(run_path):
        return None
    if not os.path.isfile(run_path):
        raise BadInput("no timing-run-%s.json: the timing of the %s set did not finish" % (which, which))
    with open(run_path, encoding="utf-8") as f:
        run = json.load(f)
    rows = read_jsonl(path)
    out = {"run": {k: run.get(k) for k in ("model", "timeout_ms", "commit", "started", "ended")}, "sends": {}}
    for i, r in enumerate(rows, 1):
        w = "timing-%s line %d" % (which, i)
        if r.get("send") not in TIMING_SENDS:
            raise BadInput("%s: send is not one of %s" % (w, ", ".join(TIMING_SENDS)))
        need(r, "ms", int, w)
        need(r, "items", int, w)
        need(r, "result", str, w)
    for send in TIMING_SENDS:
        sel = [r for r in rows if r["send"] == send]
        ok = [r for r in sel if r["result"] == "ok"]
        ms = [r["ms"] for r in ok]
        out["sends"][send] = {
            "requests": len(sel), "failed": len(sel) - len(ok),
            "timeouts": sum(1 for r in sel if r["result"] == "timeout"),
            "items_per_request": round(sum(r["items"] for r in sel) / len(sel), 2) if sel else None,
            "ms_median": statistics.median(ms) if ms else None,
            "ms_p95": nearest_rank(ms, 95),
            "ms_per_item_median": round(statistics.median([r["ms"] / r["items"] for r in ok]), 1) if ok else None,
            "ms_total": sum(ms),
        }
    return out


def compute(d):
    fig, runs, times = {}, {}, {}
    for which in SETS:
        run, inputs, records, meta = load(d, which)
        runs[which] = {k: run.get(k) for k in ("site", "model", "timeout_ms", "commit", "uncommitted_changes", "started", "ended", "groups", "items")}
        fig[which] = figures(which, inputs, records, meta)
        times[which] = timing(d, which)
    res, default = bars(fig)
    return {"runs": runs, "figures": fig, "timing": times, "layouts": res, "default": default}


def markdown(s):
    out = ["# Asking about several items at once: the comparison", ""]
    for which in SETS:
        r = s["runs"][which]
        out.append("- %s set: %s items in %s groups, site `%s`, model %s, timeout %s ms, %s to %s, commit %s%s."
                   % (which, r["items"], r["groups"], r["site"], r["model"], r["timeout_ms"], r["started"], r["ended"],
                      (r["commit"] or "")[:8], "" if r["uncommitted_changes"] is False else " (with uncommitted changes)"))
    out.append("")
    for which, lines in SETS.items():
        f = s["figures"][which]["sends"]
        out += ["## %s set" % which.capitalize(), ""]
        head = "| Measure | A1 | A2 | S (items in state) | Q (items in questions) |"
        out += [head, "|---|---|---|---|---|"]
        def row(label, fn):
            out.append("| %s | %s |" % (label, " | ".join(fn(x) for x in SENDS)))
        row("Requests (fewer is cheaper)", lambda x: str(f[x]["requests"]))
        row("Items answered", lambda x: str(f[x]["answered"]))
        for t in lines:
            row("Crossings of %s against A1 (fewer is closer)" % t, lambda x, t=t: "" if x == "A1" else str(f[x]["crossings"][str(t)]))
        row("Answered in A1, not here (fewer is better)", lambda x: "" if x == "A1" else str(f[x]["lost"]))
        row("Median difference in p from A1 (smaller is closer)", lambda x: "" if x == "A1" else ("%.3f" % f[x]["median_abs_dp"] if f[x]["median_abs_dp"] is not None else "n/a"))
        if which == "goal":
            row("Agree with the label at 0.5 (more is better)", lambda x: str(f[x]["agree"]))
        row("Client calls", lambda x: str(f[x]["calls"]))
        row("Requests per client call", lambda x: "%.2f" % (f[x]["requests"] / f[x]["calls"]) if f[x]["calls"] else "n/a")
        row("Time per call, median ms", lambda x: str(f[x]["ms_per_call_median"]))
        row("Time per call, 95th percentile ms", lambda x: str(f[x]["ms_per_call_p95"]))
        row("Time for the whole send, ms", lambda x: str(f[x]["ms_total"]))
        row("Timeouts", lambda x: str(f[x]["timeouts"]))
        out.append("")
        out.append("Times are wall time per client call, measured by run.sh around each call, so they include starting "
                   "bash and Python and reading the settings, not only the request. A1 and A2 make one request per call; "
                   "S and Q make the number of requests per call shown above. Lower is faster.")
        out.append("")
        for x in ("S", "Q"):
            pos = f[x]["crossings_0.5_by_position"]
            if pos:
                out.append("%s, crossings of 0.5 by position in the request: %s."
                           % (x, ", ".join("position %s: %d of %d" % (k, v["crossings"], v["items"]) for k, v in pos.items())))
        out.append("")
    out += ["## Time per request", "",
            "Measured by time_requests.py: each request on its own, from sending it to reading the whole reply, "
            "with nothing else running; the requests are the ones the client builds for each send. Lower is faster.", ""]
    for which in SETS:
        t = s["timing"][which]
        if t is None:
            out += ["%s set: not measured." % which.capitalize(), ""]
            continue
        r = t["run"]
        out += ["%s set, %s, timeout %s ms, %s to %s, commit %s." % (which.capitalize(), r["model"], r["timeout_ms"],
                                                                  r["started"], r["ended"], (r["commit"] or "")[:8]), "",
                "| Send | Requests | Items per request | Median ms per request | 95th percentile ms | Median ms per item | Failed | Timeouts |",
                "|---|---|---|---|---|---|---|---|"]
        for send, v in t["sends"].items():
            out.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (send, v["requests"], v["items_per_request"], v["ms_median"],
                                                                 v["ms_p95"], v["ms_per_item_median"], v["failed"], v["timeouts"]))
        out.append("")
    out += ["## Bars", "", "| Layout | 1 | 2 | 3 | 4 | 5 | Passes |", "|---|---|---|---|---|---|---|"]
    for layout, v in s["layouts"].items():
        b = v["bars"]
        out.append("| %s | %s | %s |" % (layout, " | ".join("met" if b[k] else "not met" for k in "12345"), "yes" if v["pass"] else "no"))
    out += ["", "Default chosen by the pre-registered rule: `%s`." % s["default"], ""]
    return "\n".join(out)


def check_ac1(s):
    for which in SETS:
        f = s["figures"][which]["sends"]
        for x in ("S", "Q"):
            if not f[x]["requests"] < f["A1"]["requests"]:
                return "%s set: %s made %d requests, not fewer than A1's %d" % (which, x, f[x]["requests"], f["A1"]["requests"])
        for x in SENDS:
            if f[x]["ms_per_call_median"] is None or "timeouts" not in f[x]:
                return "%s set: %s has no timing or timeout figure" % (which, x)
        t = s["timing"][which]
        if t is None:
            return "%s set: the time per request was not measured (time_requests.py)" % which
        for send, v in t["sends"].items():
            if not v["requests"] or v["ms_median"] is None:
                return "%s set: no timed request for %s" % (which, send)
    return None


def plugin_default(plugin):
    with open(os.path.join(plugin, "settings.json"), encoding="utf-8") as f:
        return json.load(f).get("systemOne", {}).get("batch")


def check_ac2(s, plugin):
    for layout in LAYOUTS.values():
        if set(s["layouts"][layout]["bars"]) != set("12345"):
            return "%s: not every bar was computed" % layout
    got = plugin_default(plugin)
    if got != s["default"]:
        return "settings.json has systemOne.batch %r; the measurement chose %r" % (got, s["default"])
    return None


def check_ac4(plugin):
    with open(os.path.join(plugin, "references", "system-one.md"), encoding="utf-8") as f:
        text = f.read()
    if SECTION not in text:
        return "references/system-one.md has no section %r" % SECTION
    body = text.split(SECTION, 1)[1]
    body = re.split(r"\n#{2,3} ", body, maxsplit=1)[0]
    for site in PER_ITEM_SITES:
        lines = [ln for ln in body.splitlines() if "`%s`" % site in ln]
        if not lines:
            return "the section does not name %s" % site
        if not any(re.search(r"\b(because|since)\b", ln) for ln in lines):
            return "the section names %s without a reason (a line with because or since)" % site
    with open(os.path.join(plugin, "bin", "_flow_s1.py"), encoding="utf-8") as f:
        m = re.search(r"^BATCH_SITES = \(([^)]*)\)", f.read(), re.M)
    if not m or tuple(re.findall(r'"([^"]+)"', m.group(1))) != BATCH_SITES:
        return "bin/_flow_s1.py BATCH_SITES is not %s" % (BATCH_SITES,)
    with open(os.path.join(plugin, "bin", "flow-s1.sh"), encoding="utf-8") as f:
        if "    goal.judge|goal.warn-evidence|review.confidence) ;;" not in f.read():
            return "bin/flow-s1.sh does not limit ask-many to %s" % ", ".join(BATCH_SITES)
    return None


def main(argv):
    d, plugin, write, check = HERE, os.path.dirname(os.path.dirname(HERE)), False, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--dir", "--plugin", "--check") and i + 1 < len(argv):
            if a == "--dir":
                d = argv[i + 1]
            elif a == "--plugin":
                plugin = argv[i + 1]
            else:
                check = argv[i + 1]
            i += 2
        elif a == "--write":
            write, i = True, i + 1
        else:
            sys.stderr.write("summarize.py: unknown argument %s\n" % a)
            return 2
    if check not in (None, "ac1", "ac2", "ac4"):
        sys.stderr.write("summarize.py: --check takes ac1, ac2 or ac4\n")
        return 2
    try:
        if check == "ac4":
            why = check_ac4(plugin)
            print("AC4=%s" % ("OK" if why is None else "FAIL " + why))
            return 0 if why is None else 1
        s = compute(d)
        if write:
            with open(os.path.join(d, "summary.json"), "w", encoding="utf-8") as f:
                json.dump(s, f, indent=2, sort_keys=True)
                f.write("\n")
            with open(os.path.join(d, "summary.md"), "w", encoding="utf-8") as f:
                f.write(markdown(s))
        if check:
            why = None
            try:
                with open(os.path.join(d, "summary.json"), encoding="utf-8") as f:
                    if json.load(f) != json.loads(json.dumps(s)):
                        why = "summary.json is not what the records give; run --write"
            except (OSError, ValueError):
                why = "no readable summary.json; run --write"
            if why is None:
                why = check_ac1(s) if check == "ac1" else check_ac2(s, plugin)
            print("%s=%s" % (check.upper(), "OK" if why is None else "FAIL " + why))
            return 0 if why is None else 1
    except BadInput as e:
        sys.stderr.write("summarize.py: %s\n" % e)
        return 2
    except (OSError, ValueError) as e:
        sys.stderr.write("summarize.py: %s: %s\n" % (type(e).__name__, e))
        return 2
    for which in SETS:
        for x, f in s["figures"][which]["sends"].items():
            print("%s_%s_REQUESTS=%s" % (which.upper(), x, f["requests"]))
            print("%s_%s_ANSWERED=%s" % (which.upper(), x, f["answered"]))
            for t, c in (f.get("crossings") or {}).items():
                print("%s_%s_CROSSINGS_%s=%s" % (which.upper(), x, t, c))
    for layout, v in s["layouts"].items():
        print("%s_PASS=%s" % (layout.upper().replace("-", "_"), "yes" if v["pass"] else "no"))
    print("DEFAULT=%s" % s["default"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
