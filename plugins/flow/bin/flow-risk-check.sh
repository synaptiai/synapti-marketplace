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
#                             * also matches /: "plugins/flow/hooks/*" covers
#                             every file below hooks/. Default [].
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

# The paths, trimmed, without a leading ./ and without blank lines.
FILES=()
while IFS= read -r f || [ -n "$f" ]; do
  f="${f%$'\r'}"
  f="${f#"${f%%[![:space:]]*}"}"
  f="${f%"${f##*[![:space:]]}"}"
  f="${f#./}"
  [ -n "$f" ] && FILES+=("$f")
done < "$FILES_FROM"
[ "${#FILES[@]}" -gt 0 ] || unavailable "the files list is empty; list the files the change will modify"

# Settings. A value of the wrong type is not a reason to skip the check.
RESOLVE="$HERE/cascade-resolve.sh"
AREAS_JSON=$("$RESOLVE" --compact --default '[]' '.design.riskAreas' 2>/dev/null)
if ! printf '%s' "$AREAS_JSON" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
  echo "WARN: design.riskAreas is not a list of strings; no declared risk areas are used" >&2
  AREAS_JSON='[]'
fi
AREAS=()
while IFS= read -r a; do
  [ -n "$a" ] && AREAS+=("$a")
done < <(printf '%s' "$AREAS_JSON" | jq -r '.[]')
THRESHOLD=$("$RESOLVE" --default 3 '.design.hotspotFixCommits' 2>/dev/null)
case "$THRESHOLD" in
  ''|*[!0-9]*)
    echo "WARN: design.hotspotFixCommits is not a whole number; 3 is used" >&2
    THRESHOLD=3 ;;
esac

# Fix commits per file over the window, as "count<TAB>path" lines.
HOT=""
COMMITS_READ=0
if [ "$THRESHOLD" -gt 0 ]; then
  LOG=$(git log --no-merges -n "$WINDOW" --format='%x1e%s' --name-only HEAD 2>/dev/null) \
    || unavailable "git log failed"
  COMMITS_READ=$(printf '%s\n' "$LOG" | grep -c $'^\x1e')
  HOT=$(printf '%s\n' "$LOG" | awk '
    /^\036/ {
      s = tolower(substr($0, 2))
      fix = (s ~ /^(fix|hotfix|bugfix|revert)([(:! ]|$)/)
      next
    }
    NF && fix { n[$0]++ }
    END { for (p in n) printf "%d\t%s\n", n[p], p }')
fi

RISKY=()
for f in "${FILES[@]}"; do
  reasons=""
  for a in ${AREAS[@]+"${AREAS[@]}"}; do
    # shellcheck disable=SC2254
    case "$f" in
      $a) reasons="${reasons:+$reasons; }risk area $a" ;;
    esac
  done
  if [ "$THRESHOLD" -gt 0 ]; then
    c=$(printf '%s\n' "$HOT" | awk -F'\t' -v p="$f" '$2 == p { print $1; exit }')
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
for r in ${RISKY[@]+"${RISKY[@]}"}; do
  echo "RISK_FILE=$r"
done
exit 0
