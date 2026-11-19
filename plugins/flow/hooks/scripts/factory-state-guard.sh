#!/usr/bin/env bash
# [flow] factory-state-guard.sh — PreToolUse hook for Write, Edit and
# NotebookEdit: the flow factory's engine is the only writer under its
# directory <main checkout>/<runtime dir>/factory, so a session's write there
# is denied (design person_channels, "The factory directory").
#
# Which directory:
#   - FLOW_FACTORY_MAIN set (a worker session, whose cwd is its job clone):
#     <FLOW_FACTORY_MAIN>/<runtime dir>/factory.
#   - Otherwise the main checkout of the payload's cwd (the parent of the
#     common git directory, so a linked worktree finds it), and its
#     <runtime dir>/factory.
# With FLOW_FACTORY_MAIN unset and no factory directory there, the hook exits
# at once and allows the write. It also allows the write when the directory
# cannot be resolved (FLOW_FACTORY_MAIN naming no folder, an unreadable
# runtime directory): tier-gate.sh and the engine's own checks remain.
#
# The path is tool_input.file_path, or tool_input.notebook_path for
# NotebookEdit. A relative path is read against the payload's cwd; `.` and
# `..` are applied to the text, then the longest existing part is replaced by
# its physical path and a symbolic link at the end is followed, so /var and
# /private/var, a `..` and a link into the factory all reach the same place.
#
# Without jq the path cannot be read: the write is denied when the payload
# text names the factory directory, and allowed otherwise.
#
# Output: nothing (allow), or one PreToolUse deny. Exit 0 always.

set -uo pipefail
unset CDPATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"

INPUT=$(cat 2>/dev/null) || INPUT=""

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

CWD=""
if [ "$HAVE_JQ" = 1 ]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty | strings' 2>/dev/null) || CWD=""
fi
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# The main checkout.
if [ -n "${FLOW_FACTORY_MAIN:-}" ]; then
  MAIN="$FLOW_FACTORY_MAIN"
else
  COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
  MAIN=$(dirname -- "$COMMON") || exit 0
fi
case "$MAIN" in /*) ;; *) exit 0 ;; esac
[ -d "$MAIN" ] || exit 0
RT=$(cd "$MAIN" 2>/dev/null && env -u PYTHONPATH "$PLUGIN_ROOT/bin/flow-runtime-dir.sh" 2>/dev/null) || exit 0
[ -n "$RT" ] || exit 0
FDIR="$MAIN/$RT/factory"
[ -d "$FDIR" ] || exit 0
FDIR_P=$(cd -P "$FDIR" 2>/dev/null && pwd -P) || exit 0

deny() {
  local r="$1" b='\' q='"'
  r=${r//"$b"/"$b$b"}
  r=${r//"$q"/"$b$q"}
  r=$(printf '%s' "$r" | LC_ALL=C tr '\000-\037' ' ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
  exit 0
}

REASON_TAIL="is under the flow factory's directory $FDIR, which only the factory's engine (bin/flow-factory.sh) writes. Change factory state through flow-factory.sh in a terminal."

# macOS reaches /var, /tmp and /etc both as themselves and under /private.
FDIR_ALT=""
case "$FDIR_P" in /private/*) FDIR_ALT="${FDIR_P#/private}" ;; /var/*|/tmp/*|/etc/*) FDIR_ALT="/private$FDIR_P" ;; esac

if [ "$HAVE_JQ" = 0 ]; then
  for S in "$FDIR" "$FDIR_P" ${FDIR_ALT:+"$FDIR_ALT"}; do
    case "$INPUT" in *"$S"*) deny "This write names a path that $REASON_TAIL" ;; esac
  done
  exit 0
fi

TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty | strings' 2>/dev/null) || TARGET=""
[ -n "$TARGET" ] || exit 0
SHOWN="$TARGET"
case "$TARGET" in /*) ;; *) TARGET="$CWD/$TARGET" ;; esac

# Apply . and .. to the text.
norm() {
  local IFS=/ part out=()
  set -f
  for part in $1; do
    case "$part" in
      ''|.) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  set +f
  local s=""
  for part in ${out[@]+"${out[@]}"}; do s="$s/$part"; done
  printf '%s' "${s:-/}"
}

# The physical path: the longest existing directory, then the rest; a link
# at the end is followed (up to 40 links).
physical() {
  local p="$1" head rest="" n=0 l
  while [ "$n" -lt 40 ] && [ -L "$p" ]; do
    l=$(readlink "$p") || break
    case "$l" in /*) p=$(norm "$l") ;; *) p=$(norm "$(dirname -- "$p")/$l") ;; esac
    n=$((n + 1))
  done
  head="$p"
  while [ "$head" != / ] && [ ! -d "$head" ]; do
    rest="/${head##*/}$rest"
    head=$(dirname -- "$head")
  done
  head=$(cd -P "$head" 2>/dev/null && pwd -P) || { printf '%s' "$p"; return; }
  [ "$head" = / ] && head=""
  printf '%s%s' "$head" "$rest"
}

T_NORM=$(norm "$TARGET")
T_PHYS=$(physical "$T_NORM")
for T in "$T_NORM" "$T_PHYS"; do
  case "$T" in
    "$FDIR"|"$FDIR"/*|"$FDIR_P"|"$FDIR_P"/*) deny "$SHOWN $REASON_TAIL" ;;
  esac
  if [ -n "$FDIR_ALT" ]; then
    case "$T" in "$FDIR_ALT"|"$FDIR_ALT"/*) deny "$SHOWN $REASON_TAIL" ;; esac
  fi
done
exit 0
