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
# Exits:
#   0 — goal recorded/updated
#   1 — input error (missing arg, malformed YAML, schema violation)
#   2 — infrastructure error (PyYAML missing, write failed, symlink rejected)

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
if ! python3 -c "import os, sys; _flow_cwd = os.path.realpath(os.getcwd()); sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]; import yaml" >/dev/null 2>&1; then
  echo "flow-goal-record.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

MODE=""
GOAL_FILE=""
GOAL_ID=""
LIFECYCLE_FILE=""
FROM_STATUS=""
MERGE=0
INCREMENT_TURNS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --create)            MODE="create"; shift ;;
    --update-lifecycle)  MODE="update-lifecycle"; shift ;;
    --goal-file)         GOAL_FILE="$2"; shift 2 ;;
    --goal-id)           GOAL_ID="$2"; shift 2 ;;
    --lifecycle-file)    LIFECYCLE_FILE="$2"; shift 2 ;;
    --from-status)       FROM_STATUS="$2"; shift 2 ;;
    --merge)             MERGE=1; shift ;;
    --increment-turns)   INCREMENT_TURNS=1; shift ;;
    -h|--help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
    *)
      echo "flow-goal-record.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -z "$MODE" ] && { echo "flow-goal-record.sh: --create or --update-lifecycle is required" >&2; exit 1; }

