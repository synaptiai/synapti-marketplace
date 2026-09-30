#!/usr/bin/env bash
# [flow] Record or update a FlowGoal in .flow/goals/<id>.goal.yaml.
#
# Two modes:
#   --create:           write a new goal YAML from scratch (refuses if existing
#                       goal has non-terminal status — goal-contract-capture
#                       does the pre-flight check, this is a second line of
#                       defense against race conditions)
#   --update-lifecycle: merge a new lifecycle block into an existing goal
#                       (used by goal-lifecycle skill)
#
# Atomicity: all writes through bin/_journal_atomic.py — O_NOFOLLOW + flock +
# tempfile+rename + fsync. Schema validation via jsonschema when available.
#
# Trust: after a successful --create, the goal is recorded in the per-user
# trust ledger (bin/flow-goal-trust.sh record) so the Stop hook may execute
# its verification commands without flow.goals.executeVerificationCommands.
# A ledger failure never fails the create — it is reported on stderr.
#
# Usage:
#   flow-goal-record.sh --create --goal-file <path-to-yaml>
#   flow-goal-record.sh --update-lifecycle --goal-id <id> --lifecycle-file <path-to-yaml-fragment>
#                       [--from-status <status>] [--merge] [--increment-turns]
#
#   --merge            the fragment's lifecycle fields are merged into the
#                      goal's current lifecycle instead of replacing it
#   --increment-turns  lifecycle.turns_evaluated becomes its current value + 1
#   Both read the current lifecycle under the goal's lock, so a caller that
#   changes one field never writes back a stale copy of the others.
#
# .flow/goals is created if it is missing, and never through a symlink: when
# .flow or .flow/goals is one (a repository can commit such a link to a
# directory outside the checkout), nothing is written and the helper exits 2.
#
# Every message is one line of text: a value in it is escaped and, when no
# earlier check has bounded it, cut (bin/_flow_cli.py).
#
# Exits:
#   0 — goal recorded or updated (a trust ledger that could not be written is
#       a note); or --help
#   1 — the arguments or the input: an argument that is not an option, or an
#       option with no value; neither --create nor --update-lifecycle; no
#       --goal-file for --create, no --goal-id or --lifecycle-file for
#       --update-lifecycle; a --goal-id holding '..' or '/', or too long for
#       the names written for it; a --goal-file or --lifecycle-file that is
#       not there or not a regular file, or that cannot be read for a reason
#       of its path; a file that is not UTF-8, not valid YAML (a value PyYAML
#       cannot build included) or nested too deep to read; a goal whose top
#       level or metadata is not a mapping, with no metadata.id, or one that
#       holds '..' or '/' or is too long for the names written for it; a
#       fragment with no top-level lifecycle block, or whose lifecycle is not
#       a mapping or whose status is not text; a goal that does not
#       match the schema (with jsonschema installed); an existing goal with a
#       non-terminal status (--create); a goal to update that does not exist,
#       is not a mapping, has a lifecycle that is not a mapping, a status that
#       is not text or a turns_evaluated that is not a whole number (with
#       --increment-turns), is terminal, or is not in the --from-status given;
#       a transition the lifecycle does not permit
#   2 — python3 or PyYAML missing; an input that cannot be read for a reason
#       of the system; .flow or .flow/goals refused or not made (a symlink
#       included); an existing goal that cannot be read (not UTF-8, not valid
#       YAML, nested too deep, a symlink or not a regular file), or whose
#       status cannot be determined (--create); the goal's lock refused; the
#       write refused or failing

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-goal-record.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; import yaml" >/dev/null 2>&1; then
  echo "flow-goal-record.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

