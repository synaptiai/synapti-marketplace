#!/usr/bin/env bash
# dossier-gate.sh — evaluate the seventeen release-gate conditions.
#
# NORMATIVE CONTRACT (references/release-gate-conditions.md):
#
#   Failing is decidable from a subset. Passing is not.
#
# Ten conditions are mechanical and decidable here. Seven are judgment and
# require the dossier-scorer verdict file. One broken link is enough to prove a
# package is NOT releasable; no amount of mechanical checking proves it IS,
# because the judgment set includes both scorecard conditions and three of the
# four "must never appear" rules. A script that emitted PASS on mechanics alone
# would certify a package whose planned features are documented as shipped and
# whose targets are printed as measurements, having read neither.
#
# Therefore this script STRUCTURALLY REFUSES to emit PASS without a valid
# scorer verdict file. Absent, stale, revision-mismatched, round-mismatched, or
# silent on any judgment condition => INCONCLUSIVE, never PASS.
#
# Usage:
#   dossier-gate.sh [--output-root <path>] [--run-id <id>] [--verdict <path>]
#                   [--json] [--strict] [--quiet]
#
# Exit: 0 PASS · 1 FAIL · 2 usage error · 3 INCONCLUSIVE (--strict maps 3 -> 1)

set -uo pipefail

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RESOLVER="$SELF_DIR/dossier-resolve-config.sh"

OUTPUT_ROOT=""
RUN_ID=""
VERDICT=""
WANT_JSON=0
STRICT=0
QUIET=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --output-root) [ $# -lt 2 ] && { echo "dossier-gate: --output-root requires a path" >&2; exit 2; }
                   OUTPUT_ROOT="$2"; shift 2 ;;
    --run-id)      [ $# -lt 2 ] && { echo "dossier-gate: --run-id requires a value" >&2; exit 2; }
                   RUN_ID="$2"; shift 2 ;;
    --verdict)     [ $# -lt 2 ] && { echo "dossier-gate: --verdict requires a path" >&2; exit 2; }
                   VERDICT="$2"; shift 2 ;;
    --json)   WANT_JSON=1; shift ;;
    --strict) STRICT=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "dossier-gate: unknown argument: $1" >&2; exit 2 ;;
  esac
done

resolve() { if [ -x "$RESOLVER" ]; then "$RESOLVER" --default "$2" "$1"; else printf '%s' "$2"; fi; }

[ -z "$OUTPUT_ROOT" ] && OUTPUT_ROOT=$(resolve dossier.project.outputRoot "docs/dossier")
MIN_SCORE=$(resolve dossier.gate.minScore 95)
MIN_DIM_PCT=$(resolve dossier.gate.minDimensionPercent 80)
PINNED_VERSION=$(resolve dossier.project.versionOrCommit "auto")

CONTROL="$OUTPUT_ROOT/00-control"
REPORT="$OUTPUT_ROOT/07-verification/documentation-verification-report.md"

if [ ! -d "$OUTPUT_ROOT" ]; then
  echo "GATE_VERDICT=not ready"
  echo "GATE_ERROR=no package at $OUTPUT_ROOT"
  exit 1
fi

