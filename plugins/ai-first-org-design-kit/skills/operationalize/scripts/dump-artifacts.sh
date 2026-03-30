#!/usr/bin/env bash
# dump-artifacts.sh — Concatenate all ai-first-kit artifacts into a single document
# Usage: dump-artifacts.sh <project-slug> [output-file]
# If output-file omitted, writes to stdout

set -eo pipefail

SLUG="${1:?Usage: dump-artifacts.sh <project-slug> [output-file]}"
BASE="$HOME/.ai-first-kit/projects/$SLUG"
OUTPUT="${2:-/dev/stdout}"
DATE=$(date +%Y-%m-%d-%H%M)

[ ! -d "$BASE" ] && echo "ERROR: No artifacts found at $BASE" >&2 && exit 1

# Helper: append file with H3 header showing source path
append_file() {
  local file="$1"
  local relative="${file#$BASE/}"
  if [ -f "$file" ]; then
    echo ""
    echo "### $relative"
    echo ""
    cat "$file"
    echo ""
    echo "---"
  fi
}

# Helper: append confidential file with warning banner
append_confidential() {
  local file="$1"
  local relative="${file#$BASE/}"
  if [ -f "$file" ]; then
    echo ""
    echo "### $relative"
    echo ""
    echo "> **⚠️ CONFIDENTIAL** — This section contains sensitive organizational data."
    echo "> Do not share externally or expose to agents."
    echo ""
    cat "$file"
    echo ""
    echo "---"
  fi
}

# Helper: section header
section() {
  echo ""
  echo "## $1"
}

# --- Build the dump ---
{
  # Header
  echo "# Organizational Design — $SLUG"
  echo "<!-- Full artifact dump generated: $DATE -->"
  echo "<!-- Source: \$HOME/.ai-first-kit/projects/$SLUG/ -->"
  echo "<!-- This is a reference document, not agent instructions. -->"
  echo "<!-- For agent consumption, use AGENT-PRIMER.md instead. -->"
  echo "<!-- Sections marked with CONFIDENTIAL contain sensitive data. -->"
  echo ""

  # 1. Identity
  if [ -d "$BASE/genome/00-identity" ]; then
    section "Identity"
    append_file "$BASE/genome/00-identity/MISSION.md"
    append_file "$BASE/genome/00-identity/VALUES.md"
    append_file "$BASE/genome/00-identity/VOICE.md"
  fi

  # 2. Decision Architecture
  if [ -d "$BASE/genome/01-decision-architecture" ]; then
    section "Decision Architecture"
    append_file "$BASE/genome/01-decision-architecture/AUTHORITY-MATRIX.md"
    append_file "$BASE/genome/01-decision-architecture/TRADEOFF-RULES.md"
  fi

  # 3. Quality Standards
  if [ -d "$BASE/genome/02-quality-standards" ]; then
    section "Quality Standards"
    append_file "$BASE/genome/02-quality-standards/BY-OUTPUT-TYPE.md"
    append_file "$BASE/genome/02-quality-standards/ANTI-PATTERNS.md"
  fi

  # 4. Governance
  if [ -d "$BASE/governance" ]; then
    section "Governance"
    append_file "$BASE/governance/AUTHORITY-MATRIX.md"
    append_file "$BASE/governance/HARD-BOUNDARIES.md"
    append_file "$BASE/governance/ESCALATION-PROTOCOLS.md"
    append_file "$BASE/governance/POLICY-GENERATION.md"
    append_file "$BASE/governance/DECISION-LEDGER-SPEC.md"
    append_file "$BASE/governance/LEARNING-LOOP.md"
  fi

  # 5. Specifications
  if ls "$BASE/specs/"*.md >/dev/null 2>&1; then
    section "Specifications"
    for f in "$BASE/specs/"*.md; do
      append_file "$f"
    done
  fi

  # 6. Quality Gates (excluding holdouts)
  if [ -d "$BASE/gates" ]; then
    section "Quality Gates"
    append_file "$BASE/gates/INDEX.md"
    for f in "$BASE/gates/"*.md; do
      [ "$(basename "$f")" = "INDEX.md" ] && continue
      append_file "$f"
    done
  fi

  # 7. Quality Gate Holdouts (CONFIDENTIAL)
  if ls "$BASE/gates/.holdouts/"*.md >/dev/null 2>&1; then
    section "Quality Gate Holdouts"
    echo ""
    echo "> **⚠️ CONFIDENTIAL** — Holdout scenarios are used to validate agent output."
    echo "> Never expose to executing agents. For internal review only."
    echo ""
    for f in "$BASE/gates/.holdouts/"*.md; do
      append_confidential "$f"
    done
  fi

  # 8. Roles (most recent)
  ROLES=$(find "$BASE" -maxdepth 1 -name "roles-*.md" -print 2>/dev/null | sort -r | head -1)
  if [ -n "${ROLES:-}" ]; then
    section "Roles"
    append_file "$ROLES"
  fi

  # 9. Political Map (CONFIDENTIAL)
  POLMAP=$(find "$BASE" -maxdepth 1 -name "political-map-*.md" -print 2>/dev/null | sort -r | head -1)
  if [ -n "${POLMAP:-}" ]; then
    section "Political Map"
    append_confidential "$POLMAP"
  fi

  # 10. Audit
  AUDIT=$(find "$BASE" -maxdepth 1 -name "audit-*.md" -print 2>/dev/null | sort -r | head -1)
  if [ -n "${AUDIT:-}" ]; then
    section "Coordination Audit"
    append_file "$AUDIT"
  fi

  # 11. Agent Primer (if exists — included for completeness)
  if [ -f "$BASE/AGENT-PRIMER.md" ]; then
    section "Agent Primer (Distilled)"
    append_file "$BASE/AGENT-PRIMER.md"
  fi

} > "$OUTPUT"

# Report to stderr so it doesn't pollute stdout output
if [ "$OUTPUT" != "/dev/stdout" ]; then
  LINES=$(wc -l < "$OUTPUT" | tr -d ' ')
  echo "Dump written to: $OUTPUT ($LINES lines)" >&2
fi
