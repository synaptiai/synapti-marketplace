"""The test-discrimination measurement: does a System One answer to "would
this test fail if the module were the risk row's plausible wrong version?"
agree with what the correctness eval observed? The method, the strata and
the adoption bar are in references/correctness-eval.md, section "System One:
does a test catch the wrong version". Reached through bin/flow-s1-eval.sh
(or _flow_eval.py s1-pairs | s1-replay | s1-score).

s1-pairs --evals-dir E --dest D [--set dev|eval] [--author] [--out R]...
         [--rescore] [--seed N] [--timeout S]
    One pair per (test, trap of the same case). --author adds the hidden
    suites (labels from hidden/traps.json); each --out adds the agent-written
    oracle tests of every run under R/runs (labels from the run's
    own-test-traps.json; the oracle test ids, which that file does not keep,
    are recovered by re-running the run's suite on its own module and on the
    reference). A run whose stored failing or unobserved list is shorter than
    its count (the 50-entry cap) is refused, exit 2, unless --rescore, which
    re-runs every variant. A run whose re-run oracle set differs from the
    stored one, or whose fail pairs (with those lost to a state error) do not
    sum to its stored failing counts, is left out and listed. Writes D/pairs.jsonl, D/export.json
    and D/states/<ablation>/<id>.json for three ablations: real,
    name-stripped (the test function renamed test_x) and shuffled (the risk
    row of a trap from another case, drawn with the seed). The risk row is
    the trap name and column 2 of expected.md; columns 3 and 4 and the trap
    description are never read into a state, and every state is checked for
    them before it is written. Author states have their comments removed.
    No model call.

s1-replay --pairs P --records R --provider-settings F [--ablation A]
          [--records-name NAME] [--workers N] [--scratch DIR] [--limit N]
          [--sample N] [--seed N] [--only-set dev|eval] [--backoff S]
    Copies the plugin to DIR/plugin (outside any repository; default a new
    temporary directory, removed when the replay ends), installs evals/s1-discrimination/questions.yaml as
    its system-one/questions.yaml, and runs, from the empty DIR/work, once per
    labelled pair: flow-s1.sh ask --site verify.discrimination --state-format
    json --state-file <the pair's state for A> --ref <pair ref> --current
    <label>, with FLOW_USER_SETTINGS=F and FLOW_STATE_DIR=R/<NAME> (NAME
    defaults to A). The settings file chooses the provider and must set
    systemOne.uses."verify.discrimination" to shadow. A pair already answered
    in R/<NAME> is not sent again. HTTP 429 is retried once after S seconds
    (default 5). Exit 3, after one call, when that call wrote no record
    (settings refused, provider none): nothing else is sent. Exit 4 when a
    sent pair has no record afterwards (flow-s1.sh keeps the answer when it
    cannot take the records lock); running the replay again sends those. At
    most 8 workers. --sample N sends N labelled pairs drawn with the seed (the
    determinism check uses --sample 30 --records-name repeat).

s1-score --pairs P --records R --dest D [--set dev|eval]
         [--choose-threshold T | --threshold-file T] [--seed N] [--limit N]
         [--permutations N]
    Joins the records under R/<ablation>/system-one.jsonl to the pairs by
    ref, runs the measurement checks, and writes D/summary.json and
    D/summary.md. Exit 1 (verdict harness-error) when records and pairs do
    not match one to one, when the answers name more than one provider and
    model, or when they name another one than the threshold file.
    --choose-threshold (dev set, with agent and author pairs) writes the
    lowest t at which the bar's false-alarm clause holds on agent and author
    pairs separately, with the commit and the time; --threshold-file
    (evaluation set) applies it.
"""

# The guard below must stay verbatim (tests/syspath-guard.test.sh matches it)
# and must run before the other imports, so ruff's rules on one import per
# line and imports at the top do not apply to this file.
# ruff: noqa: E401, E402
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import ast
import collections
import concurrent.futures
import hashlib
import json
import math
import random
import re
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone

# The sibling modules are found next to this file, never through the working
# directory (PYTHONSAFEPATH keeps the script's own directory off sys.path).
_BIN = os.path.dirname(os.path.abspath(__file__))
if _BIN not in sys.path:
    sys.path.insert(0, _BIN)
import _flow_test_state as fts
import _flow_eval as fe

SITE = "verify.discrimination"
QUESTION = "test_catches_wrong"
ABLATIONS = ("real", "name-stripped", "shuffled")
RENAMED = "test_x"
DEFAULT_SEED = 263
Z95 = 1.959963984540054
SWEEP = tuple(round(0.5 + 0.05 * i, 2) for i in range(10))
FALSE_ALARM_CEILING = 0.05
HN_RECALL_FLOOR = 0.30
COVERAGE_FLOOR = 0.95
DEGENERATE_BIN_SHARE = 0.80
PLACEBO_TOLERANCE = 0.05
PERMUTATION_TOLERANCE = 0.02
DETERMINISM_TOLERANCE = 0.02
MIN_FAIL_PAIRS_PER_CASE = 20
REF_UNSAFE = re.compile(r"[^A-Za-z0-9._:/#@+-]")


def die(msg, code=2):
    sys.stderr.write("flow-s1-eval: %s\n" % msg)
    sys.exit(code)


def parse_args(args, values, flags=(), repeat=()):
    opts = {k: [] for k in repeat}
    i = 0
    while i < len(args):
        a = args[i]
        if a in values or a in repeat:
            if i + 1 >= len(args):
                die("%s needs a value" % a)
            if a in repeat:
                opts[a].append(args[i + 1])
            else:
                opts[a] = args[i + 1]
            i += 2
        elif a in flags:
            opts[a] = True
            i += 1
        else:
            die("unknown argument: %s" % a)
    return opts


def int_opt(opts, key, default, low=None, high=None):
    raw = opts.get(key)
    if raw is None:
        return default
    try:
        v = int(raw)
    except ValueError:
        die("%s must be a whole number" % key)
    if (low is not None and v < low) or (high is not None and v > high):
        die("%s must be from %s to %s" % (key, low, high))
    return v


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ====================================================================== pairs

def expected_rows(case_dir):
    """{trap: column 2} from the trap table in expected.md. Columns 3 and 4
    (the masking input and the discriminating tests) are not returned."""
    rows = {}
    with open(os.path.join(case_dir, "expected.md"), encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^\|\s*`([A-Za-z0-9_]+)`\s*\|([^|]*)\|", line)
            if m:
                rows[m.group(1)] = m.group(2).strip()
    return rows


def load_cases(evals_dir):
    cases = {}
    for name in sorted(os.listdir(evals_dir)):
        d = os.path.join(evals_dir, name)
        if not (os.path.isfile(os.path.join(d, "hidden", "traps.json"))
                and os.path.isfile(os.path.join(d, "expected.md"))):
            continue
        traps = fe.load_traps(d)
        rows = expected_rows(d)
        missing = sorted(set(traps["traps"]) - set(rows))
        if missing:
            die("%s/expected.md has no row for trap(s) %s" % (name, ", ".join(missing)))
        with open(os.path.join(d, "scaffold", "ISSUE.md"), encoding="utf-8") as fh:
            spec = fh.read()
        cases[name] = {"dir": d, "traps": traps["traps"], "module": traps["module"], "rows": rows, "spec": spec}
    if not cases:
        die("no cases under %s" % evals_dir)
    return cases


def area_of(trap):
    return trap.replace("_", " ")


def safe_part(text):
    return REF_UNSAFE.sub("-", str(text)) or "x"


def hidden_tests(case_dir):
    """[(Class.method, method)] of the hidden suite, in file order."""
    path = os.path.join(case_dir, "hidden", "test_hidden.py")
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=path)
    out = []
    for top in tree.body:
        if isinstance(top, ast.ClassDef):
            for item in top.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and item.name.startswith("test"):
                    out.append(("%s.%s" % (top.name, item.name), item.name))
        elif isinstance(top, (ast.FunctionDef, ast.AsyncFunctionDef)) and top.name.startswith("test"):
            out.append((top.name, top.name))
    return out


class Leak(Exception):
    pass


