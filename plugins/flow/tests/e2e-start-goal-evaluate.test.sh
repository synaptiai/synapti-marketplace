# shellcheck shell=bash
# End-to-end: /flow:start evaluates its own FlowGoal at the end of VERIFY
# (#338), so /flow:pr's goal gate asks only when the goal is not met.
#
# Each scenario creates the goal with bin/flow-goal-record.sh --create, the way
# /flow:start creates it (so it is in the per-user trust ledger and its
# verification commands run), runs GOAL_EVALUATE_BLOCK from commands/start.md,
# then runs /flow:pr's Phase 1 fence and reads its `### FlowGoal State`
# section. The artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   V1 a run whose criteria all pass leaves the goal active, so /flow:pr's
#      gate reports GATE=block and asks
#   V2 a failing verification command still moves the goal to achieved
#   V3 the verdict is not recorded in lifecycle.last_evaluation, or the
#      failing criteria are not named
#   V4 a criterion with no verification command is taken as passed when the
#      verdict judge did not pass it
#   V5 an untrusted goal (its commands not run) is moved to achieved
#   V6 a run with no goal fails, or writes one
#   V7 the lifecycle write replaces the block, so turns_evaluated,
#      current_phase and current_activity are lost and the evaluator-loop
#      budget starts again from zero
#   V8 with flow.goals.executeVerificationCommands: true, a goal that is not
#      in the trust ledger has its commands run, and a pass moves it to
#      achieved without the question references/goal-lifecycle-transitions.md
#      says only a trusted goal skips

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "start goal evaluation: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

START_MD=commands/start.md
PR_MD="$E2E_PLUGIN_DIR/commands/pr.md"
BRANCH=feature/issue-42-search-fix

# _section <heading> — the lines of one ### section of the last output.
_section() {
  printf '%s\n' "$E2E_OUT" | awk -v h="### $1" '$0 == h { f = 1; next } /^### / { f = 0 } f'
}

# _start_repo <name> <purpose> — a scratch repository on the goal's branch,
# one commit ahead of main, with the gh fixtures /flow:pr's Phase 1 reads.
_start_repo() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo "$BRANCH"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git branch -f main HEAD
    printf 'work\n' > work.txt
    git add work.txt
    git commit -q -m "feat: work"
  ) || _flow_assert_fail "$1: could not set up the scratch repository"
  e2e_gh_fixture repo '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}'
  e2e_gh_fixture "open-prs-$(printf '%s' "$BRANCH" | tr / _)" '[]'
  e2e_gh_fail commit-main
  e2e_gh_fixture issue-42 '{"title":"Search returns empty results","body":"","labels":[]}'
}

# _trusted_goal <command for AC1, or "" for none> [<lifecycle JSON>] — create
# issue-42's goal the way /flow:start does, on this branch; the lifecycle is
# {"status": "active"} unless given.
_trusted_goal() {
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$E2E_DIR/goal.yaml" "$1" "${2:-}" <<'PY'
import json, sys, yaml
src, dst, cmd, life = sys.argv[1:5]
g = yaml.safe_load(open(src, encoding="utf-8"))
ac = g["objective"]["acceptance_criteria"][0]
if cmd:
    ac["verification_command"] = cmd
else:
    ac.pop("verification_command", None)
g["lifecycle"] = json.loads(life) if life else {"status": "active"}
yaml.safe_dump(g, open(dst, "w", encoding="utf-8"), sort_keys=False)
PY
  (_e2e_git_env; cd "$E2E_REPO" && "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$E2E_DIR/goal.yaml") \
    >/dev/null 2>"$E2E_DIR/create.err" || _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create failed: $(cat "$E2E_DIR/create.err")"
}

_goal_field() {
  python3 -c 'import sys, yaml; g = yaml.safe_load(open(sys.argv[1])); v = g
for k in sys.argv[2].split("."):
    v = (v or {}).get(k)
print(v)' "$E2E_REPO/.flow/goals/issue-42.goal.yaml" "$1"
}

_start_repo start-goal-pass "every criterion passes in VERIFY: the goal is achieved, and /flow:pr's gate passes without asking (V1, V3)"
_trusted_goal true
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_line "GOAL_ID=issue-42"
e2e_expect_line "GOAL_EVAL_RESULT=pass"
e2e_expect_line "GOAL_LIFECYCLE=achieved"
e2e_expect_equal achieved "$(_goal_field lifecycle.status)" "the goal file's lifecycle.status"
e2e_expect_equal pass "$(_goal_field lifecycle.last_evaluation.result)" "the goal file's last_evaluation.result"
e2e_expect_line "JOURNAL=recorded"
e2e_expect_file_has .decisions/issue-42.md "goal-evaluation"
e2e_run_fence "$PR_MD" '### Branch Delta'
e2e_expect_equal "$(printf 'STATE=ok\nGOAL_ID=issue-42\nGOAL_LIFECYCLE=achieved\nGATE=pass')" \
  "$(_section 'FlowGoal State')" "/flow:pr's FlowGoal State section"
