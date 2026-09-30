#!/usr/bin/env bash
# [flow] Record a FlowEvidence sidecar in .flow/runs/<run-id>/evidence/.
#
# Writes a FlowEvidence YAML sidecar plus optionally captures raw output
# (e.g., the stdout of a verification command) into a .txt file alongside.
# The sidecar's metadata.id determines both filenames: lower-cased, with any
# character other than a-z, 0-9, `_` and `-` made `-`. With --raw-output the
# sidecar's evidence.output_ref is set to the copy's name (`<name>.txt`,
# relative to the sidecar's directory, as the judge's bundle reads it); a
# sidecar that already names another file there is refused.
#
# Usage:
#   flow-record-evidence.sh \
#     --run-id <ISO-timestamp-id> \
#     --evidence-file <path-to-yaml> \
#     [--raw-output <path-to-stdout-capture>]
#
# Atomicity: all writes go through bin/_journal_atomic.py. The evidence
# directory is created through ensure_repo_dir(), never through a symlink.
# Every check comes first, then the raw output's copy, then the sidecar; a
# refused copy writes no sidecar, a sidecar that cannot be written takes its
# copy away again, and an id already recorded is refused (evidence is
# append-only).
#
# Exits:
#   0 — evidence recorded
#   1 — missing required argument; an evidence file that cannot be read (not
#       UTF-8, not valid YAML, not readable, or nested too deep to read or to
#       write); evidence YAML whose metadata is not a mapping or has no id;
#       an output_ref other than the name --raw-output is copied to
#   2 — infrastructure error (PyYAML missing, write failed, symlink rejected —
#       including a symlinked .flow, .flow/runs or run directory), or the id
#       is already recorded

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
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
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
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
import stat

import yaml
from _journal_atomic import JournalAtomicError, TargetExists, ensure_repo_dir, write_yaml_file

run_id = sys.argv[2]
evidence_file = sys.argv[3]
raw_output = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None


def one_line(text):
    return " ".join(str(text).split())


# Whatever stops the read is the evidence file's fault, named in one line.
try:
    with open(evidence_file, "r", encoding="utf-8") as f:
        evidence = yaml.safe_load(f)
except RecursionError:
    print("flow-record-evidence.sh: --evidence-file is nested too deep to read", file=sys.stderr)
    sys.exit(1)
except UnicodeDecodeError as e:
    print(f"flow-record-evidence.sh: --evidence-file is not UTF-8: {one_line(e)}", file=sys.stderr)
    sys.exit(1)
except OSError as e:
    print(f"flow-record-evidence.sh: cannot read --evidence-file {evidence_file}: {e.strerror or one_line(e)}", file=sys.stderr)
    sys.exit(1)
except yaml.YAMLError as e:
    print(f"flow-record-evidence.sh: --evidence-file is not valid YAML: {one_line(e)}", file=sys.stderr)
    sys.exit(1)

if not isinstance(evidence, dict):
    print("flow-record-evidence.sh: evidence YAML must be a top-level mapping", file=sys.stderr)
    sys.exit(1)

metadata = evidence.get("metadata") or {}
if not isinstance(metadata, dict):
    print("flow-record-evidence.sh: evidence.metadata must be a mapping", file=sys.stderr)
    sys.exit(1)
evidence_id = metadata.get("id")
if not evidence_id or not isinstance(evidence_id, str):
    print("flow-record-evidence.sh: evidence.metadata.id is required and must be a string", file=sys.stderr)
    sys.exit(1)

safe_name = re.sub(r"[^a-z0-9_-]", "-", evidence_id.lower())

# The raw output's name is this writer's to give: it copies --raw-output to
# <safe_name>.txt beside the sidecar, and the judge's bundle reads output_ref
# relative to the sidecar's directory. So the sidecar gets that output_ref
# here, and one that names another file is refused rather than written
# pointing at nothing.
if raw_output:
    raw_name = f"{safe_name}.txt"
    block = evidence.get("evidence")
    if isinstance(block, dict):
        given = block.get("output_ref")
        if given is not None and given != raw_name:
            print(
                f"flow-record-evidence.sh: output_ref is {given}, but --raw-output is copied to "
                f"{raw_name}; leave output_ref out and it is written",
                file=sys.stderr,
            )
            sys.exit(1)
        block["output_ref"] = raw_name

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
    # Mirror the per-day WARN from flow-goal-record.sh and flow-record-activity.sh.
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
# Never os.makedirs: a repository can commit .flow or .flow/runs as a symlink
# to a directory outside the checkout, and makedirs would create the run there.
try:
    ensure_repo_dir(evidence_dir, create=True)
except JournalAtomicError as e:
    print(f"flow-record-evidence.sh: {e}", file=sys.stderr)
    sys.exit(2)

sidecar_target = os.path.join(evidence_dir, f"{safe_name}.evidence.yaml")
lockfile = os.path.join(run_dir, ".lock")

# Nothing is written until everything that can refuse has: a sidecar is the
# record the judge's bundle believes, so one must never name a copy that was
# not made, and one already recorded must never be replaced (evidence is
# append-only; a correction is a new id).
def already_recorded():
    print(
        f"flow-record-evidence.sh: refusing — evidence {safe_name} is already recorded in "
        f"{sidecar_target}; evidence is append-only, so record a correction under a new id",
        file=sys.stderr,
    )
    sys.exit(2)


