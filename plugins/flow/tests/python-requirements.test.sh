# Tests that every job in the flow CI workflow installs the flow plugin's Python
# dependencies from plugins/flow/requirements.txt.
#
# A job that does not install PyYAML still runs: the suites that need PyYAML
# skip with a pass on a runner image that does not ship it, so their coverage
# disappears without anything turning red.

FLOW_WF="$REPO_ROOT/.github/workflows/flow-tests.yml"

_flow_test_begin "flow-tests.yml installs from the manifest in every job"
INSTALL_LINES=$(grep -cE 'pip install .*-r plugins/flow/requirements\.txt' "$FLOW_WF" || true)
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
' "$FLOW_WF")
[ -z "$JOB_COUNT" ] && JOB_COUNT=0
if [ "$INSTALL_LINES" -ge 2 ] && [ "$INSTALL_LINES" -eq "$JOB_COUNT" ]; then
  _flow_assert_pass "$INSTALL_LINES of $JOB_COUNT jobs install from the manifest"
else
  _flow_assert_fail "$INSTALL_LINES install-from-manifest lines for $JOB_COUNT jobs — a job that does not install PyYAML fails on any runner image that does not ship it, which is how the root-tests job first went red on macOS and green on Ubuntu"
fi
