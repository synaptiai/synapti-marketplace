#!/usr/bin/env bash
# [flow] Record a FlowActivity in .flow/runs/<run-id>/activities/.
#
# Writes a sequence-numbered, atomic YAML file plus appends an event to
# .flow/runs/<run-id>/events.jsonl. Activities are immutable once written;
# re-running an activity creates a new sequence-numbered file rather than
# overwriting.
#
# Usage:
#   flow-record-activity.sh \
#     --run-id <ISO-timestamp-id> \
#     --activity-file <path-to-yaml>
#
# The activity YAML must conform to plugins/flow/schemas/v1/activity.schema.json.
# Schema validation happens here (when jsonschema is available) so callers
# cannot silently produce malformed FlowActivity files.
#
# Exits:
#   0 — activity recorded; events.jsonl appended
#   1 — missing required argument; activity YAML missing metadata.id; schema mismatch
#   2 — infrastructure error (PyYAML missing, write failed, symlink rejected, etc.)
#
# Atomicity: all writes go through bin/_journal_atomic.py — same O_NOFOLLOW
# + flock + tempfile+rename + fsync defenses as journal-record.sh.

set -euo pipefail

# PYTHONSAFEPATH disables prepending CWD to sys.path inside python3 — defense
# against a hostile fork's `./yaml.py` shadowing the real PyYAML during the
# atomic-helper module import. (Python 3.11+; older Pythons fall back to the
# defensive sys.path filter inside _journal_atomic.py.)
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Graceful degradation — matches the pattern in session-end-learn.sh:13 and
# verify-task-completion.sh:13. A hook script that hard-fails on a missing
# optional tool would break sessions on stripped systems; instead we exit 0
# with a stderr explanation so callers can install the dep and retry.
if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-record-activity.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-record-activity.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

RUN_ID=""
ACTIVITY_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --activity-file)
      ACTIVITY_FILE="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "flow-record-activity.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -z "$RUN_ID" ]        && { echo "flow-record-activity.sh: --run-id is required" >&2; exit 1; }
[ -z "$ACTIVITY_FILE" ] && { echo "flow-record-activity.sh: --activity-file is required" >&2; exit 1; }

