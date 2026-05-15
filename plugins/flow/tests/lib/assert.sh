#!/usr/bin/env bash
# assert.sh — minimal bash assertion library for flow tests.
#
# Conventions:
#   - Each assertion writes a result line to $TEST_LOG (set by run.sh per test).
#   - On failure, prints to stderr with file:line citation and increments
#     $TEST_FAIL_COUNT in the calling shell (export it before sourcing).
#   - Tests source this file and call _begin/_end around each named assertion.

# Color output only when stderr is a TTY (CI logs stay plain).
if [ -t 2 ]; then
  _RED=$'\033[31m'; _GREEN=$'\033[32m'; _YELLOW=$'\033[33m'; _RESET=$'\033[0m'
else
  _RED=''; _GREEN=''; _YELLOW=''; _RESET=''
fi

TEST_PASS_COUNT=${TEST_PASS_COUNT:-0}
TEST_FAIL_COUNT=${TEST_FAIL_COUNT:-0}
TEST_CURRENT=""

# _begin <test-name> — call before each test case
_begin() {
  TEST_CURRENT="$1"
}

# _pass / _fail <message> — internal helpers
_pass() {
  TEST_PASS_COUNT=$((TEST_PASS_COUNT + 1))
  printf '  %sPASS%s %s\n' "$_GREEN" "$_RESET" "$TEST_CURRENT" >&2
}

_fail() {
  TEST_FAIL_COUNT=$((TEST_FAIL_COUNT + 1))
  local where="${BASH_SOURCE[2]:-?}:${BASH_LINENO[1]:-?}"
  printf '  %sFAIL%s %s\n' "$_RED" "$_RESET" "$TEST_CURRENT" >&2
  printf '       at %s\n' "$where" >&2
  printf '       %s\n' "$1" >&2
}

# assert_equal <expected> <actual> [message]
assert_equal() {
  if [ "$1" = "$2" ]; then
    _pass
  else
    _fail "${3:-equality} — expected: $(printf '%q' "$1") | got: $(printf '%q' "$2")"
  fi
}

# assert_match <regex> <string> [message] — uses bash =~
assert_match() {
  if [[ "$2" =~ $1 ]]; then
    _pass
  else
    _fail "${3:-regex match} — pattern: $1 | string: $(printf '%q' "$2")"
  fi
}

# assert_no_match <regex> <string> [message]
assert_no_match() {
  if [[ ! "$2" =~ $1 ]]; then
    _pass
  else
    _fail "${3:-regex non-match} — pattern should NOT match: $1 | string: $(printf '%q' "$2")"
  fi
}

# assert_contains <needle> <haystack> [message] — substring check
assert_contains() {
  case "$2" in
    *"$1"*) _pass ;;
    *) _fail "${3:-substring contains} — needle: $(printf '%q' "$1") | haystack: $(printf '%q' "$2")" ;;
  esac
}

# assert_not_contains <needle> <haystack> [message]
assert_not_contains() {
  case "$2" in
    *"$1"*) _fail "${3:-substring should NOT contain} — needle: $(printf '%q' "$1") | haystack: $(printf '%q' "$2")" ;;
    *) _pass ;;
  esac
}

# assert_exit <expected-code> <actual-code> [message]
assert_exit() {
  if [ "$1" -eq "$2" ]; then
    _pass
  else
    _fail "${3:-exit code} — expected: $1 | got: $2"
  fi
}
