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

# --- osv-scanner: severity via groups[].max_severity, not vulnerabilities[]
# .severity[].score. Real osv-scanner 2.4.0 output encodes per-vulnerability
# severity as a CVSS VECTOR STRING (e.g. "CVSS:3.1/AV:N/AC:H/..."), confirmed
# by direct live testing during issue #137 — groups[].max_severity is
# osv-scanner's own precomputed bare-number CVSS base score and the correct
# extraction source. The vulnerabilities[].severity field below is left in
# vector-string shape (realistic, and deliberately proves it is no longer
# read for bucketing at all). -------------------------------------------
cat >"$FIXTURES/scan.osv.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "package-lock.json", "type": "lockfile"},
      "packages": [
        {
          "package": {"name": "axios", "version": "0.21.1", "ecosystem": "npm"},
          "groups": [
            {"ids": ["GHSA-4w2v-q235-vp99"], "aliases": ["CVE-2021-3749", "GHSA-4w2v-q235-vp99"], "max_severity": "8.1"}
          ],
          "vulnerabilities": [
            {
              "id": "GHSA-4w2v-q235-vp99",
              "summary": "axios SSRF",
              "severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H"}]
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
assert_equal "High" "$OSV_SEV" "osv-scanner: groups[].max_severity 8.1 buckets to High"
OSV_PKG=$(printf '%s' "$OUT_OSV" | jq -r '.findings[0].package' 2>/dev/null)
assert_equal "axios" "$OSV_PKG" "osv-scanner: package name is carried through"
OSV_ID=$(printf '%s' "$OUT_OSV" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "CVE-2021-3749" "$OSV_ID" "osv-scanner: the group's CVE- prefixed alias is preferred as the primary id"

# --- osv-scanner: a group with no CVE- alias falls back to the
# lexicographically-first id, never tool-output order. -----------------------
cat >"$FIXTURES/scan.osv.no-cve-alias.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "package-lock.json"},
      "packages": [
        {
          "package": {"name": "lodash", "version": "4.17.15"},
          "groups": [
            {"ids": ["GHSA-zzzz-0001", "GHSA-aaaa-0002"], "aliases": ["GHSA-zzzz-0001", "GHSA-aaaa-0002"], "max_severity": "7.5"}
          ],
          "vulnerabilities": [
            {"id": "GHSA-zzzz-0001", "summary": "prototype pollution (dup 1)"},
            {"id": "GHSA-aaaa-0002", "summary": "prototype pollution (dup 2)"}
          ]
        }
      ]
    }
  ]
}
EOF
OSV_NOCVE_OUT=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.osv.no-cve-alias.json 2>&1)
OSV_NOCVE_COUNT=$(printf '%s' "$OSV_NOCVE_OUT" | jq '.findings | length' 2>/dev/null)
assert_equal "1" "$OSV_NOCVE_COUNT" "osv-scanner: a group merging two aliased ids produces exactly one evidence row, not two"
OSV_NOCVE_ID=$(printf '%s' "$OSV_NOCVE_OUT" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "GHSA-aaaa-0002" "$OSV_NOCVE_ID" "osv-scanner: no CVE- alias present -> lexicographically-first id wins, not the tool's listed order"

# --- osv-scanner: non-ASCII content (a package name with a multi-byte
# character, an emoji and RTL text in a finding summary) is carried through
# verbatim by the group-based extraction, not corrupted or truncated. jq
# handles UTF-8 natively and this extraction path does no byte-length or
# substring operation on these fields, but the path had no dedicated test
# for it — SEC-4 above tests shell-metacharacter injection resistance, a
# different concern from encoding. -------------------------------------------
cat >"$FIXTURES/scan.osv.unicode.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "package-lock.json"},
      "packages": [
        {
          "package": {"name": "café-café-résumé", "version": "1.0.0"},
          "groups": [
            {"ids": ["GHSA-unicode-0001"], "aliases": ["CVE-2024-90001"], "max_severity": "9.1"}
          ],
          "vulnerabilities": [
            {"id": "GHSA-unicode-0001", "summary": "🔥 critical: مرحبا injection 你好 world"}
          ]
        }
      ]
    }
  ]
}
EOF
OSV_UNICODE_OUT=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.osv.unicode.json 2>&1)
OSV_UNICODE_RC=$?
assert_equal "0" "$OSV_UNICODE_RC" "osv-scanner: non-ASCII scan content parses cleanly, not treated as malformed"
OSV_UNICODE_PKG=$(printf '%s' "$OSV_UNICODE_OUT" | jq -r '.findings[0].package' 2>/dev/null)
assert_equal "café-café-résumé" "$OSV_UNICODE_PKG" "osv-scanner: a multi-byte package name is carried through verbatim, not corrupted or truncated"
OSV_UNICODE_SUMMARY=$(printf '%s' "$OSV_UNICODE_OUT" | jq -r '.findings[0].summary' 2>/dev/null)
assert_equal "🔥 critical: مرحبا injection 你好 world" "$OSV_UNICODE_SUMMARY" "osv-scanner: emoji and RTL/CJK text in a summary field survive extraction byte-for-byte"

# --- osv-scanner: a group with null/absent max_severity falls to
# unresolved_severity, never defaulted Low. -----------------------------------
cat >"$FIXTURES/scan.osv.null-max-severity.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "package-lock.json"},
      "packages": [
        {
          "package": {"name": "example-pkg", "version": "2.0.0"},
          "groups": [
            {"ids": ["GHSA-nullsev-0001"], "aliases": ["GHSA-nullsev-0001"], "max_severity": null}
          ],
          "vulnerabilities": [
            {"id": "GHSA-nullsev-0001", "summary": "severity not yet scored"}
          ]
        }
      ]
    }
  ]
}
EOF
OSV_NULLSEV_OUT=$(cd "$FIXTURES" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.osv.null-max-severity.json 2>&1)
OSV_NULLSEV_UNRESOLVED_ID=$(printf '%s' "$OSV_NULLSEV_OUT" | jq -r '.unresolved_severity[0].id // "MISSING"' 2>/dev/null)
assert_equal "GHSA-nullsev-0001" "$OSV_NULLSEV_UNRESOLVED_ID" "osv-scanner: a group with null max_severity lands in unresolved_severity, never fabricated as Low"
OSV_NULLSEV_FINDINGS=$(printf '%s' "$OSV_NULLSEV_OUT" | jq '.findings | length' 2>/dev/null)
assert_equal "0" "$OSV_NULLSEV_FINDINGS" "osv-scanner: a null-max_severity group is never itemized as a material finding"

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

