#!/usr/bin/env bash
# dossier-staleness-check.sh — single source of truth for document staleness.
#
# Consolidates the age/last-verified computation that commands/status.md and
# bin/dossier-evidence.sh previously each implemented separately, so a future
# change to the threshold or the header-parsing pattern cannot make the two
# silently disagree. Also bounds how many stale documents a single scheduled
# sweep may hand to dossier-policy.sh for re-verification, so a repository
# that has gone stale everywhere does not trigger an unbounded run.
#
# Usage:
#   dossier-staleness-check.sh [--output-root <path>] [--stale-days <n>] [--max-sweep <n>]
#   dossier-staleness-check.sh --single-file <path> [--stale-days <n>]
#
# Output (stdout, key=value lines), sweep mode:
#   STALENESS_THRESHOLD_DAYS=<n>
#   DOCUMENTS_STALE=<n>
#   DOCUMENTS_UNDATED=<n>
#   OLDEST_VERIFICATION=<date|none>
#   MAX_STALE_DOCS_PER_SWEEP=<n>
#   STALE_DOCS_FOR_SWEEP=<comma-separated relative paths, most-overdue first, capped>
#
# Output (stdout, key=value lines), --single-file mode — the per-document query
# bin/dossier-evidence.sh uses instead of running its own header-parsing regex,
# so the two producers cannot silently disagree on what counts as verified:
#   LAST_VERIFIED=<date|> (empty when undated)
#   IS_STALE=true|false
#   IS_UNDATED=true|false
#
# A document with no `last-verified` header, or one that is not an ISO
# YYYY-MM-DD date, counts as undated — never as stale, never as fresh. See
# references/change-triggers-and-blast-radius.md: a missing date means no
# evidence anyone ever confirmed the document, which this script leaves for
# callers to treat as they see fit rather than silently folding into either
# count.
#
# Exit:
#   0 — always, even with zero documents found. An absent or empty package is
#       not an error for this script; callers decide what an empty result
#       means.
#   2 — infrastructure error (missing prerequisite tool, bad argument)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CASCADE="$SCRIPT_DIR/dossier-resolve-config.sh"

for tool in awk find date; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "dossier-staleness-check: missing prerequisite: $tool" >&2
    exit 2
  }
done

OUTPUT_ROOT=""
STALE_DAYS=""
MAX_SWEEP=""
SINGLE_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --output-root)
      [ $# -lt 2 ] && { echo "dossier-staleness-check: --output-root requires a value" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --stale-days)
      [ $# -lt 2 ] && { echo "dossier-staleness-check: --stale-days requires a value" >&2; exit 2; }
      STALE_DAYS="$2"; shift 2 ;;
    --max-sweep)
      [ $# -lt 2 ] && { echo "dossier-staleness-check: --max-sweep requires a value" >&2; exit 2; }
      MAX_SWEEP="$2"; shift 2 ;;
    --single-file)
      [ $# -lt 2 ] && { echo "dossier-staleness-check: --single-file requires a value" >&2; exit 2; }
      SINGLE_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,41p' "$0"; exit 0 ;;
    *)
      echo "dossier-staleness-check: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# The single canonical header-parsing pattern. Matches the frontmatter contract
# in references/document-headers.md exactly (`^last-verified:`, no markdown
# emphasis, no bullet prefix) — the one place this pattern is allowed to exist.
parse_last_verified() {
  awk -F': *' '/^last-verified:/{print $2; exit}' "$1" 2>/dev/null | tr -d $'"\'\r'
}

# Flags win outright (tests and callers that already resolved config pass
# them explicitly); otherwise fall through to the resolver, matching every
# other bin script's precedence.
if [ -z "$OUTPUT_ROOT" ]; then
  if [ -x "$CASCADE" ]; then
    OUTPUT_ROOT=$("$CASCADE" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
  else
    OUTPUT_ROOT="docs/dossier"
  fi
fi
# Trailing slash would otherwise break the package-relative prefix strip below.
OUTPUT_ROOT="${OUTPUT_ROOT%/}"
if [ -z "$STALE_DAYS" ]; then
  if [ -x "$CASCADE" ]; then
    STALE_DAYS=$("$CASCADE" --default 90 dossier.refresh.stalenessDays 2>/dev/null)
  else
    STALE_DAYS=90
  fi
fi
case "$STALE_DAYS" in ''|*[!0-9]*) STALE_DAYS=90 ;; esac

if [ -n "$SINGLE_FILE" ]; then
  LV=$(parse_last_verified "$SINGLE_FILE")
  case "$LV" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      TODAY_S=$(date -u +%s)
      LV_S=$(date -j -f "%Y-%m-%d" "$LV" +%s 2>/dev/null || date -d "$LV" +%s 2>/dev/null || echo "")
      if [ -z "$LV_S" ]; then
        # Shape-valid but not a real calendar date (e.g. 2024-13-45) — no
        # evidence anyone actually verified this document, same as missing.
        printf 'LAST_VERIFIED=%s\n' "$LV"
        printf 'IS_STALE=false\n'
        printf 'IS_UNDATED=true\n'
      else
        IS_STALE="false"
        AGE=$(( (TODAY_S - LV_S) / 86400 ))
        [ "$AGE" -gt "$STALE_DAYS" ] && IS_STALE="true"
        printf 'LAST_VERIFIED=%s\n' "$LV"
        printf 'IS_STALE=%s\n' "$IS_STALE"
        printf 'IS_UNDATED=false\n'
      fi
      ;;
    *)
      printf 'LAST_VERIFIED=\n'
      printf 'IS_STALE=false\n'
      printf 'IS_UNDATED=true\n'
      ;;
  esac
  exit 0
