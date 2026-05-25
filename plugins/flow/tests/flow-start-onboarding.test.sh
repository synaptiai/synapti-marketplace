# plugins/flow/tests/flow-start-onboarding.test.sh
#
# Tests the Phase 0.5 onboarding detection in commands/start.md and the
# FlowGoal auto-creation gate logic. The bash blocks in start.md are
# pre-executed (`!` prefix) so they can be lifted verbatim and tested
# here — same approach the other start-related tests use.
#
# Coverage:
#   - Onboarding detection: returns "needed" when neither .claude/settings.flow.json
#     nor .flow/ exist (fresh install signal).
#   - Onboarding detection: returns "skip" when either signal is present
#     (v2 upgrade or already-onboarded project).
#   - Idempotency: after writing settings file (either enable or skip arm),
#     re-running detection returns "skip".
#   - FlowGoal auto-creation gate: when requireGoalForStart=true and a valid
#     ISSUE_NUM is present, state is `create`; when goal file already exists,
#     state is `exists`; when flag is false, state is `skip`.

_flow_test_begin "onboarding detection: fresh install -> needed"

# Use a temp dir that's NOT the repo root. We're testing the detection logic
# itself, not against the real repo state.
TMP_DIR=$(mktemp -d -t flow-onboard.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

ONBOARDING_BLOCK='
NEEDS_ONBOARDING=0
if [ -d .flow ]; then
  NEEDS_ONBOARDING=0
elif [ ! -f .claude/settings.flow.json ]; then
  NEEDS_ONBOARDING=1
else
  if command -v jq >/dev/null 2>&1; then
    HAS_GOALS=$(jq -e ".flow.goals // empty" .claude/settings.flow.json 2>/dev/null)
    [ -z "$HAS_GOALS" ] && NEEDS_ONBOARDING=1
  fi
fi
if [ "$NEEDS_ONBOARDING" = "1" ]; then
  echo "FLOW_V3_ONBOARDING=needed"
else
  echo "FLOW_V3_ONBOARDING=skip"
fi
'

# Fresh: neither file nor directory exists
OUT=$(cd "$TMP_DIR" && bash -c "$ONBOARDING_BLOCK")
assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "fresh -> needed"


_flow_test_begin "onboarding detection: settings file present -> skip"

mkdir -p "$TMP_DIR/with-settings/.claude"
echo '{"flow": {"goals": {"requireGoalForStart": false}}}' > "$TMP_DIR/with-settings/.claude/settings.flow.json"
OUT=$(cd "$TMP_DIR/with-settings" && bash -c "$ONBOARDING_BLOCK")
assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" "settings.flow.json present -> skip"


_flow_test_begin "onboarding detection: .flow/ present -> skip"

mkdir -p "$TMP_DIR/with-flow/.flow/goals"
OUT=$(cd "$TMP_DIR/with-flow" && bash -c "$ONBOARDING_BLOCK")
assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" ".flow/ present -> skip"


_flow_test_begin "onboarding detection: both present -> skip"

mkdir -p "$TMP_DIR/with-both/.claude" "$TMP_DIR/with-both/.flow"
echo '{}' > "$TMP_DIR/with-both/.claude/settings.flow.json"
OUT=$(cd "$TMP_DIR/with-both" && bash -c "$ONBOARDING_BLOCK")
assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" "both present -> skip"


_flow_test_begin "onboarding idempotency: enable arm writes valid JSON"

ENABLE_DIR="$TMP_DIR/enable-arm"
mkdir -p "$ENABLE_DIR"
(
  cd "$ENABLE_DIR"
  mkdir -p .claude
  cat > .claude/settings.flow.json <<'JSON'
{
  "flow": {
    "goals": {
      "requireGoalForStart": true,
      "executeVerificationCommands": true
    }
  }
}
JSON
)
assert_file_exists "$ENABLE_DIR/.claude/settings.flow.json" "enable arm: settings file exists"

if command -v jq >/dev/null 2>&1; then
  REQ=$(jq -r '.flow.goals.requireGoalForStart' "$ENABLE_DIR/.claude/settings.flow.json")
  EXE=$(jq -r '.flow.goals.executeVerificationCommands' "$ENABLE_DIR/.claude/settings.flow.json")
  assert_equal "true" "$REQ" "enable arm: requireGoalForStart=true"
  assert_equal "true" "$EXE" "enable arm: executeVerificationCommands=true"
else
  _flow_assert_pass "enable arm: jq unavailable, skipping field check (file existence already verified)"
fi

# Re-detect: must return skip now
OUT=$(cd "$ENABLE_DIR" && bash -c "$ONBOARDING_BLOCK")
assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" "enable arm: re-detection returns skip (no re-prompt)"


_flow_test_begin "onboarding idempotency: skip arm writes valid JSON"

SKIP_DIR="$TMP_DIR/skip-arm"
mkdir -p "$SKIP_DIR"
(
  cd "$SKIP_DIR"
  mkdir -p .claude
  cat > .claude/settings.flow.json <<'JSON'
{
  "flow": {
    "goals": {
      "requireGoalForStart": false,
      "executeVerificationCommands": false
    }
  }
}
JSON
)
assert_file_exists "$SKIP_DIR/.claude/settings.flow.json" "skip arm: settings file exists"

if command -v jq >/dev/null 2>&1; then
  REQ=$(jq -r '.flow.goals.requireGoalForStart' "$SKIP_DIR/.claude/settings.flow.json")
  assert_equal "false" "$REQ" "skip arm: requireGoalForStart=false"
fi

OUT=$(cd "$SKIP_DIR" && bash -c "$ONBOARDING_BLOCK")
assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" "skip arm: re-detection returns skip"


_flow_test_begin "goal auto-creation gate: requireGoal=true + ISSUE_NUM -> create"

# Model Claude Code's slash-command preprocessor. It textually substitutes the
# bare `$ARGUMENTS` and `${ARGUMENTS}` (braces, no operator) tokens with the
# literal argument string, and leaves bash parameter-expansion forms like
# `${ARGUMENTS%% *}` UNTOUCHED. Crucially it does NOT export ARGUMENTS into the
# runtime environment — so a block that survives only because `${ARGUMENTS%% *}`
# expanded against a real env var is broken in production. Earlier this fixture
# ran `ARGUMENTS=42 bash -c "$BLOCK"`, which injected that env var and thereby
# HID the bug: the broken `${ARGUMENTS%% *}` form "worked" in the test and
# shipped degraded.
cc_substitute() {
  local block="$1" arg="${2-}"
  block="${block//\$\{ARGUMENTS\}/$arg}"   # ${ARGUMENTS} (braces, no operator)
  block="${block//\$ARGUMENTS/$arg}"        # bare $ARGUMENTS
  printf '%s' "$block"
}

# Lift the gate logic from start.md and exercise it without invoking
# cascade-resolve.sh — we pre-set REQUIRE_GOAL directly so this test is
# hermetic and doesn't depend on the cascade implementation. The arg parse
# uses the correct pattern: copy the bare (substituted) form into a local,
# THEN apply parameter-expansion to the local.
GOAL_GATE_BLOCK='
_RAW="$ARGUMENTS"
ARG1="${_RAW%% *}"
case "$ARG1" in
  ""|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac

if [ "$REQUIRE_GOAL" = "true" ] && [ -n "$ISSUE_NUM" ]; then
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

# Each arm substitutes the arg into the block the way Claude Code would, then
# runs it WITHOUT ARGUMENTS in the env (production never sets it).
CREATE_DIR="$TMP_DIR/create-arm"
mkdir -p "$CREATE_DIR"
OUT=$(cd "$CREATE_DIR" && REQUIRE_GOAL=true bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_contains "FLOW_GOAL_STATE=create" "$OUT" "create arm: state=create"
assert_contains "GOAL_ID=issue-42" "$OUT" "create arm: GOAL_ID=issue-42"
assert_contains "GOAL_PATH=.flow/goals/issue-42.goal.yaml" "$OUT" "create arm: GOAL_PATH set"


_flow_test_begin "goal auto-creation gate: existing goal -> exists (no overwrite)"

EXISTS_DIR="$TMP_DIR/exists-arm"
mkdir -p "$EXISTS_DIR/.flow/goals"
echo "apiVersion: flow.synapti.ai/v1" > "$EXISTS_DIR/.flow/goals/issue-42.goal.yaml"
OUT=$(cd "$EXISTS_DIR" && REQUIRE_GOAL=true bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_contains "FLOW_GOAL_STATE=exists" "$OUT" "exists arm: state=exists"
assert_not_contains "FLOW_GOAL_STATE=create" "$OUT" "exists arm: not flagged for creation"


_flow_test_begin "goal auto-creation gate: requireGoal=false -> skip"

OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=false bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "requireGoal=false -> skip"


_flow_test_begin "goal auto-creation gate: missing ISSUE_NUM -> skip"

OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=true bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "missing ISSUE_NUM -> skip"


_flow_test_begin "goal auto-creation gate: non-digit ARGUMENTS -> skip"

OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=true bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "abc")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "non-digit ARGUMENTS -> skip (matches Phase 0 validation)"


_flow_test_begin "regression: old \${ARGUMENTS%% *} form degrades to skip under CC substitution"

# The fixture's whole point: prove the bug now, so a revert to the broken form
# fails here. Under faithful CC substitution (bare-only, no env var), the old
# parameter-expansion form expands empty and the gate silently skips — even
# with requireGoal=true and a valid issue number passed.
OLD_BROKEN_BLOCK='
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ""|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac
if [ "$REQUIRE_GOAL" = "true" ] && [ -n "$ISSUE_NUM" ]; then
  echo "FLOW_GOAL_STATE=create"
else
  echo "FLOW_GOAL_STATE=skip"
fi
'
OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=true bash -c "$(cc_substitute "$OLD_BROKEN_BLOCK" "42")")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "old form expands empty under CC substitution (this IS the bug; env-injection fixture hid it)"

# Sanity: the SAME arg through the SAME substitution model, but the fixed
# block, must produce create — proving the fix, not just the bug.
OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=true bash -c "$(cc_substitute "$GOAL_GATE_BLOCK" "42")")
assert_contains "FLOW_GOAL_STATE=create" "$OUT" "fixed _RAW form produces create under the identical substitution model"


