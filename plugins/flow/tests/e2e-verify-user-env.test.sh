# shellcheck shell=bash
# End-to-end: a goal's verification commands run in the user's Python
# environment, not the one Flow hardens for its own python3 (#345).
#
# Flow's scripts clean PYTHONPATH and export PYTHONSAFEPATH=1 before their own
# python3 starts (tests/syspath-guard.test.sh has the reasons). A goal's
# verification_command is the user's command: with PYTHONSAFEPATH=1,
# `python3 -c "import calc"` does not find calc.py in the project directory,
# so a criterion that is met was reported as failing.
#
# Each scenario writes a goal into a scratch repository and runs the code
# that runs its verification commands, the way Claude Code runs it: the
# checks script (hooks/scripts/flow-run-deterministic-checks.sh), the Stop
# hook in block and evaluator-loop modes, and bin/flow-goal-judge-run.sh,
# which the goal-evaluator skill calls. /flow:start's end-of-VERIFY block is
# in e2e-start-goal-evaluate.test.sh, and promote-proposal.sh's git hooks in
# e2e-promote-tiers.test.sh. A criterion that probes its environment runs
# probe.sh, which writes what it saw to env-probe.txt in the repository. One
# artifact per scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the code:
#   W1 a criterion that imports a module from the project directory
#      (python3 -c "import calc; ...") fails in the checks, because the
#      command inherits PYTHONSAFEPATH=1
#   W2 the same through the Stop hook in block mode: the session is kept
#      working on a criterion that is met
#   W3 the same through evaluator-loop mode (flow-goal-evaluator.sh)
#   W4 PYTHONSAFEPATH unset for the user is set inside the command
#   W5 PYTHONSAFEPATH the user set (to 1, or to the empty string) is dropped
#      or changed inside the command
#   W6 PYTHONPATH unset for the user reaches the command set (empty)
#   W7 PYTHONPATH set to the empty string reaches the command unset: the
#      value is recorded as "" and which of the two it was is lost
#   W8 PYTHONPATH naming a directory inside the repository (which Flow drops
#      for its own python3) reaches the command cleaned, so the user's src/
#      layout cannot be imported
#   W9 the restore reaches Flow's own Python: a sitecustomize.py in a
#      PYTHONPATH directory inside the repository runs when Flow's python3
#      starts
#   W10 the values the Stop hook recorded are replaced by the checks script
#      it starts, which sees the hook's PYTHONSAFEPATH=1 and cleaned
#      PYTHONPATH and takes them for the user's
#   W11 Flow's bookkeeping variables (FLOW_USER_*) reach the command
#   W12 bin/flow-goal-judge-run.sh (the goal-evaluator skill's runner, whose
#      own cleaning runs before the checks script's) hands the command a
#      PYTHONPATH or PYTHONSAFEPATH that is not the user's

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "verification commands in the user's environment: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

# The environment of the person running the tests is not the scenario's: each
# scenario passes the values it tests, and everything else starts unset.
unset PYTHONPATH PYTHONSAFEPATH FLOW_USER_PYTHONPATH FLOW_USER_PYTHONPATH_SET FLOW_USER_PYTHONSAFEPATH FLOW_USER_PYTHONSAFEPATH_SET

CHECKS=hooks/scripts/flow-run-deterministic-checks.sh
STOP_HOOK=hooks/scripts/flow-goal-stop.sh
JUDGE_RUN=bin/flow-goal-judge-run.sh
BRANCH=feature/issue-7-x
PAYLOAD='{"session_id":"e2e-user-env","stop_hook_active":false}'
IMPORT_CMD='python3 -c "import calc; assert calc.subtract(5, 3) == 2"'

