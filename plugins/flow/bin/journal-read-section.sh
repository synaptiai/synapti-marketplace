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
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

FILE=""
HEADING=""

while [ $# -gt 0 ]; do
  case "$1" in
    # The count is checked before consuming. `shift 2` with one argument left
    # returns non-zero but leaves $1 in place, and this file has no `set -e`, so
    # `while [ $# -gt 0 ]` never advanced and a dangling flag spun at 100% CPU
    # forever (verified: still running after 3s). One line each turns a hang
    # into the documented exit 1.
    --file)
      [ $# -ge 2 ] || { echo "journal-read-section.sh: --file needs a value" >&2; exit 1; }
      FILE="$2"; shift 2 ;;
    --heading)
      [ $# -ge 2 ] || { echo "journal-read-section.sh: --heading needs a value" >&2; exit 1; }
      HEADING="$2"; shift 2 ;;
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
function fence_delim(s,   t, c, n) {
  # "<char><length>" for a fence line, or "". Anchored, so an INLINE ```span```
  # mid-line toggles nothing.
  t = s
  sub(/^[[:space:]]+/, "", t)
  if (t == "") return ""
  c = substr(t, 1, 1)
  if (c != "`" && c != "~") return ""
  n = 0
  while (substr(t, n + 1, 1) == c) n++
  if (n < 3) return ""
  return c n
}
function closes_fence(d, opened) {
  # Same character, run at least as long. This replaced an `index(line, char)`
  # test, which closed the fence whenever the character appeared ANYWHERE on
  # the line — so "```sample~" ended a ~~~ block, and the reader and the writer
  # disagreed about where the section ended.
  if (d == "" || opened == "") return 0
  return (substr(d, 1, 1) == substr(opened, 1, 1)) && ((substr(d, 2) + 0) >= (substr(opened, 2) + 0))
}
{
  line = $0
  d = fence_delim(line)
  if (in_fence) {
    if (closes_fence(d, fence_open)) in_fence = 0
    if (printing) print line
    next
  }
  if (d != "") {
    in_fence = 1
    fence_open = d
    if (printing) print line
    next
  }
  # The FIRST match is the section, matching the writer: _splice_section
  # replaces only the first, so a reader that returned both copies would report
  # a section the writer will not touch. A duplicate heading reaches the
  # `^## ` rule below with `printing` set, and stops there.
  if (!found && line == heading) { found = 1; printing = 1; print line; next }
  if (printing && line ~ /^## /) { printing = 0; next }
  if (printing) print line
}
' "$FILE"
exit 0
