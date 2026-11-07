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
#   B6 run from a subdirectory of the repository, the hook reads no
#      stopHookEnforcement from the repository's settings and falls back to
#      warn, so a block-mode repository's stop is allowed (#337)

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

_flow_test_begin "goal Stop hook: run from a subdirectory, the repository's block mode still applies (B6)"
e2e_new stop-branch-subdir
e2e_describe "block mode set in the repository's .claude/settings.flow.json; the hook runs in sub/deeper"
_stop_repo block
e2e_goal issue-7 feature/issue-7-x active false
mkdir -p "$E2E_REPO/sub/deeper"
printf '%s' "$PAYLOAD" > "$E2E_DIR/payload.json"
printf 'code: %s (run in sub/deeper)\npayload: %s\n' "$STOP_HOOK" "$PAYLOAD" | _e2e_art
_e2e_exec sh -c 'cd sub/deeper && exec "$CLAUDE_PLUGIN_ROOT/$1" < "$2"' sh "$STOP_HOOK" "$E2E_DIR/payload.json"
printf -- '--- expectations\n' | _e2e_art
e2e_expect_out '"decision":"block"'
e2e_expect_out "stopHookEnforcement=block"
e2e_expect_clean_edges

# Ways a goal created, updated or read in a subdirectory can be wrong (#337),
# written down before the scenarios. The goals are the repository top's, as
# bin/flow-active-goal.sh reads them, and every writer must agree with it.
#   B7  flow-goal-record.sh --create run in packages/app writes
#       packages/app/.flow/goals, which the lookup (and so the Stop hook and
#       the merge gate) never reads
#   B8  the Stop hook run in packages/app says "no active flow goal" about the
#       goal just created there
#   B9  flow-goal-record.sh --update-lifecycle run in packages/app says the
#       goal at the top does not exist, so the evaluator cannot move it
#   B10 run at the top, the paths printed change (relative before, absolute
#       after), which callers and their tests read
#   B11 bin/flow-goal-judge-run.sh run in packages/app finds no goal file to
#       read, so /flow:goal evaluate gets no judge verdict
#   B12 with flow.runtime.stateDir set, the goals land under packages/app
#       instead of the top's <stateDir>/goals, or bin/flow-runtime-dir.sh
#       --goals names a different directory from the one written

# _goal_input <id> — a schema-valid active goal for feature/issue-7-x whose
# criterion fails (its command is `false`), written to
# $E2E_DIR/<id>.input.yaml, outside the repository.
_goal_input() {
  e2e_goal "$1" feature/issue-7-x active false
  mv "$E2E_REPO/.flow/goals/$1.goal.yaml" "$E2E_DIR/$1.input.yaml"
  rmdir "$E2E_REPO/.flow/goals" "$E2E_REPO/.flow"
}
# _in_app <script under the plugin> [arguments] — run it in packages/app.
_in_app() {
  mkdir -p "$E2E_REPO/packages/app"
  printf 'code: %s (run in packages/app)\narguments: %s\n' "$1" "${*:2}" | _e2e_art
  _e2e_exec sh -c 'cd packages/app && s=$1 && shift && exec "$CLAUDE_PLUGIN_ROOT/$s" "$@"' sh "$@"
  printf -- '--- expectations\n' | _e2e_art
}
# _hook_in_app — the Stop hook, fed $PAYLOAD, in packages/app.
_hook_in_app() {
  mkdir -p "$E2E_REPO/packages/app"
  printf '%s' "$PAYLOAD" > "$E2E_DIR/payload.json"
  printf 'code: %s (run in packages/app)\npayload: %s\n' "$STOP_HOOK" "$PAYLOAD" | _e2e_art
  _e2e_exec sh -c 'cd packages/app && exec "$CLAUDE_PLUGIN_ROOT/$1" < "$2"' sh "$STOP_HOOK" "$E2E_DIR/payload.json"
  printf -- '--- expectations\n' | _e2e_art
}
# _top_status <id> — lifecycle.status of the goal at the repository top.
_top_status() {
  python3 -c 'import sys, yaml; print(((yaml.safe_load(open(sys.argv[1])) or {}).get("lifecycle") or {}).get("status", ""))' \
    "$E2E_REPO/.flow/goals/$1.goal.yaml" 2>/dev/null || printf 'missing'
}
# _exists <path under the repository> — yes or no.
_exists() { if [ -e "$E2E_REPO/$1" ]; then printf yes; else printf no; fi; }

