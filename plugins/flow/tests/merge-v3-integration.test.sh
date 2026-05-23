# Tests for #110 v3 integration — FlowRun wiring in commands/merge.md.
#
# The FlowGoal gate (block on lifecycle != achieved) already exists; this file
# covers the NEW FlowRun layer + the AC5 contract:
#   - merge.md creates a FlowRun at entry (workflow=merge-pr), gated by
#     flow.runtime.enabled, delegating to run-state-management.
#   - It verifies every linked FlowRun is completed before merge, with NO
#     override (Tier 3) — distinct from pr.md's overridable gate (AC5 vs AC4).
#   - It transitions the run + linked goal to terminal after a successful merge.
#
# Prereq: jq. SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
MERGE_MD="$PLUGIN_DIR/commands/merge.md"

MRG_CLEANUP=()
_mrg_cleanup() { local p; for p in "${MRG_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _mrg_cleanup EXIT

CONTENT=$(cat "$MERGE_MD")

_flow_test_begin "merge.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=merge-pr" "$CONTENT" "names the merge-pr workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"
assert_match 'preflight . verify . confirm . merge' "$CONTENT" "documents the merge phase order"

_flow_test_begin "merge.md verifies linked FlowRuns are completed (AC5, no override)"
assert_contains "Linked-run completion check" "$CONTENT" "linked-run check documented"
assert_contains "no override" "$CONTENT" "Tier 3 — no override beyond confirmation"
assert_match 'state.status: completed' "$CONTENT" "requires linked runs completed"

_flow_test_begin "merge.md transitions run + goal to terminal after merge"
assert_contains "FlowRun terminal transition" "$CONTENT" "terminal-transition step documented"
assert_contains "status=completed" "$CONTENT" "updates workflow-run artifact to completed"
assert_contains "cancelled" "$CONTENT" "cancels the run on aborted merge (not left resumable)"

# --- functional: extract entry block, run under controlled settings
_extract_run_block() {
  awk '/FLOW_RUN_BLOCK_BEGIN/{f=1;next} /FLOW_RUN_BLOCK_END/{f=0} f' "$MERGE_MD"
}

_flow_test_begin "entry block creates a merge-pr run carrying the PR slug"
WORK=$(mktemp -d -t flow-mrg.XXXXXX); MRG_CLEANUP+=("$WORK")
_extract_run_block > "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="113" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=merge-pr" "$OUT" "workflow id emitted"
assert_match 'RUN_ID=[0-9]{8}T[0-9]{6}Z-merge-pr-113' "$OUT" "RUN_ID carries the PR slug"

_flow_test_begin "entry block skips when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-mrg2.XXXXXX); MRG_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block > "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="113" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"
