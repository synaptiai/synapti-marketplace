#!/usr/bin/env bash
# [flow] Append to, or replace a section of, a decision-journal BODY.
#
# The journal has one file serving two roles: an append-only body (decision
# entries, captured specifications, design notes) and a rewritten YAML
# frontmatter manifest. bin/journal-record.sh owns the manifest and takes a
# flock to do it. Before this helper existed, every body writer appended with a
# bare `echo >>` or `cat >>`, or rewrote the whole file with the Write tool,
# and took no lock at all — so journal-record.sh's read→rename could publish
# over bytes appended in that window, silently. Body writes now take the SAME
# lock, on the same `<target>.lock` path, so the two serialize.
#
# Usage:
#   journal-append.sh --file <path>    [--replace-heading <H>] (--text <T> | -)
#   journal-append.sh --issue <N>      [--replace-heading <H>] (--text <T> | -)
#
#   --file <path>          explicit target (the auto-log hooks use this)
#   --issue <N>            target <journal.dir>/issue-<N>.md, journal.dir
#                          resolved through bin/cascade-resolve.sh
#   --replace-heading <H>  replace H's section (to the next `## ` heading), or
#                          append it when absent, instead of appending text
#   --text <T>             the entry text
#   -                      read the entry text from stdin
#
# Exits:
#   0 — written
#   1 — missing argument, both or neither target selector, unknown flag
#   2 — infrastructure error (symlink refused, unwritable, PyYAML missing on
#       the --replace-heading path, lock failure)
#
# Security: the target, and the lockfile beside it, are opened with O_NOFOLLOW,
# so a pre-staged symlink cannot redirect a write outside the journal. The
# payload is NOT sanitized — it is journal content and is written verbatim.
# Only values echoed back in a diagnostic go through one_line().

set -euo pipefail

# Python 3.11+ honors this; the module re-runs the same filter as a fallback.
# After `gh pr checkout` of a hostile fork, an attacker-shipped ./yaml.py at the
# repo root would otherwise shadow the real PyYAML on the module import.
export PYTHONSAFEPATH=1

# Collapse a value to one line before printing it. Everything echoed here may
# come from a tracked settings file or a caller-supplied path, and a value
# holding a real newline would forge a second diagnostic line.
one_line() {
  printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' '
}

ISSUE=""
TARGET_FILE=""
REPLACE_HEADING=""
TEXT=""
TEXT_GIVEN=0
FROM_STDIN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)           ISSUE="${2:-}"; shift 2 ;;
    --file)            TARGET_FILE="${2:-}"; shift 2 ;;
    --replace-heading) REPLACE_HEADING="${2:-}"; shift 2 ;;
    --text)            TEXT="${2:-}"; TEXT_GIVEN=1; shift 2 ;;
    -)                 FROM_STDIN=1; shift ;;
    -h|--help)         sed -n '2,56p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "journal-append.sh: unknown argument: $(one_line "$1")" >&2; exit 1 ;;
  esac
done

if [ -n "$ISSUE" ] && [ -n "$TARGET_FILE" ]; then
  echo "journal-append.sh: --issue and --file are mutually exclusive" >&2
  exit 1
fi
if [ -z "$ISSUE" ] && [ -z "$TARGET_FILE" ]; then
  echo "journal-append.sh: one of --issue <N> or --file <path> is required" >&2
  exit 1
fi
if [ "$TEXT_GIVEN" -eq 1 ] && [ "$FROM_STDIN" -eq 1 ]; then
  echo "journal-append.sh: --text and - are mutually exclusive" >&2
  exit 1
fi
if [ "$TEXT_GIVEN" -eq 0 ] && [ "$FROM_STDIN" -eq 0 ]; then
  echo "journal-append.sh: one of --text <T> or - (stdin) is required" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve the target path. --issue goes through the settings cascade exactly as
# journal-record.sh does, so the two helpers always agree on which file they
# are serializing against.
if [ -n "$ISSUE" ]; then
  case "$ISSUE" in
    ''|*[!0-9]*)
      echo "journal-append.sh: --issue must be a positive integer (got: $(one_line "$ISSUE"))" >&2
      exit 1
      ;;
  esac
  JOURNAL_DIR=$("$SCRIPT_DIR/cascade-resolve.sh" --default ".decisions" '.journal.dir // empty')
  [ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
  TARGET="$JOURNAL_DIR/issue-$ISSUE.md"
else
  TARGET="$TARGET_FILE"
fi

if [ "$FROM_STDIN" -eq 1 ]; then
  TEXT=$(cat)
fi

# mkdir -p the target's directory so a caller need not pre-create it (the
# auto-log hooks rely on this for .decisions/auto-log/).
TARGET_DIR=$(dirname "$TARGET")
[ -d "$TARGET_DIR" ] || mkdir -p "$TARGET_DIR" 2>/dev/null || {
  echo "journal-append.sh: cannot create $(one_line "$TARGET_DIR")" >&2
  exit 2
}

# Lockfile beside the target — the same path journal-record.sh builds, so a
# manifest write and a body append on one journal contend on one lock.
LOCKFILE="$TARGET.lock"

python3 - "$SCRIPT_DIR" "$TARGET" "$LOCKFILE" "$REPLACE_HEADING" "$TEXT" <<'PYTHON'
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

from _journal_atomic import (  # noqa: E402
    JournalAtomicError,
    append_body,
    replace_section,
)

target = sys.argv[2]
lockfile = sys.argv[3]
heading = sys.argv[4]
text = sys.argv[5]

try:
    if heading:
        replace_section(target, lockfile, heading, text)
    else:
        append_body(target, lockfile, text)
except JournalAtomicError as e:
    print("journal-append.sh: %s" % e, file=sys.stderr)
    sys.exit(e.exit_code)
PYTHON
