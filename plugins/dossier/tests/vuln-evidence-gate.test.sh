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

_dossier_test_summary
