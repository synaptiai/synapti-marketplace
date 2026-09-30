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
# Every message is one line of text: a value in it is escaped and, when no
# earlier check has bounded it, cut (bin/_flow_cli.py).
#
# Exits:
#   0 — activity recorded, and events.jsonl appended or its failure reported
#       as a WARN; or --help
#   1 — the arguments or the input: an argument that is not an option, or an
#       option with no value; no --run-id or no --activity-file; a --run-id
#       holding '..' or '/', or longer than a directory name; an
#       --activity-file that is not there or not a regular file, or that
#       cannot be read for a reason of its path; an activity file that is not
#       UTF-8, not valid YAML (a value PyYAML cannot build included) or
#       nested too deep to read; a top level or a metadata that is not a
#       mapping; no metadata.id, or one too long for the names written for it;
#       an activity that does not match the schema (with jsonschema installed)
#   2 — python3 or PyYAML missing; the activity file cannot be read for a
#       reason of the system; the run, activities or evidence directory
#       refused or not made (a symlinked .flow, .flow/runs or run directory
#       included); the write failing
#
# Atomicity: all writes go through bin/_journal_atomic.py — same O_NOFOLLOW
# + flock + tempfile+rename + fsync defenses as journal-record.sh. The run's
# directories are created through ensure_repo_dir(), never through a symlink.

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

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

# --help, where an option is expected. Every other argument is python3's to
# read, and to refuse: a message that prints a value is written by one
# printer, whatever the shell's locale.
wants_help() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-id|--activity-file) [ $# -ge 2 ] || return 1; shift 2 ;;
      -h|--help) return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}
if wants_help "$@"; then
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
  exit 0
fi

# Hand off to Python. The module owns lockfile acquisition, symlink rejection,
# and atomic rename; this script owns CLI parsing, run-directory layout, and
# the sequence-number convention.
python3 - "$SCRIPT_DIR" "$@" <<'PYTHON'
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
from _flow_cli import Messages, name_max, schema_problem, shown, yaml_problem
from _journal_atomic import (
    JournalAtomicError,
    ensure_repo_dir,
    write_yaml_file,
    yaml_text,
    append_jsonl,
)

messages = Messages("flow-record-activity.sh")
say, refuse = messages.say, messages.refuse

options = messages.read_arguments(sys.argv[2:], ("--run-id", "--activity-file"))
run_id = options["--run-id"]
activity_file = options["--activity-file"]
if not run_id:
    refuse("--run-id is required")
if not activity_file:
    refuse("--activity-file is required")

# Validate run-id shape early. The schema enforces this, but a malformed run-id
# here would land the activity in a typo'd directory that diverges from the
# parent FlowRun's directory — surface it before we mkdir anything. A run id
# longer than a directory name fails to be made, and its error prints the
# whole path.
if ".." in run_id or "/" in run_id:
    refuse(f"--run-id contains '..' or '/' — refusing for safety (got: {shown(run_id)})")
NAME_MAX = name_max()
run_id_bytes = len(os.fsencode(run_id))
if run_id_bytes > NAME_MAX:
    refuse(f"--run-id is {run_id_bytes} bytes; a directory name here holds at most {NAME_MAX}")
if not os.path.isfile(activity_file):
    refuse(f"--activity-file {shown(activity_file)} does not exist or is not a regular file")

# Read + parse the activity YAML the caller provided. We do this BEFORE
# creating the run directory so a malformed activity doesn't leave a stub
# directory behind. yaml.safe_load is enforced (never yaml.load).
try:
    with open(activity_file, "r", encoding="utf-8") as f:
        activity = yaml.safe_load(f)
except RecursionError:
    refuse("--activity-file is nested too deep to read")
except UnicodeDecodeError as e:
    refuse(f"--activity-file is not UTF-8: {shown(e)}")
except OSError as e:
    messages.cannot("read", "--activity-file", activity_file, e)
except yaml.YAMLError as e:
    refuse(f"--activity-file is not valid YAML: {yaml_problem(e)}")
except Exception as e:
    # Parsed, but PyYAML could not build a value from it (a date with a
    # thirteenth month): its constructors raise ValueError, AttributeError or
    # KeyError, not a YAMLError.
    refuse(f"--activity-file is not valid YAML: {type(e).__name__}: {shown(e)}")

if not isinstance(activity, dict):
    refuse("activity YAML must be a top-level mapping")

