# plugins/flow/tests/flow-start-onboarding.test.sh (goalCreation suite)
#
# #111 AC-1 retired the Phase 0.5 onboarding AskUserQuestion and the
# set_flow_goals helper, replacing the binary requireGoalForStart with the
# 3-state flow.goals.goalCreation (auto|always|off, default auto). This suite
# now covers:
#   - Read-only migration mapping (the compound jq expression start.md/pr.md/
#     merge.md resolve): requireGoalForStart true->always, false->off,
#     absent->auto, and explicit goalCreation wins over the legacy key.
#   - The FlowGoal auto-creation gate keyed on GOAL_MODE != off, including the
#     bare-$ARGUMENTS parsing regression guard from #120.
#   - start.md documents the "verifiable ACs win" auto predicate (the
#     prose-side gate Claude applies after the bash block).
# The unrelated context:fork skill lint is preserved at the end.

# -- Migration mapping (the compound jq expression, --default auto) ------------
MIG_EXPR='.flow.goals.goalCreation // (if .flow.goals.requireGoalForStart == true then "always" elif .flow.goals.requireGoalForStart == false then "off" else null end)'

_mig() {
  printf '%s' "$1" | jq -r "($MIG_EXPR) // \"auto\""
}

if command -v jq >/dev/null 2>&1; then
  _flow_test_begin "migration: requireGoalForStart:true -> always"
  assert_equal "always" "$(_mig '{"flow":{"goals":{"requireGoalForStart":true}}}')" "true maps to always"

  _flow_test_begin "migration: requireGoalForStart:false -> off"
  assert_equal "off" "$(_mig '{"flow":{"goals":{"requireGoalForStart":false}}}')" "false maps to off"

  _flow_test_begin "migration: neither key (empty goals) -> auto"
  assert_equal "auto" "$(_mig '{"flow":{"goals":{}}}')" "absent maps to auto (cascade default)"

  _flow_test_begin "migration: no flow block at all -> auto"
  assert_equal "auto" "$(_mig '{}')" "empty settings maps to auto"

  _flow_test_begin "migration: explicit goalCreation wins over legacy key"
  assert_equal "always" "$(_mig '{"flow":{"goals":{"goalCreation":"always","requireGoalForStart":false}}}')" "goalCreation overrides requireGoalForStart"
  assert_equal "off" "$(_mig '{"flow":{"goals":{"goalCreation":"off","requireGoalForStart":true}}}')" "goalCreation:off overrides requireGoalForStart:true"

  _flow_test_begin "migration: else-null lets a neither-key source fall through (no auto short-circuit)"
  RAW=$(printf '%s' '{"flow":{"goals":{}}}' | jq -r "$MIG_EXPR")
  assert_equal "null" "$RAW" "neither-key source yields null (falls through), not auto"
else
  _flow_test_begin "migration mapping"
  _flow_assert_pass "SKIP: jq not installed"
fi


# -- FlowGoal auto-creation gate (keyed on GOAL_MODE != off) -------------------
cc_substitute() {
  local block="$1" arg="${2-}"
  block="${block//\$\{ARGUMENTS\}/$arg}"
  block="${block//\$ARGUMENTS/$arg}"
  printf '%s' "$block"
}

GOAL_GATE_BLOCK='
_RAW="$ARGUMENTS"
ARG1="${_RAW%% *}"
case "$ARG1" in
  ""|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac

if [ "$GOAL_MODE" != "off" ] && [ -n "$ISSUE_NUM" ]; then
  GOAL_ID="issue-$ISSUE_NUM"
  GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"
  if [ -f "$GOAL_PATH" ]; then
    echo "FLOW_GOAL_STATE=exists"
    echo "GOAL_PATH=$GOAL_PATH"
  else
    echo "FLOW_GOAL_STATE=create"
    echo "GOAL_ID=$GOAL_ID"
    echo "GOAL_PATH=$GOAL_PATH"
  fi
else
  echo "FLOW_GOAL_STATE=skip"
fi
'

