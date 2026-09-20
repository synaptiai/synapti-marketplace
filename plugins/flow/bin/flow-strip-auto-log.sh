#!/usr/bin/env bash
# flow-strip-auto-log.sh — remove auto-log breadcrumbs from tracked journals.
#
# Before issue #244 the PostToolUse hooks appended `<!-- auto-log: ... -->`
# lines to `.decisions/issue-N.md`, which is tracked — so the breadcrumbs were
# committed. The hooks now write a gitignored trail instead, but every journal
# written before that still carries them. This is a HYGIENE upgrade, like
# bin/flow-migrate-settings.sh: a repository that never runs it keeps working,
# it just keeps carrying the residue in its diffs.
#
# /flow:setup offers it on re-run. It is safe to run by hand at any time.
#
# Usage:
#   flow-strip-auto-log.sh [--apply] [<journal-dir>]
#
#   default journal dir: resolved through bin/cascade-resolve.sh
#                       (`.journal.dir`, default `.decisions`)
#   without --apply: dry-run — prints `STRIP_AUTO_LOG=...` describing what would
#                    change (or `STRIP_AUTO_LOG=none`) and writes nothing.
#   with --apply:    rewrites each affected journal atomically.
#
# Output (dry-run):
#   STRIP_AUTO_LOG=none
#   STRIP_AUTO_LOG=<n> files, <m> lines
#   STRIP_AUTO_LOG_FILE=<path> removed=<k>      (one per affected journal)
#   STRIP_AUTO_LOG_WARN=<path> unclosed fence — left partially stripped
#   STRIP_AUTO_LOG_MODE=dry-run (re-run with --apply to write)
# Output (--apply):
#   STRIP_AUTO_LOG_APPLIED=1 files=<n> removed=<m>
#
# Exit:
#   0 — reported, or applied, or nothing to do
#   2 — infrastructure error (journal dir is a symlink, a journal is a symlink,
#       atomic write failed)
#
# What counts as a breadcrumb: a line beginning `<!-- auto-log: ` — the
# emitter's own prefix, deliberately NOT a timestamp regex, because one
# historical emitter line carried no HH:MM at all. Lines inside a
# fenced code block are never touched: a journal may legitimately quote the
# entry format (the schema reference documents it that way), and stripping a
# quoted example would corrupt a document. Migration is idempotent: a second
# run reports `none` and leaves every file byte-identical.
#
# Removal takes the marker AND the single blank line it was preceded by. The
# emitter wrote "\n<!-- ... -->\n", so a run of entries collapses to the single
# separator that separated the real content around it, rather than leaving
# doubled blank lines behind. Nothing else is normalized: a run of two or more
# blanks elsewhere, and any leading or trailing blank, are left exactly as they
# were — this script was asked to remove breadcrumbs, not to restyle the file.

set -uo pipefail

# Fold a value onto one line before printing. Every value below is read from a
# TRACKED journal, which a fork pull request can change; a value holding a real
# newline would forge a second STRIP_AUTO_LOG_* line for whoever reads this.
one_line() {
  printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' '
}

