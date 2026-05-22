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
# Usage:
#   flow-goal-record.sh --create --goal-file <path-to-yaml>
#   flow-goal-record.sh --update-lifecycle --goal-id <id> --lifecycle-file <path-to-yaml-fragment>
#
# Exits:
#   0 — goal recorded/updated
#   1 — input error (missing arg, malformed YAML, schema violation)
#   2 — infrastructure error (PyYAML missing, write failed, symlink rejected)

set -euo pipefail
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-goal-record.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-goal-record.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

MODE=""
GOAL_FILE=""
GOAL_ID=""
LIFECYCLE_FILE=""
FROM_STATUS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --create)            MODE="create"; shift ;;
    --update-lifecycle)  MODE="update-lifecycle"; shift ;;
    --goal-file)         GOAL_FILE="$2"; shift 2 ;;
    --goal-id)           GOAL_ID="$2"; shift 2 ;;
    --lifecycle-file)    LIFECYCLE_FILE="$2"; shift 2 ;;
    --from-status)       FROM_STATUS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \?//'
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

python3 - "$SCRIPT_DIR" "$MODE" "$GOAL_FILE" "$GOAL_ID" "$LIFECYCLE_FILE" "$FROM_STATUS" <<'PYTHON'
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

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

# F11 (cycle-13) + cycle-14 F11-SENTINEL fix: when jsonschema is unavailable,
# emit a stderr WARN dedup'd PER DAY via a sentinel file. The original
# cycle-13 implementation used a module-level Python sentinel that reset on
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
            if isinstance(existing, dict):
                existing_status = (existing.get("lifecycle") or {}).get("status")
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
        current_status = (existing.get("lifecycle") or {}).get("status")
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

        # Merge the validated lifecycle block. We replace (not deep-merge)
        # so the caller has full control over the final shape.
        existing["lifecycle"] = lifecycle_fragment["lifecycle"]

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

    new_status = lifecycle_fragment["lifecycle"].get("status", "<unset>")
    print(f"flow-goal-record.sh: updated {target} lifecycle.status to '{new_status}'", file=sys.stderr)
PYTHON
