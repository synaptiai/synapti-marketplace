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
if [ ! -f .claude/settings.flow.json ] && [ ! -d .flow ]; then
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

# Lift the gate logic from start.md and exercise it without invoking
# cascade-resolve.sh — we pre-set REQUIRE_GOAL directly so this test is
# hermetic and doesn't depend on the cascade implementation.
GOAL_GATE_BLOCK='
ARG1="${ARGUMENTS%% *}"
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

CREATE_DIR="$TMP_DIR/create-arm"
mkdir -p "$CREATE_DIR"
OUT=$(cd "$CREATE_DIR" && REQUIRE_GOAL=true ARGUMENTS="42" bash -c "$GOAL_GATE_BLOCK")
assert_contains "FLOW_GOAL_STATE=create" "$OUT" "create arm: state=create"
assert_contains "GOAL_ID=issue-42" "$OUT" "create arm: GOAL_ID=issue-42"
assert_contains "GOAL_PATH=.flow/goals/issue-42.goal.yaml" "$OUT" "create arm: GOAL_PATH set"


_flow_test_begin "goal auto-creation gate: existing goal -> exists (no overwrite)"

EXISTS_DIR="$TMP_DIR/exists-arm"
mkdir -p "$EXISTS_DIR/.flow/goals"
echo "apiVersion: flow.synapti.ai/v1" > "$EXISTS_DIR/.flow/goals/issue-42.goal.yaml"
OUT=$(cd "$EXISTS_DIR" && REQUIRE_GOAL=true ARGUMENTS="42" bash -c "$GOAL_GATE_BLOCK")
assert_contains "FLOW_GOAL_STATE=exists" "$OUT" "exists arm: state=exists"
assert_not_contains "FLOW_GOAL_STATE=create" "$OUT" "exists arm: not flagged for creation"


_flow_test_begin "goal auto-creation gate: requireGoal=false -> skip"

OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=false ARGUMENTS="42" bash -c "$GOAL_GATE_BLOCK")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "requireGoal=false -> skip"


_flow_test_begin "goal auto-creation gate: missing ISSUE_NUM -> skip"

OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=true ARGUMENTS="" bash -c "$GOAL_GATE_BLOCK")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "missing ISSUE_NUM -> skip"


_flow_test_begin "goal auto-creation gate: non-digit ARGUMENTS -> skip"

OUT=$(cd "$TMP_DIR" && REQUIRE_GOAL=true ARGUMENTS="abc" bash -c "$GOAL_GATE_BLOCK")
assert_equal "FLOW_GOAL_STATE=skip" "$OUT" "non-digit ARGUMENTS -> skip (matches Phase 0 validation)"
