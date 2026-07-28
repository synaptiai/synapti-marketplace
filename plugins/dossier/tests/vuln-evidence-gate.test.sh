#!/usr/bin/env bash
# Issue #136: vulnerability-scan output ingested as cited evidence
# (dossier-vuln-evidence.sh, AC1) and the G19 release-gate condition
# (dossier-gate.sh, AC2/AC3/AC4).
#
# dossier never executes a scanner. This suite proves the ingestion script
# correctly normalizes three pre-existing scan-output formats (SARIF,
# osv-scanner JSON, Dependabot alerts export) into cited evidence, and that
# the release gate correctly distinguishes "no evidence" (INCONCLUSIVE) from
# "resolved" (PASS) from "unresolved" (FAIL) — the exact bug class #133
# (commit 525cca5) fixed for the judgment-verdict path, now applied here.

_dossier_test_begin "vuln-evidence-gate"

VULN_SCRIPT="$(pwd)/plugins/dossier/bin/dossier-vuln-evidence.sh"
GATE="$(pwd)/plugins/dossier/bin/dossier-gate.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$VULN_SCRIPT" ]; then
  _dossier_assert_fail "$VULN_SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# =============================================================================
# Part 1 — dossier-vuln-evidence.sh: format detection, severity normalization,
# evidence citation (AC1)
# =============================================================================

FIXTURES=$(_dossier_safe_mktemp_dir "vuln-evidence-fixtures")

# --- SARIF: security-severity property drives CVSS bucketing ----------------
cat >"$FIXTURES/scan.sarif.json" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "example-sast", "version": "1.4.0"}},
      "results": [
        {
          "ruleId": "CVE-2024-11111",
          "message": {"text": "lodash prototype pollution"},
          "properties": {"security-severity": "9.8"},
          "locations": [{"physicalLocation": {"artifactLocation": {"uri": "package.json"}}}]
        },
        {
          "ruleId": "CVE-2024-22222",
          "message": {"text": "minor issue"},
          "properties": {"security-severity": "3.1"},
          "locations": [{"physicalLocation": {"artifactLocation": {"uri": "package.json"}}}]
        }
      ]
    }
  ]
}
EOF
OUT_SARIF=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.sarif.json 2>&1)
RC_SARIF=$?
assert_equal "0" "$RC_SARIF" "SARIF: a well-formed scan parses cleanly (exit 0)"
FORMAT_SARIF=$(printf '%s' "$OUT_SARIF" | jq -r '.scan.format' 2>/dev/null)
assert_equal "sarif" "$FORMAT_SARIF" "SARIF: format is correctly detected"
CRIT_COUNT=$(printf '%s' "$OUT_SARIF" | jq '[.findings[] | select(.severity == "Critical")] | length' 2>/dev/null)
assert_equal "1" "$CRIT_COUNT" "SARIF: security-severity 9.8 buckets to Critical, itemized"
CVE1_SEV=$(printf '%s' "$OUT_SARIF" | jq -r '.findings[] | select(.id == "CVE-2024-11111") | .severity' 2>/dev/null)
assert_equal "Critical" "$CVE1_SEV" "SARIF: CVE-2024-11111 (9.8) is Critical"
LOW_ITEMIZED=$(printf '%s' "$OUT_SARIF" | jq '[.findings[] | select(.id == "CVE-2024-22222")] | length' 2>/dev/null)
assert_equal "0" "$LOW_ITEMIZED" "SARIF: 3.1 (Low) is not itemized as a material finding"
LOW_AGG=$(printf '%s' "$OUT_SARIF" | jq -r '.aggregate.Low // 0' 2>/dev/null)
assert_equal "1" "$LOW_AGG" "SARIF: the Low-severity result is counted in the aggregate instead"

