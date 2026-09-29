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
# warning on stderr naming the value and the file, and .decisions is printed.
# Inside is ensure_inside_repo() in bin/_journal_atomic.py, the rule every flow
# writer applies below the repository (ensure_repo_dir), taken from the current
# directory, the repository's working-tree top where flow runs: the path ends
# under the current directory's physical path, and each component of it that
# exists is a directory and not a symlink, even one pointing inside the
# repository. A `..` is walked as written. An absolute value names the
# repository by its physical path (`pwd -P`); one spelled through a symlink
# above the repository, such as macOS's /var for /private/var, is refused.
#
# A value set in the user's settings — $FLOW_USER_SETTINGS, or
# ~/.claude/settings.flow.json — is printed as configured, wherever it points.
# A writer still refuses a symlink on the way to it below the repository.
#
# Usage: journal-dir.sh
#
# Output: the directory, one line, on stdout. Warnings from the settings
# cascade and a refusal on stderr.
#
# Exits:
#   0 — printed the directory (a refused value prints .decisions)
#   1 — usage error; nothing printed

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# The current directory is the repository being checked; a ./yaml.py there
# must not shadow PyYAML when the module is imported.
export PYTHONSAFEPATH=1

DEFAULT=".decisions"

case "${1:-}" in
  "") ;;
  -h|--help)
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  *)
    echo "journal-dir.sh: usage: journal-dir.sh (no arguments)" >&2
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
SOURCE=""
if command -v jq >/dev/null 2>&1; then
  for f in .claude/settings.flow.local.json .claude/settings.flow.json; do
    [ -f "$f" ] || continue
    v=$(jq -r '.journal.dir // empty' "$f" 2>/dev/null) || continue
    if [ -n "$v" ] && [ "$v" != null ]; then
      [ "$v" = "$DIR" ] && SOURCE="$f"
      break
    fi
  done
fi

if [ -n "$SOURCE" ]; then
  REASON=$(python3 - "$SCRIPT_DIR" "$DIR" 2>&1 <<'PYTHON'
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[1])

from _journal_atomic import JournalAtomicError, ensure_inside_repo  # noqa: E402

try:
    ensure_inside_repo(sys.argv[2])
except JournalAtomicError as e:
    # "refusing — docs is a symlink; nothing is written under it" -> the reason.
    msg = str(e).split("; ", 1)[0]
    prefix = "refusing — "
    print(msg[len(prefix):] if msg.startswith(prefix) else msg)
    sys.exit(1)
PYTHON
  ); RC=$?
  if [ "$RC" -ne 0 ]; then
    # A check that could not run (python3 or PyYAML missing) does not let the
    # repository's value through either.
    [ -n "$REASON" ] || REASON="it could not be checked"
    REASON=$(printf '%s' "$REASON" | head -1)
    printf "journal-dir.sh: WARN: refusing journal.dir '%s' from %s: %s; using %s\n" \
      "$(one_line "$DIR")" "$SOURCE" "$(one_line "$REASON")" "$DEFAULT" >&2
    DIR="$DEFAULT"
  fi
fi

printf '%s\n' "$DIR"
