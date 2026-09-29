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
#   E14 a stuck count survives a turn whose checks pass, so a goal that
#      recovered and failed again is failed early
#   E16 the same, on a goal with a run and on the judge path: a turn the judge
#      calls achieved leaves the count in place
#   E15 a stuck count left by an earlier goal counts toward a new goal that
#      reuses its id (goal ids such as issue-N are reused)
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
#
# A turn that fails a must_pass criterion or a path boundary compares its
# failures with the previous failing turn's: the same failures are unchanged,
# a failure the previous turn did not have is regressed, fewer failures are
# made_progress. Ways that can be wrong:
#   E17 a turn that fixes one failing criterion while another still fails
#      counts as stuck, so a goal fixed one criterion per turn is failed
#   E18 any change in the failures counts as progress, so a turn that swaps
#      one failure for another resets the stuck count
#   E19 a turn that adds a failing criterion or a path violation is not
#      recorded as regressed
#   E20 the failures from before a turn whose checks passed are kept, and a
#      later failure is compared with them instead of starting over
#   E21 the failures are compared as the checks report them, so the same
#      failures in another order, or one reported twice, count as a change
#   E22 the computed delta drives the stuck count, but the run's
#      last-verdict.json still records unchanged
#   E23 the same failures turn after turn are no longer failed as stuck
#   E24 a planted symlink where the previous failures are kept is read as the
#      previous failures, or written through
#   E25 previous failures that name a criterion the goal does not have are
#      compared anyway
#   E26 when this turn's failures cannot be kept for the next turn, the turn
#      still records progress and resets the stuck count, so the next turn
#      compares with stale failures and the loop is never failed as stuck
#   E27 a turn whose checks all pass but the judge says not achieved keeps the
#      failures from before it, so the next failing turn is compared with
#      them instead of starting over, as it does after any turn whose checks
#      pass

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

# FLOW_E2E_SCENARIOS=a,b runs only the scenarios whose artifacts are named a
# and b, so a goal criterion can run its own scenarios inside the Stop
# hook's 30 s limit.
_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
FIRST='{"session_id":"e2e-session","stop_hook_active":false}'
AGAIN='{"session_id":"e2e-session","stop_hook_active":true}'
GOAL_FILE=".flow/goals/g-stuck.goal.yaml"

