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
# Exits (every path and its message are listed in .decisions/issue-272.md):
#   0 — evidence recorded; or --help
#   1 — the arguments or the inputs: an argument that is not an option, or an
#       option with no value; no --run-id or no --evidence-file; a --run-id
#       holding '..' or '/', or longer than a directory name; an
#       --evidence-file or a --raw-output that is not there or not a regular
#       file, or that cannot be read for a reason of its path (not found, not
#       permitted, not a file that can be read, a name too long); evidence
#       that is not UTF-8, is not valid YAML (a value PyYAML cannot build
#       included), uses a YAML alias, is nested too deep to read, or cannot be
#       written as YAML; a top level or a metadata that is not a mapping; no
#       metadata.id, or one too long for the names written for it; an
#       output_ref other than the name --raw-output is copied to; evidence
#       that does not match the schema (with jsonschema installed)
#   2 — python3 or PyYAML missing; an --evidence-file or a --raw-output that
#       is a symlink, or that cannot be opened or read for a reason of the
#       system (too many open files, an I/O error); the run or evidence
#       directory refused or not made (a symlinked .flow, .flow/runs or run
#       directory included); the id already recorded, or recorded by another
#       record while this one ran; something in the way of the copy; the copy
#       failing; the sidecar's write failing
#   130 — interrupted (SIGINT)

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