# Extract the activity id. The schema enforces this field; surfacing it as
# a clear error here beats letting the schema-validator's deep-path error
# bubble up to the user.
metadata = activity.get("metadata") or {}
if not isinstance(metadata, dict):
    refuse("activity.metadata must be a mapping")
activity_name = metadata.get("id")
if not activity_name or not isinstance(activity_name, str):
    refuse("activity.metadata.id is required and must be a string")

# Sanitize the activity name for the filename. The schema permits
# [a-z0-9_-]; the regex below is a belt-and-suspenders filter so a future
# schema relaxation can't introduce path traversal here.
safe_name = re.sub(r"[^a-z0-9_-]", "-", activity_name.lower())

# The id names <NNN>-<name>.yaml and, while it is written,
# <NNN>-<name>.yaml.<8 random characters>.tmp, the longest; NNN has three
# digits up to 999 activities, four after. The schema's maxLength for
# metadata.id is MAX_ID; where the file system takes shorter names, the limit
# is lower. Checked before anything is made.
MAX_ID = 200
LONGEST_EXTRA = len("NNNN-") + len(".yaml.") + 8 + len(".tmp")
id_limit = min(MAX_ID, NAME_MAX - LONGEST_EXTRA)
if max(len(activity_name), len(safe_name)) > id_limit:
    refuse(f"activity.metadata.id is too long: {len(activity_name)} characters; at most {id_limit}")

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
        # Where and which rule, never e.message, which quotes the whole value.
        refuse(f"activity does not match schema {schema_problem(e)}")
except ImportError:
    # Apply the same per-day WARN as flow-goal-record.sh so the
    # jsonschema-degraded state is surfaced uniformly across all three
    # FlowRunArtifact writers (goal, activity, evidence). The previous silent
    # skip diverged from this "surface the degradation" rationale.
    import datetime, tempfile, getpass
    today = datetime.date.today().isoformat()
    try:
        user = getpass.getuser() or "default"
    except Exception:
        user = "default"
    user = "".join(c for c in user if c.isalnum() or c in "_-")[:32] or "default"
    sentinel = os.path.join(tempfile.gettempdir(), f"flow-warn-jsonschema-{user}-{today}")
    if not os.path.exists(sentinel):
        say(
            "WARN jsonschema unavailable — activity validation skipped. "
            "Install via 'pip install jsonschema' for safety. Warning fires once per day per user."
        )
        try:
            with open(sentinel, "w", encoding="utf-8") as _f:
                _f.write("")
        except OSError:
            pass

# The activity's text is made here, once, and written as it is. PyYAML reads
# some files it cannot write (nesting too deep, an integer too long to write
# in decimal), and that is the file's fault: found here, before anything is
# made, it is refused as a file that cannot be read is.
try:
    activity_text = yaml_text(activity)
except RecursionError:
    refuse("activity is nested too deep to write")
except Exception as e:
    refuse(f"activity cannot be written as YAML: {type(e).__name__}: {shown(e)}")

# Layout: .flow/runs/<run-id>/activities/<NNN>-<id>.yaml.
# The sequence number is the count of existing .yaml files in activities/
# zero-padded to 3 digits. This stays sortable up to 999 activities; if
# we ever hit that we have bigger problems than a 4-digit rename.
run_dir = os.path.join(".flow", "runs", run_id)
activity_dir = os.path.join(run_dir, "activities")
evidence_dir = os.path.join(run_dir, "evidence")

# Never os.makedirs: a repository can commit .flow or .flow/runs as a symlink
# to a directory outside the checkout, and makedirs would create the run there.
try:
    ensure_repo_dir(activity_dir, create=True)
    ensure_repo_dir(evidence_dir, create=True)
except JournalAtomicError as e:
    refuse(f"{e}", 2)

# Count *.yaml entries to derive the next sequence number. We deliberately
# do NOT count the lockfile or any tempfiles _atomic.py may leave behind on
# a crashed write (those have .tmp suffixes).
existing = [
    f for f in os.listdir(activity_dir)
    if f.endswith(".yaml") and not f.endswith(".tmp.yaml")
]
seq = f"{len(existing) + 1:03d}"

target = os.path.join(activity_dir, f"{seq}-{safe_name}.yaml")
lockfile = os.path.join(run_dir, ".lock")

try:
    write_yaml_file(target, lockfile, activity, text=activity_text)
except JournalAtomicError as e:
    refuse(f"{e}", e.exit_code)

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
    say(f"WARN events.jsonl append failed: {e}")

say(f"recorded {seq}-{safe_name} in {target}")
PYTHON
