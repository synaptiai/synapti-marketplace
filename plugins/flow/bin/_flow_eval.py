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
                                              every test listed for it in traps.json
  agent-tests --project-dir P                 count the agent's own tests and classify
                                              their literal sequence inputs
  finalize-run --run-dir R --case-dir C       parse stream.jsonl, grade, write result.json,
              --project-dir P --arm A         hidden.txt, agent-tests-summary.json
              --case NAME --run N --exit-code X
              [--timed-out] [--duration S] [--temp-dir T]
  aggregate   --out DIR                       summary.json + summary.md from DIR/runs
  check-cases --evals-dir DIR [--case NAME]   reference passes, every trap variant fails
                                              its listed tests; exit 1 on any violation

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


def parse_unittest(text):
    """Parse `python -m unittest -v` output. Returns {tests:{id:status}, passed, total, ...}.

    Handles the docstring layout, where the status lands on the line after the
    test id, and treats a test whose status never appears (crash, timeout) as
    an error.
    """
    tests = {}
    order = []
    pending = None
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        m = TEST_LINE_RE.match(line)
        if m:
            test_id = m.group(1)
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
    for line in text.splitlines():
        m = RAN_RE.match(line)
        if m:
            ran = int(m.group(1))
    passed = sum(1 for t in order if tests[t] == "ok")
    failed = [t for t in order if tests[t] in ("FAIL", "ERROR", "missing")]
    return {
        "tests": {t: tests[t] for t in order},
        "order": order,
        "passed": passed,
        "total": len(order),
        "failed_ids": failed,
        "ran_line": ran,
        "completed": ran is not None and ran == len(order),
    }


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
        except subprocess.TimeoutExpired as exc:
            raw = (exc.stdout or "") + (exc.stderr or "")
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", "replace")
            raw += "\n[flow-eval] hidden suite timed out after %ss\n" % timeout
            timed_out = True
    finally:
        if scratch is not None:
            shutil.rmtree(scratch, ignore_errors=True)
    parsed = parse_unittest(raw)
    parsed["timed_out"] = timed_out
    # Import failure or crash before any test ran: score 0 over the known suite size.
    expected_ids = sorted({t for trap in traps["traps"].values() for t in trap["discriminating_tests"]})
    if parsed["total"] == 0:
        parsed["total"] = count_hidden_tests(case_dir)
        parsed["passed"] = 0
        parsed["failed_ids"] = []
        parsed["import_or_crash"] = True
    else:
        parsed["import_or_crash"] = False
    parsed["pass_rate"] = (parsed["passed"] / parsed["total"]) if parsed["total"] else 0.0
    parsed["all_pass"] = parsed["total"] > 0 and parsed["passed"] == parsed["total"]
    # Signature match: a trap is "caught" when the run fails every test its
    # variant fails (traps.json discriminating_tests). Some signatures are
    # subsets of others (a tie-order test also fails under round-half-up), so a
    # run can match several traps; an import failure matches all of them.
    parsed["traps"] = {}
    for name, trap in traps["traps"].items():
        ids = trap["discriminating_tests"]
        statuses = [parsed["tests"].get(t, "missing") for t in ids]
        failing = [t for t, s in zip(ids, statuses) if s != "ok"]
        tripped = parsed["import_or_crash"] or (bool(ids) and len(failing) == len(ids))
        parsed["traps"][name] = {
            "caught": tripped,
            "failing": list(ids) if parsed["import_or_crash"] else failing,
        }
    parsed["mapped_test_ids"] = expected_ids
    return parsed, raw


def count_hidden_tests(case_dir):
    tree = ast.parse(read_text(os.path.join(case_dir, "hidden", "test_hidden.py")))
    n = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name.startswith("test"):
            n += 1
    return n


def cmd_hidden_run(args):
    opts = parse_opts(args, ["--case-dir", "--project-dir", "--impl", "--timeout", "--out"])
    if not opts.get("--case-dir") or not (opts.get("--project-dir") or opts.get("--impl")):
        die("hidden-run --case-dir D (--project-dir P | --impl FILE) [--timeout S] [--out FILE]")
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


