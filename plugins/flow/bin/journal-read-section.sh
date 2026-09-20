#!/usr/bin/env bash
# [flow] Print one section of a decision journal, fence-aware.
#
# A `## Specification` line inside a fenced code block is not a section heading.
# The schema reference quotes the specification shape that way, and a reader
# that matched it would end the real section early — reporting elements missing
# that are present, re-prompting the user for a risk map the journal already
# holds, and then rewriting the section from its own truncated view. The writer
# (bin/_journal_atomic.py, `_splice_section`) tracks fences, so the reader must
# apply the same rule or the two disagree about where a section ends. This is
# that rule, in one place.
#
# Usage:
#   journal-read-section.sh --file <path> --heading <H>
#
#   Prints the heading line and everything up to the next `## ` heading, or
#   nothing when the heading is absent. Exit 0 either way — an absent section is
#   a legitimate answer, not an error.
#
# Exits:
#   0 — printed (possibly nothing)
#   1 — missing argument or unknown flag
#   2 — the file cannot be read

set -uo pipefail

FILE=""
HEADING=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file)    FILE="${2:-}"; shift 2 ;;
    --heading) HEADING="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "journal-read-section.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$FILE" ] || { echo "journal-read-section.sh: --file is required" >&2; exit 1; }
[ -n "$HEADING" ] || { echo "journal-read-section.sh: --heading is required" >&2; exit 1; }
[ -r "$FILE" ] || { echo "journal-read-section.sh: cannot read $FILE" >&2; exit 2; }

# Same fence predicate as bin/flow-strip-auto-log.sh and the writer's
# `_fence_delim`: the first non-space run must be three or more backticks or
# tildes, so an inline ```span``` mid-line does not toggle anything, and a fence
# closes only on the character that opened it.
awk -v heading="$HEADING" '
function fence_line(s) { return (s ~ /^[[:space:]]*(```|~~~)/) }
function fence_char_of(s) { return (s ~ /^[[:space:]]*`/) ? "`" : "~" }
{
  line = $0
  if (in_fence) {
    if (fence_line(line) && index(line, fence_char) > 0) in_fence = 0
    if (printing) print line
    next
  }
  if (fence_line(line)) {
    in_fence = 1
    fence_char = fence_char_of(line)
    if (printing) print line
    next
  }
  if (line == heading) { printing = 1; print line; next }
  if (printing && line ~ /^## /) { printing = 0; next }
  if (printing) print line
}
' "$FILE"
exit 0
