# shellcheck shell=bash
# End-to-end: the Stop hook in evaluator-loop mode gives up on a goal that
# makes no progress, stops at the goal's turn budget, acts only on the goal
# that owns the current branch, and never writes through a planted symlink.
#
# Each scenario runs the hook Claude Code registers for Stop
# (hooks/scripts/flow-goal-stop.sh), which delegates to flow-goal-evaluator.sh,
# several times in a row in one scratch repository. The goals are created with
# bin/flow-goal-record.sh --create, the way /flow:start creates them, so the
# per-user trust record that lets their verification commands run is real.
# The artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
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
#   E7 the throttle (3 continuations in 5 minutes) fires before stuck
#      detection on the stop sequence Claude Code actually sends, where every
#      stop after a block carries stop_hook_active=true, so the goal is never
#      failed
#   E8 continuations are not counted, so continuation.max_iterations never
#      ends the loop; or the budget runs out and the goal is reported failed
#      without being written
#   E13 turns that approve (every check passes, the goal is waiting for
#      /flow:goal evaluate) spend the budget, so a goal that has met its
#      criteria is failed once it has sat through max_iterations stops
#   E9 a goal without scope.run_id is never failed as stuck
#   E10 a planted symlink at the stuck counter or at events.jsonl is written
#      through, overwriting the file it points to
#   E11 a deterministic-checks run that crashes reads as "all checks pass" and
#      records an achieved verdict
#   E12 a diagnostic the evaluator prints lands in stdout ahead of the JSON
#      decision, so Claude Code reads the turn's output as plain text and
#      ignores the decision

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
FIRST='{"session_id":"e2e-session","stop_hook_active":false}'
AGAIN='{"session_id":"e2e-session","stop_hook_active":true}'
GOAL_FILE=".flow/goals/g-stuck.goal.yaml"

