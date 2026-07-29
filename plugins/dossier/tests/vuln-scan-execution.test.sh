#!/usr/bin/env bash
# Issue #137, AC1/AC3/AC4: dossier-scan-security.sh executes osv-scanner as
# an isolated pre-agent step, gated by dossier.engagement.allowedActions
# .runSecurityScan, and reports every non-genuine-success case honestly
# rather than as a clean scan.

_dossier_test_begin "vuln-scan-execution"

SCRIPT="$(pwd)/plugins/dossier/bin/dossier-scan-security.sh"
VULN_SCRIPT="$(pwd)/plugins/dossier/bin/dossier-vuln-evidence.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$SCRIPT" ]; then
  _dossier_assert_fail "$SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# =============================================================================
# Disabled (default) — osv-scanner must never be invoked when the capability
# flag is off, proven with a tripwire binary: a fake `osv-scanner` on PATH
# that writes a marker file if ever executed. If the disabled path is
# genuinely short-circuited before any tool lookup, the marker never appears.
# =============================================================================
DIR_DISABLED=$(_dossier_safe_mktemp_dir "disabled")
mkdir -p "$DIR_DISABLED/target" "$DIR_DISABLED/tripwire-bin"
TRIPWIRE_MARKER="$DIR_DISABLED/osv-scanner-was-invoked"
cat >"$DIR_DISABLED/tripwire-bin/osv-scanner" <<EOF
#!/usr/bin/env bash
touch "$TRIPWIRE_MARKER"
echo '{"results":[]}'
EOF
chmod +x "$DIR_DISABLED/tripwire-bin/osv-scanner"