# --- No derivable severity: never silently Low. This package's vulnerabilities[]
# is non-empty while `groups` is entirely absent — the defensive fallback path
# added for issue #137 (real osv-scanner output always populates groups[] in
# lockstep with vulnerabilities[], but this is not observed, only assumed, so
# the fallback must fail safe rather than silently drop the record). --------
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
# Parsed via jq, not a raw-text grep for '"severity": "Low"' — the script
# always emits compact (`jq -c`) output, so a spaced-form text match can
# never appear regardless of whether the underlying value is correct,
# making a text-grep assertion here tautological rather than a real check.
NOSEV_SEVERITY=$(printf '%s' "$OUT_NOSEV" | jq -r '.unresolved_severity[0].severity // "MISSING"' 2>/dev/null)
assert_not_contains "Low" "$NOSEV_SEVERITY" "a finding with no derivable severity is never fabricated as Low"
NOSEV_ID=$(printf '%s' "$OUT_NOSEV" | jq -r '.unresolved_severity[0].id // "MISSING"' 2>/dev/null)
assert_equal "GHSA-0000-0000-0000" "$NOSEV_ID" "the no-derivable-severity finding is recorded in unresolved_severity, not silently omitted"

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
assert_contains "no scan artifact" "$OUT_MISSING" "a missing scan file names itself distinctly from a parse failure"
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

# --- General bin-script hygiene (exists, executable, syntax, usage header,
# bash-3.2 portability, unknown-flag exit code) is covered by
# bin-scripts.test.sh's EXPECTED_SCRIPTS enumeration; not duplicated here.
# That enumeration only checks for a `# Usage:` header's PRESENCE in source,
# not --help's actual invoked output — --help's content is exercised in
# Part 8 below, and dossier-vuln-evidence.sh's other usage-error exit paths
# (--scan/--out given with no value, --scan omitted) are covered directly in
# bin-scripts.test.sh alongside its unknown-flag check.

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

