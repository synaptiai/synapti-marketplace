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

# The strip. `removed` counts marker lines only — the blank lines that go with
# them are a consequence, and the number a reader cares about is how many
# breadcrumbs were deleted.
STRIP_AWK='
function fence_line(s,   m) {
  # A fence opens/closes only when the first non-space run is three or more
  # backticks or tildes. Anchored on purpose: an INLINE ```span``` mid-line
  # must not toggle the state, or the tracker desynchronizes and starts
  # stripping breadcrumbs out of real fenced blocks.
  return (s ~ /^[[:space:]]*(```|~~~)/)
}
function fence_char_of(s) {
  return (s ~ /^[[:space:]]*`/) ? "`" : "~"
}
{
  line = $0
  if (in_fence) {
    if (fence_line(line) && index(line, fence_char) > 0) { in_fence = 0 }
    flush_blank()
    print line
    next
  }
  if (fence_line(line)) {
    in_fence = 1
    fence_char = fence_char_of(line)
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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/flow-strip-auto-log.XXXXXX" 2>/dev/null) || {
  echo "flow-strip-auto-log.sh: mktemp -d failed" >&2; exit 2; }
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && command rm -rf -- "$WORK"; }
trap cleanup EXIT INT TERM

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
  awk -v cnt="$CNT" -v unbal="$UNBAL" "$STRIP_AWK" "$JOURNAL" > "$OUT" 2>/dev/null
  REMOVED=$(cat "$CNT" 2>/dev/null || echo 0)
  [ -n "$REMOVED" ] || REMOVED=0

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
    # Same-filesystem temp beside the target so the mv is an atomic rename, and
    # a symlink check immediately before it — `mv` replaces the name via
    # rename(2) rather than writing through the link, but a link swapped in
    # since the check above would still have been read into $OUT.
    TMP=$(mktemp "${JOURNAL}.XXXXXX" 2>/dev/null) || {
      echo "flow-strip-auto-log.sh: mktemp failed beside $JOURNAL" >&2; exit 2; }
    if [ -L "$JOURNAL" ]; then
      command rm -f -- "$TMP"
      echo "flow-strip-auto-log.sh: refusing — $JOURNAL became a symlink" >&2
      exit 2
    fi
    if ! cat "$OUT" > "$TMP" 2>/dev/null; then
      command rm -f -- "$TMP"
      echo "flow-strip-auto-log.sh: write failed for $JOURNAL" >&2
      exit 2
    fi
    if ! mv "$TMP" "$JOURNAL" 2>/dev/null; then
      command rm -f -- "$TMP"
      echo "flow-strip-auto-log.sh: mv failed — $JOURNAL unchanged" >&2
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
