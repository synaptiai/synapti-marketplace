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
                                              its listed tests; exit 1 on any violation

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
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

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
    # subsets of others (a tie-order test also fails under round-half-up), so a
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
    """Billed token counts summed over every modelUsage entry of a claude
    result event, falling back to the event's top-level `usage` (the last
    request only) when modelUsage carries no token fields.

    Returns {"input", "cache_read", "cache_creation", "output",
    "cache_hit_rate"} — counts are None when nothing was recorded;
    cache_hit_rate is cache_read over all input-side tokens."""
    empty = {"input": None, "cache_read": None, "cache_creation": None, "output": None, "cache_hit_rate": None}
    if not isinstance(result_event, dict):
        return empty
    fields = {"input": "inputTokens", "cache_read": "cacheReadInputTokens",
              "cache_creation": "cacheCreationInputTokens", "output": "outputTokens"}
    totals = {k: None for k in fields}
    usage = result_event.get("modelUsage")
    if isinstance(usage, dict):
        for entry in usage.values():
            if not isinstance(entry, dict):
                continue
            for key, name in fields.items():
                value = num(entry, name)
                if value is not None:
                    totals[key] = (totals[key] or 0) + value
    if all(v is None for v in totals.values()):
        top = result_event.get("usage")
        if isinstance(top, dict):
            snake = {"input": "input_tokens", "cache_read": "cache_read_input_tokens",
                     "cache_creation": "cache_creation_input_tokens", "output": "output_tokens"}
            totals = {key: num(top, name) for key, name in snake.items()}
    input_side = sum(totals[k] or 0 for k in ("input", "cache_read", "cache_creation"))
    totals["cache_hit_rate"] = ((totals["cache_read"] or 0) / input_side) if input_side else None
    return totals


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
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


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


def iter_run_dirs(out_dir):
    """Yield (run_dir, layout) for every result.json under out_dir/runs.

    New layout: runs/<model>/<arm>/<case>/<n>; old: runs/<arm>/<case>/<n>.
    The depth decides: a result.json four levels below runs/ is the new
    layout, three levels is the old one.
    """
    root = os.path.join(out_dir, "runs")
    if not os.path.isdir(root):
        return
    for dirpath, dirnames, names in os.walk(root):
        dirnames.sort()
        if "result.json" not in names:
            continue
        rel = os.path.relpath(dirpath, root).split(os.sep)
        if len(rel) == 4:
            yield dirpath, "model"
        elif len(rel) == 3:
            yield dirpath, "legacy"
        dirnames[:] = []