# Locate the verdict file. Default location is per the normative contract.
if [ -z "$VERDICT" ]; then
  if [ -n "$RUN_ID" ]; then
    VERDICT=".dossier/runs/$RUN_ID/scorer-verdict.md"
  else
    VERDICT=$(ls -1d .dossier/runs/*/scorer-verdict.md 2>/dev/null | sort | tail -1)
  fi
fi

RESULTS_FILE=$(mktemp -t dossier-gate.XXXXXX) || { echo "dossier-gate: cannot create temp file" >&2; exit 2; }
trap 'rm -f "$RESULTS_FILE" 2>/dev/null' EXIT

MECH_FAIL=0
record() { # id | tag | result | source | evidence
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$RESULTS_FILE"
  if [ "$3" = "FAIL" ]; then MECH_FAIL=$((MECH_FAIL + 1)); fi
}

# =============================================================================
# MECHANICAL CONDITIONS — decidable from repository state alone
# =============================================================================

# G03 — no unresolved Critical or High finding
if [ -f "$REPORT" ]; then
  OPEN_CH=$(grep -cE '^\|.*\b(Critical|High)\b.*\b(Open|Blocked)\b' "$REPORT" 2>/dev/null || true)
  [ -z "$OPEN_CH" ] && OPEN_CH=0
  if [ "$OPEN_CH" -eq 0 ]; then
    record G03 mechanical PASS script "0 open Critical/High findings"
  else
    record G03 mechanical FAIL script "$OPEN_CH open Critical/High findings in $REPORT"
  fi
else
  record G03 mechanical FAIL script "no verification report at $REPORT"
fi

# G05 — every required human approval recorded
APPROVAL_REQ=$(resolve dossier.disclosure.publicClaimApproval "required")
CLAIMS="$CONTROL/claim-and-disclosure-register.md"
if [ "$APPROVAL_REQ" != "required" ]; then
  record G05 mechanical PASS script "publicClaimApproval=$APPROVAL_REQ"
elif [ -f "$CLAIMS" ]; then
  PENDING=$(grep -c '^| *CL-.*| *pending *|' "$CLAIMS" 2>/dev/null || true)
  [ -z "$PENDING" ] && PENDING=0
  NEEDS_OWNER=0
  AQ="$CONTROL/assumptions-questions-and-contradictions.md"
  if [ -f "$AQ" ]; then
    NEEDS_OWNER=$(grep -c 'needs-owner' "$AQ" 2>/dev/null || true)
    [ -z "$NEEDS_OWNER" ] && NEEDS_OWNER=0
  fi
  if [ "$PENDING" -eq 0 ] && [ "$NEEDS_OWNER" -eq 0 ]; then
    record G05 mechanical PASS script "0 pending approvals, 0 needs-owner items"
  else
    record G05 mechanical FAIL script "$PENDING pending claim approvals, $NEEDS_OWNER needs-owner items"
  fi
else
  record G05 mechanical FAIL script "no claim register at $CLAIMS"
fi

# G06 — no secret, credential, personal data, or prohibited disclosure present
if [ -x "$SELF_DIR/dossier-claim-scan.sh" ]; then
  "$SELF_DIR/dossier-claim-scan.sh" --output-root "$OUTPUT_ROOT" --quiet >/dev/null 2>&1
  SCAN_RC=$?
  if [ "$SCAN_RC" -eq 2 ]; then
    record G06 mechanical FAIL script "dossier-claim-scan.sh detected leakage (exit 2)"
  else
    record G06 mechanical PASS script "no leakage patterns matched"
  fi
else
  record G06 mechanical FAIL script "dossier-claim-scan.sh missing — cannot certify disclosure safety"
fi

# G08 — canonical coverage 100%
if [ -x "$SELF_DIR/dossier-package-check.sh" ]; then
  if "$SELF_DIR/dossier-package-check.sh" --output-root "$OUTPUT_ROOT" --quiet >/dev/null 2>&1; then
    record G08 mechanical PASS script "all 23 canonical files present with valid headers"
  else
    record G08 mechanical FAIL script "dossier-package-check.sh reported structural findings"
  fi
else
  record G08 mechanical FAIL script "dossier-package-check.sh missing — cannot certify coverage"
fi

# G09 — every material internal claim has a state and locator
if [ -x "$SELF_DIR/dossier-ledger-lint.sh" ]; then
  if "$SELF_DIR/dossier-ledger-lint.sh" --output-root "$OUTPUT_ROOT" --quiet >/dev/null 2>&1; then
    record G09 mechanical PASS script "ledger lint clean"
  else
    record G09 mechanical FAIL script "dossier-ledger-lint.sh reported errors"
  fi
else
  record G09 mechanical FAIL script "dossier-ledger-lint.sh missing"
fi

# G10 — every public claim maps to V/C disclosure-approved evidence
# Mechanical precondition only: proves every REGISTERED claim is backed.
# Whether every public SENTENCE was registered is G04 (judgment).
if [ -f "$CLAIMS" ] && [ -f "$CONTROL/evidence-ledger.md" ]; then
  BAD=0
  while IFS= read -r row; do
    case "$row" in *"| approved |"*|*"|approved|"*) ;; *) continue ;; esac
    for ev in $(printf '%s' "$row" | grep -oE 'EV-[0-9]{4,}' | sort -u); do
      LR=$(grep -m1 "^| *$ev " "$CONTROL/evidence-ledger.md" 2>/dev/null)
      [ -z "$LR" ] && { BAD=$((BAD + 1)); continue; }
      ST=$(printf '%s' "$LR" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
      case "$ST" in V|C) ;; *) BAD=$((BAD + 1)) ;; esac
    done
  done < <(awk '
    /^## / { skip = ($0 ~ /^## *(Rejected|Withdrawn)/) ? 1 : 0 }
    !skip && /^\| *CL-/ { print }
  ' "$CLAIMS" 2>/dev/null)
  if [ "$BAD" -eq 0 ]; then
    record G10 mechanical PASS script "all approved claims cite V/C evidence"
  else
    record G10 mechanical FAIL script "$BAD approved claim(s) cite missing or non-V/C evidence"
  fi
else
  record G10 mechanical FAIL script "claim register or evidence ledger missing"
fi

# G11 — internal links, document paths, and diagram syntax validate
BROKEN=0
while IFS= read -r mdfile; do
  while IFS= read -r target; do
    case "$target" in http*|'#'*|mailto:*|'') continue ;; esac
    t=${target%%#*}
    [ -z "$t" ] && continue
    d=$(dirname "$mdfile")
    [ -e "$d/$t" ] || [ -e "$t" ] || BROKEN=$((BROKEN + 1))
  done < <(grep -oE '\]\([^)]+\)' "$mdfile" 2>/dev/null | sed -e 's/^](//' -e 's/)$//')
done < <(find "$OUTPUT_ROOT" -name '*.md' -type f 2>/dev/null)

UNCLOSED=0
while IFS= read -r mdfile; do
  O=$(grep -c '^```mermaid' "$mdfile" 2>/dev/null || true)
  F=$(grep -c '^```' "$mdfile" 2>/dev/null || true)
  [ -z "$O" ] && O=0; [ -z "$F" ] && F=0
  [ "$O" -gt 0 ] && [ $((F % 2)) -ne 0 ] && UNCLOSED=$((UNCLOSED + 1))
done < <(find "$OUTPUT_ROOT" -name '*.md' -type f 2>/dev/null)

if [ "$BROKEN" -eq 0 ] && [ "$UNCLOSED" -eq 0 ]; then
  record G11 mechanical PASS script "links resolve; diagram fences balanced"
else
  record G11 mechanical FAIL script "$BROKEN broken link(s), $UNCLOSED file(s) with unbalanced fences"
fi

# G12 — commands and examples executed or visibly marked not executed
ONBOARD="$OUTPUT_ROOT/04-operating/onboarding-and-local-development.md"
if [ -f "$ONBOARD" ]; then
  CMDBLOCKS=$(grep -cE '^```(bash|sh|shell|console)' "$ONBOARD" 2>/dev/null || true)
  MARKS=$(grep -cE '\b(verified|partially verified|not executed)\b' "$ONBOARD" 2>/dev/null || true)
  [ -z "$CMDBLOCKS" ] && CMDBLOCKS=0; [ -z "$MARKS" ] && MARKS=0
  if [ "$CMDBLOCKS" -eq 0 ] || [ "$MARKS" -gt 0 ]; then
    record G12 mechanical PASS script "$CMDBLOCKS command block(s), $MARKS execution marking(s)"
  else
    record G12 mechanical FAIL script "$CMDBLOCKS command block(s) with no execution marking"
  fi
else
  record G12 mechanical FAIL script "no onboarding document at $ONBOARD"
fi

# G16 — unresolved uncertainty and source limitations are visible
AQ="$CONTROL/assumptions-questions-and-contradictions.md"
if [ -f "$AQ" ] && [ -f "$CONTROL/evidence-ledger.md" ]; then
  HAS_AQ=$(grep -c '^| *AQ-' "$AQ" 2>/dev/null || true)
  HAS_LIMITS=$(grep -ciE 'not executed|inaccessible|unavailable|limitation' "$CONTROL/evidence-ledger.md" 2>/dev/null || true)
  [ -z "$HAS_AQ" ] && HAS_AQ=0; [ -z "$HAS_LIMITS" ] && HAS_LIMITS=0
  # A package claiming zero unknowns AND zero stated limitations has almost
  # certainly not looked, rather than looked and found nothing.
  if [ "$HAS_AQ" -gt 0 ] || [ "$HAS_LIMITS" -gt 0 ]; then
    record G16 mechanical PASS script "$HAS_AQ open question(s), $HAS_LIMITS stated limitation(s)"
  else
    record G16 mechanical FAIL script "no open questions and no stated source limitations — implausible; verify the registers were populated"
  fi
else
  record G16 mechanical FAIL script "registers missing"
fi

# G17 — reviewer-pass independence method disclosed, including model diversity
#
# The protocol calls this disclosure required, and the package's own evidence
# standard turns on it: three passes that shared one model decorrelate lenses
# but not model-level blind spots. Without this condition a package could pass
# every other one while omitting the sentence that tells a reader how much the
# verification is actually worth.
if [ -f "$REPORT" ]; then
  HAS_METHOD=$(grep -c '^## Reviewer-pass independence method' "$REPORT" 2>/dev/null || true)
  HAS_DIVERSITY=$(grep -c '^Model diversity:' "$REPORT" 2>/dev/null || true)
  [ -z "$HAS_METHOD" ] && HAS_METHOD=0
  [ -z "$HAS_DIVERSITY" ] && HAS_DIVERSITY=0
  if [ "$HAS_METHOD" -gt 0 ] && [ "$HAS_DIVERSITY" -gt 0 ]; then
    record G17 mechanical PASS script "independence method and model-diversity line present"
  else
    record G17 mechanical FAIL script "verification report is missing the independence method heading ($HAS_METHOD) or the 'Model diversity:' line ($HAS_DIVERSITY)"
  fi
else
  record G17 mechanical FAIL script "no verification report at $REPORT"
fi

# =============================================================================
# JUDGMENT CONDITIONS — require the scorer verdict file
# =============================================================================
JUDGMENT_IDS="G01 G02 G04 G07 G13 G14 G15"
VERDICT_OK=0
VERDICT_REASON=""

if [ -z "$VERDICT" ] || [ ! -f "$VERDICT" ]; then
  VERDICT_REASON="no scorer verdict file (looked at: ${VERDICT:-.dossier/runs/*/scorer-verdict.md})"