# _verify_repo <stopHookEnforcement> — the scratch repository on $BRANCH, with
# verification commands enabled, calc.py (the module a criterion imports),
# probe.sh, and src/ holding a sitecustomize.py that leaves a marker if any
# python3 imports it.
_verify_repo() {
  e2e_repo "$BRANCH"
  mkdir -p "$E2E_REPO/.claude" "$E2E_REPO/src" "$E2E_DIR/outside"
  jq -nc --arg m "$1" '{flow:{goals:{stopHookEnforcement:$m,executeVerificationCommands:true}}}' > "$E2E_REPO/.claude/settings.flow.json"
  printf 'def subtract(a, b):\n    return a - b\n' > "$E2E_REPO/calc.py"
  printf 'import os\nopen(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sitecustomize-ran"), "a").write("ran\\n")\n' \
    > "$E2E_REPO/src/sitecustomize.py"
  cat > "$E2E_REPO/probe.sh" <<'PROBE'
{
  if [ -n "${PYTHONPATH+x}" ]; then printf 'PYTHONPATH=set:%s\n' "$PYTHONPATH"; else printf 'PYTHONPATH=unset\n'; fi
  if [ -n "${PYTHONSAFEPATH+x}" ]; then printf 'PYTHONSAFEPATH=set:%s\n' "$PYTHONSAFEPATH"; else printf 'PYTHONSAFEPATH=unset\n'; fi
  printf 'FLOW_USER_vars=%s\n' "$(env | grep -c '^FLOW_USER_')"
} > env-probe.txt
PROBE
}

# _probe — what probe.sh saw, on one line.
_probe() {
  if [ -f "$E2E_REPO/env-probe.txt" ]; then tr '\n' ' ' < "$E2E_REPO/env-probe.txt" | sed 's/ $//'
  else printf 'probe did not run'; fi
}
# _sitecustomize — whether any python3 imported src/sitecustomize.py.
_sitecustomize() { if [ -e "$E2E_REPO/sitecustomize-ran" ]; then printf ran; else printf 'not run'; fi; }
# _report <jq filter> — a field of the checks report on stdout, compact.
_report() { printf '%s' "$E2E_OUT" | jq -c "$1" 2>/dev/null || printf 'no report'; }

_flow_test_begin "checks: a criterion that imports a module from the project directory passes (W1)"
e2e_new verify-local-import
e2e_describe "AC1 is: $IMPORT_CMD, with calc.py in the repository; PYTHONPATH and PYTHONSAFEPATH unset"
_verify_repo warn
e2e_goal issue-7 "$BRANCH" active "$IMPORT_CMD"
e2e_run_bin "$CHECKS" .flow/goals/issue-7.goal.yaml
e2e_expect_equal 0 "$E2E_RC" "the checks' exit status"
e2e_expect_equal '["AC1"]' "$(_report .passing)" "the passing criteria"
e2e_expect_equal '[]' "$(_report .failing)" "the failing criteria"
e2e_expect_clean_edges

_flow_test_begin "checks: PYTHONPATH and PYTHONSAFEPATH unset for the user are unset in the command (W4, W6, W11)"
e2e_new verify-env-unset
e2e_describe "AC1 runs probe.sh; PYTHONPATH and PYTHONSAFEPATH unset"
_verify_repo warn
e2e_goal issue-7 "$BRANCH" active "bash probe.sh"
e2e_run_bin "$CHECKS" .flow/goals/issue-7.goal.yaml
e2e_expect_equal '["AC1"]' "$(_report .passing)" "the passing criteria"
e2e_expect_equal "PYTHONPATH=unset PYTHONSAFEPATH=unset FLOW_USER_vars=0" "$(_probe)" "what the command saw"
e2e_expect_clean_edges

_flow_test_begin "checks: PYTHONPATH and PYTHONSAFEPATH set to the empty string stay set and empty (W5, W7)"
e2e_new verify-env-empty
e2e_describe "AC1 runs probe.sh; PYTHONPATH= and PYTHONSAFEPATH= (both set, empty)"
_verify_repo warn
e2e_goal issue-7 "$BRANCH" active "bash probe.sh"
e2e_run_bin PYTHONPATH= PYTHONSAFEPATH= "$CHECKS" .flow/goals/issue-7.goal.yaml
e2e_expect_equal '["AC1"]' "$(_report .passing)" "the passing criteria"
e2e_expect_equal "PYTHONPATH=set: PYTHONSAFEPATH=set: FLOW_USER_vars=0" "$(_probe)" "what the command saw"
e2e_expect_clean_edges