# Validate run-id shape early. The schema enforces this, but a malformed run-id
# here would land the activity in a typo'd directory that diverges from the
# parent FlowRun's directory — surface it before we mkdir anything.
case "$RUN_ID" in
  *..*|*/*)
    echo "flow-record-activity.sh: --run-id contains '..' or '/' — refusing for safety (got: $RUN_ID)" >&2
    exit 1
    ;;
esac

[ -f "$ACTIVITY_FILE" ] || {
  echo "flow-record-activity.sh: --activity-file '$ACTIVITY_FILE' does not exist or is not a regular file" >&2
  exit 1
}

# Hand off to Python. The module owns lockfile acquisition, symlink rejection,
# and atomic rename; this script owns CLI parsing, run-directory layout, and
# the sequence-number convention.
python3 - "$SCRIPT_DIR" "$RUN_ID" "$ACTIVITY_FILE" <<'PYTHON'
import sys

# Defense-in-depth: harden sys.path before the module import. The module
# re-runs this filter internally; doing it here too prevents `./yaml.py`
# shadowing on the `from _journal_atomic import ...` line.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import datetime
import os
import re

import yaml
from _journal_atomic import (
    JournalAtomicError,
    write_yaml_file,
    append_jsonl,
)

run_id = sys.argv[2]
activity_file = sys.argv[3]

# Read + parse the activity YAML the caller provided. We do this BEFORE
# creating the run directory so a malformed activity doesn't leave a stub
# directory behind. yaml.safe_load is enforced (never yaml.load).
try:
    with open(activity_file, "r", encoding="utf-8") as f:
        activity = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f"flow-record-activity.sh: --activity-file is not valid YAML: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(activity, dict):
    print("flow-record-activity.sh: activity YAML must be a top-level mapping", file=sys.stderr)
    sys.exit(1)

# Extract the activity id. The schema enforces this field; surfacing it as
# a clear error here beats letting the schema-validator's deep-path error
# bubble up to the user.
metadata = activity.get("metadata") or {}
activity_name = metadata.get("id")
if not activity_name or not isinstance(activity_name, str):
    print("flow-record-activity.sh: activity.metadata.id is required and must be a string", file=sys.stderr)
    sys.exit(1)

# Schema validation, if jsonschema is available. Skip gracefully if not —
# the helper still writes (callers can install jsonschema to enforce
# strict validation in CI).
schemas_dir = os.path.join(script_dir, "..", "schemas", "v1")
schema_path = os.path.normpath(os.path.join(schemas_dir, "activity.schema.json"))
try:
    import json
    import jsonschema
    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)
    try:
        jsonschema.validate(instance=activity, schema=schema)
    except jsonschema.ValidationError as e:
        print(f"flow-record-activity.sh: activity does not match schema: {e.message}", file=sys.stderr)
        sys.exit(1)
except ImportError:
    # apply the same
    # per-day WARN as flow-goal-record.sh so the jsonschema-degraded state
    # is surfaced uniformly across all three FlowRunArtifact writers (goal,
    # activity, evidence). Previous behavior was silent skip — diverged
    # following the same "surface the degradation" rationale.
    import datetime, tempfile, getpass
    today = datetime.date.today().isoformat()
    try:
        user = getpass.getuser() or "default"
    except Exception:
        user = "default"
    user = "".join(c for c in user if c.isalnum() or c in "_-")[:32] or "default"
    sentinel = os.path.join(tempfile.gettempdir(), f"flow-warn-jsonschema-{user}-{today}")
    if not os.path.exists(sentinel):
        print(
            "flow-record-activity.sh: WARN jsonschema unavailable — activity validation skipped. "
            "Install via 'pip install jsonschema' for safety. Warning fires once per day per user.",
            file=sys.stderr,
        )
        try:
            with open(sentinel, "w", encoding="utf-8") as _f:
                _f.write("")
        except OSError:
            pass

# Layout: .flow/runs/<run-id>/activities/<NNN>-<id>.yaml.
# The sequence number is the count of existing .yaml files in activities/
# zero-padded to 3 digits. This stays sortable up to 999 activities; if
# we ever hit that we have bigger problems than a 4-digit rename.
run_dir = os.path.join(".flow", "runs", run_id)
activity_dir = os.path.join(run_dir, "activities")
evidence_dir = os.path.join(run_dir, "evidence")

try:
    os.makedirs(activity_dir, exist_ok=True)
    os.makedirs(evidence_dir, exist_ok=True)
except OSError as e:
    print(f"flow-record-activity.sh: cannot create run directory: {e}", file=sys.stderr)
    sys.exit(2)

# Count *.yaml entries to derive the next sequence number. We deliberately
# do NOT count the lockfile or any tempfiles _atomic.py may leave behind on
# a crashed write (those have .tmp suffixes).
existing = [
    f for f in os.listdir(activity_dir)
    if f.endswith(".yaml") and not f.endswith(".tmp.yaml")
]
seq = f"{len(existing) + 1:03d}"

# Sanitize the activity name for the filename. The schema permits
# [a-z0-9_-]; the regex below is a belt-and-suspenders filter so a future
# schema relaxation can't introduce path traversal here.
safe_name = re.sub(r"[^a-z0-9_-]", "-", activity_name.lower())
target = os.path.join(activity_dir, f"{seq}-{safe_name}.yaml")
lockfile = os.path.join(run_dir, ".lock")

try:
    write_yaml_file(target, lockfile, activity)
except JournalAtomicError as e:
    print(f"flow-record-activity.sh: {e}", file=sys.stderr)
    sys.exit(e.exit_code)

# Append a one-line event to .flow/runs/<id>/events.jsonl. This is the
# high-volume hook-level ledger; the FlowRun.events array is for
# low-volume top-level lifecycle moments.
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
event = {
    "at": now,
    "type": "activity_recorded",
    "activity": activity_name,
    "seq": seq,
    "path": target,
}
events_path = os.path.join(run_dir, "events.jsonl")
try:
    append_jsonl(events_path, event)
except JournalAtomicError as e:
    # The activity write succeeded; the event append did not. Surface the
    # error but don't undo the activity write — the activity file is the
    # source of truth, events.jsonl is the audit trail.
    print(f"flow-record-activity.sh: WARN events.jsonl append failed: {e}", file=sys.stderr)

print(f"flow-record-activity.sh: recorded {seq}-{safe_name} in {target}", file=sys.stderr)
PYTHON
