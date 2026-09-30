#!/usr/bin/env bash
# [flow] Print the decision-journal directory, the one every flow reader and
# writer of the journal uses.
#
# journal.dir is read from the settings cascade (bin/cascade-resolve.sh);
# the default is .decisions.
#
# A value set in the repository's own settings must resolve inside the
# repository: .claude/settings.flow.json is committed, and a pull request can
# commit .claude/settings.flow.local.json too, so either lets a repository
# choose where the journal is written. A value that does not is refused with a
# warning on stderr naming the value and the file (a value the check cannot
# be run on, python3 missing, is not used either, with a warning saying it
# could not be checked), and the repository's
# settings are then left out of the lookup: the journal.dir from the user's
# settings is printed, or .decisions when they set none. That is
# cascade-resolve.sh --no-repo-settings, which also refuses to answer when this
# script itself lies inside the repository being checked (the plugin's own
# checkout); .decisions is printed then.
# Inside is ensure_inside_repo() in bin/_repo_dir.py, the rule every flow
# writer applies below the repository (ensure_repo_dir), taken from the
# repository top (the nearest directory at or above the working directory with
# a .git entry): the path, followed one name at a time as the kernel follows
# it, ends inside the repository, and no name on the way inside it is a
# symlink, even one pointing inside the repository, or anything but a
# directory. An absolute value may name the repository through a symlink
# above it, such as macOS's /var for /private/var: what counts is where the
# path ends.
#
# A value set in the user's settings — $FLOW_USER_SETTINGS, or
# ~/.claude/settings.flow.json — is printed as configured, wherever it points.
# A repository settings file that is that same file (the working directory is
# HOME, in a home kept in git) counts as the user's. A writer still refuses a
# symlink on the way to a user value below the repository, except for an
# absolute value with no `..` component (--user-owned), which is written as
# configured.
#
# Usage: journal-dir.sh [--user-owned]
#
# --user-owned: print the directory and exit 0 only when it is the user's own
# choice — absolute, with no `..` component, and not from a repository file
# (a repository value that was refused and left the user's value in effect
# counts). Otherwise print nothing and exit 1. Writers and the auto-log hooks
# skip the repository symlink check for such a directory: the user decided
# where it points, and it may run through a symlink the user made. A relative
# user value keeps the rule, and so does one with a `..` component, whose
# landing place a symlink the repository commits can decide.
#
# Output: the directory, one line, on stdout. Warnings from the settings
# cascade and a refusal on stderr.
#
# Exits:
#   0 — printed the directory (a refused value prints the user's journal.dir,
#       or .decisions)
#   1 — usage error, or with --user-owned a directory that is not the user's
#       own; nothing printed

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# The current directory is the repository being checked; a ./yaml.py there
# must not shadow PyYAML when the module is imported.
export PYTHONSAFEPATH=1

DEFAULT=".decisions"

USER_OWNED_MODE=0
case "${1:-}" in
  "") ;;
  --user-owned) USER_OWNED_MODE=1 ;;
  -h|--help)
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  *)
    echo "journal-dir.sh: usage: journal-dir.sh [--user-owned]" >&2
    exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Everything echoed back comes from a settings file a repository controls.
one_line() {
  printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' '
}

DIR=$("$SCRIPT_DIR/cascade-resolve.sh" --default "$DEFAULT" '.journal.dir // empty')
[ -n "$DIR" ] || DIR="$DEFAULT"

