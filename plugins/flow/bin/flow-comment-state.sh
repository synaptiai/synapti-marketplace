#!/usr/bin/env bash
# [flow] Build the System One state for one pull-request review comment: the
# comment, and the code at the place it refers to now. /flow:address runs it
# after `gh pr checkout`. The code is read from the working tree, and only when
# the file there is the file at HEAD, so the commit named in CHECKED is the
# code that was read.
#
# Usage: flow-comment-state.sh --comment <file> --out <file>
#
#   --comment  one review comment as `gh api repos/<repo>/pulls/comments/<id>`
#              prints it
#   --out      where the state is written, as JSON:
#              {"comment": {"body", "path", "line", "original_line",
#                           "diff_hunk", "outdated"},
#               "code_now": {"path", "head", "start", "end", "text",
#                            "original_lines_present"}}
#
# The place: the comment's `line` when GitHub still gives one. When it does not
# (the comment is outdated), the one line of the file now that equals the last
# line of `diff_hunk` that is not removed and not blank. `code_now` is that line
# with at most 40 lines either side, and `original_lines_present` is true.
#
# When that line is nowhere in the file now (a fix changed the lines the
# comment was written on, which is what makes GitHub mark it outdated), the
# comment is still located: at its `original_line`, or the last line of the
# file when the file is now shorter than that. `code_now` is the code now
# around that line number, `original_lines_present` is false, and the lines
# as they were are in `comment.diff_hunk`. An anchor found more than once, a
# hunk with no line to anchor on, or no `original_line` is not located.
# The reviewer's login is not included.
# A comment on a removed line (`side` LEFT) is not located: its `line` counts
# lines of the base file, not of the file now. Nor is a comment on the whole
# file (`subject_type` file), which has no line.
#
# Output (stdout), KEY=value lines:
#   LOCATION=ok, CHECKED=<path>:<start>-<end>@<commit, 12 characters>   exit 0
#   LOCATION=skipped, REASON=<reason>                                  exit 1
# Reasons: comment-unreadable (not a comment with a path), file-missing (the
# path is absolute, has a `..` or a control character, passes through a
# symlink, or is not a regular file now), location-not-found (the line is past
# the end of the file; the anchor is found more than once; the hunk has no
# line to anchor on; or the anchor is found nowhere and the comment has no
# `original_line`, or the file is empty),
# removed-line (the comment is on the base side), file-comment (the comment is
# on the whole file), uncommitted (the file has changes that are not committed,
# or is not in HEAD), no-repository. Exit 2 on a usage error. Nothing outside
# the repository is read, and nothing is sent.

set -uo pipefail
unset CDPATH

WINDOW=40

usage() { printf 'usage: flow-comment-state.sh --comment <file> --out <file>\n' >&2; exit 2; }
skip() { printf 'LOCATION=skipped\nREASON=%s\n' "$1"; exit 1; }

