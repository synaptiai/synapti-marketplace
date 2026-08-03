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
_dossier_require_mktemp_dir DIR_DISABLED "disabled"
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
  _dossier_require_mktemp_dir DIR_NOPY "no-python-files"
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
# The stub `exec`s into `sleep` itself (one process, matching a real
# compiled tool's shape, not a wrapper script with a child) so this test can
# verify the tool process is ACTUALLY killed, not merely that the wrapper
# reports "timeout" while the real process leaks on, orphaned.
# =============================================================================
_dossier_require_mktemp_dir DIR_TIMEOUT "timeout"
mkdir -p "$DIR_TIMEOUT/fakebin" "$DIR_TIMEOUT/target"
printf 'def f():\n    pass\n' >"$DIR_TIMEOUT/target/mod.py"
TIMEOUT_PID_MARKER="$DIR_TIMEOUT/pyscn.pid"
cat >"$DIR_TIMEOUT/fakebin/pyscn" <<EOF
#!/usr/bin/env bash
echo \$\$ > "$TIMEOUT_PID_MARKER"
exec sleep 30
EOF
chmod +x "$DIR_TIMEOUT/fakebin/pyscn"
OUT_TIMEOUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true DOSSIER_SCAN_TIMEOUT_SECONDS=2 \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$DIR_TIMEOUT/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_TIMEOUT/target" 2>/dev/null)
RC_TIMEOUT=$?
assert_equal "0" "$RC_TIMEOUT" "timeout: still exits 0 — an honest not-run outcome"
STATUS_TIMEOUT=$(printf '%s' "$OUT_TIMEOUT" | jq -r '.status' 2>/dev/null)
assert_equal "timeout" "$STATUS_TIMEOUT" "timeout: distinct status"

if [ -s "$TIMEOUT_PID_MARKER" ]; then
  TOOL_TIMEOUT_PID=$(cat "$TIMEOUT_PID_MARKER")
  # The wrapper's own poll loop already slept past TERM/KILL delivery before
  # returning; poll briefly regardless to absorb scheduler jitter.
  _still_alive=1
  for _ in 1 2 3 4 5; do
    kill -0 "$TOOL_TIMEOUT_PID" 2>/dev/null || { _still_alive=0; break; }
    sleep 0.5
  done
  if [ "$_still_alive" -eq 1 ]; then
    _dossier_assert_fail "timeout: the real tool process ($TOOL_TIMEOUT_PID) is still running after the wrapper reported timeout — TERM/KILL was sent to the wrong process"
  else
    _dossier_assert_pass "timeout: the real tool process was actually terminated, not merely orphaned while the wrapper reports timeout"
  fi
else
  _dossier_assert_fail "timeout: the tool stub never wrote its PID marker — cannot verify termination"
