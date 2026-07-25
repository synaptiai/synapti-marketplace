#!/usr/bin/env bash
# dossier-resolve-config.sh — resolve a dossier setting from the full precedence
# chain: DOSSIER_* environment variables over the four-source settings cascade.
#
# Precedence (highest first):
#   0. DOSSIER_<UPPER_SNAKE> environment variable
#   1. $DOSSIER_CONFIG                          (explicit file, if set)
#   2. .claude/settings.dossier.local.json      (project-local; gitignored)
#   3. .claude/settings.dossier.json            (project-shared; committed)
#   4. $HOME/.claude/settings.dossier.json      (user-global)
#   5. ${CLAUDE_PLUGIN_ROOT}/settings.json      (plugin default)
#
# Layers 2-5 are delegated to cascade-resolve.sh so the cascade semantics stay a
# behavioural twin of the flow plugin's. Layer 0 is what lets a CI job run with
# zero interaction and no config file on disk.
#
# Env-var naming: the dotted key path minus the leading `dossier.`, upper-snaked.
#   dossier.ci.enabled          -> DOSSIER_CI_ENABLED
#   dossier.project.outputRoot  -> DOSSIER_PROJECT_OUTPUT_ROOT
#
# Usage:
#   dossier-resolve-config.sh [--default <fallback>] [--compact] <dotted.key>
#   dossier-resolve-config.sh --json                      # whole merged config
#
# Output:
#   stdout: resolved value (one line), or the merged config object with --json
#   stderr: WARN lines for unreadable sources
#
# Exit:
#   0 — resolved a value or returned the default (both normal)
#   2 — infrastructure error (jq missing, no key given, resolver missing)

set -uo pipefail

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CASCADE="$SELF_DIR/cascade-resolve.sh"

if [ ! -x "$CASCADE" ]; then
  echo "dossier-resolve-config: cascade-resolve.sh missing or non-executable at $CASCADE" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "dossier-resolve-config: jq is required" >&2
  exit 2
fi

MODE_ARGS=""
DEFAULT_VALUE=""
DEFAULT_SET=0
WANT_JSON=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --default)
      [ $# -lt 2 ] && { echo "dossier-resolve-config: --default requires a value" >&2; exit 2; }
      DEFAULT_VALUE="$2"; DEFAULT_SET=1; shift 2 ;;
    --compact)
      MODE_ARGS="--compact"; shift ;;
    --json)
      WANT_JSON=1; shift ;;
    --) shift; break ;;
    -*) echo "dossier-resolve-config: unknown flag: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

# --- whole-config mode -------------------------------------------------------
# Merges the cascade shallowly-deep (jq `*`) from lowest to highest precedence so
# a project file that sets one key does not erase its siblings. Env overrides are
# NOT folded in here: they are scalar-only by nature and callers that need them
# should ask for the specific key.
if [ "$WANT_JSON" -eq 1 ]; then
  MERGED='{}'
  for SRC in \
    "${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/settings.json" \
    "${HOME:-/nonexistent}/.claude/settings.dossier.json" \
    ".claude/settings.dossier.json" \
    ".claude/settings.dossier.local.json" \
    "${DOSSIER_CONFIG:-}"
  do
    [ -n "$SRC" ] || continue
    [ -f "$SRC" ] || continue
    if ! NEXT=$(jq -c '.' "$SRC" 2>/dev/null); then
      echo "dossier-resolve-config: WARN: failed to parse $SRC; skipping" >&2
      continue
    fi
    MERGED=$(jq -c -n --argjson a "$MERGED" --argjson b "$NEXT" '$a * $b') || {
      echo "dossier-resolve-config: WARN: failed to merge $SRC; skipping" >&2
    }
  done
  printf '%s\n' "$MERGED"
  exit 0
fi

KEY="${1:-}"
[ -z "$KEY" ] && {
  echo "dossier-resolve-config: missing <dotted.key>. Usage: $0 [--default <v>] [--compact] <dotted.key>" >&2
  exit 2
}

# --- layer 0: environment override -------------------------------------------
# Strip a leading `dossier.`, then upper-snake the remainder. Handled with tr and
# sed rather than ${var^^} because this must run on bash 3.2 (macOS default).
ENV_TAIL=${KEY#dossier.}
ENV_NAME=$(printf '%s' "$ENV_TAIL" \
  | sed -e 's/\./_/g' -e 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' \
  | tr '[:lower:]' '[:upper:]')
ENV_NAME="DOSSIER_${ENV_NAME}"

ENV_VALUE=$(eval "printf '%s' \"\${${ENV_NAME}:-}\"" 2>/dev/null)
if [ -n "$ENV_VALUE" ]; then
  printf '%s\n' "$ENV_VALUE"
  exit 0
fi

# --- layer 1: explicit config file -------------------------------------------
if [ -n "${DOSSIER_CONFIG:-}" ] && [ -f "$DOSSIER_CONFIG" ]; then
  JQ_MODE="-r"
  [ "$MODE_ARGS" = "--compact" ] && JQ_MODE="-c"
  # Bare path, for the same reason as the cascade layers below: `// empty` and
  # `// null` both swallow an explicit `false`.
  if RESULT=$(jq $JQ_MODE ".dossier.${KEY#dossier.}" "$DOSSIER_CONFIG" 2>/dev/null); then
    if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
      printf '%s\n' "$RESULT"
      exit 0
    fi
  else
    echo "dossier-resolve-config: WARN: failed to parse \$DOSSIER_CONFIG ($DOSSIER_CONFIG); skipping" >&2
  fi
fi

# --- layers 2-5: the settings cascade ----------------------------------------
# The bare path, with NO `//` alternative operator appended.
#
# jq's `//` is falsy-triggered, not null-triggered: `false // null` evaluates to
# `null`, so `.dossier.ci.enabled // null` on an explicitly disabled feature
# reports not-found and the cascade falls through to the next layer — silently
# re-enabling the thing the user turned off. `// empty` has the same defect.
#
# The bare path avoids it entirely: jq -r prints "false" for an explicit false
# and "null" for a missing key, and cascade-resolve.sh already treats the
# literal string "null" as not-found. Explicit false resolves; absent falls
# through. Do not "simplify" this by adding an alternative operator.
if [ $DEFAULT_SET -eq 1 ]; then
  # shellcheck disable=SC2086
  exec "$CASCADE" $MODE_ARGS --default "$DEFAULT_VALUE" ".${KEY}"
fi
# shellcheck disable=SC2086
exec "$CASCADE" $MODE_ARGS ".${KEY}"
