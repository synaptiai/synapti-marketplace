#!/usr/bin/env bash
# dossier-scaffold.sh — create the canonical 7-directory / 23-file documentation
# package under an output root by copying the plugin's templates.
#
# Idempotent and non-destructive: an existing file is NEVER overwritten, never
# truncated, and never merged. Re-running after a partial scaffold fills only the
# gaps. This is deliberate — the package holds hand-written evidence, and a
# scaffold that clobbers is a scaffold nobody dares re-run.
#
# Usage:
#   dossier-scaffold.sh --output-root <path> [--dry-run] [--templates <dir>]
#
# Flags:
#   --output-root <path>   REQUIRED. Directory the package is created under.
#                          Created if absent.
#   --dry-run              Report what would be created; write nothing.
#   --templates <dir>      Override the template source directory. Defaults to
#                          <plugin-root>/templates/package. Used by tests.
#
# Output (stdout): KEY=value lines, then a per-file action list.
#   SCAFFOLD_ROOT=<path>
#   SCAFFOLD_DRY_RUN=0|1
#   SCAFFOLD_EXPECTED=23
#   SCAFFOLD_CREATED=<n>
#   SCAFFOLD_SKIPPED=<n>
#   SCAFFOLD_FAILED=<n>
#   CREATED <relative-path>   (one line per created file)
#   SKIPPED <relative-path>   (one line per pre-existing file)
#   FAILED  <relative-path>   (one line per copy failure)
#
# Exit:
#   0 — every canonical file is present (created or already there)
#   1 — one or more files could not be created
#   2 — infrastructure error (missing argument, template dir unreadable)

set -uo pipefail

OUTPUT_ROOT=""
DRY_RUN=0
TEMPLATE_DIR=""

# The canonical package. Order is the reading order, not alphabetical.
CANONICAL_FILES="
00-control/documentation-index.md
00-control/evidence-ledger.md
00-control/assumptions-questions-and-contradictions.md
00-control/claim-and-disclosure-register.md
00-control/terminology-and-ownership.md
01-project/executive-project-brief.md
01-project/product-and-domain.md
02-architecture/system-architecture.md
02-architecture/components-and-codebase.md
02-architecture/data-and-ai.md
02-architecture/interfaces-and-integrations.md
02-architecture/infrastructure-and-deployment.md
03-assurance/security-privacy-and-compliance.md
03-assurance/reliability-performance-and-observability.md
03-assurance/testing-quality-and-delivery.md
04-operating/onboarding-and-local-development.md
04-operating/operations-and-incident-response.md
04-operating/decisions-technical-debt-and-risks.md
05-due-diligence/technical-due-diligence-report.md
05-due-diligence/assets-dependencies-and-licenses.md
06-public/technical-partner-guide.md
06-public/customer-product-and-trust-guide.md
07-verification/documentation-verification-report.md
"

CANONICAL_DIRS="00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification"

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --output-root)
      [ $# -lt 2 ] && { echo "dossier-scaffold: --output-root requires a value" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --templates)
      [ $# -lt 2 ] && { echo "dossier-scaffold: --templates requires a value" >&2; exit 2; }
      TEMPLATE_DIR="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --) shift; break ;;
    *)
      echo "dossier-scaffold: unknown argument: $1" >&2
      echo "Usage: $0 --output-root <path> [--dry-run] [--templates <dir>]" >&2
      exit 2 ;;
  esac
done

if [ -z "$OUTPUT_ROOT" ]; then
  echo "dossier-scaffold: missing --output-root. Usage: $0 --output-root <path> [--dry-run] [--templates <dir>]" >&2
  exit 2
fi

# Resolve the template directory. CLAUDE_PLUGIN_ROOT is not reliably set inside
# slash-command bash blocks, so fall back to this script's own location, which is
# always <plugin-root>/bin.
if [ -z "$TEMPLATE_DIR" ]; then
  SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
  for CANDIDATE in \
    "${CLAUDE_PLUGIN_ROOT:-}/templates/package" \
    "${SCRIPT_DIR:-}/../templates/package" \
    "plugins/dossier/templates/package"
  do
    case "$CANDIDATE" in /templates/package|"") continue ;; esac
    if [ -d "$CANDIDATE" ]; then TEMPLATE_DIR="$CANDIDATE"; break; fi
  done
fi

if [ -z "$TEMPLATE_DIR" ] || [ ! -d "$TEMPLATE_DIR" ]; then
  echo "dossier-scaffold: template directory not found (looked at CLAUDE_PLUGIN_ROOT, script dir, and plugins/dossier)" >&2
  exit 2
fi

CREATED=0
SKIPPED=0
FAILED=0
ACTIONS=""

if [ "$DRY_RUN" -eq 0 ]; then
  for DIR in $CANONICAL_DIRS; do
    mkdir -p "$OUTPUT_ROOT/$DIR" 2>/dev/null || {
      echo "dossier-scaffold: cannot create $OUTPUT_ROOT/$DIR" >&2
      exit 2
    }
  done
fi

for REL in $CANONICAL_FILES; do
  SRC="$TEMPLATE_DIR/$REL"
  DEST="$OUTPUT_ROOT/$REL"

  if [ -e "$DEST" ]; then
    SKIPPED=$((SKIPPED + 1))
    ACTIONS="${ACTIONS}SKIPPED $REL
"
    continue
  fi

  if [ ! -f "$SRC" ]; then
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $REL (template missing at $SRC)
"
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    CREATED=$((CREATED + 1))
    ACTIONS="${ACTIONS}CREATED $REL
"
    continue
  fi

  if cp "$SRC" "$DEST" 2>/dev/null; then
    CREATED=$((CREATED + 1))
    ACTIONS="${ACTIONS}CREATED $REL
"
  else
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $REL (copy failed)
"
  fi
done

printf 'SCAFFOLD_ROOT=%s\n' "$OUTPUT_ROOT"
printf 'SCAFFOLD_DRY_RUN=%s\n' "$DRY_RUN"
printf 'SCAFFOLD_EXPECTED=23\n'
printf 'SCAFFOLD_CREATED=%s\n' "$CREATED"
printf 'SCAFFOLD_SKIPPED=%s\n' "$SKIPPED"
printf 'SCAFFOLD_FAILED=%s\n' "$FAILED"
printf '%s' "$ACTIONS"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