def cmd_finalize_run(args):
    opts = parse_opts(args, ["--run-dir", "--case-dir", "--project-dir", "--arm", "--case", "--run",
                             "--exit-code", "--duration", "--temp-dir", "--hidden-timeout"],
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

    hidden, raw = run_hidden(opts["--case-dir"], opts["--project-dir"], None, int(opts.get("--hidden-timeout") or 120))
    with open(os.path.join(run_dir, "hidden.txt"), "w", encoding="utf-8") as fh:
        fh.write(raw)
    agent = analyze_agent_tests(opts["--project-dir"])
    write_json(os.path.join(run_dir, "agent-tests-summary.json"), agent)

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
        "cost_usd": cost,
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
        "hidden": {
            "passed": hidden["passed"],
            "total": hidden["total"],
            "pass_rate": hidden["pass_rate"],
            "all_pass": hidden["all_pass"],
            "failed_ids": hidden["failed_ids"],
            "import_or_crash": hidden["import_or_crash"],
            "timed_out": hidden["timed_out"],
        },
        "traps": {name: t["caught"] for name, t in hidden["traps"].items()},
        "agent_tests": {
            "files": agent["file_count"],
            "test_functions": agent["test_functions"],
            "literal_inputs": agent["literal_inputs"],
            "degenerate_inputs": agent["degenerate_inputs"],
            "degenerate_share": agent["degenerate_share"],
        },
        "temp_dir": opts.get("--temp-dir"),
    }
    write_json(os.path.join(run_dir, "result.json"), result)
    print(json.dumps({"hidden_pass_rate": result["hidden"]["pass_rate"], "cost_usd": cost, "num_turns": turns,
                      "error": error, "test_functions": agent["test_functions"]}))


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


def load_results(out_dir):
    runs = []
    root = os.path.join(out_dir, "runs")
    if not os.path.isdir(root):
        return runs
    for arm in sorted(os.listdir(root)):
        for case in sorted(os.listdir(os.path.join(root, arm))):
            case_dir = os.path.join(root, arm, case)
            if not os.path.isdir(case_dir):
                continue
            for n in sorted(os.listdir(case_dir)):
                path = os.path.join(case_dir, n, "result.json")
                if os.path.exists(path):
                    try:
                        with open(path, encoding="utf-8") as fh:
                            runs.append(json.load(fh))
                    except ValueError:
                        sys.stderr.write("_flow_eval: skipping unreadable %s\n" % path)
    return runs


def aggregate(out_dir):
    runs = load_results(out_dir)
    cells = {}
    for r in runs:
        cells.setdefault((r["arm"], r["case"]), []).append(r)
    arms = sorted({a for a, _ in cells}, key=lambda a: ALL_ARMS.index(a) if a in ALL_ARMS else 99)
    cases = sorted({c for _, c in cells})
    cell_summary = {}
    for (arm, case), rs in cells.items():
        rates = [r["hidden"]["pass_rate"] for r in rs]
        traps = {}
        for name in sorted({t for r in rs for t in r.get("traps", {})}):
            hits = [r["traps"].get(name) for r in rs if name in r.get("traps", {})]
            traps[name] = mean([1.0 if h else 0.0 for h in hits])
        cell_summary["%s/%s" % (arm, case)] = {
            "arm": arm, "case": case, "runs": len(rs),
            "hidden_pass_rate_mean": mean(rates),
            "hidden_pass_rate_min": min(rates), "hidden_pass_rate_max": max(rates),
            "hidden_pass_rate_spread": max(rates) - min(rates),
            "all_pass_rate": mean([1.0 if r["hidden"]["all_pass"] else 0.0 for r in rs]),
            "trap_catch_rate": traps,
            "own_tests_mean": mean([r["agent_tests"]["test_functions"] for r in rs]),
            "degenerate_share_mean": mean([r["agent_tests"]["degenerate_share"] for r in rs]),
            "cost_usd_mean": mean([r["cost_usd"] for r in rs]),
            "num_turns_mean": mean([r["num_turns"] for r in rs]),
            "errors": sum(1 for r in rs if r.get("error")),
            "skills_invoked": sorted({s for r in rs for s in r.get("skills_invoked", [])}),
        }
    arm_summary = {}
    for arm in arms:
        rs = [r for r in runs if r["arm"] == arm]
        arm_cells = [c for c in cell_summary.values() if c["arm"] == arm]
        arm_summary[arm] = {
            "runs": len(rs),
            "cases": sorted({c["case"] for c in arm_cells}),
            "hidden_pass_rate_mean": mean([r["hidden"]["pass_rate"] for r in rs]),
            "all_pass_rate": mean([1.0 if r["hidden"]["all_pass"] else 0.0 for r in rs]),
            "own_tests_mean": mean([r["agent_tests"]["test_functions"] for r in rs]),
            "degenerate_share_mean": mean([r["agent_tests"]["degenerate_share"] for r in rs]),
            "cost_usd_mean": mean([r["cost_usd"] for r in rs]),
            "cost_usd_total": sum(r["cost_usd"] or 0 for r in rs),
            "num_turns_mean": mean([r["num_turns"] for r in rs]),
            "errors": sum(1 for r in rs if r.get("error")),
            "spread_mean": mean([c["hidden_pass_rate_spread"] for c in arm_cells]),
        }
    spread = mean([c["hidden_pass_rate_spread"] for c in cell_summary.values()])
    decision = decide(arm_summary, spread, cases)
    summary = {
        "runs": len(runs),
        "arms": arms,
        "cases": cases,
        "total_cost_usd": sum(r["cost_usd"] or 0 for r in runs),
        "run_to_run_spread": spread,
        "per_arm": arm_summary,
        "per_cell": cell_summary,
        "decision": decision,
    }
    write_json(os.path.join(out_dir, "summary.json"), summary)
    with open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write(render_summary_md(summary))
    return summary


