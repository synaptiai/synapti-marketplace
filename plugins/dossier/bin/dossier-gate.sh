#!/usr/bin/env bash
# dossier-gate.sh — evaluate the nineteen release-gate conditions.
#
# NORMATIVE CONTRACT (references/release-gate-conditions.md):
#
#   Failing is decidable from a subset. Passing is not.
#
# Twelve conditions are mechanical and decidable here. Seven are judgment and
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
ROUND=""
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
    --round)       [ $# -lt 2 ] && { echo "dossier-gate: --round requires a value" >&2; exit 2; }
                   ROUND="$2"; shift 2 ;;
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
  SCAN_OUT=$("$SELF_DIR/dossier-claim-scan.sh" --output-root "$OUTPUT_ROOT" --quiet 2>&1)
  SCAN_RC=$?
  # 2 and 3 mean different things and must not be published as the same finding.
  # A missing public directory is an incomplete package, not a disclosure
  # incident, and naming it one puts a security claim in the record that is not
  # true.
  case "$SCAN_RC" in
    2) record G06 mechanical FAIL script "dossier-claim-scan.sh detected leakage" ;;
    3) SCAN_WHY=$(printf '%s' "$SCAN_OUT" | sed -n 's/^CLAIM_SCAN_ERROR=//p' | head -1)
       record G06 mechanical INCONCLUSIVE script "disclosure scan could not run: ${SCAN_WHY:-unknown error}" ;;
    *) record G06 mechanical PASS script "no leakage patterns matched" ;;
  esac
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

# G18 — no hard-category prose-clarity violation exists in the package
#
# Purely mechanical: reads dossier-prose-lint.sh's own JSON, never the scorer
# verdict file, so it cannot inherit the class of bug that lived in the
# judgment-verdict parsing loop below. Two independent readings of the same
# run are cross-checked before recording a result — the script's exit code and
# its parsed blocking_violations count — because a script that disagrees with
# its own exit code is a linter defect, not a result to pick favorably from.
if [ -x "$SELF_DIR/dossier-prose-lint.sh" ]; then
  LINT_OUT=$("$SELF_DIR/dossier-prose-lint.sh" --output-root "$OUTPUT_ROOT" --json 2>&1)
  LINT_RC=$?
  # Anchored to the start of the object: the JSON also carries one
  # "blocking_violations" per file in its files[] array, and an unanchored
  # greedy match would silently read the LAST file's count instead of the
  # top-level total.
  LINT_COUNT=$(printf '%s' "$LINT_OUT" | sed -n 's/^{"blocking_violations":\([0-9]*\).*/\1/p' | head -1)
  [ -z "$LINT_COUNT" ] && LINT_COUNT=-1
  if [ "$LINT_COUNT" -lt 0 ]; then
    record G18 mechanical FAIL script "dossier-prose-lint.sh produced no parseable blocking_violations count"
  elif [ "$LINT_COUNT" -eq 0 ] && [ "$LINT_RC" -eq 0 ]; then
    record G18 mechanical PASS script "0 hard-category prose-clarity violations"
  elif [ "$LINT_COUNT" -gt 0 ] && [ "$LINT_RC" -ne 0 ]; then
    record G18 mechanical FAIL script "$LINT_COUNT hard-category prose-clarity violation(s)"
  else
    record G18 mechanical FAIL script "exit code ($LINT_RC) and reported count ($LINT_COUNT) disagree — linter defect, not a pass"
  fi
else
  record G18 mechanical FAIL script "dossier-prose-lint.sh missing — cannot certify prose clarity"
fi

