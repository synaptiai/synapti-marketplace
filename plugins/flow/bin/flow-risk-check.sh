#!/usr/bin/env bash
# [flow] Say whether a change touches a risky area, before it is planned.
#
# A file is risky when it matches one of the repository's declared risk areas
# (design.riskAreas), or when it is a fix hotspot: at least
# design.hotspotFixCommits of the repository's last 200 non-merge commits are
# fixes that touched it. A change that touches a risky file gets the design step of
# /flow:start Phase 1 before it is planned (references/design-step.md); every
# other change goes on as before.
#
# Callers: commands/start.md Phase 1 (RISK_CHECK_BLOCK). The session writes
# the files it expects the change to modify, one repository-relative path per
# line, to a file and passes it with --files-from; the paths are read as data,
# never run.
#
# Usage:
#   flow-risk-check.sh --files-from <file>
#
# Settings (read through bin/cascade-resolve.sh, the standard cascade):
#   design.riskAreas          shell patterns matched against each path, where
#                             * also matches /: "src/billing/*" covers every
#                             file below src/billing/; a trailing / ("lib/"), a
#                             leading / and ** are read as in CODEOWNERS.
#                             Default [].
#   design.hotspotFixCommits  fix commits that make a file a hotspot; 0 turns
#                             the hotspot signal off. Default 3.
# A fix commit is one whose subject starts with fix, hotfix, bugfix or revert,
# in any letter case, followed by "(", ":", "!", a space or the end: the
# conventional-commit types and git's own "Revert" subjects.
#
# Output (stdout, one KEY=value per line, in this order):
#   STATE=ok|unavailable
#   REASON=<why>                      (unavailable only)
#   RISK=high|normal|unknown          unknown when STATE=unavailable
#   FILES_CHECKED=<n>
#   HOTSPOT_WINDOW=<commits read>     the commits the hotspot count looked at
#   HISTORY=origin/HEAD|HEAD          where that history was read
#   SHALLOW=0|1                       1 in a shallow clone: the window may be
#                                     shorter than 200, so a hotspot can be missed
#   UNTRACKED=<n>                     listed paths git does not track: new
#                                     files, or paths that name nothing
#   RISK_FILE=<path>|<reason>[; <reason>]   one line per risky file
# A setting of the wrong type is named on stderr with a WARN and its default
# is used.
#
# Exits 0 in every reported state; 2 on a usage error.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

PROG="flow-risk-check.sh"
WINDOW=200
HERE=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

usage() { echo "usage: $PROG --files-from <file>" >&2; }

FILES_FROM=""
FILES_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --files-from) FILES_FROM="${2:-}"; FILES_SET=1; shift 2 || { usage; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PROG: unknown argument" >&2; usage; exit 2 ;;
  esac
done
[ "$FILES_SET" = 1 ] || { usage; exit 2; }

unavailable() {
  printf 'STATE=unavailable\nREASON=%s\nRISK=unknown\nFILES_CHECKED=0\nHOTSPOT_WINDOW=0\n' "$1"
  exit 0
}

[ -n "$FILES_FROM" ] && [ -f "$FILES_FROM" ] && [ -r "$FILES_FROM" ] \
  || unavailable "cannot read the files list '$FILES_FROM'"
command -v jq >/dev/null 2>&1 || unavailable "jq is not installed"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || unavailable "not inside a git work tree"

# The paths as git names them: relative to the repository's top. A list an
# agent writes may hold absolute paths, markdown bullets, backticks, a
# trailing :line, or paths relative to the directory it works in; each would
# match nothing and read as "not risky".
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
TOP_P=$(cd -P -- "$TOP" 2>/dev/null && pwd -P)
PREFIX=$(git rev-parse --show-prefix 2>/dev/null)
FILES=()
while IFS= read -r f || [ -n "$f" ]; do
  f="${f%$'\r'}"
  f="${f#"${f%%[![:space:]]*}"}"
  f="${f%"${f##*[![:space:]]}"}"
  case "$f" in '- '*|'* '*|'+ '*) f="${f#??}" ;; esac
  f="${f#\`}"; f="${f%\`}"
  case "$f" in *:[0-9]*) case "${f##*:}" in *[!0-9-]*) ;; *) f="${f%:*}" ;; esac ;; esac
  case "$f" in
    "$TOP"/*) f="${f#"$TOP"/}" ;;
    "$TOP_P"/*) f="${f#"$TOP_P"/}" ;;
    /*) ;;
    *) f="${f#./}"
       if [ -n "$PREFIX" ] && [ ! -e "$TOP/$f" ]; then f="$PREFIX$f"; fi ;;
  esac
  [ -n "$f" ] && FILES+=("$f")
done < "$FILES_FROM"
[ "${#FILES[@]}" -gt 0 ] || unavailable "the files list is empty; list the files the change will modify"
TRACKED=$(git -c core.quotePath=false ls-files --full-name -- "$TOP" 2>/dev/null)
UNTRACKED=0
for f in "${FILES[@]}"; do
  grep -qxF -- "$f" <<<"$TRACKED" || UNTRACKED=$((UNTRACKED + 1))
done

# Settings. A value of the wrong type is not a reason to skip the check.
RESOLVE="$HERE/cascade-resolve.sh"
AREAS_JSON=$("$RESOLVE" --compact --default '[]' '.design.riskAreas' 2>/dev/null)
if ! printf '%s' "$AREAS_JSON" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
  echo "WARN: design.riskAreas is not a list of strings; no declared risk areas are used" >&2
  AREAS_JSON='[]'
fi
# Each pattern is matched as a shell pattern where * also matches /. The
# CODEOWNERS and gitignore spellings mean the same here: a leading / anchors
# at the top (as every pattern already is), a trailing / is the directory's
# files, and ** is *.
AREAS=()
while IFS= read -r a; do
  [ -n "$a" ] && AREAS+=("$a")
done < <(printf '%s' "$AREAS_JSON" | jq -r '.[]')
_pattern() {
  local p="${1#/}"
  case "$p" in */) p="$p*" ;; esac
  p="${p//\*\*\//}"
  p="${p//\*\*/*}"
  printf '%s' "$p"
}
THRESHOLD=$("$RESOLVE" --default 3 '.design.hotspotFixCommits' 2>/dev/null)
case "$THRESHOLD" in
  ''|*[!0-9]*)
    echo "WARN: design.hotspotFixCommits is not a whole number; 3 is used" >&2
    THRESHOLD=3 ;;
