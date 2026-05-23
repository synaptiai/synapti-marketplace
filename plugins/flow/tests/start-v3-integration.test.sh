# Tests for #110 v3 integration — FlowRun wiring in commands/start.md.
#
# FlowGoal creation in start.md already exists (gated on requireGoalForStart)
# and is covered elsewhere. This file covers only the NEW FlowRun layer:
#   - start.md creates a FlowRun at entry (workflow=start-issue), linked to the
#     FlowGoal, gated by flow.runtime.enabled, delegating to run-state-management.
#   - It emits a workflow-run journal artifact (start is issue-scoped).
#   - It writes activities at explore/plan/code/verify boundaries and transitions
#     the run to a terminal state after the verdict.
#   - The entry block is runnable and links the goal: ARGUMENTS=<issue> →
#     GOAL_LINK=issue-<n>; no issue → GOAL_LINK=null; runtime off → skip.
#
# Prereq: jq. SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
START_MD="$PLUGIN_DIR/commands/start.md"

START_CLEANUP=()
_start_cleanup() { local p; for p in "${START_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _start_cleanup EXIT

CONTENT=$(cat "$START_MD")

_flow_test_begin "start.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=start-issue" "$CONTENT" "names the start-issue workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"

_flow_test_begin "start.md links the FlowRun to the FlowGoal"
assert_contains "GOAL_LINK" "$CONTENT" "computes goal linkage"
assert_match 'goal=.{1,2}GOAL_LINK' "$CONTENT" "passes the goal link to run-state-management"

_flow_test_begin "start.md emits a workflow-run journal artifact"
assert_contains "--type workflow-run" "$CONTENT" "emits workflow-run artifact"
assert_contains "workflow=start-issue" "$CONTENT" "artifact names the workflow"
assert_match 'status=active' "$CONTENT" "artifact records active status at entry"

_flow_test_begin "start.md records activities + terminal transition"
assert_match 'preflight . explore . plan . code . verify' "$CONTENT" "documents the start phase order"
assert_contains "state.status: completed" "$CONTENT" "completes the run on PASS verdict"
assert_match 'state.status: blocked' "$CONTENT" "blocks (resumable) on FAIL/session-end"

# --- functional: extract entry block, run with controlled ARGUMENTS + settings
_extract_run_block() {
  awk '/FLOW_RUN_BLOCK_BEGIN/{f=1;next} /FLOW_RUN_BLOCK_END/{f=0} f' "$START_MD"
}

_flow_test_begin "entry block creates + links goal when given an issue number"
WORK=$(mktemp -d -t flow-start.XXXXXX); START_CLEANUP+=("$WORK")
_extract_run_block > "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="110" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "issue arg → create"
assert_contains "WORKFLOW=start-issue" "$OUT" "workflow id emitted"
assert_contains "GOAL_LINK=issue-110" "$OUT" "goal linked to issue-110"
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
SCHEMA_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$SCHEMA_PAT"; then
  _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema metadata.id pattern"
else
  _flow_assert_fail "RUN_ID '$RUN_ID' violates run.schema pattern /$SCHEMA_PAT/"
fi
assert_contains "issue-110" "$RUN_ID" "RUN_ID carries the issue slug"

_flow_test_begin "entry block links goal=null when no issue number"
OUT_NO=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="" bash block.sh 2>/dev/null)
assert_contains "GOAL_LINK=null" "$OUT_NO" "no issue → null goal link"

_flow_test_begin "entry block skips when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-start2.XXXXXX); START_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block > "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="110" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"