if os.path.lexists(sidecar_target):
    already_recorded()

# Copy the raw output first, if given, to <safe_name>.txt next to where the
# sidecar goes. Symlink defense: O_NOFOLLOW on both source AND destination
# rejects a symlink atomically (`os.path.islink` + `shutil.copyfile` has a
# TOCTOU window), and O_EXCL on the destination refuses to overwrite an
# existing file (evidence is immutable).
raw_target = None
made_copy = False
copy_id = None


def remove_copy(unless_published=True):
    """Take this record's copy away again. Never once the sidecar is there
    (unless_published): it names the copy, whoever wrote it. Not a file that
    has taken the copy's name: the copy is known by its device and inode
    number, and a descriptor held open on it keeps that number from being
    given to another file."""
    if not made_copy:
        return
    if unless_published and os.path.lexists(sidecar_target):
        return
    try:
        now = os.lstat(raw_target)
    except OSError:
        return
    if (now.st_dev, now.st_ino) != copy_id:
        return
    try:
        os.unlink(raw_target)
    except OSError:
        pass

try:
    if raw_output:
        raw_target = os.path.join(evidence_dir, f"{safe_name}.txt")
        try:
            in_way = os.lstat(raw_target)
        except FileNotFoundError:
            in_way = None
        if in_way is not None:
            if stat.S_ISLNK(in_way.st_mode):
                print(f"flow-record-evidence.sh: refusing — raw-output target {raw_target} is a symlink", file=sys.stderr)
            elif stat.S_ISREG(in_way.st_mode):
                # No sidecar, or the check above would have refused: another
                # record of this id is between its copy and its sidecar, or
                # one was stopped there.
                print(
                    f"flow-record-evidence.sh: refusing — a copy {raw_target} exists with no sidecar: "
                    f"a record of this id is running, or one was stopped; if none is running, "
                    f"remove it, or record under a new id",
                    file=sys.stderr,
                )
            else:
                print(f"flow-record-evidence.sh: refusing — {raw_target} is in the way, and not a regular file", file=sys.stderr)
            sys.exit(2)
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
        made_copy = True
        # What the clean-up may remove: this copy, and no file that has taken
        # its name since. A file system can give a freed inode number to the
        # next file it creates (ext4 does), so a copy removed and made again
        # by another record could carry this copy's number; a second
        # descriptor stays open on this copy until the process ends, so its
        # number is not freed while the clean-up may compare it.
        made = os.fstat(dst_fd)
        copy_id = (made.st_dev, made.st_ino)
        copy_hold = os.dup(dst_fd)
        # Every chunk written whole (os.write may write less than it is
        # given, as under a file size limit), the copy synced before it is
        # closed, and a failed close a failed copy: the sidecar written next
        # says the copy is there, so it must be, all of it, after a crash too.
        try:
            try:
                while True:
                    chunk = os.read(src_fd, 65536)
                    if not chunk:
                        break
                    view = memoryview(chunk)
                    while view:
                        n = os.write(dst_fd, view)
                        if n <= 0:
                            raise OSError(errno.EIO, f"short write to {raw_target}")
                        view = view[n:]
                os.fsync(dst_fd)
            finally:
                try:
                    os.close(src_fd)
                except OSError:
                    pass
                fd, dst_fd = dst_fd, None
                os.close(fd)
        except OSError as e:
            if dst_fd is not None:
                try:
                    os.close(dst_fd)
                except OSError:
                    pass
            raise JournalAtomicError(f"raw-output copy failed: {e}", exit_code=2)

    # Then the sidecar, atomically and only if it is not there yet: the
    # check above ran outside the run's lock, and two records of one id can
    # overlap, so write_yaml_file decides again under the lock.
    write_yaml_file(sidecar_target, lockfile, evidence, exclusive=True)
except TargetExists:
    # The sidecar there is another record's, written while this one ran.
    remove_copy(unless_published=False)
    print(
        f"flow-record-evidence.sh: refusing — evidence {safe_name} was recorded by another record "
        f"while this one ran; evidence is append-only, so record a correction under a new id",
        file=sys.stderr,
    )
    sys.exit(2)
except JournalAtomicError as e:
    # A copy made for a sidecar that could not be written is taken away
    # again, so neither is left without the other.
    remove_copy()
    print(f"flow-record-evidence.sh: {e}", file=sys.stderr)
    sys.exit(e.exit_code)
except Exception as e:
    # Any other failure: the same, in one line. Evidence PyYAML could read but
    # cannot write, nested too deep, is the evidence's fault, as at the read.
    remove_copy()
    if isinstance(e, RecursionError):
        print(f"flow-record-evidence.sh: evidence {safe_name} is nested too deep to write", file=sys.stderr)
        sys.exit(1)
    print(f"flow-record-evidence.sh: cannot record {safe_name}: {type(e).__name__}: {one_line(e)}", file=sys.stderr)
    sys.exit(2)
except BaseException:
    # A KeyboardInterrupt, before or after the sidecar is published.
    remove_copy()
    raise

print(f"flow-record-evidence.sh: recorded {safe_name} in {sidecar_target}", file=sys.stderr)
PYTHON