TMP_DIR=$(mktemp -d -t flow-goalcreation.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

_flow_test_begin "gate: GOAL_MODE=auto + ISSUE_NUM -> create"
CREATE_DIR="$TMP_DIR/create-arm"; mkdir -p "$CREATE_DIR"
OUT=$(cd "$CREATE_DIR" && GOAL_MODE=auto bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_contains "FLOW_GOAL_STATE=create" "$OUT" "auto + issue -> create"
assert_contains "GOAL_ID=issue-42" "$OUT" "GOAL_ID=issue-42"
assert_contains "GOAL_PATH=.flow/goals/issue-42.goal.yaml" "$OUT" "GOAL_PATH set"

_flow_test_begin "gate: GOAL_MODE=always + existing goal -> exists (no overwrite)"
EXISTS_DIR="$TMP_DIR/exists-arm"; mkdir -p "$EXISTS_DIR/.flow/goals"
echo "apiVersion: flow.synapti.ai/v1" > "$EXISTS_DIR/.flow/goals/issue-42.goal.yaml"
OUT=$(cd "$EXISTS_DIR" && GOAL_MODE=always bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_contains "FLOW_GOAL_STATE=exists" "$OUT" "always + existing -> exists"
assert_not_contains "FLOW_GOAL_STATE=create" "$OUT" "not flagged for creation"

_flow_test_begin "gate: GOAL_MODE=off -> skip"
OUT=$(cd "$TMP_DIR" && GOAL_MODE=off bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "off -> skip (manual /flow:goal create still works)"

_flow_test_begin "gate: GOAL_MODE=auto + missing ISSUE_NUM -> skip"
OUT=$(cd "$TMP_DIR" && GOAL_MODE=auto bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "missing ISSUE_NUM -> skip"

_flow_test_begin "gate: GOAL_MODE=auto + non-digit ARGUMENTS -> skip"
OUT=$(cd "$TMP_DIR" && GOAL_MODE=auto bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "abc")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "non-digit -> skip"

_flow_test_begin "regression(#120): old \${ARGUMENTS%% *} form degrades to skip under CC substitution"
OLD_BROKEN_BLOCK='
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ""|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac
if [ "$GOAL_MODE" != "off" ] && [ -n "$ISSUE_NUM" ]; then
  echo "FLOW_GOAL_STATE=create"
else
  echo "FLOW_GOAL_STATE=skip"
fi
'
OUT=$(cd "$TMP_DIR" && GOAL_MODE=auto bash -c "$(cc_substitute "$OLD_BROKEN_BLOCK" "42")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "old form expands empty under CC substitution (this IS the #120 bug)"
OUT=$(cd "$TMP_DIR" && GOAL_MODE=auto bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_contains "FLOW_GOAL_STATE=create" "$OUT" "fixed _RAW form produces create under the identical model"


# -- start.md documents the verifiable-ACs-win auto predicate (prose gate) -----
_flow_test_begin "start.md documents the auto verifiable-AC predicate + silent skip"
START_CMD="$REPO_ROOT/plugins/flow/commands/start.md"
SC=$(cat "$START_CMD")
assert_contains "goalCreation" "$SC" "start.md references the 3-state goalCreation"
assert_contains "verification_command" "$SC" "auto predicate keyed on verification_command"
assert_contains "skip silently" "$SC" "spec-free / zero-verifiable path skips silently"
assert_not_contains "FLOW_V3_ONBOARDING" "$SC" "Phase 0.5 onboarding fully retired"
assert_not_contains "set_flow_goals" "$SC" "set_flow_goals helper removed"


_flow_test_begin "skills invoked from command Inputs blocks do not use context: fork"

# Cycle-10 + cycle-11 regression fix: skills with `context: fork` lose their
# parent's context when invoked from command markdown. Per Claude Code docs
# (https://code.claude.com/docs/en/skills.md): "context: fork only makes
# sense for skills with explicit instructions ... If your skill contains
# guidelines like 'use these API conventions' without a task, the subagent
# receives the guidelines but no actionable prompt, and returns without
# meaningful output." None of the skills below use $ARGUMENTS as a task
# input, so fork is documented misuse for all of them.
#
# Three groups:
#   - cycle-10 fixes (3): user-reported failure cases — structured Inputs
#     invocation from command markdown.
#   - cycle-11 Pattern A fixes (8): invoked via Skill(X) from command
#     markdown; 5 of them explicitly say "invoking command MUST pass" in
#     body, which fork drops.
#   - cycle-11 disable-invoke fixes (4): have disable-model-invocation:
#     true so fork is dormant anyway — cosmetic cleanup.
#
# 13 remaining ambient-only skills (architecture-patterns, brainstorming,
# branch-and-task-management, change-classification, code-review-methodology,
# convention-enforcement, criterion-verification-map, debugging-patterns,
# feedback-resolution, goal-evidence-ledger, merge-conflict-resolution,
# run-state-management, tdd-patterns) retain `context: fork` until each
# body is individually audited as task-directive-with-$ARGUMENTS vs
# reference-only. Deferred to follow-up issue.

REPO_ROOT_FOR_LINT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

# 15 skills must NOT carry context: fork
for skill in \
  specification-capture holdout-validation runtime-verification \
  capability-discovery goal-contract-capture goal-evaluator goal-lifecycle \
  issue-crafting trigger-policy visual-verification workflow-validation \
  merge-and-release pr-lifecycle preflight-checks team-coordination; do
  SKILL_PATH="$REPO_ROOT_FOR_LINT/plugins/flow/skills/$skill/SKILL.md"
  if [ -f "$SKILL_PATH" ]; then
    if grep -q "^context: fork" "$SKILL_PATH"; then
      _flow_assert_fail "skill $skill has context: fork in frontmatter (regression)"
    else
      _flow_assert_pass "skill $skill frontmatter does not carry context: fork"
    fi
  else
    _flow_assert_fail "skill file missing: $SKILL_PATH"
  fi
done

# Per-skill assertions for the 13 deferred ambient skills. Each one must
# STILL carry context: fork until its body is individually audited. Per-skill
# diagnostics (vs. a single count assertion) tell the operator WHICH skill
# drifted on a failure, instead of "expected 13, got 12 — which one?".
DEFERRED_AMBIENT=(architecture-patterns brainstorming branch-and-task-management \
                  change-classification code-review-methodology convention-enforcement \
                  criterion-verification-map debugging-patterns feedback-resolution \
                  goal-evidence-ledger merge-conflict-resolution run-state-management \
                  tdd-patterns)
for skill in "${DEFERRED_AMBIENT[@]}"; do
  SKILL_PATH="$REPO_ROOT_FOR_LINT/plugins/flow/skills/$skill/SKILL.md"
  if [ -f "$SKILL_PATH" ]; then
    if grep -q "^context: fork" "$SKILL_PATH"; then
      _flow_assert_pass "deferred-audit skill $skill still carries context: fork"
    else
      _flow_assert_fail "deferred-audit skill $skill MISSING context: fork (audit-scope drift)"
    fi
  else
    _flow_assert_fail "deferred-audit skill file missing: $SKILL_PATH"
  fi
done

# Catch the inverse case: a skill outside both the 15-fixed and 13-deferred
# sets should not be carrying context: fork (no new fork-using skills slipping
# in without an audit). This guards against the "add a new skill with fork"
# regression that the per-skill loops above would miss.
ALL_FIXED=(specification-capture holdout-validation runtime-verification \
           capability-discovery goal-contract-capture goal-evaluator goal-lifecycle \
           issue-crafting trigger-policy visual-verification workflow-validation \
           merge-and-release pr-lifecycle preflight-checks team-coordination)
EXPECTED_FORK_SET=("${DEFERRED_AMBIENT[@]}")
ALL_FORK=$(grep -l "^context: fork" "$REPO_ROOT_FOR_LINT"/plugins/flow/skills/*/SKILL.md 2>/dev/null \
           | sed 's|.*/skills/\([^/]*\)/.*|\1|' | sort)
EXPECTED_FORK_SORTED=$(printf '%s\n' "${EXPECTED_FORK_SET[@]}" | sort)
if [ "$ALL_FORK" = "$EXPECTED_FORK_SORTED" ]; then
  _flow_assert_pass "no fork-using skill outside the 13 deferred-audit set"
else
  EXTRA=$(comm -23 <(printf '%s\n' "$ALL_FORK") <(printf '%s\n' "$EXPECTED_FORK_SORTED") | head -3 | tr '\n' ',')
  MISSING=$(comm -13 <(printf '%s\n' "$ALL_FORK") <(printf '%s\n' "$EXPECTED_FORK_SORTED") | head -3 | tr '\n' ',')
  _flow_assert_fail "fork-set drift: extra=[$EXTRA] missing=[$MISSING]"
fi
