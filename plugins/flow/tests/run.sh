#!/usr/bin/env bash
# run.sh — flow plugin test runner.
#
# Discovers and executes *.test.sh files in the same directory as this script.
# Each test file is self-contained — it sources lib/assert.sh, sets up its
# own isolated state, and reports pass/fail via stderr.
#
# Exit code: 0 if all tests pass, 1 otherwise.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TESTS_DIR/.." # plugins/flow — so $PWD matches what callers see in real use

if [ -t 1 ]; then
  _RED=$'\033[31m'; _GREEN=$'\033[32m'; _CYAN=$'\033[36m'; _RESET=$'\033[0m'
else
  _RED=''; _GREEN=''; _CYAN=''; _RESET=''
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()

shopt -s nullglob
TEST_FILES=("$TESTS_DIR"/*.test.sh)
shopt -u nullglob

if [ ${#TEST_FILES[@]} -eq 0 ]; then
  echo "${_RED}No test files found in $TESTS_DIR${_RESET}" >&2
  exit 1
fi

for TEST_FILE in "${TEST_FILES[@]}"; do
  TEST_NAME="$(basename "$TEST_FILE" .test.sh)"
  printf '%s── %s ──%s\n' "$_CYAN" "$TEST_NAME" "$_RESET" >&2

  # Run each test file in a subshell so its exports don't leak. Capture the
  # per-file pass/fail counts via a temp file (subshell state can't propagate
  # back via shell vars).
  COUNT_FILE=$(mktemp -t flow-test-count.XXXXXX 2>/dev/null) || COUNT_FILE="/tmp/flow-test-count.$$"
  (
    set +e
    TEST_PASS_COUNT=0
    TEST_FAIL_COUNT=0
    # shellcheck source=lib/assert.sh
    source "$TESTS_DIR/lib/assert.sh"
    # shellcheck source=/dev/null
    source "$TEST_FILE"
    printf '%d %d\n' "$TEST_PASS_COUNT" "$TEST_FAIL_COUNT" > "$COUNT_FILE"
  )
  read -r PASS FAIL < "$COUNT_FILE"
  rm -f "$COUNT_FILE" 2>/dev/null
  PASS=${PASS:-0}
  FAIL=${FAIL:-0}
  TOTAL_PASS=$((TOTAL_PASS + PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
  if [ "$FAIL" -gt 0 ]; then
    FAILED_FILES+=("$TEST_NAME")
  fi
done

echo "" >&2
if [ $TOTAL_FAIL -eq 0 ]; then
  printf '%s✓ all %d test(s) passed%s\n' "$_GREEN" "$TOTAL_PASS" "$_RESET" >&2
  exit 0
else
  printf '%s✗ %d failed, %d passed%s\n' "$_RED" "$TOTAL_FAIL" "$TOTAL_PASS" "$_RESET" >&2
  for FILE in "${FAILED_FILES[@]}"; do
    printf '  - %s\n' "$FILE" >&2
  done
  exit 1
fi