# --- osv-scanner: CVSS score under severity[].score --------------------------
cat >"$FIXTURES/scan.osv.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "package-lock.json", "type": "lockfile"},
      "packages": [
        {
          "package": {"name": "axios", "version": "0.21.1", "ecosystem": "npm"},
          "vulnerabilities": [
            {
              "id": "GHSA-4w2v-q235-vp99",
              "summary": "axios SSRF",
              "severity": [{"type": "CVSS_V3", "score": "8.1"}]
            }
          ]
        }
      ]
    }
  ]
}
EOF
OUT_OSV=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.osv.json 2>&1)
assert_equal "0" "$?" "osv-scanner: a well-formed scan parses cleanly"
FORMAT_OSV=$(printf '%s' "$OUT_OSV" | jq -r '.scan.format' 2>/dev/null)
assert_equal "osv-scanner" "$FORMAT_OSV" "osv-scanner: format is correctly detected"
OSV_SEV=$(printf '%s' "$OUT_OSV" | jq -r '.findings[0].severity' 2>/dev/null)
assert_equal "High" "$OSV_SEV" "osv-scanner: CVSS 8.1 buckets to High"
OSV_PKG=$(printf '%s' "$OUT_OSV" | jq -r '.findings[0].package' 2>/dev/null)
assert_equal "axios" "$OSV_PKG" "osv-scanner: package name is carried through"

# --- Dependabot alerts export: severity string used directly ----------------
cat >"$FIXTURES/scan.dependabot.json" <<'EOF'
[
  {
    "number": 7,
    "state": "open",
    "dependency": {"package": {"name": "django"}, "manifest_path": "requirements.txt"},
    "security_advisory": {"ghsa_id": "GHSA-xxxx-yyyy-zzzz", "severity": "high", "summary": "SQL injection"}
  },
  {
    "number": 8,
    "state": "open",
    "dependency": {"package": {"name": "requests"}, "manifest_path": "requirements.txt"},
    "security_advisory": {"ghsa_id": "GHSA-aaaa-bbbb-cccc", "severity": "low", "summary": "minor"}
  }
]
EOF
OUT_DEP=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.dependabot.json 2>&1)
assert_equal "0" "$?" "Dependabot: a well-formed export parses cleanly"
FORMAT_DEP=$(printf '%s' "$OUT_DEP" | jq -r '.scan.format' 2>/dev/null)
assert_equal "dependabot" "$FORMAT_DEP" "Dependabot: format is correctly detected"
DEP_SEV=$(printf '%s' "$OUT_DEP" | jq -r '.findings[0].severity' 2>/dev/null)
assert_equal "High" "$DEP_SEV" "Dependabot: severity string 'high' maps directly to High"

# --- No derivable severity: never silently Low -------------------------------
cat >"$FIXTURES/scan.no-severity.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "go.sum", "type": "lockfile"},
      "packages": [
        {
          "package": {"name": "example.com/pkg", "version": "1.0.0", "ecosystem": "Go"},
          "vulnerabilities": [
            {"id": "GHSA-0000-0000-0000", "summary": "no severity data provided"}
          ]
        }
      ]
    }
  ]
}
EOF
OUT_NOSEV=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.no-severity.json 2>&1)
NOSEV_SEV=$(printf '%s' "$OUT_NOSEV" | jq -r '.findings[0].severity // .unresolved_severity[0].id // "MISSING"' 2>/dev/null)
assert_not_contains "\"severity\": \"Low\"" "$OUT_NOSEV" "a finding with no derivable severity is never fabricated as Low"
assert_not_contains "\"severity\":\"Low\"" "$OUT_NOSEV" "(compact form) never fabricated as Low"

# --- Parse failure: malformed JSON must be a distinct signal, never
# "0 findings therefore clean" — mirrors the ERR-3 fix pattern already shipped
# this session in dossier-policy.sh / dossier-evidence.sh. -------------------
printf 'this is not { valid json at all' >"$FIXTURES/scan.malformed.json"
OUT_MALFORMED=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.malformed.json 2>&1)
RC_MALFORMED=$?
if [ "$RC_MALFORMED" -ne 0 ]; then _dossier_assert_pass "malformed JSON exits non-zero, distinct from a clean scan"
else _dossier_assert_fail "malformed JSON exited 0 — indistinguishable from a clean scan"; fi
assert_contains "parse-error" "$OUT_MALFORMED" "malformed JSON produces an explicit parse-error signal"

