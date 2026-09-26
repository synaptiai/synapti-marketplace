#!/usr/bin/env bash
# _dossier_require_mktemp_dir (issue #149): closes the "cd \"\" silently
# no-ops" corruption risk that a bare `VAR=$(_dossier_safe_mktemp_dir ...)`
# call site reopens whenever it forgets to check the command substitution's
# own exit status. This file proves the guarded helper itself works, and
# regression-proves the exact file (local-merge-hook.test.sh) that corrupted
# this repository's working directory twice before the fix.

# Refuse to run without the shared library: its fixture guard is what keeps
# this file's git commands inside its own fixtures (issue #252).
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: ${BASH_SOURCE[0]##*/} must be run through plugins/dossier/tests/run.sh, which loads the fixture guard" >&2; exit 2; }

_dossier_test_begin "mktemp-guard"

# --- Scenario 1: happy path — helper assigns a real, existing directory ----
_dossier_require_mktemp_dir HAPPY_DIR "guard-happy"
if [ -n "$HAPPY_DIR" ] && [ -d "$HAPPY_DIR" ]; then
  _dossier_assert_pass "helper assigns a real, existing directory on success"
else
  _dossier_assert_fail "helper did not assign a usable directory: '$HAPPY_DIR'"
fi

# --- Scenario 2: RUN_TMPDIR invalid -> hard abort, no silent empty passthrough
# Run in a real child process (not a mere `$(...)` subshell) so we can
# observe whether `exit 2` actually escapes the helper and kills the whole
# script, rather than being swallowed the way the original bug swallowed it.
ASSERT_LIB_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/assert.sh"

GUARD_OUTPUT=$(RUN_TMPDIR="" bash -c "source '$ASSERT_LIB_ABS'; _dossier_require_mktemp_dir TARGET 'guard-should-fail'; echo \"UNREACHABLE:TARGET=[\$TARGET]\"" 2>&1)
GUARD_RC=$?

assert_exit "2" "$GUARD_RC" "helper hard-aborts (exit 2) when RUN_TMPDIR is invalid"
assert_not_contains "UNREACHABLE" "$GUARD_OUTPUT" "control flow never reaches past a failed guard call"

# --- Scenario 3: regression — local-merge-hook.test.sh's own fixture setup
# must abort, not fall through to git init/config/checkout. Exercised inside
# an isolated scratch directory (never the real repo) so that even a broken
# fix can only ever corrupt a throwaway fixture, not this working tree.
#
# Note on what this actually proves: local-merge-hook.test.sh has two guarded
# call sites (FLOWLESS_ROOT then REPO); with RUN_TMPDIR invalid, the FIRST
# one aborts before the second is ever reached, so this specifically proves
# the FLOWLESS_ROOT guard fires and the script never gets near the git init
# block behind REPO — it does not independently isolate REPO's own guard.
# That guard mechanism itself (does _dossier_require_mktemp_dir correctly
# abort on failure) is proven generically in scenario 2 above.
TARGET_TEST_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/local-merge-hook.test.sh"
_dossier_require_mktemp_dir GUARD_SCRATCH "local-merge-hook-guard-regression"
mkdir -p "$GUARD_SCRATCH/plugins/dossier/hooks/scripts"
cp "plugins/dossier/hooks/scripts/detect-local-merge.sh" "$GUARD_SCRATCH/plugins/dossier/hooks/scripts/detect-local-merge.sh"
chmod +x "$GUARD_SCRATCH/plugins/dossier/hooks/scripts/detect-local-merge.sh"

REGRESSION_OUTPUT=$(_dossier_in_fixture GUARD_SCRATCH && RUN_TMPDIR="" bash -c "source '$ASSERT_LIB_ABS'; source '$TARGET_TEST_ABS'; echo REGRESSION_UNREACHABLE_MARKER" 2>&1)
REGRESSION_RC=$?

assert_exit "2" "$REGRESSION_RC" "local-merge-hook.test.sh's FLOWLESS_ROOT guard aborts (exit 2) when RUN_TMPDIR is invalid, not a soft failure"
assert_not_contains "REGRESSION_UNREACHABLE_MARKER" "$REGRESSION_OUTPUT" "local-merge-hook.test.sh never reaches its final line when the FLOWLESS_ROOT guard fires early"
if [ -d "$GUARD_SCRATCH/.git" ]; then
  _dossier_assert_fail "regression: a .git directory was created in the scratch cwd — the guard did not prevent the script from reaching git init"
else
  _dossier_assert_pass "no .git directory materialized in the scratch cwd — the script never got far enough to run git init (proves the FLOWLESS_ROOT guard's abort, not REPO's guard specifically — that mechanism is proven generically in scenario 2)"
fi

# --- Scenario 4: pattern-level regression — a helper-consuming function that
# returns its result via stdout (meant to be called as `X=$(fn)`) swallows the
# guard's exit: the whole function runs inside the subshell that `$(...)`
# forks for it, so the guard's `exit 2` only kills that subshell. The fixed
# shape returns through an out-parameter set by _dossier_assign_outvar and is
# called as a plain statement, so the guard's exit reaches the caller.
OUTVAR_WRAPPER_OUTPUT=$(RUN_TMPDIR="" bash -c "
  source '$ASSERT_LIB_ABS'
  outvar_returning_fn() {
    local __outvar=\"\$1\" _d
    _dossier_require_mktemp_dir _d 'wrapper-fixed'
    _dossier_assign_outvar \"\$__outvar\" \"\$_d\"
  }
  outvar_returning_fn RESULT
  echo \"OUTER_UNREACHABLE_MARKER RESULT=[\$RESULT]\"
" 2>&1)
OUTVAR_WRAPPER_RC=$?
assert_exit "2" "$OUTVAR_WRAPPER_RC" "the fixed shape (out-parameter via _dossier_assign_outvar, called as a plain statement) correctly propagates exit 2 through the wrapper"
assert_not_contains "OUTER_UNREACHABLE_MARKER" "$OUTVAR_WRAPPER_OUTPUT" "the fixed shape never reaches the caller's next line when the guard fires inside the wrapper"

# --- Scenario 5: regression — a wrapper's own final assignment must be
# guarded too, not just the mktemp-dir lookup it wraps. A bare `printf -v`
# (bypassing _dossier_assign_outvar) can itself fail silently on a bad
# identifier and, under this suite's `set -uo pipefail` (no `-e`), the
# caller would continue past it with the target var never set — the same
# swallowed-failure shape this whole file exists to close, one line lower.
BAD_OUTVAR_OUTPUT=$(bash -c "
  source '$ASSERT_LIB_ABS'
  wrapper_with_guarded_assign() {
    local __outvar=\"\$1\"
    _dossier_assign_outvar \"\$__outvar\" 'some-value'
  }
  wrapper_with_guarded_assign '1bad-identifier'
  echo OUTER_UNREACHABLE_MARKER
" 2>&1)
BAD_OUTVAR_RC=$?
assert_exit "2" "$BAD_OUTVAR_RC" "_dossier_assign_outvar hard-aborts (exit 2) on an invalid target identifier, rather than letting printf -v fail silently"
assert_not_contains "OUTER_UNREACHABLE_MARKER" "$BAD_OUTVAR_OUTPUT" "control flow never reaches past a failed outvar assignment"

# --- Scenario 6: static lint — no *.test.sh file may define a function that
# calls the guard internally and is ALSO invoked via `$(...)`/backticks
# anywhere in that file. Scenario 4 regression-tests the pattern generically
# but is bound to a synthetic stand-in, not the real functions — this
# scenario is what actually stops a FUTURE helper (or a reversion of
# no_gh_path/setup_fixture) from silently reopening issue #149's bug class.
# Pure awk/grep, no python dependency (matches this suite's own toolset).
TESTS_DIR_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT_VIOLATIONS=""
for LINT_FILE in "$TESTS_DIR_ABS"/*.test.sh; do
  GUARD_FUNCS=$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{[[:space:]]*$/ {
      match($0, /^[A-Za-z_][A-Za-z0-9_]*/)
      fname = substr($0, RSTART, RLENGTH)
      in_func = 1
      has_guard = 0
      next
    }
    in_func && /_dossier_require_mktemp_dir|_dossier_assign_outvar/ { has_guard = 1 }
    in_func && /^\}[[:space:]]*$/ {
      if (has_guard) print fname
      in_func = 0
      next
    }
  ' "$LINT_FILE")
  [ -n "$GUARD_FUNCS" ] || continue
  while IFS= read -r LINT_FNAME; do
    [ -n "$LINT_FNAME" ] || continue
    if grep -vE '^\s*#' "$LINT_FILE" | grep -E "(^|[^A-Za-z0-9_])\\\$\\(\\s*${LINT_FNAME}([[:space:]]|\\))|\`\\s*${LINT_FNAME}([[:space:]]|\`)" >/dev/null; then
      LINT_VIOLATIONS="${LINT_VIOLATIONS}${LINT_FILE##*/}:${LINT_FNAME} "
    fi
  done <<EOF
