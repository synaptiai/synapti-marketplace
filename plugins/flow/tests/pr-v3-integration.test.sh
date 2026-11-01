# Tests for the v3 runtime integration — pr.md goal gate + FlowRun activity.
#
# The FlowGoal 5-state gate already exists and is covered by
# flow--behavioral.test.sh; this file asserts that gate contract holds
# and the newer pieces are wired:
#   - AC4: pr.md blocks PR creation when the linked goal is not `achieved`,
#     WITH an override path (Option 2) that records an escalation-resolved
#     artifact.
#   - PR body does not claim FlowEvidence sidecars: /flow:start writes none on
#     the start-issue run, so a list of them would name files that do not exist.
#   - pr.md appends a `pr_create` FlowActivity to the branch's start-issue run
#     (it does NOT create its own FlowRun — pr is the tail of start-issue).

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
PR_MD="$PLUGIN_DIR/commands/pr.md"
CONTENT=$(cat "$PR_MD")

_flow_test_begin "pr.md FlowGoal gate blocks when goal not achieved (AC4)"
assert_contains "GATE=block" "$CONTENT" "gate can block"
assert_contains "GATE=pass" "$CONTENT" "gate can pass"
assert_contains "flow-active-goal.sh" "$CONTENT" "reads the active goal via the centralized helper"
assert_match 'achieved' "$CONTENT" "gate keys on achieved lifecycle"

_flow_test_begin "pr.md gate has an override path (AC4 override)"
assert_contains "Option 2" "$CONTENT" "override option present"
assert_contains "escalation-resolved" "$CONTENT" "override records an escalation-resolved artifact"

_flow_test_begin "pr.md PR body does not list FlowEvidence sidecars the start-issue run never wrote"
assert_not_contains ".flow/runs/<run-id>/evidence/" "$CONTENT" "no sidecar directory in the PR body template"
assert_not_contains "evidence sidecar filenames" "$CONTENT" "no instruction to list sidecar files"

_flow_test_begin "pr.md appends a pr_create FlowActivity to the start-issue run"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management"
assert_contains "pr_create" "$CONTENT" "names the pr_create activity"
assert_contains "tail of the" "$CONTENT" "documents pr as the start-issue tail"

_flow_test_begin "pr.md does NOT create its own FlowRun (pr has no workflow of its own)"
assert_not_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "no run-create block (pr continues start-issue)"
assert_not_contains "WORKFLOW=pr-create" "$CONTENT" "no invented pr workflow id"
