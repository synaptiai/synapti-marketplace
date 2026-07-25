#!/bin/bash
# [dossier] PreToolUse hook: confine writes to the documentation output root.
#
# engagement.allowedActions.writeOutsideOutputRoot is the run's containment
# guarantee. Without enforcement it is a comment; with it, a scope decision
# recorded in Phase 0 is a scope decision that holds for the whole run.
#
# Inert unless a dossier package is present, so this hook does not interfere
# with ordinary work in a repo that merely has the plugin installed.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

RESOLVER="${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/bin/dossier-resolve-config.sh"
OUTPUT_ROOT="docs/dossier"
ALLOW_OUTSIDE="false"
if [ -x "$RESOLVER" ]; then
  OUTPUT_ROOT=$("$RESOLVER" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
  ALLOW_OUTSIDE=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.writeOutsideOutputRoot 2>/dev/null)
fi

[ "$ALLOW_OUTSIDE" = "true" ] && exit 0

# Only active during a run — the frozen scope file is the signal that a dossier
# run owns this session. Absent it, ordinary editing proceeds untouched.
SCOPE_FILE="$OUTPUT_ROOT/00-control/.scope.json"
[ -f "$SCOPE_FILE" ] || exit 0

# Normalize to a repo-relative path so `./docs/...`, an absolute path inside the
# project, and `docs/...` all compare the same way.
REL="$FILE_PATH"
case "$REL" in
  "$PWD"/*) REL="${REL#"$PWD"/}" ;;
  ./*)      REL="${REL#./}" ;;
esac

case "$REL" in
  "$OUTPUT_ROOT"/*|"$OUTPUT_ROOT") exit 0 ;;
  .dossier/*) exit 0 ;;
esac

# A traversal that lands back inside the root is still outside it as written,
# and allowing it would make the check bypassable by construction.
cat >&2 <<EOF
BLOCKED: dossier run may not write outside its output root.

  target:      $REL
  output root: $OUTPUT_ROOT

The action ceiling was frozen in Phase 0 (engagement.allowedActions.
writeOutsideOutputRoot = false). A run that widens its own scope mid-flight
produces a package nobody can audit.

If this write is genuinely required, record the need as an AQ-#### row and
finish inside the ceiling, or re-run /dossier:init with the wider ceiling
recorded as a deliberate decision.
EOF
exit 2
