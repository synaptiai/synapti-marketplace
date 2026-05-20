#!/usr/bin/env bash
# [flow] Record the most-recent verdict for a FlowRun.
#
# Writes .flow/runs/<run-id>/last-verdict.json — read by
# bin/_flow_evidence_bundle.py on subsequent turns to compute delta
# (made_progress / unchanged / regressed). Without this producer, every
# evaluator-loop turn computes delta against "nothing", so the loop has
# no memory across iterations.
#
# Two callers:
#   1. hooks/scripts/flow-goal-evaluator.sh — after the judge subprocess
#      returns a structured verdict (every evaluator-loop turn)
#   2. /flow:goal evaluate (manual mode) — after the goal-evaluator skill
#      produces a verdict at user request
#
# Verdict file shape (validated before write):
#   {
#     "verdict": "achieved | not_achieved | blocked | needs_human_review",
#     "confidence": 0.0-1.0,
#     "delta": "made_progress | unchanged | regressed",
#     "reason": "...",
#     "criterion_results": [...],         (optional)
#     "next_step_hint": "...",            (optional)
#     "blocker_type": "...",              (optional)
#     "recorded_at": "2026-05-20T14:30:00Z" (auto-added if absent)
#   }
#
# Usage:
#   flow-record-verdict.sh --run-id <ISO-id> --verdict-file <path-to-json>
#
# Atomicity: writes go through bin/_journal_atomic.py (O_NOFOLLOW + flock
# + tempfile+rename+fsync). Replace semantics — each turn supersedes the
# prior file.
#
# Exits:
#   0 — verdict recorded
#   1 — missing required argument; verdict JSON missing required keys or
#       malformed JSON
#   2 — infrastructure error (python3 missing, write failed, symlink rejected)

set -euo pipefail
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-record-verdict.sh: python3 required but not installed" >&2
  exit 2
fi

RUN_ID=""
VERDICT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id)        RUN_ID="$2"; shift 2 ;;
    --verdict-file)  VERDICT_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,33p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "flow-record-verdict.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -z "$RUN_ID" ]       && { echo "flow-record-verdict.sh: --run-id is required" >&2; exit 1; }
[ -z "$VERDICT_FILE" ] && { echo "flow-record-verdict.sh: --verdict-file is required" >&2; exit 1; }

# Defense against path traversal in the run-id (the schema also rejects
# but defend at every layer per project convention).
case "$RUN_ID" in
  *..*|*/*)
    echo "flow-record-verdict.sh: --run-id contains '..' or '/' — refusing for safety (got: $RUN_ID)" >&2
    exit 1
    ;;
esac

[ -f "$VERDICT_FILE" ] || {
  echo "flow-record-verdict.sh: --verdict-file '$VERDICT_FILE' does not exist" >&2
  exit 1
}

# Ensure the run directory exists (caller usually has, but this is a
# convenience for callers like /flow:goal evaluate that may run before
# the first activity record).
RUN_DIR=".flow/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"

python3 - "$SCRIPT_DIR" "$RUN_ID" "$VERDICT_FILE" "$RUN_DIR" <<'PYTHON'
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import datetime
import json
import os
from _journal_atomic import JournalAtomicError, write_json_file

run_id = sys.argv[2]
verdict_file = sys.argv[3]
run_dir = sys.argv[4]

# Read and parse the verdict file.
try:
    with open(verdict_file, "r", encoding="utf-8") as f:
        verdict_data = json.load(f)
except json.JSONDecodeError as e:
    print(f"flow-record-verdict.sh: --verdict-file is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)
except OSError as e:
    print(f"flow-record-verdict.sh: cannot read --verdict-file: {e}", file=sys.stderr)
    sys.exit(2)

if not isinstance(verdict_data, dict):
    print("flow-record-verdict.sh: verdict JSON must be a top-level object", file=sys.stderr)
    sys.exit(1)

# Required keys for downstream delta computation. Without these, the
# assembler can't surface a useful previous-verdict section, so we refuse
# rather than write a half-formed file.
required = ("verdict", "confidence", "delta", "reason")
missing = [k for k in required if k not in verdict_data]
if missing:
    print(
        f"flow-record-verdict.sh: verdict JSON missing required keys: {', '.join(missing)}",
        file=sys.stderr,
    )
    sys.exit(1)

# Validate enum values for verdict + delta (mirror the schema enforced by
# the evaluator hook so we refuse bogus data at write time).
valid_verdicts = {"achieved", "not_achieved", "blocked", "needs_human_review"}
valid_deltas = {"made_progress", "unchanged", "regressed"}
if verdict_data["verdict"] not in valid_verdicts:
    print(
        f"flow-record-verdict.sh: verdict must be one of {sorted(valid_verdicts)}, got {verdict_data['verdict']!r}",
        file=sys.stderr,
    )
    sys.exit(1)
if verdict_data["delta"] not in valid_deltas:
    print(
        f"flow-record-verdict.sh: delta must be one of {sorted(valid_deltas)}, got {verdict_data['delta']!r}",
        file=sys.stderr,
    )
    sys.exit(1)

confidence = verdict_data.get("confidence")
if not isinstance(confidence, (int, float)) or not (0.0 <= float(confidence) <= 1.0):
    print(
        f"flow-record-verdict.sh: confidence must be a number in [0.0, 1.0], got {confidence!r}",
        file=sys.stderr,
    )
    sys.exit(1)

# Auto-add recorded_at if absent. Use UTC ISO-8601 with second resolution
# to match the rest of the flow plugin's timestamp convention.
if "recorded_at" not in verdict_data:
    verdict_data["recorded_at"] = (
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

target = os.path.join(run_dir, "last-verdict.json")
lockfile = os.path.join(run_dir, ".verdict.lock")

try:
    write_json_file(target, lockfile, verdict_data)
except JournalAtomicError as e:
    print(f"flow-record-verdict.sh: {e}", file=sys.stderr)
    sys.exit(e.exit_code)

print(f"flow-record-verdict.sh: recorded verdict for {run_id} -> {target}", file=sys.stderr)
PYTHON
