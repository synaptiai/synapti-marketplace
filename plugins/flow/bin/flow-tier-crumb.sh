#!/usr/bin/env bash
# [flow] flow-tier-crumb.sh — one breadcrumb for a write the factory engine
# made under a journal tier key (design new_files L11).
#
# Usage: flow-tier-crumb.sh --issue <N> --main <main checkout top> <key> <summary>
#
# Writes '<!-- auto-log: <UTC time> tiers.<key> (journal, factory engine)
# "<summary>" -->' to issue N's trail file in the main checkout
# (<journal dir>/auto-log/issue-N.YYYY-MM.md), through lib/tier-trail.sh, as
# tier-gate writes its own breadcrumbs. The trail file is issue N's whatever
# branch the main checkout has checked out: tier-trail.sh names the file from
# `git -C <top> branch --show-current`, so this script answers that one call
# with issue-N and passes every other git call on. Like tier-gate, it writes
# only where the repository already has a journal folder.
#
# Exit: 0 when the breadcrumb was written or the trail was left alone (a
# problem with the trail is noted on stderr, as tier-gate does); 2 for a
# wrong argument.

unset CDPATH

PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P) || exit 2

_tg_note() { printf 'flow: tier crumb — %s\n' "$1" >&2; }

_crumb_usage() {
  printf '%s\n' "usage: flow-tier-crumb.sh --issue <N> --main <main checkout top> <key> <summary>" >&2
  exit 2
}

CRUMB_ISSUE=""
CRUMB_MAIN=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue) [ "$#" -ge 2 ] || _crumb_usage; CRUMB_ISSUE=$2; shift 2 ;;
    --main) [ "$#" -ge 2 ] || _crumb_usage; CRUMB_MAIN=$2; shift 2 ;;
    --) shift; break ;;
    -*) _crumb_usage ;;
    *) break ;;
  esac
done
[ "$#" -eq 2 ] || _crumb_usage
CRUMB_KEY=$1
CRUMB_SUMMARY=$2
case "$CRUMB_ISSUE" in ''|*[!0-9]*|0*) _crumb_usage ;; esac
case "$CRUMB_KEY" in push|prCreate|issueAssign|issueCreate|issueUpdate|merge|release) ;; *) _crumb_usage ;; esac
case "$CRUMB_MAIN" in /*) ;; *) _crumb_usage ;; esac
[ -d "$CRUMB_MAIN" ] || _crumb_usage

# shellcheck source=../hooks/scripts/lib/tier-trail.sh
. "$PLUGIN_ROOT/hooks/scripts/lib/tier-trail.sh" || exit 2

# tier-trail.sh reads the branch to pick the trail file; the engine's write
# belongs to issue N whatever is checked out. Only that one call is answered
# here; the helpers tier-trail.sh starts run git as their own processes.
git() {
  if [ "$#" -eq 4 ] && [ "$1" = -C ] && [ "$3" = branch ] && [ "$4" = --show-current ]; then
    printf 'issue-%s\n' "$CRUMB_ISSUE"
    return 0
  fi
  command git "$@"
}

CRUMB_SAFE=$(_tg_crumb_safe "$(printf '%s' "$CRUMB_SUMMARY" | cut -c1-160)")
CRUMB_TEXT="<!-- auto-log: $(date -u +%Y-%m-%dT%H:%M:%SZ) tiers.$CRUMB_KEY (journal, factory engine) \"$CRUMB_SAFE\" -->"$'\n'
_tg_write_trail "$CRUMB_MAIN" "$CRUMB_TEXT"
exit 0
