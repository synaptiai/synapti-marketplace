# Tests for tests/run-all.sh — the runner that reaches the repository-root
# tests/ tree (issue #177).
#
# What is actually at risk here is not whether the runner runs a script. It is
# whether the runner SEES every script. A discovery that matched eight of eleven
# would report "8 passed, 0 failed" and look identical to a healthy run, which
# is exactly how the agentTeams gate stayed broken with nobody noticing. So the
# assertions below compare the runner's own list against the tree, and then
# check that the runner refuses a script it would not have run.

# Cleanup is an EXIT trap, matching cascade-resolve.test.sh and
# commit-journal-churn.test.sh. A trailing `rm` only runs when the file reaches
# its last line, which is exactly not the case on the path that matters.
RTRUN_CLEANUP=()
_rtrun_cleanup() {
  local p
  for p in "${RTRUN_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done
}
trap _rtrun_cleanup EXIT

RUNNER="$REPO_ROOT/tests/run-all.sh"
ROOT_TESTS="$REPO_ROOT/tests"

_flow_test_begin "runner exists and is executable"
if [ -x "$RUNNER" ]; then
  _flow_assert_pass "tests/run-all.sh is executable"
else
  _flow_assert_fail "tests/run-all.sh missing or not executable at $RUNNER"
  return 0
fi

_flow_test_begin "the workflow invokes the runner"
WF="$REPO_ROOT/.github/workflows/flow-tests.yml"
if grep -q 'tests/run-all.sh' "$WF"; then
  _flow_assert_pass "flow-tests.yml runs tests/run-all.sh"
else
  _flow_assert_fail "no workflow step runs tests/run-all.sh — the root tests are unreached again"
fi

_flow_test_begin "the workflow path filter matches the root tests directory"
FILTER_HITS=$(grep -c "^      - 'tests/\*\*'" "$WF" || true)
[ -z "$FILTER_HITS" ] && FILTER_HITS=0
if [ "$FILTER_HITS" -eq 2 ]; then
  _flow_assert_pass "tests/** is filtered on both pull_request and push"
else
  _flow_assert_fail "expected tests/** in 2 path-filter lists, found $FILTER_HITS — a change under tests/ would not trigger the workflow"
fi

_flow_test_begin "the workflow path filter matches the flow hooks directory"
HOOK_HITS=$(grep -c "^      - 'plugins/flow/hooks/\*\*'" "$WF" || true)
[ -z "$HOOK_HITS" ] && HOOK_HITS=0
if [ "$HOOK_HITS" -eq 2 ]; then
  _flow_assert_pass "plugins/flow/hooks/** is filtered on both pull_request and push"
else
  _flow_assert_fail "expected plugins/flow/hooks/** in 2 path-filter lists, found $HOOK_HITS — a hook change would not run the flow suite"
fi

# --- Discovery covers the tree ----------------------------------------------
# The expected value is derived from the tree itself rather than from a number
# written here, so adding a twelfth check does not require editing this test —
# but a check the runner cannot see still fails it.
_flow_test_begin "runner --list finds every entry point in the tree"
EXPECTED=$(find "$ROOT_TESTS" -type f \( -name 'test.sh' -o -name 'validate.sh' -o -name 'verify.sh' \) \
  | sed "s|^$REPO_ROOT/||" | LC_ALL=C sort)
ACTUAL=$("$RUNNER" --list 2>/dev/null | LC_ALL=C sort)
EXPECTED_N=$(printf '%s\n' "$EXPECTED" | grep -c . || true)
if [ "$EXPECTED" = "$ACTUAL" ] && [ "${EXPECTED_N:-0}" -gt 0 ]; then
  _flow_assert_pass "runner lists all $EXPECTED_N entry points"
else
  _flow_assert_fail "runner list differs from the tree:
$(diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL") || true)"
fi

_flow_test_begin "the tree actually holds checks (discovery is not vacuously satisfied)"
# A discovery bug that returns nothing would satisfy an equality check against a
# tree walk that also returns nothing. Pin the floor independently: the eleven
# scripts named in issue #177 were all present when this was written.
if [ "${EXPECTED_N:-0}" -ge 11 ]; then
  _flow_assert_pass "$EXPECTED_N entry points present (issue #177 counted 11)"
else
  _flow_assert_fail "only $EXPECTED_N entry points found; issue #177 counted 11 — checks have been removed without this test being updated"
fi

# --- Mutant that must fire: an entry point the runner cannot classify --------
_flow_test_begin "runner refuses a shell script it would not have run"
SCRATCH=$(mktemp -d -t root-tests-mutant.XXXXXX 2>/dev/null) || SCRATCH=""
# An unguarded mktemp turns the paths below into /tests/..., which is a no-op
# on a Mac and a write to the filesystem root in a root container.
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then
  _flow_assert_fail "mktemp -d failed; cannot build the mutant tree"
  return 0
fi
RTRUN_CLEANUP+=("$SCRATCH")
mkdir -p "$SCRATCH/tests/newcheck"
cp "$RUNNER" "$SCRATCH/tests/run-all.sh"
chmod +x "$SCRATCH/tests/run-all.sh"
# A healthy entry point sits alongside it, so the refusal is attributable to the
# unrecognised name and not to an empty tree.
printf '#!/usr/bin/env bash\necho "PASS: synthetic"\nexit 0\n' > "$SCRATCH/tests/newcheck/test.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/tests/newcheck/checks.sh"
MUTANT_OUT=$("$SCRATCH/tests/run-all.sh" 2>&1); MUTANT_RC=$?
if [ "$MUTANT_RC" -eq 2 ] && printf '%s' "$MUTANT_OUT" | grep -q 'checks.sh'; then
  _flow_assert_pass "unrecognised script exits 2 and is named"
else
  _flow_assert_fail "runner accepted an unrecognised script (exit $MUTANT_RC): $MUTANT_OUT"
fi

# --- Mutant that must NOT fire: an ordinary new check ------------------------
_flow_test_begin "runner picks up a newly added test.sh without any edit to itself"
rm -f "$SCRATCH/tests/newcheck/checks.sh"
NEW_LIST=$("$SCRATCH/tests/run-all.sh" --list 2>/dev/null)
if printf '%s' "$NEW_LIST" | grep -q 'newcheck/test.sh'; then
  _flow_assert_pass "a new test.sh is discovered with no runner change"
else
  _flow_assert_fail "a newly added test.sh was not discovered: $NEW_LIST"
fi

# --- A failing check must fail the runner ------------------------------------
_flow_test_begin "one failing check fails the whole run"
printf '#!/usr/bin/env bash\necho "FAIL: synthetic"\nexit 1\n' > "$SCRATCH/tests/newcheck/test.sh"
FAIL_OUT=$("$SCRATCH/tests/run-all.sh" 2>&1); FAIL_RC=$?
if [ "$FAIL_RC" -eq 1 ] && printf '%s' "$FAIL_OUT" | grep -q 'newcheck/test.sh'; then
  _flow_assert_pass "runner exits 1 and names the failing check"
else
  _flow_assert_fail "runner did not fail on a failing check (exit $FAIL_RC): $FAIL_OUT"
fi

_flow_test_begin "runner reports how much it examined"
if printf '%s' "$FAIL_OUT" | grep -qE 'examined [0-9]+ entry points'; then
  _flow_assert_pass "run summary states the number of entry points examined"
else
  _flow_assert_fail "run summary does not say how much was examined — a discovery that found nothing would look like a clean run"
fi

