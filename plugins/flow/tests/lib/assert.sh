# Bash assertions for plugins/flow/tests.
#
# Each assertion emits PASS/FAIL to stdout with a file:line citation derived
# from the caller's BASH_SOURCE/LINENO, and returns 0/1 so a calling script
# can decide whether to keep going or abort. The runner aggregates pass/fail
# counts via the FLOW_TEST_PASS / FLOW_TEST_FAIL counters maintained here.
#
# Conventions:
#   - All assertions read FLOW_TEST_CURRENT (the current test name) to label
#     output. Tests call _flow_test_begin "name" before assertions.
#   - Assertions write to stdout (captured by run.sh); diagnostic detail goes
#     to the same line so a tail of the output reads like a checklist.
#   - No external dependencies beyond standard POSIX utilities.

# Counters live in the test process. run.sh re-sources this file per test
# file (each test runs in a fresh subshell), so the counters reset between
# files but accumulate within a file.
: "${FLOW_TEST_PASS:=0}"
: "${FLOW_TEST_FAIL:=0}"
: "${FLOW_TEST_CURRENT:=<unset>}"

_flow_test_begin() {
  FLOW_TEST_CURRENT="$1"
}

_flow_assert_pass() {
  FLOW_TEST_PASS=$((FLOW_TEST_PASS + 1))
  printf 'PASS %s — %s\n' "$FLOW_TEST_CURRENT" "$1"
}

_flow_assert_fail() {
  FLOW_TEST_FAIL=$((FLOW_TEST_FAIL + 1))
  # Depth-aware citation. Two call shapes exist:
  #   (a) assert_equal/match/contains/... wraps _flow_assert_fail
  #       → BASH_SOURCE[2] is the test file (one wrapper between us and caller)
  #   (b) test body calls _flow_assert_fail directly (used by the static
  #       lints in command-frontmatter.test.sh)
  #       → BASH_SOURCE[1] is the test file (no wrapper)
  # Picking the wrong depth produces citations like [run.sh:80] — the line
  # in run.sh that sourced the test, not the assertion line. Detect by
  # checking whether [1] is assert.sh.
  local where
  if [ "${BASH_SOURCE[1]##*/}" = "assert.sh" ]; then
    where="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
  else
    where="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}"
  fi
  printf 'FAIL %s — %s [%s]\n' "$FLOW_TEST_CURRENT" "$1" "$where"
}

# assert_equal <expected> <actual> [<label>]
assert_equal() {
  local expected="$1" actual="$2" label="${3:-equal}"
  if [ "$expected" = "$actual" ]; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: expected '$expected', got '$actual'"
  return 1
}

# assert_match <regex> <actual> [<label>]
# Uses grep -E so the regex is ERE — same flavor the test bodies already use.
# A here-string (not `printf ... | grep`) feeds the haystack: with a pipe,
# `grep -q` exits at the first match and closes the pipe, so printf is killed by
# SIGPIPE (141) and — under the runner's `set -o pipefail` — the pipeline
# reports non-zero even though the match succeeded. That produced nondeterministic
# false failures on large haystacks (the match position races the pipe buffer).
# A here-string has no pipeline, so pipefail/SIGPIPE cannot corrupt the result.
assert_match() {
  local pattern="$1" actual="$2" label="${3:-match}"
  if grep -qE "$pattern" <<<"$actual"; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: '$actual' does not match /$pattern/"
  return 1
}

# assert_contains <needle> <haystack> [<label>]
# Literal substring match (no regex). Useful for asserting on multi-line
# stderr where a regex special would need escaping.
assert_contains() {
  local needle="$1" haystack="$2" label="${3:-contains}"
  case "$haystack" in
    *"$needle"*)
      _flow_assert_pass "$label"
      return 0
      ;;
  esac
  _flow_assert_fail "$label: missing '$needle'"
  return 1
}

# assert_not_contains <needle> <haystack> [<label>]
assert_not_contains() {
  local needle="$1" haystack="$2" label="${3:-not-contains}"
  case "$haystack" in
    *"$needle"*)
      _flow_assert_fail "$label: unexpectedly contains '$needle'"
      return 1
      ;;
  esac
  _flow_assert_pass "$label"
  return 0
}

# assert_exit <expected> <actual> [<label>]
assert_exit() {
  local expected="$1" actual="$2" label="${3:-exit}"
  if [ "$expected" = "$actual" ]; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: expected exit $expected, got $actual"
  return 1
}

# assert_file_exists <path> [<label>]
assert_file_exists() {
  local path="$1" label="${2:-file-exists}"
  if [ -f "$path" ]; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: $path missing"
  return 1
}

# Print summary; called by run.sh after each test file completes.
_flow_test_summary() {
  printf 'SUMMARY pass=%d fail=%d\n' "$FLOW_TEST_PASS" "$FLOW_TEST_FAIL"
}
