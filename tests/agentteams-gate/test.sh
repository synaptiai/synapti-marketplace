#!/usr/bin/env bash
# Path A gate source-resolution test (issue #101).
#
# The gate at plugins/flow/commands/review.md must:
#   1. Read $HOME/.claude/settings.flow.json first (user-tier override)
#   2. Fall through to ${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json
#   3. Never read project-tier .claude/settings.flow*.json (security pin)
#   4. Emit a three-state diagnostic when no source resolves a value
#
# Extraction: gate body is delimited by # AGENTTEAMS_GATE_BEGIN / # AGENTTEAMS_GATE_END
# in plugins/flow/commands/review.md so the test verifies the actual code.
#
# Exits 0 on all PASS, 1 on first FAIL (with PASS/FAIL counts), 2 on infrastructure error.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REVIEW_MD="$REPO_ROOT/plugins/flow/commands/review.md"
PASS=0
FAIL=0

if [ ! -f "$REVIEW_MD" ]; then
  echo "FATAL: $REVIEW_MD not found" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq not installed; cannot run gate scenarios (the gate itself handles this case but the test fixtures need jq to construct settings files)" >&2
  exit 2
fi

# Extract gate bash between markers. The output is sourceable bash.
extract_gate() {
  awk '
    /^# AGENTTEAMS_GATE_BEGIN$/ { capture=1; next }
    /^# AGENTTEAMS_GATE_END$/   { capture=0 }
    capture { print }
  ' "$REVIEW_MD"
}

GATE_BODY="$(extract_gate)"
if [ -z "$GATE_BODY" ]; then
  echo "FATAL: could not extract gate body from $REVIEW_MD." >&2
  echo "       Expected markers '# AGENTTEAMS_GATE_BEGIN' and '# AGENTTEAMS_GATE_END'." >&2
  echo "       Either the markers are missing or this test is being run against a pre-fix tree." >&2
  exit 2
fi

# Run the gate in an isolated subshell with controlled HOME, CWD, and env.
# Captures gate stdout, stderr, and USE_PATH_A separately so assertions are
# unambiguous. Returns USE_PATH_A as the function's stdout (single line).
#
# Args: $1 = sandbox dir (with optional .claude/, plugins/flow/ subdirs prepared by caller)
#       $2 = HOME override (path)
#       $3 = "set" or "unset" for CLAUDE_PLUGIN_ROOT
#       $4 = value for CLAUDE_PLUGIN_ROOT (when "set")
#       $5 = "set" or "unset" for CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
#       $6 = stderr capture file
#       $7 = stdout capture file
run_gate() {
  local sandbox="$1" home="$2" plugin_root_state="$3" plugin_root="$4" env_var_state="$5" stderr_file="$6" stdout_file="$7"

  (
    cd "$sandbox"
    export HOME="$home"
    if [ "$plugin_root_state" = "set" ]; then
      export CLAUDE_PLUGIN_ROOT="$plugin_root"
    else
      unset CLAUDE_PLUGIN_ROOT
    fi
    if [ "$env_var_state" = "set" ]; then
      export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
    else
      unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
    fi
    USE_PATH_A=0
    eval "$GATE_BODY" >"$stdout_file" 2>"$stderr_file"
    printf '%s' "$USE_PATH_A"
  )
}

