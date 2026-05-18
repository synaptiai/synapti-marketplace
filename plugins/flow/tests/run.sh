#!/usr/bin/env bash
# plugins/flow/tests/run.sh — flow plugin test runner.
#
# Discovers *.test.sh files in this directory, runs each in a fresh subshell
# with assert.sh sourced, aggregates pass/fail counts, and exits non-zero if
# any assertion failed. No external test framework — pure bash + POSIX utils.
#
# Usage:
#   plugins/flow/tests/run.sh              # run all tests
#   plugins/flow/tests/run.sh <file.test.sh>  # run one file
#
# Exit:
#   0 — all assertions passed
#   1 — at least one assertion failed
#   2 — runner-level error (missing test file, etc.)

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$TESTS_DIR/lib/assert.sh"

if [ ! -f "$LIB" ]; then
  echo "run.sh: missing $LIB" >&2
  exit 2
fi

# repo root is two levels up from tests/ (plugins/flow/tests -> plugins/flow -> repo).
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

# Tests run from REPO_ROOT so relative paths in commands/ (e.g.,
# `.claude/settings.flow.local.json`) resolve against the same directory the
# actual command bash blocks would resolve them in.
cd "$REPO_ROOT"

if [ $# -gt 0 ]; then
  TEST_FILES=("$@")
else
  # Glob in TESTS_DIR; sort for deterministic order.
  shopt -s nullglob
  TEST_FILES=("$TESTS_DIR"/*.test.sh)
  shopt -u nullglob
fi

if [ "${#TEST_FILES[@]}" -eq 0 ]; then
  echo "run.sh: no *.test.sh files found in $TESTS_DIR" >&2
  exit 2
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()

for TEST_FILE in "${TEST_FILES[@]}"; do
  # Resolve relative arg against TESTS_DIR.
  if [ ! -f "$TEST_FILE" ] && [ -f "$TESTS_DIR/$TEST_FILE" ]; then
    TEST_FILE="$TESTS_DIR/$TEST_FILE"
  fi
  if [ ! -f "$TEST_FILE" ]; then
    echo "run.sh: $TEST_FILE not found" >&2
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$TEST_FILE")
    continue
  fi

  echo "=== $(basename "$TEST_FILE") ==="
  # Capture each file's output AND its summary line so the runner can
  # extract counts. Run in a subshell so counter state doesn't leak.
  OUTPUT=$(
    set +e
    # shellcheck source=lib/assert.sh
    source "$LIB"
    # shellcheck disable=SC1090
    source "$TEST_FILE"
    _flow_test_summary
  )
  printf '%s\n' "$OUTPUT"
  # Extract last SUMMARY line — robust against tests that themselves print
  # the word "SUMMARY" in PASS messages.
  SUMMARY=$(printf '%s\n' "$OUTPUT" | grep -E '^SUMMARY pass=[0-9]+ fail=[0-9]+$' | tail -1)
  if [ -z "$SUMMARY" ]; then
    echo "run.sh: WARN no SUMMARY line from $(basename "$TEST_FILE"); counting as 1 failure" >&2
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  FILE_PASS=$(printf '%s' "$SUMMARY" | sed -E 's/.*pass=([0-9]+).*/\1/')
  FILE_FAIL=$(printf '%s' "$SUMMARY" | sed -E 's/.*fail=([0-9]+).*/\1/')
  TOTAL_PASS=$((TOTAL_PASS + FILE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + FILE_FAIL))
  if [ "$FILE_FAIL" != "0" ]; then
    FAILED_FILES+=("$(basename "$TEST_FILE")")
  fi
  echo ""
done

echo "=== overall ==="
echo "TOTAL pass=$TOTAL_PASS fail=$TOTAL_FAIL"
if [ "$TOTAL_FAIL" != "0" ]; then
  echo "FAILED files: ${FAILED_FILES[*]}"
  exit 1
fi
exit 0
