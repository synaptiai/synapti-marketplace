"""The test-discrimination measurement: does a System One answer to "would
this test fail if the module were the risk row's plausible wrong version?"
agree with what the correctness eval observed? The method, the strata and
the adoption bar are in references/correctness-eval.md, section "System One:
does a test catch the wrong version". Reached through bin/flow-s1-eval.sh
(or _flow_eval.py s1-pairs | s1-replay | s1-score | s1-smoke).

s1-pairs --evals-dir E --dest D [--set dev|eval] [--author] [--out R]...
         [--rescore] [--seed N] [--timeout S]
    One pair per (test, trap of the same case). --author adds the hidden
    suites (labels from hidden/traps.json); each --out adds the agent-written
    oracle tests of every run under R/runs (labels from the run's
    own-test-traps.json; the oracle test ids, which that file does not keep,
    are recovered by re-running the run's suite on its own module and on the
    reference). A run whose stored failing or unobserved list is shorter than
    its count (the 50-entry cap) is refused, exit 2, unless --rescore, which
    re-runs every variant. A run is left out and listed when its re-run does
    not reproduce the stored oracle count, own_impl.total and failed_ids,
    reference_run.failed_ids, disagree_with_reference and
    unobserved_on_reference, or when its fail pairs (with those lost to a
    state error) do not sum to its stored failing counts. Writes D/pairs.jsonl, D/export.json
    and D/states/<ablation>/<id>.json for three ablations: real,
    name-stripped (the test function renamed test_x) and shuffled (the risk
    row of a trap from another case, drawn with the seed). The risk row is
    the trap name and column 2 of expected.md; columns 3 and 4 and the trap
    description are never read into a state, and every state is checked for
    them before it is written. Author states have their comments removed.
    No model call.

s1-replay --pairs P --records R --provider-settings F [--ablation A]
          [--records-name NAME] [--workers N] [--scratch DIR] [--limit N]
          [--sample N] [--seed N] [--only-set dev|eval] [--backoff S] [--refs F]
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
    repeatability check uses --sample 30 --records-name repeat). --refs F sends
    only the pairs whose refs F lists, one per line (# starts a comment); a
    listed ref that is not a labelled pair is a usage error.

s1-score --pairs P --records R --dest D [--set dev|eval]
         [--choose-threshold T | --threshold-file T] [--seed N] [--limit N]
         [--permutations N]
    Joins the records under R/<ablation>/system-one.jsonl to the pairs by
    ref, runs the measurement checks, and writes D/summary.json and
    D/summary.md. Exit 1 (verdict harness-error) when records and pairs do
    not match one to one, when the answers name more than one provider and
    model, when they name another one than the threshold file, or when an
    evaluation pair or agent run was in the dev set the threshold file lists.
    --choose-threshold (dev set, with agent and author pairs) writes the
    lowest t at which the bar's false-alarm clause holds on agent and author
    pairs separately, with the commit, the time, and the refs, run keys and
    run identities (the sha256 of own-test-traps.json and the session id,
    which do not depend on the --out path) of every dev pair;
    --threshold-file (evaluation set) applies it. A real-description AUC,
    the mean of the AUCs within each stratum, case and trap, more than 2
    standard errors below 0.5 makes the verdict inconclusive-direction.
    Pairs answered again under R/repeat are reported with the difference
    between their two answers (smaller is better); this never changes the
    verdict.
    --limit N scores the first N pairs of the set: the verdict is
    inconclusive-limited, and --choose-threshold refuses it.

s1-smoke --pairs P --records R [--refs F]
    Run before the dev replay, on records from replay --refs F and replay
    --refs F --sample 3 --records-name repeat. Every listed pair labelled
    fail must have p above 0.5 and every one labelled pass p below 0.5. F
    defaults to evals/s1-discrimination/smoke-refs.txt. Exit 1, naming each
    problem, when this does not hold, a pair has no answer, or the records
    do not match the pairs. The difference between the two answers of each
    pair answered twice is reported (smaller is better) and never makes the
    exit status 1, also when no pair was answered twice.
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
import bisect
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
from typing import Any, NoReturn

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
# The real-description AUC must exceed the placebo AUC by this much, both
# taken as the mean within each stratum, case and trap.
PLACEBO_MIN_GAP = 0.15
PERMUTATION_TOLERANCE = 0.02
DIRECTION_SE = 2
# Reported only: how many repeated pairs differ by more than this.
REPEAT_REPORT_LINE = 0.02
MIN_FAIL_PAIRS_PER_CASE = 20
REF_UNSAFE = re.compile(r"[^A-Za-z0-9._:/#@+-]")


def die(msg, code=2) -> NoReturn:
    sys.stderr.write("flow-s1-eval: %s\n" % msg)
    sys.exit(code)


def parse_args(args, values, flags=(), repeat=()):
    opts: dict[str, Any] = {k: [] for k in repeat}
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
    (oracle ids, {trap: (failing, unobserved)} or None, what own-test-traps.json
    keeps of the two runs, reason or None)."""
    traps = fe.load_traps(case_dir)
    module = traps["module"]
    scratch = tempfile.mkdtemp(prefix="flow-s1-pairs.")
    try:
        copy = os.path.join(scratch, "project")
        fe.snapshot_project(project, copy)
        own, _ = fe.run_own_suite(copy, timeout)
        if own["incomplete"]:
            return None, None, None, "the own suite did not finish on its own module (%s)" % own["reason"]
        passing_own = [t for t in own["order"] if own["tests"][t] == "ok"]
        module_path = os.path.join(copy, module + ".py")
        reference = os.path.join(case_dir, "hidden", "reference_impl.py")
        shutil.copy(reference, os.path.join(copy, "reference_impl.py"))
        shutil.copy(reference, module_path)
        ref_run, _ = fe.run_own_suite(copy, timeout)
        if ref_run["incomplete"]:
            return None, None, None, "the own suite did not finish on the reference (%s)" % ref_run["reason"]
        oracle = [t for t in passing_own if ref_run["tests"].get(t) == "ok"]
        disagree = [t for t in passing_own if ref_run["tests"].get(t) in ("FAIL", "ERROR")]
        seen = {"own_impl.total": own["total"], "own_impl.failed_ids": sorted(own["failed_ids"]),
                "reference_run.failed_ids": sorted(ref_run["failed_ids"]),
                "disagree_with_reference": sorted(disagree),
                "unobserved_on_reference": sorted(t for t in passing_own if t not in oracle and t not in disagree)}
        per_trap: dict[str, tuple[list[str], list[str]]] | None = None
        if variants:
            per_trap = {}
            for name in sorted(traps["traps"]):
                shutil.copy(os.path.join(case_dir, traps["traps"][name]["variant"]), module_path)
                parsed, _ = fe.run_own_suite(copy, timeout)
                per_trap[name] = ([t for t in oracle if parsed["tests"].get(t) in ("FAIL", "ERROR")],
                                  [t for t in oracle if parsed["tests"].get(t, "missing") == "missing"])
        return oracle, per_trap, seen, None
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
        with open(own_path, "rb") as fh:
            own_bytes = fh.read()
        own = json.loads(own_bytes.decode("utf-8"))
        # The run's identity apart from where it sits on disk: the same run
        # copied under another --out keeps it, so the scorer can tell that
        # the pairs that chose t are being judged again.
        run_ids = ["own-test-traps:" + sha256_bytes(own_bytes)]
        try:
            with open(os.path.join(run_dir, "result.json"), encoding="utf-8") as fh:
                session = (json.load(fh) or {}).get("session_id")
        except (OSError, ValueError, AttributeError):
            session = None
        if isinstance(session, str) and session:
            run_ids.append("session:" + session)
        if own.get("catch_rate") is None:
            excluded.append({"run": run_key, "reason": "own tests were not scored: %s" % own.get("reason")})
            continue
        cut = [t for t, v in sorted(own["per_trap"].items())
               if v["failing_count"] > len(v["failing_own_tests"]) or v["unobserved_count"] > len(v["unobserved_oracle_tests"])]
        if cut and not rescore:
            die("%s: failing_count or unobserved_count is above the stored list for %s (the list is cut at 50); "
                "pass --rescore to re-run its variants" % (run_key, ", ".join(cut)))
        oracle, per_trap, seen, reason = rerun_suite(case["dir"], project, timeout, variants=rescore)
        if reason or oracle is None or seen is None:
            excluded.append({"run": run_key, "reason": reason or "the re-run returned no oracle tests"})
            continue
        # The oracle set is the tests passing on the agent's module and on
        # the reference. own-test-traps.json keeps its size and the lists that
        # set it apart from the other tests, so the re-run must reproduce
        # each of them, not only the size.
        stored_seen = {"own_impl.total": (own.get("own_impl") or {}).get("total"),
                       "own_impl.failed_ids": sorted((own.get("own_impl") or {}).get("failed_ids") or []),
                       "reference_run.failed_ids": sorted((own.get("reference_run") or {}).get("failed_ids") or []),
                       "disagree_with_reference": sorted(own.get("disagree_with_reference") or []),
                       "unobserved_on_reference": sorted(own.get("unobserved_on_reference") or [])}
        differ = [k for k in sorted(seen) if seen[k] != stored_seen[k]]
        if len(oracle) != own.get("own_passing_tests") or differ:
            excluded.append({"run": run_key, "reason": "the re-run oracle set differs from own-test-traps.json "
                             "(%d tests re-run, %s stored; differing: %s)" % (
                                 len(oracle), own.get("own_passing_tests"), ", ".join(differ) or "none")})
            continue
        # The fail pairs must sum to the stored failing counts, which are
        # complete even where the stored lists were cut at 50.
        stored_fail = sum(v["failing_count"] for v in own["per_trap"].values())
        if rescore:
            if per_trap is None:
                die("%s: the re-run returned no trap results" % run_key)
            labels = {t: (set(f), set(u)) for t, (f, u) in per_trap.items()}
        else:
            labels = {t: (set(v["failing_own_tests"]), set(v["unobserved_oracle_tests"])) for t, v in own["per_trap"].items()}
            listed = set().union(*[f | u for f, u in labels.values()]) if labels else set()
            if not listed <= set(oracle):
                excluded.append({"run": run_key, "reason": "the re-run oracle set differs from own-test-traps.json "
                                 "(a stored failing or unobserved test is not an oracle test on the re-run)"})
                continue
        spec_path = os.path.join(project, "ISSUE.md")
        if os.path.isfile(spec_path):
            with open(spec_path, encoding="utf-8") as fh:
                spec = fh.read()
        else:
            spec = case["spec"]
        info: dict[str, Any] = {"run": run_key, "case": case_name, "model": model, "arm": arm, "oracle_tests": len(oracle),
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
                                  "run": run_key, "run_ids": run_ids, "model": model, "arm": arm, "trap": trap,
                                  "test_id": test_id,
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


def read_refs(path):
    """The refs listed in a file, one per line; blank lines and lines
    starting with # are skipped."""
    try:
        with open(path, encoding="utf-8") as fh:
            refs = [line.strip() for line in fh if line.strip() and not line.lstrip().startswith("#")]
    except OSError as e:
        die("--refs cannot be read: %s" % e)
    if not refs:
        die("--refs lists no ref: %s" % path)
    return refs


def select_refs(pairs, refs):
    """The labelled pairs whose ref is listed, in the order listed. A listed
    ref that is not a labelled pair is a usage error."""
    by_ref = {p["ref"]: p for p in pairs if p["label"] != "unobserved"}
    missing = [r for r in refs if r not in by_ref]
    if missing:
        die("%d listed refs are not labelled pairs in the pairs file (first: %s)" % (len(missing), missing[0]))
    return [by_ref[r] for r in dict.fromkeys(refs)]


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
                             "--workers", "--scratch", "--limit", "--sample", "--seed", "--only-set", "--backoff",
                             "--refs"))
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
    if opts.get("--refs"):
        pairs = select_refs(pairs, read_refs(opts["--refs"]))
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
        reason = "exit-none"
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


