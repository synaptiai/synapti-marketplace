#!/usr/bin/env bash
# [flow] Check the claims in a description that a script can check, against
# the change it describes, before the description is published.
#
# A pull request body written once and never rewritten describes the first
# version of the change: reviewers on #250, #251 and #307 filed findings such
# as "the PR body described an older head" and "102 lookups; there are 103".
# This checks the part of that a script can decide. The claims only a reader
# can judge (what the change does) go through holdout-validation, which the
# callers run on the same text.
#
# Checked:
#   - Each row of a files-changed table, `| <area> | <files> | +<added> | -<deleted> |`,
#     against the diff: <area> is a path prefix (backticks and a trailing /
#     ignored), or Total for the whole diff. A row whose area matches no
#     changed file is a mismatch too. Rows of other tables are not read.
#   - Each "<N> file(s) changed" phrase, against the number of changed files.
#   - Each path in backticks that has a / in it (with an optional :line or
#     :line-line), against the tree the change produces: the path must exist
#     there, or be a file the change deletes, and a line it names must exist.
#     A token holding < > { } * $ ~ or a space is a placeholder or a pattern,
#     not a path, and is skipped; so is one starting with / or http.
#
# Usage:
#   flow-description-check.sh --body <file> --base <ref> [--head <ref>]
#   flow-description-check.sh --body <file> --staged
# --base/--head compare <base>...<head> (head defaults to HEAD), as a pull
# request does. --staged compares the index with HEAD, for a commit message.
#
# Output (stdout, one KEY=value per line):
#   STATE=ok|stale|unavailable
#   REASON=<why>                              (unavailable only)
#   CHECKED_ROWS=<n>  CHECKED_COUNTS=<n>  CHECKED_PATHS=<n>
#   MISMATCH=<claim>|<stated>|<actual>        one per row or count that differs
#   STALE_PATH=<path>|<why>                   one per path the tree does not have
# STATE=stale when any MISMATCH or STALE_PATH line is printed.
#
# Exits 0 in every reported state; 2 on a usage error.

set -uo pipefail

PROG="flow-description-check.sh"
usage() { echo "usage: $PROG --body <file> (--base <ref> [--head <ref>] | --staged)" >&2; }

BODY=""; BASE=""; HEAD_REF="HEAD"; STAGED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --body) BODY="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --base) BASE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --head) HEAD_REF="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --staged) STAGED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PROG: unknown argument" >&2; usage; exit 2 ;;
  esac
done
{ [ "$STAGED" = 1 ] && [ -z "$BASE" ]; } || { [ "$STAGED" = 0 ] && [ -n "$BASE" ]; } || { usage; exit 2; }

unavailable() { printf 'STATE=unavailable\nREASON=%s\n' "$1"; exit 0; }
[ -n "$BODY" ] && [ -f "$BODY" ] && [ -r "$BODY" ] || unavailable "cannot read the description '$BODY'"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || unavailable "not inside a git work tree"

# The change: "added<TAB>deleted<TAB>path" per file (binary files count 0),
# and the deleted paths. Renames are shown under their new path.
if [ "$STAGED" = 1 ]; then
  NUMSTAT=$(git diff --cached --numstat --no-renames 2>/dev/null) || unavailable "git diff --cached failed"
  DELETED=$(git diff --cached --name-only --diff-filter=D --no-renames 2>/dev/null)
  TREE_REF=""
else
  git rev-parse --verify -q "$BASE^{commit}" >/dev/null || unavailable "no commit '$BASE'"
  git rev-parse --verify -q "$HEAD_REF^{commit}" >/dev/null || unavailable "no commit '$HEAD_REF'"
  NUMSTAT=$(git diff --numstat --no-renames "$BASE...$HEAD_REF" 2>/dev/null) || unavailable "git diff $BASE...$HEAD_REF failed"
  DELETED=$(git diff --name-only --diff-filter=D --no-renames "$BASE...$HEAD_REF" 2>/dev/null)
  TREE_REF="$HEAD_REF"
fi
NUMSTAT=$(printf '%s\n' "$NUMSTAT" | awk -F'\t' 'NF >= 3 { a = ($1 == "-") ? 0 : $1; d = ($2 == "-") ? 0 : $2; print a "\t" d "\t" $3 }')
TOTAL_FILES=$(printf '%s\n' "$NUMSTAT" | grep -c .)

