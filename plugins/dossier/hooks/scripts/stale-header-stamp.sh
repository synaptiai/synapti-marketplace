#!/bin/bash
# [dossier] PostToolUse hook: warn when a canonical document's claims changed
# without its last-verified date moving.
#
# `last-verified` means the claims were re-checked against evidence — not that
# the file was edited. The two failure modes are opposite and both matter:
#
#   * content changed, date unchanged  -> the package understates its own churn
#   * date advanced, content unchanged -> a stale package looks current
#
# This warns; it never blocks. Advancing the date can be correct (the claims
# genuinely were re-verified) and only the author knows which case applies.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  *.md) ;;
  *) exit 0 ;;
esac

RESOLVER="${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/bin/dossier-resolve-config.sh"
OUTPUT_ROOT="docs/dossier"
[ -x "$RESOLVER" ] && OUTPUT_ROOT=$("$RESOLVER" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)

REL="$FILE_PATH"
case "$REL" in
  "$PWD"/*) REL="${REL#"$PWD"/}" ;;
  ./*)      REL="${REL#./}" ;;
esac
case "$REL" in
  "$OUTPUT_ROOT"/*) ;;
  *) exit 0 ;;
esac

# Control-plane registers are append-only working files; their headers do not
# carry a claim-verification date in the same sense.
case "$REL" in
  */00-control/.*) exit 0 ;;
esac

head -20 "$FILE_PATH" | grep -q '^dossier-header:' || {
  echo "[dossier] note: $REL has no dossier header — run dossier-package-check.sh" >&2
  exit 0
}

LAST_VERIFIED=$(awk -F': *' '/^last-verified:/{print $2; exit}' "$FILE_PATH" | tr -d $'"\'\r')

if [ -z "$LAST_VERIFIED" ] || [ "$LAST_VERIFIED" = "{fill}" ]; then
  echo "[dossier] $REL: last-verified is unset. A document with no verification date cannot be checked for staleness." >&2
  exit 0
fi

case "$LAST_VERIFIED" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *)
    echo "[dossier] $REL: last-verified '$LAST_VERIFIED' is not an ISO YYYY-MM-DD date." >&2
    exit 0 ;;
esac

TODAY=$(date -u +%Y-%m-%d)
if [ "$LAST_VERIFIED" != "$TODAY" ]; then
  cat >&2 <<EOF
[dossier] $REL edited, last-verified still $LAST_VERIFIED.

If the claims were re-checked against evidence, advance it to $TODAY.
If this was a formatting or wording change, leave it — that date means the
claims were verified, and advancing it for a cosmetic edit is a false
statement about verification.
EOF
fi

exit 0