# _create_goal <id> <branch> [run_id] [max_iterations] [command] [created_at]
# [fuzzy] [second] — a goal whose must_pass criterion runs <command> (default
# `false`, which always fails), recorded through the shipped create path. With
# fuzzy set, a second criterion with no command is added, which only the judge
# can decide. With second set, a second must_pass criterion, AC2, runs <second>.
_create_goal() {
  local src="$E2E_DIR/$1.src.yaml"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$src" "$1" "$2" "${3:-}" "${4:-}" "${5:-false}" "${6:-}" "${7:-}" "${8:-}" <<'PY' ||
import sys, yaml
src, dst, gid, branch, run_id, max_iter, cmd, created, fuzzy, second = sys.argv[1:11]
with open(src, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = gid
g["scope"]["branch"] = branch
if run_id:
    g["scope"]["run_id"] = run_id
if max_iter:
    g["continuation"]["max_iterations"] = int(max_iter)
g["objective"]["acceptance_criteria"][0]["verification_command"] = cmd
if created:
    g["metadata"]["created_at"] = created
if fuzzy:
    g["objective"]["acceptance_criteria"].append({
        "id": "AC2", "text": "The search results read well.", "must_pass": False,
        "status": "pending", "evidence_ref": None, "last_evaluated_at": None, "last_result": None,
    })
if second:
    g["objective"]["acceptance_criteria"].append({
        "id": "AC2", "text": "Searching for a prefix returns every match.", "verification_command": second,
        "must_pass": True, "status": "pending", "evidence_ref": None, "last_evaluated_at": None, "last_result": None,
    })
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  { _flow_assert_fail "$E2E_NAME: could not write goal source $1"; return 0; }
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$src" >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create $1 failed: $(cat "$E2E_DIR/create.err")"
  fi
}

# _create_goal_pair <id> <branch> [run_id] — a goal with two must_pass
# criteria, each fixed by creating its marker file in the repository: AC1 runs
# `test -f fixed-1`, AC2 runs `test -f fixed-2`.
_create_goal_pair() { _create_goal "$1" "$2" "${3:-}" "" "test -f fixed-1" "" "" "test -f fixed-2"; }

# _edit_goal <python> — change the goal file by hand between turns; <python>
# works on the parsed goal, `g`.
_edit_goal() {
  python3 - "$E2E_REPO/$GOAL_FILE" "$1" <<'PY' || _flow_assert_fail "$E2E_NAME: could not edit the goal"
import sys, yaml
path, code = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    g = yaml.safe_load(f)
exec(code)
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
}

# The run's files the delta scenarios read.
RUN_DIR_E2E=".flow/runs/run-e2e"
# _run_file <name> — a file in the run directory, or "absent".
_run_file() { if [ -f "$E2E_REPO/$RUN_DIR_E2E/$1" ]; then cat "$E2E_REPO/$RUN_DIR_E2E/$1"; else printf 'absent'; fi; }
# _recorded_delta — the delta the last turn wrote to the run's last-verdict.json.
_recorded_delta() { jq -r '.delta' "$E2E_REPO/$RUN_DIR_E2E/last-verdict.json" 2>/dev/null || printf 'no verdict file'; }
# _state_failing — the failing set of a goal without a run, kept in per-user
# state beside its stuck counter, or "absent".
_state_failing() { cat "$E2E_HOME"/.claude/flow-state/stuck/*-g-stuck.failing 2>/dev/null || printf 'absent'; }

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

if _want goal-stuck; then
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
fi

if _want goal-budget; then
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
fi

if _want goal-budget-passing; then
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
fi

if _want goal-stuck-no-run; then
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
fi

if _want goal-symlink-counter; then
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
fi

if _want goal-symlink-events; then
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
fi

if _want goal-symlink-throttle; then
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
fi

if _want goal-checks-crash; then
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
fi

if _want goal-stuck-recovers; then
  _flow_test_begin "evaluator loop: a turn whose checks pass resets the stuck count (E14)"
  e2e_new goal-stuck-recovers
  e2e_describe "no run id; the check fails twice, passes once, then fails again"
  _loop_repo
  _create_goal g-stuck feature/e2e "" "" "test -f pass-flag"
  _turn 1 "$FIRST"; _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  : > "$E2E_REPO/pass-flag"
  _turn 3 "$FIRST"; e2e_expect_out 'all deterministic checks pass'
  rm -f "$E2E_REPO/pass-flag"
  _turn 4 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_no_out 'stuck_no_progress'
  e2e_expect_file_has "$GOAL_FILE" "status: active"
  e2e_expect_clean_edges
fi

if _want goal-stuck-reused-id; then
  _flow_test_begin "evaluator loop: a new goal that reuses an id starts with no stuck count (E15)"
  e2e_new goal-stuck-reused-id
  e2e_describe "no run id; g-stuck fails twice and is cancelled, then a new g-stuck is created"
  _loop_repo
  _create_goal g-stuck feature/e2e "" "" false "2026-09-01T00:00:00Z"
  _turn 1 "$FIRST"; _turn 2 "$FIRST"
  printf '%s\n' '{"lifecycle":{"status":"cancelled"}}' > "$E2E_DIR/cancel.yaml"
  (_e2e_git_env; cd "$E2E_REPO" && "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --update-lifecycle \
    --goal-id g-stuck --lifecycle-file "$E2E_DIR/cancel.yaml" --from-status active --merge >/dev/null 2>&1) \
    || _flow_assert_fail "$E2E_NAME: could not cancel the first goal"
  _create_goal g-stuck feature/e2e "" "" false "2026-09-02T00:00:00Z"
  _turn 3 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_no_out 'stuck_no_progress'
  e2e_expect_file_has "$GOAL_FILE" "status: active"
  e2e_expect_clean_edges
fi

if _want goal-stuck-recovers-run || _want goal-stuck-recovers-judge; then
  _flow_test_begin "evaluator loop: a passing turn resets the run's stuck counter, and so does the judge's achieved (E16)"
  e2e_new goal-stuck-recovers-run
  e2e_describe "run-e2e set; a must_pass check fails twice, passes once, fails twice more; then the same with a criterion only the judge decides"
  _loop_repo
  mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
  _create_goal g-stuck feature/e2e run-e2e "" "test -f pass-flag"
  _turn 1 "$FIRST"; _turn 2 "$FIRST"
  e2e_expect_file_has ".flow/runs/run-e2e/stuck-counter" "2"
  : > "$E2E_REPO/pass-flag"
  _turn 3 "$FIRST"; e2e_expect_out 'all deterministic checks pass'
  e2e_expect_equal no "$([ -e "$E2E_REPO/.flow/runs/run-e2e/stuck-counter" ] && echo yes || echo no)" "a stuck counter after the passing turn"
  rm -f "$E2E_REPO/pass-flag"
  _turn 4 "$FIRST"; _turn 5 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_no_out 'stuck_no_progress'
  e2e_expect_clean_edges

  e2e_new goal-stuck-recovers-judge
  e2e_describe "no run id; the must_pass check fails twice, then passes and the judge calls the fuzzy criterion achieved, then the check fails twice more"
  _loop_repo
  _create_goal g-stuck feature/e2e "" "" "test -f pass-flag" "" fuzzy
  _turn 1 "$FIRST"; _turn 2 "$FIRST"
  : > "$E2E_REPO/pass-flag"
  e2e_judge_says "$(cat "$REPO_ROOT/plugins/flow/tests/fixtures/claude-responses/verdict-achieved.json")"
  _turn 3 "$FIRST"
  e2e_expect_out 'judge verdict: achieved'
  e2e_expect_equal 1 "$(grep -c . "$E2E_DIR/judge-calls.log" 2>/dev/null || echo 0)" "judge calls"
  rm -f "$E2E_REPO/pass-flag"
  _turn 4 "$FIRST"; _turn 5 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_no_out 'stuck_no_progress'
  e2e_expect_file_has "$GOAL_FILE" "status: active"
  e2e_expect_clean_edges
fi

if _want goal-fixed-one-per-turn; then
  _flow_test_begin "evaluator loop: a goal whose failing criteria are fixed one per turn is not failed as stuck (E17)"
  e2e_new goal-fixed-one-per-turn
  e2e_describe "no run id; failAfterStuckTurns 2; AC1 and AC2 fail on turn 1, AC1 is fixed before turn 2 and AC2 before turn 3"
  _loop_repo '{"failAfterStuckTurns":2}'
  _create_goal_pair g-stuck feature/e2e
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_out 'Failing must_pass criteria: AC1, AC2\n'
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_state_failing)" "the failing set kept in per-user state after turn 1"
  e2e_expect_equal "" "$(find "$E2E_REPO/.flow/goals" -mindepth 1 ! -name '*.goal.yaml' ! -name '*.goal.yaml.lock')" "files beside the goal other than the goal and its lock"
  : > "$E2E_REPO/fixed-1"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_out 'Failing must_pass criteria: AC2\n'
  e2e_expect_no_out 'stuck_no_progress'
  e2e_expect_equal AC2 "$(_state_failing)" "the failing set kept in per-user state after turn 2"
  : > "$E2E_REPO/fixed-2"
  _turn 3 "$FIRST"
  e2e_expect_out 'all deterministic checks pass'
  e2e_expect_file_has "$GOAL_FILE" "status: active"
  e2e_expect_equal "" "$(ls "$E2E_HOME/.claude/flow-state/stuck" 2>/dev/null)" "per-user stuck state after the passing turn"
  e2e_expect_clean_edges
fi

if _want goal-same-failures; then
  _flow_test_begin "evaluator loop: a goal whose failures stay the same is still failed as stuck (E23)"
  e2e_new goal-same-failures
  e2e_describe "run-e2e set; failAfterStuckTurns 2; AC1 and AC2 fail on both turns"
  _loop_repo '{"failAfterStuckTurns":2}'
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 1 recorded (no earlier failures)"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept in the run after turn 1"
  _turn 2 "$FIRST"
  e2e_expect_out 'stuck_no_progress'
  e2e_expect_file_has "$GOAL_FILE" "status: failed"
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 2 recorded"
  e2e_expect_equal absent "$(_run_file stuck-failing)" "the failing set once the goal is failed"
  e2e_expect_clean_edges
fi

if _want goal-regressed; then
  _flow_test_begin "evaluator loop: a turn that adds a failure is recorded as regressed (E19)"
  e2e_new goal-regressed
  e2e_describe "run-e2e set; allowed_paths src/**; AC1 fails throughout, AC2 starts failing on turn 2, README.md is changed before turn 3"
  _loop_repo
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _edit_goal 'g["constraints"]["allowed_paths"] = ["src/**"]'
  : > "$E2E_REPO/fixed-2"
  _turn 1 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1\n'
  e2e_expect_equal 1 "$(_run_file stuck-counter)" "the stuck count after turn 1"
  rm -f "$E2E_REPO/fixed-2"
  _turn 2 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1, AC2\n'
  e2e_expect_equal regressed "$(_recorded_delta)" "the delta turn 2 recorded (AC2 newly failing)"
  e2e_expect_equal 0 "$(_run_file stuck-counter)" "the stuck count after the regressed turn"
  printf 'changed\n' >> "$E2E_REPO/README.md"
  _turn 3 "$FIRST"
  e2e_expect_out 'Path boundary violations: README.md'
  e2e_expect_equal regressed "$(_recorded_delta)" "the delta turn 3 recorded (a new path violation)"
  e2e_expect_equal "$(printf 'AC1\nAC2\npath:README.md')" "$(_run_file stuck-failing)" "the failing set kept after turn 3"
  e2e_expect_clean_edges
fi

if _want goal-swapped-failure; then
  _flow_test_begin "evaluator loop: a turn that swaps one failure for another is regressed, not progress (E18)"
  e2e_new goal-swapped-failure
  e2e_describe "run-e2e set; AC1 fails on turn 1; before turn 2 AC1 is fixed and AC2 breaks"
  _loop_repo
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  : > "$E2E_REPO/fixed-2"
  _turn 1 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1\n'
  : > "$E2E_REPO/fixed-1"; rm -f "$E2E_REPO/fixed-2"
  _turn 2 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC2\n'
  e2e_expect_equal regressed "$(_recorded_delta)" "the delta turn 2 recorded"
  e2e_expect_equal 0 "$(_run_file stuck-counter)" "the stuck count after turn 2"
  e2e_expect_clean_edges
fi

if _want goal-failing-after-pass; then
  _flow_test_begin "evaluator loop: a failure after a passing turn is not compared with the failures before it (E20)"
  e2e_new goal-failing-after-pass
  e2e_describe "run-e2e set; AC1 and AC2 fail on turn 1, both pass on turn 2, AC1 fails again on turn 3"
  _loop_repo
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 1"
  : > "$E2E_REPO/fixed-1"; : > "$E2E_REPO/fixed-2"
  _turn 2 "$FIRST"
  e2e_expect_out 'all deterministic checks pass'
  e2e_expect_equal absent "$(_run_file stuck-failing)" "the failing set after the passing turn"
  rm -f "$E2E_REPO/fixed-1"
  _turn 3 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1\n'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 3 recorded (nothing to compare with)"
  e2e_expect_equal 1 "$(_run_file stuck-counter)" "the stuck count after turn 3"
  e2e_expect_clean_edges
fi

if _want goal-failures-reordered; then
  _flow_test_begin "evaluator loop: the same failures reported in another order, or twice, are unchanged (E21)"
  e2e_new goal-failures-reordered
  e2e_describe "run-e2e set; failAfterStuckTurns 4; executeVerificationCommands on; AC1 and AC2 fail on every turn; before turn 2 the goal lists them in the opposite order, and before turn 3 it lists AC1 a second time"
  _loop_repo '{"failAfterStuckTurns":4,"executeVerificationCommands":true}'
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1, AC2\n'
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 1"
  _edit_goal 'g["objective"]["acceptance_criteria"].reverse()'
  _turn 2 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC2, AC1\n'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 2 recorded"
  e2e_expect_equal 2 "$(_run_file stuck-counter)" "the stuck count after turn 2"
  _edit_goal 'acs = g["objective"]["acceptance_criteria"]; acs.append(dict(next(a for a in acs if a["id"] == "AC1")))'
  _turn 3 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC2, AC1, AC1\n'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 3 recorded"
  e2e_expect_equal 3 "$(_run_file stuck-counter)" "the stuck count after turn 3"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 3"
  e2e_expect_clean_edges
fi

if _want goal-recorded-delta; then
  _flow_test_begin "evaluator loop: the run's last-verdict.json records the computed delta (E22)"
  e2e_new goal-recorded-delta
  e2e_describe "run-e2e set; AC1 and AC2 fail on turn 1; AC1 is fixed before turn 2"
  _loop_repo
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 1 recorded"
  : > "$E2E_REPO/fixed-1"
  _turn 2 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC2\n'
  e2e_expect_equal made_progress "$(_recorded_delta)" "the delta turn 2 recorded"
  e2e_expect_equal 0 "$(_run_file stuck-counter)" "the stuck count after turn 2"
  e2e_expect_equal AC2 "$(_run_file stuck-failing)" "the failing set kept after turn 2"
  e2e_expect_clean_edges
fi

if _want goal-symlink-failing; then
  _flow_test_begin "evaluator loop: a symlinked failing set is neither read nor written through (E24)"
  e2e_new goal-symlink-failing
  e2e_describe "run-e2e set; after turn 1 the run's stuck-failing is moved outside the repository and replaced by a symlink to it; AC1 is fixed before turn 2"
  _loop_repo
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  if ! mv "$E2E_REPO/$RUN_DIR_E2E/stuck-failing" "$E2E_DIR/victim" 2>/dev/null; then
    _flow_assert_fail "$E2E_NAME: turn 1 left no failing set to replace with a symlink"
  fi
  ln -s "$E2E_DIR/victim" "$E2E_REPO/$RUN_DIR_E2E/stuck-failing"
  : > "$E2E_REPO/fixed-1"
  _turn 2 "$FIRST"
  e2e_expect_err 'stuck-failing is a symlink'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 2 recorded (the symlink is not read)"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(cat "$E2E_DIR/victim" 2>/dev/null)" "the symlink target's content"
  e2e_expect_clean_edges
fi

if _want goal-failing-foreign-id; then
  _flow_test_begin "evaluator loop: earlier failures naming a criterion the goal no longer has are not compared (E25)"
  e2e_new goal-failing-foreign-id
  e2e_describe "run-e2e set; executeVerificationCommands on; AC1 and AC2 fail on turn 1; before turn 2 AC2 is renamed AC3, which fails too"
  _loop_repo '{"executeVerificationCommands":true}'
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 1"
  _edit_goal 'g["objective"]["acceptance_criteria"][1]["id"] = "AC3"'
  _turn 2 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1, AC3\n'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 2 recorded (AC2 is no longer a criterion of the goal)"
  e2e_expect_err 'not a criterion of goal g-stuck'
  e2e_expect_equal "$(printf 'AC1\nAC3')" "$(_run_file stuck-failing)" "the failing set kept after turn 2"
  e2e_expect_clean_edges
fi

if _want goal-failing-unwritable; then
  _flow_test_begin "evaluator loop: a turn whose failures cannot be kept records unchanged (E26)"
  e2e_new goal-failing-unwritable
  e2e_describe "run-e2e set; after turn 1 the run's stuck-failing is made read-only; AC1 is fixed before turn 2"
  if [ "$(id -u)" = 0 ]; then
    # root writes a mode-0444 file, so the write cannot be made to fail here.
    printf '%s\n' "SKIP: running as root; the read-only failing-set fixture needs an unprivileged user" >&2
    _flow_assert_pass "SKIPPED as root (the failing-set write cannot fail)"
  else
    _loop_repo
    mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
    _create_goal_pair g-stuck feature/e2e run-e2e
    _turn 1 "$FIRST"
    chmod 0444 "$E2E_REPO/$RUN_DIR_E2E/stuck-failing" 2>/dev/null
    : > "$E2E_REPO/fixed-1"
    _turn 2 "$FIRST"
    e2e_expect_out '"decision":"block"'
    e2e_expect_err 'failing-set write failed'
    e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 2 recorded (its failures could not be kept)"
    e2e_expect_equal 2 "$(_run_file stuck-counter)" "the stuck count after turn 2"
    e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set left by turn 1"
    chmod 0644 "$E2E_REPO/$RUN_DIR_E2E/stuck-failing" 2>/dev/null
    e2e_expect_clean_edges
  fi
fi

if _want goal-failing-after-judge-turn; then
  _flow_test_begin "evaluator loop: a turn the judge decides leaves no failures to compare with (E27)"
  e2e_new goal-failing-after-judge-turn
  e2e_describe "run-e2e set; AC1 and AC2 must pass and AC3 only the judge decides; both fail on turn 1; before turn 2 both are fixed and the judge says not achieved; before turn 3 AC2 fails again"
  _loop_repo '{"executeVerificationCommands":true}'
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _edit_goal 'g["objective"]["acceptance_criteria"].append({"id": "AC3", "text": "The search results read well.", "must_pass": False, "status": "pending", "evidence_ref": None, "last_evaluated_at": None, "last_result": None})'
  _turn 1 "$FIRST"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 1"
  : > "$E2E_REPO/fixed-1"; : > "$E2E_REPO/fixed-2"
  e2e_judge_says "$(cat "$REPO_ROOT/plugins/flow/tests/fixtures/claude-responses/verdict-not-achieved-made-progress.json")"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal 1 "$(grep -c . "$E2E_DIR/judge-calls.log" 2>/dev/null || echo 0)" "judge calls"
  e2e_expect_equal absent "$(_run_file stuck-failing)" "the failing set after the turn the judge decided"
  rm -f "$E2E_REPO/fixed-2"
  _turn 3 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC2\n'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 3 recorded (nothing kept from before the judge's turn to compare with)"
  e2e_expect_clean_edges
fi
