#!/usr/bin/env python3
"""Summarize the address.category wording comparison of issue #296.

Reads the records run.sh kept for the two wordings (records-<form>.jsonl,
meta-<form>.jsonl, run-<form>.json in --dir) against the labelled items, and
prints one KEY=VALUE line per figure. --write also writes summary.json and
summary.md into --dir. --check ac1|ac2|ac3 checks one acceptance criterion
of the issue and exits 0 when it holds, 1 when it does not.

The rules, as pre-registered in .decisions/issue-296.md:
- An item is answered when its last record carries an answer (result
  answered or below-threshold). A refused item (its text names a priority)
  and an item with no answer stay in the denominator.
- A raise at threshold t: the answer's confidence is at or above t and its
  choice ranks above the label (P1 > P2 > P3 > Question). A truncated item is
  never a raise: the block does not act on it.
- A labelled P1 placed lower: the label is P1 and the choice ranks below it,
  at any confidence (and, reported beside it, at 0.8).
- Bars, at 0.8: (1) the alternative's raises are at most half the current
  wording's; (2) the alternative places no more labelled P1 items lower than
  the current wording; (3) the alternative answers at least 195 of 200 items
  (97.5%); (4) on a blind sample of up to 20 items the two wordings answered
  differently (the first by the sha256 of the item ref), the alternative's
  choice equals the user's ruling at least as often as the current
  wording's. Until every sampled item has a ruling in rulings.jsonl, bar 4,
  and with it the result, is pending, unless bars 1 to 3 already fail: bar 4
  is then not needed and the result is fail. --sample prints the sample to rule on,
  without any priority.

Exit 2 on a usage error or an input file that is missing or cannot be read
(not JSON, a label outside P1/P2/P3/Question, a row without a ref, a questions
file without the address.category site).
"""
import os
import sys

# The working directory never supplies a module (a planted ./json.py): the
# filter runs before any other import.
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)
               and not (os.path.isdir(p) and os.path.samefile(p, os.curdir))]

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import re  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(PLUGIN, "bin"))
import _flow_s1  # noqa: E402

FORMS = ("current", "alternative")
RANK = {"P1": 4, "P2": 3, "P3": 2, "Question": 1}
THRESHOLDS = (0.5, 0.6, 0.7, 0.8, 0.9, 0.95)
BAR_T = 0.8
MIN_ANSWERED_SHARE = 195 / 200
SAMPLE_SIZE = 20
MODEL = "jev-1.13.0"
REF = re.compile(r"^replay:pr-finding:pr([0-9]+)-review([0-9]+)-([A-Za-z][A-Za-z0-9_-]*)$")


def fail(msg, code=2):
    print("summarize.py: " + msg, file=sys.stderr)
    sys.exit(code)


NUMBER = (int, float)
# Every field the summary reads, with the types it accepts; null or absent is
# accepted unless the field is listed as required. A row of another shape is
# input the summary cannot read (exit 2), never a criterion that fails.
ITEM_SHAPE = {"ref": str, "reviewer_priority": str, "model_choice": str, "text": str, "path": str,
              "line": (str, int)}
RECORD_SHAPE = {"site": str, "ref": str, "result": str, "ts": str, "model": str, "state_sha256": str,
                "answer": dict}
ANSWER_SHAPE = {"choice": str, "confidence": NUMBER}
META_SHAPE = {"ref": str, "refused": bool, "truncated": bool, "reason": str, "state_sha256": str}
RULING_SHAPE = {"ref": str, "ruling": str}
RUN_SHAPE = {"sent_sha256": str, "model": str}


def check_shape(row, shape, where, required=()):
    for field in required:
        if row.get(field) is None:
            fail("%s has no %s" % (where, field))
    for field, types in shape.items():
        v = row.get(field)
        if v is None:
            continue
        # bool is an int to Python; it is never a number or a line here.
        if not isinstance(v, types) or (isinstance(v, bool) and bool not in (types if isinstance(types, tuple) else (types,))):
            fail("%s: field %s has type %s" % (where, field, type(v).__name__))