APPLY=0
JOURNAL_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1; shift ;;
    -h|--help) sed -n '2,61p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)        echo "flow-strip-auto-log.sh: unknown flag: $1" >&2; exit 2 ;;
    *)         JOURNAL_DIR="$1"; shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$JOURNAL_DIR" ]; then
  JOURNAL_DIR=".decisions"
  if [ -x "$SCRIPT_DIR/cascade-resolve.sh" ]; then
    JOURNAL_DIR=$("$SCRIPT_DIR/cascade-resolve.sh" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
    [ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
  fi
fi

# A journal dir that is not there is nothing to do, not an error — a repository
# that never initialized flow should see `none`, not a failure.
if [ ! -d "$JOURNAL_DIR" ]; then
  echo "STRIP_AUTO_LOG=none"
  exit 0
fi
if [ -L "$JOURNAL_DIR" ]; then
  echo "flow-strip-auto-log.sh: refusing — journal dir $JOURNAL_DIR is a symlink" >&2
  exit 2
fi

# Containment. The journal dir is read from .claude/settings.flow.json, a
# TRACKED file that a fork pull request controls — the same threat
# cascade-resolve.sh's header describes — and this script REWRITES what it finds
# there. A `..` segment is how such a value escapes the repository, and the
# rewrite would never appear in `git status` or the PR diff, which is exactly
# what the documented review step ("review the deletions before committing")
# cannot see. A relative path with no `..` cannot leave the working directory,
# and a symlinked directory is already refused above, so only two shapes need
# rejecting.
case "/$JOURNAL_DIR/" in
  */../*)
    echo "flow-strip-auto-log.sh: refusing — journal dir '$JOURNAL_DIR' contains a '..' segment; it would rewrite files outside the repository" >&2
    exit 2 ;;
esac
case "$JOURNAL_DIR" in
  /*)
    # An absolute journal dir inside the repository is legitimate; outside it,
    # the rewrite is invisible to review.
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
    if [ -n "$REPO_ROOT" ]; then
      REPO_ROOT=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)
      RESOLVED=$(cd "$JOURNAL_DIR" 2>/dev/null && pwd -P)
      case "$RESOLVED" in
        "$REPO_ROOT"/*) ;;
        *)
          echo "flow-strip-auto-log.sh: refusing — absolute journal dir '$JOURNAL_DIR' resolves to '$RESOLVED', outside the repository at '$REPO_ROOT'" >&2
          exit 2 ;;
      esac
    fi ;;
esac

# The strip. `removed` counts marker lines only — the blank lines that go with
# them are a consequence, and the number a reader cares about is how many
# breadcrumbs were deleted.
STRIP_AWK='
BEGIN {
  # Initialised explicitly. An uninitialised awk variable has BOTH the numeric
  # value 0 and the string value "", and `print removed` prints the string — so
  # a file with no markers wrote an empty count file, not "0". The old
  # `|| echo 0` at the call site hid that; this makes the count honest instead.
  removed = 0
  pending_blank = 0
  in_fence = 0
}
function fence_delim(s) {
  # Returns the fence character this line opens/closes with, or "" — the same
  # rule as _fence_delim() in bin/_journal_atomic.py and journal-read-section.sh.
  # Anchored: an INLINE ```span``` mid-line must not toggle anything.
  if (s ~ /^[[:space:]]*```/) return "`"
  if (s ~ /^[[:space:]]*~~~/) return "~"
  return ""
}
{
  line = $0
  d = fence_delim(line)
  if (in_fence) {
    # A fence closes only on the character that OPENED it. Testing merely
    # whether that character appears somewhere on the line closed a ~~~ block
    # on a line like "```sample~", after which a quoted breadcrumb inside the
    # block was deleted — the one thing this script promises not to do. The
    # reader and the writer both test the delimiter, so this must too.
    if (d == fence_char) { in_fence = 0 }
    flush_blank()
    print line
    next
  }
  if (d != "") {
    in_fence = 1
    fence_char = d
    flush_blank()
    print line
    next
  }
  if (line ~ /^<!-- auto-log: /) {
    # Take exactly ONE blank with the marker — the one the emitter wrote before
    # it — and leave any others where they were. A flag rather than a count
    # here collapsed a run of blanks to a single one, which rewrote whitespace
    # the operator never asked to change.
    if (pending_blank > 0) pending_blank--
    flush_blank()
    removed++
    next
  }
  if (line == "") { pending_blank++; next }
  flush_blank()
  print line
}
# A count, and emitted even before any content: leading and trailing blanks are
# part of the file, not something this script was asked to normalize.
function flush_blank(   k) {
  for (k = 0; k < pending_blank; k++) print ""
  pending_blank = 0
}
END {
  flush_blank()
  if (cnt != "") print removed > cnt
  # Report whether the file ENDED inside an unbalanced fence. Markers after the
  # imbalance are preserved, which is the safe direction — but a silent partial
  # strip reads identically to "no churn here", so it has to be said out loud.
  if (unbal != "") print (in_fence ? "1" : "0") > unbal
}
'

# awk is the transform. Its absence used to be invisible: the count file stayed
# empty, REMOVED read as 0, and the script reported `none` for a repository full
# of breadcrumbs — so /flow:setup told the operator there was nothing to strip.
command -v awk >/dev/null 2>&1 || {
  echo "flow-strip-auto-log.sh: awk is required but not installed" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/flow-strip-auto-log.XXXXXX" 2>/dev/null) || {
  echo "flow-strip-auto-log.sh: mktemp -d failed" >&2; exit 2; }
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && command rm -rf -- "$WORK"; }
trap cleanup EXIT INT TERM

# The transform lives in a file so the locked apply path can hand the same
# program to awk rather than duplicating it.
printf '%s\n' "$STRIP_AWK" > "$WORK/strip.awk"

FILES=0
LINES=0
WARNED=0
REPORT=""

for JOURNAL in "$JOURNAL_DIR"/*.md; do
  [ -f "$JOURNAL" ] || continue
  if [ -L "$JOURNAL" ]; then
    echo "flow-strip-auto-log.sh: refusing — $JOURNAL is a symlink" >&2
    exit 2
  fi

  OUT="$WORK/out.$$"
  CNT="$WORK/cnt.$$"
  UNBAL="$WORK/unbal.$$"
  : > "$CNT"
  : > "$UNBAL"
  if ! awk -v cnt="$CNT" -v unbal="$UNBAL" -f "$WORK/strip.awk" "$JOURNAL" \
       > "$OUT" 2>"$WORK/awkerr.$$"; then
    echo "flow-strip-auto-log.sh: awk failed on $JOURNAL — $(head -1 "$WORK/awkerr.$$" 2>/dev/null)" >&2
    exit 2
  fi
  REMOVED=$(cat "$CNT" 2>/dev/null)
  # An empty count file means awk wrote nothing, which is NOT the same as
  # "nothing to remove": the old `|| echo 0` made a failed scan report a clean
  # repository. Refuse instead.
  case "$REMOVED" in
    ''|*[!0-9]*)
      echo "flow-strip-auto-log.sh: awk produced no count for $JOURNAL — refusing to report a clean result" >&2
      exit 2 ;;
  esac

  # Checked before the early-continue: a file whose only markers sit after an
  # unbalanced fence strips nothing, and reporting `none` for it would tell the
  # operator the repository is clean while the residue is visible in the diff.
  if [ "$(cat "$UNBAL" 2>/dev/null)" = "1" ]; then
    WARNED=$((WARNED + 1))
    REPORT="${REPORT}STRIP_AUTO_LOG_WARN=$(one_line "$JOURNAL") unclosed fence — left partially stripped
"
  fi

  if [ "$REMOVED" -eq 0 ]; then
    continue
  fi

  FILES=$((FILES + 1))
  LINES=$((LINES + REMOVED))
  REPORT="${REPORT}STRIP_AUTO_LOG_FILE=$(one_line "$JOURNAL") removed=$REMOVED
"

  if [ "$APPLY" -eq 1 ]; then
    # The scan above is advisory. The write is a LOCKED read-modify-write: a
    # journal writer landing between an unlocked read and an unlocked publish
    # would have its entry silently reverted — the exact loss this whole change
    # exists to stop — so the read, the transform and the publish all happen
    # under the same <target>.lock the rest of the plugin uses. flock(1) does
    # not exist on macOS, so the primitive is reached through the module.
    #
    # The reported count comes from the scan, so if a writer appends between the
    # scan and this call the count is short by that one entry; the file itself
    # is transformed from the locked read.
    if ! python3 - "$SCRIPT_DIR" "$JOURNAL" "$WORK/strip.awk" <<'PYTHON'
import os, subprocess, sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[1])

from _journal_atomic import (  # noqa: E402
    JournalAtomicError, _atomic_write, _read_with_no_follow, acquire_lock,
)

target, prog = sys.argv[2], sys.argv[3]
lock_fd = acquire_lock(target + ".lock")
try:
    content = _read_with_no_follow(target)
    r = subprocess.run(["awk", "-f", prog], input=content,
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("flow-strip-auto-log.sh: awk failed under the lock: %s"
              % r.stderr.strip(), file=sys.stderr)
        sys.exit(2)
    if r.stdout != content:
        _atomic_write(target, r.stdout)
except JournalAtomicError as e:
    print("flow-strip-auto-log.sh: %s" % e, file=sys.stderr)
    sys.exit(2)
finally:
    try:
        os.close(lock_fd)
    except OSError:
        pass
PYTHON
    then
      printf '%s' "$REPORT"
      echo "flow-strip-auto-log.sh: locked write failed for $JOURNAL — anything already rewritten is listed above" >&2
      exit 2
    fi
  fi
done

# `none` means nothing to do. A journal left partially stripped because of an
# unbalanced fence is NOT nothing to do — it is work that could not be completed
# — so it must not be reported as clean.
if [ "$FILES" -eq 0 ] && [ "$WARNED" -eq 0 ]; then
  echo "STRIP_AUTO_LOG=none"
  exit 0
fi

if [ "$APPLY" -eq 1 ]; then
  printf '%s' "$REPORT"
  echo "STRIP_AUTO_LOG_APPLIED=1 files=$FILES removed=$LINES warned=$WARNED"
  exit 0
fi

printf '%s' "$REPORT"
echo "STRIP_AUTO_LOG=$FILES files, $LINES lines"
echo "STRIP_AUTO_LOG_WARNED=$WARNED journals left partially stripped"
echo "STRIP_AUTO_LOG_MODE=dry-run (re-run with --apply to write)"
exit 0