# G19 — no unresolved Critical/High dependency vulnerability lacks a recorded
# disposition
#
# Mechanical: reads vulnerability-finding rows in 00-control/evidence-ledger.md
# (written by the evidence-ledger skill from bin/dossier-vuln-evidence.sh's
# output — dossier never executes a scanner itself) and cross-references
# disposition against 04-operating/decisions-technical-debt-and-risks.md's
# EXISTING Risk register and Accepted risks tables — no new template table.
# Deliberately never reuses G03/findings.md: references/finding-schema.md
# scopes findings.md to documentation defects only, and a dependency
# vulnerability is a defect in the project, not the documentation.
#
# Zero vulnerability evidence recorded at all is INCONCLUSIVE, never PASS —
# matching commit 525cca5's ("#133") precedent that an unevaluated condition
# must never read as assent, and G06's own INCONCLUSIVE-on-could-not-run
# behaviour. This is a deliberate design choice (see .decisions/issue-136.md):
# every existing dossier package moves to `not ready` on this condition until
# vulnerability evidence is actually ingested, rather than passing silently.
trim_g19() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Identical to dossier-staleness-check.sh's validate_calendar_date() — kept as
# a verbatim copy rather than a cross-script `source`, matching this bin/
# directory's convention of independently invocable, self-contained scripts.
# Neither BSD `date -j` nor GNU `date -d` reject an out-of-range day-of-month
# (2026-06-31 silently rolls to 2026-07-01), so a target/review date is only
# accepted if it round-trips back to its original string.
#
# Deliberately omits `local` (unlike g19_row_cites below) — this function's
# body is byte-for-byte identical to its source, modulo the function name, so
# a future diff against dossier-staleness-check.sh's copy stays a clean
# comparison rather than picking up an unrelated stylistic divergence.
validate_calendar_date_g19() {
  _orig="$1" _epoch="$2"
  [ -n "$_epoch" ] || return 0
  _rt1=$(date -j -f %s "$_epoch" +%Y-%m-%d 2>/dev/null || echo "")
  _rt2=$(date -d "@$_epoch" +%Y-%m-%d 2>/dev/null || echo "")
  if [ "$_rt1" = "$_orig" ] || [ "$_rt2" = "$_orig" ]; then
    printf '%s\n' "$_epoch"
  fi
}

date_to_epoch_g19() {
  _d="$1"
  [ -n "$_d" ] || return 0
  _e=$(date -j -f "%Y-%m-%d" "$_d" +%s 2>/dev/null || date -d "$_d" +%s 2>/dev/null || echo "")
  [ -n "$_e" ] && validate_calendar_date_g19 "$_d" "$_e"
}

extract_section_g19() { # file | anchored heading regex, e.g. "^## Risk register"
  awk -v pat="$2" '$0 ~ pat {flag=1; next} /^## / {flag=0} flag' "$1" 2>/dev/null
}