case "$MODE" in
  create)
    [ -z "$GOAL_FILE" ] && { echo "flow-goal-record.sh: --goal-file is required for --create" >&2; exit 1; }
    [ -f "$GOAL_FILE" ] || { echo "flow-goal-record.sh: --goal-file '$GOAL_FILE' does not exist" >&2; exit 1; }
    ;;
  update-lifecycle)
    [ -z "$GOAL_ID" ]        && { echo "flow-goal-record.sh: --goal-id is required for --update-lifecycle" >&2; exit 1; }
    [ -z "$LIFECYCLE_FILE" ] && { echo "flow-goal-record.sh: --lifecycle-file is required for --update-lifecycle" >&2; exit 1; }
    [ -f "$LIFECYCLE_FILE" ] || { echo "flow-goal-record.sh: --lifecycle-file '$LIFECYCLE_FILE' does not exist" >&2; exit 1; }
    case "$GOAL_ID" in
      *..*|*/*)
        echo "flow-goal-record.sh: --goal-id contains '..' or '/' — refusing (got: $GOAL_ID)" >&2
        exit 1
        ;;
    esac
    ;;
esac

mkdir -p .flow/goals

# Stdout of the Python block carries the written goal path in --create mode
# (nothing in --update-lifecycle mode); all diagnostics go to stderr. Under
# `set -e` a non-zero Python exit aborts here with that exit code.
CREATED_TARGET=$(python3 - "$SCRIPT_DIR" "$MODE" "$GOAL_FILE" "$GOAL_ID" "$LIFECYCLE_FILE" "$FROM_STATUS" "$MERGE" "$INCREMENT_TURNS" <<'PYTHON'
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
import yaml
from _journal_atomic import (
    JournalAtomicError,
    acquire_lock,
    write_yaml_file,
    _read_with_no_follow,
    _atomic_write,
)

mode = sys.argv[2]
goal_file_arg = sys.argv[3]
goal_id_arg = sys.argv[4]
lifecycle_file_arg = sys.argv[5]
from_status_arg = sys.argv[6] if len(sys.argv) > 6 else ""
merge_arg = (sys.argv[7] if len(sys.argv) > 7 else "0") == "1"
increment_turns_arg = (sys.argv[8] if len(sys.argv) > 8 else "0") == "1"

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
            print(
                "flow-goal-record.sh: WARN jsonschema unavailable — goal validation skipped. "
                "Install via 'pip install jsonschema' for safety (malformed goal YAMLs will land on disk and may break the evaluator). "
                "This warning fires once per day per user.",
                file=sys.stderr,
            )
            try:
                with open(sentinel, "w", encoding="utf-8") as _f:
                    _f.write("")
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
        raise JournalAtomicError(
            f"goal YAML does not match schema: {e.message}",
            exit_code=1,
        )


if mode == "create":
    try:
        with open(goal_file_arg, "r", encoding="utf-8") as f:
            goal = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"flow-goal-record.sh: --goal-file is not valid YAML: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(goal, dict):
        print("flow-goal-record.sh: goal YAML must be a top-level mapping", file=sys.stderr)
        sys.exit(1)

    metadata = goal.get("metadata") or {}
    goal_id = metadata.get("id")
    if not goal_id or not isinstance(goal_id, str):
        print("flow-goal-record.sh: goal.metadata.id is required and must be a string", file=sys.stderr)
        sys.exit(1)

    # Defense against path traversal in id (schema regex rejects it too;
    # this is belt-and-suspenders).
    if ".." in goal_id or "/" in goal_id:
        print(f"flow-goal-record.sh: goal.metadata.id contains '..' or '/' — refusing (got: {goal_id})", file=sys.stderr)
        sys.exit(1)

    try:
        _validate_goal(goal)
    except JournalAtomicError as e:
        print(f"flow-goal-record.sh: {e}", file=sys.stderr)
        sys.exit(e.exit_code)

    target = os.path.join(".flow", "goals", f"{goal_id}.goal.yaml")
    lockfile = target + ".lock"

    # Pre-flight: refuse to overwrite a non-terminal goal. The skill should
    # have caught this; second line of defense against TOCTOU. Goal YAML
    # files are pure YAML (no frontmatter), so we parse directly with
    # safe_load — no parse_frontmatter branch needed.
    if os.path.lexists(target):
        try:
            existing_content = _read_with_no_follow(target)
            existing = yaml.safe_load(existing_content)
            if not isinstance(existing, dict):
                # Valid YAML that is not a mapping — a list, a scalar, an empty
                # document. Falling through here overwrote it, which is the same
                # destructive answer as "no file exists" for a file that does.
                # Unreadable is unreadable however it got that way; the handler
                # below refuses for the parse-error form of exactly this.
                print(
                    f"flow-goal-record.sh: refusing to overwrite — existing goal at {target} is not a mapping "
                    f"({type(existing).__name__}); its status cannot be determined; investigate manually.",
                    file=sys.stderr,
                )
                sys.exit(2)
            existing_lifecycle = existing.get("lifecycle")
            if existing_lifecycle is not None and not isinstance(existing_lifecycle, dict):
                # `lifecycle: active` written as a scalar raises AttributeError on
                # .get below, which this handler does not catch; and treating it
                # as absent would read a goal whose status nobody can determine
                # as a goal safe to clobber.
                print(
                    f"flow-goal-record.sh: refusing to overwrite — existing goal at {target} has a lifecycle that is "
                    f"not a mapping ({type(existing_lifecycle).__name__}); investigate manually.",
                    file=sys.stderr,
                )
                sys.exit(2)
            existing_status = (existing_lifecycle or {}).get("status")
            if existing_status in ("draft", "active", "waiting_for_user", "waiting_for_ci", "blocked"):
                print(
                    f"flow-goal-record.sh: refusing to overwrite — {target} exists with non-terminal status '{existing_status}'",
                    file=sys.stderr,
                )
                print("flow-goal-record.sh: use /flow:goal clear to cancel before re-creating", file=sys.stderr)
                sys.exit(1)
        except (JournalAtomicError, yaml.YAMLError) as e:
            # If we can't read the existing file, REFUSE rather than fall
            # through and overwrite — we can't determine the on-disk status.
            print(
                f"flow-goal-record.sh: refusing to overwrite — existing goal at {target} is unreadable ({type(e).__name__}: {e}); investigate manually.",
                file=sys.stderr,
            )
            sys.exit(2)

    try:
        write_yaml_file(target, lockfile, goal)
    except JournalAtomicError as e:
        print(f"flow-goal-record.sh: {e}", file=sys.stderr)
        sys.exit(e.exit_code)
    print(f"flow-goal-record.sh: created {target}", file=sys.stderr)
    print(target)

elif mode == "update-lifecycle":
    target = os.path.join(".flow", "goals", f"{goal_id_arg}.goal.yaml")
    lockfile = target + ".lock"

    if not os.path.lexists(target):
        print(f"flow-goal-record.sh: {target} does not exist — cannot update", file=sys.stderr)
        sys.exit(1)

    # Read the lifecycle fragment the caller provided.
    try:
        with open(lifecycle_file_arg, "r", encoding="utf-8") as f:
            lifecycle_fragment = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"flow-goal-record.sh: --lifecycle-file is not valid YAML: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(lifecycle_fragment, dict) or "lifecycle" not in lifecycle_fragment:
        print("flow-goal-record.sh: --lifecycle-file must contain a top-level 'lifecycle:' block", file=sys.stderr)
        sys.exit(1)

    # Lock + read + merge + write atomically.
    lock_fd = acquire_lock(lockfile)
    try:
        try:
            existing_content = _read_with_no_follow(target)
            existing = yaml.safe_load(existing_content)
        except JournalAtomicError as e:
            print(f"flow-goal-record.sh: {e}", file=sys.stderr)
            sys.exit(e.exit_code)
        if not isinstance(existing, dict):
            print(f"flow-goal-record.sh: existing goal {target} is not a valid YAML mapping", file=sys.stderr)
            sys.exit(1)

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
            print(
                f"flow-goal-record.sh: refusing — existing goal {target} has a lifecycle that is not a mapping "
                f"({type(existing_lifecycle).__name__}); its current status cannot be determined, so no "
                f"transition can be checked against it.",
                file=sys.stderr,
            )
            sys.exit(1)
        current_status = (existing_lifecycle or {}).get("status")
        new_status = (lifecycle_fragment.get("lifecycle") or {}).get("status")

        if from_status_arg and from_status_arg != current_status:
            print(
                f"flow-goal-record.sh: race detected — observed lifecycle.status='{current_status}', "
                f"caller expected '{from_status_arg}'. Refusing to overwrite.",
                file=sys.stderr,
            )
            sys.exit(1)

        if current_status in TERMINAL_STATES:
            print(
                f"flow-goal-record.sh: refusing — lifecycle.status='{current_status}' is terminal; "
                f"terminal goals are immutable per goal-lifecycle/SKILL.md.",
                file=sys.stderr,
            )
            sys.exit(1)

        if current_status is not None and new_status is not None:
            allowed = LIFECYCLE_TRANSITIONS.get(current_status, set())
            if new_status not in allowed and new_status != current_status:
                print(
                    f"flow-goal-record.sh: refusing — '{current_status}' → '{new_status}' is not a permitted transition. "
                    f"Allowed from '{current_status}': {sorted(allowed) or 'none (terminal)'}.",
                    file=sys.stderr,
                )
                sys.exit(1)

        # Replace the lifecycle block by default, so the caller has full
        # control over the final shape. --merge keeps every field the fragment
        # does not name; --increment-turns counts from the value on disk.
        new_lifecycle = lifecycle_fragment["lifecycle"] or {}
        if merge_arg:
            new_lifecycle = {**(existing_lifecycle or {}), **new_lifecycle}
        if increment_turns_arg:
            new_lifecycle = dict(new_lifecycle)
            new_lifecycle["turns_evaluated"] = int((existing_lifecycle or {}).get("turns_evaluated") or 0) + 1
        existing["lifecycle"] = new_lifecycle

        try:
            _validate_goal(existing)
        except JournalAtomicError as e:
            print(f"flow-goal-record.sh: post-merge {e}", file=sys.stderr)
            sys.exit(e.exit_code)

        # Write atomically (re-uses lock we already hold)
        new_content = yaml.safe_dump(
            existing, sort_keys=False, default_flow_style=False, allow_unicode=True,
        )
        _atomic_write(target, new_content)
    finally:
        try:
            os.close(lock_fd)
        except OSError:
            pass

    new_status = (lifecycle_fragment["lifecycle"] or {}).get("status", "<unset>")
    print(f"flow-goal-record.sh: updated {target} lifecycle.status to '{new_status}'", file=sys.stderr)
PYTHON
)

# Record the freshly created goal in the per-user trust ledger. Best-effort:
# the goal is already on disk and valid; a ledger problem is a note, not a
# failure (the Stop hook simply treats the goal as untrusted until recorded).
if [ "$MODE" = "create" ] && [ -n "$CREATED_TARGET" ]; then
  if ! TRUST_ERR=$("${SCRIPT_DIR}/flow-goal-trust.sh" record --goal-file "$CREATED_TARGET" 2>&1 >/dev/null); then
    echo "flow-goal-record.sh: note — trust ledger record failed; run '${SCRIPT_DIR}/flow-goal-trust.sh record --goal-file ${CREATED_TARGET}' to let the Stop hook execute this goal's verification commands (${TRUST_ERR})" >&2
  fi
fi