esac

# Fix commits per file over the window, as "count<TAB>path" lines. History
# is read from the default branch the change will merge into (origin/HEAD)
# when the clone has it, not from whichever branch is checked out. A commit
# with no parent (the root commit, or the boundary of a shallow clone) is
# left out: its file list is the whole tree, not what it changed. Names are
# printed unquoted, so a path such as src/café.sh matches.
HOT=""
COMMITS_READ=0
HISTORY=HEAD
git rev-parse --verify -q refs/remotes/origin/HEAD >/dev/null 2>&1 && HISTORY=origin/HEAD
SHALLOW=0
[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ] && SHALLOW=1
if [ "$THRESHOLD" -gt 0 ]; then
  LOG=$(git -c core.quotePath=false log --no-merges -n "$WINDOW" --format='%x1e%P%x1f%s' --name-only "$HISTORY" 2>/dev/null) \
    || unavailable "git log failed"
  COMMITS_READ=$(printf '%s\n' "$LOG" | grep -c $'^\x1e')
  HOT=$(printf '%s\n' "$LOG" | awk '
    /^\036/ {
      h = substr($0, 2)
      i = index(h, "\037")
      parents = substr(h, 1, i - 1)
      s = tolower(substr(h, i + 1))
      fix = (parents != "" && s ~ /^(fix|hotfix|bugfix|revert)([(:! ]|$)/)
      next
    }
    NF && fix { n[$0]++ }
    END { for (p in n) printf "%d\t%s\n", n[p], p }')
fi

RISKY=()
for f in "${FILES[@]}"; do
  reasons=""
  for a in ${AREAS[@]+"${AREAS[@]}"}; do
    ap=$(_pattern "$a")
    # shellcheck disable=SC2254
    case "$f" in
      $ap) reasons="${reasons:+$reasons; }risk area $a" ;;
    esac
  done
  if [ "$THRESHOLD" -gt 0 ]; then
    # The path reaches awk through the environment: -v would turn a
    # backslash in it into an escape.
    c=$(P="$f" awk -F'\t' '$2 == ENVIRON["P"] { print $1; exit }' <<<"$HOT")
    if [ -n "$c" ] && [ "$c" -ge "$THRESHOLD" ]; then
      reasons="${reasons:+$reasons; }$c fix commits among the last $COMMITS_READ commits"
    fi
  fi
  [ -n "$reasons" ] && RISKY+=("$f|$reasons")
done

echo "STATE=ok"
if [ "${#RISKY[@]}" -gt 0 ]; then echo "RISK=high"; else echo "RISK=normal"; fi
echo "FILES_CHECKED=${#FILES[@]}"
echo "HOTSPOT_WINDOW=$COMMITS_READ"
echo "HISTORY=$HISTORY"
echo "SHALLOW=$SHALLOW"
echo "UNTRACKED=$UNTRACKED"
for r in ${RISKY[@]+"${RISKY[@]}"}; do
  echo "RISK_FILE=$r"
done
exit 0