write_settings() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" >"$path"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3" stderr_file="${4:-}"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    if [ -n "$stderr_file" ] && [ -f "$stderr_file" ]; then
      echo "  stderr:"
      sed 's/^/    /' "$stderr_file"
    fi
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_contains() {
  local label="$1" needle="$2" stderr_file="$3"
  if grep -qF "$needle" "$stderr_file"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  needle:  $needle"
    echo "  stderr:"
    sed 's/^/    /' "$stderr_file"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_not_contains() {
  local label="$1" needle="$2" stderr_file="$3"
  if grep -qF "$needle" "$stderr_file"; then
    echo "FAIL: $label"
    echo "  unwanted needle was present: $needle"
    echo "  stderr:"
    sed 's/^/    /' "$stderr_file"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

# ============================================================================
# Scenario 1: marketplace-installed-no-cwd-plugin-dir
# $HOME has agentTeams:true, no plugins/flow/ in CWD, env var set.
# Expected: USE_PATH_A=1, no "settings not found" WARN.
# Maps to AC1 (fresh marketplace install).
# ============================================================================
S1_DIR="$(mktemp -d -t agentteams-s1.XXXXXX)"
trap 'rm -rf "$S1_DIR"' EXIT
S1_HOME="$S1_DIR/home"
S1_CWD="$S1_DIR/cwd"
mkdir -p "$S1_HOME/.claude" "$S1_CWD"
write_settings "$S1_HOME/.claude/settings.flow.json" '{"agentTeams": true}'
S1_STDERR="$S1_DIR/stderr"

S1_STDOUT="$S1_DIR/stdout"
S1_RESULT=$(run_gate "$S1_CWD" "$S1_HOME" "unset" "" "set" "$S1_STDERR" "$S1_STDOUT")
assert_eq "S1: marketplace install with HOME override → USE_PATH_A=1" "1" "$S1_RESULT" "$S1_STDERR"
assert_stderr_not_contains "S1: no 'plugin not installed' WARN" "may not be installed" "$S1_STDERR"

# ============================================================================
# Scenario 2: upgrade-survival
# Run gate twice; between runs replace plugin-tier settings.json (simulate
# upgrade). $HOME has agentTeams:true throughout.
# Expected: both runs USE_PATH_A=1.
# Maps to AC2.
# ============================================================================
S2_DIR="$(mktemp -d -t agentteams-s2.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR"' EXIT
S2_HOME="$S2_DIR/home"
S2_CWD="$S2_DIR/cwd"
S2_CACHE_V1="$S2_DIR/cache-v1"
S2_CACHE_V2="$S2_DIR/cache-v2"
mkdir -p "$S2_HOME/.claude" "$S2_CWD" "$S2_CACHE_V1" "$S2_CACHE_V2"
write_settings "$S2_HOME/.claude/settings.flow.json" '{"agentTeams": true}'
write_settings "$S2_CACHE_V1/settings.json" '{"agentTeams": false}'
write_settings "$S2_CACHE_V2/settings.json" '{"agentTeams": false}'
S2_STDERR_A="$S2_DIR/stderr-a"
S2_STDERR_B="$S2_DIR/stderr-b"
S2_STDOUT_A="$S2_DIR/stdout-a"
S2_STDOUT_B="$S2_DIR/stdout-b"

S2_RESULT_A=$(run_gate "$S2_CWD" "$S2_HOME" "set" "$S2_CACHE_V1" "set" "$S2_STDERR_A" "$S2_STDOUT_A")
S2_RESULT_B=$(run_gate "$S2_CWD" "$S2_HOME" "set" "$S2_CACHE_V2" "set" "$S2_STDERR_B" "$S2_STDOUT_B")
assert_eq "S2a: pre-upgrade with HOME override → USE_PATH_A=1" "1" "$S2_RESULT_A" "$S2_STDERR_A"
assert_eq "S2b: post-upgrade with HOME override → USE_PATH_A=1" "1" "$S2_RESULT_B" "$S2_STDERR_B"

# ============================================================================
# Scenario 3: project-tier-bypass-attempt
# Project-tier .claude/settings.flow.json has agentTeams:true. $HOME absent.
# Plugin tier has agentTeams:false. Env var set.
# Expected: USE_PATH_A=0; project-tier path NEVER appears in any diagnostic.
# Maps to AC3 (security pin preserved).
# ============================================================================
S3_DIR="$(mktemp -d -t agentteams-s3.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR"' EXIT
S3_HOME="$S3_DIR/empty-home"
S3_CWD="$S3_DIR/cwd"
S3_CACHE="$S3_DIR/cache"
mkdir -p "$S3_HOME" "$S3_CWD/.claude" "$S3_CACHE"
write_settings "$S3_CWD/.claude/settings.flow.json" '{"agentTeams": true}'
write_settings "$S3_CWD/.claude/settings.flow.local.json" '{"agentTeams": true}'
write_settings "$S3_CACHE/settings.json" '{"agentTeams": false}'
S3_STDERR="$S3_DIR/stderr"
S3_STDOUT="$S3_DIR/stdout"

S3_RESULT=$(run_gate "$S3_CWD" "$S3_HOME" "set" "$S3_CACHE" "set" "$S3_STDERR" "$S3_STDOUT")
assert_eq "S3: project-tier agentTeams:true is ignored → USE_PATH_A=0" "0" "$S3_RESULT" "$S3_STDERR"
assert_stderr_not_contains "S3: project-tier path .claude/settings.flow.json NOT in stderr" ".claude/settings.flow.json" "$S3_STDERR"
assert_stderr_not_contains "S3: project-tier .local path NOT in stderr" ".claude/settings.flow.local.json" "$S3_STDERR"
# Same check on stdout — project-tier paths must never appear in any output
if grep -qF ".claude/settings.flow.json" "$S3_STDOUT"; then
  echo "FAIL: S3: project-tier path .claude/settings.flow.json appeared in stdout"
  echo "  stdout:"
  sed 's/^/    /' "$S3_STDOUT"
  FAIL=$((FAIL + 1))
else
  echo "PASS: S3: project-tier path .claude/settings.flow.json NOT in stdout"
  PASS=$((PASS + 1))
fi

# ============================================================================
# Scenario 4a: diagnostic state (a) — plugin not installed
# No $HOME override, no plugins/flow/ in CWD, CLAUDE_PLUGIN_ROOT unset.
# Expected: WARN names "may not be installed" (or equivalent).
# Maps to AC4 (diagnostic distinguishability).
# ============================================================================
S4A_DIR="$(mktemp -d -t agentteams-s4a.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4A_DIR"' EXIT
S4A_HOME="$S4A_DIR/empty-home"
S4A_CWD="$S4A_DIR/empty-cwd"
mkdir -p "$S4A_HOME" "$S4A_CWD"
S4A_STDERR="$S4A_DIR/stderr"
S4A_STDOUT="$S4A_DIR/stdout"

S4A_RESULT=$(run_gate "$S4A_CWD" "$S4A_HOME" "unset" "" "set" "$S4A_STDERR" "$S4A_STDOUT")
assert_eq "S4a: no sources, no env var → USE_PATH_A=0" "0" "$S4A_RESULT" "$S4A_STDERR"
assert_stderr_contains "S4a: WARN names 'may not be installed' state" "may not be installed" "$S4A_STDERR"

# ============================================================================
# Scenario 4b: diagnostic state (b) — CLAUDE_PLUGIN_ROOT set to nonexistent path
# Expected: WARN names that path explicitly.
# Maps to AC4.
# ============================================================================
S4B_DIR="$(mktemp -d -t agentteams-s4b.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4A_DIR" "$S4B_DIR"' EXIT
S4B_HOME="$S4B_DIR/empty-home"
S4B_CWD="$S4B_DIR/cwd"
S4B_BAD_PLUGIN_ROOT="$S4B_DIR/this-path-does-not-exist-12345"
mkdir -p "$S4B_HOME" "$S4B_CWD"
S4B_STDERR="$S4B_DIR/stderr"
S4B_STDOUT="$S4B_DIR/stdout"

S4B_RESULT=$(run_gate "$S4B_CWD" "$S4B_HOME" "set" "$S4B_BAD_PLUGIN_ROOT" "set" "$S4B_STDERR" "$S4B_STDOUT")
assert_eq "S4b: env var set but path missing → USE_PATH_A=0" "0" "$S4B_RESULT" "$S4B_STDERR"
assert_stderr_contains "S4b: WARN names the bad CLAUDE_PLUGIN_ROOT path" "$S4B_BAD_PLUGIN_ROOT" "$S4B_STDERR"

# ============================================================================
# Scenario 4c: diagnostic state (c) — both files exist but neither sets agentTeams
# Expected: WARN points at $HOME for opt-in.
# Maps to AC4.
# ============================================================================
S4C_DIR="$(mktemp -d -t agentteams-s4c.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4A_DIR" "$S4B_DIR" "$S4C_DIR"' EXIT
S4C_HOME="$S4C_DIR/home"
S4C_CWD="$S4C_DIR/cwd"
S4C_CACHE="$S4C_DIR/cache"
mkdir -p "$S4C_HOME/.claude" "$S4C_CWD" "$S4C_CACHE"
# Both files exist but neither has the agentTeams key
write_settings "$S4C_HOME/.claude/settings.flow.json" '{"otherKey": "value"}'
write_settings "$S4C_CACHE/settings.json" '{"otherKey": "value"}'
S4C_STDERR="$S4C_DIR/stderr"
S4C_STDOUT="$S4C_DIR/stdout"

S4C_RESULT=$(run_gate "$S4C_CWD" "$S4C_HOME" "set" "$S4C_CACHE" "set" "$S4C_STDERR" "$S4C_STDOUT")
assert_eq "S4c: files exist but no agentTeams key → USE_PATH_A=0" "0" "$S4C_RESULT" "$S4C_STDERR"
# State (c) is informational, not a warning — the gate reports it on stdout
# (same channel as the existing "Path A skipped: agentTeams=false" message).
# What matters for AC4 is that the diagnostic distinguishes this state from
# (a)/(b) AND points the user at the supported opt-in location.
if grep -qF "$S4C_HOME/.claude/settings.flow.json" "$S4C_STDOUT"; then
  echo "PASS: S4c: stdout points at HOME path for opt-in"
  PASS=$((PASS + 1))
else
  echo "FAIL: S4c: stdout does not name HOME path for opt-in"
  echo "  expected substring: $S4C_HOME/.claude/settings.flow.json"
  echo "  stdout:"
  sed 's/^/    /' "$S4C_STDOUT"
  echo "  stderr:"
  sed 's/^/    /' "$S4C_STDERR"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
# Scenario 5: precedence — HOME overrides plugin (opt-OUT semantics)
# $HOME agentTeams:false, plugin tier agentTeams:true, env var set.
# Expected: USE_PATH_A=0 (user-tier wins, even when opting OUT).
# Maps to non-goal: HOME is authoritative.
# ============================================================================
S5_DIR="$(mktemp -d -t agentteams-s5.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4A_DIR" "$S4B_DIR" "$S4C_DIR" "$S5_DIR"' EXIT
S5_HOME="$S5_DIR/home"
S5_CWD="$S5_DIR/cwd"
S5_CACHE="$S5_DIR/cache"
mkdir -p "$S5_HOME/.claude" "$S5_CWD" "$S5_CACHE"
write_settings "$S5_HOME/.claude/settings.flow.json" '{"agentTeams": false}'
write_settings "$S5_CACHE/settings.json" '{"agentTeams": true}'
S5_STDERR="$S5_DIR/stderr"
S5_STDOUT="$S5_DIR/stdout"

S5_RESULT=$(run_gate "$S5_CWD" "$S5_HOME" "set" "$S5_CACHE" "set" "$S5_STDERR" "$S5_STDOUT")
assert_eq "S5: HOME=false beats plugin=true → USE_PATH_A=0" "0" "$S5_RESULT" "$S5_STDERR"

# ============================================================================
# Scenario 6: malformed-home-falls-through
# $HOME has invalid JSON, plugin tier has agentTeams:true, env var set.
# Expected: per-source parse WARN AND USE_PATH_A=1 (falls through to plugin).
# Maps to failure mode: parse error must not silently disable Path A when
# plugin tier has a definitive value.
# ============================================================================
S6_DIR="$(mktemp -d -t agentteams-s6.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4A_DIR" "$S4B_DIR" "$S4C_DIR" "$S5_DIR" "$S6_DIR"' EXIT
S6_HOME="$S6_DIR/home"
S6_CWD="$S6_DIR/cwd"
S6_CACHE="$S6_DIR/cache"
mkdir -p "$S6_HOME/.claude" "$S6_CWD" "$S6_CACHE"
write_settings "$S6_HOME/.claude/settings.flow.json" '{not valid json'
write_settings "$S6_CACHE/settings.json" '{"agentTeams": true}'
S6_STDERR="$S6_DIR/stderr"
S6_STDOUT="$S6_DIR/stdout"

S6_RESULT=$(run_gate "$S6_CWD" "$S6_HOME" "set" "$S6_CACHE" "set" "$S6_STDERR" "$S6_STDOUT")
assert_eq "S6: malformed HOME falls through to plugin → USE_PATH_A=1" "1" "$S6_RESULT" "$S6_STDERR"
assert_stderr_contains "S6: WARN names HOME settings file as parse failure" "settings.flow.json" "$S6_STDERR"

# ============================================================================
# Scenario 7: env-var-missing
# HOME agentTeams:true, env var unset.
# Expected: USE_PATH_A=0 with WARN about env var (two-key gate: both required).
# Maps to non-goal: env var requirement preserved.
# ============================================================================
S7_DIR="$(mktemp -d -t agentteams-s7.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4A_DIR" "$S4B_DIR" "$S4C_DIR" "$S5_DIR" "$S6_DIR" "$S7_DIR"' EXIT
S7_HOME="$S7_DIR/home"
S7_CWD="$S7_DIR/cwd"
mkdir -p "$S7_HOME/.claude" "$S7_CWD"
write_settings "$S7_HOME/.claude/settings.flow.json" '{"agentTeams": true}'
S7_STDERR="$S7_DIR/stderr"
S7_STDOUT="$S7_DIR/stdout"

S7_RESULT=$(run_gate "$S7_CWD" "$S7_HOME" "unset" "" "unset" "$S7_STDERR" "$S7_STDOUT")
assert_eq "S7: agentTeams:true but env var unset → USE_PATH_A=0" "0" "$S7_RESULT" "$S7_STDERR"
assert_stderr_contains "S7: WARN about env var" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" "$S7_STDERR"

# ============================================================================
echo ""
echo "========================================"
echo "Total: $PASS PASS / $FAIL FAIL"
echo "========================================"
[ $FAIL -eq 0 ] && exit 0 || exit 1