# --- Unrecognized shape (valid JSON, none of the three known formats) -------
printf '{"totally": "unrelated", "shape": true}' >"$FIXTURES/scan.unknown-shape.json"
OUT_UNKNOWN=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.unknown-shape.json 2>&1)
RC_UNKNOWN=$?
if [ "$RC_UNKNOWN" -ne 0 ]; then _dossier_assert_pass "an unrecognized (but valid) JSON shape also exits non-zero"
else _dossier_assert_fail "an unrecognized shape exited 0"; fi
assert_contains "parse-error" "$OUT_UNKNOWN" "an unrecognized shape is reported as a parse-error, not zero findings"

# --- Missing scan file --------------------------------------------------------
OUT_MISSING=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan does-not-exist.json 2>&1)
RC_MISSING=$?
if [ "$RC_MISSING" -ne 0 ]; then _dossier_assert_pass "a missing scan file exits non-zero"
else _dossier_assert_fail "a missing scan file exited 0"; fi

# --- Every material finding cites a locator: never asserts without evidence -
SRCREF_SARIF=$(printf '%s' "$OUT_SARIF" | jq -r '.findings[0].source_ref' 2>/dev/null)
assert_contains "scan.sarif.json" "$SRCREF_SARIF" "SARIF finding's source_ref names the ingested scan artifact"
assert_contains "retrieved" "$SRCREF_SARIF" "SARIF finding's source_ref carries a retrieved-date locator"
SRCREF_OSV=$(printf '%s' "$OUT_OSV" | jq -r '.findings[0].source_ref' 2>/dev/null)
assert_contains "scan.osv.json" "$SRCREF_OSV" "osv-scanner finding's source_ref names the ingested scan artifact"

# --- Coverage record: what was scanned, always present -----------------------
COVERAGE_TOOL=$(printf '%s' "$OUT_SARIF" | jq -r '.scan.tool' 2>/dev/null)
assert_equal "example-sast" "$COVERAGE_TOOL" "the coverage record names the scanning tool from the artifact itself"
COVERAGE_DATE=$(printf '%s' "$OUT_SARIF" | jq -r '.scan.retrieved' 2>/dev/null)
case "$COVERAGE_DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) _dossier_assert_pass "the coverage record's retrieved date is a real ISO date" ;;
  *) _dossier_assert_fail "the coverage record's retrieved date '$COVERAGE_DATE' is not an ISO date" ;;
esac

# --- --help and bin-scripts hygiene are covered by bin-scripts.test.sh's
# EXPECTED_SCRIPTS enumeration; not duplicated here.

# =============================================================================
# Part 2 — dossier-gate.sh G19: FAIL / PASS / INCONCLUSIVE (AC2/AC3/AC4)
# =============================================================================

if [ ! -x "$GATE" ]; then
  _dossier_assert_fail "$GATE missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# g19_fixture <dir> <ledger-vuln-rows-heredoc-var-name> <risks-body-or-empty>
# Minimal-but-real package: only the two files G19 actually reads. The other
# 17 conditions will report FAIL/INCONCLUSIVE against this fixture — expected
# and irrelevant, since every assertion below greps out only the G19 row.
g19_fixture() {
  local dir="$1" ledger_rows="$2" risks_body="$3"
  mkdir -p "$dir/docs/dossier/00-control" "$dir/docs/dossier/04-operating"
  cat >"$dir/docs/dossier/00-control/evidence-ledger.md" <<EOF
# Evidence Ledger

| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
$ledger_rows
EOF
  if [ -n "$risks_body" ]; then
    printf '%s\n' "$risks_body" > "$dir/docs/dossier/04-operating/decisions-technical-debt-and-risks.md"
  fi
}

