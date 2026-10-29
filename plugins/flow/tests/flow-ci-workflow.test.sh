# shellcheck shell=bash
# Tests that the flow CI workflow reaches everything it is meant to test.
#
# Each check is a way for coverage to disappear without anything turning red,
# or for runs that are still passing to be cancelled:
# - a path filter that no longer matches tests/ or plugins/flow/hooks/, so a
#   change there does not run the suite;
# - a job that does not install the Python dependencies, or does not run
#   tests/run-all.sh;
# - a condition, continue-on-error or fixed runner that skips the tests or
#   keeps a failing job green;
# - for the flow suite, which runs in parts (run.sh, FLOW_TEST_SHARD=K/N): a
#   matrix that lists parts 1, 2 and 4 of 4, the part not reaching run.sh, one
#   artifact name for every part, or a limit below the floor for its OS.
# tests/lib/flow-workflow-check.py reads the workflow as YAML and makes these
# checks; a text match passes a commented-out line or a row in another layout.
# Without PyYAML the checks skip with a pass. CI installs it, and its
# "Verify test prerequisites" step fails without it.

WF="$REPO_ROOT/.github/workflows/flow-tests.yml"
WF_HAVE_YAML=0
python3 -c "import yaml" >/dev/null 2>&1 && WF_HAVE_YAML=1

_flow_test_begin "flow-tests.yml runs every suite it should, in every part, with a long enough limit"
WF_LINUX_N=""
if [ "$WF_HAVE_YAML" = 0 ]; then
  _flow_assert_pass "SKIP: PyYAML not installed (apt install python3-yaml / pip install pyyaml)"
else
  WF_CHECK=$(python3 "$REPO_ROOT/plugins/flow/tests/lib/flow-workflow-check.py" "$WF" 2>&1)
  WF_LINUX_N=$(printf '%s\n' "$WF_CHECK" | sed -n 's/^LINUX_N=\([0-9][0-9]*\)$/\1/p')
  if printf '%s\n' "$WF_CHECK" | grep -q '^OK '; then
    _flow_assert_pass "the workflow holds: $(printf '%s\n' "$WF_CHECK" | sed -n 's/^OK //p')"
  else
    _flow_assert_fail "flow-tests.yml: $(printf '%s\n' "$WF_CHECK" | grep -v '^LINUX_N=' | tr '\n' ';')"
  fi
fi

_flow_test_begin "the pattern that keeps the System One stub suites off macOS matches them"
# On the macOS runner a stub scenario takes 13 s or more and stubs can fail to
# start in time, so those suites run on Linux only. The workflow selects them
# by a line that calls e2e_stub_start (the check above pins that line); here
# the pattern must still match the suites, or the macOS job would run them.
STUB_RE='^[[:space:]]*e2e_stub_start[[:space:]]'
STUB_SUITES=$(grep -lE "$STUB_RE" "$REPO_ROOT"/plugins/flow/tests/*.test.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "${STUB_SUITES:-0}" -ge 1 ] && grep -qE "$STUB_RE" "$REPO_ROOT/plugins/flow/tests/e2e-system-one.test.sh"; then
  _flow_assert_pass "the pattern matches $STUB_SUITES suite(s), e2e-system-one.test.sh among them"
else
  _flow_assert_fail "the pattern matches no suite, or not e2e-system-one.test.sh: the macOS job would run the stub suites again"
fi

_flow_test_begin "every Linux part runs a suite that writes end-to-end artifacts"
# The upload step fails when a part wrote no artifact. A suite that loads
# tests/lib/e2e.sh writes one file per scenario; each Linux part, taken as
# run.sh takes it (this file runs under run.sh, after the same locale pin),
# must hold one. Only the line that loads the library counts: a comment, a
# message or a quoted pattern naming the file does not.
WF_E2E_RE='^[[:space:]]*(&&[[:space:]]*)?source "\$REPO_ROOT/plugins/flow/tests/lib/e2e\.sh"'
WF_EMPTY=""
if [ -n "$WF_LINUX_N" ]; then
  _wf_k=1
  while [ "$_wf_k" -le "$WF_LINUX_N" ]; do
    _wf_i=0 _wf_hit=0
    for _wf_f in "$REPO_ROOT"/plugins/flow/tests/*.test.sh; do
      if [ $((_wf_i % WF_LINUX_N)) -eq $((_wf_k - 1)) ] && grep -qE "$WF_E2E_RE" "$_wf_f"; then
        _wf_hit=1
      fi
      _wf_i=$((_wf_i + 1))
    done
    [ "$_wf_hit" = 1 ] || WF_EMPTY="$WF_EMPTY $_wf_k/$WF_LINUX_N"
    _wf_k=$((_wf_k + 1))
  done
  if [ -z "$WF_EMPTY" ]; then
    _flow_assert_pass "each of the $WF_LINUX_N Linux parts holds a suite that loads tests/lib/e2e.sh"
  else
    _flow_assert_fail "Linux parts with no end-to-end suite, whose artifact upload would fail:$WF_EMPTY"
  fi
elif [ "$WF_HAVE_YAML" = 1 ]; then
  _flow_assert_fail "no Linux part count was read from the matrix"
else
  _flow_assert_pass "SKIP: PyYAML not installed, so the Linux part count was not read"
fi