# _sum <prefix|Total> — "files added deleted" over the changed files under it.
_sum() {
  printf '%s\n' "$NUMSTAT" | awk -F'\t' -v p="$1" '
    NF < 3 { next }
    p == "Total" || $3 == p || index($3, p "/") == 1 { f++; a += $1; d += $2 }
    END { printf "%d %d %d\n", f, a, d }'
}

STALE=0
ROWS=0; COUNTS=0; PATHS=0
FOUND=()
_found() { FOUND+=("$1"); STALE=1; }
# _shape "<files> <added> <deleted>" — the numbers as a reader writes them.
_shape() { set -- $1; printf '%s files, +%s, -%s' "$1" "$2" "$3"; }

# Files-changed rows. Only a table row of four cells whose second is a whole
# number and whose third and fourth are +N and -N.
while IFS= read -r line; do
  area=$(printf '%s' "$line" | sed -E 's/^\|[[:space:]]*([^|]*[^|[:space:]])[[:space:]]*\|.*/\1/; s/`//g; s/\*\*//g; s:/+$::')
  nums=$(printf '%s' "$line" | sed -E 's/^\|[^|]*\|[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*\+([0-9]+)[[:space:]]*\|[[:space:]]*-([0-9]+)[[:space:]]*\|.*/\1 \2 \3/')
  case "$area" in [Tt]otal) area="Total" ;; esac
  ROWS=$((ROWS + 1))
  actual=$(_sum "$area")
  if [ "${actual%% *}" = 0 ]; then
    _found "MISMATCH=files-changed row $area|$(_shape "$nums")|no changed file is under $area"
  elif [ "$actual" != "$nums" ]; then
    _found "MISMATCH=files-changed row $area|$(_shape "$nums")|$(_shape "$actual")"
  fi
done < <(grep -E '^\|[^|]+\|[[:space:]]*[0-9]+[[:space:]]*\|[[:space:]]*\+[0-9]+[[:space:]]*\|[[:space:]]*-[0-9]+[[:space:]]*\|[[:space:]]*$' "$BODY")

# "<N> file(s) changed" phrases.
while IFS= read -r n; do
  COUNTS=$((COUNTS + 1))
  if [ "$n" != "$TOTAL_FILES" ]; then
    _found "MISMATCH=$n files changed|$n|$TOTAL_FILES"
  fi
done < <(grep -oE '(^|[^0-9A-Za-z])[0-9]+ files? changed' "$BODY" | grep -oE '[0-9]+')

# Paths in backticks.
_exists() {
  if [ -n "$TREE_REF" ]; then git cat-file -e "$TREE_REF:$1" 2>/dev/null
  else git cat-file -e ":$1" 2>/dev/null || git cat-file -e "HEAD:$1" 2>/dev/null; fi
}
_lines() {
  if [ -n "$TREE_REF" ]; then git show "$TREE_REF:$1" 2>/dev/null | wc -l | tr -d ' '
  else git show ":$1" 2>/dev/null | wc -l | tr -d ' '; fi
}
while IFS= read -r tok; do
  case "$tok" in
    *[\<\>\{\}\*\$\~\ ]*|/*|http*) continue ;;
    */*) ;;
    *) continue ;;
  esac
  path="${tok%%:*}"
  ref=""
  [ "$path" != "$tok" ] && ref="${tok#*:}"
  case "$path" in *[!A-Za-z0-9._/-]*) continue ;; esac
  PATHS=$((PATHS + 1))
  if ! _exists "$path"; then
    if printf '%s\n' "$DELETED" | grep -qxF -- "$path"; then continue; fi
    _found "STALE_PATH=$tok|not in the tree the change produces"
    continue
  fi
  case "$ref" in
    '') ;;
    *[!0-9-]*) ;;
    *)
      last="${ref##*-}"
      if [ -n "$last" ] && [ "$last" -gt "$(_lines "$path")" ] 2>/dev/null; then
        _found "STALE_PATH=$tok|$path has $(_lines "$path") lines"
      fi ;;
  esac
done < <(grep -oE '`[^`]+`' "$BODY" | sed 's/^`//; s/`$//' | sort -u)

if [ "$STALE" = 1 ]; then echo "STATE=stale"; else echo "STATE=ok"; fi
echo "CHECKED_ROWS=$ROWS"
echo "CHECKED_COUNTS=$COUNTS"
echo "CHECKED_PATHS=$PATHS"
for f in ${FOUND[@]+"${FOUND[@]}"}; do printf '%s\n' "$f"; done
exit 0
