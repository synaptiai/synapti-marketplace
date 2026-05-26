# Tests for plugins/flow/commands/pr.md + merge.md FlowGoal gate (cycle-13 F1).
# Source-presence lints; behavioral coverage is in flow-cycle14-behavioral.test.sh.
#
# These check that the gate bash blocks are present in the command markdown
# and use the new bin/flow-active-goal.sh helper. Behavioral tests of the
# actual gate logic happen when the command is invoked by Claude; this is
# the lint-level verification that the gate hasn't been silently removed.

PR_CMD="$REPO_ROOT/plugins/flow/commands/pr.md"
MERGE_CMD="$REPO_ROOT/plugins/flow/commands/merge.md"

_flow_test_begin "F1 — /flow:pr Phase 1 includes FlowGoal State section"
if [ ! -f "$PR_CMD" ]; then
  _flow_assert_fail "pr.md missing"
else
  CONTENT=$(cat "$PR_CMD")
  assert_contains "### FlowGoal State" "$CONTENT" "Phase 1 section heading present"
  assert_contains 'flow.goals.goalCreation' "$CONTENT" "migration-aware goalCreation resolution"
  assert_contains "flow-active-goal.sh" "$CONTENT" "uses the centralized helper"
  assert_contains "GATE=pass" "$CONTENT" "pass sentinel emitted"
  assert_contains "GATE=block" "$CONTENT" "block sentinel emitted"
  assert_contains "STATE=none" "$CONTENT" "no-goal state is gate-not-applicable (gate on existence)"
fi

_flow_test_begin "F1 — /flow:pr Phase 4 step 7a uses AskUserQuestion on gate block"
CONTENT=$(cat "$PR_CMD")
assert_contains "FlowGoal gate (v3, opt-in)" "$CONTENT" "Phase 4 step 7a heading present"
assert_contains "/flow:goal evaluate" "$CONTENT" "Recommends running evaluate first"
assert_contains "Create PR with goal not-yet-achieved" "$CONTENT" "Override option offered"
assert_contains "FlowGoal Status" "$CONTENT" "PR body section name documented"

_flow_test_begin "F1 — /flow:merge Phase 1 includes FlowGoal Gate block"
if [ ! -f "$MERGE_CMD" ]; then
  _flow_assert_fail "merge.md missing"
else
  CONTENT=$(cat "$MERGE_CMD")
  assert_contains "### FlowGoal Gate" "$CONTENT" "merge.md Phase 1 gate section present"
  assert_contains "FLOW_GOAL_GATE_STATE" "$CONTENT" "gate state sentinel emitted"
  assert_contains "flow-active-goal.sh" "$CONTENT" "uses centralized helper"
  assert_contains 'flow.goals.goalCreation' "$CONTENT" "migration-aware goalCreation resolution"
  assert_contains "gate not applicable" "$CONTENT" "no-goal merge is NOT blocked (gate on existence)"
fi

_flow_test_begin "F1 — /flow:merge BLOCKED display includes FlowGoal row"
CONTENT=$(cat "$MERGE_CMD")
assert_contains "Merge Prerequisites Not Met" "$CONTENT" "Updated BLOCKED template heading"
assert_contains "| FlowGoal" "$CONTENT" "BLOCKED table has FlowGoal row"
assert_contains "/flow:goal evaluate" "$CONTENT" "remediation references goal evaluate"

# --- gates pass --allow-terminal so an achieved goal is observable -----------
_flow_test_begin "merge.md FlowGoal gate queries the helper with --allow-terminal"
CONTENT=$(cat "$MERGE_CMD")
assert_contains -- "--status --allow-terminal" "$CONTENT" "merge gate --status uses --allow-terminal"
assert_contains -- "--id --allow-terminal" "$CONTENT" "merge gate --id uses --allow-terminal"

_flow_test_begin "pr.md FlowGoal state queries the helper with --allow-terminal"
CONTENT=$(cat "$PR_CMD")
assert_contains -- "--status --allow-terminal" "$CONTENT" "pr gate --status uses --allow-terminal"
assert_contains -- "--id --allow-terminal" "$CONTENT" "pr gate --id uses --allow-terminal"