def read_jsonl(path, required=True):
    if not os.path.isfile(path):
        if required:
            fail("missing file: " + path)
        return []
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except ValueError as e:
                fail("%s line %d is not JSON: %s" % (path, n, e))
            if not isinstance(row, dict):
                fail("%s line %d is not a JSON object" % (path, n))
            rows.append(row)
    return rows


def read_items(path):
    items = read_jsonl(path)
    for n, i in enumerate(items, 1):
        check_shape(i, ITEM_SHAPE, "%s line %d" % (path, n), required=("ref",))
        if i.get("reviewer_priority") not in RANK:
            fail("%s line %d has reviewer_priority %r, not one of %s"
                 % (path, n, i.get("reviewer_priority"), ", ".join(RANK)))
        record_ref(i["ref"])
    return items


def wording_hash(path):
    try:
        questions = _flow_s1.load_site(path, "address.category")[0]
    except _flow_s1.NoAnswer as e:
        fail("%s has no usable address.category questions (%s)" % (path, " ".join(str(x) for x in e.args)))
    return hashlib.sha256(json.dumps(questions, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def record_ref(item_ref):
    m = REF.match(item_ref)
    if not m:
        fail("item ref not in the expected shape: " + item_ref)
    return "pr:%s/review:%s/%s" % m.groups()


def at_or_above(conf, t):
    return conf is not None and conf >= t - 1e-9


def form_figures(items, form, d):
    run_path = os.path.join(d, "run-%s.json" % form)
    if not os.path.isfile(run_path):
        fail("missing file: %s (a run that stopped part way writes none)" % run_path)
    try:
        with open(run_path, encoding="utf-8") as fh:
            run = json.load(fh)
    except ValueError as e:
        fail("%s is not JSON: %s" % (run_path, e))
    if not isinstance(run, dict):
        fail("%s is not a JSON object" % run_path)
    check_shape(run, RUN_SHAPE, run_path)
    all_records = read_jsonl(os.path.join(d, "records-%s.jsonl" % form))
    for n, r in enumerate(all_records, 1):
        where = "records-%s.jsonl line %d" % (form, n)
        check_shape(r, RECORD_SHAPE, where)
        if r.get("answer") is not None:
            check_shape(r["answer"], ANSWER_SHAPE, where + " answer")
    records = [r for r in all_records if r.get("site") == "address.category"]
    # The client writes ref and result on every record; one without either is
    # not a record the summary can count.
    for r in records:
        check_shape(r, RECORD_SHAPE, "records-%s.jsonl record %s" % (form, r.get("ref")), required=("ref", "result"))
    meta_rows = read_jsonl(os.path.join(d, "meta-%s.jsonl" % form))
    for n, m in enumerate(meta_rows, 1):
        check_shape(m, META_SHAPE, "meta-%s.jsonl line %d" % (form, n), required=("ref",))
    meta = {m["ref"]: m for m in meta_rows}
    last, seen = {}, {}
    for r in records:
        seen[r.get("ref")] = seen.get(r.get("ref"), 0) + 1
        last[r.get("ref")] = r
    want = {record_ref(i["ref"]) for i in items}
    f = {"items": len(items), "answered": 0, "no_answer": 0, "refused": 0, "truncated": 0,
         "retried": sum(1 for ref, n in seen.items() if n > 1 and ref in want), "agree": 0,
         "p1_lowered": 0, "p1_lowered_bar": 0, "raises": {t: 0 for t in THRESHOLDS},
         "pairs": {}, "matrix": {a: {b: 0 for b in RANK} for a in RANK}, "no_answer_reasons": {},
         "choices": {}, "unknown_refs": sorted(set(last) - want), "models": set(),
         "state_mismatch": 0, "sent_sha256": run.get("sent_sha256"), "run": run,
         "ts": sorted(r["ts"] for r in records if r.get("ts")),
         "meta_rows": len(meta_rows), "meta_unmatched": len(set(meta) - {i["ref"] for i in items}),
         "meta_items": len(set(meta) & {i["ref"] for i in items})}
    for it in items:
        label = it["reviewer_priority"]
        m = meta.get(it["ref"], {})
        if m.get("refused"):
            f["refused"] += 1
            f["no_answer"] += 1
            f["no_answer_reasons"]["refused"] = f["no_answer_reasons"].get("refused", 0) + 1
            continue
        rec = last.get(record_ref(it["ref"]))
        ans = rec.get("answer") if rec else None
        if not ans or ans.get("choice") not in RANK:
            f["no_answer"] += 1
            # With no record, the reason the harness saw on the client's
            # stderr, when it kept one.
            why = rec.get("result", "no-record") if rec else ("no-record:" + m["reason"] if m.get("reason") else "no-record")
            f["no_answer_reasons"][why] = f["no_answer_reasons"].get(why, 0) + 1
            continue
        f["answered"] += 1
        if rec.get("model"):
            f["models"].add(rec["model"])
        if m.get("state_sha256") and rec.get("state_sha256") and m["state_sha256"] != rec["state_sha256"]:
            f["state_mismatch"] += 1
        choice, conf = ans["choice"], ans.get("confidence")
        f["choices"][it["ref"]] = choice
        f["matrix"][label][choice] += 1
        truncated = bool(m.get("truncated"))
        f["truncated"] += truncated
        if choice == label:
            f["agree"] += 1
        if label == "P1" and RANK[choice] < RANK["P1"]:
            f["p1_lowered"] += 1
            if at_or_above(conf, BAR_T):
                f["p1_lowered_bar"] += 1
        if RANK[choice] > RANK[label] and not truncated:
            for t in THRESHOLDS:
                if at_or_above(conf, t):
                    f["raises"][t] += 1
            if at_or_above(conf, BAR_T):
                key = "%s>%s" % (label, choice)
                f["pairs"][key] = f["pairs"].get(key, 0) + 1
    f["models"] = sorted(f["models"])
    return f


def sample(items, figs):
    """The items both forms answered with different choices, first 20 by the
    sha256 of the item ref."""
    cur, alt = figs["current"]["choices"], figs["alternative"]["choices"]
    diff = [i for i in items if i["ref"] in cur and i["ref"] in alt and cur[i["ref"]] != alt[i["ref"]]]
    diff.sort(key=lambda i: hashlib.sha256(i["ref"].encode()).hexdigest())
    return diff[:SAMPLE_SIZE]


def rulings_bar(items, figs, d):
    """(state, sample size, current matches, alternative matches); state is
    pass, fail or pending."""
    picked = sample(items, figs)
    rows = read_jsonl(os.path.join(d, "rulings.jsonl"), required=False)
    for n, r in enumerate(rows, 1):
        check_shape(r, RULING_SHAPE, "rulings.jsonl line %d" % n, required=("ref",))
    rulings = {r["ref"]: r.get("ruling") for r in rows}
    if any(rulings.get(i["ref"]) not in RANK for i in picked):
        return "pending", len(picked), None, None
    cur = sum(1 for i in picked if figs["current"]["choices"][i["ref"]] == rulings[i["ref"]])
    alt = sum(1 for i in picked if figs["alternative"]["choices"][i["ref"]] == rulings[i["ref"]])
    return ("pass" if alt >= cur else "fail"), len(picked), cur, alt


def bars(cur, alt, b4="pass"):
    b1 = alt["raises"][BAR_T] <= cur["raises"][BAR_T] / 2
    b2 = alt["p1_lowered"] <= cur["p1_lowered"]
    b3 = alt["answered"] >= MIN_ANSWERED_SHARE * alt["items"]
    return b1, b2, b3, b4


def bar4(items, figs, d):
    """rulings_bar, or not-needed when bars 1 to 3 already decide the result:
    no ruling could then change it, so none is asked for."""
    if not all(bars(figs["current"], figs["alternative"])[:3]):
        return "not-needed", len(sample(items, figs)), None, None
    return rulings_bar(items, figs, d)


def overall(b):
    if not all(b[:3]) or b[3] == "fail":
        return "fail"
    return "pass" if b[3] == "pass" else "pending"


def drift(items, cur):
    """Items whose current-wording choice equals the 2026-10-07 choice, over
    all items (an item unanswered in either run counts as changed)."""
    same = sum(1 for i in items if i["ref"] in cur["choices"] and cur["choices"][i["ref"]] == i.get("model_choice"))
    return same, len(items)


def lines(items, figs, d):
    out = []
    for form in FORMS:
        f = figs[form]
        for k in ("items", "answered", "no_answer", "refused", "truncated", "retried", "agree",
                  "p1_lowered"):
            out.append("%s.%s=%d" % (form, k, f[k]))
        out.append("%s.p1_lowered.%s=%d" % (form, BAR_T, f["p1_lowered_bar"]))
        for t in THRESHOLDS:
            out.append("%s.raises.%s=%d" % (form, t, f["raises"][t]))
        for k in sorted(f["pairs"]):
            out.append("%s.raises.%s.%s=%d" % (form, BAR_T, k, f["pairs"][k]))
        for a in RANK:
            out.append("%s.matrix.%s=%s" % (form, a, ",".join(str(f["matrix"][a][b]) for b in RANK)))
        for k in sorted(f["no_answer_reasons"]):
            out.append("%s.no_answer.%s=%d" % (form, k, f["no_answer_reasons"][k]))
        out.append("%s.sent_sha256=%s" % (form, f["sent_sha256"]))
        out.append("%s.models=%s" % (form, ",".join(f["models"])))
        if f["ts"]:
            out.append("%s.records=%s..%s" % (form, f["ts"][0], f["ts"][-1]))
    state, n, cm, am = bar4(items, figs, d)
    b = bars(figs["current"], figs["alternative"], state)
    out += ["bar1.raises_at_most_half=%s" % ("pass" if b[0] else "fail"),
            "bar2.p1_lowered_no_more=%s" % ("pass" if b[1] else "fail"),
            "bar3.answered_at_least_97.5pct=%s" % ("pass" if b[2] else "fail"),
            "bar4.sample=%d" % n]
    if cm is not None:
        out += ["bar4.current_matches=%d" % cm, "bar4.alternative_matches=%d" % am]
    out += ["bar4.rulings=%s" % state, "bars=%s" % overall(b)]
    same, n = drift(items, figs["current"])
    if n:
        out.append("drift.current_same_as_2026-10-07=%d/%d" % (same, n))
        out.append("drift=%s" % ("yes" if same < 0.9 * n else "no"))
    return out


def pct(n, d):
    return "%d (%.1f%%)" % (n, 100.0 * n / d) if d else str(n)


def markdown(items, figs, d):
    cur, alt = figs["current"], figs["alternative"]
    n = len(items)
    state, ns, cm, am = bar4(items, figs, d)
    b = bars(cur, alt, state)
    res = overall(b)
    same, both = drift(items, cur)
    yn = lambda x: "met" if x else "not met"
    rows = [
        "# address.category wording comparison (TypeSafe %s)" % MODEL,
        "",
        "Generated by `summarize.py --write` from the records in this directory. Higher agreement is closer to the "
        "reviewer's priority; fewer raises means fewer items handled at a higher priority than the reviewer gave. "
        "Whether a raise is right is not known: the labels are the reviewing sessions' priorities.",
        "",
        "| | Current wording | Alternative wording |",
        "|---|---|---|",
        "| Items | %d | %d |" % (cur["items"], alt["items"]),
        "| Answered | %s | %s |" % (pct(cur["answered"], n), pct(alt["answered"], n)),
        "| No answer (refused included) | %d | %d |" % (cur["no_answer"], alt["no_answer"]),
        "| Refused (text names a priority) | %d | %d |" % (cur["refused"], alt["refused"]),
        "| Truncated | %d | %d |" % (cur["truncated"], alt["truncated"]),
        "| Retried (several records for one item; the last one counts) | %d | %d |" % (cur["retried"], alt["retried"]),
        "| Agrees with the label | %s | %s |" % (pct(cur["agree"], n), pct(alt["agree"], n)),
        "| Raised above the label at %s | %s | %s |" % (BAR_T, pct(cur["raises"][BAR_T], n), pct(alt["raises"][BAR_T], n)),
        "| Labelled P1 placed lower, any confidence | %d | %d |" % (cur["p1_lowered"], alt["p1_lowered"]),
        "| Labelled P1 placed lower at %s | %d | %d |" % (BAR_T, cur["p1_lowered_bar"], alt["p1_lowered_bar"]),
        "",
        "**Raises by threshold** (all %d items; shipped rule: the answer's confidence at or above the threshold "
        "and its choice above the label):" % n,
        "",
        "| Threshold | Current wording | Alternative wording |",
        "|---|---|---|",
    ]
    rows += ["| %s | %s | %s |" % (t, pct(cur["raises"][t], n), pct(alt["raises"][t], n)) for t in THRESHOLDS]
    for form, f in (("Current wording", cur), ("Alternative wording", alt)):
        rows += ["", "**%s: choice against the label** (rows: label; columns: the model's choice):" % form, "",
                 "| Label | P1 | P2 | P3 | Question |", "|---|---|---|---|---|"]
        rows += ["| %s | %s |" % (a, " | ".join(str(f["matrix"][a][x]) for x in RANK)) for a in RANK]
        if f["pairs"]:
            rows += ["", "Raises at %s by label and choice: %s." % (
                BAR_T, ", ".join("%s %d" % (k.replace(">", " to "), v) for k, v in sorted(f["pairs"].items())))]
    rows += [
        "",
        "**Bars** (set before any result was read):",
        "",
        "1. Alternative raises at %s at most half the current wording's: %d against %d, %s." % (
            BAR_T, alt["raises"][BAR_T], cur["raises"][BAR_T], yn(b[0])),
        "2. Alternative places no more labelled P1 items lower: %d against %d, %s." % (
            alt["p1_lowered"], cur["p1_lowered"], yn(b[1])),
        "3. Alternative answers at least %d of %d items (97.5%%): %d of %d, %s." % (
            math.ceil(MIN_ANSWERED_SHARE * alt["items"] - 1e-9), alt["items"], alt["answered"], alt["items"], yn(b[2])),
        "4. On %d items the two wordings answered differently, ruled blind by the user, the alternative matches the "
        "ruling at least as often: %s." % (ns, "%d against %d, %s" % (am, cm, yn(state == "pass")) if cm is not None
                                          else {"not-needed": "not needed, since bars 1 to 3 decide the result",
                                                "pending": "rulings pending"}[state]),
        "",
        "Result: %s." % {"pass": "all four bars are met, so the alternative wording replaces the current one",
                         "fail": "not every bar is met, so the current wording stays",
                         "pending": "bars 1 to 3 are met and bar 4 waits for rulings"}[res],
    ]
    if both:
        rows += ["", "**Drift.** The current wording, run again, made the same choice as on 2026-10-07 for %d of %d "
                 "items (%.1f%%; below 90%% would be reported as drift)." % (same, both, 100.0 * same / both)]
    for form, f in (("current", cur), ("alternative", alt)):
        r = f["run"]
        rows += ["", "`%s`: question sha256 `%s`, model %s, records %s to %s." % (
            form, f["sent_sha256"], ", ".join(f["models"]) or r.get("model", "?"),
            f["ts"][0] if f["ts"] else "?", f["ts"][-1] if f["ts"] else "?")]
    return "\n".join(rows) + "\n"


def check(which, items, figs, args):
    problems = []
    if which == "ac1":
        for form in FORMS:
            f = figs[form]
            want = wording_hash(os.path.join(HERE, form + ".yaml"))
            if f["sent_sha256"] != want:
                problems.append("%s run sent a wording other than %s.yaml (sha256 %s, want %s)"
                                % (form, form, f["sent_sha256"], want))
            # Exactly one row per item: as many rows as items, every item
            # among them, and none for another ref.
            if f["meta_rows"] != len(items) or f["meta_unmatched"] or f["meta_items"] != len(items):
                problems.append("%s: meta-%s.jsonl has %d rows for %d of the %d items (%d for refs not among them), "
                                "want one row per item" % (form, form, f["meta_rows"], f["meta_items"], len(items),
                                                           f["meta_unmatched"]))
            missing = sum(v for k, v in f["no_answer_reasons"].items() if k.split(":")[0] == "no-record")
            if missing:
                problems.append("%s: %d items have no record" % (form, missing))
            if f["unknown_refs"]:
                problems.append("%s: records for refs not among the items: %s" % (form, ", ".join(f["unknown_refs"][:5])))
            if any(m != MODEL for m in f["models"]):
                problems.append("%s: answers from models %s, want %s" % (form, f["models"], MODEL))
            if f["state_mismatch"]:
                problems.append("%s: %d records whose state differs from the rebuilt one" % (form, f["state_mismatch"]))
    elif which == "ac2":
        path = os.path.join(args.dir, "summary.md")
        if not os.path.isfile(path):
            problems.append("no summary.md in " + args.dir)
        elif open(path, encoding="utf-8").read() != markdown(items, figs, args.dir):
            problems.append("summary.md is not what the records give; run summarize.py --write")
    elif which == "ac3":
        res = overall(bars(figs["current"], figs["alternative"], bar4(items, figs, args.dir)[0]))
        chosen = "alternative" if res == "pass" else "current"
        shipped = wording_hash(args.shipped)
        if res == "pending":
            problems.append("bar 4 is pending: rule every item --sample prints, in rulings.jsonl")
        elif shipped != wording_hash(os.path.join(HERE, chosen + ".yaml")):
            problems.append("the bars %s, so the %s wording should be shipped, and %s holds another"
                            % (res, chosen, args.shipped))
    for p in problems:
        print("FAIL " + p)
    print("%s=%s" % (which.upper(), "FAIL" if problems else "OK"))
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dir", default=HERE)
    ap.add_argument("--items", default=os.path.join(os.path.dirname(HERE), "results-2026-10-07-address-s1",
                                                    "address-category.jsonl"))
    ap.add_argument("--shipped", default=os.path.join(PLUGIN, "system-one", "questions.yaml"))
    ap.add_argument("--check", choices=("ac1", "ac2", "ac3"))
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--sample", action="store_true", help="print the items to rule on, without any priority")
    ap.add_argument("--hash", metavar="YAML", help="print the sha256 of the address.category questions in a "
                    "questions file, as the client loads them, and exit")
    args = ap.parse_args()
    if args.hash:
        print(wording_hash(args.hash))
        return 0
    items = read_items(args.items)
    figs = {form: form_figures(items, form, args.dir) for form in FORMS}
    if args.check:
        return check(args.check, items, figs, args)
    if args.sample:
        for k, i in enumerate(sample(items, figs), 1):
            print("ITEM %d  %s" % (k, i["ref"]))
            if i.get("path"):
                print("file: %s%s" % (i["path"], ":" + str(i["line"]) if i.get("line") else ""))
            print(i["text"])
            print()
        return 0
    out = lines(items, figs, args.dir)
    print("\n".join(out))
    if args.write:
        with open(os.path.join(args.dir, "summary.md"), "w", encoding="utf-8") as f:
            f.write(markdown(items, figs, args.dir))
        data = {k: v for k, v in (x.split("=", 1) for x in out)}
        with open(os.path.join(args.dir, "summary.json"), "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1, sort_keys=True)
            f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
