#!/usr/bin/env python3
"""Grading and aggregation helper for plugins/flow/bin/flow-eval-run.sh.

Standard library only. Every subcommand prints JSON to stdout unless noted.

  case-meta   <case-dir>                      prompt.md frontmatter as key=value lines
  case-prompt <case-dir> --arm <arm>          prompt body; the <!-- flow-only --> block is
                                              removed for the baseline arm
  parse-unittest <file>                       per-test status from `unittest -v` output
  hidden-run  --case-dir D --project-dir P    run hidden/test_hidden.py against the
              [--impl FILE] [--timeout S]     module in P (or against --impl copied in);
              [--out hidden.txt]              a trap counts as caught when the run fails
              [--raw hidden.txt]              every test listed for it in traps.json;
                                              --raw scores a saved output instead of
                                              running (an incomplete run is scored over
                                              the suite's full size, see below)
  agent-tests --project-dir P                 count the agent's own tests and classify
                                              their literal sequence inputs
  own-test-traps --case-dir C --project-dir P run the agent's own suite (tests/, unittest
              [--timeout S] [--out FILE]      discover) against its implementation and
                                              against every hidden/traps/*.py variant;
                                              a trap is caught when a test that passes on
                                              the agent's module fails on the variant
  rescore-hidden --out DIR --evals-dir E      re-run the hidden suite against every run's
              [--timeout S]                   project/ snapshot (after a suite correction);
                                              rewrites hidden.txt and result.json's hidden/traps
  rescore-own-tests --out DIR --evals-dir E   redo own-test trap scoring for every run under
              [--timeout S]                   DIR that kept a project/ snapshot (rewrites
                                              own-test-traps.json and result.json fields)
  finalize-run --run-dir R --case-dir C       parse stream.jsonl, grade, write result.json,
              --project-dir P --arm A         hidden.txt, agent-tests-summary.json,
              --case NAME --run N --exit-code X   own-test-traps.json and project/ (snapshot
              [--model-requested M]           of the agent's module and tests)
              [--timed-out] [--duration S] [--temp-dir T]
  aggregate   --out DIR                       summary.json + summary.md from DIR/runs,
                                              grouped by model (runs/<model>/<arm>/<case>/<n>;
                                              the older runs/<arm>/<case>/<n> layout is read too)
  migrate-layout --out DIR                    move runs/<arm>/<case>/<n> into
                                              runs/<model>/<arm>/<case>/<n> (model from
                                              claude.json modelUsage) and stamp `model`
                                              into each result.json; idempotent
  check-cases --evals-dir DIR [--case NAME]   reference passes, every trap variant fails
              [--mode correctness|review]     its listed tests; exit 1 on any violation.
              [--no-write]                    --mode review instead requires every variant to
                                              differ from hidden/reference_impl.py and records
                                              its changed hunks into traps.json as changed_lines
  score-review --case DIR --trap NAME         score one review run's findings (a file or an
              --findings FILE|JSON            inline JSON array) against the reference->variant
                                              diff: hit, false findings, incomplete + reason
  review-prompt <case-dir>                    the review prompt for one scratch repository
  list-traps <case-dir>                       trap names, one per line
  materialize-variant --case DIR --trap NAME  the reference's source with the variant's
              [--out FILE]                    redefinitions folded in, which is what a review
                                              run's feature branch commits
  reference-module --case DIR [--out FILE]    the reference as the default branch commits it
  variant-delegates --case DIR --trap NAME    yes/no: does the materialized variant still call
                                              into reference_impl, so the scratch repository
                                              must carry reference_impl.py beside the module
  finalize-review-run --run-dir R             parse stream.jsonl, score the findings block,
              --case-dir C --arm A --case N   write findings.txt, review-score.json, result.json
              --trap T --run N --exit-code X

Incomplete runs: a unittest run is complete only when it prints `Ran N tests`
for exactly the N tests observed and a final `OK`/`FAILED` line. When it does
not (timeout, crash, or no summary), the hidden pass rate is observed `ok`
lines over the suite's full size from hidden/test_hidden.py, never over the
tests that happened to print a status; result.json records
hidden.incomplete=true with reason timeout|crash|no-summary and the
observed/expected counts, and the aggregate tables carry an Incomplete
column. Own-test scoring applies the same rule: an incomplete run against a
trap variant counts as a catch only for an oracle test observed to FAIL or
ERROR, and a test not observed passing is not an oracle.

Degenerate-input heuristic (agent-tests): an input is a literal sequence —
a bytes constant, a list/tuple display whose elements are constants (or
nested literal sequences), or `<literal> * n` — that a `test_*` function (or
setUp) passes directly as an argument to a call other than an assert*
method, or assigns to a variable. Expected values inside assertEqual(...)
are not inputs. An input is degenerate when empty, single-element, all
elements identical, or a palindrome of length >= 2. str constants are
ignored (mostly keys and messages) and computed inputs (`bytes(range(10))`,
comprehensions) are not classified at all.
"""
import ast
import difflib
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

# PYTHONSAFEPATH is exported by the runner, but this helper is also called
# directly from tests and by hand. An empty or "." entry on sys.path makes the
# import of a standard-library name depend on the current directory, and the
# current directory here is an agent's scratch project.
sys.path[:] = [entry for entry in sys.path if entry not in ("", ".")]

PLUGIN_ARMS = ("enforce-risk", "enforce-norisk", "suggest-risk", "suggest-norisk", "off-risk", "off-norisk")
ALL_ARMS = ("baseline",) + PLUGIN_ARMS

# Frontmatter keys the runner understands (the official `claude plugin eval`
# layout). Scalars only; lists are passed through as JSON.
FRONTMATTER_KEYS = ("name", "tags", "runs", "max_turns", "timeout_seconds", "allowed_tools", "model", "scaffold_script")


def die(msg, code=2):
    sys.stderr.write("_flow_eval: %s\n" % msg)
    sys.exit(code)


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


def write_summaries(out_dir, summary, markdown):
    """summary.json and summary.md, each replaced whole. The markdown is rendered
    before anything is written, so a render that fails leaves both files as
    they were instead of a new summary.json beside a truncated summary.md."""
    write_json(os.path.join(out_dir, "summary.json"), summary)
    path = os.path.join(out_dir, "summary.md")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(markdown)
    os.replace(tmp, path)


# ---------------------------------------------------------------- frontmatter

def parse_frontmatter(text):
    """Return (meta dict, body). Minimal YAML: `key: value`, flow lists `[a, b]`."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}, text
    meta = {}
    for line in text[4:end].splitlines():
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            items = [v.strip().strip("'\"") for v in value[1:-1].split(",")]
            meta[key] = [v for v in items if v]
        else:
            meta[key] = value.strip("'\"")
    return meta, text[end + 5:]


def cmd_case_meta(args):
    if len(args) != 1:
        die("case-meta <case-dir>")
    meta, _ = parse_frontmatter(read_text(os.path.join(args[0], "prompt.md")))
    for key in FRONTMATTER_KEYS:
        if key in meta:
            value = meta[key]
            if isinstance(value, list):
                value = json.dumps(value)
            print("%s=%s" % (key, value))


FLOW_ONLY_RE = re.compile(r"<!--\s*flow-only\s*-->.*?<!--\s*/flow-only\s*-->\s*", re.S)


def case_prompt(case_dir, arm):
    _, body = parse_frontmatter(read_text(os.path.join(case_dir, "prompt.md")))
    if arm == "baseline":
        body = FLOW_ONLY_RE.sub("", body)
    else:
        body = re.sub(r"<!--\s*/?flow-only\s*-->\n?", "", body)
    return body.strip() + "\n"


def cmd_case_prompt(args):
    opts = parse_opts(args, ["--arm"])
    if len(opts["_"]) != 1 or not opts.get("--arm"):
        die("case-prompt <case-dir> --arm <arm>")
    sys.stdout.write(case_prompt(opts["_"][0], opts["--arm"]))


# ------------------------------------------------------------ unittest output

STATUS_WORDS = ("ok", "FAIL", "ERROR", "skipped", "expected failure", "unexpected success")
TEST_LINE_RE = re.compile(r"^(test\w*) \(([\w.]+)\)")
STATUS_RE = re.compile(r"\.\.\. (ok|FAIL|ERROR|skipped(?: .*)?|expected failure|unexpected success)\s*$")
RAN_RE = re.compile(r"^Ran (\d+) tests? in ")
SUMMARY_RE = re.compile(r"^(OK|FAILED)(?: \(.*\))?\s*$")
TIMEOUT_MARK_RE = re.compile(r"^\[flow-eval\] .* timed out after ", re.M)
# A crash inside a test prints the traceback on the pending test's own line
# (`test_x (...) ... Traceback (most recent call last):`), so that pattern is
# not anchored; the signal messages are.
CRASH_RE = re.compile(r"Traceback \(most recent call last\):|^(?:Segmentation fault|Bus error|Killed|Fatal Python error)\b", re.M)


def parse_unittest(text, full_ids=False):
    """Parse `python -m unittest -v` output. Returns {tests:{id:status}, passed, total, ...}.

    Handles the docstring layout, where the status lands on the line after the
    test id, and treats a test whose status never appears (crash, timeout) as
    an error. Keys are the bare method names (the hidden suites never repeat
    one); with ``full_ids`` the key is ``module.Class.method`` so an agent
    suite that reuses a method name across classes is counted per test.
    ``completed`` is true only when the `Ran N tests` line names exactly the
    observed count and the final `OK`/`FAILED` line is present.
    """
    tests = {}
    order = []
    pending = None
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        m = TEST_LINE_RE.match(line)
        if m:
            test_id = m.group(1)
            if full_ids:
                qualname = m.group(2)
                test_id = qualname if qualname.endswith("." + test_id) else qualname + "." + test_id
            if test_id not in tests:
                order.append(test_id)
            tests[test_id] = "missing"
            pending = test_id
            s = STATUS_RE.search(line)
            if s:
                tests[test_id] = normalize_status(s.group(1))
                pending = None
            continue
        if pending is not None:
            s = STATUS_RE.search(line)
            if s:
                tests[pending] = normalize_status(s.group(1))
                pending = None
    ran = None
    summary = None
    for line in text.splitlines():
        m = RAN_RE.match(line)
        if m:
            ran = int(m.group(1))
            summary = None   # the verdict belongs to the last Ran line
            continue
        s = SUMMARY_RE.match(line.rstrip("\r"))
        if s and ran is not None:
            summary = s.group(1)
    passed = sum(1 for t in order if tests[t] == "ok")
    failed = [t for t in order if tests[t] in ("FAIL", "ERROR", "missing")]
    return {
        "tests": {t: tests[t] for t in order},
        "order": order,
        "passed": passed,
        "total": len(order),
        "failed_ids": failed,
        "ran_line": ran,
        "summary_line": summary,
        "completed": ran is not None and ran == len(order) and summary is not None,
    }


def incomplete_reason(parsed, raw, timed_out=False, returncode=None):
    """Why a unittest run did not complete: timeout | crash | no-summary, or None.

    ``timed_out`` is the subprocess verdict; a saved output carries the
    `[flow-eval] ... timed out` marker instead. A crash is a non-zero exit or
    a traceback/signal message without the `Ran N tests` line; anything else
    that lacks a matching `Ran` line and final `OK`/`FAILED` is no-summary
    (truncated output, a `sys.exit` inside the suite, a count mismatch).
    """
    if parsed["completed"]:
        return None
    if timed_out or TIMEOUT_MARK_RE.search(raw):
        return "timeout"
    if parsed["ran_line"] is None and ((returncode not in (None, 0)) or CRASH_RE.search(raw)):
        return "crash"
    return "no-summary"


def normalize_status(word):
    if word.startswith("skipped"):
        return "skipped"
    return word


def cmd_parse_unittest(args):
    if len(args) != 1:
        die("parse-unittest <file>")
    print(json.dumps(parse_unittest(read_text(args[0])), indent=2, sort_keys=True))


# ---------------------------------------------------------------- hidden run

def load_traps(case_dir):
    path = os.path.join(case_dir, "hidden", "traps.json")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def run_hidden(case_dir, project_dir, impl=None, timeout=120):
    """Run hidden/test_hidden.py with PYTHONPATH=project_dir. Returns (parsed, raw_text).

    With --impl, the module file is copied into a scratch copy of project_dir
    under the case's module name (and reference_impl.py alongside so trap
    variants can import it). The agent's directory is never modified.
    """
    case_dir = os.path.abspath(case_dir)   # the suite runs with cwd=target; relative paths would not resolve
    traps = load_traps(case_dir)
    module = traps["module"]
    scratch = None
    try:
        if impl is not None:
            scratch = tempfile.mkdtemp(prefix="flow-eval-hidden.")
            shutil.copy(impl, os.path.join(scratch, module + ".py"))
            shutil.copy(os.path.join(case_dir, "hidden", "reference_impl.py"), os.path.join(scratch, "reference_impl.py"))
            target = scratch
        else:
            target = os.path.abspath(project_dir)
        env = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
        env["PYTHONSAFEPATH"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONPATH"] = target
        env["PYTHONHASHSEED"] = "0"
        cmd = [sys.executable, os.path.join(case_dir, "hidden", "test_hidden.py"), "-v"]
        try:
            proc = subprocess.run(cmd, cwd=target, env=env, capture_output=True, text=True, timeout=timeout)
            raw = proc.stdout + proc.stderr
            timed_out = False
            returncode = proc.returncode
        except subprocess.TimeoutExpired as exc:
            raw = partial_output(exc) + "\n[flow-eval] hidden suite timed out after %ss\n" % timeout
            timed_out = True
            returncode = None
    finally:
        if scratch is not None:
            shutil.rmtree(scratch, ignore_errors=True)
    return score_hidden(case_dir, raw, timed_out, returncode), raw


def partial_output(exc):
    """stdout + stderr captured before a subprocess.TimeoutExpired.

    CPython attaches the partial streams as bytes even in text mode, and as
    None for a stream the child never wrote to (unittest writes only to
    stderr), so each part is decoded on its own.
    """
    parts = []
    for chunk in (exc.stdout, exc.stderr):
        if chunk is None:
            continue
        if isinstance(chunk, bytes):
            chunk = chunk.decode("utf-8", "replace")
        parts.append(chunk)
    return "".join(parts)


def score_hidden(case_dir, raw, timed_out=False, returncode=None):
    """Score a hidden-suite output (from run_hidden or a saved hidden.txt).

    A complete run is scored over the tests it reports. An incomplete run
    (timeout, crash, no summary line) is scored as observed `ok` lines over
    the suite's full size from hidden/test_hidden.py: a suite that hangs on
    test 5 of 30 after four passes scores 4/30, not 4/5. The unobserved
    tests are listed under `unobserved` and counted in `failed_ids`.
    """
    traps = load_traps(case_dir)
    parsed = parse_unittest(raw)
    parsed["timed_out"] = timed_out
    suite_ids = hidden_test_ids(case_dir)
    expected_ids = sorted({t for trap in traps["traps"].values() for t in trap["discriminating_tests"]})
    parsed["observed"] = parsed["total"]
    parsed["expected"] = len(suite_ids)
    parsed["incomplete"] = not parsed["completed"]
    parsed["reason"] = incomplete_reason(parsed, raw, timed_out, returncode)
    # Import failure or crash before any test ran: score 0 over the known suite size.
    parsed["import_or_crash"] = parsed["total"] == 0
    if parsed["incomplete"]:
        unobserved = [t for t in suite_ids if t not in parsed["tests"]]
        parsed["unobserved"] = unobserved
        parsed["total"] = max(parsed["expected"], parsed["observed"])
        parsed["failed_ids"] = parsed["failed_ids"] + unobserved
    else:
        parsed["unobserved"] = []
    parsed["pass_rate"] = (parsed["passed"] / parsed["total"]) if parsed["total"] else 0.0
    parsed["all_pass"] = parsed["total"] > 0 and parsed["passed"] == parsed["total"]
    # Signature match: a trap is "caught" when the run fails every test its
    # variant fails (traps.json discriminating_tests). Some signatures are
    # subsets of others (a tie-order test also fails under a rounding trap), so a
    # run can match several traps; an import failure matches all of them, and
    # a test the run never reached counts as not passed (the same pessimistic
    # reading as the pass rate; `unobserved` says which).
    parsed["traps"] = {}
    for name, trap in traps["traps"].items():
        ids = trap["discriminating_tests"]
        statuses = [parsed["tests"].get(t, "missing") for t in ids]
        failing = [t for t, s in zip(ids, statuses) if s != "ok"]
        tripped = parsed["import_or_crash"] or (bool(ids) and len(failing) == len(ids))
        parsed["traps"][name] = {
            "caught": tripped,
            "failing": list(ids) if parsed["import_or_crash"] else failing,
            "unobserved": [t for t in ids if t not in parsed["tests"]],
        }
    parsed["mapped_test_ids"] = expected_ids
    return parsed


HIDDEN_RECORD_KEYS = ("passed", "total", "pass_rate", "all_pass", "failed_ids", "import_or_crash", "timed_out",
                      "incomplete", "reason", "observed", "expected")


def hidden_record(hidden):
    """The `hidden` block of result.json."""
    return {key: hidden[key] for key in HIDDEN_RECORD_KEYS}


def hidden_test_ids(case_dir):
    """Bare method names of every test_* function in hidden/test_hidden.py, in file order."""
    tree = ast.parse(read_text(os.path.join(case_dir, "hidden", "test_hidden.py")))
    return [node.name for node in ast.walk(tree)
            if isinstance(node, ast.FunctionDef) and node.name.startswith("test")]


def count_hidden_tests(case_dir):
    return len(hidden_test_ids(case_dir))


def cmd_hidden_run(args):
    opts = parse_opts(args, ["--case-dir", "--project-dir", "--impl", "--timeout", "--out", "--raw"])
    if not opts.get("--case-dir") or not (opts.get("--project-dir") or opts.get("--impl") or opts.get("--raw")):
        die("hidden-run --case-dir D (--project-dir P | --impl FILE | --raw OUTPUT) [--timeout S] [--out FILE]")
    if opts.get("--raw"):
        raw = read_text(opts["--raw"])
        parsed = score_hidden(opts["--case-dir"], raw, timed_out=bool(TIMEOUT_MARK_RE.search(raw)))
    else:
        parsed, raw = run_hidden(opts["--case-dir"], opts.get("--project-dir") or ".", opts.get("--impl"),
                                 int(opts.get("--timeout") or 120))
        if opts.get("--out"):
            with open(opts["--out"], "w", encoding="utf-8") as fh:
                fh.write(raw)
    print(json.dumps(parsed, indent=2, sort_keys=True))


# ------------------------------------------------------------ agent's tests

def is_literal_sequence(node):
    """Return a python value for a literal sequence node, or None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, (bytes, bytearray)):
        return list(node.value)
    if isinstance(node, (ast.List, ast.Tuple)):
        out = []
        for elt in node.elts:
            if isinstance(elt, ast.Constant) and not isinstance(elt.value, (bytes, bytearray)):
                out.append(("c", elt.value))
            else:
                nested = is_literal_sequence(elt)
                if nested is None:
                    return None
                out.append(("s", tuple(nested)))
        return out
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mult):
        left, right = node.left, node.right
        if isinstance(right, ast.Constant) and isinstance(right.value, int) and not isinstance(right.value, bool):
            base = is_literal_sequence(left)
            if base is not None and right.value >= 0:
                return base * right.value
        if isinstance(left, ast.Constant) and isinstance(left.value, int) and not isinstance(left.value, bool):
            base = is_literal_sequence(right)
            if base is not None and left.value >= 0:
                return base * left.value
    return None


