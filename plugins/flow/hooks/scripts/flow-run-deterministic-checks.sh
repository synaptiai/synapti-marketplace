#!/usr/bin/env bash
# [flow] Run a FlowGoal's deterministic verification commands and emit a
# structured report. Used by both flow-goal-stop.sh (warn mode) and
# flow-goal-evaluator.sh (evaluator-loop mode); the report tells the caller
# which ACs are pending evidence, which passed, and which failed.
#
# Usage:
#   flow-run-deterministic-checks.sh <goal-yaml-path>
#
# Stdout: JSON document with shape:
#   {
#     "goal_id": "issue-42",
#     "checked": [{"id": "AC1", "exit_code": 0, "must_pass": true}, ...],
#     "passing":         ["AC1", "AC3"],
#     "failing":         ["AC2"],
#     "incomplete_acs":  ["AC4"],            # ACs with no verification_command
#     "path_violations": ["src/billing/x.ts"]  # files outside allowed_paths
#   }
#
# Exits:
#   0 — report generated (caller decides what to do with it)
#   1 — input error (missing file, malformed YAML)
#   2 — infrastructure error (python3/PyYAML missing)
#
# Why this is a separate script: the report shape is reused by warn-mode
# (which formats it into a stderr warning) and by evaluator-loop mode
# (which feeds it to the judge subprocess). Keeping the deterministic
# work here makes the Stop hook scripts smaller and individually testable.

set -uo pipefail
export PYTHONSAFEPATH=1

# Graceful degradation — matches the pattern across other flow hooks.
if ! command -v python3 >/dev/null 2>&1; then
  echo '{"error": "python3 unavailable"}' >&2
  echo '{}'
  exit 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo '{"error": "PyYAML unavailable"}' >&2
  echo '{}'
  exit 0
fi

GOAL_YAML="${1:-}"
[ -z "$GOAL_YAML" ] && { echo "flow-run-deterministic-checks.sh: <goal-yaml-path> argument required" >&2; exit 1; }
[ -f "$GOAL_YAML" ] || { echo "flow-run-deterministic-checks.sh: goal yaml '$GOAL_YAML' does not exist" >&2; exit 1; }

python3 - "$GOAL_YAML" <<'PYTHON'
import json
import os
import subprocess
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml

goal_path = sys.argv[1]

try:
    with open(goal_path, "r", encoding="utf-8") as f:
        goal = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f"flow-run-deterministic-checks.sh: goal YAML parse error: {e}", file=sys.stderr)
    print(json.dumps({"error": f"yaml: {e}"}))
    sys.exit(1)

if not isinstance(goal, dict):
    print("flow-run-deterministic-checks.sh: goal YAML is not a mapping", file=sys.stderr)
    print(json.dumps({"error": "not a mapping"}))
    sys.exit(1)

metadata = goal.get("metadata") or {}
goal_id = metadata.get("id", "<unknown>")
acs = (goal.get("objective") or {}).get("acceptance_criteria", []) or []

report = {
    "goal_id": goal_id,
    "checked": [],
    "passing": [],
    "failing": [],
    "incomplete_acs": [],
    "path_violations": [],
}

# Per-AC deterministic check.
for ac in acs:
    if not isinstance(ac, dict):
        continue
    ac_id = ac.get("id", "<unknown>")
    cmd = ac.get("verification_command")
    must_pass = ac.get("must_pass", True)

    if not cmd:
        # Fuzzy criterion — no deterministic check possible. Report as
        # incomplete so the warn-mode hook surfaces it and the evaluator-loop
        # hook hands it to the LLM judge.
        report["incomplete_acs"].append(ac_id)
        continue

    # Run with a hard timeout to keep the Stop hook responsive. 30s is a
    # generous upper bound for test/lint commands; goal authors needing
    # longer-running checks should run them via /flow:goal evaluate
    # (which has no Stop-hook timeout pressure).
    try:
        result = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True,
            text=True,
            timeout=30,
        )
        exit_code = result.returncode
    except subprocess.TimeoutExpired:
        exit_code = 124
    except Exception as e:
        # Command couldn't even be launched (e.g., bash missing). Surface
        # as incomplete; the warn message will be clear.
        report["checked"].append({
            "id": ac_id,
            "exit_code": None,
            "must_pass": must_pass,
            "error": str(e),
        })
        report["incomplete_acs"].append(ac_id)
        continue

    report["checked"].append({
        "id": ac_id,
        "exit_code": exit_code,
        "must_pass": must_pass,
    })
    if exit_code == 0:
        report["passing"].append(ac_id)
    else:
        # Failing OR not-must-pass-but-failing both go here; the caller
        # checks must_pass when deciding whether to block.
        report["failing"].append(ac_id)

# Path-boundary check (only if allowed_paths is set).
allowed_paths = ((goal.get("constraints") or {}).get("allowed_paths") or [])
if allowed_paths:
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            changed_files = [f for f in result.stdout.splitlines() if f]
            # Use fnmatch for glob-style matching against allowed_paths.
            import fnmatch
            for f in changed_files:
                allowed = any(fnmatch.fnmatch(f, pat) for pat in allowed_paths)
                if not allowed:
                    report["path_violations"].append(f)
    except (subprocess.TimeoutExpired, OSError):
        # Git not available or slow — skip. The path-boundary check is
        # opportunistic, not load-bearing for the warn mode.
        pass

print(json.dumps(report))
PYTHON