# Which file the value came from. cascade-resolve.sh reads the local file, then
# the project file, then the user's, and the first that holds a value wins; a
# file it cannot parse is skipped, and jq fails on it here too. When a
# repository file holds a value but the cascade printed something else (it
# refuses a value carrying a control character and prints the default), the
# printed value is not the repository's and is not checked.
# Nor is a file that is the user's own settings file: in a home kept in git,
# run from HOME, .claude/settings.flow.json IS ~/.claude/settings.flow.json,
# and its value is the user's choice, not the repository's. Which file that is
# comes from cascade-resolve.sh, the one place that decides it.
SOURCE=""
FROM_REPO=0
if command -v jq >/dev/null 2>&1; then
  for f in .claude/settings.flow.local.json .claude/settings.flow.json; do
    [ -f "$f" ] || continue
    v=$(jq -r '.journal.dir // empty' "$f" 2>/dev/null) || continue
    if [ -n "$v" ] && [ "$v" != null ]; then
      USER_FILE=$("$SCRIPT_DIR/cascade-resolve.sh" --user-settings-path 2>/dev/null) || USER_FILE=""
      if [ -n "$USER_FILE" ] && [ "$f" -ef "$USER_FILE" ]; then
        break
      fi
      [ "$v" = "$DIR" ] && SOURCE="$f"
      break
    fi
  done
fi

if [ -n "$SOURCE" ]; then
  # The check answers 0 (inside), 12 (refused) or 13 (could not be done);
  # anything else is a check that did not run. The module it imports needs no
  # PyYAML.
  RC=0
  REASON=$(python3 - "$SCRIPT_DIR" "$DIR" 2>&1 <<'PYTHON'
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[1])

from _repo_dir import JournalAtomicError, RepoDirRefused, ensure_inside_repo  # noqa: E402

try:
    ensure_inside_repo(sys.argv[2])
except JournalAtomicError as e:
    # "docs is a symlink": the reason set where the rule refused, never the
    # message cut at a "; ", which a name can hold.
    print(e.reason)
    sys.exit(12 if isinstance(e, RepoDirRefused) else 13)
PYTHON
  ) || RC=$?
  if [ "$RC" -ne 0 ]; then
    REASON=$(printf '%s' "$REASON" | head -1)
    # A Windows python3 ends the line in \r\n, which $(...) keeps the \r of.
    REASON=${REASON%$'\r'}
    # The repository's value is ignored, not replaced by the default: what the
    # cascade says without the repository's two files stays in effect, as for
    # any setting a repository may not choose. Its warnings were printed by the
    # lookup above, and the files it ignores are the ones refused here.
    FALLBACK=$("$SCRIPT_DIR/cascade-resolve.sh" --no-repo-settings --default "$DEFAULT" '.journal.dir // empty' 2>/dev/null) || FALLBACK=""
    [ -n "$FALLBACK" ] || FALLBACK="$DEFAULT"
    if [ "$RC" -eq 12 ]; then
      printf "journal-dir.sh: WARN: refusing journal.dir '%s' from %s: %s; using %s\n" \
        "$(one_line "$DIR")" "$SOURCE" "$(one_line "$REASON")" "$(one_line "$FALLBACK")" >&2
    else
      # Not a refusal: the check could not be done (python3 missing or
      # failing). A repository's value that cannot be checked is not used.
      [ "$RC" -eq 13 ] || REASON="the check did not run (python3 exited $RC)"
      printf "journal-dir.sh: WARN: cannot check journal.dir '%s' from %s (%s); using %s\n" \
        "$(one_line "$DIR")" "$SOURCE" "$(one_line "$REASON")" "$(one_line "$FALLBACK")" >&2
    fi
    DIR="$FALLBACK"
  else
    FROM_REPO=1
  fi
fi

if [ "$USER_OWNED_MODE" -eq 1 ]; then
  # A `..` component is not the user's choice outright: read without the
  # links, <repo>/sub/../j is <repo>/j, but the kernel resolves sub first, so
  # a symlink the repository commits decides where it lands. Such a value
  # keeps the rule, which walks the `..` as written.
  case "/$DIR/" in
    */../*) exit 1 ;;
  esac
  case "$DIR" in
    /*) [ "$FROM_REPO" -eq 0 ] && { printf '%s\n' "$DIR"; exit 0; } ;;
  esac
  exit 1
fi

# A relative directory whose name starts with `-` is printed as ./<name>: the
# same directory, which no command reading it (flow-mkdir.sh, ls, find, cat)
# can take for an option.
case "$DIR" in
  -*) DIR="./$DIR" ;;
esac
printf '%s\n' "$DIR"
