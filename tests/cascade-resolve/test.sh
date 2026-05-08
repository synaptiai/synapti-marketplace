#!/usr/bin/env bash
# cascade-resolve.sh test harness.
#
# Verifies the four-tier cascade behavior, parse-error WARN surfacing,
# default-value handling, and compact-vs-raw output mode.
#
# Exits 0 on all PASS, 1 on any FAIL, 2 on infrastructure error.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$REPO_ROOT/plugins/flow/bin/cascade-resolve.sh"
PASS=0
FAIL=0

if [ ! -x "$HELPER" ]; then
  echo "FATAL: $HELPER not executable" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq not installed" >&2
  exit 2
fi

TEMP_DIRS=()
cleanup() { for d in "${TEMP_DIRS[@]}"; do rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

new_sandbox() {
  local d
  d=$(mktemp -d -t cascade-resolve.XXXXXX)
  TEMP_DIRS+=("$d")
  printf '%s' "$d"
}

write_settings() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" >"$path"
}

# Run helper in a controlled environment.
# Args: $1 = sandbox dir (becomes CWD), $2 = HOME, $3 = CLAUDE_PLUGIN_ROOT (or empty),
#       remaining = helper args
run_helper() {
  local sandbox="$1" home="$2" plugin_root="$3"
  shift 3
  (
    cd "$sandbox"
    export HOME="$home"
    if [ -n "$plugin_root" ]; then
      export CLAUDE_PLUGIN_ROOT="$plugin_root"
    else
      unset CLAUDE_PLUGIN_ROOT
    fi
    "$HELPER" "$@"
  )
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

assert_stderr_contains() {
  local label="$1" needle="$2" stderr_file="$3"
  if grep -qF "$needle" "$stderr_file"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    echo "  needle: $needle"
    echo "  stderr:"
    sed 's/^/    /' "$stderr_file"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# S1: project-local wins over all lower tiers
# ============================================================================
S1=$(new_sandbox)
S1_HOME="$S1/home"
S1_CWD="$S1/cwd"
S1_PLUG="$S1/plug"
mkdir -p "$S1_HOME/.claude" "$S1_CWD/.claude" "$S1_PLUG"
write_settings "$S1_CWD/.claude/settings.flow.local.json" '{"journal":{"dir":"local-dir"}}'
write_settings "$S1_CWD/.claude/settings.flow.json" '{"journal":{"dir":"project-dir"}}'
write_settings "$S1_HOME/.claude/settings.flow.json" '{"journal":{"dir":"home-dir"}}'
write_settings "$S1_PLUG/settings.json" '{"journal":{"dir":"plugin-dir"}}'

S1_RESULT=$(run_helper "$S1_CWD" "$S1_HOME" "$S1_PLUG" '.journal.dir // empty')
assert_eq "S1: project-local wins over project, home, plugin" "local-dir" "$S1_RESULT"

# ============================================================================
# S2: project-shared wins when local missing
# ============================================================================
S2=$(new_sandbox)
S2_HOME="$S2/home"
S2_CWD="$S2/cwd"
S2_PLUG="$S2/plug"
mkdir -p "$S2_HOME/.claude" "$S2_CWD/.claude" "$S2_PLUG"
write_settings "$S2_CWD/.claude/settings.flow.json" '{"journal":{"dir":"project-dir"}}'
write_settings "$S2_HOME/.claude/settings.flow.json" '{"journal":{"dir":"home-dir"}}'
write_settings "$S2_PLUG/settings.json" '{"journal":{"dir":"plugin-dir"}}'

S2_RESULT=$(run_helper "$S2_CWD" "$S2_HOME" "$S2_PLUG" '.journal.dir // empty')
assert_eq "S2: project-shared wins when local missing" "project-dir" "$S2_RESULT"

# ============================================================================
# S3: user-global wins when local + project missing
# ============================================================================
S3=$(new_sandbox)
S3_HOME="$S3/home"
S3_CWD="$S3/cwd"
S3_PLUG="$S3/plug"
mkdir -p "$S3_HOME/.claude" "$S3_CWD" "$S3_PLUG"
write_settings "$S3_HOME/.claude/settings.flow.json" '{"journal":{"dir":"home-dir"}}'
write_settings "$S3_PLUG/settings.json" '{"journal":{"dir":"plugin-dir"}}'

S3_RESULT=$(run_helper "$S3_CWD" "$S3_HOME" "$S3_PLUG" '.journal.dir // empty')
assert_eq "S3: user-global wins when local+project missing" "home-dir" "$S3_RESULT"

# ============================================================================
# S4: plugin default when only plugin tier exists
# ============================================================================
S4=$(new_sandbox)
S4_HOME="$S4/empty-home"
S4_CWD="$S4/empty-cwd"
S4_PLUG="$S4/plug"
mkdir -p "$S4_HOME" "$S4_CWD" "$S4_PLUG"
write_settings "$S4_PLUG/settings.json" '{"journal":{"dir":"plugin-dir"}}'

S4_RESULT=$(run_helper "$S4_CWD" "$S4_HOME" "$S4_PLUG" '.journal.dir // empty')
assert_eq "S4: plugin tier resolves when others missing" "plugin-dir" "$S4_RESULT"

# ============================================================================
# S5: --default returns when no source resolves
# ============================================================================
S5=$(new_sandbox)
S5_HOME="$S5/empty-home"
S5_CWD="$S5/empty-cwd"
mkdir -p "$S5_HOME" "$S5_CWD"

S5_RESULT=$(run_helper "$S5_CWD" "$S5_HOME" "" --default ".decisions" '.journal.dir // empty')
assert_eq "S5: --default returned when no source has the key" ".decisions" "$S5_RESULT"

# Same scenario without --default: empty stdout
S5B_RESULT=$(run_helper "$S5_CWD" "$S5_HOME" "" '.journal.dir // empty')
assert_eq "S5b: no --default, no source has key → empty stdout" "" "$S5B_RESULT"

# ============================================================================
# S6: parse error in one tier emits WARN, falls through to next
# ============================================================================
S6=$(new_sandbox)
S6_HOME="$S6/home"
S6_CWD="$S6/cwd"
S6_PLUG="$S6/plug"
mkdir -p "$S6_HOME/.claude" "$S6_CWD/.claude" "$S6_PLUG"
write_settings "$S6_CWD/.claude/settings.flow.local.json" '{not valid json'
write_settings "$S6_CWD/.claude/settings.flow.json" '{"journal":{"dir":"recovered"}}'
write_settings "$S6_PLUG/settings.json" '{"journal":{"dir":"plugin-dir"}}'

S6_STDERR=$(mktemp)
TEMP_DIRS+=("$(dirname "$S6_STDERR")")
S6_RESULT=$(run_helper "$S6_CWD" "$S6_HOME" "$S6_PLUG" '.journal.dir // empty' 2>"$S6_STDERR")
assert_eq "S6: parse error in local falls through to project-shared" "recovered" "$S6_RESULT"
assert_stderr_contains "S6: WARN names settings.flow.local.json as failing source" "settings.flow.local.json" "$S6_STDERR"

# ============================================================================
# S7: --compact preserves JSON quoting (booleans + arrays)
# ============================================================================
S7=$(new_sandbox)
S7_HOME="$S7/empty-home"
S7_CWD="$S7/cwd"
S7_PLUG="$S7/plug"
mkdir -p "$S7_HOME" "$S7_CWD/.claude" "$S7_PLUG"
write_settings "$S7_CWD/.claude/settings.flow.json" '{"agentTeams": true, "list": ["a","b"]}'

S7_BOOL=$(run_helper "$S7_CWD" "$S7_HOME" "" --compact '.agentTeams // empty')
assert_eq "S7: --compact preserves boolean true (no quotes)" "true" "$S7_BOOL"

S7_ARR=$(run_helper "$S7_CWD" "$S7_HOME" "" --compact '.list // empty')
assert_eq "S7b: --compact preserves array as JSON" '["a","b"]' "$S7_ARR"

# ============================================================================
# S8: missing arg exits 2
# ============================================================================
S8_RESULT=$("$HELPER" 2>&1; echo "EXIT:$?")
S8_EXIT=$(echo "$S8_RESULT" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
assert_eq "S8: missing arg exits 2" "2" "$S8_EXIT"

# ============================================================================
# S9: --default with empty value works (useful for "no fallback" intent)
# ============================================================================
S9=$(new_sandbox)
S9_HOME="$S9/empty-home"
S9_CWD="$S9/empty-cwd"
mkdir -p "$S9_HOME" "$S9_CWD"

S9_RESULT=$(run_helper "$S9_CWD" "$S9_HOME" "" --default "" '.journal.dir // empty')
assert_eq "S9: --default empty + no resolution → empty stdout" "" "$S9_RESULT"

# ============================================================================
echo ""
echo "========================================"
echo "Total: $PASS PASS / $FAIL FAIL"
echo "========================================"
[ $FAIL -eq 0 ] && exit 0 || exit 1