else
  VERDICT_OK=1
  # Revision must match: a verdict against a different revision is neither
  # true nor false about this package.
  if [ "$PINNED_VERSION" != "auto" ] && [ -n "$PINNED_VERSION" ]; then
    grep -q "$PINNED_VERSION" "$VERDICT" 2>/dev/null || {
      VERDICT_OK=0
      VERDICT_REASON="verdict does not name the pinned revision $PINNED_VERSION"
    }
  fi
  # Silence must not read as assent.
  if [ "$VERDICT_OK" -eq 1 ]; then
    for gid in $JUDGMENT_IDS; do
      grep -qE "^\|? *$gid\b.*\b(PASS|FAIL)\b" "$VERDICT" 2>/dev/null || {
        VERDICT_OK=0
        VERDICT_REASON="verdict is silent on $gid"
        break
      }
    done
  fi
  if [ "$VERDICT_OK" -eq 1 ]; then
    grep -qE '^\|? *[0-9]+ *\|' "$VERDICT" 2>/dev/null || {
      VERDICT_OK=0
      VERDICT_REASON="verdict carries no per-dimension score table"
    }
  fi
fi

if [ "$VERDICT_OK" -eq 1 ]; then
  for gid in $JUDGMENT_IDS; do
    LINE=$(grep -m1 -E "^\|? *$gid\b" "$VERDICT" 2>/dev/null)
    case "$LINE" in
      *FAIL*) record "$gid" judgment FAIL verdict "scorer: FAIL" ;;
      *PASS*) record "$gid" judgment PASS verdict "scorer: PASS" ;;
    esac
  done
