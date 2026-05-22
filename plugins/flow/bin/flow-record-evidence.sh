#!/usr/bin/env bash
# [flow] Record a FlowEvidence sidecar in .flow/runs/<run-id>/evidence/.
#
# Writes a FlowEvidence YAML sidecar plus optionally captures raw output
# (e.g., the stdout of a verification command) into a .txt file alongside.
# The sidecar's metadata.id determines both filenames.
#
# Usage:
#   flow-record-evidence.sh \
#     --run-id <ISO-timestamp-id> \
#     --evidence-file <path-to-yaml> \
#     [--raw-output <path-to-stdout-capture>]
#
# Atomicity: all writes go through bin/_journal_atomic.py.
#
# Exits:
#   0 — evidence recorded
#   1 — missing required argument; evidence YAML missing metadata.id
#   2 — infrastructure error (PyYAML missing, write failed, symlink rejected)

set -euo pipefail
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-record-evidence.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-record-evidence.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

RUN_ID=""
EVIDENCE_FILE=""
RAW_OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id)        RUN_ID="$2"; shift 2 ;;
    --evidence-file) EVIDENCE_FILE="$2"; shift 2 ;;
    --raw-output)    RAW_OUTPUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "flow-record-evidence.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -z "$RUN_ID" ]        && { echo "flow-record-evidence.sh: --run-id is required" >&2; exit 1; }
[ -z "$EVIDENCE_FILE" ] && { echo "flow-record-evidence.sh: --evidence-file is required" >&2; exit 1; }

case "$RUN_ID" in
  *..*|*/*)
    echo "flow-record-evidence.sh: --run-id contains '..' or '/' — refusing for safety (got: $RUN_ID)" >&2
    exit 1
    ;;
esac

[ -f "$EVIDENCE_FILE" ] || {
  echo "flow-record-evidence.sh: --evidence-file '$EVIDENCE_FILE' does not exist" >&2
  exit 1
}

if [ -n "$RAW_OUTPUT" ] && [ ! -f "$RAW_OUTPUT" ]; then
  echo "flow-record-evidence.sh: --raw-output '$RAW_OUTPUT' does not exist" >&2
  exit 1
fi

python3 - "$SCRIPT_DIR" "$RUN_ID" "$EVIDENCE_FILE" "$RAW_OUTPUT" <<'PYTHON'
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import errno
import os
import re

import yaml
from _journal_atomic import JournalAtomicError, write_yaml_file

run_id = sys.argv[2]
evidence_file = sys.argv[3]
raw_output = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None

try:
    with open(evidence_file, "r", encoding="utf-8") as f:
        evidence = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f"flow-record-evidence.sh: --evidence-file is not valid YAML: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(evidence, dict):
    print("flow-record-evidence.sh: evidence YAML must be a top-level mapping", file=sys.stderr)
    sys.exit(1)

metadata = evidence.get("metadata") or {}
evidence_id = metadata.get("id")
if not evidence_id or not isinstance(evidence_id, str):
    print("flow-record-evidence.sh: evidence.metadata.id is required and must be a string", file=sys.stderr)
    sys.exit(1)

# Optional schema validation if jsonschema is available.
schemas_dir = os.path.join(script_dir, "..", "schemas", "v1")
schema_path = os.path.normpath(os.path.join(schemas_dir, "evidence.schema.json"))
try:
    import json
    import jsonschema
    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)
    try:
        jsonschema.validate(instance=evidence, schema=schema)
    except jsonschema.ValidationError as e:
        print(f"flow-record-evidence.sh: evidence does not match schema: {e.message}", file=sys.stderr)
        sys.exit(1)
except ImportError:
    # Cycle-14 F11-INCONSISTENCY (error-handler verifier): mirror the per-day
    # WARN from flow-goal-record.sh and flow-record-activity.sh.
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
            "flow-record-evidence.sh: WARN jsonschema unavailable — evidence validation skipped. "
            "Install via 'pip install jsonschema' for safety. Warning fires once per day per user.",
            file=sys.stderr,
        )
        try:
            with open(sentinel, "w", encoding="utf-8") as _f:
                _f.write("")
        except OSError:
            pass

run_dir = os.path.join(".flow", "runs", run_id)
evidence_dir = os.path.join(run_dir, "evidence")
try:
    os.makedirs(evidence_dir, exist_ok=True)
except OSError as e:
    print(f"flow-record-evidence.sh: cannot create evidence directory: {e}", file=sys.stderr)
    sys.exit(2)

safe_name = re.sub(r"[^a-z0-9_-]", "-", evidence_id.lower())
sidecar_target = os.path.join(evidence_dir, f"{safe_name}.evidence.yaml")
lockfile = os.path.join(run_dir, ".lock")

# Write the sidecar atomically.
try:
    write_yaml_file(sidecar_target, lockfile, evidence)
except JournalAtomicError as e:
    print(f"flow-record-evidence.sh: {e}", file=sys.stderr)
    sys.exit(e.exit_code)

# Copy raw output, if provided, to <safe_name>.txt next to the sidecar.
# Symlink defense: use O_NOFOLLOW on both source AND destination to
# atomically reject symlinks. `os.path.islink` + `shutil.copyfile` has a
# TOCTOU window — an attacker can plant a symlink between the check and
# the open. O_NOFOLLOW is atomic. O_EXCL on the destination refuses to
# overwrite an existing file (intentional: evidence is immutable).
if raw_output:
    raw_target = os.path.join(evidence_dir, f"{safe_name}.txt")
    try:
        src_fd = os.open(raw_output, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as e:
        if getattr(e, "errno", None) == errno.ELOOP:
            print(f"flow-record-evidence.sh: refusing — raw-output source {raw_output} is a symlink", file=sys.stderr)
        else:
            print(f"flow-record-evidence.sh: cannot open raw-output source: {e}", file=sys.stderr)
        sys.exit(2)
    try:
        dst_fd = os.open(raw_target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    except OSError as e:
        os.close(src_fd)
        if getattr(e, "errno", None) == errno.ELOOP:
            print(f"flow-record-evidence.sh: refusing — raw-output target {raw_target} is a symlink", file=sys.stderr)
        elif getattr(e, "errno", None) == errno.EEXIST:
            print(f"flow-record-evidence.sh: refusing — raw-output target {raw_target} already exists (evidence is immutable)", file=sys.stderr)
        else:
            print(f"flow-record-evidence.sh: cannot create raw-output target: {e}", file=sys.stderr)
        sys.exit(2)
    try:
        while True:
            chunk = os.read(src_fd, 65536)
            if not chunk:
                break
            os.write(dst_fd, chunk)
    except OSError as e:
        print(f"flow-record-evidence.sh: raw-output copy failed: {e}", file=sys.stderr)
        os.close(src_fd); os.close(dst_fd)
        try: os.unlink(raw_target)
        except OSError: pass
        sys.exit(2)
    finally:
        try: os.close(src_fd)
        except OSError: pass
        try: os.close(dst_fd)
        except OSError: pass

print(f"flow-record-evidence.sh: recorded {safe_name} in {sidecar_target}", file=sys.stderr)
PYTHON
