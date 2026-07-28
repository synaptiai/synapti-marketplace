#!/usr/bin/env bash
# Issue #137, AC2/AC3/AC4: dossier-scan-quality.sh executes pyscn as an
# isolated pre-agent step, gated by dossier.engagement.allowedActions
# .runCodeQualityScan, and reports every non-genuine-success case honestly
# rather than as a clean scan. Artifact-only (no evidence-ledger citation —
# confirmed non-goal, unlike the security scan's AC1).

_dossier_test_begin "quality-scan-execution"

SCRIPT="$(pwd)/plugins/dossier/bin/dossier-scan-quality.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$SCRIPT" ]; then
  _dossier_assert_fail "$SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# =============================================================================
# Disabled (default) — pyscn must never be invoked when the capability flag
# is off, proven with a tripwire binary: a fake `pyscn` on PATH that writes
# a marker file if ever executed.
# =============================================================================
DIR_DISABLED=$(_dossier_safe_mktemp_dir "disabled")
mkdir -p "$DIR_DISABLED/target" "$DIR_DISABLED/tripwire-bin"
printf 'def f():\n    pass\n' >"$DIR_DISABLED/target/mod.py"
TRIPWIRE_MARKER="$DIR_DISABLED/pyscn-was-invoked"
cat >"$DIR_DISABLED/tripwire-bin/pyscn" <<EOF
#!/usr/bin/env bash
touch "$TRIPWIRE_MARKER"
EOF
chmod +x "$DIR_DISABLED/tripwire-bin/pyscn"