# --help, where an option is expected. Every other argument is python3's to
# read, and to refuse: a message that prints a value is written by one
# printer, whatever the shell's locale.
wants_help() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --create|--update-lifecycle|--merge|--increment-turns) shift ;;
      --goal-file|--goal-id|--lifecycle-file|--from-status) [ $# -ge 2 ] || return 1; shift 2 ;;
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

# All diagnostics go to stderr; python3 also records a created goal in the
# trust ledger, so that its note is printed the same way.
python3 - "$SCRIPT_DIR" "$@" <<'PYTHON'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import sys

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import os
import subprocess
import yaml
from _flow_cli import Messages, name_max, open_regular, schema_problem, shown, yaml_problem
from _journal_atomic import (
    JournalAtomicError,
    acquire_lock,
    ensure_repo_dir,
    write_yaml_file,
    yaml_text,
    _read_with_no_follow,
    _atomic_write,
)

messages = Messages("flow-goal-record.sh")
say, refuse = messages.say, messages.refuse

GOALS_DIR = os.path.join(".flow", "goals")


def _make_goals_dir():
    """Create .flow/goals; refuse, exit 2, when .flow or it is a symlink or not a directory."""
    try:
        ensure_repo_dir(GOALS_DIR, create=True)
    except JournalAtomicError as e:
        refuse(f"{e}", e.exit_code)


options = messages.read_arguments(
    sys.argv[2:],
    ("--goal-file", "--goal-id", "--lifecycle-file", "--from-status"),
    ("--create", "--update-lifecycle", "--merge", "--increment-turns"),
)
# The last of --create and --update-lifecycle given wins, as the shell's
# loop had it.
mode = ""
for arg in sys.argv[2:]:
    if arg == "--create" and options["--create"]:
        mode = "create"
    elif arg == "--update-lifecycle" and options["--update-lifecycle"]:
        mode = "update-lifecycle"
goal_file_arg = options["--goal-file"]
goal_id_arg = options["--goal-id"]
lifecycle_file_arg = options["--lifecycle-file"]
from_status_arg = options["--from-status"]
merge_arg = options["--merge"]
increment_turns_arg = options["--increment-turns"]

# A goal's id names .flow/goals/<id>.goal.yaml, <id>.goal.yaml.lock and,
# while it is written, <id>.goal.yaml.<8 random characters>.tmp, the
# longest. The schema's pattern holds an id to 64 characters; where the file
# system takes shorter names, the limit is lower. A name longer than that
# fails to be made, and its error prints the whole path.
MAX_ID = 64
LONGEST_EXTRA = len(".goal.yaml.") + 8 + len(".tmp")
ID_LIMIT = min(MAX_ID, name_max() - LONGEST_EXTRA)


def check_input(flag, path):
    """A --goal-file or --lifecycle-file that is there and a regular file."""
    if not os.path.exists(path):
        refuse(f"{flag} {shown(path)} does not exist")
    if not os.path.isfile(path):
        refuse(f"{flag} {shown(path)} is not a regular file")


def read_yaml(flag, path):
    """The YAML at `path`; whatever stops the read is refused in one line."""
    try:
        with open_regular(path) as f:
            return yaml.safe_load(f)
    except RecursionError:
        refuse(f"{flag} is nested too deep to read")
    except UnicodeDecodeError as e:
        refuse(f"{flag} is not UTF-8: {shown(e)}")
    except OSError as e:
        messages.cannot("read", flag, path, e)
    except yaml.YAMLError as e:
        refuse(f"{flag} is not valid YAML: {yaml_problem(e)}")
    except Exception as e:
        # Parsed, but PyYAML could not build a value from it: its
        # constructors raise ValueError, AttributeError or KeyError.
        refuse(f"{flag} is not valid YAML: {type(e).__name__}: {shown(e)}")


def read_existing(target, what):
    """The goal already at `target`, parsed. Whatever stops the read (a
    symlink or a file that is not regular, which _read_with_no_follow refuses;
    a read that fails; text that is not UTF-8, not valid YAML, a value PyYAML
    cannot build, or nesting too deep) is refused in one line, exit 2: the
    goal's status cannot be determined, so nothing is written over it."""
    try:
        return yaml.safe_load(_read_with_no_follow(target))
    except JournalAtomicError as e:
        refuse(f"{what} — {e}", 2)
    except RecursionError:
        refuse(f"{what} — existing goal at {target} is nested too deep to read", 2)
    except UnicodeDecodeError as e:
        refuse(f"{what} — existing goal at {target} is not UTF-8: {shown(e)}", 2)
    except OSError as e:
        refuse(f"{what} — existing goal at {target} cannot be read: {e.strerror or shown(e)}", 2)
    except yaml.YAMLError as e:
        refuse(f"{what} — existing goal at {target} is not valid YAML: {yaml_problem(e)}", 2)
    except Exception as e:
        refuse(f"{what} — existing goal at {target} is not valid YAML: {type(e).__name__}: {shown(e)}", 2)


if not mode:
    refuse("--create or --update-lifecycle is required")
if mode == "create":
    if not goal_file_arg:
        refuse("--goal-file is required for --create")
    check_input("--goal-file", goal_file_arg)
else:
    if not goal_id_arg:
        refuse("--goal-id is required for --update-lifecycle")
    if not lifecycle_file_arg:
        refuse("--lifecycle-file is required for --update-lifecycle")
    check_input("--lifecycle-file", lifecycle_file_arg)
    if ".." in goal_id_arg or "/" in goal_id_arg:
        refuse(f"--goal-id contains '..' or '/' — refusing (got: {shown(goal_id_arg)})")
    if len(goal_id_arg) > ID_LIMIT:
        refuse(f"--goal-id is too long: {len(goal_id_arg)} characters; at most {ID_LIMIT}")

# Lifecycle state-machine table. Source-of-truth: goal-lifecycle/SKILL.md.
# Terminal states are not present as keys — any transition out of them is
# rejected. blocked → achieved direct is rejected (must go through active).
LIFECYCLE_TRANSITIONS = {
    "draft":              {"active", "cancelled"},
    "active":             {"waiting_for_user", "waiting_for_ci", "blocked", "achieved", "failed", "cancelled"},
    "waiting_for_user":   {"active", "cancelled"},
    "waiting_for_ci":     {"active", "cancelled"},
    "blocked":            {"active", "cancelled", "failed"},
    # terminal: achieved, failed, cancelled — no outgoing transitions
}
TERMINAL_STATES = {"achieved", "failed", "cancelled"}

# When jsonschema is unavailable, emit a stderr WARN dedup'd PER DAY via a
# sentinel file. The original
# implementation used a module-level Python sentinel that reset on
# every bash invocation (because each bash call spawns a fresh Python), so
# the WARN fired on every /flow:goal command — noise that drowned out real
# diagnostics.
#
# Sentinel location: ${TMPDIR}/flow-warn-jsonschema-${USER}-YYYY-MM-DD rather
# than $HOME/.claude/ because overriding HOME (which tests sometimes do for
# isolation) breaks Python's user-site-packages lookup and would hide PyYAML.
# TMPDIR is honored, USER prevents cross-user collision on shared hosts.
# The directory can be shared (/tmp), so the sentinel is made with O_EXCL: a
# name another user put there first, a symlink included, is left alone, never
# followed to a file of this user's and emptied.
def _validate_goal(goal):
    import datetime, tempfile, getpass
    schemas_dir = os.path.join(script_dir, "..", "schemas", "v1")
    schema_path = os.path.normpath(os.path.join(schemas_dir, "goal.schema.json"))
    try:
        import json, jsonschema
    except ImportError:
        today = datetime.date.today().isoformat()
        try:
            user = getpass.getuser() or "default"
        except Exception:
            user = "default"
        # Sanitize username (could contain unsafe chars on misconfigured hosts).
        user = "".join(c for c in user if c.isalnum() or c in "_-")[:32] or "default"
        sentinel_dir = tempfile.gettempdir()
        sentinel = os.path.join(sentinel_dir, f"flow-warn-jsonschema-{user}-{today}")
        if not os.path.exists(sentinel):
            say(
                "WARN jsonschema unavailable — goal validation skipped. "
                "Install via 'pip install jsonschema' for safety (malformed goal YAMLs will land on disk and may break the evaluator). "
                "This warning fires once per day per user."
            )
            try:
                os.close(os.open(sentinel, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
            except OSError:
                # If we can't write the sentinel, WARN will re-fire on the
                # next invocation — better than masking the diagnostic.
                pass
        return  # validation skipped
    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)
    try:
        jsonschema.validate(instance=goal, schema=schema)
    except jsonschema.ValidationError as e:
        # Where and which rule, never e.message, which quotes the whole value.
        raise JournalAtomicError(
            f"goal YAML does not match schema {schema_problem(e)}",
            exit_code=1,
        )


if mode == "create":
    goal = read_yaml("--goal-file", goal_file_arg)
    if not isinstance(goal, dict):
        refuse("goal YAML must be a top-level mapping")

    metadata = goal.get("metadata") or {}
    if not isinstance(metadata, dict):
        refuse("goal.metadata must be a mapping")
    goal_id = metadata.get("id")
    if not goal_id or not isinstance(goal_id, str):
        refuse("goal.metadata.id is required and must be a string")

    # Defense against path traversal in id (schema regex rejects it too;
    # this is belt-and-suspenders).
    if ".." in goal_id or "/" in goal_id:
        refuse(f"goal.metadata.id contains '..' or '/' — refusing (got: {shown(goal_id)})")
    if len(goal_id) > ID_LIMIT:
        refuse(f"goal.metadata.id is too long: {len(goal_id)} characters; at most {ID_LIMIT}")

    try:
        _validate_goal(goal)
    except JournalAtomicError as e:
        refuse(f"{e}", e.exit_code)

    # The goal's text is made here, once, and written as it is. PyYAML reads
    # some files it cannot write (nesting too deep), and that is the file's
    # fault: found here, before .flow/goals is made, it is refused.
    try:
        goal_text = yaml_text(goal)
    except RecursionError:
        refuse("goal is nested too deep to write")
    except Exception as e:
        refuse(f"goal cannot be written as YAML: {type(e).__name__}: {shown(e)}")

    _make_goals_dir()
    target = os.path.join(GOALS_DIR, f"{goal_id}.goal.yaml")
    lockfile = target + ".lock"

    # Pre-flight: refuse to overwrite a non-terminal goal. The skill should
    # have caught this; second line of defense against TOCTOU. Goal YAML
    # files are pure YAML (no frontmatter), so we parse directly with
    # safe_load — no parse_frontmatter branch needed.
    if os.path.lexists(target):
        existing = read_existing(target, "refusing to overwrite")
        if not isinstance(existing, dict):
            # Valid YAML that is not a mapping — a list, a scalar, an empty
            # document. Falling through here overwrote it, which is the same
            # destructive answer as "no file exists" for a file that does.
            # Unreadable is unreadable however it got that way; read_existing()
            # refuses the parse-error form of exactly this.
            refuse(
                f"refusing to overwrite — existing goal at {target} is not a mapping "
                f"({type(existing).__name__}); its status cannot be determined; investigate manually.",
                2,
            )
        existing_lifecycle = existing.get("lifecycle")
        if existing_lifecycle is not None and not isinstance(existing_lifecycle, dict):
            # `lifecycle: active` written as a scalar would raise
            # AttributeError on .get below; and treating it as absent would
            # read a goal whose status nobody can determine as a goal safe to
            # clobber.
            refuse(
                f"refusing to overwrite — existing goal at {target} has a lifecycle that is "
                f"not a mapping ({type(existing_lifecycle).__name__}); investigate manually.",
                2,
            )
        existing_status = (existing_lifecycle or {}).get("status")
        if existing_status in ("draft", "active", "waiting_for_user", "waiting_for_ci", "blocked"):
            say(f"refusing to overwrite — {target} exists with non-terminal status '{shown(existing_status)}'")
            refuse("use /flow:goal clear to cancel before re-creating")

    try:
        write_yaml_file(target, lockfile, goal, text=goal_text)
    except JournalAtomicError as e:
        refuse(f"{e}", e.exit_code)
    say(f"created {target}")

    # Record the freshly created goal in the per-user trust ledger. Best-effort:
    # the goal is already on disk and valid; a ledger problem is a note, not a
    # failure (the Stop hook simply treats the goal as untrusted until recorded).
    # A ledger script that cannot be started (not executable, gone, or a .sh
    # a native Windows python3 cannot run) is the same note: the goal stands.
    trust = os.path.join(script_dir, "flow-goal-trust.sh")
    try:
        ledger = subprocess.run(
            [trust, "record", "--goal-file", target],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, errors="replace",
        )
        problem = None if ledger.returncode == 0 else shown(ledger.stderr.strip())
    except OSError as e:
        problem = e.strerror or shown(e)
    if problem is not None:
        say(
            f"note — trust ledger record failed; run '{trust} record --goal-file {target}' "
            f"to let the Stop hook execute this goal's verification commands ({problem})"
        )

elif mode == "update-lifecycle":
    # A goal reached through a symlinked .flow or .flow/goals is outside the
    # repository: acquire_lock() below refuses it, before anything is written.
    target = os.path.join(GOALS_DIR, f"{goal_id_arg}.goal.yaml")
    lockfile = target + ".lock"

    if not os.path.lexists(target):
        refuse(f"{target} does not exist — cannot update")

    # Read the lifecycle fragment the caller provided.
    lifecycle_fragment = read_yaml("--lifecycle-file", lifecycle_file_arg)
    if not isinstance(lifecycle_fragment, dict) or "lifecycle" not in lifecycle_fragment:
        refuse("--lifecycle-file must contain a top-level 'lifecycle:' block")
    # An empty block (lifecycle: with nothing under it) replaces the lifecycle
    # with an empty one, as before; anything else must be a mapping whose
    # status, when it has one, is text, which the transition table can hold.
    fragment_lifecycle = lifecycle_fragment["lifecycle"]
    if fragment_lifecycle is not None and not isinstance(fragment_lifecycle, dict):
        refuse(f"--lifecycle-file's lifecycle must be a mapping, not {type(fragment_lifecycle).__name__}")
    new_status = (fragment_lifecycle or {}).get("status")
    if new_status is not None and not isinstance(new_status, str):
        refuse(f"--lifecycle-file's lifecycle.status must be text, not {type(new_status).__name__}")

    # Lock + read + merge + write atomically. A refused lockfile exits 2, as
    # the header says, rather than escaping as a traceback and exit 1.
    try:
        lock_fd = acquire_lock(lockfile)
    except JournalAtomicError as e:
        refuse(f"{e}", e.exit_code)
    try:
        existing = read_existing(target, "refusing to update")
        if not isinstance(existing, dict):
            refuse(f"existing goal {target} is not a valid YAML mapping")

        # Enforce the lifecycle transition table BEFORE merging. Terminal
        # states are immutable; out-of-table transitions are refused. If
        # --from-status was provided, also assert it matches the on-disk
        # state (race detection for concurrent updates).
        # An absent lifecycle is a goal mid-creation and reads as status None.
        # A lifecycle that is PRESENT but is not a mapping — `lifecycle: []`,
        # `lifecycle: ""`, `lifecycle: 0`, a scalar — is falsy too, so `or {}`
        # collapsed it to the same None. Every guard below keys off
        # current_status, and the transition table is explicitly skipped when it
        # is None, so that collapse accepted any new status at all, including
        # active → achieved with no evaluation behind it.
        existing_lifecycle = existing.get("lifecycle")
        if existing_lifecycle is not None and not isinstance(existing_lifecycle, dict):
            refuse(
                f"refusing — existing goal {target} has a lifecycle that is not a mapping "
                f"({type(existing_lifecycle).__name__}); its current status cannot be determined, so no "
                f"transition can be checked against it."
            )
        current_status = (existing_lifecycle or {}).get("status")
        if current_status is not None and not isinstance(current_status, str):
            refuse(
                f"refusing — existing goal {target} has a lifecycle.status that is not text "
                f"({type(current_status).__name__}); no transition can be checked against it."
            )

        if from_status_arg and from_status_arg != current_status:
            refuse(
                f"race detected — observed lifecycle.status='{shown(current_status)}', "
                f"caller expected '{shown(from_status_arg)}'. Refusing to overwrite."
            )

        if current_status in TERMINAL_STATES:
            refuse(
                f"refusing — lifecycle.status='{current_status}' is terminal; "
                f"terminal goals are immutable per goal-lifecycle/SKILL.md."
            )

        if current_status is not None and new_status is not None:
            allowed = LIFECYCLE_TRANSITIONS.get(current_status, set())
            if new_status not in allowed and new_status != current_status:
                refuse(
                    f"refusing — '{shown(current_status)}' → '{shown(new_status)}' is not a permitted transition. "
                    f"Allowed from '{shown(current_status)}': {sorted(allowed) or 'none (terminal)'}."
                )

        # Replace the lifecycle block by default, so the caller has full
        # control over the final shape. --merge keeps every field the fragment
        # does not name; --increment-turns counts from the value on disk.
        new_lifecycle = fragment_lifecycle or {}
        if merge_arg:
            new_lifecycle = {**(existing_lifecycle or {}), **new_lifecycle}
        if increment_turns_arg:
            turns = (existing_lifecycle or {}).get("turns_evaluated") or 0
            if isinstance(turns, bool) or not isinstance(turns, int):
                refuse(
                    f"refusing — existing goal {target} has a lifecycle.turns_evaluated that is not "
                    f"a whole number ({type(turns).__name__}); it cannot be counted on from."
                )
            new_lifecycle = dict(new_lifecycle)
            new_lifecycle["turns_evaluated"] = turns + 1
        existing["lifecycle"] = new_lifecycle

        try:
            _validate_goal(existing)
        except JournalAtomicError as e:
            refuse(f"post-merge {e}", e.exit_code)

        # Write atomically (re-uses lock we already hold). A merged goal
        # nested too deep to write is refused before anything is written.
        try:
            new_content = yaml.safe_dump(
                existing, sort_keys=False, default_flow_style=False, allow_unicode=True,
            )
        except RecursionError:
            refuse("goal is nested too deep to write, with the lifecycle merged in")
        except Exception as e:
            refuse(f"goal cannot be written as YAML, with the lifecycle merged in: {type(e).__name__}: {shown(e)}")
        try:
            _atomic_write(target, new_content)
        except JournalAtomicError as e:
            refuse(f"{e}", e.exit_code)
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass

    new_status = (lifecycle_fragment["lifecycle"] or {}).get("status", "<unset>")
    say(f"updated {target} lifecycle.status to '{shown(new_status)}'")
PYTHON
