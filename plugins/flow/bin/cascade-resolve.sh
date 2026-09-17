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
#   cascade-resolve.sh [--default <fallback>] [--compact] [--scalar] <jq-expression>
#
# Flags:
#   --default <value>   value printed on stdout when no source has the key
#   --compact           use `jq -c` (preserves JSON quoting) instead of `jq -r`
#   --scalar            the caller is about to embed this in a `KEY=value`
#                       output grammar, so a value carrying a control character
#                       is refused rather than printed. See SECURITY below.
#
# Output:
#   stdout: the resolved value (one line; the default if provided and no
#           source resolved; otherwise empty)
#   stderr: per-source `cascade-resolve: WARN: ...` for parse errors
#
# Exit:
#   0 — resolved a value (or returned the default; both are normal)
#   2 — infrastructure error (jq missing, no expression provided, or --scalar
#       refused a multi-line value with no --default to fall back to)
#
# SECURITY — why --scalar exists:
#   .claude/settings.flow.json is a tracked file, so a fork pull request chooses
#   what is in it, and this helper prints a resolved string verbatim. A value
#   containing a newline therefore closes the `KEY=value` line the agent is
#   reading and opens another one: /flow:learn Phase 1 printed a `JOURNAL_DIR=`
#   line derived from `journal.dir`, and a newline in that setting forged a
#   whole `### Dismissal Artifacts` section — with its own STATE=ok and its own
#   DISMISSED= rows — above the real one. Every consumer that embeds the result
#   in that grammar passes --scalar. It is opt-in because the resolver cannot
#   know the consumer's grammar, and a caller that prints a value as data (not
#   as a KEY=value line) is unaffected.

set -uo pipefail

MODE="-r"
DEFAULT_VALUE=""
DEFAULT_SET=0
SCALAR_ONLY=0

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
    --scalar)
      SCALAR_ONLY=1
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

  # Treat jq's "null" output as not-found. Boolean callers MUST use a BARE
  # expression (`.flow.workflows.enabled`): jq then prints "false" verbatim
  # and an explicit project-level false wins over a lower-precedence true.
  # Both `// empty` and `// null` treat false as falsy and swallow it, so a
  # project's `enabled: false` would fall through to the plugin default.
  # `// empty` remains fine for string/number keys (tests/flow-cycle14-
  # behavioral.test.sh pins both behaviours).
  if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
    if [ "$SCALAR_ONLY" -eq 1 ]; then
      # A control character here is either corruption or an injection. It is
      # never part of a path, a name, or a flag, so refusing costs nothing a
      # caller would miss and refusing silently would be the failure this
      # whole plugin is written to avoid: report it, then fall back.
      case "$RESULT" in
        *[[:cntrl:]]*)
          echo "cascade-resolve: WARN: the value resolved for $EXPR from $SETTINGS contains a control character (a newline forges a second KEY=value line for the caller's consumer); refusing it" >&2
          if [ $DEFAULT_SET -eq 1 ]; then
            printf '%s\n' "$DEFAULT_VALUE"
            exit 0
          fi
          exit 2
          ;;
      esac
    fi
    printf '%s\n' "$RESULT"
    exit 0
  fi
done

# No source resolved a non-empty value
if [ $DEFAULT_SET -eq 1 ]; then
  printf '%s\n' "$DEFAULT_VALUE"
fi
exit 0
