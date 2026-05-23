# Tests for the v3 runtime integration — status Active Triggers section + settings flips.
#
#   - AC6 sub-part: /flow:status surfaces an Active Triggers section reading
#     .flow/triggers/*.trigger.yaml, gated behind flow.triggers.enabled, with a
#     render block in the output template.
#   - AC8: plugin default settings flip flow.workflows.enabled and
#     flow.triggers.enabled to true.
#
# Prereq: jq (for the settings assertions). SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
STATUS_MD="$PLUGIN_DIR/commands/status.md"
SETTINGS="$PLUGIN_DIR/settings.json"

CONTENT=$(cat "$STATUS_MD")

_flow_test_begin "status.md has an Active Triggers section (AC6)"
assert_contains "### Active Triggers" "$CONTENT" "Active Triggers heading present (both reader + render)"
assert_contains ".flow/triggers" "$CONTENT" "reads the triggers directory"
assert_contains "*.trigger.yaml" "$CONTENT" "enumerates trigger yamls"
assert_contains "flow.triggers.enabled" "$CONTENT" "gated behind the triggers flag"
assert_contains "enabled" "$CONTENT" "surfaces the enabled state per trigger (schema-backed metadata.enabled)"
assert_not_contains "state.last_fired" "$CONTENT" "no phantom state.last_fired field (not in the trigger schema)"

_flow_test_begin "status.md triggers reader has a v2 disabled sentinel + symlink defense"
assert_contains "STATE=disabled" "$CONTENT" "v2 mode renders disabled"
assert_contains "symlink rejected" "$CONTENT" "symlink defense on trigger yamls"

_flow_test_begin "settings flip workflows.enabled + triggers.enabled to true (AC8)"
WF=$(jq -r '.flow.workflows.enabled' "$SETTINGS")
TR=$(jq -r '.flow.triggers.enabled' "$SETTINGS")
assert_equal "true" "$WF" "flow.workflows.enabled is true"
assert_equal "true" "$TR" "flow.triggers.enabled is true"

_flow_test_begin "goal-creation default NOT flipped here (owned by the UX layer)"
# The FlowRun integration must NOT introduce a binary requireGoalForStart:true
# default — that migration belongs to the UX layer. Assert the default stays false.
RGS=$(jq -r '.flow.goals.requireGoalForStart' "$SETTINGS")
assert_equal "false" "$RGS" "requireGoalForStart default left false (not flipped by this work)"