# A citation cell may cite more than one id — the ledger's own inline
# citation grammar allows `[EV-0042]`, `[EV-0042, EV-0043]`, and the en-dash
# range form `[EV-0042–EV-0045]` (references/evidence-ledger-schema.md). A
# plain `grep "\[$EVID\]"` only matches the single-id form, so a genuinely
# disposed finding cited alongside another id in the same bracket would read
# as undisposed.
#
# Takes the CITATION CELL specifically (Risk register's Evidence column,
# Accepted risks' Risk ID column) — never the whole row. An earlier version
# matched against the entire row, which let an EV-#### id mentioned anywhere
# else on the row — coincidentally, in free-text Risk/Mitigation/Basis prose
# that carries no citation semantics — read as citing a DIFFERENT finding,
# falsely disposing it. Confirmed by live reproduction. Cell values (not
# table structure) may also contain no pipes — see the comment on
# `cells=($body)` below.
#
# Even scoped to the citation cell, matching is further scoped to text
# actually inside a `[...]` bracket span — the ledger's own citation grammar
# (references/evidence-ledger-schema.md) never cites outside brackets. The
# same free-text-collision risk that motivated the cell-scoping above applies
# WITHIN the cell too: a cell reading `[EV-0002] and prior related range
# EV-0050-EV-0150` legitimately cites only EV-0002, but an id/range search
# over the cell's raw text would also match the un-bracketed "EV-0050-EV-0150"
# mentioned in trailing prose and falsely dispose an unrelated finding.
# Confirmed by live reproduction.
g19_row_cites() { # citation-cell | evid
  local _row="$1" _evid="$2" _span _inner _token _ids_in_token _id_count _lo _hi _en
  while IFS= read -r _span; do
    [ -n "$_span" ] || continue
    # Strip the surrounding brackets, then split on the schema's LIST
    # separator (comma or semicolon) BEFORE ever looking for a range. Doing
    # this the other way round — searching the whole span for two ids
    # separated by any non-alphanumeric run — let the list separator itself
    # satisfy the range pattern: `[EV-0042, EV-0099]` (two ids the schema
    # documents as a LIST, each cited on its own) parsed as an inclusive
    # RANGE spanning everything between them, falsely disposing an
    # unrelated, genuinely undisposed id like EV-0050 that merely fell
    # between the two endpoints. Confirmed by live reproduction — this was
    # the fourth false-disposition bug found in this function by successive
    # narrowing of a single matcher, which is what motivated parsing the
    # grammar instead of excluding one more character. Splitting on the list
    # separator first means a range can only ever be found within a single
    # comma/semicolon-free token, where exactly two ids can only mean the
    # explicit range form.
    _inner=$(printf '%s\n' "$_span" | sed -e 's/^\[//' -e 's/\]$//')
    while IFS= read -r _token; do
      _token=$(trim_g19 "$_token")
      [ -n "$_token" ] || continue
      _ids_in_token=$(printf '%s\n' "$_token" | grep -oE 'EV-[0-9]{4,}')
      _id_count=$(printf '%s\n' "$_ids_in_token" | grep -c .)
      if [ "$_id_count" -eq 1 ]; then
        printf '%s\n' "$_ids_in_token" | grep -qxF "$_evid" && return 0
      elif [ "$_id_count" -eq 2 ]; then
        _lo=$(printf '%s\n' "$_ids_in_token" | sed -n '1p' | grep -oE '[0-9]{4,}')
        _hi=$(printf '%s\n' "$_ids_in_token" | sed -n '2p' | grep -oE '[0-9]{4,}')
        _en=$(printf '%s' "$_evid" | grep -oE '[0-9]{4,}')
        if [ -n "$_lo" ] && [ -n "$_hi" ] && [ -n "$_en" ]; then
          # 10# forces base-10: a zero-padded id like 0099 is otherwise read
          # as an invalid octal literal by bash arithmetic.
          [ "$((10#$_en))" -ge "$((10#$_lo))" ] && [ "$((10#$_en))" -le "$((10#$_hi))" ] && return 0
        fi
      fi
    done < <(printf '%s\n' "$_inner" | tr ',;' '\n\n')
  done < <(printf '%s\n' "$_row" | grep -oE '\[[^]]*\]')
  return 1
}

LEDGER="$CONTROL/evidence-ledger.md"
RISKS="$OUTPUT_ROOT/04-operating/decisions-technical-debt-and-risks.md"

# A cell that is non-empty but is one of the template's own placeholder
# conventions (an em-dash/hyphen "not applicable" marker, or an unfilled
# `{fill}` token) must never count as a real value. A denylist check that
# only excluded "—"/"-" let an unfilled `{fill}` cell — non-empty, and not
# literally either dash — pass as a real owner/accepter/basis. Confirmed by
# live reproduction against an unfilled template row.
g19_filled() {
  local _v="$1"
  [ -n "$_v" ] || return 1
  case "$_v" in
    "—"|"-"|"{fill}"|"{fill"*"}") return 1 ;;
  esac
  return 0
}

if [ ! -f "$LEDGER" ]; then
  record G19 mechanical INCONCLUSIVE script "no evidence ledger at $LEDGER — vulnerability-scan evidence could not be evaluated"