COMMENT=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --comment) [ $# -ge 2 ] || usage; COMMENT="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$COMMENT" ] && [ -n "$OUT" ] || usage
[ -f "$COMMENT" ] || skip comment-unreadable
command -v jq >/dev/null 2>&1 || skip comment-unreadable

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || skip no-repository
[ -n "$TOP" ] && [ -d "$TOP" ] || skip no-repository

# The path is checked inside jq, so no value from the comment reaches a shell
# test before it is known to be a plain relative path.
jq -e '(.path | type == "string" and length > 0 and length <= 4096)
       and ((.line == null) or (.line | type == "number" and . >= 1 and . == floor))' \
  "$COMMENT" >/dev/null 2>&1 || skip comment-unreadable
jq -e '.path | (startswith("/") | not)
               and (split("/") | all(. != ".." and . != "." and . != ""))
               and (explode | all(. >= 32 and . != 127 and . != 133 and . != 8232 and . != 8233))' \
  "$COMMENT" >/dev/null 2>&1 || skip file-missing
REL=$(jq -r '.path' "$COMMENT")

# Every component, from the repository top down, is a real directory and the
# last a regular file: a symlink anywhere on the way could point outside the
# repository, and its target would be sent to the provider.
CUR="$TOP"
REST="$REL"
while :; do
  PART="${REST%%/*}"
  CUR="$CUR/$PART"
  [ -L "$CUR" ] && skip file-missing
  if [ "$PART" = "$REST" ]; then
    [ -f "$CUR" ] || skip file-missing
    break
  fi
  [ -d "$CUR" ] || skip file-missing
  REST="${REST#*/}"
done
FILE="$CUR"

# The file read must be the file at HEAD, which CHECKED names. The path is
# taken literally: a `*` or `[` in it is not a pattern.
git -C "$TOP" cat-file -e "HEAD:$REL" 2>/dev/null || skip uncommitted
git -C "$TOP" --literal-pathspecs diff --quiet --no-ext-diff --no-textconv HEAD -- "$REL" 2>/dev/null \
  || skip uncommitted

LINES=$(awk 'END { print NR }' "$FILE") || skip file-missing
jq -e '(.subject_type // "line") != "file"' "$COMMENT" >/dev/null 2>&1 || skip file-comment
jq -e '(.side // "RIGHT") != "LEFT"' "$COMMENT" >/dev/null 2>&1 || skip removed-line
LINE=$(jq -r '.line // empty' "$COMMENT")
OUTDATED=false
PRESENT=true
if [ -n "$LINE" ]; then
  [ "$LINE" -le "$LINES" ] 2>/dev/null || skip location-not-found
else
  OUTDATED=true
  # The last line of the hunk that is not removed: context (" ") or added
  # ("+"), with its one-character prefix taken off, ignoring the "@@" header,
  # "\ No newline" notes and blank lines, which would match anywhere.
  ANCHOR=$(jq -r '(.diff_hunk // "") | split("\n")
                  | map(select(startswith(" ") or startswith("+")) | .[1:])
                  | map(select(test("\\S"))) | last // empty' "$COMMENT")
  [ -n "$ANCHOR" ] || skip location-not-found
  # Compared through the environment: awk -v would read backslashes in the
  # anchor as escapes. Compared as strings: awk compares two values that look
  # like numbers as numbers, so an anchor `1` would equal a line `1.0`.
  FOUND=$(FLOW_ANCHOR="$ANCHOR" awk 'BEGIN { a = ENVIRON["FLOW_ANCHOR"] "" }
    ($0 "") == a { n++; at = NR } END { print n + 0, at + 0 }' "$FILE")
  case "${FOUND%% *}" in
    1) LINE="${FOUND#* }" ;;
    0)
      # The lines are gone: look at the code now where they were. The
      # number is checked inside jq, and printed as plain digits (jq keeps
      # a literal such as 10.0 as written).
      PRESENT=false
      LINE=$(jq -r '.original_line | if (type == "number" and . >= 1 and . == floor
                    and . < 1000000000) then floor | tostring else empty end' "$COMMENT")
      case "$LINE" in ''|*[!0-9]*) skip location-not-found ;; esac
      [ "$LINES" -ge 1 ] || skip location-not-found
      [ "$LINE" -le "$LINES" ] || LINE=$LINES
      ;;
    *) skip location-not-found ;;
  esac
fi

START=$((LINE - WINDOW)); [ "$START" -ge 1 ] || START=1
END=$((LINE + WINDOW)); [ "$END" -le "$LINES" ] || END=$LINES
HEAD=$(git -C "$TOP" rev-parse HEAD 2>/dev/null) || skip no-repository
SHORT=$(git -C "$TOP" rev-parse --short=12 HEAD 2>/dev/null) || skip no-repository

TEXT_FILE=$(mktemp "${TMPDIR:-/tmp}/flow-comment-text.XXXXXX") || skip no-repository
awk -v s="$START" -v e="$END" 'NR >= s && NR <= e { print } NR > e { exit }' "$FILE" > "$TEXT_FILE"
jq -n --slurpfile c "$COMMENT" --rawfile text "$TEXT_FILE" --arg head "$HEAD" \
  --argjson start "$START" --argjson end "$END" --argjson outdated "$OUTDATED" \
  --argjson present "$PRESENT" '
  $c[0] as $c
  | {comment: {body: ($c.body // ""), path: $c.path, line: $c.line,
               original_line: $c.original_line, diff_hunk: ($c.diff_hunk // ""),
               outdated: $outdated},
     code_now: {path: $c.path, head: $head, start: $start, end: $end, text: $text,
                original_lines_present: $present}}' \
  > "$OUT" 2>/dev/null
RC=$?
rm -f "$TEXT_FILE"
[ "$RC" -eq 0 ] || skip comment-unreadable

printf 'LOCATION=ok\n'
printf 'CHECKED=%s:%s-%s@%s\n' "$REL" "$START" "$END" "$SHORT"
exit 0