def check_leak(state, case, stratum, own_name):
    """Raise Leak when the state carries what decides its label: a trap
    description, a discriminating hidden-test name other than the test's
    own (in the spec or the risk row anywhere; in the source for author
    tests), or, in an author test's source, a trap name or the word trap."""
    text = json.dumps(state, ensure_ascii=False)
    spec_risk = json.dumps({"spec": state["spec"], "risk": state["risk"]}, ensure_ascii=False)
    src = state["test"]["source"]
    for name, t in case["traps"].items():
        if t.get("description") and t["description"] in text:
            raise Leak("the description of trap %s" % name)
        for dt in t.get("discriminating_tests") or ():
            if dt == own_name:
                continue
            pat = r"\b%s\b" % re.escape(dt)
            if re.search(pat, spec_risk) or (stratum == "author" and re.search(pat, src)):
                raise Leak("the discriminating test name %s" % dt)
        if stratum == "author":
            for spelling in (name, name.replace("_", "-"), name.replace("_", " ")):
                if spelling in src:
                    raise Leak("the trap name %s in the test source" % spelling)
    if stratum == "author" and re.search(r"trap", src, re.I):
        raise Leak("the word trap in the test source")


def placebo_row(cases, case_name, seed, ref):
    """(case, trap, area, wrong version) of a trap from another case, drawn
    from a generator seeded by the seed and the ref."""
    others = [c for c in sorted(cases) if c != case_name]
    if not others:
        return None
    rng = random.Random("%s:%s" % (seed, ref))
    other = rng.choice(others)
    trap = rng.choice(sorted(cases[other]["traps"]))
    return other, trap, area_of(trap), cases[other]["rows"][trap]


def write_state(dest, ablation, ref, state):
    data = fts.dump_state(state)
    rel = os.path.join("states", ablation, sha256_bytes(ref.encode())[:20] + ".json")
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)
    return {"path": rel, "sha256": sha256_bytes(data)}


def pair_states(dest, cases, case_name, stratum, ref, test_file, test_id, own_name, trap, spec, seed):
    """{ablation: {path, sha256, ...}} and the builder's metadata, or raise
    StateError / Leak."""
    case = cases[case_name]
    strip = stratum == "author"
    area, wrong = area_of(trap), case["rows"][trap]
    state, meta = fts.build_state(test_file, area, wrong, spec, test_id=test_id, strip=strip)
    check_leak(state, case, stratum, own_name)
    states = {"real": write_state(dest, "real", ref, state)}
    renamed, _ = fts.build_state(test_file, area, wrong, spec, test_id=test_id, strip=strip, rename=RENAMED)
    check_leak(renamed, case, stratum, own_name)
    states["name-stripped"] = write_state(dest, "name-stripped", ref, renamed)
    row = placebo_row(cases, case_name, seed, ref)
    if row is not None:
        p_case, p_trap, p_area, p_wrong = row
        shuffled = dict(state, risk={"area": p_area, "plausible_wrong_version": p_wrong})
        check_leak(shuffled, case, stratum, own_name)
        states["shuffled"] = dict(write_state(dest, "shuffled", ref, shuffled), placebo_case=p_case, placebo_trap=p_trap)
    return states, meta


def author_pairs(dest, cases, seed, set_name, errors):
    pairs = []
    for case_name, case in cases.items():
        tests = hidden_tests(case["dir"])
        test_file = os.path.join(case["dir"], "hidden", "test_hidden.py")
        for test_id, method in tests:
            fails = {t for t, v in case["traps"].items() if method in (v.get("discriminating_tests") or ())}
            for trap in sorted(case["traps"]):
                label = "fail" if trap in fails else "pass"
                ref = "eval:author/%s/hidden/%s/%s" % (safe_part(case_name), safe_part(trap),
                                                      sha256_bytes(test_id.encode())[:12])
                try:
                    states, meta = pair_states(dest, cases, case_name, "author", ref, test_file, test_id,
                                               method, trap, case["spec"], seed)
                except Leak as e:
                    die("leak in the state for %s %s / %s: %s" % (case_name, test_id, trap, e))
                except fts.StateError as e:
                    errors.append({"ref": ref, "reason": str(e)})
                    continue
                pairs.append({"ref": ref, "set": set_name, "stratum": "author", "case": case_name,
                              "run": "hidden", "model": None, "arm": None, "trap": trap, "test_id": test_id,
                              "label": label, "hn_behavioral": label == "pass" and bool(fails - {trap}),
                              "comments_stripped": True, "helpers_missing": meta["helpers_missing"],
                              "states": states})
    return pairs


def rerun_suite(case_dir, project, timeout, variants):
    """Re-run the agent's suite as own_test_traps does: on its own module and
    on the reference, and with variants, on each trap variant. Returns
    (oracle ids, {trap: (failing, unobserved)} or None, reason or None)."""
    traps = fe.load_traps(case_dir)
    module = traps["module"]
    scratch = tempfile.mkdtemp(prefix="flow-s1-pairs.")
    try:
        copy = os.path.join(scratch, "project")
        fe.snapshot_project(project, copy)
        own, _ = fe.run_own_suite(copy, timeout)
        if own["incomplete"]:
            return None, None, "the own suite did not finish on its own module (%s)" % own["reason"]
        passing_own = [t for t in own["order"] if own["tests"][t] == "ok"]
        module_path = os.path.join(copy, module + ".py")
        reference = os.path.join(case_dir, "hidden", "reference_impl.py")
        shutil.copy(reference, os.path.join(copy, "reference_impl.py"))
        shutil.copy(reference, module_path)
        ref_run, _ = fe.run_own_suite(copy, timeout)
        if ref_run["incomplete"]:
            return None, None, "the own suite did not finish on the reference (%s)" % ref_run["reason"]
        oracle = [t for t in passing_own if ref_run["tests"].get(t) == "ok"]
        per_trap = None
        if variants:
            per_trap = {}
            for name in sorted(traps["traps"]):
                shutil.copy(os.path.join(case_dir, traps["traps"][name]["variant"]), module_path)
                parsed, _ = fe.run_own_suite(copy, timeout)
                per_trap[name] = ([t for t in oracle if parsed["tests"].get(t) in ("FAIL", "ERROR")],
                                  [t for t in oracle if parsed["tests"].get(t, "missing") == "missing"])
        return oracle, per_trap, None
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def test_file_for(project, test_id):
    """(path of the file holding test_id under project, id inside it)."""
    parts = test_id.split(".")
    for i in range(len(parts) - 1, 0, -1):
        path = os.path.join(project, *parts[:i]) + ".py"
        if os.path.isfile(path):
            return path, ".".join(parts[i:])
    return None, None