def load_results(out_dir):
    runs = []
    for run_dir, layout in iter_run_dirs(out_dir):
        path = os.path.join(run_dir, "result.json")
        try:
            with open(path, encoding="utf-8") as fh:
                record = json.load(fh)
        except ValueError:
            sys.stderr.write("_flow_eval: skipping unreadable %s\n" % path)
            continue
        if not isinstance(record, dict) or "arm" not in record or "case" not in record:
            sys.stderr.write("_flow_eval: skipping incomplete %s\n" % path)
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
        "cache_hit_rate_mean": mean([(r.get("tokens") or {}).get("cache_hit_rate") for r in rs]),
        "output_tokens_mean": mean([(r.get("tokens") or {}).get("output") for r in rs]),
        "effort_requested": sorted({str(r["effort_requested"]) for r in rs if r.get("effort_requested")}),
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
    runs = load_results(out_dir)
    models = sorted({r["_model"] for r in runs})
    per_model = {m: aggregate_model([r for r in runs if r["_model"] == m]) for m in models}
    summary = {
        "runs": len(runs),
        "models": models,
        "arms": sorted({a for m in per_model.values() for a in m["arms"]}, key=lambda a: ALL_ARMS.index(a) if a in ALL_ARMS else 99),
        "cases": sorted({c for m in per_model.values() for c in m["cases"]}),
        "total_cost_usd": sum(r["cost_usd"] or 0 for r in runs),
        "legacy_layout_runs": sum(1 for r in runs if r["_layout"] == "legacy"),
        "per_model": per_model,
        "decision": {
            "verdicts": {m: per_model[m]["decision"]["verdict"] for m in models},
            "reading": " ".join("[%s] %s" % (m, per_model[m]["decision"]["reading"]) for m in models)
                       or "No runs found.",
        },
    }
    write_json(os.path.join(out_dir, "summary.json"), summary)
    with open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write(render_summary_md(summary))
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
    lines.append("Runs: %d across %d model(s), %d arm(s) and %d case(s). Total cost: $%.2f. Models: %s."
                 % (s["runs"], len(s["models"]), len(s["arms"]), len(s["cases"]), s["total_cost_usd"],
                    ", ".join("`%s`" % m for m in s["models"]) or "none"))
    if s.get("legacy_layout_runs"):
        lines.append("")
        lines.append("%d run(s) were read from the older `runs/<arm>/<case>/<n>` layout; `_flow_eval.py migrate-layout --out <dir>` moves them under their model." % s["legacy_layout_runs"])
    lines.append("")
    lines.append("## Reading")
    lines.append("")
    for model in s["models"]:
        m = s["per_model"][model]
        lines.append("**%s** (%d runs, $%.2f, run-to-run spread %s, own-test spread %s): %s"
                     % (model, m["runs"], m["total_cost_usd"], fmt(m["run_to_run_spread"], pct=True),
                        fmt(m["own_test_trap_spread"], pct=True), m["decision"]["reading"]))
        lines.append("")
        lines.append("Verdict for `%s`: `%s`%s" % (model, m["decision"]["verdict"],
                     (" (decided by the %s signal)" % m["decision"]["decided_by"]) if m["decision"].get("decided_by") else ""))
        lines.append("")
    if not s["models"]:
        lines.append("No runs found.")
        lines.append("")
    lines.append("## Per model × arm")
    lines.append("")
    lines.append("| Model | Arm | Runs | Hidden pass rate | All-pass runs | Own tests catch traps | Own tests (mean) | Degenerate share | Cost (mean) | Turns (mean) | Errors | Incomplete |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for arm in m["arms"]:
            a = m["per_arm"][arm]
            lines.append("| %s | %s | %d | %s | %s | %s | %s | %s | $%s | %s | %d | %s |" % (
                model, arm, a["runs"], fmt(a["hidden_pass_rate_mean"], pct=True), fmt(a["all_pass_rate"], pct=True),
                own_cell(a), fmt(a["own_tests_mean"], 1), fmt(a["degenerate_share_mean"], pct=True), fmt(a["cost_usd_mean"]),
                fmt(a["num_turns_mean"], 1), a["errors"], incomplete_cell(a)))
    lines.append("")
    lines.append(INCOMPLETE_NOTE)
    lines.append("")
    lines.append("## Per model × arm × case")
    lines.append("")
    lines.append("| Model | Arm | Case | Runs | Hidden pass rate (min–max) | All-pass | Own tests catch traps | Own tests | Degenerate share | Cost | Turns | Errors | Incomplete |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in s["models"]:
        m = s["per_model"][model]
        for arm in m["arms"]:
            for case in m["cases"]:
                c = m["per_cell"].get("%s/%s" % (arm, case))
                if not c:
                    continue
                lines.append("| %s | %s | %s | %d | %s (%s–%s) | %s | %s | %s | %s | $%s | %s | %d | %s |" % (
                    model, arm, case, c["runs"], fmt(c["hidden_pass_rate_mean"], pct=True), fmt(c["hidden_pass_rate_min"], pct=True),
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
            lines.append("### %s — %s" % (model, case))
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
            lines.append("### %s — %s" % (model, case))
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
    opts = parse_opts(args, ["--out"])
    if not opts.get("--out"):
        die("aggregate --out DIR")
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
        dest = os.path.join(root, model.replace("/", "_"), arm, case, n)
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
    opts = parse_opts(args, ["--evals-dir", "--case"])
    if not opts.get("--evals-dir"):
        die("check-cases --evals-dir DIR [--case NAME]")
    report, problems = check_cases(opts["--evals-dir"], opts.get("--case"))
    print(json.dumps({"cases": report, "problems": problems}, indent=2, sort_keys=True))
    if problems or not report:
        sys.exit(1)


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
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        sys.stderr.write(__doc__)
        return 2
    COMMANDS[argv[1]](argv[2:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
