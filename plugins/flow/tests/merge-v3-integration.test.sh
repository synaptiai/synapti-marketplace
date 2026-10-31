# Tests for the v3 runtime integration — FlowRun wiring in commands/merge.md.
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

# The merge asks its own question before the merge command runs; the tier
# hook's prompt on that command is a second check, not the only one. Line
# numbers within Phase 3: the first AskUserQuestion, the sentence that gates
# the merge on the answer, and the gh pr merge line the model runs.
_flow_test_begin "merge.md asks with AskUserQuestion before the merge command runs"
_mrg_line() { awk -v pat="$1" '/^## Phase 3/ { p = 1 } /^## Phase 4/ { p = 0 } p && $0 ~ pat { print NR; exit }' "$MERGE_MD"; }
ASK_LINE=$(_mrg_line 'AskUserQuestion')
GATE_LINE=$(_mrg_line 'Only after the user confirms')
RUN_LINE=$(_mrg_line '^gh pr merge ')
if [ -n "$ASK_LINE" ] && [ -n "$GATE_LINE" ] && [ -n "$RUN_LINE" ] \
   && [ "$ASK_LINE" -lt "$GATE_LINE" ] && [ "$GATE_LINE" -lt "$RUN_LINE" ]; then
  _flow_assert_pass "Phase 3: AskUserQuestion (line $ASK_LINE), then the confirmed-only gate (line $GATE_LINE), then gh pr merge (line $RUN_LINE)"
else
  _flow_assert_fail "Phase 3 must ask with AskUserQuestion, then run gh pr merge only after the user confirms (ask='$ASK_LINE' gate='$GATE_LINE' merge='$RUN_LINE')"
fi
assert_not_contains "Do not ask a yes/no question" "$CONTENT" "no instruction to skip the question"
assert_not_contains "does not ask a separate yes/no question" "$CONTENT" "no claim that the command does not ask"
if grep -qE 'gh pr merge` \| 3 \| \*\*Confirm\*\* — asks via `AskUserQuestion`' <<<"$CONTENT"; then
  _flow_assert_pass "the Tier table names the command's own question"
else
  _flow_assert_fail "the Tier table names the command's own question: no Tier table row matches /"'gh pr merge` \| 3 \| \*\*Confirm\*\* — asks via `AskUserQuestion`'"/"
fi
assert_contains "ask_user_to_merge" "$(cat "$PLUGIN_DIR/workflows/merge-pr.workflow.yaml")" "the merge-pr workflow keeps its confirm activity"

# --- functional: extract entry block, run under controlled settings
# _extract_run_block <out file> — the FLOW_RUN_BLOCK block, through assert_block (lib/assert.sh),
# which fails the test when the markers do not pair.
_extract_run_block() {
  assert_block "$MERGE_MD" FLOW_RUN_BLOCK "$1"
}

_flow_test_begin "entry block creates a merge-pr run carrying the PR slug"
WORK=$(mktemp -d -t flow-mrg.XXXXXX); MRG_CLEANUP+=("$WORK")
_extract_run_block "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="113" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=merge-pr" "$OUT" "workflow id emitted"
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
SCHEMA_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$SCHEMA_PAT"; then
  _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema metadata.id pattern"
else
  _flow_assert_fail "RUN_ID '$RUN_ID' violates run.schema pattern /$SCHEMA_PAT/"
fi
assert_contains "merge-pr-113" "$RUN_ID" "RUN_ID carries the PR slug"

_flow_test_begin "entry block skips when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-mrg2.XXXXXX); MRG_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ARGUMENTS="113" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"