fi

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
  _dossier_require_mktemp_dir DIR_E2E "ac2-e2e"
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
  _dossier_require_mktemp_dir DIR_RERUN "rerun"
  mkdir -p "$DIR_RERUN/target" "$DIR_RERUN/out"
  printf 'def f():\n    pass\n' >"$DIR_RERUN/target/mod.py"
  DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_RERUN/target" --out "$DIR_RERUN/out" >/dev/null 2>&1
  # Two independent command substitutions, not `A || B` inside one: GNU
  # stat's `-f` means "filesystem status", not BSD's "custom format" — on
  # Linux, `stat -f %m FILE` fails but still leaks a multi-line filesystem
  # dump to stdout before failing, which corrupts a single merged capture.
  # Verified live on Ubuntu 24.04 (GNU coreutils).
  FIRST_MTIME=$(stat -f %m "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null) || FIRST_MTIME=$(stat -c %Y "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null)
  sleep 2
  DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_RERUN/target" --out "$DIR_RERUN/out" >/dev/null 2>&1
  SECOND_MTIME=$(stat -f %m "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null) || SECOND_MTIME=$(stat -c %Y "$DIR_RERUN/out/pyscn-scan-raw.json" 2>/dev/null)
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
  _dossier_require_mktemp_dir DIR_JOINT "ac3-joint"
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

# =============================================================================
# --out write failure (error-handler-inspector P1): a fully-computed, valid
# JSON envelope must still reach stdout even when the optional --out copy
# can't be written. --out is a path nested UNDER A PLAIN FILE, guaranteeing
# mkdir -p fails structurally.
# =============================================================================
_dossier_require_mktemp_dir DIR_OUTFAIL "out-write-failure"
mkdir -p "$DIR_OUTFAIL/target"
printf 'not a directory\n' >"$DIR_OUTFAIL/blocker"
OUT_OUTFAIL=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_OUTFAIL/target" --out "$DIR_OUTFAIL/blocker/nested" 2>/dev/null)
RC_OUTFAIL=$?
assert_equal "0" "$RC_OUTFAIL" "--out under an unwritable path: still exits 0 -- a failed --out copy is not an internal-bug case"
STATUS_OUTFAIL=$(printf '%s' "$OUT_OUTFAIL" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_OUTFAIL" "--out under an unwritable path: the already-computed result still reaches stdout as valid JSON"
STDERR_OUTFAIL=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_OUTFAIL/target" --out "$DIR_OUTFAIL/blocker/nested" 2>&1 >/dev/null)
assert_contains "could not create --out directory" "$STDERR_OUTFAIL" "--out under an unwritable path: the write failure is still surfaced, on stderr as a warning rather than silently swallowed"

# =============================================================================
# Malformed DOSSIER_SCAN_TIMEOUT_SECONDS (error-handler-inspector P2): a
# non-numeric value made the ELAPSED -ge TIMEOUT_SECONDS comparison itself
# error ("integer expression expected"), read as false by [ ], silently
# disabling the poll loop's own timeout enforcement. A stub that runs for
# ~2 real seconds forces the loop to iterate at least once.
# =============================================================================
_dossier_require_mktemp_dir DIR_BADTIMEOUT "bad-timeout-env"
mkdir -p "$DIR_BADTIMEOUT/fakebin" "$DIR_BADTIMEOUT/target"
printf 'def f():\n    pass\n' >"$DIR_BADTIMEOUT/target/mod.py"
cat >"$DIR_BADTIMEOUT/fakebin/pyscn" <<'EOF'
#!/usr/bin/env bash
sleep 2
echo '{}'
EOF
chmod +x "$DIR_BADTIMEOUT/fakebin/pyscn"
STDERR_BADTIMEOUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true DOSSIER_SCAN_TIMEOUT_SECONDS=not-a-number \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$DIR_BADTIMEOUT/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_BADTIMEOUT/target" 2>&1 >/dev/null)
assert_not_contains "integer expression expected" "$STDERR_BADTIMEOUT" "a non-numeric DOSSIER_SCAN_TIMEOUT_SECONDS falls back to the documented default instead of breaking the poll loop's own comparison"

# =============================================================================
# Coverage gaps found by test-runner-verifier during PR #144 review: fail-
# closed branches that were already correct but untested.
# =============================================================================
# A plain FILE as --target is an explicit error, never a clean result.
_dossier_require_mktemp_dir DIR_FILETARGET "file-as-target"
printf 'not a directory\n' >"$DIR_FILETARGET/plainfile"
OUT_FILETARGET=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$SCRIPT" --target "$DIR_FILETARGET/plainfile" 2>&1)
STATUS_FILETARGET=$(printf '%s' "$OUT_FILETARGET" | jq -r '.status' 2>/dev/null)
assert_equal "error" "$STATUS_FILETARGET" "a plain file as --target (not a directory) is an explicit error, never a clean result"

# A readable-but-not-enterable directory (r--, no x). Skipped when the test
# runner itself is root, which bypasses directory permission checks.
if [ "$(id -u)" != "0" ]; then
  _dossier_require_mktemp_dir DIR_NOEXEC_PARENT "noexec-target"
  mkdir -p "$DIR_NOEXEC_PARENT/locked"
  chmod 644 "$DIR_NOEXEC_PARENT/locked"
  OUT_NOEXEC=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_NOEXEC_PARENT/locked" 2>&1)
  STATUS_NOEXEC=$(printf '%s' "$OUT_NOEXEC" | jq -r '.status' 2>/dev/null)
  assert_equal "error" "$STATUS_NOEXEC" "a readable-but-not-enterable directory (r--, no x) as --target is an explicit error, not a later silent cd failure"
  chmod 755 "$DIR_NOEXEC_PARENT/locked" 2>/dev/null
else
  _dossier_assert_pass "readable-but-not-enterable directory check skipped -- test runner is root, which bypasses directory permission checks entirely"
fi

# pyscn producing a report file that isn't valid JSON (distinct from
# "produced no report file at all", which is already covered elsewhere).
_dossier_require_mktemp_dir DIR_MALFORMED "malformed-report"
mkdir -p "$DIR_MALFORMED/fakebin" "$DIR_MALFORMED/target"
printf 'def f():\n    pass\n' >"$DIR_MALFORMED/target/mod.py"
cat >"$DIR_MALFORMED/fakebin/pyscn" <<'EOF'
#!/usr/bin/env bash
mkdir -p .pyscn/reports
echo 'this is not json' > .pyscn/reports/analyze_bad.json
EOF
chmod +x "$DIR_MALFORMED/fakebin/pyscn"
OUT_MALFORMED=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  PATH="$DIR_MALFORMED/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_MALFORMED/target" 2>&1)
STATUS_MALFORMED=$(printf '%s' "$OUT_MALFORMED" | jq -r '.status' 2>/dev/null)
assert_equal "error" "$STATUS_MALFORMED" "pyscn producing a report file that isn't valid JSON is an explicit error, never a clean result"

_dossier_test_summary
