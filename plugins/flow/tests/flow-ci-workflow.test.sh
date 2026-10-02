# Tests that the flow CI workflow reaches everything it is meant to test.
#
# Each of these is a way for coverage to disappear without anything turning
# red: a workflow that no longer runs tests/run-all.sh, a path filter that no
# longer matches tests/ or plugins/flow/hooks/, so a change there does not
# trigger the suite, or a job that does not install the Python dependencies.
# The suites that need PyYAML skip with a pass on a runner image that does not
# ship it.

WF="$REPO_ROOT/.github/workflows/flow-tests.yml"

_flow_test_begin "flow-tests.yml installs from the manifest in every job"
INSTALL_LINES=$(grep -cE 'pip install .*-r plugins/flow/requirements\.txt' "$WF" || true)
[ -z "$INSTALL_LINES" ] && INSTALL_LINES=0
# Job keys are the two-space-indented mapping keys under the top-level `jobs:`
# block. Counting every two-space key in the file would also count pull_request
# and push under `on:`, which is how the first version of this assertion
# reported three jobs for a two-job workflow.
JOB_COUNT=$(awk '
  /^jobs:/ { in_jobs = 1; next }
  /^[^[:space:]#]/ { in_jobs = 0 }
  in_jobs && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { n++ }
  END { print n + 0 }
' "$WF")
[ -z "$JOB_COUNT" ] && JOB_COUNT=0
if [ "$INSTALL_LINES" -ge 2 ] && [ "$INSTALL_LINES" -eq "$JOB_COUNT" ]; then
  _flow_assert_pass "$INSTALL_LINES of $JOB_COUNT jobs install from the manifest"
else
  _flow_assert_fail "$INSTALL_LINES install-from-manifest lines for $JOB_COUNT jobs — a job that does not install PyYAML fails on any runner image that does not ship it, which is how the root-tests job first went red on macOS and green on Ubuntu"
fi

_flow_test_begin "the workflow invokes the runner"
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

_flow_test_begin "the macOS flow job leaves out the suites that start the System One stub, by content"
# On the macOS runner a stub scenario takes 13 s or more and stubs can fail to
# start in time, so those suites run on Linux only. The selection is by a line
# that calls e2e_stub_start; this keeps it from being renamed away or matching
# nothing, which would leave CI green while the rule did nothing.
STUB_RE='^[[:space:]]*e2e_stub_start[[:space:]]'
if grep -qF "grep -qE '$STUB_RE'" "$WF"; then
  _flow_assert_pass "the flow-tests step selects suites with the e2e_stub_start pattern"
else
  _flow_assert_fail "the flow-tests step no longer selects suites by a line that calls e2e_stub_start"
fi
STUB_SUITES=$(grep -lE "$STUB_RE" "$REPO_ROOT"/plugins/flow/tests/*.test.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "${STUB_SUITES:-0}" -ge 1 ] && grep -qE "$STUB_RE" "$REPO_ROOT/plugins/flow/tests/e2e-system-one.test.sh"; then
  _flow_assert_pass "the pattern matches $STUB_SUITES suite(s), e2e-system-one.test.sh among them"
else
  _flow_assert_fail "the pattern matches no suite, or not e2e-system-one.test.sh: the macOS job would run the stub suites again"
fi