OUT_DISABLED=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
RC_DISABLED=$?
assert_equal "0" "$RC_DISABLED" "disabled: exits 0 (an honest not-run outcome, never a CI-breaking failure)"
STATUS_DISABLED=$(printf '%s' "$OUT_DISABLED" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_DISABLED" "disabled: status is disabled by default (runCodeQualityScan defaults false)"

OUT_DISABLED_TRIPWIRE=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$DIR_DISABLED/tripwire-bin:$PATH" "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
STATUS_DISABLED_TRIPWIRE=$(printf '%s' "$OUT_DISABLED_TRIPWIRE" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_DISABLED_TRIPWIRE" "disabled: still disabled even with a real pyscn on PATH"
if [ -e "$TRIPWIRE_MARKER" ]; then
  _dossier_assert_fail "disabled: pyscn tripwire was invoked — the disabled path must short-circuit before any tool invocation"
else
  _dossier_assert_pass "disabled: pyscn tripwire was never invoked — the flag check happens before any tool lookup"
fi

# =============================================================================
# Invalid input: a nonexistent target directory is an explicit error.
# =============================================================================
OUT_BADTARGET=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$SCRIPT" --target "$DIR_DISABLED/does-not-exist" 2>&1)
STATUS_BADTARGET=$(printf '%s' "$OUT_BADTARGET" | jq -r '.status' 2>/dev/null)
assert_equal "error" "$STATUS_BADTARGET" "invalid target: a nonexistent target directory is an explicit error, never a clean result"

# =============================================================================
# Tool unavailable — fails closed, distinct from a clean scan.
# =============================================================================
OUT_NOTOOL=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH=/usr/bin:/bin \
  "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
RC_NOTOOL=$?
assert_equal "0" "$RC_NOTOOL" "tool-unavailable: still exits 0 — an honest not-run outcome"
STATUS_NOTOOL=$(printf '%s' "$OUT_NOTOOL" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_NOTOOL" "tool-unavailable: distinct status, never fabricated as a clean scan"

# =============================================================================
# A target with no Python files at all is an explicit error — pyscn itself
# produces no report file in this case (verified empirically: "Error: no
# Python files found in the specified paths", no .pyscn/reports/ entry ever
# created), so this must never read as a clean zero-issues result.
# =============================================================================
if command -v pyscn >/dev/null 2>&1; then
  DIR_NOPY=$(_dossier_safe_mktemp_dir "no-python-files")
  mkdir -p "$DIR_NOPY/target"
  printf 'hello\n' >"$DIR_NOPY/target/readme.txt"
  OUT_NOPY=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_NOPY/target" 2>&1)
  STATUS_NOPY=$(printf '%s' "$OUT_NOPY" | jq -r '.status' 2>/dev/null)
  assert_equal "error" "$STATUS_NOPY" "no Python files: an explicit error, never a clean zero-issues result"
else
  _dossier_assert_pass "pyscn unavailable on PATH — the no-Python-files assertion was skipped"
fi

# =============================================================================
# Timeout — a stub tool that outlives the configured timeout is terminated.
# =============================================================================
DIR_TIMEOUT=$(_dossier_safe_mktemp_dir "timeout")
mkdir -p "$DIR_TIMEOUT/fakebin" "$DIR_TIMEOUT/target"
printf 'def f():\n    pass\n' >"$DIR_TIMEOUT/target/mod.py"
cat >"$DIR_TIMEOUT/fakebin/pyscn" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$DIR_TIMEOUT/fakebin/pyscn"
OUT_TIMEOUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true DOSSIER_SCAN_TIMEOUT_SECONDS=2 \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$DIR_TIMEOUT/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_TIMEOUT/target" 2>/dev/null)
RC_TIMEOUT=$?
assert_equal "0" "$RC_TIMEOUT" "timeout: still exits 0 — an honest not-run outcome"
STATUS_TIMEOUT=$(printf '%s' "$OUT_TIMEOUT" | jq -r '.status' 2>/dev/null)
assert_equal "timeout" "$STATUS_TIMEOUT" "timeout: distinct status"

# =============================================================================
# AC2 real end-to-end run: a fixture with an intentional dead-code function
# (unreachable statement after return) and a high-nesting-complexity
# function, scanned for real. Proves both mixed-casing report sections
# (dead_code: snake_case; complexity: PascalCase — verified empirically to
# differ within the SAME report) are correctly carried through. Per the
# project's precedent (workflow-template.test.sh:17,44): degrade to an
# honest, NAMED skip locally when the tool is absent; CI installs it.
# =============================================================================
if command -v pyscn >/dev/null 2>&1; then
  DIR_E2E=$(_dossier_safe_mktemp_dir "ac2-e2e")
  mkdir -p "$DIR_E2E/target" "$DIR_E2E/out"
  cat >"$DIR_E2E/target/bad.py" <<'EOF'
def unreachable_after_return(x):
    return x
    print("dead code")

def high_complexity(a, b, c, d, e):
    if a:
        if b:
            if c:
                if d:
                    if e:
                        return 1
                    else:
                        return 2
                elif d:
                    return 3
            elif c:
                return 4
        elif b:
            return 5
    return 0
EOF
  OUT_E2E=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_E2E/target" --out "$DIR_E2E/out" 2>&1)
  RC_E2E=$?
  assert_equal "0" "$RC_E2E" "AC2 e2e: a real scan against a fixture with known issues exits 0"
  STATUS_E2E=$(printf '%s' "$OUT_E2E" | jq -r '.status' 2>/dev/null)
  assert_equal "ok" "$STATUS_E2E" "AC2 e2e: status is ok"

  DEADCODE_COUNT=$(printf '%s' "$OUT_E2E" | jq -r '.dead_code.summary.total_findings // "MISSING"' 2>/dev/null)
  case "$DEADCODE_COUNT" in
    MISSING|0) _dossier_assert_fail "AC2 e2e: expected at least one dead-code finding (snake_case dead_code.summary.total_findings), got $DEADCODE_COUNT" ;;
    *) _dossier_assert_pass "AC2 e2e: dead_code section's snake_case keys correctly carried through ($DEADCODE_COUNT finding(s))" ;;
  esac
  DEADCODE_SEVERITY=$(printf '%s' "$OUT_E2E" | jq -r '.dead_code.files[0].functions[0].findings[0].severity // "MISSING"' 2>/dev/null)
  assert_equal "critical" "$DEADCODE_SEVERITY" "AC2 e2e: dead_code's nested snake_case severity field (unreachable-after-return) is correctly carried through"

  COMPLEXITY_FUNCS=$(printf '%s' "$OUT_E2E" | jq -r '.complexity.Summary.TotalFunctions // "MISSING"' 2>/dev/null)
  case "$COMPLEXITY_FUNCS" in
    MISSING|0) _dossier_assert_fail "AC2 e2e: expected complexity.Summary.TotalFunctions (PascalCase) to be populated, got $COMPLEXITY_FUNCS" ;;
    *) _dossier_assert_pass "AC2 e2e: complexity section's PascalCase keys correctly carried through ($COMPLEXITY_FUNCS function(s) analyzed)" ;;
  esac
  COMPLEXITY_NAME=$(printf '%s' "$OUT_E2E" | jq -r '.complexity.Functions[] | select(.Name == "high_complexity") | .Name // "MISSING"' 2>/dev/null)
  assert_equal "high_complexity" "$COMPLEXITY_NAME" "AC2 e2e: the high-complexity function is correctly identified by name (PascalCase .Name field)"

  ARTIFACT_E2E=$(printf '%s' "$OUT_E2E" | jq -r '.artifact_path' 2>/dev/null)
  assert_file_exists "$ARTIFACT_E2E" "AC2 e2e: the raw pyscn artifact file actually exists on disk"
