#!/usr/bin/env bash
# flow-migrate-settings.sh — upgrade a flow settings file to the current schema.
#
# Applies deprecated-key migrations to a `.claude/settings.flow.json`-style file
# so a project that committed an older-schema settings file can be brought
# forward. The runtime already honors deprecated keys read-only (via
# cascade-resolve), so this is a HYGIENE upgrade, not a correctness fix —
# nothing breaks if it is never run.
#
# Migrations applied (extend the jq filter below as new deprecations land):
#   - flow.goals.requireGoalForStart  ->  flow.goals.goalCreation
#       true -> "always", false -> "off", any other value -> "auto".
#       If goalCreation is already set, it WINS and the legacy key is dropped.
#
# Usage:
#   flow-migrate-settings.sh [--apply] [<settings-file>]
#
#   default file: .claude/settings.flow.json
#   without --apply: dry-run — prints `MIGRATE=...` lines describing pending
#                    changes (or `MIGRATE=none`) and exits 0 without writing.
#   with --apply:    rewrites the file atomically (tmpfile + validate + mv),
#                    preserving every other key.
#
# Exit:
#   0  success (dry-run reported, or --apply wrote / had nothing to do)
#   2  infrastructure error (jq missing, file missing, symlink rejected,
#      malformed JSON, atomic write failed)
#
# Safety: refuses to operate through a symlinked settings file or .claude dir
# (matches bin/journal-record.sh / bin/flow-active-goal.sh). The --apply write
# is atomic and validates the produced JSON before replacing the original, so a
# jq failure can never leave a truncated settings file.

set -uo pipefail

APPLY=0
SETTINGS=".claude/settings.flow.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,33p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) echo "flow-migrate-settings.sh: unknown flag: $1" >&2; exit 2 ;;
    *) SETTINGS="$1"; shift ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "flow-migrate-settings.sh: jq required but not installed" >&2
  exit 2
fi

if [ ! -f "$SETTINGS" ]; then
  echo "flow-migrate-settings.sh: settings file not found: $SETTINGS" >&2
  exit 2
fi

# Symlink defense — refuse to read/write through a symlinked file or .claude dir.
SETTINGS_DIR=$(dirname "$SETTINGS")
if [ -L "$SETTINGS" ]; then
  echo "flow-migrate-settings.sh: refusing — $SETTINGS is a symlink" >&2
  exit 2
fi
if [ -L "$SETTINGS_DIR" ]; then
  echo "flow-migrate-settings.sh: refusing — $SETTINGS_DIR is a symlink" >&2
  exit 2
fi

# The migration filter. Pure, idempotent: a file with no deprecated keys passes
# through unchanged. New deprecations extend this single expression.
MIGRATE_FILTER='
  if (.flow.goals | type) == "object" and (.flow.goals | has("requireGoalForStart")) then
    .flow.goals.goalCreation = (
      .flow.goals.goalCreation //
      (if .flow.goals.requireGoalForStart == true then "always"
       elif .flow.goals.requireGoalForStart == false then "off"
       else "auto" end)
    )
    | .flow.goals = (.flow.goals | del(.requireGoalForStart))
  else . end
'

ORIGINAL=$(cat "$SETTINGS")
if ! MIGRATED=$(printf '%s' "$ORIGINAL" | jq "$MIGRATE_FILTER" 2>/dev/null); then
  echo "flow-migrate-settings.sh: $SETTINGS is not valid JSON — refusing to migrate" >&2
  exit 2
fi

# Compare canonically (sorted keys) so formatting differences don't masquerade
# as changes.
ORIG_CANON=$(printf '%s' "$ORIGINAL" | jq -S . 2>/dev/null)
MIG_CANON=$(printf '%s' "$MIGRATED" | jq -S . 2>/dev/null)

if [ "$ORIG_CANON" = "$MIG_CANON" ]; then
  echo "MIGRATE=none"
  exit 0
fi

# Describe the concrete change (requireGoalForStart -> goalCreation).
OLD_VAL=$(printf '%s' "$ORIGINAL" | jq -r '.flow.goals.requireGoalForStart // "absent"' 2>/dev/null)
NEW_VAL=$(printf '%s' "$MIGRATED" | jq -r '.flow.goals.goalCreation // "absent"' 2>/dev/null)
echo "MIGRATE=requireGoalForStart->goalCreation"
echo "MIGRATE_FROM=requireGoalForStart=$OLD_VAL"
echo "MIGRATE_TO=goalCreation=$NEW_VAL"

if [ "$APPLY" != "1" ]; then
  echo "MIGRATE_MODE=dry-run (re-run with --apply to write)"
  exit 0
fi

# Atomic write: tmpfile in the SAME directory as the target (so the final mv is
# a same-filesystem atomic rename, not a cross-FS copy+unlink), validate, then
# mv. flock guards the read-modify-write window against concurrent writers.
TMP=$(mktemp "${SETTINGS_DIR}/.flow-migrate-settings.XXXXXX" 2>/dev/null) || {
  echo "flow-migrate-settings.sh: mktemp failed in $SETTINGS_DIR" >&2; exit 2; }
LOCK="${SETTINGS}.lock"
trap 'rm -f "$TMP"' EXIT INT TERM
(
  flock -x 9 || { echo "flow-migrate-settings.sh: failed to acquire $LOCK" >&2; exit 2; }
  # Re-read under the lock and re-apply so a concurrent writer's change isn't lost.
  if ! jq "$MIGRATE_FILTER" "$SETTINGS" > "$TMP" 2>/dev/null; then
    echo "flow-migrate-settings.sh: jq migration failed under lock" >&2; exit 2
  fi
  if [ ! -s "$TMP" ] || ! jq empty "$TMP" >/dev/null 2>&1; then
    echo "flow-migrate-settings.sh: produced empty/invalid JSON — $SETTINGS unchanged" >&2; exit 2
  fi
  if ! mv "$TMP" "$SETTINGS"; then
    echo "flow-migrate-settings.sh: mv failed — $SETTINGS unchanged" >&2; exit 2
  fi
) 9>"$LOCK"
RC=$?
trap - EXIT INT TERM
rm -f "$TMP"
[ "$RC" -ne 0 ] && exit 2

echo "MIGRATE_APPLIED=1"
exit 0
