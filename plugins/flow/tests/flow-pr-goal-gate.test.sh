# Source-presence checks for the FlowGoal state lookup in
# plugins/flow/commands/pr.md.
#
# It must query bin/flow-active-goal.sh with --allow-terminal (so an achieved
# goal is visible) and --branch-strict (so another branch's goal never gates
# this one). merge.md's gate is run end to end in e2e-merge-gates.test.sh.

PR_CMD="$REPO_ROOT/plugins/flow/commands/pr.md"

_flow_test_begin "pr.md FlowGoal state queries the helper with --allow-terminal"
CONTENT=$(cat "$PR_CMD")
assert_contains "--status --allow-terminal" "$CONTENT" "pr gate --status uses --allow-terminal"
assert_contains "--id --allow-terminal" "$CONTENT" "pr gate --id uses --allow-terminal"

_flow_test_begin "pr.md gate resolves with --branch-strict"
assert_contains "--branch-strict" "$CONTENT" "pr gate passes --branch-strict to the resolver"