g19_result() { # dir
  ( cd "$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root docs/dossier --json 2>/dev/null ) \
    | jq -r '.conditions[] | select(.id=="G19") | .result' 2>/dev/null
}
g19_evidence() { # dir
  ( cd "$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root docs/dossier --json 2>/dev/null ) \
    | jq -r '.conditions[] | select(.id=="G19") | .evidence' 2>/dev/null
}

# --- FAIL: a High finding with no disposition anywhere ----------------------
G19_FAIL_DIR=$(_dossier_safe_mktemp_dir "g19-fail")
g19_fixture "$G19_FAIL_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0002 | osv-scanner reports GHSA-4w2v-q235-vp99 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-4w2v-q235-vp99, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
''
G19_FAIL_RESULT=$(g19_result "$G19_FAIL_DIR")
assert_equal "FAIL" "$G19_FAIL_RESULT" "AC2: an unresolved High finding with no risks file at all fails G19"
G19_FAIL_EVIDENCE=$(g19_evidence "$G19_FAIL_DIR")
assert_contains "EV-0002" "$G19_FAIL_EVIDENCE" "AC2: G19's evidence names the specific unresolved EV-#### row"

# --- FAIL: a Risk register row exists but Status is still open --------------
G19_OPEN_DIR=$(_dossier_safe_mktemp_dir "g19-open")
g19_fixture "$G19_OPEN_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0002 | osv-scanner reports GHSA-4w2v-q235-vp99 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-4w2v-q235-vp99, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0001 | axios SSRF via GHSA-4w2v-q235-vp99 | dependency | medium | high | high | high | [EV-0002] | upgrade to 0.21.2 | Jane Doe | open |'
G19_OPEN_RESULT=$(g19_result "$G19_OPEN_DIR")
assert_equal "FAIL" "$G19_OPEN_RESULT" "AC2: a Risk register row with Status=open still fails G19 — an open row is not a disposition"

# --- PASS: an Accepted risks row with a named accepter, valid dates, and a
# stated basis disposes a High finding (AC3) --------------------------------
G19_ACCEPTED_DIR=$(_dossier_safe_mktemp_dir "g19-accepted")
g19_fixture "$G19_ACCEPTED_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0042 | osv-scanner reports GHSA-4w2v-q235-vp99 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-4w2v-q235-vp99, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0042] | Jane Doe, VP Engineering | 2026-07-20 | Low exploitability in this deployment; upgrade scheduled next quarter | 2026-10-20 | Slack thread, 2026-07-20, #security-review |'
G19_ACCEPTED_RESULT=$(g19_result "$G19_ACCEPTED_DIR")
assert_equal "PASS" "$G19_ACCEPTED_RESULT" "AC3: a High finding with a named accepter, valid dates, and a stated basis in Accepted risks passes G19"

# --- PASS: a Risk register row alone (Category=dependency, owned, not open)
# also disposes a Critical finding — Accepted risks is not the only path ----
G19_MITIGATING_DIR=$(_dossier_safe_mktemp_dir "g19-mitigating")
g19_fixture "$G19_MITIGATING_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0043 | osv-scanner reports GHSA-9999-9999-9999 in lodash@4.17.15, severity Critical | R | `scan.json` — osv-scanner, GHSA-9999-9999-9999, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0002 | lodash prototype pollution via GHSA-9999-9999-9999 | dependency | medium | critical | high | high | [EV-0043] | upgrading in the next patch release | Jane Doe | mitigating |'
G19_MITIGATING_RESULT=$(g19_result "$G19_MITIGATING_DIR")
assert_equal "PASS" "$G19_MITIGATING_RESULT" "AC3: a Risk register row with Category=dependency, a named Owner, and Status=mitigating disposes a Critical finding — Risk register alone qualifies, not only Accepted risks"

# --- PASS: a clean scan (coverage recorded, zero Critical/High findings) is
# a legitimate pass, not an omission ------------------------------------------
G19_CLEAN_DIR=$(_dossier_safe_mktemp_dir "g19-clean")
g19_fixture "$G19_CLEAN_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0002 | osv-scanner aggregate: 2 Low-severity findings in package-lock.json | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding-aggregate severity=Low count=2 |' \
''
G19_CLEAN_RESULT=$(g19_result "$G19_CLEAN_DIR")
assert_equal "PASS" "$G19_CLEAN_RESULT" "AC3/AC4: a parsed scan with zero Critical/High findings passes G19 — a clean scan is a legitimate pass, not an omission"

# --- Negative control: a calendar-invalid rollover Review date must NOT
# dispose the finding — proves validate_calendar_date() is actually applied,
# not merely present in the source file --------------------------------------
G19_ROLLOVER_DIR=$(_dossier_safe_mktemp_dir "g19-rollover")
g19_fixture "$G19_ROLLOVER_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0044 | osv-scanner reports GHSA-8888-8888-8888 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-8888-8888-8888, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0044] | Jane Doe, VP Engineering | 2026-07-20 | Low exploitability in this deployment | 2026-06-31 | Slack thread, 2026-07-20, #security-review |'
G19_ROLLOVER_RESULT=$(g19_result "$G19_ROLLOVER_DIR")
if [ "$G19_ROLLOVER_RESULT" = "PASS" ]; then
  _dossier_assert_fail "a calendar-invalid rollover Review date (2026-06-31) was accepted as a valid disposition"
else
  _dossier_assert_pass "a calendar-invalid rollover Review date (2026-06-31, silently rolls to July 1) does not dispose the finding (G19 result: $G19_ROLLOVER_RESULT)"
fi

# --- INCONCLUSIVE: no vulnerability evidence at all (AC4, gate half) --------
# Confirmed design decision (.decisions/issue-136.md): zero evidence means
# INCONCLUSIVE, never PASS — not a bug to work around.
G19_NOEVIDENCE_DIR=$(_dossier_safe_mktemp_dir "g19-noevidence")
g19_fixture "$G19_NOEVIDENCE_DIR" \
'| EV-0001 | The HTTP API authenticates with OAuth 2.0 | V | `src/api/auth.ts::authenticate` | yes | 2 | main | 2026-07-28 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' \
''
G19_NOEVIDENCE_RESULT=$(g19_result "$G19_NOEVIDENCE_DIR")
assert_equal "INCONCLUSIVE" "$G19_NOEVIDENCE_RESULT" "AC4: zero vulnerability-scan evidence in the ledger is INCONCLUSIVE, never PASS"
G19_NOEVIDENCE_EVIDENCE=$(g19_evidence "$G19_NOEVIDENCE_DIR")
assert_contains "no vulnerability-scan evidence" "$G19_NOEVIDENCE_EVIDENCE" "AC4: the no-evidence branch names itself distinctly"

# The overall GATE_RESULT (not just the G19 row) must not read PASS either —
# a regression check that G19 participates in the existing FAIL > INCONCLUSIVE
# > PASS precedence correctly, with no change expected to that logic.
G19_NOEVIDENCE_OVERALL=$(cd "$G19_NOEVIDENCE_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root docs/dossier --quiet 2>&1; echo "RC=$?")
assert_not_contains "GATE_RESULT=PASS" "$G19_NOEVIDENCE_OVERALL" "AC4: the overall gate result does not read PASS when G19 is INCONCLUSIVE"

# --- INCONCLUSIVE: a scan artifact that failed to parse, distinct wording ---
# from the "never scanned" branch above — the ERR-3-style distinction must
# survive into the gate's own reported reason, not just the ingestion script.
G19_PARSEERR_DIR=$(_dossier_safe_mktemp_dir "g19-parseerr")
g19_fixture "$G19_PARSEERR_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | U | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parse-error |' \
''
G19_PARSEERR_RESULT=$(g19_result "$G19_PARSEERR_DIR")
assert_equal "INCONCLUSIVE" "$G19_PARSEERR_RESULT" "AC4: a parse-error coverage row is also INCONCLUSIVE, never PASS"
G19_PARSEERR_EVIDENCE=$(g19_evidence "$G19_PARSEERR_DIR")
assert_contains "could not be parsed" "$G19_PARSEERR_EVIDENCE" "AC4: the parse-error branch names itself distinctly from the no-evidence branch"
assert_contains "EV-0001" "$G19_PARSEERR_EVIDENCE" "AC4: the parse-error branch cites the specific coverage row"
if [ "$G19_NOEVIDENCE_EVIDENCE" = "$G19_PARSEERR_EVIDENCE" ]; then
  _dossier_assert_fail "the no-evidence and parse-error branches produced identical evidence text — the ERR-3-style distinction did not survive into the gate"
else
  _dossier_assert_pass "the no-evidence and parse-error branches produce distinguishable evidence text"
fi

# --- This repo's own docs/dossier package: G19 is reported, not silently
# omitted, on a real pre-existing package that predates this feature --------
if [ -d "$(pwd)/docs/dossier" ]; then
  REPO_G19_OUT=$( CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root docs/dossier --json 2>/dev/null )
  REPO_G19_LINE=$(printf '%s' "$REPO_G19_OUT" | jq -r '.conditions[] | select(.id=="G19")' 2>/dev/null)
  if [ -n "$REPO_G19_LINE" ]; then
    _dossier_assert_pass "this repo's own docs/dossier package reports a G19 line (not silently omitted)"
  else
    _dossier_assert_fail "this repo's own docs/dossier package has no G19 line at all"
  fi
else
  _dossier_assert_pass "docs/dossier not present in this checkout — skipping the real-package guard"
fi

# =============================================================================
# Part 3 — template fill-instructions never imply a clean bill of health when
# no scan output exists (AC1 support + AC4, template half)
# =============================================================================
ASSETS_TEMPLATE="plugins/dossier/templates/package/05-due-diligence/assets-dependencies-and-licenses.md"
CONTRACT_05="plugins/dossier/references/package-contract-05-due-diligence.md"

if [ -f "$ASSETS_TEMPLATE" ]; then
  if grep -qiE 'no vulnerability-scan output.*located' "$ASSETS_TEMPLATE"; then
    _dossier_assert_pass "assets-dependencies-and-licenses.md's Vulnerability evidence table instructs the honest no-scan-found fallback"
  else
    _dossier_assert_fail "assets-dependencies-and-licenses.md has no explicit no-scan-found instruction — a blank table would read as clean"
  fi
else
  _dossier_assert_fail "$ASSETS_TEMPLATE missing"
fi

if [ -f "$CONTRACT_05" ]; then
  if grep -qiE 'no vulnerability-scan output exists.*table states that explicitly' "$CONTRACT_05"; then
    _dossier_assert_pass "package-contract-05-due-diligence.md's Required content requires the honest-absence case"
  else
    _dossier_assert_fail "package-contract-05-due-diligence.md's Required content does not require the honest-absence case"
  fi
else
  _dossier_assert_fail "$CONTRACT_05 missing"
fi

# =============================================================================
# Part 4 — end-to-end: a planted unresolved vulnerability is actually caught,
# not just theoretically coverable (AC5)
# =============================================================================
# Full pipeline in one fixture: a real scan artifact -> the real ingestion
# script's real output -> a ledger row built FROM that output (not
# hand-typed, bypassing the parser) -> the real gate. Distinct from Part 2's
# fixtures, which hand-write ledger rows to test G19's logic in isolation.

E2E_DIR=$(_dossier_safe_mktemp_dir "e2e-planted-vuln")
mkdir -p "$E2E_DIR/docs/dossier/00-control"

cat >"$E2E_DIR/planted-scan.json" <<'EOF'
[
  {
    "number": 42,
    "state": "open",
    "dependency": {"package": {"name": "jinja2"}, "manifest_path": "requirements.txt"},
    "security_advisory": {"ghsa_id": "GHSA-h5c8-rqwp-cp95", "severity": "high", "summary": "Jinja2 sandbox escape"}
  }
]
EOF

E2E_INGEST_OUT=$(cd "$E2E_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan planted-scan.json 2>&1)
E2E_INGEST_RC=$?
assert_equal "0" "$E2E_INGEST_RC" "e2e: the planted Dependabot artifact ingests cleanly"

E2E_FINDING_ID=$(printf '%s' "$E2E_INGEST_OUT" | jq -r '.findings[0].id' 2>/dev/null)
E2E_FINDING_SEV=$(printf '%s' "$E2E_INGEST_OUT" | jq -r '.findings[0].severity' 2>/dev/null)
E2E_FINDING_PKG=$(printf '%s' "$E2E_INGEST_OUT" | jq -r '.findings[0].package' 2>/dev/null)
assert_equal "GHSA-h5c8-rqwp-cp95" "$E2E_FINDING_ID" "e2e: the ingestion script's real output carries the planted finding's real ID"
assert_equal "High" "$E2E_FINDING_SEV" "e2e: the ingestion script's real output carries the planted finding's real severity"
assert_equal "jinja2" "$E2E_FINDING_PKG" "e2e: the ingestion script's real output carries the planted finding's real package"

# Simulate what the evidence-ledger skill does: append the script's own
# output as ledger rows, verbatim from the parsed fields above — not a
# second, independently hand-typed claim.
cat >"$E2E_DIR/docs/dossier/00-control/evidence-ledger.md" <<EOF
# Evidence Ledger

| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EV-0001 | Dependency vulnerability scan: dependabot on requirements.txt, 2026-07-28 | R | \`planted-scan.json\` — dependabot, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0002 | dependabot reports $E2E_FINDING_ID in $E2E_FINDING_PKG, severity $E2E_FINDING_SEV | R | \`planted-scan.json\` — dependabot, $E2E_FINDING_ID, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=$E2E_FINDING_SEV |
EOF
# Deliberately no 04-operating/decisions-technical-debt-and-risks.md at all —
# the planted finding has no disposition anywhere in this package.

E2E_GATE_OUT=$(cd "$E2E_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root docs/dossier --json 2>/dev/null)
E2E_G19_RESULT=$(printf '%s' "$E2E_GATE_OUT" | jq -r '.conditions[] | select(.id=="G19") | .result' 2>/dev/null)
E2E_G19_EVIDENCE=$(printf '%s' "$E2E_GATE_OUT" | jq -r '.conditions[] | select(.id=="G19") | .evidence' 2>/dev/null)
assert_equal "FAIL" "$E2E_G19_RESULT" "AC5: the planted unresolved High vulnerability, carried through the real ingestion script and the real gate, is actually caught"
assert_contains "EV-0002" "$E2E_G19_EVIDENCE" "AC5: G19's evidence names the planted finding's specific EV-#### row"

# =============================================================================
# Part 5 — regressions found and fixed during self-review (F1-F4)
# =============================================================================

# --- F1: a selected row (matches the vuln-finding tag) whose id cannot be
# extracted must never silently vanish from the loop — it counts as
# undisposed, never as an implicit pass. A row indented by a couple of
# spaces before the pipe renders identically in Markdown but was previously
# lost between the (unanchored) selection grep and the (anchored) extraction
# grep. ------------------------------------------------------------------
G19_INDENT_DIR=$(_dossier_safe_mktemp_dir "g19-indent")
mkdir -p "$G19_INDENT_DIR/docs/dossier/00-control"
printf '%s\n' \
  '# Evidence Ledger' \
  '' \
  '| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |' \
  '  | EV-0002 | osv-scanner reports GHSA-4w2v-q235-vp99 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-4w2v-q235-vp99, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
  > "$G19_INDENT_DIR/docs/dossier/00-control/evidence-ledger.md"
G19_INDENT_RESULT=$(g19_result "$G19_INDENT_DIR")
assert_equal "FAIL" "$G19_INDENT_RESULT" "F1 regression: a vuln-finding row indented before the pipe still fails G19 (never silently drops out as an implicit pass)"

# --- F2: format detection on a genuinely clean scan for the two formats
# whose empty shape does not carry a nested array to key off -----------------
G19_F2_DIR=$(_dossier_safe_mktemp_dir "f2-clean-detect")
printf '[]' >"$G19_F2_DIR/empty.json"
F2_DEP_OUT=$(cd "$G19_F2_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan empty.json 2>&1)
F2_DEP_RC=$?
assert_equal "0" "$F2_DEP_RC" "F2 regression: an empty Dependabot alerts array ([]) — the real zero-open-alerts API shape — parses cleanly"
F2_DEP_FORMAT=$(printf '%s' "$F2_DEP_OUT" | jq -r '.scan.format' 2>/dev/null)
assert_equal "dependabot" "$F2_DEP_FORMAT" "F2 regression: an empty array is still detected as dependabot, not rejected as unknown"

printf '{"results":[]}' >"$G19_F2_DIR/clean.json"
F2_OSV_OUT=$(cd "$G19_F2_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan clean.json 2>&1)
F2_OSV_RC=$?
assert_equal "0" "$F2_OSV_RC" "F2 regression: an osv-scanner clean result ({\"results\":[]}) with no packages key anywhere parses cleanly"
F2_OSV_FORMAT=$(printf '%s' "$F2_OSV_OUT" | jq -r '.scan.format' 2>/dev/null)
assert_equal "osv-scanner" "$F2_OSV_FORMAT" "F2 regression: a results-only-empty-array shape is still detected as osv-scanner"

# --- F3: a disposition citing the finding alongside another id in the same
# bracket, and a finding cited by a second (qualifying) row after a first
# (non-qualifying) row, must both be recognized. -----------------------------
G19_MULTI_DIR=$(_dossier_safe_mktemp_dir "g19-multi-citation")
g19_fixture "$G19_MULTI_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0005 | osv-scanner reports GHSA-multi-0001 in requests@2.25.0, severity High | R | `scan.json` — osv-scanner, GHSA-multi-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0003 | requests vulnerability, comma-cited alongside another evidence row | dependency | medium | high | high | high | [EV-0004, EV-0005] | upgrading next sprint | Jane Doe | mitigating |'
G19_MULTI_RESULT=$(g19_result "$G19_MULTI_DIR")
assert_equal "PASS" "$G19_MULTI_RESULT" "F3 regression: a Risk register row citing the finding alongside another id in the same bracket ([EV-0004, EV-0005]) still disposes it"

G19_SECONDROW_DIR=$(_dossier_safe_mktemp_dir "g19-second-row")
g19_fixture "$G19_SECONDROW_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0006 | osv-scanner reports GHSA-multi-0002 in flask@1.1.0, severity Critical | R | `scan.json` — osv-scanner, GHSA-multi-0002, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0004 | flask vulnerability, initial triage row not yet disposed | dependency | medium | critical | high | high | [EV-0006] | investigation ongoing | | open |
| RISK-0005 | flask vulnerability, later fully-qualifying mitigation row citing the same evidence | dependency | medium | critical | high | high | [EV-0006] | upgraded to 1.1.1 | Jane Doe | mitigating |'
G19_SECONDROW_RESULT=$(g19_result "$G19_SECONDROW_DIR")
assert_equal "PASS" "$G19_SECONDROW_RESULT" "F3 regression: a second Risk register row citing the same finding disposes it even when an earlier citing row does not qualify"

_dossier_test_summary