e2e_expect_clean_edges

_start_repo start-goal-fail "a verification command fails: the goal stays active, the failing criterion is named, and /flow:pr's gate still asks (V2, V3)"
_trusted_goal false
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_line "GOAL_EVAL_RESULT=fail"
e2e_expect_line "GOAL_LIFECYCLE=active"
e2e_expect_line "GOAL_EVAL_REASON=verification commands failed for: AC1"
e2e_expect_equal active "$(_goal_field lifecycle.status)" "the goal file's lifecycle.status"
e2e_expect_equal fail "$(_goal_field lifecycle.last_evaluation.result)" "the goal file's last_evaluation.result"
e2e_run_fence "$PR_MD" '### Branch Delta'
e2e_expect_equal "$(printf 'STATE=ok\nGOAL_ID=issue-42\nGOAL_LIFECYCLE=active\nGATE=block')" \
  "$(_section 'FlowGoal State')" "/flow:pr's FlowGoal State section"
e2e_expect_clean_edges

_start_repo start-goal-no-command "a criterion with no verification command, and the verdict judge could not decide it: incomplete, still active (V4)"
_trusted_goal ""
e2e_run_block GOAL_EVAL_VERDICT=NEEDS-HUMAN-REVIEW "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "GOAL_EVAL_RESULT=incomplete"
e2e_expect_line "GOAL_LIFECYCLE=active"
e2e_expect_out "were not passed by the verdict judge (NEEDS-HUMAN-REVIEW): AC1"
e2e_expect_clean_edges

_start_repo start-goal-no-command-pass "a criterion with no verification command that the verdict judge passed: achieved (V4)"
_trusted_goal ""
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "GOAL_EVAL_RESULT=pass"
e2e_expect_line "GOAL_LIFECYCLE=achieved"
e2e_expect_clean_edges

_start_repo start-goal-untrusted "a goal that is not in the trust ledger: its command is not run, so it is not achieved (V5)"
e2e_goal issue-42 "$BRANCH" active true
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "GOAL_EVAL_RESULT=incomplete"
e2e_expect_line "GOAL_LIFECYCLE=active"
e2e_expect_out "because the goal is not trusted: AC1"
e2e_expect_clean_edges

_start_repo start-goal-keeps-lifecycle "a goal three Stop-hook turns in that stays active: turns_evaluated, current_phase and current_activity are kept (V7)"
_trusted_goal false '{"status":"active","current_phase":"verify","current_activity":"verdict","turns_evaluated":3}'
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_line "GOAL_LIFECYCLE=active"
e2e_expect_equal fail "$(_goal_field lifecycle.last_evaluation.result)" "the goal file's last_evaluation.result"
e2e_expect_equal 3 "$(_goal_field lifecycle.turns_evaluated)" "the goal file's lifecycle.turns_evaluated"
e2e_expect_equal verify "$(_goal_field lifecycle.current_phase)" "the goal file's lifecycle.current_phase"
e2e_expect_equal verdict "$(_goal_field lifecycle.current_activity)" "the goal file's lifecycle.current_activity"
e2e_expect_clean_edges

_start_repo start-goal-untrusted-exec-on "executeVerificationCommands: true and a goal not in the trust ledger whose command passes: incomplete, still active, so /flow:pr asks (V8)"
e2e_goal issue-42 "$BRANCH" active true
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"goals":{"executeVerificationCommands":true}}}' > "$E2E_REPO/.claude/settings.flow.json"
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_line "GOAL_EVAL_RESULT=incomplete"
e2e_expect_line "GOAL_LIFECYCLE=active"
e2e_expect_out "the goal is not in the trust ledger"
e2e_expect_equal active "$(_goal_field lifecycle.status)" "the goal file's lifecycle.status"
e2e_run_fence "$PR_MD" '### Branch Delta'
e2e_expect_equal "$(printf 'STATE=ok\nGOAL_ID=issue-42\nGOAL_LIFECYCLE=active\nGATE=block')" \
  "$(_section 'FlowGoal State')" "/flow:pr's FlowGoal State section"
e2e_expect_clean_edges

_start_repo start-goal-none "no goal on this branch: nothing is evaluated or written (V6)"
e2e_run_block GOAL_EVAL_VERDICT=PASS "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "STATE=none"
e2e_expect_equal 0 "$([ -d "$E2E_REPO/.flow/goals" ] && echo 1 || echo 0)" "a goals directory was created"
e2e_expect_clean_edges

_start_repo start-goal-bad-verdict "GOAL_EVAL_VERDICT not set: the block refuses rather than guessing"
_trusted_goal true
e2e_run_block "$START_MD" GOAL_EVALUATE_BLOCK
e2e_expect_line "STATE=blocked"
e2e_expect_equal active "$(_goal_field lifecycle.status)" "the goal file's lifecycle.status"
e2e_expect_clean_edges