# --help, where an option is expected. Every other argument is python3's to
# read, and to refuse: a message that prints a value is written by one
# printer, whatever the shell's locale.
wants_help() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-id|--evidence-file|--raw-output) [ $# -ge 2 ] || return 1; shift 2 ;;
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

python3 - "$SCRIPT_DIR" "$@" <<'PYTHON'
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import errno
import os
import re
import stat

import yaml
from _flow_cli import O_BINARY, O_NOFOLLOW, Messages, name_max, schema_problem, shown, yaml_problem
from _journal_atomic import JournalAtomicError, TargetExists, ensure_repo_dir, write_yaml_file, yaml_text


# Every message is one line of text, printed by say(), which escapes the
# whole of it; a value from outside that no earlier check has bounded (an
# argument, a path, a value from the evidence file, an error's text) is also
# cut by shown(). Both are bin/_flow_cli.py's, shared with the other writers.
messages = Messages("flow-record-evidence.sh")
say, refuse = messages.say, messages.refuse


# The arguments, read as the shell passed them.
options = messages.read_arguments(sys.argv[2:], ("--run-id", "--evidence-file", "--raw-output"))
run_id = options["--run-id"]
evidence_file = options["--evidence-file"]
raw_output = options["--raw-output"] or None
if not run_id:
    refuse("--run-id is required")
if not evidence_file:
    refuse("--evidence-file is required")
if ".." in run_id or "/" in run_id:
    refuse(f"--run-id contains '..' or '/' — refusing for safety (got: {shown(run_id)})")

# The longest name a file system here takes. The run id is a directory's name,
# and the id names the sidecar, its copy and the sidecar's temporary file:
# a name longer than this fails to be made, and its error prints the whole
# path.
NAME_MAX = name_max()
run_id_bytes = len(os.fsencode(run_id))
if run_id_bytes > NAME_MAX:
    refuse(f"--run-id is {run_id_bytes} bytes; a directory name here holds at most {NAME_MAX}")


# The copy is created with O_NOFOLLOW and O_BINARY, where the platform has
# each (bin/_flow_cli.py says why); the inputs are opened by
# messages.open_input().
_O_NOFOLLOW = O_NOFOLLOW
_O_BINARY = O_BINARY


class AliasRefused(Exception):
    pass


# The name PyYAML gives its input in an error: a short label, not the path,
# which the message would print twice and the cut could take the line and
# column off.
YAML_NAME = "--evidence-file"


def refuse_aliases(text):
    """Evidence is a record, not a program. PyYAML shares an alias's value
    in memory, but anything that prints the value (a schema refusal) prints
    every copy: a few hundred bytes of nested aliases become megabytes on one
    line. Nothing flow writes uses an alias, so refusing them costs nothing.
    The events are read in a pass of their own, which does not recurse: a
    loader that checked in compose_node would add a frame to every level of
    nesting, and read a third less deep than PyYAML does."""
    scan = yaml.SafeLoader(text)
    scan.name = YAML_NAME
    try:
        while scan.check_event():
            if isinstance(scan.get_event(), yaml.events.AliasEvent):
                raise AliasRefused()
    finally:
        scan.dispose()


# Both inputs are opened, and so checked, before anything is read or made:
# a raw output that cannot be read leaves no run directory behind.
evidence_fd = messages.open_input(evidence_file, "--evidence-file", "--evidence-file")
raw_fd = messages.open_input(raw_output, "--raw-output", "raw-output source") if raw_output else None

# Whatever stops the read is the evidence file's fault, named in one line.
try:
    with os.fdopen(evidence_fd, "r", encoding="utf-8") as f:
        evidence_text = f.read()
    refuse_aliases(evidence_text)
    loader = yaml.SafeLoader(evidence_text)
    loader.name = YAML_NAME
    try:
        evidence = loader.get_single_data()
    finally:
        loader.dispose()
except RecursionError:
    refuse("--evidence-file is nested too deep to read")
except UnicodeDecodeError as e:
    refuse(f"--evidence-file is not UTF-8: {shown(e)}")
except OSError as e:
    messages.cannot("read", "--evidence-file", evidence_file, e)
except AliasRefused:
    refuse("--evidence-file uses a YAML alias, which evidence does not need")
except yaml.YAMLError as e:
    refuse(f"--evidence-file is not valid YAML: {yaml_problem(e)}")
except Exception as e:
    # Parsed, but PyYAML could not build a value from it: a date with a
    # thirteenth month, an integer over Python's digit limit, a scalar its
    # explicit tag does not fit. Its constructors raise ValueError,
    # AttributeError or KeyError here, not a YAMLError.
    refuse(f"--evidence-file is not valid YAML: {type(e).__name__}: {shown(e)}")

if not isinstance(evidence, dict):
    refuse("evidence YAML must be a top-level mapping")

metadata = evidence.get("metadata") or {}
if not isinstance(metadata, dict):
    refuse("evidence.metadata must be a mapping")
evidence_id = metadata.get("id")
if not evidence_id or not isinstance(evidence_id, str):
    refuse("evidence.metadata.id is required and must be a string")

safe_name = re.sub(r"[^a-z0-9_-]", "-", evidence_id.lower())

# The id names three files: <name>.evidence.yaml, <name>.txt and, while the
# sidecar is written, <name>.evidence.yaml.<8 random characters>.tmp, the
# longest. The schema's maxLength for metadata.id is MAX_ID; where the file
# system takes shorter names, the limit is lower. Checked here, before
# anything is made, and the name is bounded from here on.
MAX_ID = 200
LONGEST_EXTRA = len(".evidence.yaml.") + 8 + len(".tmp")
id_limit = min(MAX_ID, NAME_MAX - LONGEST_EXTRA)
if max(len(evidence_id), len(safe_name)) > id_limit:
    refuse(f"evidence.metadata.id is too long: {len(evidence_id)} characters; at most {id_limit}")

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
            refuse(
                f"output_ref is {shown(given)}, but --raw-output is copied to "
                f"{raw_name}; leave output_ref out and it is written"
            )
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
        # Where and which rule, from the schema; never e.message, which quotes
        # the whole value that failed, however large.
        refuse(f"evidence does not match schema {schema_problem(e)}")
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
        say(
            "WARN jsonschema unavailable — evidence validation skipped. "
            "Install via 'pip install jsonschema' for safety. Warning fires once per day per user."
        )
        try:
            with open(sentinel, "w", encoding="utf-8") as _f:
                _f.write("")
        except OSError:
            pass

# The sidecar's text is made here, once, and written as it is under the run's
# lock after the copy. PyYAML reads some evidence it cannot write (nesting
# too deep, an integer too long to write in decimal), and that is the
# evidence's fault: found here, before anything is made, it is refused as
# evidence that cannot be read is. The text written is the text made here,
# so a write that fails after this is the write's fault, never the
# evidence's.
try:
    sidecar_text = yaml_text(evidence)
except RecursionError:
    refuse(f"evidence {safe_name} is nested too deep to write")
except Exception as e:
    refuse(f"evidence {safe_name} cannot be written as YAML: {type(e).__name__}: {shown(e)}")

run_dir = os.path.join(".flow", "runs", run_id)
evidence_dir = os.path.join(run_dir, "evidence")
# Never os.makedirs: a repository can commit .flow or .flow/runs as a symlink
# to a directory outside the checkout, and makedirs would create the run there.
try:
    ensure_repo_dir(evidence_dir, create=True)
except JournalAtomicError as e:
    refuse(f"{e}", 2)

sidecar_target = os.path.join(evidence_dir, f"{safe_name}.evidence.yaml")
lockfile = os.path.join(run_dir, ".lock")

# Nothing is written until everything that can refuse has: a sidecar is the
# record the judge's bundle believes, so one must never name a copy that was
# not made, and one already recorded must never be replaced (evidence is
# append-only; a correction is a new id).
def already_recorded():
    say(
        f"refusing — evidence {safe_name} is already recorded in "
        f"{sidecar_target}; evidence is append-only, so record a correction under a new id"
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
copy_hold = None


def remove_copy(unless_published=True):
    """Take this record's copy away again. Never once the sidecar is there
    (unless_published): it names the copy, whoever wrote it. Not a file that
    has taken the copy's name: the copy is known by its device and inode
    number, and a descriptor held open on it keeps that number from being
    given to another file. That descriptor is closed only once the file at
    the name is known to be the copy, just before the unlink: Windows does not
    remove a file that is open."""
    global copy_hold
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
    if copy_hold is not None:
        try:
            os.close(copy_hold)
        except OSError:
            pass
        copy_hold = None
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
                say(f"refusing — raw-output target {raw_target} is a symlink")
            elif stat.S_ISREG(in_way.st_mode):
                # No sidecar, or the check above would have refused: another
                # record of this id is between its copy and its sidecar, or
                # one was stopped there.
                say(
                    f"refusing — a copy {raw_target} exists with no sidecar: "
                    f"a record of this id is running, or one was stopped; if none is running, "
                    f"remove it, or record under a new id"
                )
            else:
                say(f"refusing — {raw_target} is in the way, and not a regular file")
            sys.exit(2)
        src_fd = raw_fd
        try:
            dst_fd = os.open(raw_target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | _O_NOFOLLOW | _O_BINARY, 0o644)
        except OSError as e:
            os.close(src_fd)
            if getattr(e, "errno", None) in (errno.ELOOP, errno.EMLINK):
                say(f"refusing — raw-output target {raw_target} is a symlink")
            elif getattr(e, "errno", None) == errno.EEXIST:
                say(f"refusing — raw-output target {raw_target} already exists (evidence is immutable)")
            else:
                say(f"cannot create raw-output target {raw_target}: {e.strerror or shown(e)}")
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
            raise JournalAtomicError(f"raw-output copy failed: {e.strerror or shown(e)}", exit_code=2)

    # Then the sidecar, atomically and only if it is not there yet: the
    # check above ran outside the run's lock, and two records of one id can
    # overlap, so write_yaml_file decides again under the lock.
    write_yaml_file(sidecar_target, lockfile, evidence, exclusive=True, text=sidecar_text)
except TargetExists:
    # The sidecar there is another record's, written while this one ran.
    remove_copy(unless_published=False)
    say(
        f"refusing — evidence {safe_name} was recorded by another record "
        f"while this one ran; evidence is append-only, so record a correction under a new id"
    )
    sys.exit(2)
except JournalAtomicError as e:
    # A copy made for a sidecar that could not be written is taken away
    # again, so neither is left without the other.
    remove_copy()
    say(f"{e}")
    sys.exit(e.exit_code)
except Exception as e:
    # Any other failure: the same, in one line. The evidence was found
    # writable before the copy, so this is the write's fault.
    remove_copy()
    say(f"cannot record {safe_name}: {type(e).__name__}: {shown(e)}")
    sys.exit(2)
except BaseException:
    # A KeyboardInterrupt, before or after the sidecar is published.
    remove_copy()
    raise

say(f"recorded {safe_name} in {sidecar_target}")
PYTHON