def agent_pairs(dest, cases, out_dir, seed, set_name, rescore, timeout, excluded, runs_info, errors, unfinished):
    pairs = []
    root = os.path.join(out_dir, "runs")
    problems = []
    for run_dir, layout in fe.iter_run_dirs(out_dir, problems):
        rel = os.path.relpath(run_dir, root).split(os.sep)
        if layout == "model":
            model, arm, case_name, _n = rel
        elif layout == "legacy":
            model, (arm, case_name, _n) = None, rel
        else:
            continue
        run_key = "/".join(safe_part(x) for x in [os.path.basename(os.path.normpath(out_dir))] + rel)
        if case_name not in cases:
            excluded.append({"run": run_key, "reason": "case %s is not under the evals directory" % case_name})
            continue
        case = cases[case_name]
        project = os.path.join(run_dir, "project")
        own_path = os.path.join(run_dir, "own-test-traps.json")
        if not os.path.isdir(project) or not os.path.isfile(own_path):
            excluded.append({"run": run_key, "reason": "no project/ snapshot or no own-test-traps.json"})
            continue
        with open(own_path, encoding="utf-8") as fh:
            own = json.load(fh)
        if own.get("catch_rate") is None:
            excluded.append({"run": run_key, "reason": "own tests were not scored: %s" % own.get("reason")})
            continue
        cut = [t for t, v in sorted(own["per_trap"].items())
               if v["failing_count"] > len(v["failing_own_tests"]) or v["unobserved_count"] > len(v["unobserved_oracle_tests"])]
        if cut and not rescore:
            die("%s: failing_count or unobserved_count is above the stored list for %s (the list is cut at 50); "
                "pass --rescore to re-run its variants" % (run_key, ", ".join(cut)))
        oracle, per_trap, reason = rerun_suite(case["dir"], project, timeout, variants=rescore)
        if reason:
            excluded.append({"run": run_key, "reason": reason})
            continue
        if rescore:
            labels = {t: (set(f), set(u)) for t, (f, u) in per_trap.items()}
            stored_fail = sum(len(f) for f, _ in per_trap.values())
        else:
            labels = {t: (set(v["failing_own_tests"]), set(v["unobserved_oracle_tests"])) for t, v in own["per_trap"].items()}
            stored_fail = sum(v["failing_count"] for v in own["per_trap"].values())
            listed = set().union(*[f | u for f, u in labels.values()]) if labels else set()
            if len(oracle) != own.get("own_passing_tests") or not listed <= set(oracle):
                excluded.append({"run": run_key, "reason": "the re-run oracle set differs from own-test-traps.json "
                                 "(%d tests re-run, %s stored)" % (len(oracle), own.get("own_passing_tests"))})
                continue
        spec_path = os.path.join(project, "ISSUE.md")
        if os.path.isfile(spec_path):
            with open(spec_path, encoding="utf-8") as fh:
                spec = fh.read()
        else:
            spec = case["spec"]
        info = {"run": run_key, "case": case_name, "model": model, "arm": arm, "oracle_tests": len(oracle),
                "fail_stored": stored_fail, "fail": 0, "pass": 0, "unobserved": 0, "fail_lost": 0}
        run_pairs = []
        for test_id in oracle:
            test_file, inner = test_file_for(project, test_id)
            fails = {t for t, (f, _) in labels.items() if test_id in f}
            for trap in sorted(case["traps"]):
                f, u = labels.get(trap, (set(), set()))
                label = "fail" if test_id in f else ("unobserved" if test_id in u else "pass")
                ref = "eval:agent/%s/%s/%s/%s" % (safe_part(case_name), run_key, safe_part(trap),
                                                  sha256_bytes(test_id.encode())[:12])
                if test_file is None:
                    errors.append({"ref": ref, "reason": "no file for test %s" % test_id})
                    info["fail_lost"] += label == "fail"
                    continue
                try:
                    states, meta = pair_states(dest, cases, case_name, "agent", ref, test_file, inner,
                                               test_id.rsplit(".", 1)[-1], trap, spec, seed)
                except Leak as e:
                    die("leak in the state for %s %s / %s: %s" % (run_key, test_id, trap, e))
                except fts.StateError as e:
                    errors.append({"ref": ref, "reason": str(e)})
                    info["fail_lost"] += label == "fail"
                    continue
                info[label] += 1
                run_pairs.append({"ref": ref, "set": set_name, "stratum": "agent", "case": case_name,
                                  "run": run_key, "model": model, "arm": arm, "trap": trap, "test_id": test_id,
                                  "label": label, "hn_behavioral": label == "pass" and bool(fails - {trap}),
                                  "comments_stripped": False, "helpers_missing": meta["helpers_missing"],
                                  "states": states})
        # The fail pairs of a run, with those lost to a state error, must
        # equal the stored failing counts; otherwise the labels were not read
        # as the correctness eval recorded them.
        if info["fail"] + info["fail_lost"] != stored_fail:
            excluded.append({"run": run_key, "reason": "%d fail pairs (%d more lost to state errors) but the stored "
                             "failing counts sum to %d" % (info["fail"], info["fail_lost"], stored_fail)})
            for p in run_pairs:
                for st in p["states"].values():
                    os.remove(os.path.join(dest, st["path"]))
            continue
        pairs += run_pairs
        runs_info.append(info)
    # Runs that started and wrote no result.json, and directories the walk
    # could not read: no pairs, but listed.
    unfinished += [os.path.relpath(p, root) if p.startswith(root) else p for p in problems]
    return pairs


def cmd_pairs(args):
    opts = parse_args(args, ("--evals-dir", "--dest", "--set", "--seed", "--timeout"),
                      flags=("--author", "--rescore"), repeat=("--out",))
    if not opts.get("--evals-dir") or not opts.get("--dest"):
        die("s1-pairs --evals-dir E --dest D [--set dev|eval] [--author] [--out R]... [--rescore] [--seed N]")
    set_name = opts.get("--set", "dev")
    if set_name not in ("dev", "eval"):
        die("--set must be dev or eval")
    if not opts.get("--author") and not opts["--out"]:
        die("nothing to export: pass --author, --out R, or both")
    seed = int_opt(opts, "--seed", DEFAULT_SEED)
    timeout = int_opt(opts, "--timeout", 120, 1)
    dest = os.path.abspath(opts["--dest"])
    cases = load_cases(opts["--evals-dir"])
    if os.path.isdir(os.path.join(dest, "states")):
        shutil.rmtree(os.path.join(dest, "states"))
    os.makedirs(dest, exist_ok=True)
    errors, excluded, runs_info, unfinished = [], [], [], []
    pairs = author_pairs(dest, cases, seed, set_name, errors) if opts.get("--author") else []
    for out_dir in opts["--out"]:
        pairs += agent_pairs(dest, cases, out_dir, seed, set_name, bool(opts.get("--rescore")), timeout,
                             excluded, runs_info, errors, unfinished)
    refs = [p["ref"] for p in pairs]
    if len(set(refs)) != len(refs):
        die("two pairs share a ref; refs must be unique")
    bad = [r for r in refs if len(r) > 200]
    if bad:
        die("ref longer than 200 characters: %s" % bad[0])
    pairs.sort(key=lambda p: (p["stratum"], p["case"], p["run"], p["test_id"], p["trap"]))
    with open(os.path.join(dest, "pairs.jsonl"), "w", encoding="utf-8") as fh:
        for p in pairs:
            fh.write(json.dumps(p, sort_keys=True) + "\n")
    labels = collections.Counter(p["label"] for p in pairs)
    export = {
        "set": set_name, "seed": seed,
        "pairs": len(pairs),
        "labels": {k: labels.get(k, 0) for k in ("fail", "pass", "unobserved")},
        "strata": {s: {k: sum(1 for p in pairs if p["stratum"] == s and p["label"] == k) for k in ("fail", "pass", "unobserved")}
                   for s in ("author", "agent")},
        "hn_behavioral": sum(1 for p in pairs if p["hn_behavioral"]),
        "helpers_missing": sum(1 for p in pairs if p["helpers_missing"]),
        "runs": runs_info, "excluded_runs": excluded, "unfinished_runs": unfinished, "state_errors": errors,
        "shuffled": all("shuffled" in p["states"] for p in pairs) if pairs else False,
    }
    write_json(os.path.join(dest, "export.json"), export)
    fail_lost = sum(r["fail_lost"] for r in runs_info)
    if fail_lost:
        sys.stderr.write("flow-s1-eval: %d fail pairs were lost to state errors (export.json state_errors)\n" % fail_lost)
    print(json.dumps({"pairs": len(pairs), "labels": export["labels"], "excluded_runs": len(excluded),
                      "state_errors": len(errors), "fail_pairs_lost": fail_lost}, sort_keys=True))


# ===================================================================== replay

def load_pairs(path):
    pairs = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                pairs.append(json.loads(line))
    return pairs


def read_records(path):
    out = []
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except ValueError:
                out.append({"_unreadable": line[:80]})
    return out


