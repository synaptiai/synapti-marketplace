# Tests for #110 v3 integration — FlowRun + FlowGoal wiring in commands/debug.md.
#
# debug is the second goal-creating command (alongside start). It:
#   - creates a FlowRun at entry (workflow=debug), gated by flow.runtime.enabled,
#     forward-referencing the debug FlowGoal id (GOAL_LINK=debug-<ts>).
#   - creates the FlowGoal via goal-contract-capture (reason=debug) AFTER
#     hypothesis confirmation (end of diagnose), with the failure-outcome template.
#   - evaluates the goal via goal-evaluator after VERIFY and transitions the run.
#   - adds a `debug` row to the specification-capture per-invoker scope table.
#
# Prereq: jq. SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
DEBUG_MD="$PLUGIN_DIR/commands/debug.md"
SPEC_SKILL="$PLUGIN_DIR/skills/specification-capture/SKILL.md"

DBG_CLEANUP=()
_dbg_cleanup() { local p; for p in "${DBG_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _dbg_cleanup EXIT

CONTENT=$(cat "$DEBUG_MD")

_flow_test_begin "debug.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=debug" "$CONTENT" "names the debug workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"
assert_match 'preflight . reproduce . diagnose . fix . verify' "$CONTENT" "documents the debug phase order"

_flow_test_begin "debug.md creates the FlowGoal after hypothesis confirmation"
assert_contains "goal-contract-capture" "$CONTENT" "creates a FlowGoal via goal-contract-capture"
assert_match 'invocation reason .debug' "$CONTENT" "uses the debug invocation reason"
assert_contains "reproduced, root-caused" "$CONTENT" "uses the failure-outcome template"
assert_contains "GOAL_LINK" "$CONTENT" "the run forward-references the goal id"

_flow_test_begin "debug.md evaluates the goal + transitions the run after verify"
assert_contains "goal-evaluator" "$CONTENT" "invokes goal-evaluator after verify"
assert_contains "state.status: completed" "$CONTENT" "completes the run when goal achieved"
assert_match 'state.status: blocked' "$CONTENT" "blocks (resumable) when not root-caused"

_flow_test_begin "specification-capture scope table has a debug row"
SPEC=$(cat "$SPEC_SKILL")
assert_contains "commands/debug.md" "$SPEC" "debug invoker row present"
assert_contains "reproducing test" "$SPEC" "AC is the reproducing test"

# --- functional: extract entry block, run under controlled settings
_extract_run_block() {
  awk '/FLOW_RUN_BLOCK_BEGIN/{f=1;next} /FLOW_RUN_BLOCK_END/{f=0} f' "$DEBUG_MD"
}

_flow_test_begin "entry block creates a debug run forward-referencing the goal id"
WORK=$(mktemp -d -t flow-dbg.XXXXXX); DBG_CLEANUP+=("$WORK")
_extract_run_block > "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=debug" "$OUT" "workflow id emitted"
# Validate RUN_ID against run.schema and GOAL_LINK against goal.schema — the
# goal id pattern forbids uppercase, so the forward-referenced goal id must NOT
# reuse the ISO run timestamp (the bug a hand-written regex would have missed).
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
GOAL_LINK=$(printf '%s\n' "$OUT" | grep '^GOAL_LINK=' | cut -d= -f2-)
RUN_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
GOAL_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/goal.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$RUN_PAT"; then _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema"; else _flow_assert_fail "RUN_ID '$RUN_ID' violates /$RUN_PAT/"; fi
if printf '%s' "$GOAL_LINK" | grep -qE "$GOAL_PAT"; then _flow_assert_pass "GOAL_LINK '$GOAL_LINK' conforms to goal.schema (no uppercase)"; else _flow_assert_fail "GOAL_LINK '$GOAL_LINK' violates /$GOAL_PAT/"; fi
assert_contains "debug" "$RUN_ID" "RUN_ID carries the debug slug"

_flow_test_begin "entry block skips when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-dbg2.XXXXXX); DBG_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block > "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"
