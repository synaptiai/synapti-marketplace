# Source-presence check for plugins/flow/hooks/scripts/flow-goal-evaluator.sh:
# the hook must resolve the active goal through bin/flow-active-goal.sh with
# --path --branch-strict, so it evaluates the current branch's goal and never
# another branch's.

# --- evaluator resolves the active goal branch-aware (not an inline scan) ------
_flow_test_begin "evaluator delegates active-goal lookup to the branch-strict resolver"
HOOK_SRC=$(cat "$REPO_ROOT/plugins/flow/hooks/scripts/flow-goal-evaluator.sh")
assert_contains "flow-active-goal.sh" "$HOOK_SRC" "uses the centralized resolver"
assert_contains "--path --branch-strict" "$HOOK_SRC" "resolves the current branch's goal (no cross-branch / alphabetical-first pick)"
