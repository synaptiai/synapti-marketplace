#!/usr/bin/env bash
# merge.markerTrust.allowedAssociations source-resolution test (issue #101).
#
# The gate at plugins/flow/commands/merge.md must apply the same trimmed-cascade
# pattern used by the agentTeams gate in review.md:
#   1. $HOME/.claude/settings.flow.json (user-tier override)
#   2. ${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json (plugin default)
#   project-tier (.claude/settings.flow*.json) is excluded.
#
# Extraction: gate body is delimited by # MARKERTRUST_GATE_BEGIN / # MARKERTRUST_GATE_END
# in plugins/flow/commands/merge.md.
#
# Exits 0 on all PASS, 1 on first FAIL, 2 on infrastructure error.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MERGE_MD="$REPO_ROOT/plugins/flow/commands/merge.md"
PASS=0
FAIL=0

if [ ! -f "$MERGE_MD" ]; then
  echo "FATAL: $MERGE_MD not found" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq not installed" >&2
  exit 2
fi

extract_gate() {
  awk '
    /^# MARKERTRUST_GATE_BEGIN$/ { capture=1; next }
    /^# MARKERTRUST_GATE_END$/   { capture=0 }
    capture { print }
  ' "$MERGE_MD"
}

GATE_BODY="$(extract_gate)"
if [ -z "$GATE_BODY" ]; then
  echo "FATAL: could not extract gate body from $MERGE_MD." >&2
  echo "       Expected markers '# MARKERTRUST_GATE_BEGIN' and '# MARKERTRUST_GATE_END'." >&2
  exit 2
fi

# Run the gate in an isolated subshell. The gate sets TRUST_LIST and may emit
# FINDING_LEDGER_BLOCK messages. Captures TRUST_LIST + stdout + stderr.
# Args: $1 sandbox dir, $2 HOME path, $3 plugin_root_state {set,unset},
#       $4 plugin_root path (when set), $5 stdout file, $6 stderr file
run_gate() {
  local sandbox="$1" home="$2" plugin_root_state="$3" plugin_root="$4" stdout_file="$5" stderr_file="$6"

  (
    cd "$sandbox"
    export HOME="$home"
    if [ "$plugin_root_state" = "set" ]; then
      export CLAUDE_PLUGIN_ROOT="$plugin_root"
    else
      unset CLAUDE_PLUGIN_ROOT
    fi
    TRUST_LIST=""
    eval "$GATE_BODY" >"$stdout_file" 2>"$stderr_file"
    printf '%s' "$TRUST_LIST"
  )
}

write_settings() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" >"$path"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -qF "$needle" "$file"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  needle: $needle"
    echo "  file content:"
    sed 's/^/    /' "$file"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -qF "$needle" "$file"; then
    echo "FAIL: $label"
    echo "  unwanted needle was present: $needle"
    echo "  file content:"
    sed 's/^/    /' "$file"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

DEFAULT_TRUST='["OWNER","MEMBER","COLLABORATOR"]'
PERMISSIVE_TRUST='["OWNER","MEMBER","COLLABORATOR","CONTRIBUTOR","NONE"]'

# ============================================================================
# S1: marketplace install with HOME override
# $HOME has merge.markerTrust.allowedAssociations:[...permissive...].
# No plugins/flow/ in CWD, no env var.
# Expected: TRUST_LIST = permissive (HOME wins).
# ============================================================================
S1_DIR="$(mktemp -d -t markertrust-s1.XXXXXX)"
trap 'rm -rf "$S1_DIR"' EXIT
S1_HOME="$S1_DIR/home"
S1_CWD="$S1_DIR/cwd"
mkdir -p "$S1_HOME/.claude" "$S1_CWD"
write_settings "$S1_HOME/.claude/settings.flow.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$PERMISSIVE_TRUST}}}"
S1_STDOUT="$S1_DIR/stdout"
S1_STDERR="$S1_DIR/stderr"

S1_RESULT=$(run_gate "$S1_CWD" "$S1_HOME" "unset" "" "$S1_STDOUT" "$S1_STDERR")
assert_eq "S1: marketplace install with HOME override → TRUST_LIST=permissive" "$PERMISSIVE_TRUST" "$S1_RESULT"
assert_not_contains "S1: no FINDING_LEDGER_BLOCK on stdout" "FINDING_LEDGER_BLOCK" "$S1_STDOUT"

# ============================================================================
# S2: upgrade-survival
# Run gate twice with plugin-tier swap. HOME persists.
# ============================================================================
S2_DIR="$(mktemp -d -t markertrust-s2.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR"' EXIT
S2_HOME="$S2_DIR/home"
S2_CWD="$S2_DIR/cwd"
S2_CACHE_V1="$S2_DIR/cache-v1"
S2_CACHE_V2="$S2_DIR/cache-v2"
mkdir -p "$S2_HOME/.claude" "$S2_CWD" "$S2_CACHE_V1" "$S2_CACHE_V2"
write_settings "$S2_HOME/.claude/settings.flow.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$PERMISSIVE_TRUST}}}"
write_settings "$S2_CACHE_V1/settings.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$DEFAULT_TRUST}}}"
write_settings "$S2_CACHE_V2/settings.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$DEFAULT_TRUST}}}"
S2_STDOUT_A="$S2_DIR/stdout-a"
S2_STDOUT_B="$S2_DIR/stdout-b"
S2_STDERR_A="$S2_DIR/stderr-a"
S2_STDERR_B="$S2_DIR/stderr-b"

