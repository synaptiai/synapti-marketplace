# shellcheck shell=bash
# End-to-end: the goal Stop hook judges only the goal that owns the current
# branch (#336).
#
# Each scenario runs the hook Claude Code registers for Stop
# (hooks/scripts/flow-goal-stop.sh) in a scratch repository on branch
# feature/issue-7-x, the reproduction in #336. Goal files are committed, so a
# branch can carry active goals for other issues; the hook must not judge them.
# The artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   B1 with active goals for two branches, the hook reports the first goal in
#      sorted order (issue-1, another branch's) instead of this branch's
#   B2 in block mode the same pick keeps the session working on another
#      issue's criteria
#   B3 with an active goal only for another branch, the hook reports or
#      enforces it instead of approving with no goal
#   B4 two active goals that both own this branch: one is picked silently
#      instead of the stop being allowed with the reason
#   B5 with no branch to go by (detached HEAD), no goal is judged at all

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

STOP_HOOK=hooks/scripts/flow-goal-stop.sh
PAYLOAD='{"session_id":"e2e-branch","stop_hook_active":false}'

# _stop_repo <mode> — the scratch repository on feature/issue-7-x with
# stopHookEnforcement set to <mode>. Verification commands run for every goal,
# so a goal's criterion (its command is `false`) fails and block mode blocks.
_stop_repo() {
  e2e_repo feature/issue-7-x
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg m "$1" '{flow:{goals:{stopHookEnforcement:$m,executeVerificationCommands:true}}}' > "$E2E_REPO/.claude/settings.flow.json"
}

_flow_test_begin "goal Stop hook: warn mode reports this branch's goal, not the first in sorted order (B1)"
e2e_new stop-branch-warn
e2e_describe "active goals issue-1 (feature/issue-1-other) and issue-7 (feature/issue-7-x), on feature/issue-7-x, warn mode"
_stop_repo warn
e2e_goal issue-1 feature/issue-1-other active false
e2e_goal issue-7 feature/issue-7-x active false
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"approve"'
e2e_expect_out "Active goal: issue-7"
e2e_expect_out "Next action: /flow:goal evaluate issue-7"
e2e_expect_no_out "issue-1"
e2e_expect_clean_edges

_flow_test_begin "goal Stop hook: block mode enforces only this branch's goal (B2)"
e2e_new stop-branch-block
e2e_describe "the same two goals, block mode: the block must name issue-7's criteria, never issue-1's"
_stop_repo block
e2e_goal issue-1 feature/issue-1-other active false
e2e_goal issue-7 feature/issue-7-x active false
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"block"'
e2e_expect_out "Active goal: issue-7"
e2e_expect_no_out "issue-1"
e2e_expect_clean_edges

_flow_test_begin "goal Stop hook: an active goal only on another branch is not judged (B3)"
e2e_new stop-branch-other-only
e2e_describe "the only active goal belongs to feature/issue-1-other; block mode on feature/issue-7-x"
_stop_repo block
e2e_goal issue-1 feature/issue-1-other active false
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_line '{"decision":"approve","reason":"no active flow goal"}'
e2e_expect_no_out "issue-1"
e2e_expect_clean_edges

_flow_test_begin "goal Stop hook: two active goals owning this branch are reported, not picked (B4)"
e2e_new stop-branch-two-here
e2e_describe "two active goals both own feature/issue-7-x, block mode: the stop is allowed and the reason says why"
_stop_repo block
e2e_goal issue-7 feature/issue-7-x active false
e2e_goal issue-7b feature/issue-7-x active false
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"approve"'
e2e_expect_out "FLOW_GOAL_UNCHECKED"
e2e_expect_out "2 active goals on branch 'feature/issue-7-x'"
e2e_expect_clean_edges

_flow_test_begin "goal Stop hook: with a detached HEAD the most recent active goal is still judged (B5)"
e2e_new stop-branch-detached
e2e_describe "detached HEAD, one active goal for feature/issue-7-x, warn mode: the hook still reports it"
_stop_repo warn
e2e_goal issue-7 feature/issue-7-x active false
( _e2e_git_env; cd "$E2E_REPO" && git checkout -q --detach ) || _flow_assert_fail "stop-branch-detached: could not detach HEAD"
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out "Active goal: issue-7"
e2e_expect_clean_edges