def inside_repository(path):
    try:
        r = subprocess.run(["git", "-C", path, "rev-parse", "--is-inside-work-tree"],
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0 and r.stdout.strip() == "true"


def plugin_copy(scratch):
    """Copy this plugin to scratch/plugin with the eval question file as its
    system-one/questions.yaml. Run output (evals/results*) and bytecode are
    left out."""
    src = os.path.dirname(_BIN)
    dst = os.path.join(scratch, "plugin")
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    evals = os.path.join(src, "evals")

    def ignore(d, names):
        drop = [n for n in names if n == "__pycache__" or n.endswith(".pyc") or n == ".git"]
        if os.path.realpath(d) == os.path.realpath(evals):
            drop += [n for n in names if n.startswith("results")]
        return drop
    shutil.copytree(src, dst, ignore=ignore, symlinks=True)
    shutil.copy(os.path.join(src, "evals", "s1-discrimination", "questions.yaml"),
                os.path.join(dst, "system-one", "questions.yaml"))
    return dst


def cmd_replay(args):
    opts = parse_args(args, ("--pairs", "--records", "--provider-settings", "--ablation", "--records-name",
                             "--workers", "--scratch", "--limit", "--sample", "--seed", "--only-set", "--backoff"))
    for k in ("--pairs", "--records", "--provider-settings"):
        if not opts.get(k):
            die("s1-replay --pairs P --records R --provider-settings F [--ablation A] [--workers N] ...")
    ablation = opts.get("--ablation", "real")
    if ablation not in ABLATIONS:
        die("--ablation must be one of %s" % ", ".join(ABLATIONS))
    name = opts.get("--records-name", ablation)
    if not re.fullmatch(r"[a-z][a-z0-9-]*", name):
        die("--records-name must be lowercase letters, digits and dashes")
    workers = int_opt(opts, "--workers", 1, 1, 8)
    limit = int_opt(opts, "--limit", None, 1)
    sample = int_opt(opts, "--sample", None, 1)
    seed = int_opt(opts, "--seed", DEFAULT_SEED)
    try:
        backoff = float(opts.get("--backoff", "5"))
    except ValueError:
        die("--backoff must be a number of seconds")
    settings = os.path.abspath(opts["--provider-settings"])
    if not os.path.isfile(settings):
        die("--provider-settings is not a file: %s" % settings)
    pairs_path = os.path.abspath(opts["--pairs"])
    base = os.path.dirname(pairs_path)
    pairs = [p for p in load_pairs(pairs_path) if p["label"] != "unobserved"]
    if opts.get("--only-set"):
        pairs = [p for p in pairs if p["set"] == opts["--only-set"]]
    if sample is not None:
        rng = random.Random(seed)
        pairs = sorted(rng.sample(pairs, min(sample, len(pairs))), key=lambda p: p["ref"])
    if limit is not None:
        pairs = pairs[:limit]
    missing_state = [p["ref"] for p in pairs if ablation not in p["states"]]
    pairs = [p for p in pairs if ablation in p["states"]]

    if opts.get("--scratch"):
        scratch, made = os.path.abspath(opts["--scratch"]), False
        os.makedirs(scratch, exist_ok=True)
    else:
        scratch, made = os.path.realpath(tempfile.mkdtemp(prefix="flow-s1-replay.")), True
    try:
        return replay(scratch, opts, ablation, name, workers, backoff, settings, base, pairs, missing_state)
    finally:
        # A directory this run made holds only the plugin copy and the empty
        # working directory; one passed with --scratch is the caller's.
        if made:
            shutil.rmtree(scratch, ignore_errors=True)


def replay(scratch, opts, ablation, name, workers, backoff, settings, base, pairs, missing_state):
    if inside_repository(scratch):
        die("the scratch directory %s is inside a git repository; flow-s1.sh refuses to read the user's "
            "settings from a plugin copy there" % scratch)
    plugin = plugin_copy(scratch)
    work = os.path.join(scratch, "work")
    os.makedirs(work, exist_ok=True)
    rec_dir = os.path.join(os.path.abspath(opts["--records"]), name)
    os.makedirs(rec_dir, exist_ok=True)
    rec_file = os.path.join(rec_dir, "system-one.jsonl")
    answered = {r.get("ref") for r in read_records(rec_file) if r.get("answer") is not None}
    todo = [p for p in pairs if p["ref"] not in answered]

    env = dict(os.environ)
    for k in ("CLAUDE_PROJECT_DIR", "FLOW_USER_PYTHONPATH"):
        env.pop(k, None)
    env.update({"FLOW_USER_SETTINGS": settings, "FLOW_STATE_DIR": rec_dir, "CLAUDE_PLUGIN_ROOT": plugin})
    try:
        with open(settings, encoding="utf-8") as fh:
            s1 = (json.load(fh) or {}).get("systemOne") or {}
    except (OSError, ValueError):
        s1 = {}
    sys.stderr.write("flow-s1-eval: replay %d pairs (%s, records %s) to provider %s, model %s; %d already answered\n"
                     % (len(todo), ablation, name, s1.get("provider", "none"), s1.get("model", "default"),
                        len(pairs) - len(todo)))
    client = os.path.join(plugin, "bin", "flow-s1.sh")
    lock = threading.Lock()
    reasons = collections.Counter()
    retried = [0]

    def ask(p):
        cmd = [client, "ask", "--site", SITE, "--state-file", os.path.join(base, p["states"][ablation]["path"]),
               "--state-format", "json", "--ref", p["ref"], "--current", p["label"]]
        for attempt in (1, 2):
            try:
                r = subprocess.run(cmd, cwd=work, env=env, capture_output=True, text=True, timeout=120)
                rc, err = r.returncode, r.stderr
            except subprocess.TimeoutExpired:
                rc, err = 3, "flow-s1: no answer: replay-timeout"
            m = re.search(r"no answer: ([a-z0-9-]+)", err)
            if rc == 0:
                reason = "answered"
            elif rc == 3 and m:
                # Shadow mode records the answer and then reports no answer
                # to its caller; for the replay it is an answer.
                reason = "answered" if m.group(1) == "shadow" else m.group(1)
            else:
                # A usage error (exit 2: a state file that cannot be read)
                # or anything else that is not an answer or a no-answer.
                reason = "exit-%d" % rc
            if reason == "http-429" and attempt == 1:
                with lock:
                    retried[0] += 1
                time.sleep(backoff)
                continue
            with lock:
                reasons[reason] += 1
            return reason
        return reason

    before = len(read_records(rec_file))
    if todo:
        first = todo[0]
        reason = ask(first)
        after = [r for r in read_records(rec_file)[before:] if r.get("ref") == first["ref"]]
        if not after:
            sys.stderr.write("flow-s1-eval: the first call wrote no record (%s); nothing else was sent\n" % reason)
            print(json.dumps({"sent": 1, "records": 0, "reasons": dict(reasons)}, sort_keys=True))
            return 3
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(ask, todo[1:]))
    # flow-s1.sh keeps the answer when it cannot write the record (the records
    # lock held for more than a second), so a sent pair can have no record.
    # Only the records this run wrote count: a no-answer from an earlier run
    # is not a record of this send.
    recorded = {r.get("ref") for r in read_records(rec_file)[before:]}
    unrecorded = [p["ref"] for p in todo if p["ref"] not in recorded]
    print(json.dumps({"sent": len(todo), "retried_429": retried[0], "reasons": dict(reasons),
                      "skipped_no_state": len(missing_state), "records": rec_file,
                      "sent_without_record": len(unrecorded)}, sort_keys=True))
    if unrecorded:
        sys.stderr.write("flow-s1-eval: %d sent pairs have no record (first: %s); run the replay again to send "
                         "them\n" % (len(unrecorded), unrecorded[0]))
        return 4
    return 0


# ====================================================================== score

def wilson(k, n, z=Z95):
    """(lower, upper) of the Wilson score interval, or (None, None) for n=0."""
    if n == 0:
        return None, None
    phat = k / n
    denom = 1 + z * z / n
    centre = (phat + z * z / (2 * n)) / denom
    half = z * math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n)) / denom
    return max(0.0, centre - half), min(1.0, centre + half)


def auc(rows):
    """Mann-Whitney AUC of p for label fail against pass; ties count half.
    None when either class is empty."""
    pos = sorted(p for p, y in rows if y)
    neg = sorted(p for p, y in rows if not y)
    if not pos or not neg:
        return None
    # rank-sum with average ranks for ties
    allv = sorted([(p, 1) for p in pos] + [(p, 0) for p in neg])
    ranks = {}
    i = 0
    while i < len(allv):
        j = i
        while j < len(allv) and allv[j][0] == allv[i][0]:
            j += 1
        ranks[allv[i][0]] = (i + j + 1) / 2.0
        i = j
    rsum = sum(ranks[p] for p in pos)
    return (rsum - len(pos) * (len(pos) + 1) / 2.0) / (len(pos) * len(neg))


