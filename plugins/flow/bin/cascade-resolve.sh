#!/usr/bin/env bash
# cascade-resolve.sh — read a flow plugin setting from the standard Claude Code
# settings cascade with per-source parse-error surfacing.
#
# Resolves a jq expression against four trusted sources, in precedence order
# (highest first — first non-empty value wins):
#
#   1. .claude/settings.flow.local.json — project-local; gitignored
#   2. .claude/settings.flow.json       — project-shared; committed
#   3. $HOME/.claude/settings.flow.json — user-global
#   4. ${CLAUDE_PLUGIN_ROOT}/settings.json — plugin default
#
# Usage:
#   cascade-resolve.sh [--default <fallback>] [--compact] <jq-expression>
#
# Flags:
#   --default <value>   value printed on stdout when no source has the key
#   --compact           use `jq -c` (preserves JSON quoting) instead of `jq -r`
#
# Output:
#   stdout: the resolved value (one line; the default if provided and no
#           source resolved; otherwise empty)
#   stderr: per-source `cascade-resolve: WARN: ...` for parse errors
#
# Exit:
#   0 — resolved a value (or returned the default; both are normal)
#   2 — infrastructure error (jq missing, no expression provided)

set -uo pipefail

MODE="-r"
DEFAULT_VALUE=""
DEFAULT_SET=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --default)
      [ $# -lt 2 ] && { echo "cascade-resolve: --default requires a value" >&2; exit 2; }
      DEFAULT_VALUE="$2"
      DEFAULT_SET=1
      shift 2
      ;;
    --compact)
      MODE="-c"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "cascade-resolve: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

EXPR="${1:-}"
[ -z "$EXPR" ] && {
  echo "cascade-resolve: missing <jq-expression>. Usage: $0 [--default <v>] [--compact] <jq-expression>" >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  echo "cascade-resolve: WARN: jq not installed; cannot resolve cascade" >&2
  if [ $DEFAULT_SET -eq 1 ]; then
    printf '%s\n' "$DEFAULT_VALUE"
    exit 0
  fi
  exit 2
fi

LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"

for SETTINGS in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS" ] || continue

  # Capture stdout and stderr separately. `2>&1` would mix jq's parse-error
  # text with the resolved value when jq emits warnings on stderr while
  # exiting 0 (older jq versions can do this).
  STDERR_TMP=$(mktemp -t cascade-resolve.err.XXXXXX 2>/dev/null) || STDERR_TMP="/tmp/cascade-resolve.err.$$"
  RESULT=$(jq $MODE "$EXPR" "$SETTINGS" 2>"$STDERR_TMP")
  EXIT=$?

  if [ $EXIT -ne 0 ]; then
    ERR=$(tr '\n' ' ' <"$STDERR_TMP" 2>/dev/null | cut -c1-200)
    rm -f "$STDERR_TMP" 2>/dev/null
    echo "cascade-resolve: WARN: failed to parse $SETTINGS (jq exit=$EXIT, error: $ERR); skipping this source" >&2
    continue
  fi
  rm -f "$STDERR_TMP" 2>/dev/null

  # treat jq's "null" output as not-found so callers can use
  # `.flow.workflows.enabled // null` (recognizes explicit false) instead of
  # `// empty` (which swallows false alongside null). Backward compatible:
  # callers still using `// empty` produce "" and fall through as before.
  if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
    printf '%s\n' "$RESULT"
    exit 0
  fi
done

# No source resolved a non-empty value
if [ $DEFAULT_SET -eq 1 ]; then
  printf '%s\n' "$DEFAULT_VALUE"
fi
exit 0