_flow_test_begin "goal record: --create run in a subdirectory writes the top's goals, which the lookup reads (B7)"
e2e_new goal-create-subdir
e2e_describe "flow-goal-record.sh --create in packages/app, then flow-active-goal.sh --path --branch-strict there"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
_goal_input issue-7
_in_app bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/issue-7.input.yaml"
e2e_expect_equal 0 "$E2E_RC" "the create's exit status"
e2e_expect_err "created $TOP/.flow/goals/issue-7.goal.yaml"
e2e_expect_equal yes "$(_exists .flow/goals/issue-7.goal.yaml)" "a goal file at the top"
e2e_expect_equal no "$(_exists packages/app/.flow)" "a .flow in packages/app"
_in_app bin/flow-active-goal.sh --path --branch-strict
e2e_expect_equal 0 "$E2E_RC" "the lookup's exit status"
e2e_expect_line "$TOP/.flow/goals/issue-7.goal.yaml"
e2e_expect_clean_edges

_flow_test_begin "goal Stop hook: a goal created in a subdirectory is judged by the hook run there (B8)"
e2e_new stop-branch-create-subdir
e2e_describe "flow-goal-record.sh --create in packages/app, then the Stop hook in packages/app, warn mode"
_stop_repo warn
_goal_input issue-7
_in_app bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/issue-7.input.yaml"
e2e_expect_equal 0 "$E2E_RC" "the create's exit status"
_hook_in_app
e2e_expect_out '"decision":"approve"'
e2e_expect_out "Active goal: issue-7"
e2e_expect_no_out "no active flow goal"
e2e_expect_clean_edges

_flow_test_begin "goal record: --update-lifecycle run in a subdirectory updates the top's goal (B9)"
e2e_new goal-update-subdir
e2e_describe "an active goal at the top; flow-goal-record.sh --update-lifecycle --from-status active in packages/app moves it to waiting_for_user"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
e2e_goal issue-7 feature/issue-7-x active true
printf 'lifecycle:\n  status: waiting_for_user\n' > "$E2E_DIR/lifecycle.yaml"
_in_app bin/flow-goal-record.sh --update-lifecycle --goal-id issue-7 --lifecycle-file "$E2E_DIR/lifecycle.yaml" --from-status active --merge
e2e_expect_equal 0 "$E2E_RC" "the update's exit status"
e2e_expect_err "updated $TOP/.flow/goals/issue-7.goal.yaml lifecycle.status to 'waiting_for_user'"
e2e_expect_equal waiting_for_user "$(_top_status issue-7)" "the top goal's lifecycle.status"
e2e_expect_equal no "$(_exists packages/app/.flow)" "a .flow in packages/app"
e2e_expect_clean_edges

_flow_test_begin "goal record: run at the top, the paths printed stay relative (B10)"
e2e_new goal-record-top
e2e_describe "flow-goal-record.sh --create and --update-lifecycle, and the lookup, at the repository top"
_stop_repo warn
_goal_input issue-7
e2e_run_bin bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/issue-7.input.yaml"
e2e_expect_equal 0 "$E2E_RC" "the create's exit status"
e2e_expect_err "created .flow/goals/issue-7.goal.yaml"
printf 'lifecycle:\n  status: waiting_for_user\n' > "$E2E_DIR/lifecycle.yaml"
e2e_run_bin bin/flow-goal-record.sh --update-lifecycle --goal-id issue-7 --lifecycle-file "$E2E_DIR/lifecycle.yaml" --merge
e2e_expect_err "updated .flow/goals/issue-7.goal.yaml lifecycle.status to 'waiting_for_user'"
e2e_run_bin bin/flow-active-goal.sh --path --any-status --branch-strict
e2e_expect_line ".flow/goals/issue-7.goal.yaml"
e2e_expect_clean_edges

_flow_test_begin "goal judge: bin/flow-goal-judge-run.sh run in a subdirectory reads the top's goal (B11)"
e2e_new goal-judge-run-subdir
e2e_describe "an active goal at the top whose one criterion passes; the judge helper runs in packages/app and the judge replies achieved"
_stop_repo warn
e2e_goal issue-7 feature/issue-7-x active true
e2e_judge_says '{"structured_output":{"verdict":"achieved","confidence":0.9,"delta":"made_progress","next_step_hint":"none","reason":"AC1 passes"}}'
_in_app bin/flow-goal-judge-run.sh issue-7 ""
e2e_expect_no_out "no goal file to read"
e2e_expect_line "JUDGE_STATE=done"
e2e_expect_equal 1 "$(wc -l < "$E2E_DIR/judge-calls.log" 2>/dev/null | tr -d ' ')" "the judge calls"
e2e_expect_clean_edges

