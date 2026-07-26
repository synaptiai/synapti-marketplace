#!/usr/bin/env bash
# cascade-resolve.sh — read a dossier plugin setting from the standard Claude Code
# settings cascade with per-source parse-error surfacing.
#
# Resolves a jq expression against four trusted sources, in precedence order
# (highest first — first non-empty value wins):
#
#   1. .claude/settings.dossier.local.json — project-local; gitignored
#   2. .claude/settings.dossier.json       — project-shared; committed
#   3. $HOME/.claude/settings.dossier.json — user-global
#   4. ${CLAUDE_PLUGIN_ROOT}/settings.json — plugin default
#
# Environment overrides (DOSSIER_*) are NOT handled here — they are applied by
# dossier-resolve-config.sh, which wraps this script. That split keeps this file
# a byte-for-byte behavioural twin of plugins/flow/bin/cascade-resolve.sh, so a
# fix to the cascade semantics in either plugin ports directly to the other.
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

LOCAL_SETTINGS=".claude/settings.dossier.local.json"
PROJECT_SETTINGS=".claude/settings.dossier.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.dossier.json"
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/settings.json"

for SETTINGS in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS" ] || continue

  # Capture stdout and stderr separately. `2>&1` would mix jq's parse-error
  # text with the resolved value when jq emits warnings on stderr while
  # exiting 0 (older jq versions can do this).
  STDERR_TMP=$(mktemp -t cascade-resolve.err.XXXXXX) || {
  echo "cascade-resolve: cannot create a temporary file or directory" >&2; exit 2;
}
  RESULT=$(jq $MODE "$EXPR" "$SETTINGS" 2>"$STDERR_TMP")
  EXIT=$?

  if [ $EXIT -ne 0 ]; then
    ERR=$(tr '\n' ' ' <"$STDERR_TMP" 2>/dev/null | cut -c1-200)
    rm -f "$STDERR_TMP" 2>/dev/null
    echo "cascade-resolve: WARN: failed to parse $SETTINGS (jq exit=$EXIT, error: $ERR); skipping this source" >&2
    continue
  fi
  rm -f "$STDERR_TMP" 2>/dev/null

  # Absence is decided by jq, not by the shell.
  #
  # The old test was `[ -n "$RESULT" ] && [ "$RESULT" != "null" ]`, which
  # conflates three different states: key absent, key set to null, and key set
  # to an EMPTY STRING. The third is a meaningful, documented value in this
  # plugin — `project.name: ""` means "deliberately unresolved" and
  # `ci.agent.model: ""` means "inherit the action default". Treating it as
  # absence made a higher-precedence layer's explicit clear fall through to a
  # lower one, so a stale user-global value silently won.
  #
  # This is the same defect already fixed for booleans further down the stack;
  # it simply was never extended to strings. Ask jq whether the path resolves
  # to a non-null value — true for `""` and for `false`, false for a missing
  # key — and only then read it.
  if jq -e "($EXPR) != null" "$SETTINGS" >/dev/null 2>&1; then
    printf '%s\n' "$RESULT"
    exit 0
  fi
done

# No source resolved a non-empty value
if [ $DEFAULT_SET -eq 1 ]; then
  printf '%s\n' "$DEFAULT_VALUE"
fi
exit 0