def classify_sequence(seq):
    if len(seq) == 0:
        return "empty"
    if len(seq) == 1:
        return "single"
    if all(x == seq[0] for x in seq):
        return "identical"
    if seq == seq[::-1]:
        return "palindrome"
    return "distinct"


def render(node):
    try:
        return ast.unparse(node)
    except Exception:  # pragma: no cover - ast.unparse exists on 3.9+
        return "<literal>"


def is_assert_call(call):
    func = call.func
    if isinstance(func, ast.Attribute):
        return func.attr.startswith("assert")
    if isinstance(func, ast.Name):
        return func.id.startswith("assert")
    return False


def analyze_test_file(path):
    """Count test functions and classify the literal sequence inputs they feed to code.

    An input is a literal sequence that is either a direct argument (positional
    or keyword) of a call whose callee is not an assert* method, or the right
    hand side of an assignment. Expected values inside assertEqual(...) and
    literals in other positions are not inputs and are not counted.
    """
    tree = ast.parse(read_text(path), filename=path)
    functions = 0
    inputs = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        is_test = node.name.startswith("test")
        if is_test:
            functions += 1
        if not (is_test or node.name in ("setUp", "setUpClass")):
            continue
        candidates = []
        for sub in ast.walk(node):
            if isinstance(sub, ast.Call) and not is_assert_call(sub):
                candidates.extend(sub.args)
                candidates.extend(kw.value for kw in sub.keywords)
            elif isinstance(sub, ast.Assign):
                candidates.append(sub.value)
        for cand in candidates:
            seq = is_literal_sequence(cand)
            if seq is None:
                continue
            inputs.append({
                "test": node.name,
                "line": getattr(cand, "lineno", 0),
                "literal": render(cand)[:80],
                "length": len(seq),
                "kind": classify_sequence(seq),
            })
    return functions, inputs


def find_agent_test_files(project_dir):
    files = []
    for root, dirs, names in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d not in (".git", ".claude", ".flow", ".decisions", "__pycache__", "hidden")]
        for name in names:
            if re.match(r"^(test_.*|.*_test)\.py$", name) and name != "test_hidden.py":
                files.append(os.path.join(root, name))
    return sorted(files)


def analyze_agent_tests(project_dir):
    files = find_agent_test_files(project_dir)
    total_functions = 0
    inputs = []
    per_file = {}
    for path in files:
        try:
            functions, found = analyze_test_file(path)
        except SyntaxError as exc:
            per_file[os.path.relpath(path, project_dir)] = {"error": "syntax error: %s" % exc}
            continue
        rel = os.path.relpath(path, project_dir)
        per_file[rel] = {"test_functions": functions, "literal_inputs": len(found)}
        total_functions += functions
        for item in found:
            item["file"] = rel
        inputs.extend(found)
    degenerate = [i for i in inputs if i["kind"] != "distinct"]
    by_kind = {}
    for i in inputs:
        by_kind[i["kind"]] = by_kind.get(i["kind"], 0) + 1
    return {
        "files": [os.path.relpath(p, project_dir) for p in files],
        "file_count": len(files),
        "test_functions": total_functions,
        "literal_inputs": len(inputs),
        "degenerate_inputs": len(degenerate),
        "degenerate_share": (len(degenerate) / len(inputs)) if inputs else None,
        "by_kind": by_kind,
        "per_file": per_file,
        "degenerate_examples": [
            {"file": i["file"], "test": i["test"], "line": i["line"], "kind": i["kind"], "literal": i["literal"]}
            for i in degenerate[:25]
        ],
    }


def cmd_agent_tests(args):
    opts = parse_opts(args, ["--project-dir"])
    if not opts.get("--project-dir"):
        die("agent-tests --project-dir P")
    print(json.dumps(analyze_agent_tests(opts["--project-dir"]), indent=2, sort_keys=True))


# ------------------------------------------------------- own tests vs traps

