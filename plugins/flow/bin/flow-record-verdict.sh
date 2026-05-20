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
# PyYAML is imported transitively by _journal_atomic.py — check here so
# callers see a clear message instead of a Python traceback. Matches the
# graceful-degradation pattern used by flow-record-evidence.sh and
# flow-record-activity.sh.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-record-verdict.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
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
  .|..|*..*|*/*)
    # Reject path-traversal AND the bare `.`/`..` identifiers (which would
    # collapse the run dir to `.flow/runs/` itself, breaking per-run isolation).
    echo "flow-record-verdict.sh: --run-id contains '..' or '/' or is bare '.'/'..' — refusing for safety (got: $RUN_ID)" >&2
    exit 1
    ;;
esac

[ -f "$VERDICT_FILE" ] || {
  echo "flow-record-verdict.sh: --verdict-file '$VERDICT_FILE' does not exist" >&2
  exit 1
}

# Ensure the run directory exists (caller usually has, but this is a
# convenience for callers like /flow:goal evaluate that may run before
# the first activity record). Defend against directory-level symlink
# attacks: O_NOFOLLOW on the verdict file alone is insufficient if the
# .flow/runs/<id>/ directory itself is a symlink to an attacker-chosen
# path — tempfile.mkstemp + os.rename inside _journal_atomic would then
# write into the attacker dir. Reject symlinked directories explicitly.
RUN_DIR=".flow/runs/${RUN_ID}"
if [ -L "$RUN_DIR" ]; then
  echo "flow-record-verdict.sh: refusing — $RUN_DIR is a symlink (cannot redirect verdict writes outside .flow/runs/)" >&2
  exit 2
fi
mkdir -p "$RUN_DIR" 2>/dev/null || {
  echo "flow-record-verdict.sh: cannot create $RUN_DIR (disk full, permissions, or parent inaccessible)" >&2
  exit 2
}
# Re-check after mkdir — a race could substitute a symlink between the
# initial check and create. Belt-and-suspenders.
if [ -L "$RUN_DIR" ]; then
  echo "flow-record-verdict.sh: refusing — $RUN_DIR became a symlink during mkdir" >&2
  exit 2
fi

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

# Read and parse the verdict file with O_NOFOLLOW so a pre-staged symlink
# at the temp-file path (e.g., a race against caller's mktemp) is refused
# atomically rather than followed to an attacker-chosen target.
import errno
try:
    src_fd = os.open(verdict_file, os.O_RDONLY | os.O_NOFOLLOW)
except OSError as e:
    if getattr(e, "errno", None) in (errno.ELOOP, errno.EMLINK):
        print(f"flow-record-verdict.sh: refusing — --verdict-file '{verdict_file}' is a symlink", file=sys.stderr)
        sys.exit(2)
    print(f"flow-record-verdict.sh: cannot open --verdict-file: {e}", file=sys.stderr)
    sys.exit(2)
try:
    with os.fdopen(src_fd, "r", encoding="utf-8") as f:
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
# isinstance(True, int) is True in Python — explicitly reject bools to
# preserve the "must be a number" contract.
if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not (0.0 <= float(confidence) <= 1.0):
    print(
        f"flow-record-verdict.sh: confidence must be a number in [0.0, 1.0], got {confidence!r}",
        file=sys.stderr,
    )
    sys.exit(1)

# Validate optional fields. Producers writing untrusted content (e.g.,
# judge subprocess output) can ship strings that would survive into the
# next-turn UNTRUSTED_PREVIOUS_VERDICT fence. The fence is the primary
# defense; this is belt-and-suspenders bounding.
_OPTIONAL_STRING_CAPS = {
    "reason": 2048,
    "next_step_hint": 500,
    "source": 64,
}
_VALID_BLOCKER_TYPES = {
    "missing_dep", "missing_approval", "ambiguous_requirement",
    "external_service", "scope_violation", "none",
}
for _key, _cap in _OPTIONAL_STRING_CAPS.items():
    _val = verdict_data.get(_key)
    if _val is None:
        continue
    if not isinstance(_val, str):
        print(
            f"flow-record-verdict.sh: optional field '{_key}' must be a string, got {type(_val).__name__}",
            file=sys.stderr,
        )
        sys.exit(1)
    if len(_val) > _cap:
        # Soft cap — truncate with marker rather than reject, so a slightly
        # over-budget verdict doesn't break the next-turn delta loop.
        verdict_data[_key] = _val[:_cap] + "…"
        print(
            f"flow-record-verdict.sh: optional field '{_key}' exceeded {_cap}-byte cap; truncated",
            file=sys.stderr,
        )

_blocker = verdict_data.get("blocker_type")
if _blocker is not None and _blocker not in _VALID_BLOCKER_TYPES:
    print(
        f"flow-record-verdict.sh: blocker_type must be one of {sorted(_VALID_BLOCKER_TYPES)}, got {_blocker!r}",
        file=sys.stderr,
    )
    sys.exit(1)

# criterion_results, when present, must be a list of dicts. Don't
# deep-validate (the schema enforces shape upstream); just refuse
# non-list to prevent type confusion downstream.
_crit = verdict_data.get("criterion_results")
if _crit is not None and not isinstance(_crit, list):
    print(
        f"flow-record-verdict.sh: criterion_results must be a list, got {type(_crit).__name__}",
        file=sys.stderr,
    )
    sys.exit(1)

# Auto-add recorded_at if absent. Use UTC ISO-8601 with second resolution
# to match the rest of the flow plugin's timestamp convention. We mutate
# a COPY of verdict_data, not the caller's dict — the helper's contract
# is "validate + write", not "mutate input". Callers (especially the
# shell heredoc subprocess) don't observe the mutation today, but the
# copy semantics keep the contract clean for future Python callers.
to_write = dict(verdict_data)
to_write.setdefault(
    "recorded_at",
    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
)

target = os.path.join(run_dir, "last-verdict.json")
lockfile = os.path.join(run_dir, ".verdict.lock")

try:
    write_json_file(target, lockfile, to_write)
except JournalAtomicError as e:
    print(f"flow-record-verdict.sh: {e}", file=sys.stderr)
    # Surface the `refuse` attribute so a clobber-refusal includes the
    # canonical "fix manually" suffix the journal-record helper uses.
    if getattr(e, "refuse", False):
        print("flow-record-verdict.sh: refusing to overwrite — fix manually", file=sys.stderr)
    sys.exit(e.exit_code)

# Success-path stderr is gated behind FLOW_RECORD_VERDICT_QUIET so callers
# (the evaluator-loop hook in particular) can suppress chatter without
# losing real error visibility. Default unset = chatty (manual `/flow:goal
# evaluate` callers benefit from the confirmation).
if not os.environ.get("FLOW_RECORD_VERDICT_QUIET", ""):
    print(f"flow-record-verdict.sh: recorded verdict for {run_id} -> {target}", file=sys.stderr)
PYTHON
