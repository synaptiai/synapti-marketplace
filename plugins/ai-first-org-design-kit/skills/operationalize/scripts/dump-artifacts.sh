#!/usr/bin/env bash
# dump-artifacts.sh — Concatenate all ai-first-kit artifacts into a single document
# Usage: dump-artifacts.sh <project-slug> [output-file] [--include-confidential]
# If output-file omitted, writes to stdout
# Confidential sections (holdouts, political maps) are EXCLUDED by default.
# Pass --include-confidential to include them with warning banners.

set -eo pipefail
shopt -s nullglob

# --- Argument parsing ---
SLUG=""
OUTPUT="/dev/stdout"
INCLUDE_CONFIDENTIAL=false

for arg in "$@"; do
  case "$arg" in
    --include-confidential) INCLUDE_CONFIDENTIAL=true ;;
    *)
      if [ -z "$SLUG" ]; then
        SLUG="$arg"
      elif [ "$OUTPUT" = "/dev/stdout" ]; then
        OUTPUT="$arg"
      fi
      ;;
  esac
done

[ -z "$SLUG" ] && { echo "Usage: dump-artifacts.sh <project-slug> [output-file] [--include-confidential]" >&2; exit 1; }

# --- Validation ---
[ -z "$HOME" ] && { echo "ERROR: \$HOME is not set" >&2; exit 1; }
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "ERROR: Invalid slug: $SLUG" >&2; exit 1; }

BASE="$HOME/.ai-first-kit/projects/$SLUG"
DATE=$(date +%Y-%m-%d-%H%M)

[ ! -d "$BASE" ] && { echo "ERROR: No artifacts found at $BASE" >&2; exit 1; }

# Validate output directory if writing to file
if [ "$OUTPUT" != "/dev/stdout" ]; then
  OUTPUT_DIR=$(dirname "$OUTPUT")
  [ ! -d "$OUTPUT_DIR" ] && { echo "ERROR: Output directory $OUTPUT_DIR does not exist" >&2; exit 1; }
  [ ! -w "$OUTPUT_DIR" ] && { echo "ERROR: Output directory $OUTPUT_DIR is not writable" >&2; exit 1; }
fi

# --- Helpers ---

# Append file with H3 header showing source path
append_file() {
  local file="$1"
  local relative="${file#$BASE/}"
  if [ -f "$file" ] && [ -r "$file" ]; then
    echo ""
    echo "### $relative"
    echo ""
    cat "$file"
    echo ""
    echo "---"
  elif [ -f "$file" ]; then
    echo ""
    echo "### $relative"
    echo ""
    echo "(ERROR: file exists but is not readable)"
    echo ""
    echo "---"
  fi
}

# Append confidential file with warning banner
append_confidential() {
  local file="$1"
  local relative="${file#$BASE/}"
  if [ -f "$file" ] && [ -r "$file" ]; then
    echo ""
    echo "### $relative"
    echo ""
    echo "> **⚠️ CONFIDENTIAL** — This section contains sensitive organizational data."
    echo "> Do not share externally or expose to agents."
    echo ""
    cat "$file"
    echo ""
    echo "---"
  elif [ -f "$file" ]; then
    echo ""
    echo "### $relative"
    echo ""
    echo "(ERROR: file exists but is not readable)"
    echo ""
    echo "---"
  fi
}

# Section header
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
  if [ "$INCLUDE_CONFIDENTIAL" = true ]; then
    echo "<!-- Sections marked with CONFIDENTIAL contain sensitive data. -->"
  else
    echo "<!-- Confidential sections (holdouts, political maps) excluded. Use --include-confidential to include. -->"
  fi
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
  for f in "$BASE/specs/"*.md; do
    # nullglob ensures this loop is skipped when no matches
    [ -z "${_specs_header_printed:-}" ] && { section "Specifications"; _specs_header_printed=1; }
    append_file "$f"
  done

  # 6. Quality Gates (excluding holdouts)
  if [ -d "$BASE/gates" ]; then
    section "Quality Gates"
    append_file "$BASE/gates/INDEX.md"
    for f in "$BASE/gates/"*.md; do
      [ "$(basename "$f")" = "INDEX.md" ] && continue
      append_file "$f"
    done
  fi

  # 7. Quality Gate Holdouts (CONFIDENTIAL — only with --include-confidential)
  if [ "$INCLUDE_CONFIDENTIAL" = true ]; then
    for f in "$BASE/gates/.holdouts/"*.md; do
      [ -z "${_holdouts_header_printed:-}" ] && {
        section "Quality Gate Holdouts"
        echo ""
        echo "> **⚠️ CONFIDENTIAL** — Holdout scenarios are used to validate agent output."
        echo "> Never expose to executing agents. For internal review only."
        echo ""
        _holdouts_header_printed=1
      }
      append_confidential "$f"
    done
  fi

  # 8. Roles (most recent)
  ROLES=$(find "$BASE" -maxdepth 1 -name "roles-*.md" -print 2>/dev/null | sort -r | head -1)
  if [ -n "${ROLES:-}" ]; then
    section "Roles"
    append_file "$ROLES"
  fi

  # 9. Political Map (CONFIDENTIAL — only with --include-confidential)
  if [ "$INCLUDE_CONFIDENTIAL" = true ]; then
    POLMAP=$(find "$BASE" -maxdepth 1 -name "political-map-*.md" -print 2>/dev/null | sort -r | head -1)
    if [ -n "${POLMAP:-}" ]; then
      section "Political Map"
      append_confidential "$POLMAP"
    fi
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
  if [ "$INCLUDE_CONFIDENTIAL" = true ]; then
    echo "WARNING: Dump includes confidential sections (holdouts, political maps)" >&2
  fi
fi
