#!/usr/bin/env bash
# plugins/dossier/tests/run.sh — dossier plugin test runner.
#
# Discovers *.test.sh files in this directory, runs each in a fresh subshell
# with assert.sh sourced, aggregates pass/fail counts, and exits non-zero if
# any assertion failed. No external test framework — pure bash + POSIX utils.
#
# Usage:
#   plugins/dossier/tests/run.sh              # run all tests
#   plugins/dossier/tests/run.sh <file.test.sh>  # run one file
#
# Exit:
#   0 — all assertions passed
#   1 — at least one assertion failed
#   2 — runner-level error (missing test file, missing prerequisites, cd failed)
#
# Notes on flag choice: `set -uo pipefail` is used WITHOUT `-e` on purpose —
# the runner must keep iterating across test files even if one of them fails
# its assertions. Per-step exit codes are checked explicitly where they matter.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$TESTS_DIR/lib/assert.sh"

if [ ! -f "$LIB" ]; then
  echo "run.sh: missing $LIB" >&2
  exit 2
fi

# Prerequisite check: surface a single clear message at the runner level
# rather than letting individual tests produce cryptic per-tool errors.
for tool in awk grep sed mktemp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "run.sh: missing prerequisite: $tool" >&2
    exit 2
  fi
done

# repo root is two levels up from tests/ (plugins/dossier/tests -> plugins/dossier -> repo).
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

# Tests run from REPO_ROOT so relative paths in commands/ (e.g.,
# `.claude/settings.dossier.local.json`) resolve against the same directory the
# actual command bash blocks would resolve them in. Fail loudly if the cd
# fails — silently running from the caller's cwd would make every test that
# uses a relative path report misleading results.
cd "$REPO_ROOT" || { echo "run.sh: cannot cd to $REPO_ROOT" >&2; exit 2; }

# Every `mktemp` in a test body, and in the scripts those tests invoke, lands
# under a directory this runner owns and removes when the run ends.
#
# Per-file cleanup does not survive contact with a growing suite: test files are
# *sourced*, so an `EXIT` trap set by one is replaced by the next file's, and a
# trailing `rm` gets stranded above whatever the next contributor appends. Both
# happened here. Owning the parent directory makes the guarantee independent of
# per-file discipline — the failure mode is a full disk on a developer's laptop,
# which nothing in the suite would otherwise report.
RUN_TMPDIR=$(mktemp -d -t dossier-run.XXXXXX 2>/dev/null) || {
  echo "run.sh: cannot create a run temp directory" >&2; exit 2; }
export TMPDIR="$RUN_TMPDIR"
trap 'rm -rf "$RUN_TMPDIR" 2>/dev/null' EXIT INT TERM

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
# Tracked separately from assertion failures: a runner-level error (missing
# test file, malformed SUMMARY) is NOT the same as a test failure. The exit
# code distinguishes 1 (assertions failed) from 2 (runner error).
RUNNER_ERR=0

for TEST_FILE in "${TEST_FILES[@]}"; do
  # Resolve relative arg against TESTS_DIR.
  if [ ! -f "$TEST_FILE" ] && [ -f "$TESTS_DIR/$TEST_FILE" ]; then
    TEST_FILE="$TESTS_DIR/$TEST_FILE"
  fi
  if [ ! -f "$TEST_FILE" ]; then
    echo "run.sh: $TEST_FILE not found" >&2
    RUNNER_ERR=1
    FAILED_FILES+=("$TEST_FILE")
    continue
  fi

  echo "=== $(basename "$TEST_FILE") ==="
  # Capture stdout AND stderr together: stderr from awk/grep/jq inside test
  # bodies otherwise interleaves out-of-order with the SUMMARY extraction
  # below and is invisible to CI artifact capture (T4/EV2). Also capture the
  # subshell's exit code so a `set -u` unbound-var abort or explicit `exit`
  # inside a test body surfaces with diagnostic context rather than just a
  # bare "no SUMMARY line".
  OUTPUT=$(
    set +e
    # shellcheck source=lib/assert.sh
    source "$LIB"
    # shellcheck disable=SC1090
    source "$TEST_FILE"
    _dossier_test_summary
  2>&1)
  RC=$?
  printf '%s\n' "$OUTPUT"
  # Extract last SUMMARY line — tolerate trailing whitespace and CR (a stray
  # CRLF in a test file used to make the anchored regex reject the line).
  SUMMARY=$(printf '%s\n' "$OUTPUT" | tr -d '\r' | grep -E '^SUMMARY pass=[0-9]+ fail=[0-9]+[[:space:]]*$' | tail -1)
  if [ -z "$SUMMARY" ]; then
    echo "run.sh: WARN no SUMMARY line from $(basename "$TEST_FILE") (subshell exit=$RC); last lines:" >&2
    printf '%s\n' "$OUTPUT" | tail -10 >&2
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  FILE_PASS=$(printf '%s' "$SUMMARY" | sed -E 's/.*pass=([0-9]+).*/\1/')
  FILE_FAIL=$(printf '%s' "$SUMMARY" | sed -E 's/.*fail=([0-9]+).*/\1/')
  # Defensive: a future SUMMARY format that emits non-numeric values would
  # break the arithmetic that follows. Catch and route to a clear error.
  if ! [[ "$FILE_PASS" =~ ^[0-9]+$ ]] || ! [[ "$FILE_FAIL" =~ ^[0-9]+$ ]]; then
    echo "run.sh: WARN malformed SUMMARY from $(basename "$TEST_FILE"): '$SUMMARY'" >&2
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  # Zero-assertion files are a hazard, not a clean PASS: a future test that
  # accidentally comments out every assertion would otherwise silently
  # report green. Treat as a runner-level error.
  if [ "$FILE_PASS" = "0" ] && [ "$FILE_FAIL" = "0" ]; then
    echo "run.sh: WARN $(basename "$TEST_FILE") executed no assertions; counting as failure" >&2
    RUNNER_ERR=1
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  TOTAL_PASS=$((TOTAL_PASS + FILE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + FILE_FAIL))
  if [ "$FILE_FAIL" != "0" ]; then
    FAILED_FILES+=("$(basename "$TEST_FILE")")
  fi
  echo ""
done

echo "=== overall ==="
echo "TOTAL pass=$TOTAL_PASS fail=$TOTAL_FAIL"
if [ "${#FAILED_FILES[@]}" -gt 0 ]; then
  echo "FAILED files: ${FAILED_FILES[*]}"
fi
# Exit code precedence: runner errors (exit 2) beat assertion failures
# (exit 1) beat success (exit 0). The two are reported separately above so
# CI can tell "you broke the harness" apart from "a real test failed".
if [ "$RUNNER_ERR" != "0" ]; then
  exit 2
fi
if [ "$TOTAL_FAIL" != "0" ]; then
  exit 1
fi
exit 0