else
  COVERAGE_ROWS=$(grep -ci 'vuln-scan-coverage' "$LEDGER" 2>/dev/null || true)
  [ -z "$COVERAGE_ROWS" ] && COVERAGE_ROWS=0
  FINDING_ROWS=$(grep -ci 'vuln-finding ' "$LEDGER" 2>/dev/null || true)
  [ -z "$FINDING_ROWS" ] && FINDING_ROWS=0
  PARSE_ERROR_ROW=$(grep -im1 'vuln-scan-coverage status=parse-error' "$LEDGER" 2>/dev/null)
  # A whole-scan parse failure (status=parse-error) is not the only way the
  # finding set can be incomplete. dossier-vuln-evidence.sh's per-record fault
  # isolation lets the scan AS A WHOLE parse while one or more individual
  # records inside it did not — evidence-ledger-schema.md's own grammar has
  # the evidence-ledger skill record that as status=partial. A condition
  # whose materiality is unknown (an unparsed record could have been
  # Critical/High) must never read as clean just because every record that
  # DID parse happens to be disposed — the same "unevaluated must never read
  # as assent" principle the parse-error branch already applies, extended to
  # the case where SOME of the scan was readable and some was not.
  PARTIAL_ROW=$(grep -im1 'vuln-scan-coverage status=partial' "$LEDGER" 2>/dev/null)
  # A finding whose severity could not be derived gets its own
  # `vuln-finding-unresolved` row while the coverage row can still read
  # status=parsed: the SCAN parsed fine, one RECORD's materiality didn't.
  # dossier-vuln-evidence.sh's own header flags the osv-scanner
  # CVSS-vector-vs-bare-score assumption as unverified against live tool
  # output — this is plausibly the mainline path against real osv-scanner
  # output, not an edge case. Confirmed by live reproduction: a ledger with
  # status=parsed, one unresolved row, and zero severity=Critical|High rows
  # fell through every prior branch to a vacuous PASS. Checked below the
  # main disposition loop, not here, so it never overrides a genuine FAIL
  # from a confirmed, undisposed Critical/High finding — unresolved severity
  # means "materiality unknown", which is worse than PASS but better than a
  # FAIL naming a specific disposed-or-not finding.
  UNRESOLVED_ROW=$(grep -im1 'vuln-finding-unresolved' "$LEDGER" 2>/dev/null)

  if [ "$COVERAGE_ROWS" -eq 0 ] && [ "$FINDING_ROWS" -eq 0 ]; then
    record G19 mechanical INCONCLUSIVE script "no vulnerability-scan evidence recorded in the ledger — ingest an existing scan artifact via dossier-vuln-evidence.sh, or record why none is available"
  elif [ -n "$PARSE_ERROR_ROW" ]; then
    PE_EVID=$(printf '%s\n' "$PARSE_ERROR_ROW" | grep -oE 'EV-[0-9]{4,}' | head -1)
    record G19 mechanical INCONCLUSIVE script "the vulnerability-scan artifact could not be parsed (${PE_EVID:-no EV row found}) — the finding set is incomplete, not clean"
  elif [ -n "$PARTIAL_ROW" ]; then
    PA_EVID=$(printf '%s\n' "$PARTIAL_ROW" | grep -oE 'EV-[0-9]{4,}' | head -1)
    record G19 mechanical INCONCLUSIVE script "the vulnerability scan parsed partially (${PA_EVID:-no EV row found}) — one or more records could not be normalized, so the finding set may be incomplete"
  else
    NOW_EPOCH_G19=$(date -u +%s)
    # An unreadable (as opposed to absent) risk register is a DIFFERENT
    # condition from "no disposition was recorded" — the former means
    # disposition genuinely could not be evaluated, the latter means it was
    # evaluated and found wanting. Conflating them let a permissions problem
    # read as an ordinary FAIL, misdirecting remediation toward triaging
    # findings that may in fact already be disposed in a file G19 simply
    # couldn't open.
    RISKS_UNREADABLE=0
    [ -f "$RISKS" ] && [ ! -r "$RISKS" ] && RISKS_UNREADABLE=1

    UNDISPOSED=""
    CONSUMED_FINDING_ROWS=0
    while IFS= read -r G19_ROW; do
      [ -n "$G19_ROW" ] || continue
      CONSUMED_FINDING_ROWS=$((CONSUMED_FINDING_ROWS + 1))
      # Case-insensitive on both the selection (below) and this extraction:
      # the ledger's `Notes` tags are authored by the evidence-ledger SKILL
      # (an LLM transcribing free text), not emitted by a script, so casing
      # drift ("severity=critical") is realistic rather than adversarial —
      # the same reasoning G16 already applies with its own `-ciE` selector.
      # Normalized back to canonical Title-case so downstream evidence text
      # is consistent regardless of source casing.
      G19_SEV_RAW=$(printf '%s\n' "$G19_ROW" | grep -oiE 'vuln-finding severity=(Critical|High)' | sed 's/.*severity=//')
      case "$(printf '%s' "$G19_SEV_RAW" | tr '[:upper:]' '[:lower:]')" in
        critical) G19_SEV="Critical" ;;
        high) G19_SEV="High" ;;
        *) continue ;;
      esac
      # Tolerant of up to 3 leading spaces before the pipe, matching CommonMark's
      # own table-row syntax (a row indented that far still renders identically,
      # so the selection grep above — deliberately unanchored, since it exists to
      # catch the row regardless of incidental leading whitespace — must not lose
      # the id extraction step to a stricter anchor than its own selection step
      # used. A selected row whose id still cannot be extracted is NEVER silently
      # dropped: it is recorded as its own unparseable-and-therefore-undisposed
      # entry, never allowed to vanish from the loop the way an omitted `record`
      # call let a condition vanish before commit 525cca5 ("#133").
      G19_EVID=$(printf '%s\n' "$G19_ROW" | grep -oE '^[[:space:]]{0,3}\| *EV-[0-9]{4,}' | grep -oE 'EV-[0-9]{4,}')
      if [ -z "$G19_EVID" ]; then
        UNDISPOSED="${UNDISPOSED}${UNDISPOSED:+, }<unparseable vuln-finding severity=$G19_SEV row — no EV-#### id could be extracted>"
        continue
      fi

      G19_DISPOSED=0

      # Risk register: ANY row citing EV-#### (a bracket may cite more than one
      # id — see g19_row_cites) with Category dependency|security, a filled
      # Owner, and a Status of mitigating|closed disposes the finding. Every
      # citing row is checked, not just the first, since an earlier triage row
      # citing the same id may not itself qualify while a later one does.
      if [ "$RISKS_UNREADABLE" -eq 0 ] && [ -f "$RISKS" ]; then
        while IFS= read -r RISK_ROW; do
          [ "$G19_DISPOSED" -eq 0 ] || break
          case "$RISK_ROW" in "|"*) ;; *) continue ;; esac
          body=${RISK_ROW#|}; body=${body%|}
          OLD_IFS=$IFS; IFS='|'; set -f
          # shellcheck disable=SC2206
          # A cell containing a literal, unescaped `|` desyncs this split — the
          # same documented limitation dossier-ledger-lint.sh's own row parser
          # carries (see its comment above `cells=($body)`); Risk register and
          # Accepted risks cells are held to the same no-raw-pipes constraint.
          cells=($body)
          set +f; IFS=$OLD_IFS
          if [ "${#cells[@]}" -eq 11 ]; then
            # Citation match is scoped to the Evidence cell specifically, never
            # the whole row. Checking the full row text let an EV-#### id
            # mentioned anywhere else on the row — coincidentally, in the
            # free-text Risk/Mitigation prose, which carries no citation
            # semantics — read as a citation belonging to a DIFFERENT finding
            # entirely, falsely disposing it. Confirmed by live reproduction:
            # a Risk register row for one finding whose "Risk" description
            # cell happened to mention another finding's id disposed that
            # other, genuinely-undisposed finding.
            g19_row_cites "${cells[7]}" "$G19_EVID" || continue
            RISK_CATEGORY=$(trim_g19 "${cells[2]}" | tr '[:upper:]' '[:lower:]')
            RISK_OWNER=$(trim_g19 "${cells[9]}")
            RISK_STATUS=$(trim_g19 "${cells[10]}" | tr '[:upper:]' '[:lower:]')
            case "$RISK_CATEGORY" in
              dependency|security)
                # An allowlist against the template's own closed enum
                # (open|mitigating|accepted|closed), not a denylist of the
                # single string "open" — a denylist disposed the finding for
                # ANY other value, including case variants ("Open"), unfilled
                # template placeholders ("{fill}"), and genuinely
                # non-dispositive statuses ("blocked", "reopened"). Confirmed
                # by live reproduction against both a capitalized value and an
                # unfilled placeholder.
                #
                # `accepted` is deliberately excluded here: the template
                # states acceptance requires a named human with the authority
                # to accept, which this table's bare Owner cell does not
                # establish. An accepted disposition must go through the
                # Accepted risks table below, with its
                # accepter/date/basis/review-date accountability fields —
                # this Risk register path covers only ownership-tracked
                # remediation that is in progress or already done.
                case "$RISK_STATUS" in
                  mitigating|closed)
                    g19_filled "$RISK_OWNER" && G19_DISPOSED=1
                    ;;
                esac
                ;;
            esac
          fi
        done < <(extract_section_g19 "$RISKS" '^## Risk register')
      fi

      # Accepted risks: ANY row citing EV-#### with a named accepter, a
      # calendar-valid acceptance date, a stated basis, and a calendar-valid
      # review date that has not yet elapsed.
      if [ "$G19_DISPOSED" -eq 0 ] && [ "$RISKS_UNREADABLE" -eq 0 ] && [ -f "$RISKS" ]; then
        while IFS= read -r ACC_ROW; do
          [ "$G19_DISPOSED" -eq 0 ] || break
          case "$ACC_ROW" in "|"*) ;; *) continue ;; esac
          body=${ACC_ROW#|}; body=${body%|}
          OLD_IFS=$IFS; IFS='|'; set -f
          # shellcheck disable=SC2206
          cells=($body)
          set +f; IFS=$OLD_IFS
          if [ "${#cells[@]}" -eq 6 ]; then
            # Citation match scoped to the "Risk ID" cell specifically — same
            # reasoning as the Risk register fix above: matching the whole row
            # let an EV-#### id mentioned in the free-text Basis-for-acceptance
            # prose falsely dispose an unrelated finding.
            g19_row_cites "${cells[0]}" "$G19_EVID" || continue
            ACC_ACCEPTER=$(trim_g19 "${cells[1]}")
            ACC_DATE=$(trim_g19 "${cells[2]}")
            ACC_BASIS=$(trim_g19 "${cells[3]}")
            ACC_REVIEW=$(trim_g19 "${cells[4]}")
            ACC_DATE_EPOCH=$(date_to_epoch_g19 "$ACC_DATE")
            ACC_REVIEW_EPOCH=$(date_to_epoch_g19 "$ACC_REVIEW")
            # A review date's whole purpose is to force periodic
            # re-affirmation of a risk acceptance — validating only that it
            # is CALENDAR-valid, never comparing it to "now", let an
            # acceptance from years ago dispose a Critical finding
            # permanently. Confirmed by live reproduction (a 2020 review
            # date still disposed a Critical finding today). Matches this
            # project's own established staleness-enforcement philosophy
            # (dossier-staleness-check.sh) rather than inventing a new one.
            if g19_filled "$ACC_ACCEPTER" && [ -n "$ACC_DATE_EPOCH" ] \
               && g19_filled "$ACC_BASIS" \
               && [ -n "$ACC_REVIEW_EPOCH" ] && [ "$ACC_REVIEW_EPOCH" -ge "$NOW_EPOCH_G19" ]; then
              G19_DISPOSED=1
            fi
          fi
        done < <(extract_section_g19 "$RISKS" '^## Accepted risks')
      fi

      if [ "$G19_DISPOSED" -eq 0 ]; then
        UNDISPOSED="${UNDISPOSED}${UNDISPOSED:+, }$G19_EVID ($G19_SEV)"
      fi
    done < <(grep -iE 'vuln-finding severity=(Critical|High)' "$LEDGER" 2>/dev/null)

    # A row counted by the loose FINDING_ROWS scan above but never consumed by
    # the (already case-insensitive) selection loop indicates formatting
    # drift beyond mere case — unexpected spacing around `=`, a stray
    # separator — that would otherwise let a genuine finding row go
    # completely unevaluated. Silently treating that as "nothing to see" is
    # the same "unevaluated must never read as assent" failure this whole
    # condition exists to prevent one level up; it is surfaced as
    # INCONCLUSIVE below rather than allowed to vanish.
    UNRECOGNIZED_FINDING_ROWS=$((FINDING_ROWS - CONSUMED_FINDING_ROWS))
    [ "$UNRECOGNIZED_FINDING_ROWS" -lt 0 ] && UNRECOGNIZED_FINDING_ROWS=0

    if [ -n "$UNDISPOSED" ]; then
      if [ "$RISKS_UNREADABLE" -eq 1 ]; then
        record G19 mechanical INCONCLUSIVE script "$RISKS exists but could not be read — disposition could not be evaluated for: $UNDISPOSED"
      else
        record G19 mechanical FAIL script "unresolved vulnerability finding(s) with no recorded disposition: $UNDISPOSED"
      fi
    elif [ -n "$UNRESOLVED_ROW" ]; then
      record G19 mechanical INCONCLUSIVE script "one or more vulnerability findings have unresolved severity — materiality unknown, not a clean scan"
    elif [ "$UNRECOGNIZED_FINDING_ROWS" -gt 0 ]; then
      record G19 mechanical INCONCLUSIVE script "$UNRECOGNIZED_FINDING_ROWS vulnerability-finding row(s) in the ledger did not match the expected severity=Critical|High tag format — could not be evaluated"
    else
      record G19 mechanical PASS script "vulnerability-scan evidence recorded; every Critical/High finding is disposed (resolved or explicitly risk-accepted)"
    fi
  fi
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
  # `auto` is the shipped default and the scoping skill promises it "resolves
  # the current SHA and pins it for the whole run". It did not: it was a
  # sentinel that switched the revision check off entirely, so on a default
  # configuration a verdict from any revision was accepted. Resolve it here to
  # the commit actually under evaluation rather than treating it as "no pin".
  EFFECTIVE_PIN="$PINNED_VERSION"
  if [ "$EFFECTIVE_PIN" = "auto" ]; then
    EFFECTIVE_PIN=$(git rev-parse --short HEAD 2>/dev/null || printf '')
    [ -n "$EFFECTIVE_PIN" ] || VERDICT_REASON="versionOrCommit is 'auto' but the revision could not be resolved"
  fi
  if [ -n "$EFFECTIVE_PIN" ]; then
    grep -q "$EFFECTIVE_PIN" "$VERDICT" 2>/dev/null || {
      VERDICT_OK=0
      VERDICT_REASON="verdict does not name the pinned revision $EFFECTIVE_PIN"
    }
  fi
  # A verdict from another round is not true or false about this one. The flag
  # was advertised in three commands' argument-hints and invoked verbatim in the
  # documented Phase 2 command while the parser rejected it, so the round pin
  # was both unenforced and un-runnable.
  if [ "$VERDICT_OK" -eq 1 ] && [ -n "$ROUND" ]; then
    grep -qiE "^\|? *Round[[:space:]]*[:|][[:space:]]*$ROUND\b" "$VERDICT" 2>/dev/null || {
      VERDICT_OK=0
      VERDICT_REASON="verdict does not name round $ROUND"
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
    # The SAME predicate the silence check used. Previously the silence check
    # required a PASS/FAIL token anywhere in the file while extraction took the
    # first line merely mentioning the id — so a verdict naming an id twice (a
    # summary row with an empty Result cell, then a later detail row carrying
    # the real word) satisfied the silence check on the second line and parsed
    # the first. The `case` matched neither token, `record` was never called,
    # and the condition disappeared from the output and from BOTH counters. A
    # dropped condition is worse than a silent one: silence is at least counted
    # as inconclusive, while this was counted as nothing at all, which is how a
    # PASS could be emitted for a package with a judgment condition nobody
    # evaluated — exactly what this script's header says cannot happen.
    LINE=$(grep -m1 -E "^\|? *$gid\b.*\b(PASS|FAIL)\b" "$VERDICT" 2>/dev/null)
    case "$LINE" in
      *FAIL*) record "$gid" judgment FAIL verdict "scorer: FAIL" ;;
      *PASS*) record "$gid" judgment PASS verdict "scorer: PASS" ;;
      *)      record "$gid" judgment INCONCLUSIVE verdict "verdict carries no decidable result for $gid" ;;
    esac
  done

  # Belt and braces: every judgment id must have produced exactly one row. If
  # the loop above ever fails to record one, the gate must not be able to reach
  # PASS on a condition that is simply absent from its own results.
  for gid in $JUDGMENT_IDS; do
    ROWS=$(grep -cE "^${gid}[[:space:]]" "$RESULTS_FILE" 2>/dev/null || true)
    [ -z "$ROWS" ] && ROWS=0
    if [ "$ROWS" -ne 1 ]; then
      record "$gid" judgment INCONCLUSIVE verdict "expected exactly one verdict row for $gid, found $ROWS"
    fi
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
# Split by tag, not just count: an INCONCLUSIVE judgment condition means "run
# dossier-scorer"; an INCONCLUSIVE mechanical condition (G06 when the
# disclosure scan could not run, G19 when vulnerability evidence is missing
# or incomplete — both pre-date and post-date this comment respectively, and
# more may be added later) means something else entirely, and a different
# something for each condition. Conflating them into one remedy would
# misdirect the reader — the exact "clear, specific reason" issue #136's AC2
# requires, generalized to every mechanical condition, not just G19.
JUDGMENT_INCONC_COUNT=$(awk -F'\t' '$2=="judgment" && $3=="INCONCLUSIVE"' "$RESULTS_FILE" | wc -l | tr -d ' ')
MECHANICAL_INCONC_IDS=$(awk -F'\t' '$2=="mechanical" && $3=="INCONCLUSIVE"{printf "%s,",$1}' "$RESULTS_FILE" | sed 's/,$//')

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
  if [ "$JUDGMENT_INCONC_COUNT" -gt 0 ]; then
    echo ""
    echo "The judgment conditions were not evaluated. Mechanical checks alone cannot"
    echo "certify a package — run /dossier:gate to dispatch dossier-scorer, or pass"
    echo "--verdict <path> if a verdict already exists."
  fi
  if [ -n "$MECHANICAL_INCONC_IDS" ]; then
    echo ""
    echo "Mechanical condition(s) $MECHANICAL_INCONC_IDS could not be evaluated — see the"
    echo "EVIDENCE column(s) above for what is missing. This is a different gap than an"
    echo "uncovered judgment set and has a different remedy for each condition."
  fi
fi

if [ "$CODE" -eq 3 ] && [ "$STRICT" -eq 1 ]; then exit 1; fi
exit "$CODE"