def decide(arm_summary, spread, cases):
    """Apply the decision rule documented in references/correctness-eval.md."""
    def arm_mean(names):
        vals = [arm_summary[a]["hidden_pass_rate_mean"] for a in names if a in arm_summary]
        return mean(vals)

    enforce = arm_mean(["enforce-risk", "enforce-norisk"])
    suggest = arm_mean(["suggest-risk", "suggest-norisk"])
    off = arm_mean(["off-risk", "off-norisk"])
    risk = arm_mean(["enforce-risk", "suggest-risk", "off-risk"])
    norisk = arm_mean(["enforce-norisk", "suggest-norisk", "off-norisk"])
    baseline = arm_mean(["baseline"])
    best_alt = mean([v for v in (suggest, off) if v is not None]) if (suggest is not None or off is not None) else None
    best_alt = max(v for v in (suggest, off) if v is not None) if best_alt is not None else None
    complete = all(a in arm_summary for a in ALL_ARMS) and len(cases) >= 3 and all(
        arm_summary[a]["runs"] >= 3 * len(cases) for a in ALL_ARMS)
    sentences = []
    verdict = "insufficient-data"
    if enforce is None or best_alt is None or spread is None:
        sentences.append("Not enough arms have results to apply the decision rule (need at least one enforce-* arm and one suggest-*/off-* arm).")
    else:
        gap = best_alt - enforce
        alt_name = "suggest" if (suggest is not None and (off is None or suggest >= off)) else "off"
        if gap > spread:
            verdict = "flip-to-suggest"
            sentences.append(
                "Hidden pass rate under tddMode=enforce (%s) is below the best non-enforce plugin arm (%s, %s) by %.1f points, "
                "more than the run-to-run spread of %.1f points, so the rule says testing.tddMode should default to suggest."
                % (fmt(enforce, pct=True), alt_name, fmt(best_alt, pct=True), gap * 100, spread * 100))
        else:
            verdict = "keep-enforce"
            sentences.append(
                "Hidden pass rate under tddMode=enforce (%s) is not below the best non-enforce plugin arm (%s, %s) by more than "
                "the run-to-run spread (%.1f points vs %.1f), so the rule keeps testing.tddMode=enforce."
                % (fmt(enforce, pct=True), alt_name, fmt(best_alt, pct=True), gap * 100, spread * 100))
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
    if not complete:
        sentences.append("The comparison is incomplete (not every arm has >= 3 runs on every case); treat the reading as provisional.")
    return {
        "verdict": verdict,
        "enforce_mean": enforce, "suggest_mean": suggest, "off_mean": off,
        "risk_mean": risk, "norisk_mean": norisk, "baseline_mean": baseline,
        "spread": spread, "complete": complete,
        "reading": " ".join(sentences),
    }