OUT_DISABLED=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
RC_DISABLED=$?
assert_equal "0" "$RC_DISABLED" "disabled: exits 0 (an honest not-run outcome, never a CI-breaking failure)"
STATUS_DISABLED=$(printf '%s' "$OUT_DISABLED" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_DISABLED" "disabled: status is disabled by default (runSecurityScan defaults false)"

OUT_DISABLED_TRIPWIRE=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$DIR_DISABLED/tripwire-bin:$PATH" "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
STATUS_DISABLED_TRIPWIRE=$(printf '%s' "$OUT_DISABLED_TRIPWIRE" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_DISABLED_TRIPWIRE" "disabled: still disabled even with a real osv-scanner on PATH"
if [ -e "$TRIPWIRE_MARKER" ]; then
  _dossier_assert_fail "disabled: osv-scanner tripwire was invoked — the disabled path must short-circuit before any tool invocation"
else
  _dossier_assert_pass "disabled: osv-scanner tripwire was never invoked — the flag check happens before any tool lookup"
fi

# =============================================================================
# Invalid input: a nonexistent/unreadable/non-directory target is an
# explicit error, never a clean zero-issues result — even before the tool
# availability check, so this fires regardless of whether osv-scanner is
# installed.
# =============================================================================
OUT_BADTARGET=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$SCRIPT" --target "$DIR_DISABLED/does-not-exist" 2>&1)
STATUS_BADTARGET=$(printf '%s' "$OUT_BADTARGET" | jq -r '.status' 2>/dev/null)
assert_equal "error" "$STATUS_BADTARGET" "invalid target: a nonexistent target directory is an explicit error, never a clean result"

# =============================================================================
# Tool unavailable — fails closed, distinct from a clean scan, before
# attempting any invocation.
# =============================================================================
OUT_NOTOOL=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH=/usr/bin:/bin \
  "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
RC_NOTOOL=$?
assert_equal "0" "$RC_NOTOOL" "tool-unavailable: still exits 0 — an honest not-run outcome"
STATUS_NOTOOL=$(printf '%s' "$OUT_NOTOOL" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_NOTOOL" "tool-unavailable: distinct status, never fabricated as 0 vulnerabilities"

# =============================================================================
# Timeout — a stub tool that outlives the configured timeout is terminated,
# and its (nonexistent, since it never got to print) output is never read
# as a result.
# =============================================================================
DIR_TIMEOUT=$(_dossier_safe_mktemp_dir "timeout")
mkdir -p "$DIR_TIMEOUT/fakebin" "$DIR_TIMEOUT/target"
cat >"$DIR_TIMEOUT/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
sleep 30
echo '{"results":[]}'
EOF
chmod +x "$DIR_TIMEOUT/fakebin/osv-scanner"
OUT_TIMEOUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true DOSSIER_SCAN_TIMEOUT_SECONDS=2 \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PATH="$DIR_TIMEOUT/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_TIMEOUT/target" 2>/dev/null)
RC_TIMEOUT=$?
assert_equal "0" "$RC_TIMEOUT" "timeout: still exits 0 — an honest not-run outcome, not a hang and not a crash"
STATUS_TIMEOUT=$(printf '%s' "$OUT_TIMEOUT" | jq -r '.status' 2>/dev/null)
assert_equal "timeout" "$STATUS_TIMEOUT" "timeout: distinct status, wording distinguishable from unavailable/error"

# =============================================================================
# --offline with no cached vulnerability database — shares an exit code with
# a genuine bad-path failure, and produces valid, EMPTY-results JSON on
# stdout that is content-indistinguishable from a genuine clean scan.
# Verified live against real osv-scanner 2.4.0 during planning. This is
# AC4's highest-stakes case: an offline "clean" result must never be
# reported the same as a real clean scan.
# =============================================================================
# --offline with a MISSING cache directory (not merely empty) must refuse
# before ever invoking osv-scanner — independent of whether the real tool is
# installed, proven with the same tripwire technique used for the disabled
# path above. This closes a false-assurance gap: falling through to
# invocation here would let a real "ok" scan (from a cache osv-scanner finds
# at some location this wrapper's own guess missed) emit an offline_caveat
# unconditionally claiming the result is "age-checked before this scan ran"
# when no age check occurred at all.
DIR_MISSING_CACHE=$(_dossier_safe_mktemp_dir "offline-missing-cache")
mkdir -p "$DIR_MISSING_CACHE/target" "$DIR_MISSING_CACHE/tripwire-bin"
TRIPWIRE_OFFLINE_MARKER="$DIR_MISSING_CACHE/osv-scanner-was-invoked"
cat >"$DIR_MISSING_CACHE/tripwire-bin/osv-scanner" <<EOF
#!/usr/bin/env bash
touch "$TRIPWIRE_OFFLINE_MARKER"
echo '{"results":[]}'
EOF
chmod +x "$DIR_MISSING_CACHE/tripwire-bin/osv-scanner"
DIR_MISSING_CACHE_HOME=$(_dossier_safe_mktemp_dir "offline-missing-cache-home")
OUT_MISSING_CACHE=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_MISSING_CACHE_HOME" PATH="$DIR_MISSING_CACHE/tripwire-bin:$PATH" \
  "$SCRIPT" --target "$DIR_MISSING_CACHE/target" --offline 2>&1)
STATUS_MISSING_CACHE=$(printf '%s' "$OUT_MISSING_CACHE" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_MISSING_CACHE" "--offline with a wholly missing cache directory: reported as unavailable"
if [ -e "$TRIPWIRE_OFFLINE_MARKER" ]; then
  _dossier_assert_fail "--offline with a missing cache directory: osv-scanner tripwire was invoked — must refuse before any tool invocation, never emit ok with an unearned age-checked claim"
else
  _dossier_assert_pass "--offline with a missing cache directory: osv-scanner tripwire was never invoked — the age-verifiability check happens before any tool lookup"
fi

# --offline with a cache directory that EXISTS but contains zero stat-able
# files (holdout finding on issue #137): there is nothing whose age this
# check can verify. With the real osv-scanner binary this state happens to
# be caught downstream anyway (the tool itself fails to load a nonexistent
# database), which is why this needs its own tripwire rather than relying
# on the real binary — a stub that succeeds regardless of cache contents
# proves the wrapper refuses BEFORE invocation, not that it merely happens
# to be saved by the real tool's own behavior. Without the upstream refusal
# this stub would return "ok" carrying an offline_caveat that falsely
# claims "age-checked before this scan ran."
DIR_EMPTY_CACHE=$(_dossier_safe_mktemp_dir "offline-empty-cache")
mkdir -p "$DIR_EMPTY_CACHE/target" "$DIR_EMPTY_CACHE/tripwire-bin"
TRIPWIRE_EMPTY_MARKER="$DIR_EMPTY_CACHE/osv-scanner-was-invoked"
cat >"$DIR_EMPTY_CACHE/tripwire-bin/osv-scanner" <<EOF
#!/usr/bin/env bash
touch "$TRIPWIRE_EMPTY_MARKER"
echo '{"results":[]}'
EOF
chmod +x "$DIR_EMPTY_CACHE/tripwire-bin/osv-scanner"
DIR_EMPTY_CACHE_HOME=$(_dossier_safe_mktemp_dir "offline-empty-cache-home")
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  mkdir -p "$DIR_EMPTY_CACHE_HOME/Library/Caches/osv-scanner"
else
  mkdir -p "$DIR_EMPTY_CACHE_HOME/.cache/osv-scanner"
fi
OUT_EMPTY_CACHE=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_EMPTY_CACHE_HOME" PATH="$DIR_EMPTY_CACHE/tripwire-bin:$PATH" \
  "$SCRIPT" --target "$DIR_EMPTY_CACHE/target" --offline 2>&1)
STATUS_EMPTY_CACHE=$(printf '%s' "$OUT_EMPTY_CACHE" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_EMPTY_CACHE" "--offline with a cache directory that exists but contains no files: reported as unavailable"
if [ -e "$TRIPWIRE_EMPTY_MARKER" ]; then
  _dossier_assert_fail "--offline with an empty cache directory: osv-scanner tripwire was invoked — must refuse before any tool invocation, never emit ok with an unearned age-checked claim from an unverifiable cache"
else
  _dossier_assert_pass "--offline with an empty cache directory: osv-scanner tripwire was never invoked — refused before any tool lookup, not merely saved by the real tool's own fallback behavior"
fi

DIR_OFFLINE=$(_dossier_safe_mktemp_dir "offline-no-db")
mkdir -p "$DIR_OFFLINE/target"
printf 'requests==2.32.3\n' >"$DIR_OFFLINE/target/requirements.txt"

# Isolation technique: override $HOME, not XDG_CACHE_HOME. Verified live
# that osv-scanner's own cache-directory resolution (Go's
# os.UserCacheDir()) IGNORES XDG_CACHE_HOME entirely on Darwin — it
# always uses $HOME/Library/Caches regardless — so an XDG_CACHE_HOME-only
# override silently fails to isolate this test from a real system cache
# on macOS (confirmed: it produced a false failure against this exact
# machine's own prior manual osv-scanner use). Overriding $HOME instead
# redirects both this wrapper's own cache-path computation AND
# osv-scanner's real internal resolution consistently, on every platform.
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  OSV_CACHE_REL="Library/Caches/osv-scanner/PyPI"
  OSV_CACHE_REL_NPM="Library/Caches/osv-scanner/npm"
else
  OSV_CACHE_REL=".cache/osv-scanner/PyPI"
  OSV_CACHE_REL_NPM=".cache/osv-scanner/npm"
fi

if command -v osv-scanner >/dev/null 2>&1; then
  DIR_OFFLINE_HOME=$(_dossier_safe_mktemp_dir "offline-no-db-home")
  OUT_OFFLINE=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    HOME="$DIR_OFFLINE_HOME" \
    "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
  STATUS_OFFLINE=$(printf '%s' "$OUT_OFFLINE" | jq -r '.status' 2>/dev/null)
  assert_equal "unavailable" "$STATUS_OFFLINE" "--offline with no cached DB: reported as unavailable, never as a clean scan, even though the tool's own stdout is valid empty-results JSON"
else
  _dossier_assert_pass "osv-scanner unavailable on PATH — the --offline-no-cached-DB assertion was skipped (real-tool-dependent; run.sh's CI job installs it)"
fi

# =============================================================================
# Offline cache staleness, per ecosystem (issue #137 verdict-judge
# NEEDS-HUMAN-REVIEW on AC4, then a holdout-validation P1 on the first fix).
#
# osv-scanner itself has no staleness check on a cache that DOES load
# successfully — verified live against real osv-scanner 2.4.0 (a real
# cached database artificially aged to 2020 loaded and scanned with zero
# warning, indistinguishable from a fresh fetch). This wrapper detects that
# independently, AFTER osv-scanner runs, keyed on the ecosystem(s) its own
# JSON output actually names (results[].packages[].package.ecosystem) —
# verified live for both PyPI and npm targets. A stub `osv-scanner` on PATH
# isolates this wrapper's own age logic from whether the real tool can load
# a given cache file's *content*, which is a separate concern the AC1 real
# end-to-end run below already covers; the stub always reports having
# consulted PyPI, deterministically, so these tests run everywhere,
# independent of whether the real tool is installed.
# =============================================================================
DIR_STALE_HOME=$(_dossier_safe_mktemp_dir "offline-stale-home")
mkdir -p "$DIR_STALE_HOME/$OSV_CACHE_REL" "$DIR_STALE_HOME/fakebin"
printf 'stale placeholder db\n' >"$DIR_STALE_HOME/$OSV_CACHE_REL/all.zip"
touch -t 202001010000 "$DIR_STALE_HOME/$OSV_CACHE_REL/all.zip"
cat >"$DIR_STALE_HOME/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[{"packages":[{"package":{"name":"requests","version":"2.32.3","ecosystem":"PyPI"},"vulnerabilities":[],"groups":[]}]}]}'
exit 0
EOF
chmod +x "$DIR_STALE_HOME/fakebin/osv-scanner"
OUT_STALE=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_STALE_HOME" PATH="$DIR_STALE_HOME/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
STATUS_STALE=$(printf '%s' "$OUT_STALE" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_STALE" "--offline with a stale (2020) cached DB for the consulted ecosystem: reported as unavailable"
DETAIL_STALE=$(printf '%s' "$OUT_STALE" | jq -r '.detail' 2>/dev/null)
assert_contains "stale_advisory_data" "$DETAIL_STALE" "--offline stale-cache detail names the specific reason"
assert_contains "PyPI" "$DETAIL_STALE" "--offline stale-cache detail names the specific ecosystem"

# A cache within the configured max age must NOT be refused by the age check.
DIR_FRESH_HOME=$(_dossier_safe_mktemp_dir "offline-fresh-home")
mkdir -p "$DIR_FRESH_HOME/$OSV_CACHE_REL" "$DIR_FRESH_HOME/fakebin"
printf 'fresh placeholder db\n' >"$DIR_FRESH_HOME/$OSV_CACHE_REL/all.zip"
cat >"$DIR_FRESH_HOME/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[{"packages":[{"package":{"name":"requests","version":"2.32.3","ecosystem":"PyPI"},"vulnerabilities":[],"groups":[]}]}]}'
exit 0
EOF
chmod +x "$DIR_FRESH_HOME/fakebin/osv-scanner"
OUT_FRESH=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_FRESH_HOME" PATH="$DIR_FRESH_HOME/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
STATUS_FRESH=$(printf '%s' "$OUT_FRESH" | jq -r '.status' 2>/dev/null)
assert_equal "ok" "$STATUS_FRESH" "--offline with a fresh (just-created) cache for the consulted ecosystem: reported as ok, not refused as stale"

# DOSSIER_SCAN_OFFLINE_MAX_AGE_DAYS override: a cache that would fail the
# default 7-day threshold must NOT be refused as stale under a wide override.
DIR_OVERRIDE_HOME=$(_dossier_safe_mktemp_dir "offline-max-age-override-home")
mkdir -p "$DIR_OVERRIDE_HOME/$OSV_CACHE_REL" "$DIR_OVERRIDE_HOME/fakebin"
printf 'placeholder db\n' >"$DIR_OVERRIDE_HOME/$OSV_CACHE_REL/all.zip"
touch -t 202001010000 "$DIR_OVERRIDE_HOME/$OSV_CACHE_REL/all.zip"
cat >"$DIR_OVERRIDE_HOME/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[{"packages":[{"package":{"name":"requests","version":"2.32.3","ecosystem":"PyPI"},"vulnerabilities":[],"groups":[]}]}]}'
exit 0
EOF
chmod +x "$DIR_OVERRIDE_HOME/fakebin/osv-scanner"
OUT_OVERRIDE=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true DOSSIER_SCAN_OFFLINE_MAX_AGE_DAYS=99999 \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" HOME="$DIR_OVERRIDE_HOME" PATH="$DIR_OVERRIDE_HOME/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
STATUS_OVERRIDE=$(printf '%s' "$OUT_OVERRIDE" | jq -r '.status' 2>/dev/null)
assert_equal "ok" "$STATUS_OVERRIDE" "DOSSIER_SCAN_OFFLINE_MAX_AGE_DAYS override widens the acceptable-age window as configured"

# Mixed-ecosystem, stale TARGET ecosystem (holdout finding P1, original
# repro): a fresh, UNRELATED sibling ecosystem (npm) must not mask a stale
# database in the ecosystem the scan actually consulted (PyPI).
DIR_MIXED_HOME=$(_dossier_safe_mktemp_dir "offline-mixed-ecosystem-home")
mkdir -p "$DIR_MIXED_HOME/$OSV_CACHE_REL" "$DIR_MIXED_HOME/$OSV_CACHE_REL_NPM" "$DIR_MIXED_HOME/fakebin"
printf 'stale PyPI db\n' >"$DIR_MIXED_HOME/$OSV_CACHE_REL/all.zip"
touch -t 202001010000 "$DIR_MIXED_HOME/$OSV_CACHE_REL/all.zip"
printf 'fresh npm db\n' >"$DIR_MIXED_HOME/$OSV_CACHE_REL_NPM/all.zip"
cat >"$DIR_MIXED_HOME/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[{"packages":[{"package":{"name":"requests","version":"2.32.3","ecosystem":"PyPI"},"vulnerabilities":[],"groups":[]}]}]}'
exit 0
EOF
chmod +x "$DIR_MIXED_HOME/fakebin/osv-scanner"
OUT_MIXED=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_MIXED_HOME" PATH="$DIR_MIXED_HOME/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
STATUS_MIXED=$(printf '%s' "$OUT_MIXED" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_MIXED" "--offline with a stale PyPI db (the consulted ecosystem) alongside a fresh, unrelated npm db: still refused as stale — a fresh sibling ecosystem must not mask the one actually needed"
DETAIL_MIXED=$(printf '%s' "$OUT_MIXED" | jq -r '.detail' 2>/dev/null)
assert_contains "stale_advisory_data" "$DETAIL_MIXED" "mixed-ecosystem cache: detail names the specific reason"

# Mixed-ecosystem, stale SIBLING ecosystem (the inverse case, catching a
# regression a whole-tree check of either direction gets wrong): a stale,
# UNRELATED npm db must NOT block a scan whose actually-consulted ecosystem
# (PyPI) is fresh. A whole-tree "oldest file" check would incorrectly
# refuse this scan forever, on a database it never needed.
DIR_MIXED2_HOME=$(_dossier_safe_mktemp_dir "offline-mixed-ecosystem-2-home")
mkdir -p "$DIR_MIXED2_HOME/$OSV_CACHE_REL" "$DIR_MIXED2_HOME/$OSV_CACHE_REL_NPM" "$DIR_MIXED2_HOME/fakebin"
printf 'fresh PyPI db\n' >"$DIR_MIXED2_HOME/$OSV_CACHE_REL/all.zip"
printf 'stale npm db\n' >"$DIR_MIXED2_HOME/$OSV_CACHE_REL_NPM/all.zip"
touch -t 202001010000 "$DIR_MIXED2_HOME/$OSV_CACHE_REL_NPM/all.zip"
cat >"$DIR_MIXED2_HOME/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[{"packages":[{"package":{"name":"requests","version":"2.32.3","ecosystem":"PyPI"},"vulnerabilities":[],"groups":[]}]}]}'
exit 0
EOF
chmod +x "$DIR_MIXED2_HOME/fakebin/osv-scanner"
OUT_MIXED2=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_MIXED2_HOME" PATH="$DIR_MIXED2_HOME/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
STATUS_MIXED2=$(printf '%s' "$OUT_MIXED2" | jq -r '.status' 2>/dev/null)
assert_equal "ok" "$STATUS_MIXED2" "--offline with a fresh PyPI db (the consulted ecosystem) alongside a stale, unrelated npm db: reported ok — a stale sibling ecosystem must not permanently block a scan that never needed it"

# Consulted ecosystem has NO cache subdirectory at all, despite osv-scanner
# successfully resolving packages for it from the lockfile (which needs no
# network/cache access) — this wrapper cannot tell "a cached database
# silently backed this" from "no advisory data was checked at all" from the
# JSON alone, so it refuses rather than guess.
DIR_NOCACHE_HOME=$(_dossier_safe_mktemp_dir "offline-consulted-ecosystem-no-cache-home")
mkdir -p "$DIR_NOCACHE_HOME/fakebin"
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  mkdir -p "$DIR_NOCACHE_HOME/Library/Caches/osv-scanner"
else
  mkdir -p "$DIR_NOCACHE_HOME/.cache/osv-scanner"
fi
cat >"$DIR_NOCACHE_HOME/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[{"packages":[{"package":{"name":"requests","version":"2.32.3","ecosystem":"PyPI"},"vulnerabilities":[],"groups":[]}]}]}'
exit 0
EOF
chmod +x "$DIR_NOCACHE_HOME/fakebin/osv-scanner"
OUT_NOCACHE=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_NOCACHE_HOME" PATH="$DIR_NOCACHE_HOME/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_OFFLINE/target" --offline 2>&1)
STATUS_NOCACHE=$(printf '%s' "$OUT_NOCACHE" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_NOCACHE" "--offline where the consulted ecosystem (PyPI) has no cache subdirectory at all: refused, not reported ok"

# =============================================================================
# --offline-DB-unavailable defense-in-depth: a stub osv-scanner reproduces
# the same exit-127-with-empty-results shape a real missing-DB run produces,
# but with stderr wording that does NOT match the known "could not load
# db"/"no offline version" text. This is independent of whether the real
# tool is installed — it proves the structural (exit-code + empty-results)
# check catches a reworded message the text match alone would miss. A fresh
# placeholder cache under a dedicated $HOME override ensures the ERR-1
# missing-directory refusal (checked before invocation) doesn't itself fire
# first — this test isolates the DOWNSTREAM defense-in-depth specifically.
# =============================================================================
DIR_REWORDED=$(_dossier_safe_mktemp_dir "offline-reworded-stderr")
mkdir -p "$DIR_REWORDED/fakebin" "$DIR_REWORDED/target"
cat >"$DIR_REWORDED/fakebin/osv-scanner" <<'EOF'
#!/usr/bin/env bash
echo '{"results":[]}'
echo "hypothetical future wording: advisory database not present" >&2
exit 127
EOF
chmod +x "$DIR_REWORDED/fakebin/osv-scanner"
if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  REWORDED_CACHE_REL="Library/Caches/osv-scanner/PyPI"
else
  REWORDED_CACHE_REL=".cache/osv-scanner/PyPI"
fi
DIR_REWORDED_HOME=$(_dossier_safe_mktemp_dir "offline-reworded-stderr-home")
mkdir -p "$DIR_REWORDED_HOME/$REWORDED_CACHE_REL"
printf 'fresh placeholder db\n' >"$DIR_REWORDED_HOME/$REWORDED_CACHE_REL/all.zip"
OUT_REWORDED=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  HOME="$DIR_REWORDED_HOME" PATH="$DIR_REWORDED/fakebin:$PATH" \
  "$SCRIPT" --target "$DIR_REWORDED/target" --offline 2>&1)
STATUS_REWORDED=$(printf '%s' "$OUT_REWORDED" | jq -r '.status' 2>/dev/null)
assert_equal "unavailable" "$STATUS_REWORDED" "--offline with exit 127 + empty results but non-matching stderr wording: still reported as unavailable via the structural defense-in-depth check, never as a clean scan"

# =============================================================================
# AC1 real end-to-end run: a fixture with actually-known-vulnerable
# dependencies (django 2.0.1, requests 2.6.0, pyyaml 5.3 — all carry
# multiple real, high-severity CVEs), scanned for real, fed into
# dossier-vuln-evidence.sh, and cited as evidence. This is the load-bearing
# proof for AC1 and, together with AC6, is not run against a substitute or
# stand-in — it is the real osv-scanner binary querying the real OSV
# database. Per the project's precedent (workflow-template.test.sh:17,44):
# degrade to an honest, NAMED skip locally when the tool is absent; CI
# installs it so the skip path is never exercised there.
# =============================================================================
if command -v osv-scanner >/dev/null 2>&1; then
  DIR_E2E=$(_dossier_safe_mktemp_dir "ac1-e2e")
  mkdir -p "$DIR_E2E/target" "$DIR_E2E/out"
  # django 2.0.1 and requests 2.6.0 both carry multiple real, published
  # Critical/High CVEs (confirmed via a live osv-scanner run against this
  # exact fixture shape during planning: 39 findings including several at
  # CVSS 9.8).
  printf 'django==2.0.1\nrequests==2.6.0\npyyaml==5.3\n' >"$DIR_E2E/target/requirements.txt"
  OUT_E2E=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_E2E/target" --out "$DIR_E2E/out" 2>&1)
  RC_E2E=$?
  assert_equal "0" "$RC_E2E" "AC1 e2e: a real scan against known-vulnerable deps exits 0"
  STATUS_E2E=$(printf '%s' "$OUT_E2E" | jq -r '.status' 2>/dev/null)
  assert_equal "ok" "$STATUS_E2E" "AC1 e2e: status is ok (osv-scanner's own exit 1 for vulnerabilities-found is a SUCCESS case, not a failure)"
  ARTIFACT_E2E=$(printf '%s' "$OUT_E2E" | jq -r '.artifact_path' 2>/dev/null)
  assert_file_exists "$ARTIFACT_E2E" "AC1 e2e: the raw osv-scanner artifact file actually exists on disk"

  EVIDENCE_E2E=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$VULN_SCRIPT" --scan "$ARTIFACT_E2E" 2>&1)
  EVIDENCE_RC=$?
  assert_equal "0" "$EVIDENCE_RC" "AC1 e2e: dossier-vuln-evidence.sh successfully ingests the wrapper's raw artifact"
  FINDINGS_COUNT_E2E=$(printf '%s' "$EVIDENCE_E2E" | jq '.findings | length' 2>/dev/null)
  case "$FINDINGS_COUNT_E2E" in
    ''|0) _dossier_assert_fail "AC1 e2e: expected real Critical/High findings for django 2.0.1 / requests 2.6.0 / pyyaml 5.3, got $FINDINGS_COUNT_E2E — the severity-extraction fix or the live OSV database may not be behaving as expected" ;;
    *) _dossier_assert_pass "AC1 e2e: $FINDINGS_COUNT_E2E real Critical/High finding(s) correctly extracted from a live osv-scanner run" ;;
  esac
  SRCREF_E2E=$(printf '%s' "$EVIDENCE_E2E" | jq -r '.findings[0].source_ref // "MISSING"' 2>/dev/null)
  assert_contains "osv-scan-raw.json" "$SRCREF_E2E" "AC1 e2e: the finding's source_ref names the actual scan artifact, not a placeholder"
else
  _dossier_assert_pass "osv-scanner unavailable on PATH — the real end-to-end AC1 assertion was skipped (run.sh's CI job installs the pinned version so this skip is never exercised there)"
fi

# =============================================================================
# A genuine successful scan (real dependencies, tool actually ran) is
# distinct from disabled/unavailable/error — "ok" covers both a scan that
# found nothing and one that found something; both are real results, not
# not-run outcomes. (A truly dependency-free manifest is NOT usable as this
# fixture: osv-scanner itself reports "No package sources found" — exit 128,
# empty stdout — identically for "zero packages in a real manifest" and "no
# manifest at all," confirmed empirically. dossier-scan-security.sh
# correctly reports that ambiguous case as `error`, not `ok` — conservative
# per the project's "unevaluated must never read as assent" rule, so it is
# not exercised as an `ok` case here.)
# =============================================================================
if command -v osv-scanner >/dev/null 2>&1; then
  DIR_CLEAN=$(_dossier_safe_mktemp_dir "genuine-scan")
  mkdir -p "$DIR_CLEAN/target"
  printf 'requests==2.32.3\n' >"$DIR_CLEAN/target/requirements.txt"
  OUT_CLEAN=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$SCRIPT" --target "$DIR_CLEAN/target" 2>&1)
  STATUS_CLEAN=$(printf '%s' "$OUT_CLEAN" | jq -r '.status' 2>/dev/null)
  assert_equal "ok" "$STATUS_CLEAN" "genuine scan: a real dependency scan is ok regardless of whether it finds vulnerabilities, distinct from disabled/unavailable/error"
else
  _dossier_assert_pass "osv-scanner unavailable on PATH — the genuine-scan assertion was skipped"
fi

# =============================================================================
# AC3 (script-local half): the security wrapper never consults
# runCodeQualityScan — proven by enabling only that flag and confirming the
# security wrapper still reports disabled.
# =============================================================================
OUT_CROSSFLAG=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$SCRIPT" --target "$DIR_DISABLED/target" 2>&1)
STATUS_CROSSFLAG=$(printf '%s' "$OUT_CROSSFLAG" | jq -r '.status' 2>/dev/null)
assert_equal "disabled" "$STATUS_CROSSFLAG" "AC3: runCodeQualityScan=true alone never enables the security wrapper"

# =============================================================================
# AC3 (joint, issue #137 Task 26): with BOTH scripts invoked under one shared
# config where only runSecurityScan is true, the security wrapper proceeds
# while the quality wrapper independently reports disabled — and vice versa.
# The per-script AC3 assertions above prove each script ignores the other's
# flag in isolation; this proves it holds when both run back to back against
# the identical environment, per AC3's own stated verification (same two
# test files).
# =============================================================================
QUALITY_SCRIPT="$(pwd)/plugins/dossier/bin/dossier-scan-quality.sh"
if [ -x "$QUALITY_SCRIPT" ]; then
  DIR_JOINT=$(_dossier_safe_mktemp_dir "ac3-joint")
  mkdir -p "$DIR_JOINT/sec-target" "$DIR_JOINT/qual-target"
  printf 'def f():\n    pass\n' >"$DIR_JOINT/qual-target/mod.py"

  SEC_OUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=false \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_JOINT/sec-target" 2>&1)
  QUAL_OUT=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=false \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$QUALITY_SCRIPT" --target "$DIR_JOINT/qual-target" 2>&1)
  SEC_STATUS=$(printf '%s' "$SEC_OUT" | jq -r '.status' 2>/dev/null)
  QUAL_STATUS=$(printf '%s' "$QUAL_OUT" | jq -r '.status' 2>/dev/null)
  assert_not_contains "disabled" "$SEC_STATUS" "AC3 joint: security proceeds (not disabled) when only runSecurityScan is true"
  assert_equal "disabled" "$QUAL_STATUS" "AC3 joint: quality independently stays disabled under the identical shared environment"

  SEC_OUT2=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=false DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" --target "$DIR_JOINT/sec-target" 2>&1)
  QUAL_OUT2=$(DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=false DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_CODE_QUALITY_SCAN=true \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$QUALITY_SCRIPT" --target "$DIR_JOINT/qual-target" 2>&1)
  SEC_STATUS2=$(printf '%s' "$SEC_OUT2" | jq -r '.status' 2>/dev/null)
  QUAL_STATUS2=$(printf '%s' "$QUAL_OUT2" | jq -r '.status' 2>/dev/null)
  assert_equal "disabled" "$SEC_STATUS2" "AC3 joint (flipped): security independently stays disabled under the identical shared environment"
  assert_not_contains "disabled" "$QUAL_STATUS2" "AC3 joint (flipped): quality proceeds (not disabled) when only runCodeQualityScan is true"
else
  _dossier_assert_fail "$QUALITY_SCRIPT missing or not executable — AC3 joint assertions could not run"
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
