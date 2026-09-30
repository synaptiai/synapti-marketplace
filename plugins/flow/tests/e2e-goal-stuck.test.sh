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
#   E28 a goal with a run whose directory does not exist yet (.flow/runs is
#      not tracked, so a fresh clone or worktree has none) keeps its first
#      failures in per-user state while the stuck count goes to the run, so
#      the next turn has nothing to compare with and a goal fixed one
#      criterion per turn is failed as stuck
#   E29 a run directory that is a symlink, or lies under a symlinked .flow or
#      .flow/runs (a repository can commit one), gets the stuck count, the
#      failures, the last verdict or the run's events written into the link's
#      target
#   E30 E27 for a goal without a run: the failures kept in per-user state
#      survive a turn the judge decides
#   E31 an empty file where the failures are kept is compared as no failures,
#      so every failure looks new and the turn is recorded as regressed
#   E32 a kept path violation is taken for an id that is not a criterion, so a
#      turn that fixes a path violation is not compared and records unchanged
#   E33 a run directory reached through a symlinked .flow/runs whose target
#      already holds a directory of that name is taken for the repository's:
#      the stuck count and the failing set are written there. The scenarios
#      above link to an empty target, where the test for a symlinked
#      .flow/runs refuses before the run directory itself is checked
#   E34 the same, for the throttle event the fourth consecutive stop appends
#   E35 a goal without a run in a folder of a home kept in git, with
#      ~/.claude a symlink to elsewhere (GNU stow), cannot keep its stuck
#      state or be trusted: per-user state under ~/.claude is taken for a
#      directory the repository committed
#   E36 a refused run directory whose name holds "; " (a goal's run_id,
#      which the schema would refuse but a goal file on disk can hold) is
#      named cut at its "; "; or, where Python writes \r\n to a pipe
#      (Windows), the refusal keeps its fixed ending and a \r
#   E37 a FLOW_STATE_DIR the repository chose (a directory inside it, or one
#      its own .claude/settings.json env block names) holds a trust ledger
#      that trusts the goal the repository ships, and the Stop hook runs that
#      goal's verification command

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
# _state_counter — the stuck count of a goal without a run, kept in per-user
# state, or "absent".
_state_counter() { cat "$E2E_HOME"/.claude/flow-state/stuck/*-g-stuck 2>/dev/null || printf 'absent'; }
# _state_files — the names in the per-user stuck state directory.
_state_files() { (cd "$E2E_HOME/.claude/flow-state/stuck" 2>/dev/null && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' '); }
# _outside_files — what is under $E2E_DIR/outside, the target of a planted
# symlink, other than a goal moved there with its lock: directories too, so a
# run directory created through the link shows.
_outside_files() {
  (cd "$E2E_DIR/outside" 2>/dev/null && find . -mindepth 1 ! -path ./flow ! -path './flow/goals' ! -path './flow/goals/*' | LC_ALL=C sort | tr '\n' ' ')
}
# _plant_symlink run-dir|runs|flow — after the goal is created, replace one
# directory on the path to the run with a symlink to $E2E_DIR/outside: the run
# directory itself, .flow/runs, or .flow (whose goals move to the target).
_plant_symlink() {
  mkdir -p "$E2E_DIR/outside"
  case "$1" in
    run-dir) mkdir -p "$E2E_REPO/.flow/runs" && ln -s "$E2E_DIR/outside" "$E2E_REPO/$RUN_DIR_E2E" ;;
    runs) ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow/runs" ;;
    flow) mv "$E2E_REPO/.flow" "$E2E_DIR/outside/flow" && ln -s "$E2E_DIR/outside/flow" "$E2E_REPO/.flow" ;;
  esac || _flow_assert_fail "$E2E_NAME: could not plant the $1 symlink"
}

# _plant_runs_holding_run — .flow/runs becomes a symlink to $E2E_DIR/outside,
# which already holds a directory named like the goal's run, run-e2e.
_plant_runs_holding_run() {
  mkdir -p "$E2E_DIR/outside/run-e2e" "$E2E_REPO/.flow" &&
    ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow/runs" ||
    _flow_assert_fail "$E2E_NAME: could not plant the .flow/runs symlink"
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
  _flow_test_begin "evaluator loop: a turn that adds a failure is recorded as regressed, and one that fixes a path violation as progress (E19, E32)"
  e2e_new goal-regressed
  e2e_describe "run-e2e set; allowed_paths src/**; AC1 fails throughout, AC2 starts failing on turn 2, README.md is changed before turn 3 and restored before turn 4"
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
  (_e2e_git_env; cd "$E2E_REPO" && git checkout -q -- README.md) || _flow_assert_fail "$E2E_NAME: could not restore README.md"
  _turn 4 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC1, AC2\n'
  e2e_expect_no_out 'Path boundary violations'
  e2e_expect_equal made_progress "$(_recorded_delta)" "the delta turn 4 recorded (the path violation fixed)"
  e2e_expect_equal 0 "$(_run_file stuck-counter)" "the stuck count after turn 4"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 4"
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

if _want goal-failing-after-judge-turn-no-run; then
  _flow_test_begin "evaluator loop: a turn the judge decides leaves no failures to compare with, for a goal without a run (E30)"
  e2e_new goal-failing-after-judge-turn-no-run
  e2e_describe "no run id; AC1 and AC2 must pass and AC3 only the judge decides; both fail on turn 1; before turn 2 both are fixed and the judge says not achieved; before turn 3 AC2 fails again"
  _loop_repo '{"executeVerificationCommands":true}'
  _create_goal_pair g-stuck feature/e2e
  _edit_goal 'g["objective"]["acceptance_criteria"].append({"id": "AC3", "text": "The search results read well.", "must_pass": False, "status": "pending", "evidence_ref": None, "last_evaluated_at": None, "last_result": None})'
  _turn 1 "$FIRST"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_state_failing)" "the failing set kept in per-user state after turn 1"
  : > "$E2E_REPO/fixed-1"; : > "$E2E_REPO/fixed-2"
  e2e_judge_says "$(cat "$REPO_ROOT/plugins/flow/tests/fixtures/claude-responses/verdict-not-achieved-made-progress.json")"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal 1 "$(grep -c . "$E2E_DIR/judge-calls.log" 2>/dev/null || echo 0)" "judge calls"
  e2e_expect_equal absent "$(_state_failing)" "the failing set in per-user state after the turn the judge decided"
  e2e_expect_equal 0 "$(_state_counter)" "the per-user stuck count after the judge's made_progress"
  rm -f "$E2E_REPO/fixed-2"
  _turn 3 "$FIRST"
  e2e_expect_out 'Failing must_pass criteria: AC2\n'
  e2e_expect_equal 1 "$(_state_counter)" "the per-user stuck count after turn 3 (nothing kept from before the judge's turn to compare with)"
  e2e_expect_equal AC2 "$(_state_failing)" "the failing set kept in per-user state after turn 3"
  e2e_expect_clean_edges
fi

if _want goal-failing-empty; then
  _flow_test_begin "evaluator loop: an empty file where the failures are kept is not compared (E31)"
  e2e_new goal-failing-empty
  e2e_describe "run-e2e set; after turn 1 the run's stuck-failing is emptied; AC1 is fixed before turn 2"
  _loop_repo
  mkdir -p "$E2E_REPO/$RUN_DIR_E2E"
  _create_goal_pair g-stuck feature/e2e run-e2e
  _turn 1 "$FIRST"
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept after turn 1"
  : > "$E2E_REPO/$RUN_DIR_E2E/stuck-failing"
  : > "$E2E_REPO/fixed-1"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_err 'stuck-failing is unreadable or empty'
  e2e_expect_equal unchanged "$(_recorded_delta)" "the delta turn 2 recorded (the empty file is not compared)"
  e2e_expect_equal 2 "$(_run_file stuck-counter)" "the stuck count after turn 2"
  e2e_expect_equal AC2 "$(_run_file stuck-failing)" "the failing set kept after turn 2"
  e2e_expect_clean_edges
fi

if _want goal-run-dir-created; then
  _flow_test_begin "evaluator loop: a goal whose run directory does not exist yet keeps all its stuck state in the run (E28)"
  e2e_new goal-run-dir-created
  e2e_describe "run-e2e set and its directory not created, as in a fresh clone; failAfterStuckTurns 2; AC1 and AC2 fail on turn 1, AC1 is fixed before turn 2"
  _loop_repo '{"failAfterStuckTurns":2}'
  _create_goal_pair g-stuck feature/e2e run-e2e
  e2e_expect_equal absent "$([ -e "$E2E_REPO/$RUN_DIR_E2E" ] && echo present || echo absent)" "the run directory before turn 1"
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_run_file stuck-failing)" "the failing set kept in the run after turn 1"
  e2e_expect_equal 1 "$(_run_file stuck-counter)" "the stuck count after turn 1"
  e2e_expect_equal "" "$(_state_files)" "per-user stuck state after turn 1"
  : > "$E2E_REPO/fixed-1"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_out 'Failing must_pass criteria: AC2\n'
  e2e_expect_no_out 'stuck_no_progress'
  e2e_expect_file_has "$GOAL_FILE" "status: active"
  e2e_expect_equal made_progress "$(_recorded_delta)" "the delta turn 2 recorded"
  e2e_expect_equal 0 "$(_run_file stuck-counter)" "the stuck count after turn 2"
  e2e_expect_equal AC2 "$(_run_file stuck-failing)" "the failing set kept in the run after turn 2"
  e2e_expect_equal "" "$(_state_files)" "per-user stuck state after turn 2"
  e2e_expect_clean_edges
fi

if _want goal-symlink-run-dir; then
  _flow_test_begin "evaluator loop: a run directory that is a symlink is not written through, and the goal is still failed as stuck (E29)"
  e2e_new goal-symlink-run-dir
  e2e_describe "run-e2e set; .flow/runs/run-e2e is a symlink to an empty directory outside the repository; failAfterStuckTurns 2; AC1 and AC2 fail on both turns"
  _loop_repo '{"failAfterStuckTurns":2}'
  _create_goal_pair g-stuck feature/e2e run-e2e
  _plant_symlink run-dir
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_err 'refusing run directory .flow/runs/run-e2e'
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_state_failing)" "the failing set kept in per-user state after turn 1"
  e2e_expect_equal 1 "$(_state_counter)" "the per-user stuck count after turn 1"
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds after turn 1"
  _turn 2 "$FIRST"
  e2e_expect_out 'stuck_no_progress'
  e2e_expect_file_has "$GOAL_FILE" "status: failed"
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds after the stuck turn"
  e2e_expect_equal "" "$(_state_files)" "per-user stuck state once the goal is failed"
  e2e_expect_clean_edges
fi

if _want goal-symlink-run-dir-throttle; then
  _flow_test_begin "evaluator loop: a run directory that is a symlink gets no throttle event (E29)"
  e2e_new goal-symlink-run-dir-throttle
  e2e_describe "run-e2e set; .flow/runs/run-e2e is a symlink to an empty directory outside the repository; failAfterStuckTurns 10, so the fourth consecutive stop hits the throttle"
  _loop_repo '{"failAfterStuckTurns":10}'
  _create_goal g-stuck feature/e2e run-e2e
  _plant_symlink run-dir
  _turn 1 "$FIRST"; _turn 2 "$AGAIN"; _turn 3 "$AGAIN"; _turn 4 "$AGAIN"
  e2e_expect_out 'throttled'
  e2e_expect_err 'refusing to append throttle event — .flow/runs/run-e2e'
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds"
  e2e_expect_clean_edges
fi

if _want goal-symlink-runs; then
  _flow_test_begin "evaluator loop: a symlinked .flow/runs is not written through (E29)"
  e2e_new goal-symlink-runs
  e2e_describe "run-e2e set; .flow/runs is a symlink to an empty directory outside the repository; AC1 and AC2 fail on both turns"
  _loop_repo
  _create_goal_pair g-stuck feature/e2e run-e2e
  _plant_symlink runs
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_err 'refusing run directory .flow/runs/run-e2e'
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_state_failing)" "the failing set kept in per-user state after turn 1"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal 2 "$(_state_counter)" "the per-user stuck count after turn 2"
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds"
  e2e_expect_clean_edges
fi

if _want goal-symlink-flow; then
  _flow_test_begin "evaluator loop: a goal under a symlinked .flow is not read, so the stop is approved and nothing is kept for it (E29)"
  e2e_new goal-symlink-flow
  e2e_describe "run-e2e set; .flow is moved outside the repository and replaced by a symlink to it; AC1 and AC2 fail on both turns"
  _loop_repo
  _create_goal_pair g-stuck feature/e2e run-e2e
  _plant_symlink flow
  # The hook used to read the goal through the link, block on both turns and
  # keep the goal's stuck state per user, since the run directory under the
  # link was refused. A goal read through a symlinked .flow belongs to the
  # link's target, not to this repository, so the hook no longer reads one: it
  # approves as if no goal were active, keeps nothing for it, and says why on
  # stderr. Nothing is written under the link either way.
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_err 'refusing — .flow is a symlink; goals are not read through it'
  e2e_expect_equal absent "$(_state_failing)" "the failing set kept in per-user state after turn 1"
  _turn 2 "$FIRST"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_equal absent "$(_state_counter)" "the per-user stuck count after turn 2"
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds besides the goal"
  e2e_expect_clean_edges
fi

if _want goal-symlink-runs-holding-run; then
  _flow_test_begin "evaluator loop: a run directory under a symlinked .flow/runs whose target holds it is not written through (E33)"
  e2e_new goal-symlink-runs-holding-run
  e2e_describe "run-e2e set; .flow/runs is a symlink to a directory outside the repository that already holds run-e2e/; AC1 and AC2 fail"
  _loop_repo
  _create_goal_pair g-stuck feature/e2e run-e2e
  _plant_runs_holding_run
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_err 'refusing run directory .flow/runs/run-e2e'
  e2e_expect_equal "$(printf 'AC1\nAC2')" "$(_state_failing)" "the failing set kept in per-user state after turn 1"
  e2e_expect_equal "./run-e2e " "$(_outside_files)" "what the symlink's target holds after turn 1"
  e2e_expect_clean_edges
fi

if _want goal-symlink-runs-holding-run-throttle; then
  _flow_test_begin "evaluator loop: a run directory under a symlinked .flow/runs whose target holds it gets no throttle event (E34)"
  e2e_new goal-symlink-runs-holding-run-throttle
  e2e_describe "run-e2e set; .flow/runs is a symlink to a directory outside the repository that already holds run-e2e/; failAfterStuckTurns 10, so the fourth consecutive stop hits the throttle"
  _loop_repo '{"failAfterStuckTurns":10}'
  _create_goal g-stuck feature/e2e run-e2e
  _plant_runs_holding_run
  _turn 1 "$FIRST"; _turn 2 "$AGAIN"; _turn 3 "$AGAIN"; _turn 4 "$AGAIN"
  e2e_expect_out 'throttled'
  e2e_expect_err 'refusing to append throttle event — .flow/runs/run-e2e'
  e2e_expect_equal "./run-e2e " "$(_outside_files)" "what the symlink's target holds"
  e2e_expect_clean_edges
fi

# _stow_loop_home — the scenario's HOME is a git repository on branch
# feature/e2e and $HOME/.claude a symlink to $E2E_DIR/dotfiles/claude, as GNU
# stow makes it; E2E_REPO is $HOME/proj, not a repository of its own, with
# evaluator-loop enabled.
_stow_loop_home() {
  mkdir -p "$E2E_DIR/dotfiles/claude" "$E2E_HOME/proj/.claude" &&
    ln -s "$E2E_DIR/dotfiles/claude" "$E2E_HOME/.claude" &&
    (
      _e2e_git_env
      cd "$E2E_HOME" &&
        git init -q &&
        git config user.email e2e@example.invalid &&
        git config user.name e2e &&
        git config commit.gpgsign false &&
        git commit -q --allow-empty -m init &&
        git checkout -q -b feature/e2e
    ) || _flow_assert_fail "$E2E_NAME: could not make HOME a repository with a stowed .claude"
  E2E_REPO="$E2E_HOME/proj"
  printf '%s\n' '{"flow":{"goals":{"stopHookEnforcement":"evaluator-loop"}}}' > "$E2E_REPO/.claude/settings.flow.json"
}

if _want goal-stuck-stow-home; then
  _flow_test_begin "evaluator loop: a goal without a run keeps its stuck state and trust under a stowed ~/.claude (E35)"
  e2e_new goal-stuck-stow-home
  e2e_describe "HOME is a git repository and ~/.claude a symlink to a directory elsewhere; the goal, without a run, is created from HOME/proj and its must_pass check always fails; one stop"
  _stow_loop_home
  _create_goal g-stuck feature/e2e
  e2e_expect_equal yes "$(grep -q '"goal_id": "g-stuck"' "$E2E_DIR/dotfiles/claude/flow-state/goal-trust.jsonl" 2>/dev/null && echo yes || echo no)" "the trust ledger in the stowed directory records the goal"
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal 1 "$(_state_counter)" "the per-user stuck count after turn 1"
  e2e_expect_clean_edges
fi

# --- a refused run directory named whole (E36) --------------------------------

# _goal_semicolon_run — goal g-stuck with run_id 'x; y', recorded through the
# shipped create path with jsonschema hidden (the schema refuses the name; a
# goal file on disk can hold it); .flow/runs/x; y is a symlink to an empty
# directory outside the repository.
_goal_semicolon_run() {
  _loop_repo '{"failAfterStuckTurns":2}'
  mkdir -p "$E2E_DIR/nojs/jsonschema"
  printf 'raise ImportError("jsonschema is hidden for this scenario")\n' > "$E2E_DIR/nojs/jsonschema/__init__.py"
  printf 'jsonschema: hidden while the goal is created\n' >> "$E2E_ARTIFACT"
  local saved="${PYTHONPATH:-}"
  export PYTHONPATH="$E2E_DIR/nojs${saved:+:$saved}"
  _create_goal g-stuck feature/e2e "x; y"
  export PYTHONPATH="$saved"
  mkdir -p "$E2E_DIR/outside" "$E2E_REPO/.flow/runs"
  ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow/runs/x; y" || _flow_assert_fail "$E2E_NAME: could not plant the run directory"
}

if _want goal-semicolon-run-dir; then
  _flow_test_begin "evaluator loop: a refused run directory whose name holds '; ' is named whole (E36)"
  e2e_new goal-semicolon-run-dir
  e2e_describe "g-stuck's run_id is 'x; y'; .flow/runs/x; y is a symlink to an empty directory outside the repository; AC1 fails"
  _goal_semicolon_run
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_err "refusing run directory .flow/runs/x; y — .flow/runs/x; y is a symlink; the goal's state is kept in per-user state"
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds"
  e2e_expect_clean_edges
fi

if _want goal-symlink-run-dir-crlf; then
  _flow_test_begin "evaluator loop: a refusal whose line ends in \\r is still named without its ending (E36)"
  e2e_new goal-symlink-run-dir-crlf
  e2e_describe "run-e2e set; .flow/runs/run-e2e is a symlink to an empty directory outside the repository; python3 ends its stderr lines in CR LF, its stdout lines not; AC1 and AC2 fail"
  # Only stderr ends in CR LF here. With stdout too, the evaluator reads the
  # goal's turn budget as N\r at its budget read and allows the stop before it
  # reaches the run directory check: a Windows gap that predates this branch,
  # listed in docs/windows-support.md, and not this scenario's subject.
  _loop_repo '{"failAfterStuckTurns":2}'
  _create_goal_pair g-stuck feature/e2e run-e2e
  _plant_symlink run-dir
  _real_python3=$(command -v python3)
  _cr=$(printf '\r')
  cat > "$E2E_BIN/python3" <<SHIM
#!/bin/bash
{ "$_real_python3" "\$@" 2>&1 1>&3 3>&- | sed 's/\$/$_cr/' >&2; exit "\${PIPESTATUS[0]}"; } 3>&1
SHIM
  chmod +x "$E2E_BIN/python3"
  printf 'python3: the real one, its stderr lines ending in CR LF\n' >> "$E2E_ARTIFACT"
  _turn 1 "$FIRST"
  e2e_expect_out '"decision":"block"'
  e2e_expect_err "refusing run directory .flow/runs/run-e2e — .flow/runs/run-e2e is a symlink; the goal's state is kept in per-user state"
  e2e_expect_equal "" "$(_outside_files)" "what the symlink's target holds"
fi

# --- every read of the goal during a stop, with a FIFO in its place (L72) ---

source "$REPO_ROOT/plugins/flow/tests/lib/fifo-trap.sh" || return 0

if _want goal-fifo-reads; then
  _flow_test_begin "evaluator loop: each open of the goal during a stop meets a FIFO in its place in turn, and none waits on it, for a goal with a run, a goal without one, and a stop the throttle ends (L72)"
  e2e_new goal-fifo-reads
  e2e_describe "g-stuck owns this branch and its must_pass check always fails. Three stops: g-stuck with a run; g-stuck without one, which keeps its stuck count in per-user state; and a stop after three continuations in a row, which the throttle ends. Each is run once to count the opens of the goal file across every python3 it starts; then, for each of those opens, the repository, the per-user state and the throttle's count are put back as they were, and the stop is run again with a FIFO nothing writes to put in place of the goal just before that open. Every python3 is ended after 8 seconds if it waits, and says where (tests/lib/fifo-trap.sh)"
  _loop_repo
  fifo_trap_site "$E2E_DIR/site-fifo-trap"
  printf 'python3 start-up: fifo-trap\n' >> "$E2E_ARTIFACT"
  _saved_pp="${PYTHONPATH:-}"
  mkdir -p "$E2E_HOME/.claude/flow-state"
  # _before_stop <pass>: the throttle's count for the throttled pass, as three
  # continuations in a row, the last just now.
  _before_stop() {
    if [ "$1" = throttled ]; then
      mkdir -p "$E2E_HOME/.claude/flow-goal-throttle"
      printf '3:%s' "$(date +%s)" > "$E2E_HOME/.claude/flow-goal-throttle/e2e-session"
    fi
  }
  # _fifo_stops <pass> <payload> <fewest opens>: the stop run once to count
  # the opens of the goal, then once per open with the FIFO before it.
  _fifo_stops() {
    local pass="$1" payload="$2" fewest="$3" n k site
    cp -R "$E2E_REPO/.flow" "$E2E_DIR/flow.pristine-$pass"
    cp -R "$E2E_HOME/.claude/flow-state" "$E2E_DIR/state.pristine-$pass"
    export PYTHONPATH="$E2E_DIR/site-fifo-trap${_saved_pp:+:$_saved_pp}" SPY_WATCHDOG=8 \
      SPY_FIFO_PATH="$E2E_REPO/.flow/goals/g-stuck.goal.yaml"
    export SPY_FIFO_AT=0 SPY_FIFO_LOG="$E2E_DIR/opens-$pass-count.log" SPY_HUNG_LOG="$E2E_DIR/hung-$pass-count.log"
    _before_stop "$pass"
    _turn "$pass count" "$payload"
    [ "$pass" = throttled ] && e2e_expect_out 'throttled'
    n=$(wc -l < "$E2E_DIR/opens-$pass-count.log" 2>/dev/null | tr -d ' ')
    printf 'the opens of the goal in one stop, %s:\n%s\n' "$pass" "$(cat "$E2E_DIR/opens-$pass-count.log" 2>/dev/null)" >> "$E2E_ARTIFACT"
    e2e_expect_equal yes "$([ "${n:-0}" -ge "$fewest" ] && echo yes || echo no)" "$pass: a stop opens the goal at least $fewest times"
    k=1
    while [ "$k" -le "${n:-0}" ]; do
      mv "$E2E_REPO/.flow" "$E2E_DIR/flow-used-$pass-$k"
      cp -R "$E2E_DIR/flow.pristine-$pass" "$E2E_REPO/.flow"
      mv "$E2E_HOME/.claude/flow-state" "$E2E_DIR/state-used-$pass-$k"
      cp -R "$E2E_DIR/state.pristine-$pass" "$E2E_HOME/.claude/flow-state"
      site=$(sed -n "${k}p" "$E2E_DIR/opens-$pass-count.log")
      export SPY_FIFO_AT=$k SPY_FIFO_LOG="$E2E_DIR/opens-$pass-$k.log" SPY_HUNG_LOG="$E2E_DIR/hung-$pass-$k.log"
      _before_stop "$pass"
      _turn "$pass $k" "$payload"
      e2e_expect_equal "" "$(cat "$E2E_DIR/hung-$pass-$k.log" 2>/dev/null)" "$pass, open $site: no python3 waited"
      k=$((k + 1))
    done
    export PYTHONPATH="$_saved_pp"
    unset SPY_WATCHDOG SPY_FIFO_PATH SPY_FIFO_AT SPY_FIFO_LOG SPY_HUNG_LOG
    mv "$E2E_REPO/.flow" "$E2E_DIR/flow-done-$pass"
  }
  mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
  _create_goal g-stuck feature/e2e run-e2e
  _fifo_stops with-run "$FIRST" 5
  _create_goal g-stuck feature/e2e
  _fifo_stops without-run "$FIRST" 5
  mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
  _create_goal g-stuck feature/e2e run-e2e
  _fifo_stops throttled "$AGAIN" 2
fi

# _shipped_goal: a goal the repository ships, g-shipped, whose must_pass
# check creates ran-check in the repository, and a trust ledger trusting it,
# written to $E2E_DIR/ledger as the repository's author would have prepared it
# (recorded from this checkout, so it names this repository).
_shipped_goal() {
  _loop_repo
  e2e_goal g-shipped feature/e2e active "touch ran-check"
  mkdir -p "$E2E_DIR/ledger"
  if ! (_e2e_git_env; cd "$E2E_REPO" && FLOW_STATE_DIR="$E2E_DIR/ledger" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-trust.sh" record --goal-file .flow/goals/g-shipped.goal.yaml >/dev/null 2>&1); then
    _flow_assert_fail "$E2E_NAME: could not prepare the trust ledger"
  fi
  printf 'trust ledger prepared outside the repository, trusting g-shipped\n' >> "$E2E_ARTIFACT"
}

# _check_ran — whether the shipped goal's verification command ran.
_check_ran() { if [ -e "$E2E_REPO/ran-check" ]; then printf 'ran'; else printf 'did not run'; fi; }

# _refused_state <what>: after one Stop run, the shipped goal is still the
# active goal (so the run judged it), its check did not run, and stderr names
# FLOW_STATE_DIR, why, and nothing from the ledger.
_refused_state() {
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal "did not run" "$(_check_ran)" "the shipped goal's check, $1"
  e2e_expect_err "ignoring FLOW_STATE_DIR: $2"
  e2e_expect_err_lacks '"goal_id"'
}

if _want state-dir-from-repo; then
  _flow_test_begin "Stop hook: a FLOW_STATE_DIR inside the repository does not make the goal it ships trusted, and says so (E37)"
  e2e_new state-dir-from-repo
  e2e_describe "the repository ships g-shipped, whose check creates ran-check, and a trust ledger trusting it, copied into the repository; one Stop with FLOW_STATE_DIR at that copy: the check does not run, and stderr names FLOW_STATE_DIR and why, and not the ledger's contents"
  _shipped_goal
  mkdir -p "$E2E_REPO/.flow-state"
  cp "$E2E_DIR/ledger/goal-trust.jsonl" "$E2E_REPO/.flow-state/goal-trust.jsonl"
  e2e_run_hook "FLOW_STATE_DIR=$E2E_REPO/.flow-state" "$STOP_HOOK" "$FIRST"
  _refused_state "with the ledger inside the repository" "it names a place inside this repository"
  e2e_expect_clean_edges
fi

if _want state-dir-link-into-repo; then
  _flow_test_begin "Stop hook: a FLOW_STATE_DIR reaching into the repository through a symlink is refused (E37)"
  e2e_new state-dir-link-into-repo
  e2e_describe "the same shipped goal and ledger copy inside the repository; one Stop with FLOW_STATE_DIR at a symlink outside the repository that points to that copy: the check does not run"
  _shipped_goal
  mkdir -p "$E2E_REPO/.flow-state"
  cp "$E2E_DIR/ledger/goal-trust.jsonl" "$E2E_REPO/.flow-state/goal-trust.jsonl"
  ln -s "$E2E_REPO/.flow-state" "$E2E_DIR/link-in"
  e2e_run_hook "FLOW_STATE_DIR=$E2E_DIR/link-in" "$STOP_HOOK" "$FIRST"
  _refused_state "through a symlink outside the repository" "it names a place inside this repository"
  e2e_expect_clean_edges
fi

if _want state-dir-link-dotdot; then
  _flow_test_begin "Stop hook: a FLOW_STATE_DIR through a committed symlink followed by .. is judged where the kernel resolves it (E37)"
  e2e_new state-dir-link-dotdot
  e2e_describe "the same shipped goal and ledger copy inside the repository, and a symlink the repository commits, evil -> a/b; one Stop with FLOW_STATE_DIR at evil/../../.flow-state, which the kernel resolves to the copy in the repository and a text-only reading to a directory beside the repository: the check does not run"
  _shipped_goal
  # The directory the text-only reading lands on exists, empty: where it does
  # not, bash's cd falls back to the physical path and the difference hides.
  mkdir -p "$E2E_REPO/.flow-state" "$E2E_REPO/a/b" "$E2E_DIR/.flow-state"
  cp "$E2E_DIR/ledger/goal-trust.jsonl" "$E2E_REPO/.flow-state/goal-trust.jsonl"
  ln -s "$E2E_REPO/a/b" "$E2E_REPO/evil"
  e2e_run_hook "FLOW_STATE_DIR=$E2E_REPO/evil/../../.flow-state" "$STOP_HOOK" "$FIRST"
  _refused_state "through a committed symlink and .." "it names a place inside this repository"
  e2e_expect_clean_edges
fi

if _want state-dir-set-by-repo; then
  _flow_test_begin "Stop hook: a FLOW_STATE_DIR outside the repository that the repository's own settings set is refused (E37)"
  e2e_new state-dir-set-by-repo
  e2e_describe "the same shipped goal, and its ledger outside the repository, named by the repository's own .claude/settings.json env block; one Stop with FLOW_STATE_DIR at that ledger: the check does not run, and stderr says the repository's settings set it"
  _shipped_goal
  jq -nc --arg v "$E2E_DIR/ledger" '{env:{FLOW_STATE_DIR:$v}}' > "$E2E_REPO/.claude/settings.json"
  e2e_run_hook "FLOW_STATE_DIR=$E2E_DIR/ledger" "$STOP_HOOK" "$FIRST"
  _refused_state "with the ledger named by the repository's settings" "this repository's Claude Code settings set it"
  e2e_expect_clean_edges
fi

if _want state-dir-from-user; then
  _flow_test_begin "Stop hook: a FLOW_STATE_DIR the user set outside the repository is still used (E37)"
  e2e_new state-dir-from-user
  e2e_describe "the same shipped goal and ledger outside the repository; Stop with FLOW_STATE_DIR at that ledger, which no repository settings name: the ledger is read, the goal is trusted and its check runs, with no warning. Then a FLOW_STATE_DIR outside the repository that does not exist yet: the goal is recorded into it, which makes it, and the Stop hook then runs the check"
  _shipped_goal
  e2e_run_hook "FLOW_STATE_DIR=$E2E_DIR/ledger" "$STOP_HOOK" "$FIRST"
  e2e_expect_equal "ran" "$(_check_ran)" "the goal's check, with the user's own FLOW_STATE_DIR"
  e2e_expect_err_lacks "FLOW_STATE_DIR"
  rm -f "$E2E_REPO/ran-check"
  e2e_run_bin "FLOW_STATE_DIR=$E2E_DIR/fresh/state" bin/flow-goal-trust.sh record --goal-file .flow/goals/g-shipped.goal.yaml
  e2e_expect_equal yes "$([ -s "$E2E_DIR/fresh/state/goal-trust.jsonl" ] && echo yes || echo no)" "the ledger written to a FLOW_STATE_DIR that did not exist yet"
  e2e_expect_err_lacks "FLOW_STATE_DIR"
  e2e_run_hook "FLOW_STATE_DIR=$E2E_DIR/fresh/state" "$STOP_HOOK" "$FIRST"
  e2e_expect_equal "ran" "$(_check_ran)" "the goal's check, trusted in the new FLOW_STATE_DIR"
  e2e_expect_clean_edges
fi