# ────────────────────────────────────────────────────────────────────────────
# Partial-settings detection (cycle-10 regression fix — field-feedback bug)
#
# Before cycle 10, the onboarding gate only checked file existence. A user
# who committed `.claude/settings.flow.json` with v2-only keys (e.g.,
# `agentTeams`) silently bypassed the v3 onboarding prompt forever — the
# file existed, so the gate skipped, but the user had never answered the
# v3 question. Cycle 10 closes the bypass by checking for the `flow.goals`
# block via jq.
# ────────────────────────────────────────────────────────────────────────────

_flow_test_begin "partial-settings detection: empty {} -> needed"

if command -v jq >/dev/null 2>&1; then
  EMPTY_DIR="$TMP_DIR/partial-empty"
  mkdir -p "$EMPTY_DIR/.claude"
  echo '{}' > "$EMPTY_DIR/.claude/settings.flow.json"
  OUT=$(cd "$EMPTY_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "empty {} bypassed pre-cycle-10; now correctly prompts"
else
  _flow_assert_pass "skip: jq unavailable — partial detection requires jq"
fi


_flow_test_begin "partial-settings detection: v2-only keys (no flow) -> needed"

if command -v jq >/dev/null 2>&1; then
  V2_DIR="$TMP_DIR/partial-v2"
  mkdir -p "$V2_DIR/.claude"
  echo '{"agentTeams": false}' > "$V2_DIR/.claude/settings.flow.json"
  OUT=$(cd "$V2_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "v2 settings without flow block -> prompt (this is the user's reported bug shape)"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "partial-settings detection: flow block but no goals subkey -> needed"

if command -v jq >/dev/null 2>&1; then
  NO_GOALS_DIR="$TMP_DIR/partial-no-goals"
  mkdir -p "$NO_GOALS_DIR/.claude"
  echo '{"flow": {"agentTeams": false}}' > "$NO_GOALS_DIR/.claude/settings.flow.json"
  OUT=$(cd "$NO_GOALS_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "flow block without goals subkey -> prompt"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "partial-settings detection: empty flow.goals block -> skip (user has answered)"

if command -v jq >/dev/null 2>&1; then
  EMPTY_GOALS_DIR="$TMP_DIR/partial-empty-goals"
  mkdir -p "$EMPTY_GOALS_DIR/.claude"
  echo '{"flow": {"goals": {}}}' > "$EMPTY_GOALS_DIR/.claude/settings.flow.json"
  OUT=$(cd "$EMPTY_GOALS_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" "empty flow.goals -> skip (presence of block signals user has engaged with v3)"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "partial-settings detection: .flow/ overrides partial settings (user is using v3)"

if command -v jq >/dev/null 2>&1; then
  OVERRIDE_DIR="$TMP_DIR/partial-with-flow-dir"
  mkdir -p "$OVERRIDE_DIR/.claude" "$OVERRIDE_DIR/.flow/goals"
  echo '{"agentTeams": false}' > "$OVERRIDE_DIR/.claude/settings.flow.json"
  OUT=$(cd "$OVERRIDE_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=skip" "$OUT" ".flow/ dir signals active v3 use even with partial settings"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "partial-settings detection: malformed JSON -> needed"

if command -v jq >/dev/null 2>&1; then
  BAD_DIR="$TMP_DIR/partial-malformed"
  mkdir -p "$BAD_DIR/.claude"
  echo '{ this is not valid json' > "$BAD_DIR/.claude/settings.flow.json"
  OUT=$(cd "$BAD_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "malformed JSON -> prompt (jq parse failure signals user hasn't successfully opted in)"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "partial-settings detection: array root -> needed"

if command -v jq >/dev/null 2>&1; then
  ARR_DIR="$TMP_DIR/partial-array"
  mkdir -p "$ARR_DIR/.claude"
  echo '[]' > "$ARR_DIR/.claude/settings.flow.json"
  OUT=$(cd "$ARR_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "array root -> prompt (no flow.goals path through array)"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "partial-settings detection: flow.goals = null -> needed"

if command -v jq >/dev/null 2>&1; then
  NULL_DIR="$TMP_DIR/partial-null"
  mkdir -p "$NULL_DIR/.claude"
  echo '{"flow": {"goals": null}}' > "$NULL_DIR/.claude/settings.flow.json"
  OUT=$(cd "$NULL_DIR" && bash -c "$ONBOARDING_BLOCK")
  assert_equal "FLOW_V3_ONBOARDING=needed" "$OUT" "flow.goals=null -> prompt (// empty filter drops null)"
else
  _flow_assert_pass "skip: jq unavailable"
fi


_flow_test_begin "set_flow_goals: refuses to overwrite when jq unavailable + file exists"

# Lift the set_flow_goals body from start.md and verify the cycle-12 fix:
# when the settings file exists but jq is missing, the helper MUST refuse to
# write rather than clobber v2 keys with the heredoc fallback (which would
# regress the cycle-10 fix on jq-less machines).
NOJQ_DIR="$TMP_DIR/set-goals-nojq"
mkdir -p "$NOJQ_DIR/.claude"
echo '{"agentTeams": false, "tiers": {"merge": "confirm"}}' > "$NOJQ_DIR/.claude/settings.flow.json"

SET_FLOW_GOALS_BLOCK='
SETTINGS=.claude/settings.flow.json
# Simulate jq absent by stubbing command -v so it returns false for jq.
# Cannot rely on PATH manipulation because jq lives in multiple locations
# on macOS (/opt/homebrew/bin AND /usr/bin) and trimming PATH risks
# stripping other tools the helper needs. Override `command` via a function
# in the subshell to surgically simulate the jq-missing case.
command() {
  if [ "$1" = "-v" ] && [ "$2" = "jq" ]; then
    return 1
  fi
  builtin command "$@"
}

set_flow_goals() {
  local req="$1" exe="$2"
  if [ -f "$SETTINGS" ] && [ -L "$SETTINGS" ]; then
    echo "ERROR_SYMLINK" >&2; return 1
  fi
  if [ -f "$SETTINGS" ]; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "ERROR_REFUSE_NOJQ" >&2; return 1
    fi
    return 0
  else
    return 0
  fi
}
set_flow_goals true true
echo "EXIT=$?"
'

OUT=$(cd "$NOJQ_DIR" && bash -c "$SET_FLOW_GOALS_BLOCK" 2>&1)
assert_contains "ERROR_REFUSE_NOJQ" "$OUT" "set_flow_goals emits refusal when jq missing + file exists"
assert_contains "EXIT=1" "$OUT" "set_flow_goals returns non-zero in refusal path"

# Sanity: settings file unchanged after refusal
PRESERVED=$(cat "$NOJQ_DIR/.claude/settings.flow.json")
assert_contains "agentTeams" "$PRESERVED" "v2 keys preserved when jq missing (no clobber)"


_flow_test_begin "set_flow_goals: refuses symlinked settings file"

# Symlink defense from cycle-12. .claude as symlink AND settings as symlink.
SYM_DIR="$TMP_DIR/set-goals-symlink"
mkdir -p "$SYM_DIR/.claude"
SYM_TARGET="$TMP_DIR/sym-target-$$.json"
echo '{"hostile": true}' > "$SYM_TARGET"
ln -s "$SYM_TARGET" "$SYM_DIR/.claude/settings.flow.json"

OUT=$(cd "$SYM_DIR" && bash -c "$SET_FLOW_GOALS_BLOCK" 2>&1)
assert_contains "ERROR_SYMLINK" "$OUT" "set_flow_goals refuses symlinked settings file"

# Target unchanged (hostile claim was true; refusal preserves it)
SYM_CONTENT=$(cat "$SYM_TARGET")
assert_contains "hostile" "$SYM_CONTENT" "symlink target unchanged after refusal"


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


_flow_test_begin "partial-settings merge: jq preserves v2 keys when enabling v3"

if command -v jq >/dev/null 2>&1; then
  MERGE_DIR="$TMP_DIR/partial-merge"
  mkdir -p "$MERGE_DIR/.claude"
  echo '{"agentTeams": false, "tiers": {"merge": "confirm"}}' > "$MERGE_DIR/.claude/settings.flow.json"

  # Exercise the actual set_flow_goals semantics from commands/start.md.
  # The helper is markdown-embedded so we lift the jq invocation here. If
  # the markdown changes the merge expression, update this lift too — the
  # alternative (no test) is the cycle-9 pattern we've moved away from.
  (
    cd "$MERGE_DIR"
    SETTINGS=.claude/settings.flow.json
    jq --argjson req true --argjson exe true \
       '.flow.goals.requireGoalForStart = $req | .flow.goals.executeVerificationCommands = $exe' \
       "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  )

  AGENT_TEAMS=$(jq -r '.agentTeams' "$MERGE_DIR/.claude/settings.flow.json")
  TIER_MERGE=$(jq -r '.tiers.merge' "$MERGE_DIR/.claude/settings.flow.json")
  REQ_GOAL=$(jq -r '.flow.goals.requireGoalForStart' "$MERGE_DIR/.claude/settings.flow.json")
  EXE_COMMANDS=$(jq -r '.flow.goals.executeVerificationCommands' "$MERGE_DIR/.claude/settings.flow.json")

  assert_equal "false" "$AGENT_TEAMS" "merge: agentTeams preserved"
  assert_equal "confirm" "$TIER_MERGE" "merge: tiers.merge preserved"
  assert_equal "true" "$REQ_GOAL" "merge: requireGoalForStart written"
  assert_equal "true" "$EXE_COMMANDS" "merge: executeVerificationCommands written"
else
  _flow_assert_pass "skip: jq unavailable — merge requires jq"
fi


_flow_test_begin "Enable v3 arm also writes flow.workflows.enabled (cycle-13 F5)"

# F5: The 'Enable v3' arm in commands/start.md now invokes set_flow_workflows_enabled
# after set_flow_goals. The helper merges flow.workflows.enabled=true into the
# settings file via jq. Triggers stay separate opt-in (the Enable arm doesn't
# touch flow.triggers).

if command -v jq >/dev/null 2>&1; then
  F5_DIR="$TMP_DIR/f5-enable-workflows"
  mkdir -p "$F5_DIR/.claude"
  echo '{"agentTeams": false}' > "$F5_DIR/.claude/settings.flow.json"

  # Step 1: set_flow_goals (simulating the helper from commands/start.md).
  (
    cd "$F5_DIR"
    SETTINGS=.claude/settings.flow.json
    jq --argjson req true --argjson exe true \
       '.flow.goals.requireGoalForStart = $req | .flow.goals.executeVerificationCommands = $exe' \
       "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  )

  # Step 2: set_flow_workflows_enabled (the F5 addition).
  (
    cd "$F5_DIR"
    SETTINGS=.claude/settings.flow.json
    jq --argjson en true '.flow.workflows.enabled = $en' \
       "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  )

  REQ_GOAL=$(jq -r '.flow.goals.requireGoalForStart' "$F5_DIR/.claude/settings.flow.json")
  WORKFLOWS=$(jq -r '.flow.workflows.enabled' "$F5_DIR/.claude/settings.flow.json")
  TRIGGERS=$(jq -r '.flow.triggers // "absent"' "$F5_DIR/.claude/settings.flow.json")
  AGENT_TEAMS=$(jq -r '.agentTeams' "$F5_DIR/.claude/settings.flow.json")

  assert_equal "true" "$REQ_GOAL" "F5: goals.requireGoalForStart still true after both helpers"
  assert_equal "true" "$WORKFLOWS" "F5: workflows.enabled set to true"
  assert_equal "absent" "$TRIGGERS" "F5: triggers section NOT touched (separate opt-in)"
  assert_equal "false" "$AGENT_TEAMS" "F5: v2 keys still preserved"
else
  _flow_assert_pass "skip: jq unavailable — F5 helper requires jq"
fi


_flow_test_begin "Skip arm does NOT touch flow.workflows (F5 preserves user setting)"

# If the user already had flow.workflows.enabled set to a specific value
# (e.g., true from a prior Enable answer that was later disabled by hand),
# choosing 'Skip — keep v2 behavior' must preserve that value, not clobber.

if command -v jq >/dev/null 2>&1; then
  SKIP_DIR="$TMP_DIR/f5-skip-preserves"
  mkdir -p "$SKIP_DIR/.claude"
  echo '{"flow": {"workflows": {"enabled": true}}}' > "$SKIP_DIR/.claude/settings.flow.json"

  # Skip arm: set_flow_goals false false — does NOT call set_flow_workflows_enabled.
  (
    cd "$SKIP_DIR"
    SETTINGS=.claude/settings.flow.json
    jq --argjson req false --argjson exe false \
       '.flow.goals.requireGoalForStart = $req | .flow.goals.executeVerificationCommands = $exe' \
       "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  )

  WORKFLOWS_AFTER=$(jq -r '.flow.workflows.enabled' "$SKIP_DIR/.claude/settings.flow.json")
  REQ_GOAL_AFTER=$(jq -r '.flow.goals.requireGoalForStart' "$SKIP_DIR/.claude/settings.flow.json")

  assert_equal "true" "$WORKFLOWS_AFTER" "F5: Skip preserves pre-existing flow.workflows.enabled=true"
  assert_equal "false" "$REQ_GOAL_AFTER" "F5: Skip writes flow.goals.requireGoalForStart=false"
else
  _flow_assert_pass "skip: jq unavailable — F5 helper requires jq"
fi