def null_auc_se(rows):
    """Standard error of the AUC when p carries no signal about the label
    (Hanley and McNeil, no ties): sqrt((n1 + n2 + 1) / (12 n1 n2))."""
    n1 = sum(1 for _, y in rows if y)
    n2 = len(rows) - n1
    if not n1 or not n2:
        return None
    return math.sqrt((n1 + n2 + 1) / (12.0 * n1 * n2))


def flagged(p, t):
    """The site acts on a confident "would still pass": confidence |2p-1| at
    least t, and p below 0.5."""
    return p < 0.5 and abs(2 * p - 1) >= t - 1e-9


def bin_of(p):
    return min(9, int(p * 10))


def stratum_metrics(rows):
    """rows: [(pair, p or None, reason)]."""
    n = len(rows)
    ans = [(pair, p) for pair, p, _ in rows if p is not None]
    reasons = collections.Counter(r for _, p, r in rows if p is None)
    y = [(p, pair["label"] == "fail") for pair, p in ans]
    fail_n = sum(1 for _, t in y if t)
    pass_n = len(y) - fail_n
    out = {"pairs": n, "answered": len(ans), "coverage": round(len(ans) / n, 6) if n else None,
           "no_answer": dict(reasons), "fail": sum(1 for pair, _, _ in rows if pair["label"] == "fail"),
           "pass": sum(1 for pair, _, _ in rows if pair["label"] == "pass"),
           "hn_behavioral": sum(1 for pair, _, _ in rows if pair["hn_behavioral"]),
           "answered_fail": fail_n, "answered_pass": pass_n}
    if not ans:
        out.update(accuracy=None, balanced_accuracy=None, auc=None, brier=None, brier_skill=None)
        return out
    correct = sum(1 for p, t in y if (p >= 0.5) == t)
    tpr = sum(1 for p, t in y if t and p >= 0.5) / fail_n if fail_n else None
    tnr = sum(1 for p, t in y if not t and p < 0.5) / pass_n if pass_n else None
    base = fail_n / len(y)
    brier = sum((p - (1.0 if t else 0.0)) ** 2 for p, t in y) / len(y)
    brier_ref = base * (1 - base)
    a = auc(y)
    out.update(
        accuracy=round(correct / len(y), 6),
        balanced_accuracy=round((tpr + tnr) / 2, 6) if tpr is not None and tnr is not None else None,
        auc=round(a, 6) if a is not None else None,
        brier=round(brier, 6),
        brier_skill=round(1 - brier / brier_ref, 6) if brier_ref > 0 else None,
        constant_predictor={"predicts": "fail" if base >= 0.5 else "pass", "accuracy": round(max(base, 1 - base), 6),
                            "balanced_accuracy": 0.5, "auc": 0.5, "brier": round(brier_ref, 6)},
        reliability=[{"bin": "%.1f-%.1f" % (b / 10, (b + 1) / 10),
                      "n": len(ps), "mean_p": round(sum(ps) / len(ps), 4) if ps else None,
                      "fail_rate": round(sum(1 for q, t in y if bin_of(q) == b and t) / len(ps), 4) if ps else None}
                     for b in range(10) for ps in [[q for q, _ in y if bin_of(q) == b]]],
        histogram={lab: [sum(1 for q, t in y if t == (lab == "fail") and bin_of(q) == b) for b in range(10)]
                   for lab in ("fail", "pass")},
    )
    return out


def sweep_for(rows):
    ans = [(pair, p) for pair, p, _ in rows if p is not None]
    fails = [p for pair, p in ans if pair["label"] == "fail"]
    hns = [p for pair, p in ans if pair["label"] == "pass" and pair["hn_behavioral"]]
    passes = [p for pair, p in ans if pair["label"] == "pass"]
    out = {}
    for t in SWEEP:
        fa_k = sum(1 for p in fails if flagged(p, t))
        hn_k = sum(1 for p in hns if flagged(p, t))
        ps_k = sum(1 for p in passes if flagged(p, t))
        fa_lo, fa_hi = wilson(fa_k, len(fails))
        hn_lo, hn_hi = wilson(hn_k, len(hns))
        ps_lo, ps_hi = wilson(ps_k, len(passes))
        out["%.2f" % t] = {
            "false_alarm": {"k": fa_k, "n": len(fails), "rate": round(fa_k / len(fails), 6) if fails else None,
                            "wilson_lower": fa_lo, "wilson_upper": fa_hi},
            "hn_recall": {"k": hn_k, "n": len(hns), "rate": round(hn_k / len(hns), 6) if hns else None,
                          "wilson_lower": hn_lo, "wilson_upper": hn_hi},
            "pass_flagged": {"k": ps_k, "n": len(passes), "rate": round(ps_k / len(passes), 6) if passes else None,
                             "wilson_lower": ps_lo, "wilson_upper": ps_hi},
        }
    return out


def clauses_at(sweep, t):
    if t is None or sweep is None:
        return None
    s = sweep["%.2f" % t]
    fa, hn = s["false_alarm"], s["hn_recall"]
    return {"t": t,
            "false_alarm": dict(fa, ceiling=FALSE_ALARM_CEILING,
                                holds=fa["wilson_upper"] is not None and fa["wilson_upper"] <= FALSE_ALARM_CEILING),
            "hn_recall": dict(hn, floor=HN_RECALL_FLOOR,
                              holds=hn["wilson_lower"] is not None and hn["wilson_lower"] >= HN_RECALL_FLOOR)}


def degenerate(rows):
    """p collapsed into one band: more than 80% of the fail-labelled answers
    and more than 80% of the pass-labelled answers in the same 0.1-wide bin,
    or one class always predicted. A confident provider on a set that is 80%
    pass puts most of all answers in one bin; that alone is not a collapse."""
    ans = [(p, pair["label"] == "fail") for pair, p, _ in rows if p is not None]
    if not ans:
        return {"degenerate": False, "largest_bin_share": None, "per_label": None, "one_class": None}
    ps = [p for p, _ in ans]
    share = max(collections.Counter(bin_of(p) for p in ps).values()) / len(ps)
    per_label = {}
    for lab, want in (("fail", True), ("pass", False)):
        sub = [bin_of(p) for p, y in ans if y == want]
        if sub:
            b, n = collections.Counter(sub).most_common(1)[0]
            per_label[lab] = {"bin": b, "share": round(n / len(sub), 6)}
    collapsed = len(per_label) == 2 and per_label["fail"]["bin"] == per_label["pass"]["bin"] and all(
        v["share"] > DEGENERATE_BIN_SHARE for v in per_label.values())
    one_class = all(p >= 0.5 for p in ps) or all(p < 0.5 for p in ps)
    return {"degenerate": collapsed or one_class, "largest_bin_share": round(share, 6),
            "per_label": per_label, "one_class": one_class}


def permutation_auc(rows, seed, k):
    """(mean within-group AUC, mean pooled AUC) with labels permuted within
    each (case, trap). The within-group mean is 0.5 in expectation whatever
    the provider answers, so it tests the scorer; the pooled AUC also carries
    differences in p between traps and is reported beside it."""
    ans = [(pair, p) for pair, p, _ in rows if p is not None]
    groups = collections.defaultdict(list)
    for i, (pair, _) in enumerate(ans):
        groups[(pair["case"], pair["trap"])].append(i)
    labels = [pair["label"] == "fail" for pair, _ in ans]
    rng = random.Random(seed)
    within, pooled = [], []
    for _ in range(k):
        perm = list(labels)
        aucs = []
        for idx in groups.values():
            sub = [labels[i] for i in idx]
            rng.shuffle(sub)
            for i, v in zip(idx, sub):
                perm[i] = v
            a = auc([(ans[i][1], perm[i]) for i in idx])
            if a is not None:
                aucs.append(a)
        if aucs:
            within.append(sum(aucs) / len(aucs))
        a = auc([(p, perm[i]) for i, (_, p) in enumerate(ans)])
        if a is not None:
            pooled.append(a)
    mean = lambda v: round(sum(v) / len(v), 6) if v else None  # noqa: E731
    return mean(within), mean(pooled)


