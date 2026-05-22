# Tests for plugins/flow/commands/status.md + learn.md v3 sections (cycle-13 F2 + F3).
# Source-presence lints; behavioral coverage is in flow-cycle14-behavioral.test.sh.

STATUS_CMD="$REPO_ROOT/plugins/flow/commands/status.md"
LEARN_CMD="$REPO_ROOT/plugins/flow/commands/learn.md"

_flow_test_begin "F2 — /flow:status includes FlowGoal State + Recent Runs sections"
if [ ! -f "$STATUS_CMD" ]; then
  _flow_assert_fail "status.md missing"
else
  CONTENT=$(cat "$STATUS_CMD")
  assert_contains "### FlowGoal State" "$CONTENT" "FlowGoal State section heading present"
  assert_contains "### Recent Runs" "$CONTENT" "Recent Runs section heading present"
  assert_contains 'flow.goals.enabled' "$CONTENT" "gated behind enabled flag"
  assert_contains "flow-active-goal.sh" "$CONTENT" "uses centralized helper"
  assert_contains "STATE=disabled" "$CONTENT" "v2 mode sentinel"
  assert_contains "last-verdict.json" "$CONTENT" "Recent Runs reads last-verdict.json"
fi

_flow_test_begin "F2 — /flow:status Suggestions table mentions /flow:goal evaluate"
CONTENT=$(cat "$STATUS_CMD")
assert_contains "/flow:goal evaluate" "$CONTENT" "suggestion table includes /flow:goal evaluate path"

_flow_test_begin "F3 — /flow:learn discovers FlowRun events + goal yamls"
if [ ! -f "$LEARN_CMD" ]; then
  _flow_assert_fail "learn.md missing"
else
  CONTENT=$(cat "$LEARN_CMD")
  assert_contains "### FlowRun Events" "$CONTENT" "Phase 1 FlowRun Events section present"
  assert_contains ".flow/goals/" "$CONTENT" "goal yamls enumerated"
  assert_contains ".flow/runs/" "$CONTENT" "run events enumerated"
  assert_contains 'flow.goals.enabled' "$CONTENT" "gated behind enabled flag"
fi

_flow_test_begin "F3 — /flow:learn Phase 2 has Goal Failure Patterns category"
CONTENT=$(cat "$LEARN_CMD")
assert_contains "Goal Failure Patterns" "$CONTENT" "category heading present"
assert_contains "Recurring failed ACs" "$CONTENT" "AC failure signal documented"
assert_contains "Stuck-detection hits" "$CONTENT" "stuck signal documented"
assert_contains "not_executed" "$CONTENT" "not_executed signal documented"
assert_contains "Path-boundary violations" "$CONTENT" "path violation signal documented"