# _create_goal <id> <branch> [run_id] [max_iterations] [command] — a goal whose
# one must_pass criterion runs <command> (default `false`, which always fails),
# recorded through the shipped create path.
_create_goal() {
  local src="$E2E_DIR/$1.src.yaml"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$src" "$1" "$2" "${3:-}" "${4:-}" "${5:-false}" <<'PY' ||
import sys, yaml
src, dst, gid, branch, run_id, max_iter, cmd = sys.argv[1:8]
with open(src, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = gid
g["scope"]["branch"] = branch
if run_id:
    g["scope"]["run_id"] = run_id
if max_iter:
    g["continuation"]["max_iterations"] = int(max_iter)
g["objective"]["acceptance_criteria"][0]["verification_command"] = cmd
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  { _flow_assert_fail "$E2E_NAME: could not write goal source $1"; return 0; }
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$src" >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create $1 failed: $(cat "$E2E_DIR/create.err")"
  fi
}

# _loop_repo <settings json> — the scratch repo with evaluator-loop enabled and
# any further goal settings merged in.
_loop_repo() {
  e2e_repo feature/e2e
  mkdir -p "$E2E_REPO/.claude"
  local extra="${1:-}"
  [ -n "$extra" ] || extra='{}'
  jq -nc --argjson extra "$extra" '{flow:{goals:({stopHookEnforcement:"evaluator-loop"} + $extra)}}' \
    > "$E2E_REPO/.claude/settings.flow.json"
}

# Each turn also checks that stdout is one JSON object: Claude Code reads the
# decision only when stdout starts with `{`, so a diagnostic printed ahead of
# it turns the decision into ignored plain text.
_turn() {
  printf '\n=== turn %s\n' "$1" >> "$E2E_ARTIFACT"
  e2e_run_hook "$STOP_HOOK" "$2"
  if jq -e 'type == "object" and has("decision")' <<<"$E2E_OUT" >/dev/null 2>&1; then
    _e2e_result pass "turn $1 stdout is one JSON decision"
  else
    _e2e_result fail "turn $1 stdout is one JSON decision"
  fi
}

_flow_test_begin "evaluator loop: a goal stuck on a failing check is failed on turn 3 (E1-E7, E12)"
e2e_new goal-stuck
e2e_describe "g-stuck owns this branch and its must_pass check always fails; g-other is active on feature/other and fails too; stops after the first carry stop_hook_active=true"
_loop_repo
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
_create_goal g-stuck feature/e2e run-e2e
_create_goal g-other feature/other
_turn 1 "$FIRST"
e2e_expect_out '"decision":"block"'
e2e_expect_out 'Goal: g-stuck'
e2e_expect_file_has "$GOAL_FILE" "status: active"
_turn 2 "$AGAIN"
e2e_expect_out '"decision":"block"'
_turn 3 "$AGAIN"
e2e_expect_out '"decision":"approve"'
e2e_expect_out 'stuck_no_progress'
e2e_expect_no_out 'throttled'
e2e_expect_file_has "$GOAL_FILE" "status: failed"
# Turns 1 and 2 blocked; turn 3 approved on stuck detection, so two
# continuations were spent.
e2e_expect_file_has "$GOAL_FILE" "turns_evaluated: 2"
e2e_expect_file_has ".flow/runs/run-e2e/events.jsonl" '"type":"stuck-detection-fired"'
e2e_expect_file_has ".flow/runs/run-e2e/events.jsonl" '"goal_id":"g-stuck"'
_turn 4 "$FIRST"
e2e_expect_out '"decision":"approve"'
e2e_expect_out 'no active flow goal'
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: the turn budget ends the loop and fails the goal (E8)"
e2e_new goal-budget
e2e_describe "max_iterations 2 and failAfterStuckTurns 5, so the budget runs out before stuck detection would fire"
_loop_repo '{"failAfterStuckTurns":5}'
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
_create_goal g-stuck feature/e2e run-e2e 2
_turn 1 "$FIRST"
e2e_expect_out '"decision":"block"'
e2e_expect_out 'Budget remaining after this turn: 1 turns'
e2e_expect_file_has "$GOAL_FILE" "turns_evaluated: 1"
_turn 2 "$FIRST"
e2e_expect_out '"decision":"block"'
e2e_expect_out 'Budget remaining after this turn: 0 turns'
e2e_expect_file_has "$GOAL_FILE" "turns_evaluated: 2"
_turn 3 "$FIRST"
e2e_expect_out '"decision":"approve"'
e2e_expect_out 'goal budget exhausted'
e2e_expect_out 'lifecycle transitioned to failed'
e2e_expect_file_has "$GOAL_FILE" "status: failed"
e2e_expect_file_has "$GOAL_FILE" "budget_exhausted"
e2e_expect_file_has ".flow/runs/run-e2e/events.jsonl" '"type":"budget-exhausted"'
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: turns where every check passes do not spend the budget (E13)"
e2e_new goal-budget-passing
e2e_describe "max_iterations 2 and a must_pass check that passes: three stops while the goal waits for /flow:goal evaluate"
_loop_repo
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
_create_goal g-stuck feature/e2e run-e2e 2 true
_turn 1 "$FIRST"; e2e_expect_out 'all deterministic checks pass'
_turn 2 "$FIRST"; e2e_expect_out 'all deterministic checks pass'
_turn 3 "$FIRST"
e2e_expect_out 'all deterministic checks pass'
e2e_expect_no_out 'budget'
e2e_expect_file_has "$GOAL_FILE" "status: active"
e2e_expect_file_has "$GOAL_FILE" "turns_evaluated: 0"
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: a goal without a run id is still failed as stuck (E9)"
e2e_new goal-stuck-no-run
e2e_describe "g-stuck has no scope.run_id, so there is no run directory for the counter"
_loop_repo
_create_goal g-stuck feature/e2e
_turn 1 "$FIRST"; e2e_expect_out '"decision":"block"'
# The counter is per-user state: while the goal runs, nothing new sits in the
# working tree, where /flow:start would read it as an uncommitted change.
e2e_expect_equal "" "$(find "$E2E_REPO/.flow/goals" -mindepth 1 ! -name '*.goal.yaml' ! -name '*.goal.yaml.lock')" "files beside the goal other than the goal and its lock"
_turn 2 "$FIRST"; e2e_expect_out '"decision":"block"'
_turn 3 "$FIRST"
e2e_expect_out 'stuck_no_progress'
e2e_expect_file_has "$GOAL_FILE" "status: failed"
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: a symlinked stuck counter is not written through (E10)"
e2e_new goal-symlink-counter
e2e_describe "the run's stuck-counter is a symlink to a file outside the repository"
_loop_repo
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
printf 'victim\n' > "$E2E_DIR/victim"
ln -s "$E2E_DIR/victim" "$E2E_REPO/.flow/runs/run-e2e/stuck-counter"
_create_goal g-stuck feature/e2e run-e2e
_turn 1 "$FIRST"; _turn 2 "$FIRST"; _turn 3 "$FIRST"
e2e_expect_err "stuck-counter is a symlink (stuck-detection skipped this turn)"
e2e_expect_equal victim "$(cat "$E2E_DIR/victim")" "the symlink target's content"
e2e_expect_file_has "$GOAL_FILE" "status: active"
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: a symlinked events.jsonl is not appended to when stuck fires (E10)"
e2e_new goal-symlink-events
e2e_describe "the run's events.jsonl is a symlink to a file outside the repository"
_loop_repo
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
printf 'victim\n' > "$E2E_DIR/victim"
ln -s "$E2E_DIR/victim" "$E2E_REPO/.flow/runs/run-e2e/events.jsonl"
_create_goal g-stuck feature/e2e run-e2e
_turn 1 "$FIRST"; _turn 2 "$FIRST"; _turn 3 "$FIRST"
e2e_expect_out 'stuck_no_progress'
e2e_expect_err "refusing to append stuck-detection event"
e2e_expect_equal victim "$(cat "$E2E_DIR/victim")" "the symlink target's content"
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: a symlinked events.jsonl is not appended to when the throttle fires (E10)"
e2e_new goal-symlink-throttle
e2e_describe "failAfterStuckTurns 10, so the fourth consecutive stop hits the throttle; events.jsonl is a symlink"
_loop_repo '{"failAfterStuckTurns":10}'
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
printf 'victim\n' > "$E2E_DIR/victim"
ln -s "$E2E_DIR/victim" "$E2E_REPO/.flow/runs/run-e2e/events.jsonl"
_create_goal g-stuck feature/e2e run-e2e
_turn 1 "$FIRST"; _turn 2 "$AGAIN"; _turn 3 "$AGAIN"; _turn 4 "$AGAIN"
e2e_expect_out 'throttled'
e2e_expect_err "refusing to append throttle event"
e2e_expect_equal victim "$(cat "$E2E_DIR/victim")" "the symlink target's content"
e2e_expect_clean_edges

_flow_test_begin "evaluator loop: a crashed checks run is reported, not read as passing (E11)"
e2e_new goal-checks-crash
e2e_describe "the deterministic checks script exits 1 without a report"
_loop_repo
mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
e2e_plugin_copy hooks/scripts/flow-run-deterministic-checks.sh '#!/usr/bin/env bash
echo "checks: boom" >&2
exit 1'
_create_goal g-stuck feature/e2e run-e2e
_turn 1 "$FIRST"
e2e_expect_out '"decision":"approve"'
e2e_expect_out 'deterministic checks unavailable'
e2e_expect_no_out 'all deterministic checks pass'
e2e_expect_err 'checks: boom'
e2e_expect_equal no "$([ -e "$E2E_REPO/.flow/runs/run-e2e/last-verdict.json" ] && echo yes || echo no)" "a verdict file was written"
e2e_expect_file_has "$GOAL_FILE" "status: active"
e2e_expect_file_has "$GOAL_FILE" "turns_evaluated: 0"
e2e_expect_clean_edges
