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
#     ignored), Total for the whole diff, or (root) (also root, / or .) for
#     the files at the top of the repository. A row whose area matches no
#     changed file is a mismatch too. Rows of other tables are not read.
#     Renames count as git diff --stat counts them: one file, under its new
#     path.
#   - Each "<N> file(s) changed" phrase, against the number of changed files.
#   - Each path in backticks that looks like a file (a / in it and a dot in
#     its last segment; directories are not checked), with an optional :line
#     or :line-line, against the tree the change produces. It must be there,
#     at the repository root or below a directory (a package-relative path),
#     or be a file the change deletes or renames away; a line it names must
#     exist. A placeholder or pattern (< > { } * $ ~ or a space), a URL, an
#     absolute path, host:port/..., and anything that names a git commit
#     (origin/main, a branch) are skipped.
#
# Usage:
#   flow-description-check.sh --body <file> --base <ref> [--head <ref>]
#   flow-description-check.sh --body <file> --staged
# --base/--head compare <base>...<head> (head defaults to HEAD), as a pull
# request does. A bare branch name for --base is read as origin/<name> when
# that ref exists: a local default branch is usually behind. --staged
# compares the index with HEAD, for a commit message.
#
# Output (stdout, one KEY=value per line):
#   STATE=ok|stale|unavailable
#   REASON=<why>                              (unavailable only)
#   COMPARED=<base>...<head>|staged           the range the counts come from
#   CHECKED_ROWS=<n>  CHECKED_COUNTS=<n>  CHECKED_PATHS=<n>
#   MISMATCH=<claim>|<stated>|<actual>        one per row or count that differs
#   STALE_PATH=<path>|<why>                   one per path the tree does not have
# STATE=stale when any MISMATCH or STALE_PATH line is printed.
#
# Exits 0 in every reported state; 2 on a usage error.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

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