def paired_auc_difference(rows):
    """rows: [(p_a, p_b, is_fail)], two answers for each pair. Returns
    (AUC of a, AUC of b, a minus b, standard error of a minus b) by DeLong's
    method for two AUCs over the same pairs, or None when either class has
    fewer than two pairs."""
    fail = [(a, b) for a, b, y in rows if y]
    passed = [(a, b) for a, b, y in rows if not y]
    m, n = len(fail), len(passed)
    if m < 2 or n < 2:
        return None

    def components(k):
        xs = sorted(r[k] for r in fail)
        ys = sorted(r[k] for r in passed)
        # v10: for each fail pair, the share of pass pairs it ranks above
        # (ties half); v01: for each pass pair, the share of fail pairs
        # ranked above it.
        v10 = [(bisect.bisect_left(ys, r[k]) + 0.5 * (bisect.bisect_right(ys, r[k]) - bisect.bisect_left(ys, r[k]))) / n
               for r in fail]
        v01 = [(m - bisect.bisect_right(xs, r[k]) + 0.5 * (bisect.bisect_right(xs, r[k]) - bisect.bisect_left(xs, r[k]))) / m
               for r in passed]
        return v10, v01

    def cov(u, v):
        mu, mv = sum(u) / len(u), sum(v) / len(v)
        return sum((a - mu) * (b - mv) for a, b in zip(u, v)) / (len(u) - 1)

    a10, a01 = components(0)
    b10, b01 = components(1)
    auc_a, auc_b = sum(a10) / m, sum(b10) / m
    var = ((cov(a10, a10) + cov(b10, b10) - 2 * cov(a10, b10)) / m
           + (cov(a01, a01) + cov(b01, b01) - 2 * cov(a01, b01)) / n)
    return auc_a, auc_b, auc_a - auc_b, math.sqrt(max(var, 0.0))


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
    out: dict[str, Any] = {"pairs": n, "answered": len(ans), "coverage": round(len(ans) / n, 6) if n else None,
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


def clauses_at(sweep, t) -> dict[str, Any] | None:
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


def group_aucs(rows):
    """{(stratum, case, trap): AUC} over the groups that hold answers for
    both labels."""
    groups = collections.defaultdict(list)
    for pair, p, _ in rows:
        if p is not None:
            groups[(pair["stratum"], pair["case"], pair["trap"])].append((p, pair["label"] == "fail"))
    out = {}
    for k, g in groups.items():
        a = auc(g)
        if a is not None:
            out[k] = a
    return out


def placebo_gap(real_rows, placebo_rows):
    """The placebo check: the mean real-description AUC and the mean placebo
    AUC within each (stratum, case, trap), over the groups both hold, and the
    gap between them. The gap is judged; the per-group gaps are reported."""
    real, plac = group_aucs(real_rows), group_aucs(placebo_rows)
    keys = sorted(set(real) & set(plac))
    if not keys:
        return {"groups": 0, "real_auc": None, "placebo_auc": None, "gap": None,
                "groups_under_min_gap": None, "smallest_gap": None, "ok": False}
    gaps = {k: real[k] - plac[k] for k in keys}
    r = sum(real[k] for k in keys) / len(keys)
    pl = sum(plac[k] for k in keys) / len(keys)
    # Rounded so that a gap of exactly the minimum is not lost to float error.
    gap = round(r - pl, 9)
    smallest = min(gaps, key=lambda k: gaps[k])
    return {"groups": len(keys), "real_auc": round(r, 6), "placebo_auc": round(pl, 6), "gap": round(gap, 6),
            "groups_under_min_gap": sum(1 for v in gaps.values() if round(v, 9) < PLACEBO_MIN_GAP),
            "smallest_gap": round(gaps[smallest], 6), "smallest_gap_group": "/".join(smallest),
            "ok": gap >= PLACEBO_MIN_GAP}


def within_group_auc(rows):
    """(mean AUC, its standard error with no signal, groups, pairs) over the
    (stratum, case, trap) groups that hold both labels; Nones and zeros when
    no group does. A mean within groups does not move with differences in p
    between traps, which the AUC pooled over all pairs does. The standard
    error is that of a mean of independent AUCs: sqrt(sum se_i^2) / k."""
    groups = collections.defaultdict(list)
    for pair, p, _ in rows:
        if p is not None:
            groups[(pair["stratum"], pair["case"], pair["trap"])].append((p, pair["label"] == "fail"))
    aucs, ses, n = [], [], 0
    for g in groups.values():
        a, se = auc(g), null_auc_se(g)
        if a is None or se is None:
            continue
        aucs.append(a)
        ses.append(se)
        n += len(g)
    if not aucs:
        return None, None, 0, 0
    k = len(aucs)
    return sum(aucs) / k, math.sqrt(sum(v * v for v in ses)) / k, k, n


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


def placebo_within_text(w):
    if w["gap"] is None:
        return "gap not computed: no case and trap holds answers for both labels on both"
    return ("real-description AUC %s, placebo AUC %s, gap %s, over %d case and trap groups; reported, not judged: "
            "%d groups with a gap under %.2f, smallest gap %s (%s)" % (
                fmt(w["real_auc"]), fmt(w["placebo_auc"]), fmt(w["gap"]), w["groups"],
                w["groups_under_min_gap"], PLACEBO_MIN_GAP, fmt(w["smallest_gap"]), w["smallest_gap_group"]))


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
    sets = sorted({p["set"] for p in pairs})
    set_name = opts.get("--set") or (sets[0] if len(sets) == 1 else None)
    if set_name not in ("dev", "eval"):
        die("the pairs hold sets %s; pass --set dev or --set eval" % sets)
    pairs = [p for p in pairs if p["set"] == set_name]
    # --limit scores the first N pairs of the set: a check of the harness on
    # a few pairs, never a threshold or an adoption.
    if limit is not None:
        pairs = pairs[:limit]
    if opts.get("--choose-threshold") and set_name != "dev":
        die("a threshold is chosen on the dev set only")
    if opts.get("--choose-threshold") and limit is not None:
        die("a threshold is chosen on every dev pair; --limit cannot be used with --choose-threshold")
    dest = os.path.abspath(opts["--dest"])
    os.makedirs(dest, exist_ok=True)
    rec_root = os.path.abspath(opts["--records"])
    ablations = sorted(d for d in os.listdir(rec_root)
                       if os.path.isfile(os.path.join(rec_root, d, "system-one.jsonl"))) if os.path.isdir(rec_root) else []

    errors = []
    joined: dict[str, dict[str, Any]] = {}
    counts: dict[str, dict[str, Any]] = {}
    models: set[str] = set()
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
    tinfo: dict[str, Any] | None = None
    if opts.get("--threshold-file"):
        try:
            with open(opts["--threshold-file"], encoding="utf-8") as fh:
                tinfo = json.load(fh)
        except (OSError, ValueError) as e:
            die("--threshold-file cannot be read: %s" % e)
        if not isinstance(tinfo, dict):
            die("--threshold-file does not hold a threshold: %s" % opts["--threshold-file"])
        if models and sorted(models) != sorted(tinfo.get("providers") or []):
            errors.append("the answers come from %s, the threshold was chosen on answers from %s" % (
                "; ".join(sorted(models)), "; ".join(sorted(tinfo.get("providers") or [])) or "none"))
        # The pairs that chose t are never judged again: an evaluation pair
        # whose ref, or an agent run whose key, was in the dev set stops the
        # scorer.
        dev_refs, dev_runs, dev_run_ids = tinfo.get("dev_refs"), tinfo.get("dev_runs"), tinfo.get("dev_run_ids")
        if set_name == "eval" and not (isinstance(dev_refs, list) and isinstance(dev_runs, list)
                                       and isinstance(dev_run_ids, list)):
            errors.append("the threshold file does not list the dev pairs and runs it was chosen on")
        elif set_name == "eval" and isinstance(dev_refs, list) and isinstance(dev_runs, list) \
                and isinstance(dev_run_ids, list):
            judged = [p for p in all_pairs if p["set"] == set_name]
            same_refs = sorted({p["ref"] for p in judged} & set(dev_refs))
            # A run key and a ref are built from the --out directory's name;
            # the run's own identity is not, so a dev run copied or renamed
            # and exported again is still found.
            same_runs = sorted({p["run"] for p in judged if p["stratum"] == "agent"
                                and (p["run"] in dev_runs or set(p.get("run_ids") or ()) & set(dev_run_ids))})
            no_ids = sorted({p["run"] for p in judged if p["stratum"] == "agent" and not p.get("run_ids")})
            if no_ids:
                errors.append("%d evaluation runs carry no run identity; export them again (first: %s)"
                              % (len(no_ids), no_ids[0]))
            if same_refs:
                errors.append("%d evaluation pairs were in the dev set the threshold was chosen on (first: %s)"
                              % (len(same_refs), same_refs[0]))
            if same_runs:
                errors.append("%d evaluation runs were in the dev set the threshold was chosen on (first: %s)"
                              % (len(same_runs), same_runs[0]))

    summary: dict[str, Any] = {"set": set_name, "pairs_file_sha256": pairs_sha, "pairs": len(pairs), "limit": limit,
               "unobserved_excluded": unobserved,
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
        # Judged: the real-description AUC exceeds the placebo AUC by at
        # least PLACEBO_MIN_GAP, both the mean within each stratum, case and
        # trap. The placebo AUCs (pooled, per stratum, within groups) are
        # reported with their standard errors and do not decide the check
        # on their own.
        gap = placebo_gap(rows_for("real"), rows_for("shuffled"))
        checks["placebo"] = {"ran": True, "auc": round(pooled, 6) if pooled is not None else None,
                             "per_stratum": per, "within": gap, "min_gap": PLACEBO_MIN_GAP, "ok": gap["ok"],
                             "null_se": {k: round(v, 6) if v is not None else None for k, v in se.items()}}
    else:
        checks["placebo"] = {"ran": False, "auc": None, "ok": None}
    # The direction check: the mean of the real-description AUCs within each
    # stratum, case and trap. Well below 0.5 means the answers say "would
    # fail" for the tests that pass against the same wrong version, which a
    # harness or question fault produces (the flag read the wrong way round),
    # and it is named as such rather than read as the model. The AUC pooled
    # over all pairs also moves with differences in p between traps, so it is
    # reported beside the mean and does not decide the check. Near 0.5 is
    # reported: a provider without the signal also gives it.
    real_rows = rows_for("real")
    dir_auc, dir_se, dir_groups, dir_pairs = within_group_auc(real_rows)
    dir_rows = [(p, pair["label"] == "fail") for pair, p, _ in real_rows if p is not None]
    dir_pooled, dir_pooled_se = auc(dir_rows), null_auc_se(dir_rows)
    checks["direction"] = {"auc": round(dir_auc, 6) if dir_auc is not None else None,
                           "null_se": round(dir_se, 6) if dir_se is not None else None,
                           "groups": dir_groups, "pairs": dir_pairs,
                           "pooled_auc": round(dir_pooled, 6) if dir_pooled is not None else None,
                           "pooled_null_se": round(dir_pooled_se, 6) if dir_pooled_se is not None else None,
                           "ok": None if dir_auc is None or dir_se is None
                           else dir_auc >= 0.5 - DIRECTION_SE * dir_se,
                           "near_chance": None if dir_auc is None or dir_se is None
                           else abs(dir_auc - 0.5) <= DIRECTION_SE * dir_se}
    perm_both = {s: permutation_auc(rows_for("real", s), seed, n_perm) for s in strata_names}
    perm = {s: v[0] for s, v in perm_both.items()}
    checks["permutation"] = {"per_stratum": perm, "pooled_per_stratum": {s: v[1] for s, v in perm_both.items()},
                             "permutations": n_perm,
                             "ok": all(v is None or abs(v - 0.5) <= PERMUTATION_TOLERANCE for v in perm.values())}
    # The test name removed: a large drop in AUC on agent pairs means the
    # answers lean on the name, not the code. Reported, not judged.
    if "name-stripped" in joined and "agent" in strata_names:
        real, ns = joined.get("real", {}), joined["name-stripped"]
        both = [(real[p["ref"]][0], ns[p["ref"]][0], p["label"] == "fail") for p in pairs
                if p["stratum"] == "agent" and p["ref"] in real and p["ref"] in ns
                and real[p["ref"]][0] is not None and ns[p["ref"]][0] is not None]
        diff = paired_auc_difference(both)
        checks["name_stripped"] = {"ran": True, "stratum": "agent", "pairs": len(both),
                                   "auc_real": round(diff[0], 6) if diff else None,
                                   "auc_name_stripped": round(diff[1], 6) if diff else None,
                                   "difference": round(diff[2], 6) if diff else None,
                                   "standard_error": round(diff[3], 6) if diff else None}
    else:
        checks["name_stripped"] = {"ran": False}
    # The same state sent twice: the spread is reported and never changes
    # the verdict (references/correctness-eval.md, Repeatability).
    checks["determinism"] = repeat_spread(answered_twice(joined.get("real", {}), joined.get("repeat", {})))
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
        dev_all = [p for p in all_pairs if p["set"] == "dev"]
        if any(p["stratum"] == "agent" and not p.get("run_ids") for p in dev_all):
            die("dev agent pairs carry no run identity, so a dev run exported again as the evaluation set could "
                "not be found; export the dev pairs again")
        tinfo = {"t": t, "chosen_at": now_utc(), "commit": git_head(_BIN), "set": "dev",
                 "pairs_file_sha256": pairs_sha, "providers": sorted(models),
                 "dev_refs": sorted(p["ref"] for p in dev_all),
                 "dev_runs": sorted({p["run"] for p in dev_all if p["stratum"] == "agent"}),
                 "dev_run_ids": sorted({i for p in dev_all if p["stratum"] == "agent" for i in p.get("run_ids") or ()}),
                 "placebo": checks["placebo"], "degenerate": checks["degenerate"]["any"],
                 "coverage_ok": checks["coverage"]["ok"], "permutation_ok": checks["permutation"]["ok"],
                 "direction_ok": checks["direction"]["ok"] is not False,
                 "rule": "lowest t in 0.50..0.95 at which the false-alarm Wilson upper bound is at most 5% "
                         "on dev agent pairs and on dev author pairs separately"}
        write_json(os.path.abspath(opts["--choose-threshold"]), tinfo)
    summary["threshold"] = ({k: v for k, v in tinfo.items() if k not in ("dev_refs", "dev_runs", "dev_run_ids")}
                            if tinfo else None)

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
            reasons.append("the dev set's shuffled-wrong-version placebo did not run, or the real-description AUC "
                           "did not exceed it by at least %.2f within each case and trap" % PLACEBO_MIN_GAP)
        elif not (tinfo.get("coverage_ok") is True and tinfo.get("degenerate") is False
                  and tinfo.get("permutation_ok") is True and tinfo.get("direction_ok") is True):
            verdict = "inconclusive-dev-checks"
            failed = [name for name, ok in (("coverage", tinfo.get("coverage_ok") is True),
                                            ("degenerate answers", tinfo.get("degenerate") is False),
                                            ("label permutation", tinfo.get("permutation_ok") is True),
                                            ("direction", tinfo.get("direction_ok") is True)) if not ok]
            reasons.append("the threshold was chosen on a dev set whose own checks did not pass (%s)" % ", ".join(failed))
        else:
            verdict = None
    else:
        verdict = None
    # Every check that ran on the pairs scored here gates the verdict, on
    # either set; the evaluation set is also held to the dev set's checks
    # above.
    if verdict is None and checks["placebo"]["ran"] and not checks["placebo"]["ok"]:
        verdict = "inconclusive-placebo"
        w = checks["placebo"]["within"]
        if w["gap"] is None:
            reasons.append("the placebo gap could not be computed: no case and trap holds answers for both labels "
                           "on both the real description and the shuffled-wrong-version placebo")
        else:
            reasons.append("within each case and trap the real-description AUC is %s and the shuffled-wrong-version "
                           "placebo AUC %s, a gap of %s, less than %.2f, so too much of the answer comes from the "
                           "test alone" % (fmt(w["real_auc"]), fmt(w["placebo_auc"]), fmt(w["gap"]), PLACEBO_MIN_GAP))
    if verdict is None and checks["direction"]["ok"] is False:
        verdict = "inconclusive-direction"
        reasons.append("the real-description AUC, the mean within each case and trap, is %s, more than %d "
                       "standard errors below 0.5: within the same wrong version the answers say \"would fail\" "
                       "for the tests that pass, so the question is read the wrong way round, which is a fault in "
                       "the harness or the question, not a result about the provider"
                       % (fmt(checks["direction"]["auc"]), DIRECTION_SE))
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
        if limit is not None:
            verdict = "inconclusive-limited"
            reasons.append("only the first %d pairs were scored (--limit)" % limit)
        elif set_name == "dev":
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
    md_lines = ["# System One test-discrimination measurement", "",
         "Question: if the module did what the risk row's plausible wrong version describes, would this test fail? "
         "p is the provider's probability of yes. A pair is flagged when the provider is confident the test would "
         "still pass: confidence |2p - 1| at least t and p below 0.5.", "",
         "Set: %s. Pairs scored: %d%s (%d unobserved pairs left out). Provider: %s." % (
             s["set"], s["pairs"], ", only the first %d (--limit)" % s["limit"] if s.get("limit") else "",
             s["unobserved_excluded"], ", ".join(s["providers"]) or "none"), ""]
    md_lines += ["## Measurement checks", "",
          "Each check says what the result would look like if the harness, not the model, produced it. They are read "
          "before any metric.", "",
          "| Check | Result |", "|---|---|"]
    for ab, cnt in sorted(c["count"].items()):
        md_lines.append("| Records match pairs (%s) | %s: %d pairs, %d answered, no answer %s, %d retried |" % (
            ab, "yes" if cnt["ok"] else "NO", cnt["pairs"], cnt["answered"],
            ", ".join("%s %d" % kv for kv in sorted(cnt["no_answer"].items())) or "0", cnt["retried"]))
    md_lines.append("| Coverage at least 95%% | %s (%s) |" % ("yes" if c["coverage"]["ok"] else "NO", ", ".join(
        "%s %s" % (st, fmt(c["coverage"][st], pct=True)) for st in strata_names)))
    md_lines.append("| Answers spread out (fail and pass answers not both over 80%% in one bin; both classes predicted) | %s (%s) |" % (
        "NO, degenerate" if c["degenerate"]["any"] else "yes", ", ".join(
            "%s largest bin %s" % (st, fmt(c["degenerate"][st]["largest_bin_share"], pct=True)) for st in strata_names)))
    pl = c["placebo"]
    md_lines.append("| Shuffled-wrong-version placebo: within each case and trap, the real-description AUC exceeds "
                    "the placebo AUC by at least %.2f (larger is better; a gap of 0 means the description adds nothing "
                    "to the test alone) | %s |" % (PLACEBO_MIN_GAP, "not run" if not pl["ran"] else (
        "%s (%s; placebo AUC reported, not judged: pooled %s, standard error with no signal %s; %s)" % (
            "yes" if pl["ok"] else "NO", placebo_within_text(pl["within"]), fmt(pl["auc"]),
            fmt(pl["null_se"]["pooled"]), ", ".join(
                "%s AUC %s, standard error %s" % (st, fmt(pl["per_stratum"][st]), fmt(pl["null_se"][st]))
                for st in strata_names)))))
    dr = c["direction"]
    md_lines.append("| Real-description AUC, mean within case and trap, not more than 2 standard errors below 0.5 "
                    "(below means the question is read the wrong way round) | %s |" % (
        "not computed (no case and trap has answers for both labels)" if dr["ok"] is None else
        "%s (AUC %s, standard error with no signal %s, over %d case and trap groups holding %d pairs; "
        "pooled over all pairs, reported and not judged: AUC %s, standard error %s%s)" % (
            "yes" if dr["ok"] else "NO", fmt(dr["auc"]), fmt(dr["null_se"]), dr["groups"], dr["pairs"],
            fmt(dr["pooled_auc"]), fmt(dr["pooled_null_se"]),
            "; within 2 standard errors of 0.5: the answers carry no signal on the real description, "
            "so check the harness before reading this as the provider" if dr["near_chance"] else "")))
    md_lines.append("| Label-permutation AUC, mean within case and trap, within 0.02 of 0.5 | %s (%s; pooled %s) |" % (
        "yes" if c["permutation"]["ok"] else "NO",
        ", ".join("%s %s" % (st, fmt(val)) for st, val in c["permutation"]["per_stratum"].items()),
        ", ".join("%s %s" % (st, fmt(val)) for st, val in c["permutation"]["pooled_per_stratum"].items())))
    ns = c.get("name_stripped") or {}
    md_lines.append("| Test name removed, agent pairs (reported, not judged; a drop well above its standard error means "
                    "the answers lean on the name, not the code) | %s |" % (
        "not run" if not ns.get("ran") else "AUC %s with the name, %s without; drop %s, standard error %s, over %d "
        "pairs answered both ways" % (fmt(ns["auc_real"]), fmt(ns["auc_name_stripped"]), fmt(ns["difference"]),
                                      fmt(ns["standard_error"]), ns["pairs"])))
    d = c["determinism"]
    md_lines.append("| Same state sent twice: how far apart the two answers are (smaller is better; reported, not "
                    "judged) | %s |" % spread_sentence(d))
    tr = c["truncation"]
    md_lines.append("| States over a provider's cap | %d over imajev's 7,000 tokens, %d over TypeSafe's 28,000 (largest %d bytes) |" % (
        tr["states_over_imajev_cap"], tr["states_over_typesafe_cap"], tr["largest_state_bytes"]))
    if s.get("threshold"):
        th = s["threshold"]
        md_lines.append("| Threshold fixed on the dev set before the evaluation records | t = %s, chosen %s at commit %s |" % (
            fmt(th.get("t"), digits=2), th.get("chosen_at"), th.get("commit")))
    md_lines += ["", "## Adoption bar", "",
          "Verdict: **%s**. %s" % (v["verdict"], " ".join(r[0].upper() + r[1:] + "." for r in v["reasons"])), ""]
    cl = v.get("clauses")
    if cl:
        fa, hn = cl["false_alarm"], cl["hn_recall"]
        md_lines += ["On agent-written pairs at t = %.2f:" % cl["t"], "",
              "1. Tests that do fail against the wrong version, flagged as if they would pass: %d of %d (Wilson 95%% upper "
              "bound %s; must be at most 5%%; lower is better): %s." % (fa["k"], fa["n"], fmt(fa["wilson_upper"], pct=True),
                                                                   "holds" if fa["holds"] else "does not hold"),
              "2. Hard negatives (tests that pass against this wrong version but fail another) flagged: %d of %d (Wilson "
              "95%% lower bound %s; must be at least 30%%; higher is better): %s." % (
                  hn["k"], hn["n"], fmt(hn["wilson_lower"], pct=True), "holds" if hn["holds"] else "does not hold"), ""]
    md_lines += ["## Results per stratum", "",
          "Accuracy and balanced accuracy read p at 0.5. AUC: 0.5 is chance, 1.0 is perfect ordering of fail above pass. "
          "Brier: lower is better. Brier skill: above 0 beats always answering the base rate.", "",
          "| Stratum | Ablation | Pairs | Coverage | Fail / pass (hard negatives) | Accuracy (constant) | Balanced accuracy | AUC | Brier (constant) | Brier skill |",
          "|---|---|---|---|---|---|---|---|---|---|"]
    for st in strata_names:
        for ab, m in sorted(s["strata"][st].items()):
            cp = m.get("constant_predictor") or {}
            md_lines.append("| %s | %s | %d | %s | %d / %d (%d) | %s (%s) | %s | %s | %s (%s) | %s |" % (
                st, ab, m["pairs"], fmt(m["coverage"], pct=True), m["fail"], m["pass"], m["hn_behavioral"],
                fmt(m["accuracy"], pct=True), fmt(cp.get("accuracy"), pct=True), fmt(m["balanced_accuracy"], pct=True),
                fmt(m["auc"]), fmt(m["brier"]), fmt(cp.get("brier")), fmt(m["brier_skill"])))
    md_lines += ["", "## Per case (real descriptions)", "",
          "| Stratum | Case | Pairs | Coverage | Fail pairs | AUC | Note |", "|---|---|---|---|---|---|---|"]
    for st in strata_names:
        for case, m in s["per_case"][st].items():
            md_lines.append("| %s | %s | %d | %s | %d | %s | %s |" % (
                st, case, m["pairs"], fmt(m["coverage"], pct=True), m["fail"], fmt(m["auc"]),
                "fewer than 20 fail pairs: cannot carry the verdict alone" if m["fail"] < MIN_FAIL_PAIRS_PER_CASE else ""))
    for st in strata_names:
        md_lines += ["", "## Threshold sweep, %s pairs" % st, "",
              "| t | Fail pairs flagged (lower is better) | Wilson upper | Hard negatives flagged (higher is better) | Wilson lower | All pass pairs flagged (reported) | Wilson lower, upper |",
              "|---|---|---|---|---|---|---|"]
        for key, row in s["sweep"][st].items():
            fa, hn, ps = row["false_alarm"], row["hn_recall"], row["pass_flagged"]
            md_lines.append("| %s | %d of %d | %s | %d of %d | %s | %d of %d | %s, %s |" % (
                key, fa["k"], fa["n"], fmt(fa["wilson_upper"], pct=True), hn["k"], hn["n"],
                fmt(hn["wilson_lower"], pct=True), ps["k"], ps["n"], fmt(ps["wilson_lower"], pct=True),
                fmt(ps["wilson_upper"], pct=True)))
        rel = s["strata"][st].get("real", {}).get("reliability")
        if rel:
            md_lines += ["", "Reliability, %s pairs (a calibrated provider has fail rate close to mean p in each bin):" % st, "",
                  "| p bin | Pairs | Mean p | Fail rate |", "|---|---|---|---|"]
            for b in rel:
                md_lines.append("| %s | %d | %s | %s |" % (b["bin"], b["n"], fmt(b["mean_p"]), fmt(b["fail_rate"])))
    md_lines += ["", "## Appendix: five states", "",
          "Each state below is what the provider received for that pair. It should show the test and the risk row's "
          "wrong version, and no hidden test name other than the test's own.", ""]
    for smp in c["sample"]:
        md_lines.append("### %s" % smp["ref"])
        md_lines.append("")
        md_lines.append("sha256 %s, record matches: %s" % (smp["sha256"], "yes" if smp["record_sha256_matches"] else "no"))
        md_lines.append("")
        if smp["state"]:
            md_lines.append("```json")
            md_lines.append(json.dumps({"risk": smp["state"]["risk"], "test": smp["state"]["test"]}, indent=2, ensure_ascii=False))
            md_lines.append("```")
            md_lines.append("")
    if d["pairs"]:
        md_lines += ["## Same state sent twice", "",
                     "Each pair below was sent twice with the same state. The difference is how far apart the two "
                     "answers are; smaller is better, and 0 means the provider gave the same p both times. It is "
                     "reported and does not change the verdict.", "",
                     "| Pair | First answer | Second answer | Difference |", "|---|---|---|---|"]
        for row in d["per_pair"]:
            md_lines.append("| %s | %s | %s | %s |" % (row["ref"], fmt(row["first"]), fmt(row["second"]),
                                                    fmt(row["difference"])))
        md_lines.append("")
    return "\n".join(md_lines) + "\n"


def answered_twice(real, repeat):
    """(ref, first p, second p) for every ref answered in both, sorted by
    ref. A record with no answer on either side is left out."""
    return [(ref, real[ref][0], v[0]) for ref, v in sorted(repeat.items())
            if v[0] is not None and ref in real and real[ref][0] is not None]


def repeat_spread(twice) -> dict[str, Any]:
    """The difference between the two answers of each pair sent twice, and
    over all of them the largest, the mean, and how many differ by more than
    REPEAT_REPORT_LINE. Smaller is better. A report, never a check."""
    per_pair = [{"ref": ref, "first": round(a, 6), "second": round(b, 6), "difference": round(abs(a - b), 6)}
                for ref, a, b in twice]
    diffs = [abs(a - b) for _, a, b in twice]
    return {"pairs": len(per_pair),
            "over_0.02": sum(1 for x in diffs if x > REPEAT_REPORT_LINE) if diffs else None,
            "largest_difference": round(max(diffs), 6) if diffs else None,
            "mean_difference": round(sum(diffs) / len(diffs), 6) if diffs else None,
            "per_pair": per_pair}


def spread_sentence(d):
    if not d["pairs"]:
        return "not measured: no pair was answered twice"
    return ("%d pairs; the two answers differ by %s at most and %s on average; %d differ by more than 0.02"
            % (d["pairs"], fmt(d["largest_difference"]), fmt(d["mean_difference"]), d["over_0.02"]))


# ====================================================================== smoke

SMOKE_REFS = os.path.join(_BIN, "..", "evals", "s1-discrimination", "smoke-refs.txt")


def cmd_smoke(args):
    """Before the dev replay: hand-picked obvious catches must get p above
    0.5 and obvious non-catches p below it. A failure here is a fault in the
    harness, the question or the settings, found before 1,549 pairs are
    sent. The pairs sent twice are reported with the difference between
    their two answers; that spread comes from the provider and never makes
    the smoke check fail."""
    opts = parse_args(args, ("--pairs", "--records", "--refs"))
    for k in ("--pairs", "--records"):
        if not opts.get(k):
            die("s1-smoke --pairs P --records R [--refs F]")
    pairs = select_refs(load_pairs(os.path.abspath(opts["--pairs"])), read_refs(opts.get("--refs") or SMOKE_REFS))
    rec_root = os.path.abspath(opts["--records"])
    problems = []
    real_recs = read_records(os.path.join(rec_root, "real", "system-one.jsonl"))
    for r in real_recs:
        r["_ablation"] = "real"
    real, errs = join(pairs, real_recs, expected_all=True)
    problems += ["real: %s" % e for e in errs]
    rows = []
    for p in pairs:
        ans = real.get(p["ref"])
        pv = ans[0] if ans else None
        if pv is None:
            ok = False
            problems.append("%s (%s): no answer (%s)" % (p["ref"], p["label"], ans[1] if ans else "no record"))
        else:
            ok = pv > 0.5 if p["label"] == "fail" else pv < 0.5
            if not ok:
                problems.append("%s: label %s but p = %s, the wrong side of 0.5" % (p["ref"], p["label"], fmt(pv)))
        rows.append({"ref": p["ref"], "label": p["label"], "p": pv, "ok": ok})
    rep_recs = read_records(os.path.join(rec_root, "repeat", "system-one.jsonl"))
    for r in rep_recs:
        r["_ablation"] = "real"
    repeat, errs = join(pairs, rep_recs, expected_all=False)
    problems += ["repeat: %s" % e for e in errs]
    spread = repeat_spread(answered_twice(real, repeat))
    out = {"ok": not problems, "pairs": rows, "sent_twice": spread["pairs"], "repeatability": spread,
           "problems": problems}
    print(json.dumps(out, indent=2, sort_keys=True))
    for e in problems[:10]:
        sys.stderr.write("flow-s1-eval: smoke: %s\n" % e)
    sys.stderr.write("flow-s1-eval: smoke: same state sent twice (smaller is better; reported, does not stop): %s\n"
                     % spread_sentence(spread))
    for row in spread["per_pair"]:
        sys.stderr.write("flow-s1-eval: smoke:   %s: %s then %s, difference %s\n"
                         % (row["ref"], fmt(row["first"]), fmt(row["second"]), fmt(row["difference"])))
    return 0 if not problems else 1


COMMANDS = {"s1-pairs": cmd_pairs, "s1-replay": cmd_replay, "s1-score": cmd_score, "s1-smoke": cmd_smoke}
