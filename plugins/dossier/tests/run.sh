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

# The suites build their own git repositories and must never act on the one
# they were started from (issue #252). Git variables inherited from the
# caller either point git at the caller's repository regardless of the
# working directory (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, ...) or inject
# the caller's configuration into every fixture and every script under test
# (GIT_CONFIG_COUNT/KEY_n/VALUE_n, GIT_CONFIG_PARAMETERS, GIT_ATTR_SOURCE).
# Neither belongs in a hermetic test run. GIT_CONFIG_GLOBAL, GIT_CONFIG_NOSYSTEM
# and GIT_ALLOW_PROTOCOL are left alone: they only narrow what git reads or
# may reach, and never redirect it to the caller's repository.
for _git_var in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX \
    GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_ATTR_SOURCE \
    GIT_SHALLOW_FILE GIT_QUARANTINE_PATH GIT_REPLACE_REF_BASE GIT_GRAFT_FILE \
    GIT_NO_REPLACE_OBJECTS GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_CEILING_DIRECTORIES; do
  unset "$_git_var"
done
for _git_var in $(env | sed -nE 's/^(GIT_CONFIG_(KEY|VALUE)_[0-9]+)=.*/\1/p'); do
  unset "$_git_var"
done
unset _git_var

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

# Prerequisite check: a helper that did not load is invisible. `command not
# found` returns 127, the test subshell has no `-e`, and the file still prints
# a SUMMARY -- so a suite left running against half a library reports a clean
# pass over assertions that never executed (deleting assert_equal used to leave
# hooks.test.sh reporting pass=41 fail=0). Checked here rather than inside the
# per-file subshell so a partial library exits as the harness error it is, not
# as one more failed test file.
MISSING_HELPERS=$(
  set +e
  # shellcheck source=lib/assert.sh
  # Not silenced: a library that fails to parse is the likeliest reason helpers
  # go missing, and swallowing its syntax error would report the symptom as the
  # cause. A clean load prints nothing.
  source "$LIB"
  for _h in _dossier_test_begin _dossier_assert_pass _dossier_assert_fail \
            assert_equal assert_match assert_contains assert_not_contains \
            assert_exit assert_file_exists \
            _dossier_in_fixture _dossier_fixture_ready _dossier_git_guard \
            _dossier_fixture_drain_violations _dossier_fixture_unbuilt git cd; do
    declare -F "$_h" >/dev/null || printf '%s ' "$_h"
  done
)
if [ -n "$MISSING_HELPERS" ]; then
  echo "run.sh: $LIB loaded without: $MISSING_HELPERS-- refusing to run any test file against a partial library" >&2
  exit 2
fi

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
#
# Created under "$TMPDIR" by explicit path rather than `mktemp -t`: BSD/macOS
# `mktemp -t` ignores TMPDIR in favour of the per-user system directory, so
# the run landed somewhere other than where the caller asked on one platform
# only.
_run_tmp_base=${TMPDIR:-/tmp}
RUN_TMPDIR=$(mktemp -d "${_run_tmp_base%/}/dossier-run.XXXXXX" 2>/dev/null) || {
  echo "run.sh: cannot create a run temp directory" >&2; exit 2; }
export TMPDIR="$RUN_TMPDIR"
trap 'rm -rf "$RUN_TMPDIR" 2>/dev/null' EXIT INT TERM

# Git looks for a repository by walking up from the working directory. A
# fixture whose `git init`/`git clone` failed is a plain directory, and if the
# run's temp directory sits inside some repository (TMPDIR under a worktree,
# for instance), every git command in that fixture — including those run by
# the scripts under test, which the shell-level guard in lib/assert.sh cannot
# see — would walk up into it. The ceiling stops the walk at the run's own
# directory. Canonical path: git compares ceilings against the resolved path.
GIT_CEILING_DIRECTORIES=$(cd "$RUN_TMPDIR" && pwd -P) || {
  echo "run.sh: cannot resolve $RUN_TMPDIR" >&2; exit 2; }
export GIT_CEILING_DIRECTORIES

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
  # Fixture-guard refusals are recorded in one file under RUN_TMPDIR and turned
  # into FAILs by the file's own summary. A file that exits before its summary
  # leaves its refusals behind; start every file with an empty record so they
  # are never reported under the next file's name (they are reported below,
  # under this one's).
  : > "$RUN_TMPDIR/.dossier-fixture-violations"
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
  ) 2>&1
  RC=$?
  printf '%s\n' "$OUTPUT"
  # Extract last SUMMARY line — tolerate trailing whitespace and CR (a stray
  # CRLF in a test file used to make the anchored regex reject the line).
  SUMMARY=$(printf '%s\n' "$OUTPUT" | tr -d '\r' | grep -E '^SUMMARY pass=[0-9]+ fail=[0-9]+[[:space:]]*$' | tail -1)
  if [ -z "$SUMMARY" ]; then
    echo "run.sh: WARN no SUMMARY line from $(basename "$TEST_FILE") (subshell exit=$RC); last lines:" >&2
    printf '%s\n' "$OUTPUT" | tail -10 >&2
    if [ -s "$RUN_TMPDIR/.dossier-fixture-violations" ]; then
      echo "run.sh: $(basename "$TEST_FILE") also had fixture-guard refusals it never reported:" >&2
      sed "s/^/  $(basename "$TEST_FILE"): /" "$RUN_TMPDIR/.dossier-fixture-violations" >&2
      : > "$RUN_TMPDIR/.dossier-fixture-violations"
    fi
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