def join(pairs, records, expected_all):
    """({ref: (p or None, reason, attempts)}, errors)."""
    by_ref = {p["ref"]: p for p in pairs}
    grouped = collections.defaultdict(list)
    errors = []
    for r in records:
        if "_unreadable" in r:
            errors.append("an unreadable record line")
            continue
        if r.get("site") != SITE or r.get("question") != QUESTION:
            continue
        ref = r.get("ref")
        if ref not in by_ref:
            errors.append("a record for a ref that is not a pair: %s" % ref)
            continue
        grouped[ref].append(r)
    out = {}
    for ref, rs in grouped.items():
        ans = [r for r in rs if isinstance(r.get("answer"), dict) and "p" in r["answer"]]
        if len(ans) > 1:
            errors.append("ref answered more than once: %s" % ref)
            continue
        chosen = ans[0] if ans else rs[-1]
        want = by_ref[ref]["states"].get(chosen.get("_ablation", ""), {}).get("sha256")
        if want and chosen.get("state_sha256") != want:
            errors.append("record state does not match the pair's state: %s" % ref)
        p = float(chosen["answer"]["p"]) if ans else None
        out[ref] = (p, "answered" if ans else str(chosen.get("result")), len(rs), chosen.get("ts"))
    if expected_all:
        missing = [p["ref"] for p in pairs if p["ref"] not in out]
        if missing:
            errors.append("%d pairs have no record (first: %s)" % (len(missing), missing[0]))
    return out, errors


def git_head(path):
    try:
        r = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    return r.stdout.strip() if r.returncode == 0 else "unknown"


def fmt(v, pct=False, digits=3):
    if v is None:
        return "n/a"
    if pct:
        return "%.1f%%" % (100 * v)
    return ("%." + str(digits) + "f") % v


