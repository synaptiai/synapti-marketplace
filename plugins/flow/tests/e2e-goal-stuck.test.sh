# End-to-end: the Stop hook in evaluator-loop mode gives up on a goal that
# makes no progress, and acts only on the goal that owns the current branch.
#
# The scenario runs the hook Claude Code registers for Stop
# (hooks/scripts/flow-goal-stop.sh), which delegates to flow-goal-evaluator.sh,
# four times in a row in one scratch repository. The goals are created with
# bin/flow-goal-record.sh --create, the way /flow:start creates them, so the
# per-user trust record that lets their verification commands run is real.
# The artifact is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenario:
#   E1 a failing must_pass criterion does not keep the agent working (the hook
#      approves the stop on the first turn)
#   E2 the stuck counter never reaches the threshold (not written, not read
#      back, or reset on an unchanged turn), so the agent is kept working
#      forever
#   E3 at the threshold the stop is approved but the goal is not moved to
#      failed, so the next session picks it up again
#   E4 the stuck event is not logged to the run's events.jsonl
#   E5 once this branch's goal is failed, the evaluator picks up an active goal
#      on ANOTHER branch and blocks this session on that goal's checks
#   E6 the judge (the claude CLI) runs on the deterministic path, costing a
#      model call per turn when a failing command already decided the verdict

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
PAYLOAD='{"session_id":"e2e-session","stop_hook_active":false}'
GOAL_FILE=".flow/goals/g-stuck.goal.yaml"

# _create_goal <id> <branch> [run_id] — a goal whose one must_pass criterion
# always fails, recorded through the shipped create path.
_create_goal() {
  local src="$E2E_DIR/$1.src.yaml"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$src" "$1" "$2" "${3:-}" <<'PY'
import sys, yaml
src, dst, gid, branch, run_id = sys.argv[1:6]
with open(src, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = gid
g["scope"]["branch"] = branch
if run_id:
    g["scope"]["run_id"] = run_id
g["objective"]["acceptance_criteria"][0]["verification_command"] = "false"
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$src" >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "flow-goal-record.sh --create $1 failed: $(cat "$E2E_DIR/create.err")"
  fi
}

_flow_test_begin "evaluator loop: a goal stuck on a failing check is failed after three turns (E1-E6)"
e2e_new goal-stuck
e2e_describe "g-stuck owns this branch and its must_pass check always fails; g-other is active on feature/other and fails too"
e2e_repo feature/e2e
mkdir -p "$E2E_REPO/.claude" "$E2E_REPO/.flow/runs/run-e2e"
printf '%s\n' '{"flow":{"goals":{"stopHookEnforcement":"evaluator-loop"}}}' > "$E2E_REPO/.claude/settings.flow.json"
_create_goal g-stuck feature/e2e run-e2e
_create_goal g-other feature/other

printf '\n=== turn 1\n' >> "$E2E_ARTIFACT"
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"block"'
e2e_expect_out 'Goal: g-stuck'
e2e_expect_file_has "$GOAL_FILE" "status: active"

printf '\n=== turn 2\n' >> "$E2E_ARTIFACT"
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"block"'

printf '\n=== turn 3\n' >> "$E2E_ARTIFACT"
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"approve"'
e2e_expect_out 'stuck_no_progress'
e2e_expect_file_has "$GOAL_FILE" "status: failed"
e2e_expect_file_has ".flow/runs/run-e2e/events.jsonl" '"type":"stuck-detection-fired"'
e2e_expect_file_has ".flow/runs/run-e2e/events.jsonl" '"goal_id":"g-stuck"'

printf '\n=== turn 4\n' >> "$E2E_ARTIFACT"
e2e_run_hook "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"approve"'
e2e_expect_out 'no active flow goal'
e2e_expect_clean_edges