OWN_TEST_COMMAND = [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", ".", "-v"]
SNAPSHOT_SKIP_DIRS = (".git", ".claude", ".flow", ".flow-state", ".decisions", "__pycache__", "node_modules")


def snapshot_project(project_dir, dest):
    """Copy the agent's project (minus VCS, plugin state and caches) to dest."""
    def ignore(_dir, names):
        return [n for n in names if n in SNAPSHOT_SKIP_DIRS or n.endswith(".pyc")]
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(project_dir, dest, ignore=ignore, symlinks=True)
    return dest


def module_names_used_by_tests(test_files, module):
    """Return (imports_module, names) — whether any test file imports ``module`` and
    the attribute / from-import names it takes from it."""
    imports = False
    names = set()
    aliases = set()
    for path in test_files:
        try:
            tree = ast.parse(read_text(path), filename=path)
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == module or alias.name.startswith(module + "."):
                        imports = True
                        aliases.add((alias.asname or alias.name).split(".")[0])
            elif isinstance(node, ast.ImportFrom):
                if node.module == module or (node.module or "").startswith(module + "."):
                    imports = True
                    for alias in node.names:
                        if alias.name != "*":
                            names.add(alias.name)
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id in aliases:
                names.add(node.attr)
    return imports, sorted(names)


def public_names_defined(path, seen=None, search_dirs=()):
    """Top-level names a variant module defines, following `from x import *`.

    A star-imported sibling is looked up next to ``path`` and then in
    ``search_dirs`` (the case's hidden/ directory, where reference_impl.py
    lives while the variants sit in hidden/traps/).
    """
    seen = seen or set()
    if path in seen or not os.path.exists(path):
        return set()
    seen.add(path)
    try:
        tree = ast.parse(read_text(path), filename=path)
    except SyntaxError:
        return set()
    names = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                for leaf in ast.walk(target):
                    if isinstance(leaf, ast.Name):
                        names.add(leaf.id)
        elif isinstance(node, (ast.AnnAssign, ast.AugAssign)) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                names.add((alias.asname or alias.name).split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name == "*":
                    filename = (node.module or "") + ".py"
                    for base in (os.path.dirname(path),) + tuple(search_dirs):
                        sibling = os.path.join(base, filename)
                        if os.path.exists(sibling):
                            names |= {n for n in public_names_defined(sibling, seen, search_dirs) if not n.startswith("_")}
                            break
                else:
                    names.add(alias.asname or alias.name)
    return names


def run_own_suite(project_copy, timeout):
    """Run the agent's suite the way the agent did. Returns (parsed, raw)."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["PYTHONHASHSEED"] = "0"
    env["PYTHONPATH"] = project_copy
    try:
        proc = subprocess.run(OWN_TEST_COMMAND, cwd=project_copy, env=env, capture_output=True, text=True, timeout=timeout)
        raw = proc.stdout + proc.stderr
        timed_out = False
        returncode = proc.returncode
    except subprocess.TimeoutExpired as exc:
        raw = partial_output(exc) + "\n[flow-eval] own suite timed out after %ss\n" % timeout
        timed_out = True
        returncode = None
    parsed = parse_unittest(raw, full_ids=True)
    parsed["timed_out"] = timed_out
    parsed["incomplete"] = not parsed["completed"]
    parsed["reason"] = incomplete_reason(parsed, raw, timed_out, returncode)
    return parsed, raw


def own_run_record(parsed):
    """The fields of one own-suite run kept in own-test-traps.json."""
    return {
        "passed": parsed["passed"], "total": parsed["total"], "failed_ids": parsed["failed_ids"],
        "timed_out": parsed["timed_out"], "completed": parsed["completed"],
        "incomplete": parsed["incomplete"], "reason": parsed["reason"],
    }


def own_test_traps(case_dir, project_dir, timeout=120):
    """Score the agent's own tests against every trap variant.

    A trap is caught when at least one oracle test fails (FAIL or ERROR)
    against the variant swapped in under the same module name. An oracle
    test is one that passes against the agent's own implementation AND
    against hidden/reference_impl.py: every variant inherits the reference's
    behaviour on whatever rule it does not override, so a test that already
    disagrees with the reference (a spec edge the agent read differently)
    would "catch" every variant for the wrong reason. Those tests are listed
    under `disagree_with_reference` and ignored. `catch_rate` is caught /
    traps, or None with a `reason` when the suite cannot be used as an
    oracle (no tests/ dir, no tests discovered, the module not imported by
    the tests, the tests using names the variants do not define, or no test
    passing on both implementations).

    Incomplete runs (timeout, crash, no summary line) never add evidence: a
    test is an oracle only when it was observed passing on both the agent's
    module and the reference, and a variant is caught only by an oracle test
    observed to FAIL or ERROR against it — a test the variant run never
    reached, or that was pending when it stopped, is not a catch. Each run's
    `incomplete`/`reason` is recorded (`own_impl`, `reference_run`,
    `per_trap.<name>`) and `incomplete_runs` counts them.
    """
    traps = load_traps(case_dir)
    module = traps["module"]
    trap_names = sorted(traps["traps"])
    result = {
        "module": module,
        "command": " ".join(["python3"] + OWN_TEST_COMMAND[1:]),
        "catch_rate": None,
        "reason": None,
        "caught": {name: None for name in trap_names},
        "per_trap": {},
        "own_impl": None,
        "incomplete_runs": 0,
    }

    def bail(reason):
        result["reason"] = reason
        return result

    tests_dir = os.path.join(project_dir, "tests")
    if not os.path.isdir(tests_dir):
        return bail("no tests/ directory in the agent's project")
    if not os.path.exists(os.path.join(project_dir, module + ".py")):
        return bail("module %s.py missing from the agent's project" % module)
    test_files = [p for p in find_agent_test_files(project_dir) if os.path.relpath(p, project_dir).startswith("tests" + os.sep)]
    if not test_files:
        return bail("no test_*.py files under tests/")
    imports_module, used_names = module_names_used_by_tests(test_files, module)
    if not imports_module:
        return bail("agent tests never import %s" % module)
    missing_by_variant = {}
    hidden_dir = os.path.join(case_dir, "hidden")
    for name in trap_names:
        variant = os.path.join(case_dir, traps["traps"][name]["variant"])
        defined = public_names_defined(variant, search_dirs=(hidden_dir,))
        missing = sorted(n for n in used_names if n not in defined)
        if missing:
            missing_by_variant[name] = missing
    if missing_by_variant:
        return bail("agent tests use names the trap variants do not define: %s" % json.dumps(missing_by_variant, sort_keys=True))

    scratch = tempfile.mkdtemp(prefix="flow-eval-own.")
    try:
        copy = os.path.join(scratch, "project")
        snapshot_project(project_dir, copy)
        own, own_raw = run_own_suite(copy, timeout)
        result["own_impl"] = own_run_record(own)
        result["own_impl_output_tail"] = own_raw[-2000:]
        result["incomplete_runs"] += 1 if own["incomplete"] else 0
        if own["total"] == 0:
            return bail("own suite discovered no tests (import error or empty tests/)")
        # Only a test observed passing is an oracle candidate; a test the run
        # never reached (hang, crash) is not.
        passing_own = [t for t in own["order"] if own["tests"][t] == "ok"]
        if not passing_own:
            return bail("no own test passes against the agent's own implementation")
        module_path = os.path.join(copy, module + ".py")
        original = read_text(module_path)
        reference = os.path.join(case_dir, "hidden", "reference_impl.py")
        shutil.copy(reference, os.path.join(copy, "reference_impl.py"))
        shutil.copy(reference, module_path)
        ref_run, _ = run_own_suite(copy, timeout)
        result["incomplete_runs"] += 1 if ref_run["incomplete"] else 0
        passing = [t for t in passing_own if ref_run["tests"].get(t, "missing") == "ok"]
        result["disagree_with_reference"] = [t for t in passing_own if ref_run["tests"].get(t) in ("FAIL", "ERROR")]
        result["unobserved_on_reference"] = [t for t in passing_own if t not in passing and t not in result["disagree_with_reference"]]
        result["reference_run"] = own_run_record(ref_run)
        if not passing:
            with open(module_path, "w", encoding="utf-8") as fh:
                fh.write(original)
            return bail("no own test passes against both the agent's implementation and the reference")
        caught_count = 0
        for name in trap_names:
            variant = os.path.join(case_dir, traps["traps"][name]["variant"])
            shutil.copy(variant, module_path)
            parsed, _ = run_own_suite(copy, timeout)
            # A catch is an oracle test observed to FAIL or ERROR on the variant.
            # On an incomplete run, tests never reached (or pending when the run
            # stopped) are not evidence either way and are listed separately.
            failing = [t for t in passing if parsed["tests"].get(t) in ("FAIL", "ERROR")]
            unobserved = [t for t in passing if parsed["tests"].get(t, "missing") == "missing"]
            caught = bool(failing)
            caught_count += 1 if caught else 0
            result["caught"][name] = caught
            result["incomplete_runs"] += 1 if parsed["incomplete"] else 0
            result["per_trap"][name] = {
                "caught": caught,
                "failing_own_tests": failing[:50],
                "failing_count": len(failing),
                "unobserved_oracle_tests": unobserved[:50],
                "unobserved_count": len(unobserved),
                "passed": parsed["passed"], "total": parsed["total"], "timed_out": parsed["timed_out"],
                "incomplete": parsed["incomplete"], "reason": parsed["reason"],
            }
        with open(module_path, "w", encoding="utf-8") as fh:
            fh.write(original)
        result["catch_rate"] = caught_count / len(trap_names) if trap_names else None
        result["caught_count"] = caught_count
        result["trap_count"] = len(trap_names)
        result["own_passing_tests"] = len(passing)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return result


def cmd_own_test_traps(args):
    opts = parse_opts(args, ["--case-dir", "--project-dir", "--timeout", "--out"])
    if not opts.get("--case-dir") or not opts.get("--project-dir"):
        die("own-test-traps --case-dir C --project-dir P [--timeout S] [--out FILE]")
    result = own_test_traps(opts["--case-dir"], opts["--project-dir"], int(opts.get("--timeout") or 120))
    if opts.get("--out"):
        write_json(opts["--out"], result)
    print(json.dumps(result, indent=2, sort_keys=True))


def rescore_own_tests(out_dir, evals_dir, timeout=120):
    """Re-run own-test trap scoring for every run that kept a project/ snapshot.

    Rewrites own-test-traps.json and the own-test fields of result.json;
    runs without a snapshot are left untouched and listed as skipped.
    """
    scored, skipped = [], []
    for run_dir, _layout in iter_run_dirs(out_dir):
        result_path = os.path.join(run_dir, "result.json")
        project = os.path.join(run_dir, "project")
        try:
            with open(result_path, encoding="utf-8") as fh:
                record = json.load(fh)
        except ValueError:
            skipped.append((run_dir, "unreadable result.json"))
            continue
        case_dir = os.path.join(evals_dir, str(record.get("case") or ""))
        if not os.path.isdir(project):
            skipped.append((run_dir, "no project/ snapshot"))
            continue
        if not os.path.isfile(os.path.join(case_dir, "hidden", "traps.json")):
            skipped.append((run_dir, "no such case under %s" % evals_dir))
            continue
        own = own_test_traps(case_dir, project, timeout)
        write_json(os.path.join(run_dir, "own-test-traps.json"), own)
        record["own_test_trap_catch_rate"] = own.get("catch_rate")
        record["own_test_traps"] = own_traps_record(own)
        write_json(result_path, record)
        scored.append((run_dir, own.get("catch_rate"), own.get("reason")))
    return scored, skipped


def rescore_hidden(out_dir, evals_dir, timeout=120):
    """Re-run the hidden suite against every run's project/ snapshot and rewrite
    hidden.txt plus the hidden/trap/module_exists fields of result.json."""
    scored, skipped = [], []
    for run_dir, _layout in iter_run_dirs(out_dir):
        result_path = os.path.join(run_dir, "result.json")
        project = os.path.join(run_dir, "project")
        try:
            with open(result_path, encoding="utf-8") as fh:
                record = json.load(fh)
        except ValueError:
            skipped.append((run_dir, "unreadable result.json"))
            continue
        case_dir = os.path.join(evals_dir, str(record.get("case") or ""))
        if not os.path.isdir(project):
            skipped.append((run_dir, "no project/ snapshot"))
            continue
        if not os.path.isfile(os.path.join(case_dir, "hidden", "traps.json")):
            skipped.append((run_dir, "no such case under %s" % evals_dir))
            continue
        hidden, raw = run_hidden(case_dir, project, None, timeout)
        with open(os.path.join(run_dir, "hidden.txt"), "w", encoding="utf-8") as fh:
            fh.write(raw)
        record["hidden"] = hidden_record(hidden)
        record["traps"] = {name: t["caught"] for name, t in hidden["traps"].items()}
        record["module_exists"] = os.path.exists(os.path.join(project, load_traps(case_dir)["module"] + ".py"))
        write_json(result_path, record)
        scored.append((run_dir, hidden["pass_rate"], hidden["reason"]))
    return scored, skipped


def own_traps_record(own):
    """The `own_test_traps` block of result.json."""
    return {"caught": own.get("caught") or {}, "reason": own.get("reason"), "own_impl": own.get("own_impl"),
            "incomplete_runs": int(own.get("incomplete_runs") or 0)}


def cmd_rescore_hidden(args):
    opts = parse_opts(args, ["--out", "--evals-dir", "--timeout"])
    if not opts.get("--out") or not opts.get("--evals-dir"):
        die("rescore-hidden --out DIR --evals-dir EVALS [--timeout S]")
    scored, skipped = rescore_hidden(opts["--out"], opts["--evals-dir"], int(opts.get("--timeout") or 120))
    for run_dir, rate, reason in scored:
        print("scored  %s  hidden_pass_rate=%.3f%s" % (os.path.relpath(run_dir, opts["--out"]), rate,
                                                    ("  incomplete=%s" % reason) if reason else ""))
    for run_dir, why in skipped:
        print("skipped %s  %s" % (os.path.relpath(run_dir, opts["--out"]), why))
    print(json.dumps({"scored": len(scored), "skipped": len(skipped)}))


def cmd_rescore_own_tests(args):
    opts = parse_opts(args, ["--out", "--evals-dir", "--timeout"])
    if not opts.get("--out") or not opts.get("--evals-dir"):
        die("rescore-own-tests --out DIR --evals-dir EVALS [--timeout S]")
    scored, skipped = rescore_own_tests(opts["--out"], opts["--evals-dir"], int(opts.get("--timeout") or 120))
    for run_dir, rate, reason in scored:
        print("scored  %s  rate=%s%s" % (os.path.relpath(run_dir, opts["--out"]), "-" if rate is None else "%.3f" % rate,
                                         ("  (%s)" % reason) if reason else ""))
    for run_dir, why in skipped:
        print("skipped %s  %s" % (os.path.relpath(run_dir, opts["--out"]), why))
    print(json.dumps({"scored": len(scored), "skipped": len(skipped)}))


# --------------------------------------------------------------- stream.jsonl

def parse_stream(path):
    """Extract the final result event and tool-use counts from a stream-json log.

    The format is Claude Code's `--output-format stream-json`; parsed
    defensively, unknown lines are skipped.
    """
    result = None
    tool_counts = {}
    skills = []
    events = 0
    if not os.path.exists(path):
        return None, tool_counts, skills, events
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            events += 1
            if not isinstance(event, dict):
                continue
            if event.get("type") == "result":
                result = event
                continue
            message = event.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = str(block.get("name", "?"))
                tool_counts[name] = tool_counts.get(name, 0) + 1
                if name == "Skill":
                    inp = block.get("input") or {}
                    skill = inp.get("skill") or inp.get("name") or inp.get("command")
                    if skill:
                        skills.append(str(skill))
    return result, tool_counts, skills, events


def agents_dispatched(path):
    """subagent_type of every Agent (or older Task) tool call in a stream-json log
    whose result did not come back as an error, in order. A call that failed
    (an unknown agent type, a refused spawn) ran nothing. A missing or
    unreadable log gives an empty list."""
    calls = []
    failed = set()
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            message = event.get("message") if isinstance(event, dict) else None
            content = message.get("content") if isinstance(message, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_result" and block.get("is_error") is True:
                    failed.add(block.get("tool_use_id"))
                    continue
                if block.get("type") != "tool_use" or block.get("name") not in ("Agent", "Task"):
                    continue
                inp = block.get("input")
                kind = inp.get("subagent_type") if isinstance(inp, dict) else None
                if kind:
                    calls.append((block.get("id"), str(kind)))
    return [kind for call_id, kind in calls if call_id is None or call_id not in failed]


def critic_ran(agents):
    """True when finding-critic, under any plugin prefix, is among the agents."""
    return any(a.split(":")[-1] == "finding-critic" for a in agents)


def models_from_result_event(result_event):
    """(primary model, all models) from a claude result event's modelUsage keys.

    The primary model is the one with the largest recorded cost (a subagent on
    another model shows up as a second key); None when there is no usage.
    """
    usage = result_event.get("modelUsage") if isinstance(result_event, dict) else None
    if not isinstance(usage, dict) or not usage:
        return None, []
    names = sorted(str(k) for k in usage)

    def cost(name):
        entry = usage.get(name)
        value = entry.get("costUSD") if isinstance(entry, dict) else None
        return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0.0
    primary = max(names, key=lambda n: (cost(n), -names.index(n)))
    return primary, names


def tokens_from_result_event(result_event):
    """Billed token counts for one run, and where they came from.

    `source` is "modelUsage" when the counts are whole-run totals summed over
    every billed model, "usage" when only the result event's top-level usage
    object carried them (the LAST REQUEST, not the run — a different scope, so
    aggregation keeps the two apart), and None when nothing was recorded.
    `entries_skipped` counts modelUsage entries that were not objects; a
    non-zero value means the totals are missing a billed model.

    Counts stay None when unrecorded rather than collapsing to zero, and
    cache_hit_rate (cache reads over all input-side tokens) is None unless the
    cache-read count itself was recorded — an unknown rate must not read as a
    confirmed 0%."""
    empty = {"input": None, "cache_read": None, "cache_creation": None, "output": None,
             "cache_hit_rate": None, "source": None, "entries_skipped": 0}
    if not isinstance(result_event, dict):
        return empty
    fields = {"input": "inputTokens", "cache_read": "cacheReadInputTokens",
              "cache_creation": "cacheCreationInputTokens", "output": "outputTokens"}
    totals = {k: None for k in fields}
    source = None
    skipped = 0
    usage = result_event.get("modelUsage")
    if isinstance(usage, dict):
        for entry in usage.values():
            if not isinstance(entry, dict):
                skipped += 1
                continue
            for key, name in fields.items():
                value = num(entry, name)
                if value is not None:
                    totals[key] = (totals[key] or 0) + value
    if any(v is not None for v in totals.values()):
        source = "modelUsage"
    else:
        top = result_event.get("usage")
        if isinstance(top, dict):
            snake = {"input": "input_tokens", "cache_read": "cache_read_input_tokens",
                     "cache_creation": "cache_creation_input_tokens", "output": "output_tokens"}
            totals = {key: num(top, name) for key, name in snake.items()}
            if any(v is not None for v in totals.values()):
                source = "usage"
    input_side = sum(totals[k] or 0 for k in ("input", "cache_read", "cache_creation"))
    totals["cache_hit_rate"] = (totals["cache_read"] / input_side) \
        if (totals["cache_read"] is not None and input_side) else None
    totals["source"] = source
    totals["entries_skipped"] = skipped
    return totals


def all_tokens(record):
    """The run's token block whatever its scope, or {} when it has none."""
    tokens = record.get("tokens")
    return tokens if isinstance(tokens, dict) else {}


def run_tokens(record):
    """The run's token block when it holds whole-run totals, else {}.

    Runs that fell back to the last request's `usage`, and runs recorded before
    the token fields existed, are excluded: averaging last-request counts with
    whole-run counts understates the cell by whatever the fallback missed."""
    tokens = all_tokens(record)
    return tokens if tokens.get("source") == "modelUsage" else {}


def cmd_finalize_run(args):
    opts = parse_opts(args, ["--run-dir", "--case-dir", "--project-dir", "--arm", "--case", "--run",
                             "--exit-code", "--duration", "--temp-dir", "--hidden-timeout", "--model-requested",
                             "--effort-requested", "--own-timeout"],
                      flags=["--timed-out"])
    for key in ("--run-dir", "--case-dir", "--project-dir", "--arm", "--case", "--run"):
        if not opts.get(key):
            die("finalize-run missing %s" % key)
    run_dir = opts["--run-dir"]
    os.makedirs(run_dir, exist_ok=True)
    stream_path = os.path.join(run_dir, "stream.jsonl")
    result_event, tool_counts, skills, events = parse_stream(stream_path)
    if result_event is not None:
        write_json(os.path.join(run_dir, "claude.json"), result_event)
    model, models_used = models_from_result_event(result_event)
    tokens = tokens_from_result_event(result_event)

    hidden, raw = run_hidden(opts["--case-dir"], opts["--project-dir"], None, int(opts.get("--hidden-timeout") or 120))
    with open(os.path.join(run_dir, "hidden.txt"), "w", encoding="utf-8") as fh:
        fh.write(raw)
    agent = analyze_agent_tests(opts["--project-dir"])
    write_json(os.path.join(run_dir, "agent-tests-summary.json"), agent)
    try:
        snapshot_project(opts["--project-dir"], os.path.join(run_dir, "project"))
    except OSError as exc:
        sys.stderr.write("_flow_eval: project snapshot failed: %s\n" % exc)
    try:
        own = own_test_traps(opts["--case-dir"], opts["--project-dir"], int(opts.get("--own-timeout") or 120))
    except Exception as exc:  # never let own-test scoring sink the run record
        own = {"catch_rate": None, "reason": "own-test scoring crashed: %s: %s" % (type(exc).__name__, exc),
               "caught": {}, "per_trap": {}, "own_impl": None}
    write_json(os.path.join(run_dir, "own-test-traps.json"), own)

    exit_code = int(opts.get("--exit-code") or 0)
    timed_out = bool(opts.get("--timed-out"))
    cost = num(result_event, "total_cost_usd") if result_event else None
    turns = num(result_event, "num_turns") if result_event else None
    is_error = bool(result_event.get("is_error")) if result_event else True
    error = None
    if timed_out:
        error = "timeout"
    elif result_event is None:
        error = "no result event (exit %d)" % exit_code
    elif is_error:
        error = str(result_event.get("result") or result_event.get("subtype") or "is_error")[:300]
    elif exit_code != 0:
        error = "claude exit %d" % exit_code
    final_text = str(result_event.get("result") or "") if result_event else ""
    result = {
        "arm": opts["--arm"],
        "case": opts["--case"],
        "run": int(opts["--run"]),
        "model": model,
        "models_used": models_used,
        "model_requested": opts.get("--model-requested") or None,
        "effort_requested": opts.get("--effort-requested") or None,
        "cost_usd": cost,
        "tokens": tokens,
        "num_turns": turns,
        "session_id": result_event.get("session_id") if result_event else None,
        "is_error": is_error,
        "error": error,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "duration_s": float(opts["--duration"]) if opts.get("--duration") else None,
        "stream_events": events,
        "tool_counts": tool_counts,
        "skills_invoked": skills,
        "completion_phrase": "IMPLEMENTATION COMPLETE" in final_text,
        "permission_denials": (result_event.get("permission_denials") or []) if result_event else [],
        "module_exists": os.path.exists(os.path.join(opts["--project-dir"], load_traps(opts["--case-dir"])["module"] + ".py")),
        "hidden": hidden_record(hidden),
        "traps": {name: t["caught"] for name, t in hidden["traps"].items()},
        "agent_tests": {
            "files": agent["file_count"],
            "test_functions": agent["test_functions"],
            "literal_inputs": agent["literal_inputs"],
            "degenerate_inputs": agent["degenerate_inputs"],
            "degenerate_share": agent["degenerate_share"],
        },
        "own_test_trap_catch_rate": own.get("catch_rate"),
        "own_test_traps": own_traps_record(own),
        "temp_dir": opts.get("--temp-dir"),
    }
    write_json(os.path.join(run_dir, "result.json"), result)
    print(json.dumps({"hidden_pass_rate": result["hidden"]["pass_rate"], "hidden_incomplete": hidden["reason"],
                      "cost_usd": cost, "num_turns": turns,
                      "error": error, "test_functions": agent["test_functions"], "model": model,
                      "own_test_trap_catch_rate": own.get("catch_rate")}))


def num(obj, key):
    value = obj.get(key)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return None
    # json.load parses bare NaN/Infinity; either would poison every mean it
    # reaches and write a literal json.dump cannot round-trip.
    return value if math.isfinite(value) else None


# ----------------------------------------------------------------- aggregate

def mean(values):
    values = [v for v in values if v is not None]
    return (sum(values) / len(values)) if values else None


def fmt(value, digits=2, pct=False):
    if value is None:
        return "-"
    if pct:
        return "%.0f%%" % (value * 100)
    return ("%%.%df" % digits) % value


def infer_model(run_dir, record):
    """Model for grouping: result.json `model`, else claude.json modelUsage, else
    the model directory of the new layout, else `model_requested`, else "default"."""
    if record.get("model"):
        return str(record["model"])
    claude_path = os.path.join(run_dir, "claude.json")
    if os.path.exists(claude_path):
        try:
            with open(claude_path, encoding="utf-8") as fh:
                primary, _ = models_from_result_event(json.load(fh))
            if primary:
                return primary
        except (ValueError, OSError):
            pass
    if record.get("model_requested"):
        return str(record["model_requested"])
    return "default"


# Files the runner writes into a run directory before the session starts; a
# directory holding one of them but no result.json is a run that started and
# never finished (an interrupt, a crash in scoring).
RUN_STARTED_FILES = ("prompt.txt", "command.txt", "stream.jsonl")


def iter_run_dirs(out_dir, problems=None):
    """Yield (run_dir, layout) for every result.json under out_dir/runs.

    New layout: runs/<model>/<arm>/<case>/<n>; old: runs/<arm>/<case>/<n>;
    review mode adds the trap: runs/<model>/<arm>/<case>/<trap>/<n>. The depth
    decides: five levels below runs/ is review, four is the new correctness
    layout, three is the old one.

    When `problems` is a list, a directory the walk could not read and a run
    that started but wrote no result.json are appended to it, so a caller can
    say how much of the data it did not see instead of reading as if it were
    all there.
    """
    root = os.path.join(out_dir, "runs")
    if not os.path.isdir(root):
        return

    def unreadable(err):
        if problems is not None:
            problems.append("%s (cannot be read)" % getattr(err, "filename", root))

    for dirpath, dirnames, names in os.walk(root, onerror=unreadable):
        dirnames.sort()
        if "result.json" not in names:
            if problems is not None and any(f in names for f in RUN_STARTED_FILES):
                problems.append("%s (started, no result.json)" % dirpath)
                dirnames[:] = []
            continue
        rel = os.path.relpath(dirpath, root).split(os.sep)
        if len(rel) == 5:
            yield dirpath, "review"
        elif len(rel) == 4:
            yield dirpath, "model"
        elif len(rel) == 3:
            yield dirpath, "legacy"
        dirnames[:] = []


def load_results(out_dir, skipped=None):
    """Every readable run record under out_dir. A record that cannot be read is
    skipped with a message, and appended to `skipped` when a list is passed, so
    the caller can say how much of the data it did not see."""
    runs = []
    for run_dir, layout in iter_run_dirs(out_dir, skipped):
        path = os.path.join(run_dir, "result.json")
        try:
            with open(path, encoding="utf-8") as fh:
                record = json.load(fh)
        except (ValueError, OSError):
            # One unreadable record must not cost the aggregation of every
            # other run; the sibling helpers already catch both.
            sys.stderr.write("_flow_eval: skipping unreadable %s\n" % path)
            if skipped is not None:
                skipped.append(path)
            continue
        if isinstance(record, dict) and record.get("abandoned") is True:
            # flow-eval-run.sh --abandon-unfinished: a run that started and never
            # finished. Its cost counts at the per-run cap; it has no result to
            # score, and scoring it as a miss would read as a clean answer.
            sys.stderr.write("_flow_eval: skipping abandoned %s\n" % path)
            if skipped is not None:
                skipped.append(path)
            continue
        if not isinstance(record, dict) or "arm" not in record or "case" not in record:
            sys.stderr.write("_flow_eval: skipping incomplete %s\n" % path)
            if skipped is not None:
                skipped.append(path)
            continue
        record["_model"] = infer_model(run_dir, record)
        record["_layout"] = layout
        record["_run_dir"] = run_dir
        runs.append(record)
    return runs


def own_rate(record):
    value = record.get("own_test_trap_catch_rate")
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def own_caught(record):
    own = record.get("own_test_traps") or {}
    caught = own.get("caught") or {}
    return {k: v for k, v in caught.items() if isinstance(v, bool)}


def hidden_incomplete(record):
    """Whether the run's hidden suite did not finish. Records written before the
    `incomplete` field existed are read through `timed_out`/`import_or_crash`."""
    hidden = record.get("hidden") or {}
    if "incomplete" in hidden:
        return bool(hidden["incomplete"])
    return bool(hidden.get("timed_out")) or bool(hidden.get("import_or_crash"))


def own_incomplete_runs(record):
    own = record.get("own_test_traps") or {}
    value = own.get("incomplete_runs")
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def summarize_runs(rs):
    """Metrics shared by the per-arm and per-cell tables."""
    rates = [r["hidden"]["pass_rate"] for r in rs]
    return {
        "runs": len(rs),
        "hidden_pass_rate_mean": mean(rates),
        "hidden_pass_rate_min": min(rates), "hidden_pass_rate_max": max(rates),
        "hidden_pass_rate_spread": max(rates) - min(rates),
        "all_pass_rate": mean([1.0 if r["hidden"]["all_pass"] else 0.0 for r in rs]),
        "incomplete_runs": sum(1 for r in rs if hidden_incomplete(r)),
        "incomplete_reasons": sorted({str((r.get("hidden") or {}).get("reason") or "unknown") for r in rs if hidden_incomplete(r)}),
        "own_test_incomplete_runs": sum(1 for r in rs if own_incomplete_runs(r)),
        "own_tests_mean": mean([r["agent_tests"]["test_functions"] for r in rs]),
        "degenerate_share_mean": mean([r["agent_tests"]["degenerate_share"] for r in rs]),
        "own_test_trap_catch_rate": mean([own_rate(r) for r in rs]),
        "own_test_trap_scored_runs": sum(1 for r in rs if own_rate(r) is not None),
        "own_test_trap_unscored_reasons": sorted({str((r.get("own_test_traps") or {}).get("reason"))
                                                 for r in rs if own_rate(r) is None and (r.get("own_test_traps") or {}).get("reason")}),
        "cost_usd_mean": mean([r["cost_usd"] for r in rs]),
        "cost_usd_total": sum(r["cost_usd"] or 0 for r in rs),
        "num_turns_mean": mean([r["num_turns"] for r in rs]),
        "cache_hit_rate_mean": mean([run_tokens(r).get("cache_hit_rate") for r in rs]),
        "output_tokens_mean": mean([run_tokens(r).get("output") for r in rs]),
        "token_scored_runs": sum(1 for r in rs if run_tokens(r)),
        # Coverage is per mean, not per run: a run can carry whole-run totals
        # and still be missing the one field a given mean averages.
        "cache_hit_rate_scored_runs": sum(1 for r in rs if run_tokens(r).get("cache_hit_rate") is not None),
        "output_tokens_scored_runs": sum(1 for r in rs if run_tokens(r).get("output") is not None),
        "token_fallback_runs": sum(1 for r in rs if all_tokens(r).get("source") == "usage"),
        "token_entries_skipped": sum(all_tokens(r).get("entries_skipped") or 0 for r in rs),
        "effort_requested": sorted({str(r.get("effort_requested") or "unpinned") for r in rs}),
        "errors": sum(1 for r in rs if r.get("error")),
        "skills_invoked": sorted({s for r in rs for s in r.get("skills_invoked", [])}),
    }


def aggregate_model(runs):
    """Per-arm, per-cell and decision for the runs of one model."""
    cells = {}
    for r in runs:
        cells.setdefault((r["arm"], r["case"]), []).append(r)
    arms = sorted({a for a, _ in cells}, key=lambda a: ALL_ARMS.index(a) if a in ALL_ARMS else 99)
    cases = sorted({c for _, c in cells})
    cell_summary = {}
    for (arm, case), rs in cells.items():
        entry = summarize_runs(rs)
        entry.update({"arm": arm, "case": case})
        traps = {}
        for name in sorted({t for r in rs for t in r.get("traps", {})}):
            hits = [r["traps"].get(name) for r in rs if name in r.get("traps", {})]
            traps[name] = mean([1.0 if h else 0.0 for h in hits])
        entry["trap_catch_rate"] = traps
        own_traps = {}
        for name in sorted({t for r in rs for t in own_caught(r)}):
            hits = [own_caught(r)[name] for r in rs if name in own_caught(r)]
            own_traps[name] = mean([1.0 if h else 0.0 for h in hits])
        entry["own_test_trap_catch"] = own_traps
        own_rates = [own_rate(r) for r in rs if own_rate(r) is not None]
        entry["own_test_trap_catch_spread"] = (max(own_rates) - min(own_rates)) if own_rates else None
        cell_summary["%s/%s" % (arm, case)] = entry
    arm_summary = {}
    for arm in arms:
        rs = [r for r in runs if r["arm"] == arm]
        arm_cells = [c for c in cell_summary.values() if c["arm"] == arm]
        entry = summarize_runs(rs)
        entry["cases"] = sorted({c["case"] for c in arm_cells})
        entry["spread_mean"] = mean([c["hidden_pass_rate_spread"] for c in arm_cells])
        arm_summary[arm] = entry
    spread = mean([c["hidden_pass_rate_spread"] for c in cell_summary.values()])
    own_spread = mean([c["own_test_trap_catch_spread"] for c in cell_summary.values()])
    decision = decide(arm_summary, spread, cases, own_spread)
    return {
        "runs": len(runs),
        "arms": arms,
        "cases": cases,
        "total_cost_usd": sum(r["cost_usd"] or 0 for r in runs),
        "run_to_run_spread": spread,
        "own_test_trap_spread": own_spread,
        "per_arm": arm_summary,
        "per_cell": cell_summary,
        "decision": decision,
    }


def aggregate(out_dir):
    # Review-mode runs carry mode="review" and are scored by aggregate_review;
    # they have no hidden suite, so they would crash the correctness tables.
    skipped = []
    runs = [r for r in load_results(out_dir, skipped) if r.get("mode") != "review"]
    models = sorted({r["_model"] for r in runs})
    per_model = {m: aggregate_model([r for r in runs if r["_model"] == m]) for m in models}
    summary = {
        "runs": len(runs),
        "models": models,
        "arms": sorted({a for m in per_model.values() for a in m["arms"]}, key=lambda a: ALL_ARMS.index(a) if a in ALL_ARMS else 99),
        "cases": sorted({c for m in per_model.values() for c in m["cases"]}),
        "total_cost_usd": sum(r["cost_usd"] or 0 for r in runs),
        "runs_without_cost": sum(1 for r in runs if r.get("cost_usd") is None),
        "unreadable_records": len(skipped),
        "legacy_layout_runs": sum(1 for r in runs if r["_layout"] == "legacy"),
        "per_model": per_model,
        "decision": {
            "verdicts": {m: per_model[m]["decision"]["verdict"] for m in models},
            "reading": " ".join("[%s] %s" % (m, per_model[m]["decision"]["reading"]) for m in models)
                       or "No runs found.",
        },
    }
    write_summaries(out_dir, summary, render_summary_md(summary))
    return summary


def decide(arm_summary, spread, cases, own_spread=None):
    """Apply the decision rule documented in references/correctness-eval.md.

    Primary signal: hidden pass rate. Secondary, used only when the primary
    ties within the run-to-run spread: the own-test trap catch rate (share
    of trap variants the agent's own suite fails), compared against its own
    per-cell spread.
    """
    def arm_mean(names, key="hidden_pass_rate_mean"):
        vals = [arm_summary[a][key] for a in names if a in arm_summary]
        return mean(vals)

    enforce = arm_mean(["enforce-risk", "enforce-norisk"])
    suggest = arm_mean(["suggest-risk", "suggest-norisk"])
    off = arm_mean(["off-risk", "off-norisk"])
    risk = arm_mean(["enforce-risk", "suggest-risk", "off-risk"])
    norisk = arm_mean(["enforce-norisk", "suggest-norisk", "off-norisk"])
    baseline = arm_mean(["baseline"])
    best_alt = max(v for v in (suggest, off) if v is not None) if (suggest is not None or off is not None) else None
    complete = all(a in arm_summary for a in ALL_ARMS) and len(cases) >= 3 and all(
        arm_summary[a]["runs"] >= 3 * len(cases) for a in ALL_ARMS)
    sentences = []
    verdict = "insufficient-data"
    decided_by = None
    secondary = {"enforce": None, "alt": None, "spread": own_spread, "verdict": None}
    if enforce is None or best_alt is None or spread is None:
        sentences.append("Not enough arms have results to apply the decision rule (need at least one enforce-* arm and one suggest-*/off-* arm).")
    else:
        gap = best_alt - enforce
        alt_name = "suggest" if (suggest is not None and (off is None or suggest >= off)) else "off"
        alt_arms = ["suggest-risk", "suggest-norisk"] if alt_name == "suggest" else ["off-risk", "off-norisk"]
        if gap > spread:
            verdict = "flip-to-suggest"
            decided_by = "primary"
            sentences.append(
                "Hidden pass rate under tddMode=enforce (%s) is below the best non-enforce plugin arm (%s, %s) by %.1f points, "
                "more than the run-to-run spread of %.1f points, so the rule says testing.tddMode should default to suggest."
                % (fmt(enforce, pct=True), alt_name, fmt(best_alt, pct=True), gap * 100, spread * 100))
        else:
            sentences.append(
                "Hidden pass rate under tddMode=enforce (%s) is not below the best non-enforce plugin arm (%s, %s) by more than "
                "the run-to-run spread (%.1f points vs %.1f), so on the primary signal the rule keeps testing.tddMode=enforce."
                % (fmt(enforce, pct=True), alt_name, fmt(best_alt, pct=True), gap * 100, spread * 100))
            enforce_own = arm_mean(["enforce-risk", "enforce-norisk"], "own_test_trap_catch_rate")
            alt_own = arm_mean(alt_arms, "own_test_trap_catch_rate")
            secondary["enforce"], secondary["alt"] = enforce_own, alt_own
            if abs(gap) <= spread and enforce_own is not None and alt_own is not None:
                own_gap = alt_own - enforce_own
                threshold = own_spread if own_spread is not None else 0.0
                if own_gap > threshold:
                    verdict = "flip-to-suggest"
                    decided_by = "secondary"
                    secondary["verdict"] = "alt-ahead"
                    sentences.append(
                        "The arms tie within the spread, so the secondary signal decides: the agent's own tests catch %s of the trap "
                        "variants under %s against %s under enforce, a gap of %.1f points beyond the own-test spread of %.1f, "
                        "so the rule says testing.tddMode should default to suggest."
                        % (fmt(alt_own, pct=True), alt_name, fmt(enforce_own, pct=True), own_gap * 100, threshold * 100))
                else:
                    verdict = "keep-enforce"
                    decided_by = "secondary"
                    secondary["verdict"] = "enforce-ahead" if -own_gap > threshold else "tie"
                    sentences.append(
                        "The arms tie within the spread, so the secondary signal decides: the agent's own tests catch %s of the trap "
                        "variants under enforce against %s under %s (%+.1f points for %s, own-test spread %.1f), so the rule keeps "
                        "testing.tddMode=enforce."
                        % (fmt(enforce_own, pct=True), fmt(alt_own, pct=True), alt_name, own_gap * 100, alt_name, threshold * 100))
            else:
                verdict = "keep-enforce"
                decided_by = "primary"
                if abs(gap) <= spread:
                    sentences.append("The arms tie within the spread but the own-test trap catch rate is unavailable for one side, so the primary signal stands.")
    if risk is not None and norisk is not None:
        diff = risk - norisk
        sentences.append("Arms with specFirst.riskMap=true average %s hidden pass rate against %s without it (%+.1f points%s)."
                         % (fmt(risk, pct=True), fmt(norisk, pct=True), diff * 100,
                            "" if spread is None else (", %s the spread" % ("beyond" if abs(diff) > spread else "within"))))
    if baseline is not None:
        plugin = arm_mean(list(PLUGIN_ARMS))
        if plugin is not None:
            sentences.append("The no-plugin baseline scores %s against a plugin-arm average of %s."
                             % (fmt(baseline, pct=True), fmt(plugin, pct=True)))
        baseline_own = arm_mean(["baseline"], "own_test_trap_catch_rate")
        plugin_own = arm_mean(list(PLUGIN_ARMS), "own_test_trap_catch_rate")
        if baseline_own is not None and plugin_own is not None:
            sentences.append("Own tests catch %s of the trap variants on the baseline against %s on the plugin arms."
                             % (fmt(baseline_own, pct=True), fmt(plugin_own, pct=True)))
    if not complete:
        sentences.append("The comparison is incomplete (not every arm has >= 3 runs on every case); treat the reading as provisional.")
    return {
        "verdict": verdict,
        "decided_by": decided_by,
        "enforce_mean": enforce, "suggest_mean": suggest, "off_mean": off,
        "risk_mean": risk, "norisk_mean": norisk, "baseline_mean": baseline,
        "spread": spread, "complete": complete,
        "secondary": secondary,
        "reading": " ".join(sentences),
    }


def render_summary_md(s):
    lines = ["# Flow correctness eval — summary", ""]
    efforts = sorted({e for m in s["per_model"].values() for a in m["per_arm"].values()
                      for e in (a.get("effort_requested") or [])})
    lines.append("Runs: %d across %d model(s), %d arm(s) and %d case(s). Total cost: $%.2f. Models: %s. Effort: %s."
                 % (s["runs"], len(s["models"]), len(s["arms"]), len(s["cases"]), s["total_cost_usd"],
                    ", ".join("`%s`" % md_cell(m) for m in s["models"]) or "none",
                    ", ".join("`%s`" % md_cell(e) for e in efforts) or "none"))
    if s.get("legacy_layout_runs"):
        lines.append("")
        lines.append("%d run(s) were read from the older `runs/<arm>/<case>/<n>` layout; `_flow_eval.py migrate-layout --out <dir>` moves them under their model." % s["legacy_layout_runs"])
    if s.get("runs_without_cost"):
        lines.append("")
        lines.append("%d run%s reported no cost (a timeout or a crash), so the total above leaves %s out; each may have spent up to the per-run cap."
                     % (s["runs_without_cost"], "" if s["runs_without_cost"] == 1 else "s",
                        "it" if s["runs_without_cost"] == 1 else "them"))
    if s.get("unreadable_records"):
        lines.append("")
        lines.append("%d result record%s could not be read or %s abandoned, and %s not in these numbers."
                     % (s["unreadable_records"], "" if s["unreadable_records"] == 1 else "s",
                        "was" if s["unreadable_records"] == 1 else "were",
                        "is" if s["unreadable_records"] == 1 else "are"))
    lines.append("")
    lines.append("## Reading")
    lines.append("")
    for model in s["models"]:
        m = s["per_model"][model]
        lines.append("**%s** (%d runs, $%.2f, run-to-run spread %s, own-test spread %s): %s"
                     % (md_cell(model), m["runs"], m["total_cost_usd"], fmt(m["run_to_run_spread"], pct=True),
                        fmt(m["own_test_trap_spread"], pct=True), m["decision"]["reading"]))
        lines.append("")
        lines.append("Verdict for `%s`: `%s`%s" % (md_cell(model), m["decision"]["verdict"],
                     (" (decided by the %s signal)" % m["decision"]["decided_by"]) if m["decision"].get("decided_by") else ""))
        lines.append("")
    if not s["models"]:
        lines.append("No runs found.")
        lines.append("")
    lines.append("## Per model × arm")
    lines.append("")
    lines.append("| Model | Arm | Effort | Runs | Hidden pass rate | All-pass runs | Own tests catch traps | Own tests (mean) | Degenerate share | Cost (mean) | Turns (mean) | Cache hits | Output tokens | Errors | Incomplete |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for arm in m["arms"]:
            a = m["per_arm"][arm]
            lines.append("| %s | %s | %s | %d | %s | %s | %s | %s | %s | $%s | %s | %s | %s | %d | %s |" % (
                md_cell(model), md_cell(arm), effort_cell(a), a["runs"], fmt(a["hidden_pass_rate_mean"], pct=True),
                fmt(a["all_pass_rate"], pct=True),
                own_cell(a), fmt(a["own_tests_mean"], 1), fmt(a["degenerate_share_mean"], pct=True), fmt(a["cost_usd_mean"]),
                fmt(a["num_turns_mean"], 1),
                token_cell(a, "cache_hit_rate_mean", "cache_hit_rate_scored_runs", pct=True),
                token_cell(a, "output_tokens_mean", "output_tokens_scored_runs"),
                a["errors"], incomplete_cell(a)))
    lines.append("")
    lines.append(INCOMPLETE_NOTE)
    # Only shown when it applies: a reader who never sees this line can take the
    # token columns at face value.
    fallback = sum(a.get("token_fallback_runs") or 0
                   for m in s["per_model"].values() for a in m["per_arm"].values())
    skipped = sum(a.get("token_entries_skipped") or 0
                  for m in s["per_model"].values() for a in m["per_arm"].values())
    if fallback or skipped:
        lines.append("")
        lines.append(token_caveat(fallback, skipped))
    lines.append("")
    lines.append("## Per model × arm × case")
    lines.append("")
    lines.append("| Model | Arm | Case | Effort | Runs | Hidden pass rate (min–max) | All-pass | Own tests catch traps | Own tests | Degenerate share | Cost | Turns | Errors | Incomplete |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for arm in m["arms"]:
            for case in m["cases"]:
                c = m["per_cell"].get("%s/%s" % (arm, case))
                if not c:
                    continue
                lines.append("| %s | %s | %s | %s | %d | %s (%s–%s) | %s | %s | %s | %s | $%s | %s | %d | %s |" % (
                    md_cell(model), md_cell(arm), md_cell(case), effort_cell(c), c["runs"], fmt(c["hidden_pass_rate_mean"], pct=True), fmt(c["hidden_pass_rate_min"], pct=True),
                    fmt(c["hidden_pass_rate_max"], pct=True), fmt(c["all_pass_rate"], pct=True), own_cell(c), fmt(c["own_tests_mean"], 1),
                    fmt(c["degenerate_share_mean"], pct=True), fmt(c["cost_usd_mean"]), fmt(c["num_turns_mean"], 1), c["errors"],
                    incomplete_cell(c)))
    lines.append("")
    lines.append("## Trap catch rate (share of runs whose implementation fell into the trap; lower is better)")
    lines.append("")
    for model in s["models"]:
        m = s["per_model"][model]
        for case in m["cases"]:
            traps = sorted({t for c in m["per_cell"].values() if c["case"] == case for t in c["trap_catch_rate"]})
            if not traps:
                continue
            lines.append("### %s — %s" % (md_cell(model), md_cell(case)))
            lines.append("")
            lines.append("| Arm | " + " | ".join(traps) + " |")
            lines.append("|---|" + "---|" * len(traps))
            for arm in m["arms"]:
                c = m["per_cell"].get("%s/%s" % (arm, case))
                if not c:
                    continue
                lines.append("| %s | " % arm + " | ".join(fmt(c["trap_catch_rate"].get(t), pct=True) for t in traps) + " |")
            lines.append("")
    lines.append("## Own-test trap catch rate (share of runs whose own tests fail the trap variant; higher is better)")
    lines.append("")
    lines.append("A run is scored only when its `tests/` suite imports the module, passes at least one test against the agent's own implementation, and uses no names the variants lack; `summary.json` lists the reasons for unscored runs (`per_cell.*.own_test_trap_unscored_reasons`).")
    lines.append("")
    for model in s["models"]:
        m = s["per_model"][model]
        for case in m["cases"]:
            traps = sorted({t for c in m["per_cell"].values() if c["case"] == case for t in c["own_test_trap_catch"]})
            if not traps:
                continue
            lines.append("### %s — %s" % (md_cell(model), md_cell(case)))
            lines.append("")
            lines.append("| Arm | scored runs | " + " | ".join(traps) + " |")
            lines.append("|---|---|" + "---|" * len(traps))
            for arm in m["arms"]:
                c = m["per_cell"].get("%s/%s" % (arm, case))
                if not c:
                    continue
                lines.append("| %s | %s | " % (arm, scored_cell(c))
                             + " | ".join(fmt(c["own_test_trap_catch"].get(t), pct=True) for t in traps) + " |")
            lines.append("")
    lines.append("A run whose own suite did not finish against the agent's module, the reference or a variant (timeout, crash, no summary line) is marked `n incomplete` in the scored-runs column; such a run counts a variant as caught only on an observed FAIL/ERROR of an oracle test, and a test never observed passing is not an oracle (`own_test_traps.incomplete_runs` in result.json).")
    lines.append("")
    lines.append("Skills invoked per cell are listed in summary.json (`per_model.<model>.per_cell.*.skills_invoked`); a plugin arm with no `flow:*` skill invocation did not exercise the plugin.")
    lines.append("")
    return "\n".join(lines)


INCOMPLETE_NOTE = ("Incomplete: runs whose hidden suite did not finish (timeout, crash or no `OK`/`FAILED` summary line). "
                   "Such a run is scored as the `ok` lines observed over the suite's full size, so the cell's hidden pass "
                   "rate is a lower bound; `hidden.incomplete`, `hidden.reason` and `hidden.observed`/`hidden.expected` "
                   "in its result.json say what was seen.")


def own_cell(entry):
    """'67% (3/3)' — mean own-test trap catch rate and how many runs were scored."""
    if entry["own_test_trap_catch_rate"] is None:
        return "- (0/%d)" % entry["runs"]
    return "%s (%d/%d)" % (fmt(entry["own_test_trap_catch_rate"], pct=True), entry["own_test_trap_scored_runs"], entry["runs"])


def path_component(value):
    """A result.json string made safe to use as one directory name.

    `model` comes from the run record, so `..` or an empty value would move a
    run out of runs/ where the aggregate can no longer find it — the run then
    disappears from the measurement silently.
    """
    text = str(value).replace("/", "_").replace("\\", "_").strip()
    return text if text and text not in (".", "..") else "default"


def md_cell(value):
    """A result.json string rendered safely into a markdown table cell.

    Values here come from run records, which are data the harness collected,
    not text it authored: a `|` in a model name would split the row, and
    `--aggregate-only` runs over directories this machine did not produce.
    """
    text = str(value)
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", text).replace("|", "\\|").strip()
    return (text[:117] + "...") if len(text) > 120 else text


def token_caveat(fallback, skipped):
    """The one-line warning under the arm table when token totals are partial."""
    parts = []
    if fallback:
        parts.append("%d run(s) recorded only the last request's counts and are outside the "
                     "token means (`tokens.source: usage` in their result.json)" % fallback)
    if skipped:
        parts.append("%d malformed `modelUsage` entr(y/ies) were dropped, so those runs' totals "
                     "are missing a billed model" % skipped)
    return "Token totals are partial: " + "; ".join(parts) + "."


def effort_cell(entry):
    """'high' or 'high, unpinned' — the effort levels behind the cell.

    A cell mixing levels is not a result; it reads as mixed here so nobody
    compares its cost mean against another cell's."""
    levels = [md_cell(level) for level in (entry.get("effort_requested") or [])]
    return ", ".join(levels) if levels else "-"


def token_cell(entry, key, count_key, pct=False):
    """'90% (2/3)' — a token mean and how many of the cell's runs it covers.

    The count is per mean, not per run: a run can carry whole-run totals and
    still be missing this mean's field, and a mean over one of three runs is
    not the cell.
    """
    value = entry.get(key)
    scored = entry.get(count_key) or 0
    if value is None:
        return "- (0/%d)" % entry["runs"]
    return "%s (%d/%d)" % (fmt(value, pct=pct) if pct else fmt(value, 0), scored, entry["runs"])


def scored_cell(entry):
    """'3/3' or '2/3, 1 incomplete' — own-test scored runs, flagging runs with an unfinished suite run."""
    text = "%d/%d" % (entry["own_test_trap_scored_runs"], entry["runs"])
    if entry.get("own_test_incomplete_runs"):
        text += ", %d incomplete" % entry["own_test_incomplete_runs"]
    return text


def incomplete_cell(entry):
    """'0' or '1 (timeout)' — runs whose hidden suite did not finish, with the reasons."""
    if not entry["incomplete_runs"]:
        return "0"
    return "%d (%s)" % (entry["incomplete_runs"], ", ".join(entry["incomplete_reasons"]))


def cmd_aggregate(args):
    opts = parse_opts(args, ["--out", "--mode"])
    if not opts.get("--out"):
        die("aggregate --out DIR [--mode correctness|review]")
    if not os.path.isdir(opts["--out"]):
        die("aggregate: %s is not a directory" % opts["--out"])
    mode = opts.get("--mode")
    if mode is None:
        # Auto-detect so `--aggregate-only` on a review directory does not need
        # the flag; an empty directory falls back to the correctness tables.
        records = load_results(opts["--out"])
        modes = {"review" if r.get("mode") == "review" else "correctness" for r in records}
        if len(modes) > 1:
            # Guessing either mode would leave the other mode's runs out of the
            # summary without a word.
            die("aggregate: %s holds both correctness and review runs; pass --mode correctness or --mode review"
                % opts["--out"])
        mode = "review" if modes == {"review"} else "correctness"
    if mode not in ("correctness", "review"):
        die("aggregate --mode must be correctness or review, got '%s'" % mode)
    # A mode that matches none of the recorded runs would write a summary of
    # nothing over whatever summary is there. The runner always passes a mode,
    # so this is the check an operator's --aggregate-only actually reaches.
    skipped = []
    records = load_results(opts["--out"], skipped)
    # Nothing readable but something there: a summary of nothing would be
    # written over whatever summary exists.
    if skipped and not records:
        die("aggregate: all %d result record(s) in %s could not be read; nothing written" % (len(skipped), opts["--out"]))
    if records and not any((r.get("mode") == "review") == (mode == "review") for r in records):
        other = "correctness" if mode == "review" else "review"
        die("aggregate: %s holds only %s runs, not %s runs; pass --mode %s" % (opts["--out"], other, mode, other))
    if mode == "review":
        summary = aggregate_review(opts["--out"])
        print(json.dumps({"mode": "review", "runs": summary["runs"], "models": summary["models"],
                          "verdict": summary["decision"]["verdict"],
                          "total_cost_usd": summary["total_cost_usd"]}))
        return
    summary = aggregate(opts["--out"])
    print(json.dumps({"runs": summary["runs"], "models": summary["models"], "verdicts": summary["decision"]["verdicts"],
                      "total_cost_usd": summary["total_cost_usd"]}))


# ------------------------------------------------------------ migrate-layout

def migrate_layout(out_dir):
    """Move runs/<arm>/<case>/<n> to runs/<model>/<arm>/<case>/<n> and stamp `model`.

    The model comes from result.json (`model`), else claude.json modelUsage,
    else `model_requested`, else "default". Idempotent: runs already in the
    model layout are left alone (their result.json still gets `model` filled
    in when missing). Returns the list of (from, to) moves.
    """
    moves = []
    root = os.path.join(out_dir, "runs")
    for run_dir, layout in list(iter_run_dirs(out_dir)):
        path = os.path.join(run_dir, "result.json")
        try:
            with open(path, encoding="utf-8") as fh:
                record = json.load(fh)
        except ValueError:
            continue
        model = infer_model(run_dir, record)
        if record.get("model") != model:
            record["model"] = model
            claude_path = os.path.join(run_dir, "claude.json")
            if os.path.exists(claude_path) and not record.get("models_used"):
                try:
                    with open(claude_path, encoding="utf-8") as fh:
                        _, record["models_used"] = models_from_result_event(json.load(fh))
                except (ValueError, OSError):
                    pass
            write_json(path, record)
        if layout == "model":
            continue
        arm, case, n = os.path.relpath(run_dir, root).split(os.sep)
        dest = os.path.join(root, path_component(model), arm, case, n)
        if os.path.exists(dest):
            sys.stderr.write("_flow_eval: not moving %s: %s exists\n" % (run_dir, dest))
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(run_dir, dest)
        moves.append((run_dir, dest))
    # drop the now-empty legacy directories (bottom-up; a dir emptied by the
    # previous rmdir is re-checked with listdir, not os.walk's stale dirnames)
    for arm in list(os.listdir(root)) if os.path.isdir(root) else []:
        arm_dir = os.path.join(root, arm)
        if arm in ALL_ARMS and os.path.isdir(arm_dir):
            for dirpath, _dirnames, _filenames in os.walk(arm_dir, topdown=False):
                if not os.listdir(dirpath):
                    os.rmdir(dirpath)
    return moves


def cmd_migrate_layout(args):
    opts = parse_opts(args, ["--out"])
    if not opts.get("--out"):
        die("migrate-layout --out DIR")
    moves = migrate_layout(opts["--out"])
    for src, dst in moves:
        print("moved %s -> %s" % (os.path.relpath(src, opts["--out"]), os.path.relpath(dst, opts["--out"])))
    print(json.dumps({"moved": len(moves)}))


# --------------------------------------------------------------- check-cases

def check_cases(evals_dir, only=None):
    problems = []
    report = {}
    for case in sorted(os.listdir(evals_dir)):
        case_dir = os.path.join(evals_dir, case)
        if not os.path.isfile(os.path.join(case_dir, "prompt.md")) or (only and case != only):
            continue
        traps = load_traps(case_dir)
        ref, _ = run_hidden(case_dir, None, os.path.join(case_dir, "hidden", "reference_impl.py"))
        entry = {"reference": "%d/%d" % (ref["passed"], ref["total"]), "traps": {}}
        if not ref["all_pass"]:
            problems.append("%s: reference fails %s" % (case, ref["failed_ids"]))
        for name, trap in traps["traps"].items():
            parsed, _ = run_hidden(case_dir, None, os.path.join(case_dir, trap["variant"]))
            failing = set(parsed["failed_ids"])
            listed = set(trap["discriminating_tests"])
            entry["traps"][name] = {"failing": len(failing), "listed": len(listed), "caught": parsed["traps"][name]["caught"]}
            if not listed:
                problems.append("%s/%s: no discriminating tests listed" % (case, name))
            if not parsed["traps"][name]["caught"]:
                problems.append("%s/%s: variant passes all listed tests" % (case, name))
            if listed != failing:
                problems.append("%s/%s: traps.json lists %s but variant fails %s" % (case, name, sorted(listed), sorted(failing)))
        report[case] = entry
    return report, problems


def cmd_check_cases(args):
    opts = parse_opts(args, ["--evals-dir", "--case", "--mode"],
                      flags=["--no-write", "--no-verify-behaviour"])
    if not opts.get("--evals-dir"):
        die("check-cases --evals-dir DIR [--case NAME] [--mode correctness|review] "
            "[--no-write] [--no-verify-behaviour]")
    mode = opts.get("--mode") or "correctness"
    if mode not in ("correctness", "review"):
        die("check-cases --mode must be correctness or review, got '%s'" % mode)
    if mode == "review":
        report, problems, examined, behaviour_checked = check_cases_review(
            opts["--evals-dir"], opts.get("--case"), write=not opts.get("--no-write"),
            verify_behaviour=not opts.get("--no-verify-behaviour"))
        print(json.dumps({"mode": "review", "cases": report, "problems": problems,
                          "variants_examined": examined,
                          "behaviour_checked": behaviour_checked}, indent=2, sort_keys=True))
    else:
        report, problems = check_cases(opts["--evals-dir"], opts.get("--case"))
        print(json.dumps({"cases": report, "problems": problems}, indent=2, sort_keys=True))
    if problems or not report:
        sys.exit(1)


# ------------------------------------------------------------ review mode

REVIEW_ARMS = ("review-b", "review-b-critic")
# Priorities that enter review scoring at all. P3 findings are never sent to
# the grounding critic and are not scored here either, so a reviewer is
# neither rewarded nor punished for raising one.
SCORED_PRIORITIES = ("P1", "P2")
# A fence line: optional indent, three or more backticks, then an optional info
# string with no backtick in it (CommonMark allows anything there, as in
# ```python title="r.py"). Matched per line, so a tagged block can never be
# misread as the start of the next one. The tag is the leading word of the info
# string, cut at anything that cannot be part of a language name, so
# `python:money.py` is a python block.
FENCE_LINE_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})([^`]*)$")
FENCE_TAG_RE = re.compile(r"[A-Za-z0-9_+.-]*")
# Tags that hold the answer. The prompt asks for a `json` block; `jsonc` is the
# same answer. An untagged block is read only when no block carries either tag,
# so a bare repro block after the answer is never taken for it.
ANSWER_TAGS = ("json", "jsonc")


def fenced_blocks(text):
    """Every fenced block in text as (tag, body), in order.

    Read line by line: an opening fence carries a tag, the block closes at the
    next bare fence of at least the same length, and a block still open at the
    end of the text runs to the end. CRLF endings are handled by splitlines().
    """
    blocks = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = FENCE_LINE_RE.match(lines[i])
        if not m:
            i += 1
            continue
        ticks = m.group(1)
        info = m.group(2).strip()
        tag = FENCE_TAG_RE.match(info.split()[0] if info else "").group(0).lower()
        body = []
        i += 1
        while i < len(lines):
            close = FENCE_LINE_RE.match(lines[i])
            # A fence closes with the same character it opened with.
            if close and not close.group(2).strip() and close.group(1)[0] == ticks[0] \
                    and len(close.group(1)) >= len(ticks):
                break
            body.append(lines[i])
            i += 1
        blocks.append((tag, "\n".join(body)))
        i += 1
    return blocks


def split_lines(text):
    return text.splitlines()


def changed_hunks(ref_text, variant_text):
    """Variant-side line ranges the reference→variant diff touches.

    Returns a sorted list of inclusive 1-based [start, end] pairs, and a bool
    saying whether the two texts differ at all. Ranges are the lines a reviewer
    reading the branch diff sees as added or changed, because those are the
    lines a finding can cite.

    A pure deletion has no variant-side line of its own, so it is anchored to
    the variant lines that flank the removal — without the anchor a trap that
    only removes code could never be hit, which would score the reviewer for
    the shape of the edit rather than for finding the defect.
    """
    ref = split_lines(ref_text)
    var = split_lines(variant_text)
    ranges = []
    differs = False
    matcher = difflib.SequenceMatcher(a=ref, b=var, autojunk=False)
    for tag, _i1, _i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        differs = True
        if tag in ("replace", "insert"):
            if j2 > j1:
                ranges.append([j1 + 1, j2])
        elif tag == "delete" and var:
            start = max(1, j1)
            end = min(len(var), j1 + 1)
            if end >= start:
                ranges.append([start, end])
    ranges.sort()
    merged = []
    for start, end in ranges:
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged, differs



def toplevel_name(stmt):
    """The single top-level name a statement binds, or None.

    Only the shapes a variant can substitute for a reference statement count:
    a function, a class, or an assignment to one plain name. A tuple assignment
    binds several names at once and has no single statement in the reference it
    could replace, so it is appended instead.
    """
    if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return stmt.name
    if isinstance(stmt, ast.Assign) and len(stmt.targets) == 1 and isinstance(stmt.targets[0], ast.Name):
        return stmt.targets[0].id
    if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
        return stmt.target.id
    return None


def stmt_span(stmt):
    """(first line, last line), 1-based inclusive, decorators included."""
    start = stmt.lineno
    for decorator in getattr(stmt, "decorator_list", []) or []:
        start = min(start, decorator.lineno)
    return start, getattr(stmt, "end_lineno", stmt.lineno)


def stmt_source(lines, stmt):
    start, end = stmt_span(stmt)
    return "".join(lines[start - 1:end])


def is_docstring(stmt):
    return (isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant)
            and isinstance(stmt.value.value, str))


def is_star_import_of_reference(stmt):
    return (isinstance(stmt, ast.ImportFrom) and stmt.module == "reference_impl"
            and any(alias.name == "*" for alias in stmt.names))


def import_is_used(import_source, body_text):
    """Whether any name an import statement binds appears in the module body."""
    try:
        stmt = ast.parse(import_source.strip()).body[0]
    except (SyntaxError, IndexError):
        return True
    for alias in getattr(stmt, "names", []):
        bound = (alias.asname or alias.name).split(".")[0]
        if re.search(r"\b%s\b" % re.escape(bound), body_text):
            return True
    return False


def subclassed_reference_class(stmt, ref_classes):
    """The reference class this variant class subclasses, or None.

    Accepts `class V(X)` and `class V(_ref.X)`, one base only: two bases mean
    the variant composes something the reference does not have, and folding
    that into one class would change what runs.
    """
    if not isinstance(stmt, ast.ClassDef) or len(stmt.bases) != 1 or stmt.keywords:
        return None
    base = stmt.bases[0]
    if isinstance(base, ast.Attribute) and isinstance(base.value, ast.Name):
        name = base.attr
    elif isinstance(base, ast.Name):
        name = base.id
    else:
        return None
    return name if name in ref_classes else None


def names_used(stmt):
    return {node.id for node in ast.walk(stmt) if isinstance(node, ast.Name)}


def bound_names(stmt):
    names = set()
    for target in getattr(stmt, "targets", []) or []:
        for node in ast.walk(target):
            if isinstance(node, ast.Name):
                names.add(node.id)
    name = toplevel_name(stmt)
    if name:
        names.add(name)
    return names


def patch_class_body(ref_lines, class_stmt, patches):
    """The reference class's source with the variant's methods written into it."""
    start, end = stmt_span(class_stmt)
    out = []
    cursor = start - 1
    remaining = dict(patches)
    for member in class_stmt.body:
        mstart, mend = stmt_span(member)
        out.extend(ref_lines[cursor:mstart - 1])
        if isinstance(member, (ast.FunctionDef, ast.AsyncFunctionDef)) and member.name in remaining:
            out.append(remaining.pop(member.name))
        else:
            out.extend(ref_lines[mstart - 1:mend])
        cursor = mend
    out.extend(ref_lines[cursor:end])
    text = "".join(out)
    for _name, source in sorted(remaining.items()):
        if not text.endswith("\n"):
            text += "\n"
        text += "\n" + source
    return text


def materialize_variant(ref_text, variant_text):
    """The reference's source with the variant's changes written into it.

    A trap variant as shipped is a few lines that import the reference and
    redefine one name. Committed as the module it would replace the whole file,
    and every finding that named the file would land inside a hunk — recall and
    precision of 1.0 for a reviewer that read nothing. So the variant is folded
    back into the reference's own source: a statement that redefines a name the
    reference defines is substituted where that name is defined, and anything
    else is appended in the order the variant wrote it, which keeps the later
    binding that makes the variant behave as the variant.

    The variant's module docstring is dropped. It says which trap this is, and
    the reviewer must not be told.
    """
    ref_lines = ref_text.splitlines(True)
    var_lines = variant_text.splitlines(True)
    ref_tree = ast.parse(ref_text)
    var_tree = ast.parse(variant_text)

    replacements = {}
    method_patches = {}
    appended = []
    appended_imports = []
    alias_names = set()
    ref_names = {toplevel_name(st) for st in ref_tree.body}
    ref_names.discard(None)
    ref_classes = {st.name for st in ref_tree.body if isinstance(st, ast.ClassDef)}
    for index, stmt in enumerate(var_tree.body):
        if index == 0 and is_docstring(stmt):
            continue
        if is_star_import_of_reference(stmt):
            continue
        name = toplevel_name(stmt)
        source = stmt_source(var_lines, stmt)
        base = subclassed_reference_class(stmt, ref_classes)
        if base is not None:
            # A variant that subclasses a reference class and overrides one
            # method is a patch to that method, not a new class. Committed as a
            # subclass it would delete the original class from the diff and
            # hand the reviewer a file that obviously is not the project's.
            patches = method_patches.setdefault(base, {})
            for member in stmt.body:
                if isinstance(member, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    patches[member.name] = stmt_source(var_lines, member)
            alias_names.add(stmt.name)
            continue
        if names_used(stmt) & alias_names:
            # Whatever this statement rebinds, it rebinds through the subclass
            # that no longer exists; the reference's own wiring already reaches
            # the patched method. Dropping it is verified, not assumed: the case
            # check reruns the hidden suite against the materialized module and
            # requires the same tests to fail.
            alias_names.update(bound_names(stmt))
            continue
        if isinstance(stmt, (ast.Import, ast.ImportFrom)):
            appended_imports.append(source)
        elif name is not None and name in ref_names and name not in replacements:
            replacements[name] = source
        else:
            appended.append(source)

    # The variant's own imports go where the reference keeps its imports. Left
    # at the bottom they would read as a defect of their own, and a reviewer
    # who flagged them would be scored as having found the seeded bug.
    import_anchor = 0
    for position, stmt in enumerate(ref_tree.body):
        if isinstance(stmt, (ast.Import, ast.ImportFrom)):
            import_anchor = position + 1
        elif position == 0 and is_docstring(stmt):
            import_anchor = 1

    def render(imports):
        out = []
        cursor = 0
        pending = list(imports)
        used = dict(replacements)
        for position, stmt in enumerate(ref_tree.body):
            start, end = stmt_span(stmt)
            if position == import_anchor and pending:
                out.extend(pending)
                pending = []
            out.extend(ref_lines[cursor:start - 1])
            name = toplevel_name(stmt)
            if name is not None and name in used:
                out.append(used.pop(name))
            elif isinstance(stmt, ast.ClassDef) and stmt.name in method_patches:
                out.append(patch_class_body(ref_lines, stmt, method_patches[stmt.name]))
            else:
                out.extend(ref_lines[start - 1:end])
            cursor = end
        out.extend(ref_lines[cursor:])
        text = "".join(out)
        if pending:
            text = "".join(pending) + text
        if appended:
            if not text.endswith("\n"):
                text += "\n"
            text += "\n\n" + "\n\n\n".join(part.rstrip("\n") for part in appended) + "\n"
        return text

    # An import the materialized module never uses — or one the reference
    # already has, which would materialize as the same line twice — shows up in
    # the diff as a defect of its own, and a reviewer who flagged it would be
    # credited with finding the seeded bug. Keep only the imports something
    # still refers to and the reference does not already state.
    ref_imports = {stmt_source(ref_lines, stmt).strip()
                   for stmt in ref_tree.body if isinstance(stmt, (ast.Import, ast.ImportFrom))}
    body = render([])
    kept = [source for source in appended_imports
            if import_is_used(source, body) and source.strip() not in ref_imports]
    return render(kept)


def strip_module_docstring(text):
    """The source without its module docstring.

    Both eval references open by naming the hidden suite and the trap variants
    under hidden/traps/. Committed as the module under review that sentence
    tells the reviewer it is being tested and where the bug is, so it is
    removed from the file the review sees. It is removed from the reference and
    the variant alike, so the branch diff is unchanged.
    """
    tree = ast.parse(text)
    if not tree.body or not is_docstring(tree.body[0]):
        return text
    lines = text.splitlines(True)
    _start, end = stmt_span(tree.body[0])
    rest = lines[end:]
    while rest and not rest[0].strip():
        rest.pop(0)
    return "".join(rest)


def reference_module_text(case_dir):
    """The reference implementation as the default branch commits it."""
    ref_path = os.path.join(case_dir, "hidden", "reference_impl.py")
    return strip_module_docstring(read_text(ref_path))


def materialized_variant_text(case_dir, trap):
    """The trap variant as the feature branch commits it."""
    ref_path, var_path, _module, _entry = variant_paths(case_dir, trap)
    return strip_module_docstring(materialize_variant(read_text(ref_path), read_text(var_path)))


def cmd_reference_module(args):
    opts = parse_opts(args, ["--case", "--out"])
    if not opts.get("--case"):
        die("reference-module --case <dir> [--out FILE]")
    text = reference_module_text(opts["--case"])
    if opts.get("--out"):
        with open(opts["--out"], "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)


def variant_delegates_to_reference(case_dir, trap):
    """Does the trap variant, as the feature branch commits it, still call into
    reference_impl? Those variants need reference_impl.py beside the module;
    the rest must not be given it, because a pristine correct copy of the
    module locates the defect by diff alone."""
    return "reference_impl" in materialized_variant_text(case_dir, trap)


def cmd_variant_delegates(args):
    opts = parse_opts(args, ["--case", "--trap"])
    for key in ("--case", "--trap"):
        if not opts.get(key):
            die("variant-delegates --case <dir> --trap <name>")
    sys.stdout.write("yes\n" if variant_delegates_to_reference(opts["--case"], opts["--trap"]) else "no\n")


def cmd_materialize_variant(args):
    opts = parse_opts(args, ["--case", "--trap", "--out"])
    for key in ("--case", "--trap"):
        if not opts.get(key):
            die("materialize-variant --case <dir> --trap <name> [--out FILE]")
    text = materialized_variant_text(opts["--case"], opts["--trap"])
    if opts.get("--out"):
        with open(opts["--out"], "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)


def variant_paths(case_dir, trap):
    traps = load_traps(case_dir)
    entry = traps["traps"].get(trap)
    if entry is None:
        die("no trap '%s' in %s (have: %s)" % (trap, case_dir, ", ".join(sorted(traps["traps"]))))
    return (os.path.join(case_dir, "hidden", "reference_impl.py"),
            os.path.join(case_dir, entry["variant"]),
            traps["module"],
            entry)


def sources_digest(ref_text, variant_text):
    """A digest of the exact two texts changed_hunks diffs.

    Recorded next to changed_lines so scoring can tell whether what was
    recorded still describes the diff. Without it, a variant edited after the
    check was last run is scored against hunks that no longer exist: a finding
    on the real defect reads as false and a finding on an untouched line reads
    as the hit."""
    digest = hashlib.sha256()
    digest.update(ref_text.encode("utf-8"))
    digest.update(b"\0")
    digest.update(variant_text.encode("utf-8"))
    return digest.hexdigest()[:16]


def trap_sources_digest(case_dir, trap):
    return sources_digest(reference_module_text(case_dir), materialized_variant_text(case_dir, trap))


def hunks_for_trap(case_dir, trap):
    """(hunks, source) for one trap.

    The hunks are always computed from the reference and the materialized
    variant, and the changed_lines recorded by `check-cases --mode review` are
    used only when they equal them and their digest still matches the sources.
    Checking the record item by item kept missing shapes (a list with one bad
    item was scored against the rest; a string read as "nothing recorded"), and
    a well-formed record with the wrong ranges passes any shape check.

    source is "traps.json" when the record was used; otherwise the hunks are the
    computed ones and source says why the record was not: "computed" (nothing
    recorded), "computed:traps.json-malformed" (not a list of [first, last]
    integer pairs), "computed:traps.json-unpinned" (no digest, so nothing says
    what it was computed from), "computed:traps.json-stale" (the sources moved
    since), or "computed:traps.json-mismatch" (the digest matches but the ranges
    are not the diff's).
    """
    _ref_path, _var_path, _module, entry = variant_paths(case_dir, trap)
    ref_text = reference_module_text(case_dir)
    variant_text = materialized_variant_text(case_dir, trap)
    hunks, _differs = changed_hunks(ref_text, variant_text)
    if "changed_lines" not in entry:
        return hunks, "computed"
    recorded = entry.get("changed_lines")
    well_formed = (
        isinstance(recorded, list) and recorded
        and all(isinstance(item, list) and len(item) == 2
                and all(isinstance(v, int) and not isinstance(v, bool) for v in item)
                for item in recorded)
    )
    if not well_formed:
        return hunks, "computed:traps.json-malformed"
    recorded_digest = entry.get("changed_lines_digest")
    if not recorded_digest:
        return hunks, "computed:traps.json-unpinned"
    if recorded_digest != sources_digest(ref_text, variant_text):
        return hunks, "computed:traps.json-stale"
    if [list(item) for item in recorded] != [list(item) for item in hunks]:
        return hunks, "computed:traps.json-mismatch"
    return hunks, "traps.json"


def extract_findings(text):
    """(findings list, reason) from a session's final text.

    The run is asked to end with its findings as a fenced JSON block. The LAST
    block tagged json or jsonc is read, or the last untagged block when no
    block carries either tag: a session that shows an example block first and
    its answer last must be scored on its answer, and a python, bash or bare
    block around the answer (a suggested fix, a repro) is not the answer. A bare JSON array with no fence is accepted too. reason is None
    on success, otherwise the incomplete reason the run is recorded under.
    """
    if not isinstance(text, str) or not text.strip():
        return None, "no-findings-block"
    found = fenced_blocks(text)
    blocks = [body for tag, body in found if tag in ANSWER_TAGS] \
        or [body for tag, body in found if tag == ""]
    if blocks:
        try:
            parsed = json.loads(blocks[-1])
        except ValueError:
            return None, "malformed-json"
        if not isinstance(parsed, list):
            return None, "findings-not-a-list"
        return parsed, None
    stripped = text.strip()
    if stripped.startswith("["):
        try:
            parsed = json.loads(stripped)
        except ValueError:
            return None, "malformed-json"
        if not isinstance(parsed, list):
            return None, "findings-not-a-list"
        return parsed, None
    return None, "no-findings-block"


def finding_line(value):
    """A finding's line number as an int, or None when it is not one."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        match = re.match(r"^\s*(\d+)", value)
        if match:
            return int(match.group(1))
    return None


def in_any_hunk(line, hunks):
    return any(start <= line <= end for start, end in hunks)


def score_review(case_dir, trap, findings_text):
    """Score one review run against one trap variant.

    A run is a `hit` when at least one P1/P2 finding cites the case's module and
    a line inside a hunk of the reference→variant diff. Every other P1/P2
    finding is a `false_finding` — including a second finding on the same hunk,
    because the run was asked for the defect, not for a list of remarks about
    the changed lines. A run with no findings is a miss with no false findings.
    A run whose findings block is missing or unparseable is incomplete: it is
    scored as a miss and carries the reason, so it can be told apart from a run
    that reviewed the diff and found nothing.
    """
    _ref_path, _var_path, module, _entry = variant_paths(case_dir, trap)
    hunks, hunks_source = hunks_for_trap(case_dir, trap)
    record = {
        "case": os.path.basename(os.path.abspath(case_dir)),
        "trap": trap,
        "module": module,
        "changed_lines": hunks,
        "changed_lines_source": hunks_source,
        "hit": False,
        "hits": 0,
        "in_hunk_findings": 0,
        "false_findings": 0,
        "scored_findings": 0,
        "findings_total": 0,
        "ignored_findings": 0,
        "incomplete": False,
        "reason": None,
        "confidences": {},
    }
    findings, reason = extract_findings(findings_text)
    if findings is None:
        record["incomplete"] = True
        record["reason"] = reason
        return record
    record["findings_total"] = len(findings)
    wanted = module + ".py"
    for finding in findings:
        if not isinstance(finding, dict):
            record["ignored_findings"] += 1
            continue
        priority = str(finding.get("priority", "")).strip().upper()
        if priority not in SCORED_PRIORITIES:
            record["ignored_findings"] += 1
            continue
        record["scored_findings"] += 1
        confidence = str(finding.get("confidence", "")).strip().upper() or "UNSTATED"
        line = finding_line(finding.get("line"))
        cited = os.path.basename(str(finding.get("file", "")).strip())
        inside = cited in (wanted, module) and line is not None and in_any_hunk(line, hunks)
        if inside:
            record["in_hunk_findings"] += 1
        # The first in-hunk finding is the run's hit. Every finding after it is
        # false, in-hunk or not: the run was asked for the defect, not for a
        # list of remarks about the changed lines. Without this, a run that
        # raises one P1 per changed line — which it can read straight off the
        # branch diff it is handed — scores perfect precision in both arms and
        # the eval measures nothing.
        is_hit = inside and not record["hit"]
        if is_hit:
            record["hit"] = True
        else:
            record["false_findings"] += 1
        # Location, not outcome. The report renders these as "On a changed
        # line" / "Elsewhere", which is a calibration question: does the run
        # know when it is guessing. Bucketing by the hit rule instead put a
        # second finding that IS on a changed line under "Elsewhere". These
        # therefore do not sum to hits + false_findings, and should not.
        bucket = record["confidences"].setdefault(confidence, {"in_hunk": 0, "false": 0})
        bucket["in_hunk" if inside else "false"] += 1
    record["hits"] = 1 if record["hit"] else 0
    return record


def cmd_score_review(args):
    opts = parse_opts(args, ["--case", "--trap", "--findings"])
    for key in ("--case", "--trap", "--findings"):
        if not opts.get(key):
            die("score-review --case <dir> --trap <name> --findings <file|json>")
    source = opts["--findings"]
    text = read_text(source) if os.path.isfile(source) else source
    print(json.dumps(score_review(opts["--case"], opts["--trap"], text), indent=2, sort_keys=True))


def has_hidden_suite(case_dir):
    return os.path.isfile(os.path.join(case_dir, "hidden", "test_hidden.py"))


def same_failures(case_dir, variant_path, materialized_text):
    """Does the materialized module fail exactly the tests the shipped variant fails?

    Substituting the variant into the reference must not change what the defect
    does. When it does, the case is measuring something other than the seeded
    bug, and that is a broken case rather than a result.
    """
    scratch = tempfile.mkdtemp(prefix="flow-eval-materialize.")
    try:
        path = os.path.join(scratch, "materialized.py")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(materialized_text)
        raw_parsed, _ = run_hidden(case_dir, None, variant_path)
        new_parsed, _ = run_hidden(case_dir, None, path)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    before = sorted(raw_parsed["failed_ids"])
    after = sorted(new_parsed["failed_ids"])
    if before == after:
        return True, "%d failing test(s)" % len(after)
    return False, "variant fails %s, materialized fails %s" % (before, after)


def check_cases_review(evals_dir, only=None, write=True, verify_behaviour=True):
    """Every trap variant must differ from the reference on at least one line,
    and its changed hunks are recorded into hidden/traps.json as changed_lines.

    A variant identical to the reference makes a hit impossible, so the run
    would score 0% recall for a defect that is not there. That is a broken
    case, not a result, and it fails the check.
    """
    problems = []
    report = {}
    examined = 0
    behaviour_checked = 0
    for case in sorted(os.listdir(evals_dir)):
        case_dir = os.path.join(evals_dir, case)
        if not os.path.isfile(os.path.join(case_dir, "prompt.md")) or (only and case != only):
            continue
        traps_path = os.path.join(case_dir, "hidden", "traps.json")
        traps = load_traps(case_dir)
        ref_path = os.path.join(case_dir, "hidden", "reference_impl.py")
        if not os.path.isfile(ref_path):
            problems.append("%s: no hidden/reference_impl.py to diff against" % case)
            continue
        ref_text = strip_module_docstring(read_text(ref_path))
        entry = {"module": traps["module"], "traps": {}}
        if not traps["traps"]:
            problems.append("%s: no trap variants to diff" % case)
        for name in sorted(traps["traps"]):
            trap = traps["traps"][name]
            var_path = os.path.join(case_dir, trap["variant"])
            if not os.path.isfile(var_path):
                problems.append("%s/%s: missing variant %s" % (case, name, trap["variant"]))
                continue
            examined += 1
            try:
                materialized = strip_module_docstring(
                    materialize_variant(read_text(ref_path), read_text(var_path)))
            except SyntaxError as exc:
                problems.append("%s/%s: variant cannot be materialized into the reference: %s" % (case, name, exc))
                continue
            hunks, differs = changed_hunks(ref_text, materialized)
            if not differs:
                problems.append("%s/%s: variant is identical to the reference, so no finding can hit it" % (case, name))
            elif not hunks:
                problems.append("%s/%s: variant differs but has no line a finding could cite" % (case, name))
            # The variant still calls into reference_impl, so the module under
            # review says it is one. Recorded rather than fixed: the fix is new
            # case content, not a change to the harness. It is written into
            # traps.json as well as the report because
            # references/review-precision-eval.md tells the operator to read it
            # there; the runner does not read it, it recomputes the same
            # question from the materialized text through `variant-delegates`.
            delegates = "reference_impl" in materialized
            trap["changed_lines"] = hunks
            # Pins what the hunks were computed from, so scoring can tell a
            # record that still describes the diff from one that does not.
            trap["changed_lines_digest"] = sources_digest(ref_text, materialized)
            trap["delegates_to_reference"] = delegates
            entry["traps"][name] = {
                "changed_lines": hunks,
                "changed_line_count": sum(e - s + 1 for s, e in hunks),
                "delegates_to_reference": delegates,
            }
            if verify_behaviour and not has_hidden_suite(case_dir):
                entry["traps"][name]["behaviour_matches_variant"] = None
                entry["traps"][name]["behaviour_unverified"] = "no hidden/test_hidden.py"
            elif verify_behaviour:
                same, detail = same_failures(case_dir, var_path, materialized)
                entry["traps"][name]["behaviour_matches_variant"] = same
                behaviour_checked += 1
                if not same:
                    problems.append("%s/%s: the materialized variant does not behave as the variant (%s)" % (case, name, detail))
        if write:
            write_json(traps_path, traps)
        report[case] = entry
    if examined == 0:
        problems.append("no trap variants were examined under %s — the check reached nothing" % evals_dir)
    return report, problems, examined, behaviour_checked


def review_case_prompt(case_dir, module, base_branch="main", head_branch="review-candidate"):
    """The review prompt for one scratch repository."""
    template = os.path.join(os.path.dirname(os.path.abspath(case_dir)), "review-prompt.md")
    text = read_text(template)
    return (text.replace("{{MODULE}}", module)
                .replace("{{MODULE_FILE}}", module + ".py")
                .replace("{{BASE_BRANCH}}", base_branch)
                .replace("{{HEAD_BRANCH}}", head_branch))


def cmd_review_prompt(args):
    opts = parse_opts(args, ["--base-branch", "--head-branch"])
    if len(opts["_"]) != 1:
        die("review-prompt <case-dir> [--base-branch B] [--head-branch H]")
    case_dir = opts["_"][0]
    module = load_traps(case_dir)["module"]
    sys.stdout.write(review_case_prompt(case_dir, module,
                                        opts.get("--base-branch") or "main",
                                        opts.get("--head-branch") or "review-candidate"))


def cmd_list_traps(args):
    """Trap names for one case, one per line — the runner's loop variable.

    bash 3.2 has no associative arrays, so the per-case trap list is read from
    here rather than built in the shell."""
    opts = parse_opts(args, [])
    if len(opts["_"]) != 1:
        die("list-traps <case-dir>")
    for name in sorted(load_traps(opts["_"][0])["traps"]):
        print(name)


def cmd_finalize_review_run(args):
    opts = parse_opts(args, ["--run-dir", "--case-dir", "--arm", "--case", "--trap", "--run",
                             "--exit-code", "--duration", "--model-requested", "--effort-requested"],
                      flags=["--timed-out"])
    for key in ("--run-dir", "--case-dir", "--arm", "--case", "--trap", "--run"):
        if not opts.get(key):
            die("finalize-review-run missing %s" % key)
    run_dir = opts["--run-dir"]
    os.makedirs(run_dir, exist_ok=True)
    result_event, tool_counts, skills, events = parse_stream(os.path.join(run_dir, "stream.jsonl"))
    if result_event is not None:
        write_json(os.path.join(run_dir, "claude.json"), result_event)
    model, models_used = models_from_result_event(result_event)
    tokens = tokens_from_result_event(result_event)
    exit_code = int(opts.get("--exit-code") or 0)
    timed_out = bool(opts.get("--timed-out"))
    final_text = str(result_event.get("result") or "") if result_event else ""
    with open(os.path.join(run_dir, "findings.txt"), "w", encoding="utf-8") as fh:
        fh.write(final_text)
    review = score_review(opts["--case-dir"], opts["--trap"], final_text)
    if timed_out and not review["incomplete"]:
        review["incomplete"] = True
        review["reason"] = "timeout"
    agents = agents_dispatched(os.path.join(run_dir, "stream.jsonl"))
    # Each arm must run what it is named for, or scoring it as that arm makes
    # the two arms look alike. The critic arm: a run that reported a P1 or P2
    # finding and never ran finding-critic ran the plain review. A critic-arm
    # run with no P1 or P2 finding gave the critic nothing to audit, and stays
    # scored. The plain arm: any run of finding-critic is the critic arm.
    if not review["incomplete"]:
        if (opts["--arm"] == "review-b-critic" and review["scored_findings"] > 0
                and not critic_ran(agents)):
            review["incomplete"] = True
            review["reason"] = "critic-not-dispatched"
        elif opts["--arm"] == "review-b" and critic_ran(agents):
            review["incomplete"] = True
            review["reason"] = "critic-dispatched-in-plain-arm"
    write_json(os.path.join(run_dir, "review-score.json"), review)
    is_error = bool(result_event.get("is_error")) if result_event else True
    error = None
    if timed_out:
        error = "timeout"
    elif result_event is None:
        error = "no result event (exit %d)" % exit_code
    elif is_error:
        error = str(result_event.get("result") or result_event.get("subtype") or "is_error")[:300]
    elif exit_code != 0:
        error = "claude exit %d" % exit_code
    result = {
        "mode": "review",
        "arm": opts["--arm"],
        "case": opts["--case"],
        "trap": opts["--trap"],
        "run": int(opts["--run"]),
        "model": model,
        "models_used": models_used,
        "model_requested": opts.get("--model-requested") or None,
        "effort_requested": opts.get("--effort-requested") or None,
        "cost_usd": num(result_event, "total_cost_usd") if result_event else None,
        "tokens": tokens,
        "num_turns": num(result_event, "num_turns") if result_event else None,
        "session_id": result_event.get("session_id") if result_event else None,
        "is_error": is_error,
        "error": error,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "duration_s": float(opts["--duration"]) if opts.get("--duration") else None,
        "stream_events": events,
        "tool_counts": tool_counts,
        "skills_invoked": skills,
        "agents_dispatched": agents,
        # A review run is granted read-only tools; an attempt to use Write or
        # Edit is the run rewriting the module instead of reviewing it, and
        # references/review-precision-eval.md says it is recorded here.
        "permission_denials": (result_event.get("permission_denials") or []) if result_event else [],
        "review": review,
    }
    write_json(os.path.join(run_dir, "result.json"), result)
    print(json.dumps({"hit": review["hit"], "false_findings": review["false_findings"],
                      "incomplete": review["incomplete"], "reason": review["reason"],
                      "cost_usd": result["cost_usd"], "model": model, "error": error}))


# --------------------------------------------------- review-mode aggregation

def review_record(record):
    value = record.get("review")
    return value if isinstance(value, dict) else {}


def f1(precision, recall):
    if precision is None or recall is None or (precision + recall) == 0:
        return 0.0 if (precision is not None and recall is not None) else None
    return 2 * precision * recall / (precision + recall)


def summarize_review_runs(rs):
    scored = [r for r in rs if not review_record(r).get("incomplete")]
    hits = sum(1 for r in scored if review_record(r).get("hit"))
    false = sum(review_record(r).get("false_findings") or 0 for r in scored)
    recall = (hits / float(len(scored))) if scored else None
    precision = (hits / float(hits + false)) if (hits + false) else (0.0 if scored else None)
    confidences = {}
    for r in scored:
        for name, bucket in (review_record(r).get("confidences") or {}).items():
            entry = confidences.setdefault(str(name), {"in_hunk": 0, "false": 0})
            entry["in_hunk"] += bucket.get("in_hunk") or 0
            entry["false"] += bucket.get("false") or 0
    return {
        "runs": len(rs),
        "scored_runs": len(scored),
        "incomplete_runs": len(rs) - len(scored),
        "incomplete_reasons": sorted({str(review_record(r).get("reason") or "unknown")
                                      for r in rs if review_record(r).get("incomplete")}),
        "hits": hits,
        "false_findings": false,
        "recall": recall,
        "precision": precision,
        "f1": f1(precision, recall),
        "findings_per_run": mean([review_record(r).get("scored_findings") for r in scored]),
        "cost_usd_mean": mean([r.get("cost_usd") for r in rs]),
        "cost_usd_total": sum(r.get("cost_usd") or 0 for r in rs),
        "num_turns_mean": mean([r.get("num_turns") for r in rs]),
        "output_tokens_mean": mean([run_tokens(r).get("output") for r in rs]),
        "output_tokens_scored_runs": sum(1 for r in rs if run_tokens(r).get("output") is not None),
        "cache_hit_rate_mean": mean([run_tokens(r).get("cache_hit_rate") for r in rs]),
        "cache_hit_rate_scored_runs": sum(1 for r in rs if run_tokens(r).get("cache_hit_rate") is not None),
        "token_fallback_runs": sum(1 for r in rs if all_tokens(r).get("source") == "usage"),
        "token_entries_skipped": sum(all_tokens(r).get("entries_skipped") or 0 for r in rs),
        "effort_requested": sorted({str(r.get("effort_requested") or "unpinned") for r in rs}),
        "errors": sum(1 for r in rs if r.get("error")),
        "confidences": confidences,
    }


def replication_f1s(rs):
    """F1 per replication of the matrix, for one model and arm.

    Run n of every case and trap is one independent replication: a full pass
    over the same defects. A single run's F1 is 1 or 0 on recall and so says
    nothing about stability, which is why the spread is taken between whole
    replications rather than between runs.
    """
    by_index = {}
    for r in rs:
        by_index.setdefault(r.get("run"), []).append(r)
    values = []
    for index in sorted(by_index, key=lambda v: (v is None, v)):
        value = summarize_review_runs(by_index[index])["f1"]
        if value is not None:
            values.append(value)
    return values


def aggregate_review_model(runs):
    cells = {}
    for r in runs:
        cells.setdefault((r["arm"], r["case"], r.get("trap") or "-"), []).append(r)
    arms = sorted({a for a, _, _ in cells}, key=lambda a: REVIEW_ARMS.index(a) if a in REVIEW_ARMS else 99)
    cases = sorted({c for _, c, _ in cells})
    cell_summary = {}
    for (arm, case, trap), rs in cells.items():
        entry = summarize_review_runs(rs)
        entry.update({"arm": arm, "case": case, "trap": trap})
        cell_summary["%s/%s/%s" % (arm, case, trap)] = entry
    arm_summary = {}
    spreads = []
    for arm in arms:
        rs = [r for r in runs if r["arm"] == arm]
        entry = summarize_review_runs(rs)
        entry["cases"] = sorted({r["case"] for r in rs})
        values = replication_f1s(rs)
        entry["replication_f1"] = values
        entry["f1_spread"] = (max(values) - min(values)) if len(values) >= 2 else None
        spreads.append(entry["f1_spread"])
        arm_summary[arm] = entry
    spread = mean(spreads)
    return {
        "runs": len(runs),
        "arms": arms,
        "cases": cases,
        "total_cost_usd": sum(r.get("cost_usd") or 0 for r in runs),
        "run_to_run_spread": spread,
        "per_arm": arm_summary,
        "per_cell": cell_summary,
    }


def decide_review(per_model):
    """The adoption rule from references/review-precision-eval.md.

    `review.groundingCritic` becomes the default only when the critic arm's F1
    beats the plain arm's by more than that model's run-to-run spread on every
    model, and at least two models ran. Anything else is recorded as a
    no-change outcome, which is a result and not a failure.

    Incomplete runs are left out of F1, so an arm whose misses time out reads
    better than it is. When, on any model, the critic arm's share of incomplete
    runs exceeds the plain arm's by more than one run's worth, a verdict that
    would adopt the critic is inconclusive instead.
    """
    models = sorted(per_model)
    deltas = {}
    sentences = []
    improved = []
    breaks_more = []
    for model in models:
        m = per_model[model]
        base_arm = m["per_arm"].get("review-b") or {}
        critic_arm = m["per_arm"].get("review-b-critic") or {}
        if base_arm.get("runs") and critic_arm.get("runs"):
            base_share = base_arm["incomplete_runs"] / float(base_arm["runs"])
            critic_share = critic_arm["incomplete_runs"] / float(critic_arm["runs"])
            one_run = 1.0 / max(base_arm["runs"], critic_arm["runs"])
            sentences.append("[%s] %d of %d critic runs and %d of %d plain runs were incomplete." % (
                model, critic_arm["incomplete_runs"], critic_arm["runs"],
                base_arm["incomplete_runs"], base_arm["runs"]))
            if critic_share - base_share > one_run + 1e-9:
                breaks_more.append(model)
        base = base_arm.get("f1")
        critic = critic_arm.get("f1")
        spread = m.get("run_to_run_spread")
        if base is None or critic is None:
            deltas[model] = None
            sentences.append("[%s] one of the two arms has no scored run, so the rule cannot be applied." % model)
            continue
        if spread is None:
            deltas[model] = None
            sentences.append("[%s] the matrix ran only once, so there is no run-to-run spread to beat; "
                             "the rule needs at least two runs per case and trap." % model)
            continue
        delta = critic - base
        deltas[model] = delta
        beats = delta > spread
        improved.append(beats)
        sentences.append(
            "[%s] F1 is %s with the critic against %s without it, a change of %+.3f against a run-to-run spread of %.3f, "
            "which %s the spread." % (model, fmt(critic, 3), fmt(base, 3), delta, spread,
                                      "clears" if beats else "does not clear"))
    if len(models) < 2:
        verdict = "insufficient-models"
        sentences.append("The rule needs at least two models; %d ran." % len(models))
    elif improved and all(improved) and len(improved) == len(models) and breaks_more:
        verdict = "inconclusive-incomplete-runs-differ"
        sentences.append("Every model improves by more than its spread, but on %s the critic arm left more runs "
                         "incomplete than the plain arm by more than one run, and incomplete runs are not in F1; "
                         "the rule makes no change until that is explained." % ", ".join(breaks_more))
    elif improved and all(improved) and len(improved) == len(models):
        verdict = "adopt-critic"
        sentences.append("Every model improves by more than its spread, so the rule says review.groundingCritic defaults to on.")
    else:
        verdict = "keep-off"
        sentences.append("Not every model improves by more than its spread, so the rule says review.groundingCritic stays off.")
    return {"verdict": verdict, "deltas": deltas, "reading": " ".join(sentences)}


def aggregate_review(out_dir):
    skipped = []
    runs = [r for r in load_results(out_dir, skipped) if r.get("mode") == "review"]
    models = sorted({r["_model"] for r in runs})
    per_model = {m: aggregate_review_model([r for r in runs if r["_model"] == m]) for m in models}
    decision = decide_review(per_model)
    # A record that could not be read might be a critic run that broke; the
    # rule does not adopt the critic while part of the data is unseen.
    if skipped and decision["verdict"] == "adopt-critic":
        decision["verdict"] = "inconclusive-unreadable-records"
        decision["reading"] += (" %d result record(s) could not be read or were abandoned, so the rule makes no change until they are rerun."
                                % len(skipped))
    summary = {
        "mode": "review",
        "runs": len(runs),
        "models": models,
        "arms": sorted({a for m in per_model.values() for a in m["arms"]},
                       key=lambda a: REVIEW_ARMS.index(a) if a in REVIEW_ARMS else 99),
        "cases": sorted({c for m in per_model.values() for c in m["cases"]}),
        "total_cost_usd": sum(r.get("cost_usd") or 0 for r in runs),
        "runs_without_cost": sum(1 for r in runs if r.get("cost_usd") is None),
        "per_model": per_model,
        "decision": decision,
        "unreadable_records": len(skipped),
    }
    write_summaries(out_dir, summary, render_review_summary_md(summary))
    return summary


ADOPTION_RULE = ("Adoption rule: `review.groundingCritic` becomes the default only when the critic arm's F1 beats the "
                 "plain arm's by more than that model's run-to-run spread on every model that ran, with at least two "
                 "models. No improvement is a valid recorded outcome, not a failed run. Incomplete runs are not in F1, so when "
                 "the critic arm leaves more runs incomplete than the plain arm by more than one run's worth on any "
                 "model, a result that would adopt the critic is inconclusive instead.")
SPREAD_NOTE = ("Spread is how much F1 moves between repeats of the same matrix. Run 1 of every case and trap is one "
               "replication, run 2 is the next, and so on; each replication gets its own F1, and an arm's spread is the "
               "largest of those minus the smallest. A model's spread is the mean over its arms. A single run is not a "
               "replication, so a matrix run once has no spread and the adoption rule cannot be applied to it.")
REVIEW_METRIC_NOTE = ("Precision is the share of scored P1/P2 findings that were a run's hit — the first finding to "
                      "land on a changed line of the seeded defect. Every other scored finding is false, including a "
                      "further finding on a hunk the run already hit, so a run contributes at most one hit however "
                      "many findings it raises. Recall is the share of runs that found the defect at all. Higher is "
                      "better for both, "
                      "and for F1. Findings per run counts only P1/P2 findings. Incomplete runs — no findings block, "
                      "unparseable JSON, or a timeout — are excluded from precision, recall and F1 and counted on "
                      "their own, so a broken run never reads as a clean miss.")


def render_review_summary_md(s):
    lines = ["# Flow review-precision eval — summary", ""]
    efforts = sorted({e for m in s["per_model"].values() for a in m["per_arm"].values()
                      for e in (a.get("effort_requested") or [])})
    lines.append("Runs: %d across %d model(s), %d arm(s) and %d case(s). Total cost: $%.2f. Models: %s. Effort: %s."
                 % (s["runs"], len(s["models"]), len(s["arms"]), len(s["cases"]), s["total_cost_usd"],
                    ", ".join("`%s`" % md_cell(m) for m in s["models"]) or "none",
                    ", ".join("`%s`" % md_cell(e) for e in efforts) or "none"))
    if s.get("unreadable_records"):
        lines.append("")
        lines.append("%d result record%s could not be read or %s abandoned, and %s not in these numbers."
                     % (s["unreadable_records"], "" if s["unreadable_records"] == 1 else "s",
                        "was" if s["unreadable_records"] == 1 else "were",
                        "is" if s["unreadable_records"] == 1 else "are"))
    if s.get("runs_without_cost"):
        lines.append("")
        lines.append("%d run%s reported no cost (a timeout or a crash), so the total above leaves %s out; each may have spent up to the per-run cap."
                     % (s["runs_without_cost"], "" if s["runs_without_cost"] == 1 else "s",
                        "it" if s["runs_without_cost"] == 1 else "them"))
    lines.append("")
    lines.append("## Reading")
    lines.append("")
    lines.append(s["decision"]["reading"] or "No runs found.")
    lines.append("")
    lines.append(ADOPTION_RULE)
    lines.append("")
    lines.append("Verdict: `%s`" % s["decision"]["verdict"])
    lines.append("")
    lines.append("## Per model × arm")
    lines.append("")
    lines.append("| Model | Arm | Effort | Runs | Scored | Precision | Recall | F1 | Findings per run | Cost (mean) | Cache hits | Output tokens | Spread | Errors | Incomplete |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for arm in m["arms"]:
            a = m["per_arm"][arm]
            lines.append("| %s | %s | %s | %d | %d | %s | %s | %s | %s | $%s | %s | %s | %s | %d | %s |" % (
                md_cell(model), md_cell(arm), effort_cell(a), a["runs"], a["scored_runs"],
                fmt(a["precision"], pct=True), fmt(a["recall"], pct=True), fmt(a["f1"], 3),
                fmt(a["findings_per_run"], 1), fmt(a["cost_usd_mean"]),
                token_cell(a, "cache_hit_rate_mean", "cache_hit_rate_scored_runs", pct=True),
                token_cell(a, "output_tokens_mean", "output_tokens_scored_runs"),
                fmt(a.get("f1_spread"), 3), a["errors"], review_incomplete_cell(a)))
    lines.append("")
    lines.append(REVIEW_METRIC_NOTE)
    lines.append("")
    lines.append(SPREAD_NOTE)
    lines.append("")
    lines.append("## Per model × arm × case × trap")
    lines.append("")
    lines.append("| Model | Arm | Case | Trap | Runs | Scored | Hits | False findings | Precision | Recall | F1 | Cost | Incomplete |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for key in sorted(m["per_cell"]):
            c = m["per_cell"][key]
            lines.append("| %s | %s | %s | %s | %d | %d | %d | %d | %s | %s | %s | $%s | %s |" % (
                md_cell(model), md_cell(c["arm"]), md_cell(c["case"]), md_cell(c["trap"]), c["runs"], c["scored_runs"],
                c["hits"], c["false_findings"], fmt(c["precision"], pct=True), fmt(c["recall"], pct=True),
                fmt(c["f1"], 3), fmt(c["cost_usd_mean"]), review_incomplete_cell(c)))
    lines.append("")
    lines.append("## Confidence against where the finding landed")
    lines.append("")
    lines.append("| Model | Arm | Confidence | On a changed line | Elsewhere |")
    lines.append("|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for arm in m["arms"]:
            for name in sorted(m["per_arm"][arm].get("confidences") or {}):
                bucket = m["per_arm"][arm]["confidences"][name]
                lines.append("| %s | %s | %s | %d | %d |" % (md_cell(model), md_cell(arm), md_cell(name),
                                                             bucket["in_hunk"], bucket["false"]))
    lines.append("")
    return "\n".join(lines) + "\n"


def review_incomplete_cell(entry):
    if not entry.get("incomplete_runs"):
        return "0"
    return "%d (%s)" % (entry["incomplete_runs"], ", ".join(entry.get("incomplete_reasons") or []))


# ------------------------------------------------------------------- driver

def parse_opts(args, keys, flags=()):
    opts = {"_": []}
    i = 0
    while i < len(args):
        a = args[i]
        if a in keys:
            if i + 1 >= len(args):
                die("%s requires a value" % a)
            opts[a] = args[i + 1]
            i += 2
        elif a in flags:
            opts[a] = True
            i += 1
        elif a.startswith("--"):
            die("unknown option %s" % a)
        else:
            opts["_"].append(a)
            i += 1
    return opts


COMMANDS = {
    "case-meta": cmd_case_meta,
    "case-prompt": cmd_case_prompt,
    "parse-unittest": cmd_parse_unittest,
    "hidden-run": cmd_hidden_run,
    "agent-tests": cmd_agent_tests,
    "own-test-traps": cmd_own_test_traps,
    "rescore-own-tests": cmd_rescore_own_tests,
    "rescore-hidden": cmd_rescore_hidden,
    "finalize-run": cmd_finalize_run,
    "aggregate": cmd_aggregate,
    "migrate-layout": cmd_migrate_layout,
    "check-cases": cmd_check_cases,
    "score-review": cmd_score_review,
    "review-prompt": cmd_review_prompt,
    "list-traps": cmd_list_traps,
    "materialize-variant": cmd_materialize_variant,
    "reference-module": cmd_reference_module,
    "variant-delegates": cmd_variant_delegates,
    "finalize-review-run": cmd_finalize_review_run,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        sys.stderr.write(__doc__)
        return 2
    COMMANDS[argv[1]](argv[2:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