def cmd_score(args):
    opts = parse_args(args, ("--pairs", "--records", "--dest", "--set", "--choose-threshold", "--threshold-file",
                             "--seed", "--limit", "--permutations"))
    for k in ("--pairs", "--records", "--dest"):
        if not opts.get(k):
            die("s1-score --pairs P --records R --dest D [--set dev|eval] [--choose-threshold T | --threshold-file T]")
    if opts.get("--choose-threshold") and opts.get("--threshold-file"):
        die("--choose-threshold and --threshold-file exclude each other")
    seed = int_opt(opts, "--seed", DEFAULT_SEED)
    limit = int_opt(opts, "--limit", None, 1)
    n_perm = int_opt(opts, "--permutations", 200, 1)
    pairs_path = os.path.abspath(opts["--pairs"])
    with open(pairs_path, "rb") as fh:
        pairs_sha = sha256_bytes(fh.read())
    all_pairs = load_pairs(pairs_path)
    unobserved = sum(1 for p in all_pairs if p["label"] == "unobserved")
    pairs = [p for p in all_pairs if p["label"] != "unobserved"]
    if limit is not None:
        pairs = pairs[:limit]
    sets = sorted({p["set"] for p in pairs})
    set_name = opts.get("--set") or (sets[0] if len(sets) == 1 else None)
    if set_name not in ("dev", "eval"):
        die("the pairs hold sets %s; pass --set dev or --set eval" % sets)
    pairs = [p for p in pairs if p["set"] == set_name]
    if opts.get("--choose-threshold") and set_name != "dev":
        die("a threshold is chosen on the dev set only")
    dest = os.path.abspath(opts["--dest"])
    os.makedirs(dest, exist_ok=True)
    rec_root = os.path.abspath(opts["--records"])
    ablations = sorted(d for d in os.listdir(rec_root)
                       if os.path.isfile(os.path.join(rec_root, d, "system-one.jsonl"))) if os.path.isdir(rec_root) else []

    errors = []
    joined, counts, models = {}, {}, set()
    for ab in ablations:
        recs = read_records(os.path.join(rec_root, ab, "system-one.jsonl"))
        for r in recs:
            r["_ablation"] = "real" if ab == "repeat" else ab
            # The provider and model that answered. A no-answer record names
            # the configured model, which can be spelled differently from
            # the one a reply names, so only answers are counted.
            if r.get("site") == SITE and isinstance(r.get("answer"), dict) and "p" in r["answer"]:
                models.add("%s %s" % (r.get("provider"), r.get("model")))
        j, errs = join(pairs, recs, expected_all=ab != "repeat")
        errors += ["%s: %s" % (ab, e) for e in errs]
        joined[ab] = j
        reasons = collections.Counter(v[1] for v in j.values() if v[0] is None)
        counts[ab] = {"pairs": len(pairs) if ab != "repeat" else len(j), "record_lines": len(recs),
                      "answered": sum(1 for v in j.values() if v[0] is not None),
                      "no_answer": dict(reasons), "retried": sum(1 for v in j.values() if v[2] > 1)}
        counts[ab]["ok"] = counts[ab]["answered"] + sum(reasons.values()) == counts[ab]["pairs"]
    if "real" not in joined:
        errors.append("no records under %s/real" % rec_root)
    # The bar holds for one provider and model: answers from two are never
    # pooled, and the evaluation set is judged against the provider and model
    # the threshold was chosen on.
    if len(models) > 1:
        errors.append("the answers come from more than one provider and model: %s" % "; ".join(sorted(models)))
    tinfo = None
    if opts.get("--threshold-file"):
        with open(opts["--threshold-file"], encoding="utf-8") as fh:
            tinfo = json.load(fh)
        if models and sorted(models) != sorted(tinfo.get("providers") or []):
            errors.append("the answers come from %s, the threshold was chosen on answers from %s" % (
                "; ".join(sorted(models)), "; ".join(sorted(tinfo.get("providers") or [])) or "none"))

    summary = {"set": set_name, "pairs_file_sha256": pairs_sha, "pairs": len(pairs), "unobserved_excluded": unobserved,
               "providers": sorted(models), "seed": seed, "checks": {"count": counts}}
    if errors:
        summary["verdict"] = {"verdict": "harness-error", "reasons": errors[:20]}
        write_json(os.path.join(dest, "summary.json"), summary)
        with open(os.path.join(dest, "summary.md"), "w", encoding="utf-8") as fh:
            fh.write("# System One test-discrimination measurement\n\nVerdict: harness-error. Records and pairs do "
                     "not match one to one, so no metric is read.\n\n" + "".join("- %s\n" % e for e in errors[:20]))
        for e in errors[:5]:
            sys.stderr.write("flow-s1-eval: records: %s\n" % e)
        print(json.dumps({"verdict": "harness-error"}))
        return 1

    def rows_for(ab, stratum=None, case=None):
        j = joined.get(ab, {})
        out = []
        for p in pairs:
            if (stratum and p["stratum"] != stratum) or (case and p["case"] != case):
                continue
            if p["ref"] in j:
                out.append((p, j[p["ref"]][0], j[p["ref"]][1]))
        return out

    strata_names = [s for s in ("agent", "author") if any(p["stratum"] == s for p in pairs)]
    if opts.get("--choose-threshold") and strata_names != ["agent", "author"]:
        die("a threshold is chosen on dev agent pairs and dev author pairs separately; these pairs hold only %s"
            % (", ".join(strata_names) or "none"))
    strata = {s: {ab: stratum_metrics(rows_for(ab, s)) for ab in ablations if ab != "repeat"} for s in strata_names}
    per_case = {s: {c: stratum_metrics(rows_for("real", s, c))
                    for c in sorted({p["case"] for p in pairs if p["stratum"] == s})} for s in strata_names}
    sweep = {s: sweep_for(rows_for("real", s)) for s in strata_names}

    checks = summary["checks"]
    checks["coverage"] = {s: strata[s]["real"]["coverage"] for s in strata_names}
    checks["coverage"]["ok"] = all((strata[s]["real"]["coverage"] or 0) >= COVERAGE_FLOOR for s in strata_names)
    checks["degenerate"] = {s: degenerate(rows_for("real", s)) for s in strata_names}
    checks["degenerate"]["any"] = any(checks["degenerate"][s]["degenerate"] for s in strata_names)
    if "shuffled" in joined:
        pl_rows = [(p, pair["label"] == "fail") for pair, p, _ in rows_for("shuffled") if p is not None]
        pooled = auc(pl_rows)
        per = {s: strata[s]["shuffled"]["auc"] for s in strata_names}
        se = {s: null_auc_se([(p, pair["label"] == "fail") for pair, p, _ in rows_for("shuffled", s) if p is not None])
              for s in strata_names}
        se["pooled"] = null_auc_se(pl_rows)
        ok = pooled is not None and abs(pooled - 0.5) <= PLACEBO_TOLERANCE and all(
            v is not None and abs(v - 0.5) <= PLACEBO_TOLERANCE for v in per.values())
        checks["placebo"] = {"ran": True, "auc": round(pooled, 6) if pooled is not None else None,
                             "per_stratum": per, "ok": ok,
                             "null_se": {k: round(v, 6) if v is not None else None for k, v in se.items()}}
    else:
        checks["placebo"] = {"ran": False, "auc": None, "ok": None}
    perm_both = {s: permutation_auc(rows_for("real", s), seed, n_perm) for s in strata_names}
    perm = {s: v[0] for s, v in perm_both.items()}
    checks["permutation"] = {"per_stratum": perm, "pooled_per_stratum": {s: v[1] for s, v in perm_both.items()},
                             "permutations": n_perm,
                             "ok": all(v is None or abs(v - 0.5) <= PERMUTATION_TOLERANCE for v in perm.values())}
    if "repeat" in joined:
        real = joined.get("real", {})
        both = [(ref, v[0], real[ref][0]) for ref, v in joined["repeat"].items()
                if v[0] is not None and ref in real and real[ref][0] is not None]
        checks["determinism"] = {"pairs": len(both),
                                 "over_0.02": sum(1 for _, a, b in both if abs(a - b) > DETERMINISM_TOLERANCE),
                                 "largest_difference": round(max((abs(a - b) for _, a, b in both), default=0.0), 6)}
    else:
        checks["determinism"] = {"pairs": 0, "over_0.02": None, "largest_difference": None}
    base = os.path.dirname(pairs_path)
    sizes = []
    for p in pairs:
        st = p["states"].get("real")
        if st and os.path.isfile(os.path.join(base, st["path"])):
            sizes.append(os.path.getsize(os.path.join(base, st["path"])))
    checks["truncation"] = {"states_over_imajev_cap": sum(1 for b in sizes if b > 7000 * 4),
                            "states_over_typesafe_cap": sum(1 for b in sizes if b > 28000 * 4),
                            "largest_state_bytes": max(sizes, default=0)}
    rng = random.Random(seed)
    sample = rng.sample(pairs, min(5, len(pairs)))
    real_recs = {r.get("ref"): r for r in read_records(os.path.join(rec_root, "real", "system-one.jsonl"))}
    checks["sample"] = []
    for p in sample:
        st = p["states"]["real"]
        try:
            with open(os.path.join(base, st["path"]), encoding="utf-8") as fh:
                state = json.load(fh)
        except (OSError, ValueError):
            state = None
        checks["sample"].append({"ref": p["ref"], "sha256": st["sha256"],
                                 "record_sha256_matches": (real_recs.get(p["ref"]) or {}).get("state_sha256") == st["sha256"],
                                 "state": state})

    # Threshold: chosen on dev, applied on eval.
    t = tinfo.get("t") if tinfo else None
    if opts.get("--choose-threshold"):
        for cand in SWEEP:
            ok = []
            for s in strata_names:
                fa = sweep[s]["%.2f" % cand]["false_alarm"]
                ok.append(fa["wilson_upper"] is not None and fa["wilson_upper"] <= FALSE_ALARM_CEILING)
            if ok and all(ok):
                t = cand
                break
        tinfo = {"t": t, "chosen_at": now_utc(), "commit": git_head(_BIN), "set": "dev",
                 "pairs_file_sha256": pairs_sha, "providers": sorted(models),
                 "placebo": checks["placebo"], "degenerate": checks["degenerate"]["any"],
                 "coverage_ok": checks["coverage"]["ok"], "permutation_ok": checks["permutation"]["ok"],
                 "rule": "lowest t in 0.50..0.95 at which the false-alarm Wilson upper bound is at most 5% "
                         "on dev agent pairs and on dev author pairs separately"}
        write_json(os.path.abspath(opts["--choose-threshold"]), tinfo)
    summary["threshold"] = tinfo

    clauses = clauses_at(sweep.get("agent"), t)
    reasons = []
    if set_name == "eval":
        if tinfo is None or t is None:
            verdict = "inconclusive-no-threshold"
            reasons.append("no threshold from the dev set")
        elif any((v[3] or "") <= tinfo.get("chosen_at", "") for v in joined.get("real", {}).values()):
            verdict = "inconclusive-threshold-order"
            reasons.append("an evaluation record is not newer than the threshold (%s)" % tinfo.get("chosen_at"))
        elif not (tinfo.get("placebo") or {}).get("ok"):
            verdict = "inconclusive-placebo"
            reasons.append("the dev set's shuffled-wrong-version placebo did not run or scored away from 0.5")
        elif not (tinfo.get("coverage_ok") is True and tinfo.get("degenerate") is False
                  and tinfo.get("permutation_ok") is True):
            verdict = "inconclusive-dev-checks"
            failed = [name for name, ok in (("coverage", tinfo.get("coverage_ok") is True),
                                            ("degenerate answers", tinfo.get("degenerate") is False),
                                            ("label permutation", tinfo.get("permutation_ok") is True)) if not ok]
            reasons.append("the threshold was chosen on a dev set whose own checks did not pass (%s)" % ", ".join(failed))
        else:
            verdict = None
    else:
        verdict = None
        if checks["placebo"]["ran"] and not checks["placebo"]["ok"]:
            verdict = "inconclusive-placebo"
            reasons.append("the shuffled-wrong-version placebo AUC is %s, more than 0.05 from 0.5"
                           % fmt(checks["placebo"]["auc"]))
    if verdict is None and not checks["coverage"]["ok"]:
        verdict = "inconclusive-coverage"
        reasons.append("coverage below 95%% on a stratum (%s)" % ", ".join(
            "%s %s" % (s, fmt(checks["coverage"][s], pct=True)) for s in strata_names))
    if verdict is None and checks["degenerate"]["any"]:
        verdict = "inconclusive-degenerate"
        reasons.append("the answers are degenerate: more than 80% of the fail answers and of the pass answers in the "
                       "same 0.1-wide bin, or one class always predicted")
    if verdict is None and not checks["permutation"]["ok"]:
        verdict = "inconclusive-permutation"
        reasons.append("the label-permutation AUC (mean within case and trap) is not within 0.02 of 0.5")
    if verdict is None:
        if set_name == "dev":
            verdict = "dev-only-provisional"
            reasons.append("a result on the dev set cannot adopt the site")
        elif clauses and clauses["false_alarm"]["holds"] and clauses["hn_recall"]["holds"]:
            verdict = "adopt"
            reasons.append("both clauses of the bar hold at t=%.2f" % t)
        else:
            verdict = "not-adopted"
            reasons.append("a clause of the bar does not hold at t=%s" % ("%.2f" % t if t is not None else "n/a"))
    summary["verdict"] = {"verdict": verdict, "reasons": reasons, "t": t, "clauses": clauses}
    summary["strata"] = strata
    summary["per_case"] = per_case
    summary["sweep"] = sweep
    summary["small_cases"] = sorted("%s/%s" % (s, c) for s in per_case for c, m in per_case[s].items()
                                    if m["fail"] < MIN_FAIL_PAIRS_PER_CASE)
    write_json(os.path.join(dest, "summary.json"), summary)
    with open(os.path.join(dest, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write(render_md(summary, strata_names))
    print(json.dumps({"verdict": verdict, "t": t}))
    return 0


def render_md(s, strata_names):
    v = s["verdict"]
    c = s["checks"]
    L = ["# System One test-discrimination measurement", "",
         "Question: if the module did what the risk row's plausible wrong version describes, would this test fail? "
         "p is the provider's probability of yes. A pair is flagged when the provider is confident the test would "
         "still pass: confidence |2p - 1| at least t and p below 0.5.", "",
         "Set: %s. Pairs scored: %d (%d unobserved pairs left out). Provider: %s." % (
             s["set"], s["pairs"], s["unobserved_excluded"], ", ".join(s["providers"]) or "none"), ""]
    L += ["## Measurement checks", "",
          "Each check says what the result would look like if the harness, not the model, produced it. They are read "
          "before any metric.", "",
          "| Check | Result |", "|---|---|"]
    for ab, cnt in sorted(c["count"].items()):
        L.append("| Records match pairs (%s) | %s: %d pairs, %d answered, no answer %s, %d retried |" % (
            ab, "yes" if cnt["ok"] else "NO", cnt["pairs"], cnt["answered"],
            ", ".join("%s %d" % kv for kv in sorted(cnt["no_answer"].items())) or "0", cnt["retried"]))
    L.append("| Coverage at least 95%% | %s (%s) |" % ("yes" if c["coverage"]["ok"] else "NO", ", ".join(
        "%s %s" % (st, fmt(c["coverage"][st], pct=True)) for st in strata_names)))
    L.append("| Answers spread out (fail and pass answers not both over 80%% in one bin; both classes predicted) | %s (%s) |" % (
        "NO, degenerate" if c["degenerate"]["any"] else "yes", ", ".join(
            "%s largest bin %s" % (st, fmt(c["degenerate"][st]["largest_bin_share"], pct=True)) for st in strata_names)))
    pl = c["placebo"]
    L.append("| Shuffled-wrong-version placebo AUC within 0.05 of 0.5 | %s |" % (
        "not run" if not pl["ran"] else "%s (pooled AUC %s, standard error with no signal %s; %s)" % (
            "yes" if pl["ok"] else "NO", fmt(pl["auc"]), fmt(pl["null_se"]["pooled"]), ", ".join(
                "%s AUC %s, standard error %s" % (st, fmt(pl["per_stratum"][st]), fmt(pl["null_se"][st]))
                for st in strata_names))))
    L.append("| Label-permutation AUC, mean within case and trap, within 0.02 of 0.5 | %s (%s; pooled %s) |" % (
        "yes" if c["permutation"]["ok"] else "NO",
        ", ".join("%s %s" % (st, fmt(val)) for st, val in c["permutation"]["per_stratum"].items()),
        ", ".join("%s %s" % (st, fmt(val)) for st, val in c["permutation"]["pooled_per_stratum"].items())))
    d = c["determinism"]
    L.append("| Same state sent twice | %s |" % ("not run" if not d["pairs"] else "%d pairs, %d differ by more than 0.02 (largest %s)" % (
        d["pairs"], d["over_0.02"], fmt(d["largest_difference"]))))
    tr = c["truncation"]
    L.append("| States over a provider's cap | %d over imajev's 7,000 tokens, %d over TypeSafe's 28,000 (largest %d bytes) |" % (
        tr["states_over_imajev_cap"], tr["states_over_typesafe_cap"], tr["largest_state_bytes"]))
    if s.get("threshold"):
        th = s["threshold"]
        L.append("| Threshold fixed on the dev set before the evaluation records | t = %s, chosen %s at commit %s |" % (
            fmt(th.get("t"), digits=2), th.get("chosen_at"), th.get("commit")))
    L += ["", "## Adoption bar", "",
          "Verdict: **%s**. %s" % (v["verdict"], " ".join(r[0].upper() + r[1:] + "." for r in v["reasons"])), ""]
    cl = v.get("clauses")
    if cl:
        fa, hn = cl["false_alarm"], cl["hn_recall"]
        L += ["On agent-written pairs at t = %.2f:" % cl["t"], "",
              "1. Tests that do fail against the wrong version, flagged as if they would pass: %d of %d (Wilson 95%% upper "
              "bound %s; must be at most 5%%; lower is better): %s." % (fa["k"], fa["n"], fmt(fa["wilson_upper"], pct=True),
                                                                   "holds" if fa["holds"] else "does not hold"),
              "2. Hard negatives (tests that pass against this wrong version but fail another) flagged: %d of %d (Wilson "
              "95%% lower bound %s; must be at least 30%%; higher is better): %s." % (
                  hn["k"], hn["n"], fmt(hn["wilson_lower"], pct=True), "holds" if hn["holds"] else "does not hold"), ""]
    L += ["## Results per stratum", "",
          "Accuracy and balanced accuracy read p at 0.5. AUC: 0.5 is chance, 1.0 is perfect ordering of fail above pass. "
          "Brier: lower is better. Brier skill: above 0 beats always answering the base rate.", "",
          "| Stratum | Ablation | Pairs | Coverage | Fail / pass (hard negatives) | Accuracy (constant) | Balanced accuracy | AUC | Brier (constant) | Brier skill |",
          "|---|---|---|---|---|---|---|---|---|---|"]
    for st in strata_names:
        for ab, m in sorted(s["strata"][st].items()):
            cp = m.get("constant_predictor") or {}
            L.append("| %s | %s | %d | %s | %d / %d (%d) | %s (%s) | %s | %s | %s (%s) | %s |" % (
                st, ab, m["pairs"], fmt(m["coverage"], pct=True), m["fail"], m["pass"], m["hn_behavioral"],
                fmt(m["accuracy"], pct=True), fmt(cp.get("accuracy"), pct=True), fmt(m["balanced_accuracy"], pct=True),
                fmt(m["auc"]), fmt(m["brier"]), fmt(cp.get("brier")), fmt(m["brier_skill"])))
    L += ["", "## Per case (real descriptions)", "",
          "| Stratum | Case | Pairs | Coverage | Fail pairs | AUC | Note |", "|---|---|---|---|---|---|---|"]
    for st in strata_names:
        for case, m in s["per_case"][st].items():
            L.append("| %s | %s | %d | %s | %d | %s | %s |" % (
                st, case, m["pairs"], fmt(m["coverage"], pct=True), m["fail"], fmt(m["auc"]),
                "fewer than 20 fail pairs: cannot carry the verdict alone" if m["fail"] < MIN_FAIL_PAIRS_PER_CASE else ""))
    for st in strata_names:
        L += ["", "## Threshold sweep, %s pairs" % st, "",
              "| t | Fail pairs flagged (lower is better) | Wilson upper | Hard negatives flagged (higher is better) | Wilson lower | All pass pairs flagged (reported) | Wilson lower, upper |",
              "|---|---|---|---|---|---|---|"]
        for key, row in s["sweep"][st].items():
            fa, hn, ps = row["false_alarm"], row["hn_recall"], row["pass_flagged"]
            L.append("| %s | %d of %d | %s | %d of %d | %s | %d of %d | %s, %s |" % (
                key, fa["k"], fa["n"], fmt(fa["wilson_upper"], pct=True), hn["k"], hn["n"],
                fmt(hn["wilson_lower"], pct=True), ps["k"], ps["n"], fmt(ps["wilson_lower"], pct=True),
                fmt(ps["wilson_upper"], pct=True)))
        rel = s["strata"][st].get("real", {}).get("reliability")
        if rel:
            L += ["", "Reliability, %s pairs (a calibrated provider has fail rate close to mean p in each bin):" % st, "",
                  "| p bin | Pairs | Mean p | Fail rate |", "|---|---|---|---|"]
            for b in rel:
                L.append("| %s | %d | %s | %s |" % (b["bin"], b["n"], fmt(b["mean_p"]), fmt(b["fail_rate"])))
    L += ["", "## Appendix: five states", "",
          "Each state below is what the provider received for that pair. It should show the test and the risk row's "
          "wrong version, and no hidden test name other than the test's own.", ""]
    for smp in c["sample"]:
        L.append("### %s" % smp["ref"])
        L.append("")
        L.append("sha256 %s, record matches: %s" % (smp["sha256"], "yes" if smp["record_sha256_matches"] else "no"))
        L.append("")
        if smp["state"]:
            L.append("```json")
            L.append(json.dumps({"risk": smp["state"]["risk"], "test": smp["state"]["test"]}, indent=2, ensure_ascii=False))
            L.append("```")
            L.append("")
    return "\n".join(L) + "\n"


COMMANDS = {"s1-pairs": cmd_pairs, "s1-replay": cmd_replay, "s1-score": cmd_score}
