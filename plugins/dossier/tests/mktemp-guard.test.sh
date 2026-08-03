# _dossier_require_mktemp_dir (issue #149): closes the "cd \"\" silently
# no-ops" corruption risk that a bare `VAR=$(_dossier_safe_mktemp_dir ...)`
# call site reopens whenever it forgets to check the command substitution's
# own exit status. This file proves the guarded helper itself works, and
# regression-proves the exact file (local-merge-hook.test.sh) that corrupted
# this repository's working directory twice before the fix.

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
TARGET_TEST_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/local-merge-hook.test.sh"
GUARD_SCRATCH=$(_dossier_safe_mktemp_dir "local-merge-hook-guard-regression")
mkdir -p "$GUARD_SCRATCH/plugins/dossier/hooks/scripts"
cp "plugins/dossier/hooks/scripts/detect-local-merge.sh" "$GUARD_SCRATCH/plugins/dossier/hooks/scripts/detect-local-merge.sh"
chmod +x "$GUARD_SCRATCH/plugins/dossier/hooks/scripts/detect-local-merge.sh"

REGRESSION_OUTPUT=$(cd "$GUARD_SCRATCH" && RUN_TMPDIR="" bash -c "source '$ASSERT_LIB_ABS'; source '$TARGET_TEST_ABS'; echo REGRESSION_UNREACHABLE_MARKER" 2>&1)
REGRESSION_RC=$?

assert_exit "2" "$REGRESSION_RC" "local-merge-hook.test.sh aborts (exit 2) when RUN_TMPDIR is invalid, not a soft failure"
assert_not_contains "REGRESSION_UNREACHABLE_MARKER" "$REGRESSION_OUTPUT" "local-merge-hook.test.sh never reaches its final line when the guard fires early"
if [ -d "$GUARD_SCRATCH/.git" ]; then
  _dossier_assert_fail "regression: a .git directory was created in the scratch cwd — the guard did not prevent git init from running against a real-looking directory"
else
  _dossier_assert_pass "no .git directory materialized in the scratch cwd — git init never ran"
fi

_dossier_test_summary