# Scoped honestly: this fixture is deliberately minimal (only the two files
# G19 reads), so several OTHER conditions also fail on it independently of
# G19 — verified directly: this exact fixture's overall result is FAIL, from
# G03/G05/G08/G09/G10/G12/G16/G17, not from G19. This assertion therefore
# does NOT isolate G19's individual causal contribution to the overall
# result (that would need a fixture where every other condition legitimately
# passes); it is a narrower sanity check that the aggregate FAIL/INCONCLUSIVE
# precedence computation doesn't erroneously report PASS on a fixture with
# multiple non-PASS conditions, G19 among them. G19's OWN row is what the
# assert_equal two lines above already proves precisely, via the
# per-condition JSON field rather than a text search.
G19_NOEVIDENCE_OVERALL_RESULT=$(cd "$G19_NOEVIDENCE_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root docs/dossier --json 2>/dev/null | jq -r '.result' 2>/dev/null)
if [ "$G19_NOEVIDENCE_OVERALL_RESULT" = "PASS" ]; then
  _dossier_assert_fail "AC4: the overall gate result read PASS on a fixture where G19 (among other uncovered conditions) is non-PASS"
else
  _dossier_assert_pass "AC4: the overall gate result is not PASS on a fixture where G19 (among other uncovered conditions) is non-PASS (got: $G19_NOEVIDENCE_OVERALL_RESULT)"
fi

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

# =============================================================================
# Part 6 — holdout validation findings
# =============================================================================

# --- H1 (was P1): one malformed record in an otherwise-valid multi-finding
# scan must not abort extraction of the OTHER, genuinely valid findings — a
# jq object-construction error on one array element previously propagated
# out of the whole array comprehension, discarding every finding, not just
# the bad one. -----------------------------------------------------------
H1_DIR=$(_dossier_safe_mktemp_dir "h1-partial-record")
cat >"$H1_DIR/mixed.json" <<'EOF'
{
  "runs": [
    {
      "tool": {"driver": {"name": "example-sast", "version": "1.4.0"}},
      "results": [
        {
          "ruleId": "CVE-2024-11111",
          "message": {"text": "malformed properties field"},
          "properties": "this-should-be-an-object-not-a-string",
          "locations": [{"physicalLocation": {"artifactLocation": {"uri": "package.json"}}}]
        },
        {
          "ruleId": "CVE-2024-33333",
          "message": {"text": "a perfectly normal second finding"},
          "properties": {"security-severity": "9.5"},
          "locations": [{"physicalLocation": {"artifactLocation": {"uri": "package.json"}}}]
        }
      ]
    }
  ]
}
EOF
H1_OUT=$(cd "$H1_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan mixed.json 2>&1)
H1_RC=$?
assert_equal "0" "$H1_RC" "H1: a scan with one malformed record alongside a valid one still exits 0 — a per-record problem, not a total failure"
H1_VALID_ID=$(printf '%s' "$H1_OUT" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "CVE-2024-33333" "$H1_VALID_ID" "H1: the genuinely valid Critical finding is NOT lost alongside its malformed sibling"
H1_VALID_SEV=$(printf '%s' "$H1_OUT" | jq -r '.findings[0].severity' 2>/dev/null)
assert_equal "Critical" "$H1_VALID_SEV" "H1: the valid finding's severity is correctly preserved"
H1_UNPARSEABLE_COUNT=$(printf '%s' "$H1_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "1" "$H1_UNPARSEABLE_COUNT" "H1: the malformed record is flagged in unparseable_records, not silently dropped"
H1_PARSE_ERROR=$(printf '%s' "$H1_OUT" | jq -r '.unparseable_records[0].parse_error' 2>/dev/null)
assert_contains "security-severity" "$H1_PARSE_ERROR" "H1: the unparseable record retains the underlying error detail"

# --- H2: SARIF's own empty-runs clean-scan shape must parse cleanly, the
# same guarantee already regression-tested for Dependabot/osv-scanner -------
H2_DIR=$(_dossier_safe_mktemp_dir "h2-sarif-empty")
printf '{"runs":[]}' >"$H2_DIR/empty-runs.json"
H2_OUT=$(cd "$H2_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan empty-runs.json 2>&1)
H2_RC=$?
assert_equal "0" "$H2_RC" "H2: a SARIF scan with zero runs (a clean scan) parses cleanly"
H2_FORMAT=$(printf '%s' "$H2_OUT" | jq -r '.scan.format' 2>/dev/null)
assert_equal "sarif" "$H2_FORMAT" "H2: an empty-runs SARIF file is still detected as sarif"
H2_FINDINGS_COUNT=$(printf '%s' "$H2_OUT" | jq '.findings | length' 2>/dev/null)
assert_equal "0" "$H2_FINDINGS_COUNT" "H2: zero findings, correctly — not a parse error"

# --- H3: CVSS bucket boundaries are exact, not approximate ------------------
H3_DIR=$(_dossier_safe_mktemp_dir "h3-cvss-boundaries")
cat >"$H3_DIR/boundaries.json" <<'EOF'
{
  "runs": [{
    "tool": {"driver": {"name": "boundary-test"}},
    "results": [
      {"ruleId": "B-CRIT-LOW",  "message": {"text": "exactly 9.0"}, "properties": {"security-severity": "9.0"}},
      {"ruleId": "B-HIGH-HIGH", "message": {"text": "just under Critical"}, "properties": {"security-severity": "8.9"}},
      {"ruleId": "B-HIGH-LOW",  "message": {"text": "exactly 7.0"}, "properties": {"security-severity": "7.0"}},
      {"ruleId": "B-MED-HIGH",  "message": {"text": "just under High"}, "properties": {"security-severity": "6.9"}},
      {"ruleId": "B-MED-LOW",   "message": {"text": "exactly 4.0"}, "properties": {"security-severity": "4.0"}},
      {"ruleId": "B-LOW-HIGH",  "message": {"text": "just under Medium"}, "properties": {"security-severity": "3.9"}},
      {"ruleId": "B-LOW-LOW",   "message": {"text": "just above zero"}, "properties": {"security-severity": "0.1"}},
      {"ruleId": "B-ZERO",      "message": {"text": "zero score"}, "properties": {"security-severity": "0.0"}}
    ]
  }]
}
EOF
H3_OUT=$(cd "$H3_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan boundaries.json 2>&1)
# Critical/High are itemized in `findings[]`; Medium/Low are aggregate-only
# counts (never individually addressable by id) — sev_of() only resolves the
# itemized half.
sev_of() { printf '%s' "$H3_OUT" | jq -r --arg id "$1" '.findings[] | select(.id == $id) | .severity // "null"' 2>/dev/null; }
assert_equal "Critical" "$(sev_of B-CRIT-LOW)" "H3: 9.0 is Critical (lower boundary inclusive)"
assert_equal "High" "$(sev_of B-HIGH-HIGH)" "H3: 8.9 is High, not Critical"
assert_equal "High" "$(sev_of B-HIGH-LOW)" "H3: 7.0 is High (lower boundary inclusive)"
H3_MEDIUM_COUNT=$(printf '%s' "$H3_OUT" | jq -r '.aggregate.Medium // 0' 2>/dev/null)
assert_equal "2" "$H3_MEDIUM_COUNT" "H3: both 6.9 (just under High) and 4.0 (lower boundary) bucket to Medium, not High"
H3_LOW_COUNT=$(printf '%s' "$H3_OUT" | jq -r '.aggregate.Low // 0' 2>/dev/null)
assert_equal "2" "$H3_LOW_COUNT" "H3: both 3.9 (just under Medium) and 0.1 (lower boundary) bucket to Low, not Medium"
H3_ZERO_SEV=$(printf '%s' "$H3_OUT" | jq -r '.unresolved_severity[] | select(.id == "B-ZERO") | .severity' 2>/dev/null)
assert_equal "null" "$H3_ZERO_SEV" "H3: a 0.0 score is unresolved, not fabricated as Low"

# --- H4: two Critical/High findings, one disposed and one not — the gate
# must FAIL for the undisposed one without being satisfied by the other's
# valid disposition, and the evidence must name the undisposed one specifically
H4_DIR=$(_dossier_safe_mktemp_dir "h4-mixed-disposition")
g19_fixture "$H4_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0010 | osv-scanner reports GHSA-disposed-0001 in flask@1.1.0, severity Critical | R | `scan.json` — osv-scanner, GHSA-disposed-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |
| EV-0011 | osv-scanner reports GHSA-undisposed-0002 in requests@2.25.0, severity High | R | `scan.json` — osv-scanner, GHSA-undisposed-0002, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0010] | Jane Doe, VP Engineering | 2026-07-20 | Low exploitability in this deployment | 2026-10-20 | Slack thread, 2026-07-20, #security-review |'
H4_RESULT=$(g19_result "$H4_DIR")
assert_equal "FAIL" "$H4_RESULT" "H4: one disposed and one undisposed finding — the gate still FAILs overall"
H4_EVIDENCE=$(g19_evidence "$H4_DIR")
assert_contains "EV-0011" "$H4_EVIDENCE" "H4: the evidence names the undisposed finding"
assert_not_contains "EV-0010" "$H4_EVIDENCE" "H4: the evidence does not also name the properly-disposed finding"

# =============================================================================
# Part 7 — independent post-fix re-validation findings (H1's fix was
# incomplete: it protected the final per-record object build, but a type
# error occurring further upstream in the generator chain that PRODUCES each
# record — a malformed top-level field, or a malformed individual array
# element one or more levels above the final record — throws before ever
# reaching that protection and still aborts the whole extraction.)
# =============================================================================

# --- H5: a malformed top-level scan-metadata field (tool) must not cost the
# scan its actual findings ----------------------------------------------------
H5_DIR=$(_dossier_safe_mktemp_dir "h5-bad-tool-field")
cat >"$H5_DIR/bad-tool.json" <<'EOF'
{
  "runs": [
    {
      "tool": "this-should-be-an-object-not-a-string",
      "results": [
        {"ruleId": "CVE-2024-99999", "message": {"text": "valid finding"}, "properties": {"security-severity": "9.5"}}
      ]
    }
  ]
}
EOF
H5_OUT=$(cd "$H5_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad-tool.json 2>&1)
H5_RC=$?
assert_equal "0" "$H5_RC" "H5: a malformed top-level tool field does not abort the whole scan"
H5_FINDING_ID=$(printf '%s' "$H5_OUT" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "CVE-2024-99999" "$H5_FINDING_ID" "H5: the genuinely valid finding survives a malformed sibling top-level field"
H5_TOOL=$(printf '%s' "$H5_OUT" | jq -r '.scan.tool' 2>/dev/null)
assert_equal "unknown" "$H5_TOOL" "H5: the malformed tool field itself degrades to 'unknown', not a crash"

# --- H6: a malformed individual entry ABOVE the final record (a bad `.runs[]`
# entry sitting next to a well-formed one) must not cost the WELL-FORMED
# run's findings --------------------------------------------------------------
H6_DIR=$(_dossier_safe_mktemp_dir "h6-bad-run-entry")
cat >"$H6_DIR/bad-run.json" <<'EOF'
{
  "runs": [
    "this-run-entry-is-a-string-not-an-object",
    {
      "tool": {"driver": {"name": "example-sast"}},
      "results": [
        {"ruleId": "CVE-2024-88888", "message": {"text": "valid finding in the second run"}, "properties": {"security-severity": "9.1"}}
      ]
    }
  ]
}
EOF
H6_OUT=$(cd "$H6_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad-run.json 2>&1)
H6_RC=$?
assert_equal "0" "$H6_RC" "H6: one malformed run entry alongside a well-formed one does not abort the whole scan"
H6_FINDING_ID=$(printf '%s' "$H6_OUT" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "CVE-2024-88888" "$H6_FINDING_ID" "H6: the well-formed run's genuine finding survives its malformed sibling run"

# --- H7: same isolation for osv-scanner's own nested structure (a malformed
# `packages` field on one result must not cost a sibling result's findings) --
H7_DIR=$(_dossier_safe_mktemp_dir "h7-osv-bad-packages")
cat >"$H7_DIR/osv-bad-packages.json" <<'EOF'
{
  "results": [
    {
      "source": {"path": "package-lock.json"},
      "packages": "this-should-be-an-array-not-a-string"
    },
    {
      "source": {"path": "requirements.txt"},
      "packages": [
        {
          "package": {"name": "requests", "version": "2.25.0"},
          "groups": [
            {"ids": ["GHSA-valid-0001"], "aliases": ["GHSA-valid-0001"], "max_severity": "9.2"}
          ],
          "vulnerabilities": [
            {"id": "GHSA-valid-0001", "summary": "a genuinely valid finding"}
          ]
        }
      ]
    }
  ]
}
EOF
H7_OUT=$(cd "$H7_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan osv-bad-packages.json 2>&1)
H7_RC=$?
assert_equal "0" "$H7_RC" "H7: osv-scanner — one malformed result's packages field does not abort the whole scan"
H7_FINDING_ID=$(printf '%s' "$H7_OUT" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "GHSA-valid-0001" "$H7_FINDING_ID" "H7: a sibling result's genuine finding survives a malformed packages field elsewhere"

# --- H8: Dependabot's own equivalent case — a malformed array element
# alongside a well-formed one. Dependabot's shape is flat (a single top-level
# array, no intermediate nesting), so this is a narrower case than H5-H7, but
# it closes out the same fault-isolation guarantee across all three formats.
H8_DIR=$(_dossier_safe_mktemp_dir "h8-dependabot-bad-element")
cat >"$H8_DIR/dependabot-bad-element.json" <<'EOF'
[
  "this-element-is-a-string-not-an-alert-object",
  {
    "number": 7,
    "state": "open",
    "dependency": {"package": {"name": "django"}, "manifest_path": "requirements.txt"},
    "security_advisory": {"ghsa_id": "GHSA-valid-dep01", "severity": "high", "summary": "a genuinely valid finding"}
  }
]
EOF
H8_OUT=$(cd "$H8_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan dependabot-bad-element.json 2>&1)
H8_RC=$?
assert_equal "0" "$H8_RC" "H8: Dependabot — one malformed array element does not abort the whole scan"
H8_FINDING_ID=$(printf '%s' "$H8_OUT" | jq -r '.findings[0].id' 2>/dev/null)
assert_equal "GHSA-valid-dep01" "$H8_FINDING_ID" "H8: a sibling array element's genuine finding survives a malformed element elsewhere"
H8_UNPARSEABLE_COUNT=$(printf '%s' "$H8_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "1" "$H8_UNPARSEABLE_COUNT" "H8: the malformed element is flagged, not silently dropped"

# --- H9: an EV-#### id mentioned coincidentally in a Risk/Mitigation/Basis
# prose cell (not the actual citation cell) must NEVER be read as disposing
# that finding — citation matching is scoped to the Evidence/Risk-ID cell
# specifically, never the whole row. A real, exploitable false-positive: a
# Risk register row for one finding, whose free-text description happens to
# mention a completely different finding's id, previously disposed that
# other, genuinely-unresolved finding. ---------------------------------------
H9_RISK_DIR=$(_dossier_safe_mktemp_dir "h9-coincidental-mention-risk")
g19_fixture "$H9_RISK_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0099 | osv-scanner reports GHSA-real-target in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-real-target, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0002 | A totally unrelated dependency risk whose own tracking reference happens to be EV-0099-old, citing different evidence entirely | dependency | low | low | low | low | [EV-0002] | patched already | Jane Doe | mitigating |'
H9_RISK_RESULT=$(g19_result "$H9_RISK_DIR")
assert_equal "FAIL" "$H9_RISK_RESULT" "H9: a coincidental EV-#### mention in the Risk register's Risk/Mitigation prose does not falsely dispose an unrelated finding"
H9_RISK_EVIDENCE=$(g19_evidence "$H9_RISK_DIR")
assert_contains "EV-0099" "$H9_RISK_EVIDENCE" "H9: the genuinely undisposed finding is still correctly named"

H9_ACC_DIR=$(_dossier_safe_mktemp_dir "h9-coincidental-mention-accepted")
g19_fixture "$H9_ACC_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0099 | osv-scanner reports GHSA-real-target in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-real-target, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0002] | Jane Doe | 2026-07-20 | Low exploitability; unrelated finding, but this basis text happens to mention EV-0099 in passing for historical context | 2026-10-20 | Slack thread |'
H9_ACC_RESULT=$(g19_result "$H9_ACC_DIR")
assert_equal "FAIL" "$H9_ACC_RESULT" "H9: a coincidental EV-#### mention in the Accepted risks Basis prose does not falsely dispose an unrelated finding"

# --- SEC-4: shell metacharacters in scan-artifact content (package name,
# summary — repository/fork-PR-controlled data) must never be executed, at
# either the ingestion step (jq --arg, never string-concatenated into the jq
# program) or the gate's table-cell parsing (bash IFS='|' word-splitting,
# which does not re-invoke the shell parser on cell contents). A pinned
# regression so a future refactor of either path cannot silently reintroduce
# an injection vector without a test catching it. ---------------------------
SEC4_MARKER="/tmp/dossier-sec4-pwned-marker-$$"
rm -f "$SEC4_MARKER" 2>/dev/null
SEC4_DIR=$(_dossier_safe_mktemp_dir "sec4-injection-safety")
cat >"$SEC4_DIR/scan.json" <<EOF
[
  {
    "number": 1,
    "state": "open",
    "dependency": {"package": {"name": "\$(touch $SEC4_MARKER)\`touch $SEC4_MARKER\`"}, "manifest_path": "requirements.txt"},
    "security_advisory": {"ghsa_id": "GHSA-inj-0001", "severity": "high", "summary": "\$(touch $SEC4_MARKER); a summary with a | pipe and \`backticks\` and \$(command substitution)"}
  }
]
EOF
SEC4_INGEST_OUT=$(cd "$SEC4_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan scan.json 2>&1)
SEC4_INGEST_RC=$?
assert_equal "0" "$SEC4_INGEST_RC" "SEC-4: shell metacharacters in scan content do not break ingestion"
if [ -f "$SEC4_MARKER" ]; then
  _dossier_assert_fail "SEC-4: shell metacharacters in scan content were executed during ingestion"
  rm -f "$SEC4_MARKER" 2>/dev/null
else
  _dossier_assert_pass "SEC-4: shell metacharacters in scan content were not executed during ingestion"
fi
SEC4_PKG=$(printf '%s' "$SEC4_INGEST_OUT" | jq -r '.findings[0].package' 2>/dev/null)
assert_contains 'touch' "$SEC4_PKG" "SEC-4: the malicious-looking package name is preserved verbatim as data, not stripped or executed"

# Thread the same content into a ledger fixture and confirm the gate's own
# table-cell parsing is equally inert.
mkdir -p "$SEC4_DIR/docs/dossier/00-control"
cat >"$SEC4_DIR/docs/dossier/00-control/evidence-ledger.md" <<EOF
# Evidence Ledger

| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EV-0001 | Dependency vulnerability scan: dependabot on requirements.txt, 2026-07-28 | R | \`scan.json\` — dependabot, retrieved 2026-07-28 | yes | 3 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0002 | dependabot reports GHSA-inj-0001 in \$(touch $SEC4_MARKER), severity High | R | \`scan.json\` — dependabot, GHSA-inj-0001, retrieved 2026-07-28 | yes | 3 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |
EOF
SEC4_GATE_OUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$GATE" --output-root "$SEC4_DIR/docs/dossier" --json 2>/dev/null)
SEC4_GATE_RESULT=$(printf '%s' "$SEC4_GATE_OUT" | jq -r '.conditions[] | select(.id=="G19") | .result' 2>/dev/null)
assert_equal "FAIL" "$SEC4_GATE_RESULT" "SEC-4: the gate still correctly evaluates disposition (FAIL, undisposed) despite shell-metacharacter content in the ledger"
if [ -f "$SEC4_MARKER" ]; then
  _dossier_assert_fail "SEC-4: shell metacharacters in ledger content were executed during gate evaluation"
  rm -f "$SEC4_MARKER" 2>/dev/null
else
  _dossier_assert_pass "SEC-4: shell metacharacters in ledger content were not executed during gate evaluation"
fi

# --- ERR-1: a container-level malformed entry (not just a leaf record) must
# be tracked in unparseable_records, never silently degrade to an empty
# result indistinguishable from that container legitimately having nothing
# — a scan where EVERY container is malformed must not read as a clean,
# zero-findings scan. --------------------------------------------------------
ERR1_DIR=$(_dossier_safe_mktemp_dir "err1-container-tracking")
cat >"$ERR1_DIR/all-bad-runs.json" <<'EOF'
{"runs": ["a string, not an object", 42]}
EOF
ERR1_OUT=$(cd "$ERR1_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan all-bad-runs.json 2>&1)
ERR1_RC=$?
assert_equal "0" "$ERR1_RC" "ERR-1: a scan where every runs[] entry is malformed still exits 0 (a tracked condition, not a total failure)"
ERR1_UNPARSEABLE_COUNT=$(printf '%s' "$ERR1_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "2" "$ERR1_UNPARSEABLE_COUNT" "ERR-1: both malformed runs[] entries are tracked in unparseable_records — never silently indistinguishable from a genuinely clean scan"

cat >"$ERR1_DIR/bad-packages-field.json" <<'EOF'
{"results": [{"source": {"path": "a"}, "packages": "not-an-array"}]}
EOF
ERR1_PKG_OUT=$(cd "$ERR1_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad-packages-field.json 2>&1)
ERR1_PKG_UNPARSEABLE=$(printf '%s' "$ERR1_PKG_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "1" "$ERR1_PKG_UNPARSEABLE" "ERR-1: a wrong-typed packages field one level above the leaf record is also tracked, not silently swallowed"

# --- ERR-2 / F1: a status=partial coverage row (some records parsed, some
# did not) must make G19 INCONCLUSIVE, never PASS just because every record
# that DID parse happens to be disposed — the unparsed portion's materiality
# is unknown. -----------------------------------------------------------
ERR2_DIR=$(_dossier_safe_mktemp_dir "err2-status-partial")
g19_fixture "$ERR2_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 (1 record could not be normalized) | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=partial |
| EV-0002 | osv-scanner: one record could not be normalized, severity unknown | U | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding-unresolved |' \
''
ERR2_RESULT=$(g19_result "$ERR2_DIR")
assert_equal "INCONCLUSIVE" "$ERR2_RESULT" "ERR-2/F1: a status=partial coverage row with zero itemized Critical/High rows is INCONCLUSIVE, never a vacuous PASS"
ERR2_EVIDENCE=$(g19_evidence "$ERR2_DIR")
assert_contains "parsed partially" "$ERR2_EVIDENCE" "ERR-2/F1: the partial-parse branch names itself distinctly from both the no-evidence and total-parse-error branches"

# =============================================================================
# Part 8 — /flow:review PR#141 findings (F1-F5 code-reviewer, SEC-1/2/3
# security-reviewer, ERR-1/2/3/6 error-handler-inspector; 3-6 independent
# agents corroborated most of these)
# =============================================================================

# --- F1 (historical, code-reviewer-skeptic / ERR-1 error-handler): osv-scanner's
# `.severity[0]?.score` used to swallow a wrong-typed `.severity` field into a
# zero-output jq generator — the WHOLE finding record vanished (not in
# findings, not in unresolved_severity, not in unparseable_records), with exit
# 0. Confirmed by live reproduction before the original PR#141 fix (dropping
# the `?` so the wrong-typed field threw and was caught).
#
# Superseded by issue #137's severity-extraction rework: real osv-scanner
# output encodes per-vulnerability severity as a CVSS VECTOR STRING, not a
# bare score (confirmed by direct live testing), so `.severity` is no longer
# read for extraction AT ALL — the correct source is groups[].max_severity.
# This closes the original bug class categorically (a malformed .severity
# field, in ANY shape, is now simply irrelevant to extraction — proven below),
# but shifts the "malformed record must not silently vanish" risk to the
# groups[] iteration itself, tested separately after this. -----------------
F1_DIR=$(_dossier_safe_mktemp_dir "f1-severity-swallow")
cat >"$F1_DIR/bad-severity-shape.json" <<'EOF'
{
  "results": [
    {
      "packages": [
        {
          "package": {"name": "left-pad", "version": "1.0.0"},
          "vulnerabilities": [
            {"id": "GHSA-swallow-0001", "summary": "actually a critical RCE", "severity": "HIGH"}
          ]
        }
      ]
    }
  ]
}
EOF
F1_OUT=$(cd "$F1_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad-severity-shape.json 2>&1)
assert_equal "0" "$?" "F1: a malformed (non-array) .severity field still exits 0 — a tracked condition, not a crash"
F1_FINDINGS_COUNT=$(printf '%s' "$F1_OUT" | jq '.findings | length' 2>/dev/null)
assert_equal "0" "$F1_FINDINGS_COUNT" "F1: no groups present means no material finding is itemized, regardless of the malformed .severity field's content"
F1_UNRESOLVED_ID=$(printf '%s' "$F1_OUT" | jq -r '.unresolved_severity[0].id // "MISSING"' 2>/dev/null)
assert_equal "GHSA-swallow-0001" "$F1_UNRESOLVED_ID" "F1: with groups absent, the record lands in unresolved_severity via the fallback — never silently discarded, and the malformed .severity content has no bearing on this outcome"
F1_UNPARSEABLE_COUNT=$(printf '%s' "$F1_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "0" "$F1_UNPARSEABLE_COUNT" "F1: the fallback path never throws on a malformed .severity field, because that field is never read by it"

# A genuinely absent severity field behaves identically to the malformed-shape
# case above — proving .severity's presence/absence/shape is uniformly
# irrelevant now that extraction reads groups[].max_severity instead.
cat >"$F1_DIR/absent-severity.json" <<'EOF'
{"results": [{"packages": [{"package": {"name": "left-pad", "version": "1.0.0"}, "vulnerabilities": [{"id": "GHSA-absent-0001", "summary": "no severity field at all"}]}]}]}
EOF
F1_ABSENT_OUT=$(cd "$F1_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan absent-severity.json 2>&1)
F1_ABSENT_UNRESOLVED=$(printf '%s' "$F1_ABSENT_OUT" | jq -r '.unresolved_severity[0].id // "MISSING"' 2>/dev/null)
assert_equal "GHSA-absent-0001" "$F1_ABSENT_UNRESOLVED" "F1: a genuinely absent severity field still lands in unresolved_severity, not unparseable_records"
F1_ABSENT_UNPARSEABLE=$(printf '%s' "$F1_ABSENT_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "0" "$F1_ABSENT_UNPARSEABLE" "F1: an absent severity field is not mis-routed to unparseable_records"

# --- F1-successor (issue #137): the new swallow-risk surface is groups[]
# itself, not .severity. A malformed groups[] entry (wrong type, not an
# object) must throw inside safe_finding's try/catch and land in
# unparseable_records — never silently vanish with zero trace, the same
# failure mode the original F1 fix closed one field over. -------------------
F1B_DIR=$(_dossier_safe_mktemp_dir "f1-successor-bad-group-entry")
cat >"$F1B_DIR/bad-group-entry.json" <<'EOF'
{
  "results": [
    {
      "packages": [
        {
          "package": {"name": "left-pad", "version": "1.0.0"},
          "groups": ["this-should-be-an-object-not-a-string"],
          "vulnerabilities": [
            {"id": "GHSA-badgroup-0001", "summary": "actually a critical RCE"}
          ]
        }
      ]
    }
  ]
}
EOF
F1B_OUT=$(cd "$F1B_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad-group-entry.json 2>&1)
assert_equal "0" "$?" "F1-successor: a malformed groups[] entry still exits 0 — a tracked condition, not a crash"
F1B_FINDINGS_COUNT=$(printf '%s' "$F1B_OUT" | jq '.findings | length' 2>/dev/null)
assert_equal "0" "$F1B_FINDINGS_COUNT" "F1-successor: the malformed group entry is never itemized as a material finding"
F1B_UNPARSEABLE_COUNT=$(printf '%s' "$F1B_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "1" "$F1B_UNPARSEABLE_COUNT" "F1-successor: a non-object groups[] entry is tracked in unparseable_records — never silently discarded with zero trace"

# --- F1-successor-2 (/flow:review PR#137 findings, code-reviewer P1): the
# group-summary lookup ($vulns[]? | select(.id as $vid | ...)) is shared
# across EVERY group's build in a package. A single non-object element
# anywhere in vulnerabilities[] threw when that shared lookup indexed .id —
# and because the throw happened inside safe_finding's own try/catch, it
# took down the whole group's build, but since the lookup is re-evaluated
# per group, a bad element poisoned ALL of that package's groups, not just
# whichever group's summary happened to hit it. Reproduced live before the
# fix: two genuinely valid groups (Critical 9.8, High 8.1) alongside one bad
# element in vulnerabilities[] produced findings:[] and both groups routed
# to unparseable_records with a generic id — silently discarding two real
# findings. Confirmed by direct reproduction that this is reachable from
# ingested scan-artifact content, not only from a live scanner bug. -------
F1C_DIR=$(_dossier_safe_mktemp_dir "f1-successor-2-bad-vuln-element")
cat >"$F1C_DIR/bad-vuln-element.json" <<'EOF'
{
  "results": [
    {
      "packages": [
        {
          "package": {"name": "left-pad", "version": "1.0.0"},
          "groups": [
            {"ids": ["GHSA-good-0001"], "aliases": ["CVE-2024-88880"], "max_severity": "9.8"},
            {"ids": ["GHSA-good-0002"], "aliases": ["CVE-2024-88881"], "max_severity": "8.1"}
          ],
          "vulnerabilities": [
            {"id": "GHSA-good-0001", "summary": "a real critical finding"},
            "this-is-a-malformed-non-object-element",
            {"id": "GHSA-good-0002", "summary": "a real high finding"}
          ]
        }
      ]
    }
  ]
}
EOF
F1C_OUT=$(cd "$F1C_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad-vuln-element.json 2>&1)
assert_equal "0" "$?" "F1-successor-2: a malformed vulnerabilities[] entry alongside valid groups still exits 0"
F1C_FINDINGS_COUNT=$(printf '%s' "$F1C_OUT" | jq '.findings | length' 2>/dev/null)
assert_equal "2" "$F1C_FINDINGS_COUNT" "F1-successor-2: both genuinely valid groups still resolve to material findings — one bad vulnerabilities[] element does not poison every group's summary lookup in the same package"
F1C_IDS=$(printf '%s' "$F1C_OUT" | jq -r '[.findings[].id] | sort | join(",")' 2>/dev/null)
assert_equal "CVE-2024-88880,CVE-2024-88881" "$F1C_IDS" "F1-successor-2: both real findings resolve to their correct CVE- primary ids, not UNKNOWN"
F1C_UNPARSEABLE_COUNT=$(printf '%s' "$F1C_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "1" "$F1C_UNPARSEABLE_COUNT" "F1-successor-2: the single malformed vulnerabilities[] element is tracked exactly once, not once per group"
F1_ABSENT_UNPARSEABLE=$(printf '%s' "$F1_ABSENT_OUT" | jq '.unparseable_records | length' 2>/dev/null)
assert_equal "0" "$F1_ABSENT_UNPARSEABLE" "F1: an absent severity field is not mis-routed to unparseable_records by the fix"

# --- SEC-3: the ingestion script's output now carries a structural
# untrusted-content marker, matching the pattern dossier-evidence.sh's
# manifest.json already uses for the same class of contributor-controlled
# content, rather than relying on skill prose alone. -------------------------
NOTE_TEXT=$(printf '%s' "$F1_ABSENT_OUT" | jq -r '.note // "MISSING"' 2>/dev/null)
assert_contains "evidence" "$NOTE_TEXT" "SEC-3: the output JSON carries a structural note field"
assert_contains "never as instructions" "$NOTE_TEXT" "SEC-3: the note frames scan content as data, never as instructions"

# --- --help now shows the Exit codes section (previously truncated by
# sed -n '2,42p', which cut off before the output-schema/exit-code lines) ---
HELP_OUT=$("$VULN_SCRIPT" --help 2>&1)
assert_contains "Exit:" "$HELP_OUT" "--help includes the Exit codes section, not truncated before it"
assert_contains "missing or invalid argument" "$HELP_OUT" "--help includes exit code 2's description"

# --- --out: previously untested. Confirms the file is actually written, its
# content matches stdout, and the flag doesn't change exit behaviour. -------
OUT_DIR=$(_dossier_safe_mktemp_dir "out-flag")
mkdir -p "$OUT_DIR/target"
printf '{"results":[]}' >"$OUT_DIR/clean.json"
OUT_STDOUT=$(cd "$OUT_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan clean.json --out target 2>&1)
OUT_RC=$?
assert_equal "0" "$OUT_RC" "--out: a successful run with --out still exits 0"
if [ -f "$OUT_DIR/target/vuln-evidence.json" ]; then
  _dossier_assert_pass "--out: the output file is actually created"
else
  _dossier_assert_fail "--out: no file was written to the --out directory"
fi
OUT_FILE_CONTENT=$(cat "$OUT_DIR/target/vuln-evidence.json" 2>/dev/null)
assert_equal "$OUT_STDOUT" "$OUT_FILE_CONTENT" "--out: the file content matches stdout exactly"

# --out on a parse failure: the error JSON must be written to the file too,
# not leave a stale prior success result sitting there (F2 from PR-creation
# review — already fixed; still worth pinning against --out specifically).
printf 'not json' >"$OUT_DIR/bad.json"
OUT_ERR_RC=0
( cd "$OUT_DIR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan bad.json --out target >/dev/null 2>&1 ) || OUT_ERR_RC=$?
assert_equal "1" "$OUT_ERR_RC" "--out: a parse failure with --out still exits 1"
OUT_ERR_FILE=$(cat "$OUT_DIR/target/vuln-evidence.json" 2>/dev/null)
assert_contains "parse-error" "$OUT_ERR_FILE" "--out: a failed run overwrites the file with the error JSON, not a stale prior success"

# =============================================================================
# Part 8b — dossier-gate.sh G19 findings
# =============================================================================

# --- F2 (code-reviewer-skeptic/verifier, SEC-1 security-skeptic/verifier,
# ERR-2 error-handler-skeptic — 5 independent agents): the Risk register
# Status check was a denylist of the single literal string "open", so a
# capitalized variant or an unfilled template placeholder disposed a
# genuinely undisposed Critical/High finding. Now an allowlist against the
# template's own closed enum, case-normalized, with placeholder rejection. --
G19_STATUS_CASE_DIR=$(_dossier_safe_mktemp_dir "f2-status-case")
g19_fixture "$G19_STATUS_CASE_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0050 | osv-scanner reports GHSA-f2-0001 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-f2-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0010 | axios SSRF | dependency | medium | high | high | high | [EV-0050] | upgrade planned | Jane Doe | Open |'
assert_equal "FAIL" "$(g19_result "$G19_STATUS_CASE_DIR")" "F2: a capitalized Status value (\"Open\") no longer disposes a Critical/High finding"

G19_STATUS_PLACEHOLDER_DIR=$(_dossier_safe_mktemp_dir "f2-status-placeholder")
g19_fixture "$G19_STATUS_PLACEHOLDER_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0051 | osv-scanner reports GHSA-f2-0002 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-f2-0002, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0011 | axios SSRF, unfilled template row | dependency | medium | high | high | high | [EV-0051] | {fill} | {fill} | {fill} |'
assert_equal "FAIL" "$(g19_result "$G19_STATUS_PLACEHOLDER_DIR")" "F2/F4: an unfilled {fill} Status/Owner placeholder no longer disposes a finding"

# --- F5/SEC-4 (code-reviewer-verifier, security-skeptic): Category is now
# case-insensitive — a capitalized "Dependency" must still dispose a
# genuinely-mitigated finding, not spuriously FAIL. --------------------------
G19_CATEGORY_CASE_DIR=$(_dossier_safe_mktemp_dir "f5-category-case")
g19_fixture "$G19_CATEGORY_CASE_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0052 | osv-scanner reports GHSA-f5-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-f5-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0012 | axios SSRF, capitalized Category | Dependency | medium | critical | high | high | [EV-0052] | upgraded | Jane Doe | closed |'
assert_equal "PASS" "$(g19_result "$G19_CATEGORY_CASE_DIR")" "F5/SEC-4: a capitalized Category (\"Dependency\") still disposes an otherwise fully-qualifying finding"

# --- F3 (code-reviewer-verifier, design decision): "accepted" is no longer a
# valid disposition via the Risk register alone — the template requires a
# named human with the authority to accept, which a bare Owner cell does not
# establish. An accepted disposition must go through the Accepted risks
# table, with its accepter/date/basis/review-date accountability fields. ----
G19_RISKACCEPTED_DIR=$(_dossier_safe_mktemp_dir "f3-risk-register-accepted")
g19_fixture "$G19_RISKACCEPTED_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0053 | osv-scanner reports GHSA-f3-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-f3-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0013 | axios SSRF, marked accepted via Risk register alone | dependency | medium | critical | high | high | [EV-0053] | none planned | Jane Doe | accepted |'
assert_equal "FAIL" "$(g19_result "$G19_RISKACCEPTED_DIR")" "F3: Status=accepted in the Risk register alone (no Accepted risks row) no longer disposes the finding"

# --- F4 (code-reviewer-verifier): Accepted risks' Accepter/Basis cells
# accepted the literal unfilled template placeholder {fill}. -----------------
G19_ACC_PLACEHOLDER_DIR=$(_dossier_safe_mktemp_dir "f4-accepted-placeholder")
g19_fixture "$G19_ACC_PLACEHOLDER_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0054 | osv-scanner reports GHSA-f4-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-f4-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0054] | {fill} | 2026-07-20 | {fill} | 2026-10-20 | {fill} |'
assert_equal "FAIL" "$(g19_result "$G19_ACC_PLACEHOLDER_DIR")" "F4: unfilled {fill} Accepter/Basis placeholders no longer dispose a finding via Accepted risks"

# --- New (SEC-2 security-skeptic, SEC-3 security-verifier, F1
# code-reviewer-verifier — 3 independent agents): a scan that parsed cleanly
# (status=parsed, not partial) but recorded a finding with unresolved
# severity, and zero confirmed Critical/High rows, must be INCONCLUSIVE —
# materiality unknown is not the same as clean. Distinct from the existing
# status=partial test above: here the COVERAGE row itself is status=parsed. -
G19_UNRESOLVED_ONLY_DIR=$(_dossier_safe_mktemp_dir "unresolved-only")
g19_fixture "$G19_UNRESOLVED_ONLY_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0060 | osv-scanner: severity could not be derived for GHSA-unresolved-0001 | U | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding-unresolved |' \
''
G19_UNRESOLVED_ONLY_RESULT=$(g19_result "$G19_UNRESOLVED_ONLY_DIR")
assert_equal "INCONCLUSIVE" "$G19_UNRESOLVED_ONLY_RESULT" "New: status=parsed with an unresolved-severity row and zero confirmed Critical/High rows is INCONCLUSIVE, not a vacuous PASS"
G19_UNRESOLVED_ONLY_EVIDENCE=$(g19_evidence "$G19_UNRESOLVED_ONLY_DIR")
assert_contains "unresolved severity" "$G19_UNRESOLVED_ONLY_EVIDENCE" "New: the unresolved-severity branch names itself distinctly"

# A confirmed, undisposed Critical finding alongside an unrelated unresolved
# row must still FAIL, not soften to INCONCLUSIVE — FAIL outranks
# INCONCLUSIVE, matching the gate's existing overall precedence.
G19_UNRESOLVED_PLUS_FAIL_DIR=$(_dossier_safe_mktemp_dir "unresolved-plus-fail")
g19_fixture "$G19_UNRESOLVED_PLUS_FAIL_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0061 | osv-scanner: severity could not be derived for GHSA-unresolved-0002 | U | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding-unresolved |
| EV-0062 | osv-scanner reports GHSA-confirmed-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-confirmed-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
''
assert_equal "FAIL" "$(g19_result "$G19_UNRESOLVED_PLUS_FAIL_DIR")" "New: a confirmed undisposed Critical finding still FAILs even alongside an unrelated unresolved-severity row"

# --- New (SEC-2 security-verifier, ERR-3 error-handler-skeptic — 2
# independent agents): the Accepted risks Review date was only checked for
# calendar validity, never compared to "now" — a review date from years ago
# disposed a Critical finding permanently. -----------------------------------
G19_STALE_REVIEW_DIR=$(_dossier_safe_mktemp_dir "stale-review-date")
g19_fixture "$G19_STALE_REVIEW_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0070 | osv-scanner reports GHSA-stale-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-stale-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0070] | Jane Doe, VP Engineering | 2020-01-01 | Low exploitability at the time | 2020-01-01 | Slack thread, 2020-01-01 |'
assert_equal "FAIL" "$(g19_result "$G19_STALE_REVIEW_DIR")" "New: an Accepted-risks Review date years in the past no longer disposes a Critical finding"

# A review date in the future (not yet elapsed) must still dispose normally —
# negative control proving the fix checks "elapsed", not "always reject".
G19_FUTURE_REVIEW_DIR=$(_dossier_safe_mktemp_dir "future-review-date")
g19_fixture "$G19_FUTURE_REVIEW_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0071 | osv-scanner reports GHSA-future-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-future-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| [EV-0071] | Jane Doe, VP Engineering | 2026-07-20 | Low exploitability in this deployment | 2099-01-01 | Slack thread, 2026-07-20 |'
assert_equal "PASS" "$(g19_result "$G19_FUTURE_REVIEW_DIR")" "New: an Accepted-risks Review date still in the future disposes the finding normally"

# --- ERR-2 (error-handler-inspector-verifier): the citation-range regex
# could not distinguish the en-dash range form from the schema-legal
# comma-separated LIST form, so [EV-0042, EV-0099] falsely disposed an
# unrelated EV-0050 that merely fell numerically between the two listed,
# non-adjacent ids. g19_row_cites now splits on the list separator before
# ever looking for a range. --------------------------------------------------
G19_COMMA_NOT_RANGE_DIR=$(_dossier_safe_mktemp_dir "err2-comma-not-range")
g19_fixture "$G19_COMMA_NOT_RANGE_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0042 | osv-scanner reports GHSA-list-0001 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-list-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |
| EV-0050 | osv-scanner reports GHSA-list-0002 in lodash@4.17.15, severity Critical | R | `scan.json` — osv-scanner, GHSA-list-0002, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |
| EV-0099 | osv-scanner reports GHSA-list-0003 in requests@2.25.0, severity High | R | `scan.json` — osv-scanner, GHSA-list-0003, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=High |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0020 | two of three findings triaged together, cited as a comma-separated LIST, not a range | dependency | medium | high | high | high | [EV-0042, EV-0099] | upgraded both | Jane Doe | closed |'
G19_COMMA_RESULT=$(g19_result "$G19_COMMA_NOT_RANGE_DIR")
assert_equal "FAIL" "$G19_COMMA_RESULT" "ERR-2: EV-0050 (never cited, only numerically between the two listed ids) is still undisposed — the comma-list is not misread as a range"
G19_COMMA_EVIDENCE=$(g19_evidence "$G19_COMMA_NOT_RANGE_DIR")
assert_contains "EV-0050" "$G19_COMMA_EVIDENCE" "ERR-2: the evidence names the genuinely undisposed finding"
assert_not_contains "EV-0042" "$G19_COMMA_EVIDENCE" "ERR-2: EV-0042, actually cited in the list, is not also reported as undisposed"
assert_not_contains "EV-0099" "$G19_COMMA_EVIDENCE" "ERR-2: EV-0099, actually cited in the list, is not also reported as undisposed"

# --- ERR-3 (error-handler-inspector-skeptic): a vuln-finding row whose
# formatting drifts beyond mere case (unexpected spacing around `=`) is
# counted by the loose FINDING_ROWS scan but was previously invisible to the
# strict selection loop — silently treated as "nothing to see" rather than
# flagged. Now reconciled: a leftover, unrecognized row makes G19
# INCONCLUSIVE instead of vanishing. ------------------------------------------
G19_MALFORMED_TAG_DIR=$(_dossier_safe_mktemp_dir "err3-malformed-tag")
g19_fixture "$G19_MALFORMED_TAG_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0080 | osv-scanner reports GHSA-err3-0001 in axios@0.21.1, severity High | R | `scan.json` — osv-scanner, GHSA-err3-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity = High |' \
''
G19_MALFORMED_TAG_RESULT=$(g19_result "$G19_MALFORMED_TAG_DIR")
assert_equal "INCONCLUSIVE" "$G19_MALFORMED_TAG_RESULT" "ERR-3: a vuln-finding row with non-canonical tag spacing is INCONCLUSIVE, not silently treated as a clean scan"
G19_MALFORMED_TAG_EVIDENCE=$(g19_evidence "$G19_MALFORMED_TAG_DIR")
assert_contains "did not match" "$G19_MALFORMED_TAG_EVIDENCE" "ERR-3: the reconciliation branch names itself distinctly"

# Case drift alone (not spacing) must now be tolerated directly by the main
# selection loop, not merely caught by the reconciliation fallback.
G19_CASE_DRIFT_DIR=$(_dossier_safe_mktemp_dir "err3-case-drift")
g19_fixture "$G19_CASE_DRIFT_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0081 | osv-scanner reports GHSA-err3-0002 in axios@0.21.1, severity critical | R | `scan.json` — osv-scanner, GHSA-err3-0002, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=critical |' \
''
G19_CASE_DRIFT_RESULT=$(g19_result "$G19_CASE_DRIFT_DIR")
assert_equal "FAIL" "$G19_CASE_DRIFT_RESULT" "ERR-3: a lowercase severity value (severity=critical) is still recognized and correctly FAILs as undisposed"
G19_CASE_DRIFT_EVIDENCE=$(g19_evidence "$G19_CASE_DRIFT_DIR")
assert_contains "EV-0081 (Critical)" "$G19_CASE_DRIFT_EVIDENCE" "ERR-3: the recognized severity is normalized back to canonical Title-case in the evidence text"

# --- ERR-6 (error-handler-inspector-verifier): an unreadable (as opposed to
# absent) risk register was indistinguishable from a genuine FAIL — a
# permissions problem misdirected remediation toward triaging findings that
# may already be disposed in a file G19 simply couldn't open. ----------------
if [ "$(id -u)" != "0" ]; then
  G19_UNREADABLE_DIR=$(_dossier_safe_mktemp_dir "err6-unreadable-risks")
  g19_fixture "$G19_UNREADABLE_DIR" \
'| EV-0001 | Dependency vulnerability scan: osv-scanner on package-lock.json, 2026-07-28 | R | `scan.json` — osv-scanner, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-scan-coverage status=parsed |
| EV-0090 | osv-scanner reports GHSA-err6-0001 in axios@0.21.1, severity Critical | R | `scan.json` — osv-scanner, GHSA-err6-0001, retrieved 2026-07-28 | yes | 2 | main | 2026-07-28 | none | Internal | no | 05-due-diligence/assets-dependencies-and-licenses.md | vuln-finding severity=Critical |' \
'## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-0030 | axios SSRF, disposed in a file the gate cannot read | dependency | medium | critical | high | high | [EV-0090] | upgraded | Jane Doe | closed |'
  chmod 000 "$G19_UNREADABLE_DIR/docs/dossier/04-operating/decisions-technical-debt-and-risks.md"
  G19_UNREADABLE_RESULT=$(g19_result "$G19_UNREADABLE_DIR")
  chmod 644 "$G19_UNREADABLE_DIR/docs/dossier/04-operating/decisions-technical-debt-and-risks.md" 2>/dev/null
  assert_equal "INCONCLUSIVE" "$G19_UNREADABLE_RESULT" "ERR-6: an unreadable (not absent) risk register is INCONCLUSIVE, distinct from a genuine FAIL"
else
  _dossier_assert_pass "ERR-6: skipped — running as root, chmod 000 does not enforce unreadability"
fi

_dossier_test_summary