# The base. /flow:start branches from origin/<default> and never updates the
# local branch of that name, so a bare branch name is read as its
# remote-tracking ref when there is one: the local one is usually behind, and
# comparing against it would count every commit merged upstream since.
if [ "$STAGED" = 0 ]; then
  case "$BASE" in
    origin/*) ;;
    *) git rev-parse --verify -q "origin/$BASE^{commit}" >/dev/null 2>&1 && BASE="origin/$BASE" ;;
  esac
  git rev-parse --verify -q "$BASE^{commit}" >/dev/null || unavailable "no commit '$BASE'"
  git rev-parse --verify -q "$HEAD_REF^{commit}" >/dev/null || unavailable "no commit '$HEAD_REF'"
fi

# The change: "added<TAB>deleted<TAB>path" per file (binary files count 0),
# with renames detected as git diff --stat detects them: a rename is one file,
# under its new path, and its old path is added to the deleted ones.
NUMSTAT=""
DELETED=""
if [ "$STAGED" = 1 ]; then
  git diff --cached --quiet --exit-code >/dev/null 2>&1; [ $? -le 1 ] || unavailable "git diff --cached failed"
  set -- --cached
  TREE_REF=""
  TREE_FILES=$(git ls-files 2>/dev/null)
else
  set -- "$BASE...$HEAD_REF"
  TREE_REF="$HEAD_REF"
  TREE_FILES=$(git ls-tree -r --name-only "$TREE_REF" 2>/dev/null) || unavailable "cannot list the tree of '$HEAD_REF'"
fi
while IFS= read -r -d '' rec; do
  a=${rec%%$'\t'*}; rest=${rec#*$'\t'}; d=${rest%%$'\t'*}; path=${rest#*$'\t'}
  if [ -z "$path" ]; then
    IFS= read -r -d '' old || break
    IFS= read -r -d '' path || break
    DELETED="$DELETED$old"$'\n'
  fi
  [ "$a" = - ] && a=0
  [ "$d" = - ] && d=0
  NUMSTAT="$NUMSTAT$a"$'\t'"$d"$'\t'"$path"$'\n'
done < <(git diff --numstat -z -M "$@" 2>/dev/null)
DELETED="$DELETED$(git diff --name-only -M --diff-filter=D "$@" 2>/dev/null)"
TOTAL_FILES=$(printf '%s' "$NUMSTAT" | grep -c .)

# _sum <prefix|Total|(root)> — "files added deleted" over the changed files
# under it. (root) is the files at the top of the repository.
_sum() {
  printf '%s' "$NUMSTAT" | awk -F'\t' -v p="$1" '
    NF < 3 { next }
    p == "Total" || (p == "(root)" && index($3, "/") == 0) || $3 == p || index($3, p "/") == 1 { f++; a += $1; d += $2 }
    END { printf "%d %d %d\n", f, a, d }'
}

STALE=0
ROWS=0; COUNTS=0; PATHS=0
FOUND=()
_found() { FOUND+=("$1"); STALE=1; }
# _shape "<files> <added> <deleted>" — the numbers as a reader writes them.
_shape() { set -- $1; printf '%s files, +%s, -%s' "$1" "$2" "$3"; }

# Files-changed rows. Only a table row of four cells whose second is a whole
# number and whose third and fourth are +N and -N. [|] is a literal pipe in
# every ERE dialect; \| is not defined by POSIX.
while IFS= read -r line; do
  area=$(printf '%s' "$line" | sed -E 's/^[|][[:space:]]*([^|]*[^|[:space:]])[[:space:]]*[|].*/\1/; s/`//g; s/[*][*]//g; s:/+$::')
  nums=$(printf '%s' "$line" | sed -E 's/^[|][^|]*[|][[:space:]]*([0-9]+)[[:space:]]*[|][[:space:]]*[+]([0-9]+)[[:space:]]*[|][[:space:]]*-([0-9]+)[[:space:]]*[|].*/\1 \2 \3/')
  case "$area" in
    [Tt]otal) area="Total" ;;
    root|'(root)'|/|.) area="(root)" ;;
  esac
  ROWS=$((ROWS + 1))
  actual=$(_sum "$area")
  if [ "${actual%% *}" = 0 ]; then
    _found "MISMATCH=files-changed row $area|$(_shape "$nums")|no changed file is under $area"
  elif [ "$actual" != "$nums" ]; then
    _found "MISMATCH=files-changed row $area|$(_shape "$nums")|$(_shape "$actual")"
  fi
done < <(grep -E '^[|][^|]+[|][[:space:]]*[0-9]+[[:space:]]*[|][[:space:]]*[+][0-9]+[[:space:]]*[|][[:space:]]*-[0-9]+[[:space:]]*[|][[:space:]]*$' "$BODY")

# "<N> file(s) changed" phrases.
while IFS= read -r n; do
  COUNTS=$((COUNTS + 1))
  if [ "$n" != "$TOTAL_FILES" ]; then
    _found "MISMATCH=$n files changed|$n|$TOTAL_FILES"
  fi
done < <(grep -oE '(^|[^0-9A-Za-z])[0-9]+ files? changed' "$BODY" | grep -oE '[0-9]+')

# Paths in backticks. Only a token that looks like a file (its last segment
# has a dot) is checked: origin/main,
# feature/issue-1-x, owner/repo and application/json are not paths, and a
# token that names a git commit is never one. A path is found at the
# repository root or, as a description scoped to one package writes it,
# below a directory (references/x.md for plugins/flow/references/x.md).
# _resolve <path> — the file in the tree, or nothing. Here-strings, not pipes:
# under pipefail a reader that stops at its first match would fail the writer.
_resolve() {
  grep -qxF -- "$1" <<<"$TREE_FILES" && { printf '%s' "$1"; return; }
  awk -v p="/$1" 'length($0) > length(p) && substr($0, length($0) - length(p) + 1) == p { print; exit }' <<<"$TREE_FILES"
}
_deleted() {
  awk -v p="$1" 'NF && ($0 == p || (length($0) > length(p) && substr($0, length($0) - length(p)) == "/" p)) { f = 1; exit } END { exit !f }' <<<"$DELETED"
}
_lines() {
  if [ -n "$TREE_REF" ]; then git show "$TREE_REF:$1" 2>/dev/null | awk 'END { print NR }'
  else git show ":$1" 2>/dev/null | awk 'END { print NR }'; fi
}
while IFS= read -r tok; do
  case "$tok" in
    *[\<\>\{\}\*\$\~\ ]*|/*|http*|*://*) continue ;;
    */*) ;;
    *) continue ;;
  esac
  path="${tok%%:*}"
  ref=""
  if [ "$path" != "$tok" ]; then
    ref="${tok#*:}"
    # Only :<line> or :<line>-<line> follows a path; host:port/x is not one.
    case "$ref" in ''|*[!0-9-]*) continue ;; esac
  fi
  case "$path" in *[!A-Za-z0-9._/-]*) continue ;; esac
  git rev-parse -q --verify "$path^{commit}" >/dev/null 2>&1 && continue
  # A directory is not checked: one named in prose is as often a runtime or
  # build location git never tracks (.venv/, dist/) as a source directory.
  case "$path" in */) continue ;; esac
  case "${path##*/}" in *.*) ;; *) continue ;; esac
  PATHS=$((PATHS + 1))
  full=$(_resolve "$path")
  if [ -z "$full" ]; then
    _deleted "$path" && continue
    _found "STALE_PATH=$tok|not in the tree the change produces"
    continue
  fi
  if [ -n "$ref" ]; then
    last="${ref##*-}"
    n=$(_lines "$full")
    if [ -n "$last" ] && [ "$last" -gt "$n" ] 2>/dev/null; then
      _found "STALE_PATH=$tok|$full has $n lines"
    fi
  fi
done < <(grep -oE '`[^`]+`' "$BODY" | sed 's/^`//; s/`$//' | sort -u)

if [ "$STALE" = 1 ]; then echo "STATE=stale"; else echo "STATE=ok"; fi
if [ "$STAGED" = 1 ]; then echo "COMPARED=staged"; else echo "COMPARED=$BASE...$HEAD_REF"; fi
echo "CHECKED_ROWS=$ROWS"
echo "CHECKED_COUNTS=$COUNTS"
echo "CHECKED_PATHS=$PATHS"
for f in ${FOUND[@]+"${FOUND[@]}"}; do printf '%s\n' "$f"; done
exit 0