fi

if [ -z "$MAX_SWEEP" ]; then
  if [ -x "$CASCADE" ]; then
    MAX_SWEEP=$("$CASCADE" --default 5 dossier.refresh.maxStaleDocsPerSweep 2>/dev/null)
  else
    MAX_SWEEP=5
  fi
fi
case "$MAX_SWEEP" in ''|*[!0-9]*) MAX_SWEEP=5 ;; esac

TODAY_S=$(date -u +%s)
STALE=0
UNDATED=0
OLDEST=""

TMPDIR_SC=$(mktemp -d -t dossier-staleness.XXXXXX) || {
  echo "dossier-staleness-check: cannot create a temporary directory" >&2
  exit 2
}
trap 'rm -rf "$TMPDIR_SC" 2>/dev/null' EXIT
STALE_LIST="$TMPDIR_SC/stale.tsv"
: >"$STALE_LIST"

# The 23 canonical documents bin/dossier-evidence.sh recognizes. A sweep's
# re-verification slots are bounded (MAX_SWEEP), so a stray non-canonical
# markdown file (a README, a scratch note) with an old or missing
# last-verified date must not consume a sweep slot that starves a genuinely
# stale canonical document — membership in this list gates SWEEP eligibility
# only. It does NOT gate the STALE/UNDATED/OLDEST scalar counts below: those
# must keep counting every *.md under OUTPUT_ROOT exactly as the pre-existing
# walk did, so status.md's dashboard contract does not silently change
# meaning for a package that has non-canonical markdown files in it.
CANONICAL_DOCS='00-control/documentation-index.md
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
07-verification/documentation-verification-report.md'

is_canonical_doc() {
  printf '%s\n' "$CANONICAL_DOCS" | grep -Fxq "$1"
}

# Same field order and skip/continue semantics as commands/status.md's former
# inline loop, byte-for-byte, so its emitted counters do not change meaning.
# STALE_LIST stores package-relative paths ($REL, never $OUTPUT_ROOT/$REL) —
# every downstream consumer (dossier-blast-radius.sh --stale-docs,
# commands/refresh.md) expects package-relative, matching
# dossier-evidence.sh's CANONICAL_DOCS convention.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#"$OUTPUT_ROOT"/}"
  lv=$(parse_last_verified "$f")
  case "$lv" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) UNDATED=$((UNDATED + 1)); continue ;;
  esac
  # BSD and GNU date take different flags; try both rather than assuming.
  lv_s=$(date -j -f "%Y-%m-%d" "$lv" +%s 2>/dev/null || date -d "$lv" +%s 2>/dev/null || echo "")
  if [ -z "$lv_s" ]; then
    # Shape-valid but not a real calendar date (e.g. 2024-13-45) — no
    # evidence anyone actually verified this document, same as missing.
    UNDATED=$((UNDATED + 1))
    continue
  fi
  age=$(( (TODAY_S - lv_s) / 86400 ))
  if [ "$age" -gt "$STALE_DAYS" ]; then
    STALE=$((STALE + 1))
    is_canonical_doc "$rel" && printf '%s\t%s\n' "$age" "$rel" >>"$STALE_LIST"
  fi
  if [ -z "$OLDEST" ] || [ "$lv" \< "$OLDEST" ]; then OLDEST="$lv"; fi
done <<EOF
$(find "$OUTPUT_ROOT" -name '*.md' -type f 2>/dev/null)
EOF

SWEEP_LIST=""
if [ -s "$STALE_LIST" ]; then
  SWEEP_LIST=$(sort -t "$(printf '\t')" -k1,1nr "$STALE_LIST" | head -n "$MAX_SWEEP" | cut -f2 | paste -sd, -)
fi

printf 'STALENESS_THRESHOLD_DAYS=%s\n' "$STALE_DAYS"
printf 'DOCUMENTS_STALE=%s\n' "$STALE"
printf 'DOCUMENTS_UNDATED=%s\n' "$UNDATED"
printf 'OLDEST_VERIFICATION=%s\n' "${OLDEST:-none}"
printf 'MAX_STALE_DOCS_PER_SWEEP=%s\n' "$MAX_SWEEP"
printf 'STALE_DOCS_FOR_SWEEP=%s\n' "$SWEEP_LIST"

exit 0