else
  for gid in $JUDGMENT_IDS; do
    record "$gid" judgment INCONCLUSIVE none "$VERDICT_REASON"
  done
fi

# =============================================================================
# Verdict
# =============================================================================
FAILED=$(awk -F'\t' '$3=="FAIL"{printf "%s,",$1}' "$RESULTS_FILE" | sed 's/,$//')
FAIL_COUNT=$(awk -F'\t' '$3=="FAIL"' "$RESULTS_FILE" | wc -l | tr -d ' ')
INCONC_COUNT=$(awk -F'\t' '$3=="INCONCLUSIVE"' "$RESULTS_FILE" | wc -l | tr -d ' ')

if [ "$FAIL_COUNT" -gt 0 ]; then
  RESULT="FAIL"; STATUS="not ready"; CODE=1
elif [ "$INCONC_COUNT" -gt 0 ]; then
  # Never PASS, and never "conditionally ready": "we did not check" is an
  # absence of assurance, not a condition to attach.
  RESULT="INCONCLUSIVE"; STATUS="not ready"; CODE=3
else
  RESULT="PASS"; STATUS="release-ready"; CODE=0
fi

if [ "$WANT_JSON" -eq 1 ]; then
  printf '{"result":"%s","status":"%s","min_score":%s,"min_dimension_percent":%s,' \
    "$RESULT" "$STATUS" "$MIN_SCORE" "$MIN_DIM_PCT"
  printf '"failed_conditions":"%s","verdict_file":"%s","verdict_valid":%s,"conditions":[' \
    "$FAILED" "${VERDICT:-}" "$VERDICT_OK"
  first=1
  while IFS=$'\t' read -r id tag res src ev; do
    [ $first -eq 0 ] && printf ','
    first=0
    esc=$(printf '%s' "$ev" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '{"id":"%s","tag":"%s","result":"%s","source":"%s","evidence":"%s"}' \
      "$id" "$tag" "$res" "$src" "$esc"
  done < <(sort "$RESULTS_FILE")
  printf ']}\n'
elif [ "$QUIET" -eq 0 ]; then
  echo "GATE_RESULT=$RESULT"
  echo "GATE_VERDICT=$STATUS"
  echo "GATE_FAILED_CONDITIONS=${FAILED:-none}"
  echo "GATE_INCONCLUSIVE_COUNT=$INCONC_COUNT"
  echo "SCORER_VERDICT_PRESENT=$([ "$VERDICT_OK" -eq 1 ] && echo yes || echo no)"
  [ "$VERDICT_OK" -eq 0 ] && echo "SCORER_VERDICT_REASON=$VERDICT_REASON"
  echo ""
  printf '%-5s %-11s %-13s %-8s %s\n' "ID" "TAG" "RESULT" "SOURCE" "EVIDENCE"
  sort "$RESULTS_FILE" | while IFS=$'\t' read -r id tag res src ev; do
    printf '%-5s %-11s %-13s %-8s %s\n' "$id" "$tag" "$res" "$src" "$ev"
  done
  if [ "$INCONC_COUNT" -gt 0 ]; then
    echo ""
    echo "The judgment conditions were not evaluated. Mechanical checks alone cannot"
    echo "certify a package — run /dossier:gate to dispatch dossier-scorer, or pass"
    echo "--verdict <path> if a verdict already exists."
  fi
fi

if [ "$CODE" -eq 3 ] && [ "$STRICT" -eq 1 ]; then exit 1; fi
exit "$CODE"