else
  _dossier_assert_pass "pyscn unavailable on PATH — the real end-to-end AC2 assertion was skipped (run.sh's CI job installs the pinned version so this skip is never exercised there)"
fi

# =============================================================================
# Report-selection regression: running the wrapper twice in sequence must
# never return a stale (first-run) artifact on the second run.
# =============================================================================
if command -v pyscn >/dev/null 2>&1; then
  DIR_RERUN=$(_dossier_safe_mktemp_dir "rerun")
  mkdir -p "$DIR_RERUN/target" "$DIR_RERUN/out"
  printf 'def f():\n    pass\n' >"$DIR_RERUN/target/mod.py"
  DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_RERUN/target" --out "$DIR_RERUN/out" >/dev/null 2>&1
  FIRST_MTIME=$(stat -f %m "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null || stat -c %Y "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null)
  sleep 2
  DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_RERUN/target" --out "$DIR_RERUN/out" >/dev/null 2>&1
  SECOND_MTIME=$(stat -f %m "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null || stat -c %Y "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null)
  if [ -n "$FIRST_MTIME" ] && [ -n "$SECOND_MTIME" ] && [ "$SECOND_MTIME" -gt "$FIRST_MTIME" ]; then
    _dossier_assert_pass "report selection: a second run produces a strictly newer artifact, never the first run's stale report"
  else
    _dossier_assert_fail "report selection: second run's artifact ($SECOND_MTIME) is not newer than the first's ($FIRST_MTIME) — possible stale-report bug"
  fi
else
  _dossier_assert_pass "pyscn unavailable on PATH — the report-selection regression was skipped"
fi

# =============================================================================
# AC3 (script-local half): the quality wrapper never consults
# runSecurityScan — proven by enabling only that flag and confirming the
# quality wrapper still reports disabled.
# =============================================================================
OUT_CROSSFLAG=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
STATUS_CROSSFLAG=$(printf '%s' "$OUT_CROSSFLAG" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_CROSSFLAG" "AC3: runSecurityScan=true alone never enables the quality wrapper"

# =============================================================================
# AC3 (joint, issue #137 Task 26): with BOTH scripts invoked under one shared
# config where only runCodeQualityScan is true, the quality wrapper proceeds
# while the security wrapper independently reports disabled — and vice
# versa. Mirrors the joint assertion in vuln-scan-execution.test.sh (AC3's
# own stated verification names both test files).
# =============================================================================
SECURITY_SCRIPT="$(pwd)/plugins/dossier/bin/dossier-scan-security.sh"
if [ -x "$SECURITY_SCRIPT" ]; then
  DIR_JOINT=$(_dossier_safe_mktemp_dir "ac3-joint")
  mkdir -p "$DIR_JOINT/sec-target" "$DIR_JOINT/qual-target"
  printf 'def f():\n    pass\n' >"$DIR_JOINT/qual-target/mod.py"

  QUAL_OUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=false \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_JOINT/qual-target" 2>&1)
  SEC_OUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=false \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SECURITY_SCRIPT" --target "$DIR_JOINT/sec-target" 2>&1)
  QUAL_STATUS=$(printf '%s' "$QUAL_OUT" | jq -r '.status' 2>/dev/null)
  SEC_STATUS=$(printf '%s' "$SEC_OUT" | jq -r '.status' 2>/dev/null)
  assert_not_contains "disabled" "$QUAL_STATUS" "AC3 joint: quality proceeds (not disabled) when only runCodeQualityScan is true"
  assert_equal "disabled" "$SEC_STATUS" "AC3 joint: security independently stays disabled under the identical shared environment"
else
  _dossier_assert_fail "$SECURITY_SCRIPT missing or not executable — AC3 joint assertions could not run"
fi

# =============================================================================
# CLI hygiene
# =============================================================================
"$SCRIPT" --target >/dev/null 2>&1
assert_equal "2" "$?" "exits 2 when --target is given with no path"
"$SCRIPT" >/dev/null 2>&1
assert_equal "2" "$?" "exits 2 when the required --target flag is omitted entirely"
"$SCRIPT" --target "$DIR_DISABLED/target" --out >/dev/null 2>&1
assert_equal "2" "$?" "exits 2 when --out is given with no path"
"$SCRIPT" --nonexistent-flag >/dev/null 2>&1
assert_equal "2" "$?" "exits 2 on an unrecognized flag"

_dossier_test_summary