$GUARD_FUNCS
EOF
done
assert_equal "" "$LINT_VIOLATIONS" "static lint: no guard-consuming function anywhere in plugins/dossier/tests/*.test.sh is invoked via \$(...)/backticks (violations: ${LINT_VIOLATIONS:-none})"

# --- Scenario 7: a fixture directory that mktemp cannot create stops the test
# with a message naming the fixture variable and its prefix (issue #252, AC3).
# mktemp is made to fail by a stub first on PATH rather than by removing write
# permission, which has no effect when the suite runs as root.
_dossier_require_mktemp_dir MKTEMP_STUB_DIR "mktemp-fail-stub"
_dossier_require_mktemp_dir MKTEMP_FAIL_RUN "mktemp-fail-run"
printf '#!/bin/sh\necho "mktemp: refused by the mktemp-guard stub" >&2\nexit 1\n' > "$MKTEMP_STUB_DIR/mktemp"
chmod +x "$MKTEMP_STUB_DIR/mktemp"
MKTEMP_FAIL_OUT=$(PATH="$MKTEMP_STUB_DIR:$PATH" RUN_TMPDIR="$MKTEMP_FAIL_RUN" bash -c "source '$ASSERT_LIB_ABS'; _dossier_require_mktemp_dir F1 rotation-fixture; echo MKTEMP_UNREACHABLE_MARKER" 2>&1)
MKTEMP_FAIL_RC=$?
assert_exit "2" "$MKTEMP_FAIL_RC" "a fixture directory mktemp cannot create stops the test with exit 2"
assert_contains "fixture \$F1" "$MKTEMP_FAIL_OUT" "the failure names the fixture variable"
assert_contains "\"rotation-fixture\"" "$MKTEMP_FAIL_OUT" "the failure names the fixture's directory prefix"
assert_contains "refused by the mktemp-guard stub" "$MKTEMP_FAIL_OUT" "the failure came from mktemp, not from some other step"
assert_not_contains "MKTEMP_UNREACHABLE_MARKER" "$MKTEMP_FAIL_OUT" "control flow never reaches past a fixture directory that could not be created"

_dossier_test_summary
