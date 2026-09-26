# plugins/flow/tests/flow-start-onboarding.test.sh
#
# Covers:
#   - which skills may carry `context: fork` in their frontmatter: the 15 skills
#     invoked from command Inputs blocks must not, the 13 ambient skills awaiting
#     audit still do, and no other skill does.
#   - start.md's goal-creation gate forces GOAL_MODE off when flow.goals.enabled
#     is not true.

_flow_test_begin "skills invoked from command Inputs blocks do not use context: fork"

# Skills with `context: fork` lose their
# parent's context when invoked from command markdown. Per Claude Code docs
# (https://code.claude.com/docs/en/skills.md): "context: fork only makes
# sense for skills with explicit instructions ... If your skill contains
# guidelines like 'use these API conventions' without a task, the subagent
# receives the guidelines but no actionable prompt, and returns without
# meaningful output." None of the skills below use $ARGUMENTS as a task
# input, so fork is documented misuse for all of them.
#
# Three groups:
#   - fixes (3): user-reported failure cases — structured Inputs
#     invocation from command markdown.
#   - Pattern A fixes (8): invoked via Skill(X) from command
#     markdown; 5 of them explicitly say "invoking command MUST pass" in
#     body, which fork drops.
#   - disable-invoke fixes (4): have disable-model-invocation:
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


# --- goals.enabled master switch forces goal creation off ---------------------
_flow_test_begin "start.md documents the enabled:false -> off master switch"
SC=$(cat "$REPO_ROOT/plugins/flow/commands/start.md")
assert_contains 'ENABLED" != "true" ] && GOAL_MODE="off"' "$SC" "master-switch coercion present in the gate block"