S2_RESULT_A=$(run_gate "$S2_CWD" "$S2_HOME" "set" "$S2_CACHE_V1" "$S2_STDOUT_A" "$S2_STDERR_A")
S2_RESULT_B=$(run_gate "$S2_CWD" "$S2_HOME" "set" "$S2_CACHE_V2" "$S2_STDOUT_B" "$S2_STDERR_B")
assert_eq "S2a: pre-upgrade with HOME override → TRUST_LIST=permissive" "$PERMISSIVE_TRUST" "$S2_RESULT_A"
assert_eq "S2b: post-upgrade with HOME override → TRUST_LIST=permissive" "$PERMISSIVE_TRUST" "$S2_RESULT_B"

# ============================================================================
# S3: project-tier-bypass-attempt
# Project-tier has permissive trust list, plugin tier has default.
# HOME absent. Expected: plugin default wins (project-tier ignored).
# ============================================================================
S3_DIR="$(mktemp -d -t markertrust-s3.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR"' EXIT
S3_HOME="$S3_DIR/empty-home"
S3_CWD="$S3_DIR/cwd"
S3_CACHE="$S3_DIR/cache"
mkdir -p "$S3_HOME" "$S3_CWD/.claude" "$S3_CACHE"
write_settings "$S3_CWD/.claude/settings.flow.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$PERMISSIVE_TRUST}}}"
write_settings "$S3_CWD/.claude/settings.flow.local.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$PERMISSIVE_TRUST}}}"
write_settings "$S3_CACHE/settings.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$DEFAULT_TRUST}}}"
S3_STDOUT="$S3_DIR/stdout"
S3_STDERR="$S3_DIR/stderr"

S3_RESULT=$(run_gate "$S3_CWD" "$S3_HOME" "set" "$S3_CACHE" "$S3_STDOUT" "$S3_STDERR")
assert_eq "S3: project-tier permissive ignored → TRUST_LIST=default" "$DEFAULT_TRUST" "$S3_RESULT"
assert_not_contains "S3: project-tier path NOT in stderr" ".claude/settings.flow.json" "$S3_STDERR"
assert_not_contains "S3: project-tier path NOT in stdout" ".claude/settings.flow.json" "$S3_STDOUT"

# ============================================================================
# S4: HOME=invalid (empty array) → FINDING_LEDGER_BLOCK
# Empty array is the existing rejection criterion. HOME has empty array,
# plugin tier has valid default.
# Expected: FINDING_LEDGER_BLOCK emitted naming HOME, AND falls through to
# plugin default (so the merge can still proceed if user fixes HOME later).
# ============================================================================
S4_DIR="$(mktemp -d -t markertrust-s4.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4_DIR"' EXIT
S4_HOME="$S4_DIR/home"
S4_CWD="$S4_DIR/cwd"
S4_CACHE="$S4_DIR/cache"
mkdir -p "$S4_HOME/.claude" "$S4_CWD" "$S4_CACHE"
write_settings "$S4_HOME/.claude/settings.flow.json" '{"merge":{"markerTrust":{"allowedAssociations":[]}}}'
write_settings "$S4_CACHE/settings.json" "{\"merge\":{\"markerTrust\":{\"allowedAssociations\":$DEFAULT_TRUST}}}"
S4_STDOUT="$S4_DIR/stdout"
S4_STDERR="$S4_DIR/stderr"

S4_RESULT=$(run_gate "$S4_CWD" "$S4_HOME" "set" "$S4_CACHE" "$S4_STDOUT" "$S4_STDERR")
assert_contains "S4: empty array in HOME triggers FINDING_LEDGER_BLOCK" "FINDING_LEDGER_BLOCK" "$S4_STDOUT"
assert_contains "S4: FINDING_LEDGER_BLOCK names HOME path" "settings.flow.json" "$S4_STDOUT"

# ============================================================================
# S5: no sources, defaults preserved
# Neither HOME nor plugin tier exist. Expected: TRUST_LIST defaults to
# the existing default ['OWNER','MEMBER','COLLABORATOR'] (existing behavior).
# ============================================================================
S5_DIR="$(mktemp -d -t markertrust-s5.XXXXXX)"
trap 'rm -rf "$S1_DIR" "$S2_DIR" "$S3_DIR" "$S4_DIR" "$S5_DIR"' EXIT
S5_HOME="$S5_DIR/empty-home"
S5_CWD="$S5_DIR/empty-cwd"
mkdir -p "$S5_HOME" "$S5_CWD"
S5_STDOUT="$S5_DIR/stdout"
S5_STDERR="$S5_DIR/stderr"

S5_RESULT=$(run_gate "$S5_CWD" "$S5_HOME" "unset" "" "$S5_STDOUT" "$S5_STDERR")
assert_eq "S5: no sources → TRUST_LIST=default" "$DEFAULT_TRUST" "$S5_RESULT"

# ============================================================================
echo ""
echo "========================================"
echo "Total: $PASS PASS / $FAIL FAIL"
echo "========================================"
[ $FAIL -eq 0 ] && exit 0 || exit 1