_flow_test_begin "goal record: with flow.runtime.stateDir set, a subdirectory writes and names the top's goals (B12)"
e2e_new goal-statedir-subdir
e2e_describe "flow.runtime.stateDir is state/flow; flow-goal-record.sh --create, flow-runtime-dir.sh --goals and the lookup all run in packages/app"
e2e_repo feature/issue-7-x
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"runtime":{"stateDir":"state/flow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
TOP=$(cd "$E2E_REPO" && pwd -P)
_goal_input issue-7
_in_app bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/issue-7.input.yaml"
e2e_expect_equal 0 "$E2E_RC" "the create's exit status"
e2e_expect_equal yes "$(_exists state/flow/goals/issue-7.goal.yaml)" "a goal file in the top's state/flow/goals"
e2e_expect_equal no "$(_exists packages/app/state)" "a state directory in packages/app"
_in_app bin/flow-runtime-dir.sh --goals
e2e_expect_line "$TOP/state/flow/goals"
_in_app bin/flow-active-goal.sh --path --branch-strict
e2e_expect_line "$TOP/state/flow/goals/issue-7.goal.yaml"
e2e_run_bin bin/flow-runtime-dir.sh --goals
e2e_expect_line "state/flow/goals"
e2e_expect_clean_edges

# Ways a terminal goal can be changed from a subdirectory (#337), written down
# before the scenarios. A terminal goal (achieved, failed, cancelled) never
# changes; the readers must see the goals where the writer writes them, at the
# repository top, and the writer must not replace a terminal goal.
#   B13 /flow:start run in packages/app does not see the achieved goal at the
#       top and answers FLOW_GOAL_STATE=create, which goes on to create the
#       goal again under the same id
#   B14 the same for an active goal at the top: create instead of exists, so
#       the goal in progress is not resumed
#   B15 flow-goal-record.sh --create, at the top or in packages/app, replaces
#       an achieved, failed or cancelled goal with a new active one: it
#       refuses only a goal that is not terminal
#   B16 /flow:goal status run in packages/app finds no goal under
#       packages/app and says no goal is active, beside the active one at the
#       top
#   B17 /flow:learn run in packages/app lists no goal file, so its goal
#       patterns read nothing

START_MD="commands/start.md"
GOAL_CHECK_MARK='FLOW_GOAL_STATE=terminal'

# _commit_goals — commit .flow/goals, as a branch carries its goal.
_commit_goals() {
  ( _e2e_git_env; cd "$E2E_REPO" && git add .flow && git commit -q -m goals ) \
    || _flow_assert_fail "$E2E_NAME: could not commit the goals"
}
# _fence_in_app <command.md> <marker> [arguments] — run that fence with the
# working directory in packages/app, as the Bash tool keeps it between calls.
_fence_in_app() {
  local top="$E2E_REPO"
  mkdir -p "$top/packages/app"
  E2E_REPO="$top/packages/app"
  printf 'working directory: <repo>/packages/app\n' | _e2e_art
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/$1" "$2" "${3:-}"
  E2E_REPO="$top"
}
# _block_in_app <command.md> <BLOCK> — the same for a marker-delimited block.
_block_in_app() {
  local top="$E2E_REPO"
  mkdir -p "$top/packages/app"
  E2E_REPO="$top/packages/app"
  printf 'working directory: <repo>/packages/app\n' | _e2e_art
  e2e_run_block "$1" "$2"
  E2E_REPO="$top"
}

_flow_test_begin "/flow:start goal check: run in a subdirectory, an achieved goal at the top is terminal (B13)"
e2e_new start-goal-terminal-subdir
e2e_describe "an achieved issue-7 goal committed at the top; /flow:start 7's goal check at the top, then in packages/app"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
e2e_goal issue-7 feature/issue-7-x achieved true
_commit_goals
e2e_run_fence "$E2E_ACTIVE_PLUGIN/$START_MD" "$GOAL_CHECK_MARK" 7
e2e_expect_line "FLOW_GOAL_STATE=terminal"
e2e_expect_line "GOAL_PATH=.flow/goals/issue-7.goal.yaml"
_fence_in_app "$START_MD" "$GOAL_CHECK_MARK" 7
e2e_expect_line "FLOW_GOAL_STATE=terminal"
e2e_expect_line "GOAL_STATUS=achieved"
e2e_expect_line "GOAL_PATH=$TOP/.flow/goals/issue-7.goal.yaml"
e2e_expect_no_line "FLOW_GOAL_STATE=create"
e2e_expect_equal no "$(_exists packages/app/.flow)" "a .flow in packages/app"
e2e_expect_clean_edges

_flow_test_begin "/flow:start goal check: run in a subdirectory, an active goal at the top is resumed (B14)"
e2e_new start-goal-exists-subdir
e2e_describe "an active issue-7 goal committed at the top; /flow:start 7's goal check in packages/app"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
e2e_goal issue-7 feature/issue-7-x active true
_commit_goals
_fence_in_app "$START_MD" "$GOAL_CHECK_MARK" 7
e2e_expect_line "FLOW_GOAL_STATE=exists"
e2e_expect_line "GOAL_STATUS=active"
e2e_expect_line "GOAL_PATH=$TOP/.flow/goals/issue-7.goal.yaml"
e2e_expect_no_line "FLOW_GOAL_STATE=create"
e2e_expect_clean_edges

_flow_test_begin "goal record: --create refuses to replace an achieved, failed or cancelled goal, at the top or in a subdirectory (B15)"
e2e_new goal-create-over-terminal
e2e_describe "for each terminal status, a goal issue-7 in it committed at the top; flow-goal-record.sh --create of an active issue-7 in packages/app, then at the top. Each is refused with the status named, and the goal at the top keeps its status and its bytes"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
_goal_input issue-7
for B15_STATUS in achieved failed cancelled; do
  rm -rf "$E2E_REPO/.flow"
  e2e_goal issue-7 feature/issue-7-x "$B15_STATUS" true
  _commit_goals
  B15_BEFORE=$(cat "$E2E_REPO/.flow/goals/issue-7.goal.yaml")
  _in_app bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/issue-7.input.yaml"
  e2e_expect_equal 1 "$E2E_RC" "the create's exit status in packages/app over a $B15_STATUS goal"
  e2e_expect_err "refusing to overwrite — $TOP/.flow/goals/issue-7.goal.yaml exists with terminal status '$B15_STATUS'"
  e2e_expect_equal "$B15_STATUS" "$(_top_status issue-7)" "the top goal's lifecycle.status after the create in packages/app"
  e2e_expect_equal no "$(_exists packages/app/.flow)" "a .flow in packages/app"
  e2e_run_bin bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/issue-7.input.yaml"
  e2e_expect_equal 1 "$E2E_RC" "the create's exit status at the top over a $B15_STATUS goal"
  e2e_expect_err "refusing to overwrite — .flow/goals/issue-7.goal.yaml exists with terminal status '$B15_STATUS'"
  e2e_expect_equal "$B15_BEFORE" "$(cat "$E2E_REPO/.flow/goals/issue-7.goal.yaml")" "the $B15_STATUS goal's bytes"
done
e2e_expect_clean_edges

_flow_test_begin "/flow:goal status: run in a subdirectory, the scan reads the top's goals (B16)"
e2e_new goal-scan-subdir
e2e_describe "an active issue-7 goal committed at the top; the GOAL_SCAN_BLOCK of commands/goal.md in packages/app"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
e2e_goal issue-7 feature/issue-7-x active true
_commit_goals
_block_in_app commands/goal.md GOAL_SCAN_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_line "ACTIVE_GOAL=$TOP/.flow/goals/issue-7.goal.yaml"
e2e_expect_no_line "STATE=none"
e2e_expect_clean_edges

_flow_test_begin "/flow:learn: run in a subdirectory, the goal files listed are the top's (B17)"
e2e_new learn-goals-subdir
e2e_describe "an achieved issue-7 goal committed at the top; /flow:learn's block in packages/app"
_stop_repo warn
TOP=$(cd "$E2E_REPO" && pwd -P)
e2e_goal issue-7 feature/issue-7-x achieved true
_commit_goals
_fence_in_app commands/learn.md 'GOAL_FILE_COUNT='
e2e_expect_line "GOAL_FILE_COUNT=1"
e2e_expect_line "GOAL_FILE=$TOP/.flow/goals/issue-7.goal.yaml"
e2e_expect_clean_edges
