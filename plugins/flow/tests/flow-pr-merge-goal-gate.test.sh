# Source-presence checks for the FlowGoal gate in plugins/flow/commands/pr.md
# and merge.md.
#
# Both gates must query bin/flow-active-goal.sh with --allow-terminal (so an
# achieved goal is visible) and --branch-strict (so another branch's goal never
# gates this one), and merge.md must map the helper's result to
# FLOW_GOAL_GATE_STATE: achieved -> ok, active and not achieved -> blocked,
# no goal on the branch -> ok with a not-applicable note (the #125 false-block).

PR_CMD="$REPO_ROOT/plugins/flow/commands/pr.md"
MERGE_CMD="$REPO_ROOT/plugins/flow/commands/merge.md"

# --- gates pass --allow-terminal so an achieved goal is observable -----------
_flow_test_begin "merge.md FlowGoal gate queries the helper with --allow-terminal"
CONTENT=$(cat "$MERGE_CMD")
assert_contains "--status --allow-terminal" "$CONTENT" "merge gate --status uses --allow-terminal"
assert_contains "--id --allow-terminal" "$CONTENT" "merge gate --id uses --allow-terminal"

_flow_test_begin "pr.md FlowGoal state queries the helper with --allow-terminal"
CONTENT=$(cat "$PR_CMD")
assert_contains "--status --allow-terminal" "$CONTENT" "pr gate --status uses --allow-terminal"
assert_contains "--id --allow-terminal" "$CONTENT" "pr gate --id uses --allow-terminal"

# --- gate callers resolve branch-strict (no cross-branch false-block) ----------
_flow_test_begin "pr.md + merge.md gate resolve with --branch-strict"
assert_contains "--branch-strict" "$(cat "$PR_CMD")" "pr gate passes --branch-strict to the resolver"
assert_contains "--branch-strict" "$(cat "$MERGE_CMD")" "merge gate passes --branch-strict to the resolver"

# --- #125 regression guard: merge gate maps lifecycle -> FLOW_GOAL_GATE_STATE ---
# The achieved-reads-as-no-active-goal false-block (#125) lives in the precompute
# block's lifecycle->state mapping. Assert all three arms are present so the mapping
# can't silently regress: achieved->ok, exit-0-not-achieved->blocked, exit-1->ok.
_flow_test_begin "#125: merge gate maps an achieved goal to FLOW_GOAL_GATE_STATE=ok"
MCONTENT=$(cat "$MERGE_CMD")
assert_contains '[ "$GOAL_STATUS" = "achieved" ]' "$MCONTENT" "gate branches on achieved status"
assert_contains "FLOW_GOAL_GATE_STATE=ok" "$MCONTENT" "achieved (and not-applicable) arms emit ok"

_flow_test_begin "#125: merge gate blocks an active (not-achieved) goal"
assert_contains "FLOW_GOAL_GATE_STATE=blocked" "$MCONTENT" "non-achieved active goal is a block"
assert_contains "lifecycle is" "$MCONTENT" "block reason names the offending lifecycle status"

_flow_test_begin "#125: merge gate treats exit-1 (no goal on branch) as not-applicable, not a block"
assert_contains "gate not applicable" "$MCONTENT" "exit-1 maps to ok with a not-applicable note"
assert_contains "FLOW_GOAL_GATE_NOTE=no active FlowGoal for this branch" "$MCONTENT" "not-applicable note is explicit"