_flow_test_begin "checks: the user's PYTHONPATH (a src/ inside the repository) and PYTHONSAFEPATH=yes reach the command; Flow's python3 still drops src/ (W5, W8, W9)"
e2e_new verify-env-set
e2e_describe "AC1 runs probe.sh; PYTHONPATH=<repo>/src:<outside>, PYTHONSAFEPATH=yes; src/sitecustomize.py leaves a marker if imported"
_verify_repo warn
e2e_goal issue-7 "$BRANCH" active "bash probe.sh"
USER_PP="$E2E_REPO/src:$E2E_DIR/outside"
e2e_run_bin PYTHONPATH="$USER_PP" PYTHONSAFEPATH=yes "$CHECKS" .flow/goals/issue-7.goal.yaml
e2e_expect_equal '["AC1"]' "$(_report .passing)" "the passing criteria"
e2e_expect_equal "PYTHONPATH=set:$USER_PP PYTHONSAFEPATH=set:yes FLOW_USER_vars=0" "$(_probe)" "what the command saw"
e2e_expect_equal "not run" "$(_sitecustomize)" "src/sitecustomize.py"
e2e_expect_clean_edges

_flow_test_begin "Stop hook, block mode: a met local-import criterion does not block, and the command sees the user's values (W2, W7, W10)"
e2e_new verify-stop-block
e2e_describe "block mode; AC1 is: bash probe.sh && $IMPORT_CMD; PYTHONPATH= (set, empty), PYTHONSAFEPATH unset"
_verify_repo block
e2e_goal issue-7 "$BRANCH" active "bash probe.sh && $IMPORT_CMD"
e2e_run_hook PYTHONPATH= "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"approve"'
e2e_expect_no_out '"decision":"block"'
e2e_expect_equal "PYTHONPATH=set: PYTHONSAFEPATH=unset FLOW_USER_vars=0" "$(_probe)" "what the command saw"
e2e_expect_clean_edges

_flow_test_begin "Stop hook, evaluator-loop mode: a met local-import criterion passes, and the command sees the user's values (W3, W5, W6, W10)"
e2e_new verify-stop-evaluator
e2e_describe "evaluator-loop mode; AC1 is: bash probe.sh && $IMPORT_CMD; PYTHONPATH unset, PYTHONSAFEPATH= (set, empty)"
_verify_repo evaluator-loop
e2e_goal issue-7 "$BRANCH" active "bash probe.sh && $IMPORT_CMD"
e2e_run_hook PYTHONSAFEPATH= "$STOP_HOOK" "$PAYLOAD"
e2e_expect_out '"decision":"approve"'
e2e_expect_out "all deterministic checks pass"
e2e_expect_equal "PYTHONPATH=unset PYTHONSAFEPATH=set: FLOW_USER_vars=0" "$(_probe)" "what the command saw"
e2e_expect_clean_edges

_flow_test_begin "goal-evaluator runner: bin/flow-goal-judge-run.sh hands the command the user's values, and its own python3 still drops src/ (W8, W9, W12)"
e2e_new verify-judge-run
e2e_describe "flow-goal-judge-run.sh issue-7; AC1 runs probe.sh; PYTHONPATH=<repo>/src, PYTHONSAFEPATH unset; the judge replies achieved"
_verify_repo warn
e2e_goal issue-7 "$BRANCH" active "bash probe.sh"
e2e_judge_says '{"structured_output":{"verdict":"achieved","confidence":0.9,"reason":"met","criteria":[{"id":"AC1","status":"pass","reason":"met"}]}}'
e2e_run_bin PYTHONPATH="$E2E_REPO/src" "$JUDGE_RUN" issue-7 ""
e2e_expect_equal "PYTHONPATH=set:$E2E_REPO/src PYTHONSAFEPATH=unset FLOW_USER_vars=0" "$(_probe)" "what the command saw"
e2e_expect_equal "not run" "$(_sitecustomize)" "src/sitecustomize.py"