def render_summary_md(s):
    lines = ["# Flow correctness eval — summary", ""]
    lines.append("Runs: %d across %d arm(s) and %d case(s). Total cost: $%.2f. Run-to-run spread (mean per-cell max−min of hidden pass rate): %s."
                 % (s["runs"], len(s["arms"]), len(s["cases"]), s["total_cost_usd"], fmt(s["run_to_run_spread"], pct=True)))
    lines.append("")
    lines.append("## Reading")
    lines.append("")
    lines.append(s["decision"]["reading"])
    lines.append("")
    lines.append("Verdict: `%s`" % s["decision"]["verdict"])
    lines.append("")
    lines.append("## Per arm")
    lines.append("")
    lines.append("| Arm | Runs | Hidden pass rate | All-pass runs | Own tests (mean) | Degenerate share | Cost (mean) | Turns (mean) | Errors |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for arm in s["arms"]:
        a = s["per_arm"][arm]
        lines.append("| %s | %d | %s | %s | %s | %s | $%s | %s | %d |" % (
            arm, a["runs"], fmt(a["hidden_pass_rate_mean"], pct=True), fmt(a["all_pass_rate"], pct=True),
            fmt(a["own_tests_mean"], 1), fmt(a["degenerate_share_mean"], pct=True), fmt(a["cost_usd_mean"]),
            fmt(a["num_turns_mean"], 1), a["errors"]))
    lines.append("")
    lines.append("## Per arm × case")
    lines.append("")
    lines.append("| Arm | Case | Runs | Hidden pass rate (min–max) | All-pass | Own tests | Degenerate share | Cost | Turns | Errors |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for arm in s["arms"]:
        for case in s["cases"]:
            c = s["per_cell"].get("%s/%s" % (arm, case))
            if not c:
                continue
            lines.append("| %s | %s | %d | %s (%s–%s) | %s | %s | %s | $%s | %s | %d |" % (
                arm, case, c["runs"], fmt(c["hidden_pass_rate_mean"], pct=True), fmt(c["hidden_pass_rate_min"], pct=True),
                fmt(c["hidden_pass_rate_max"], pct=True), fmt(c["all_pass_rate"], pct=True), fmt(c["own_tests_mean"], 1),
                fmt(c["degenerate_share_mean"], pct=True), fmt(c["cost_usd_mean"]), fmt(c["num_turns_mean"], 1), c["errors"]))
    lines.append("")
    lines.append("## Trap catch rate (share of runs whose implementation fell into the trap; lower is better)")
    lines.append("")
    for case in s["cases"]:
        traps = sorted({t for key, c in s["per_cell"].items() if c["case"] == case for t in c["trap_catch_rate"]})
        if not traps:
            continue
        lines.append("### %s" % case)
        lines.append("")
        lines.append("| Arm | " + " | ".join(traps) + " |")
        lines.append("|---|" + "---|" * len(traps))
        for arm in s["arms"]:
            c = s["per_cell"].get("%s/%s" % (arm, case))
            if not c:
                continue
            lines.append("| %s | " % arm + " | ".join(fmt(c["trap_catch_rate"].get(t), pct=True) for t in traps) + " |")
        lines.append("")
    lines.append("Skills invoked per cell are listed in summary.json (`per_cell.*.skills_invoked`); a plugin arm with no `flow:*` skill invocation did not exercise the plugin.")
    lines.append("")
    return "\n".join(lines)


def cmd_aggregate(args):
    opts = parse_opts(args, ["--out"])
    if not opts.get("--out"):
        die("aggregate --out DIR")
    summary = aggregate(opts["--out"])
    print(json.dumps({"runs": summary["runs"], "verdict": summary["decision"]["verdict"],
                      "total_cost_usd": summary["total_cost_usd"]}))


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
    "finalize-run": cmd_finalize_run,
    "aggregate": cmd_aggregate,
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
