# Tests for the v3 runtime integration — FlowRun wiring in commands/release.md.
#
# Contract under test:
#   - release.md wires a FlowRun at entry (FLOW_RUN_STATE block, gated by
#     flow.runtime.enabled), invokes Skill(run-state-management), records
#     activities at the preflight→bump→release_pr (first run) and
#     preflight→tag (second run) boundaries, and transitions
#     the run to a terminal state in Phase 5.
#   - release is FlowRun-only (no FlowGoal) — it is not goal-bound.
#   - The entry block (between FLOW_RUN_BLOCK_BEGIN/END) is runnable: it emits
#     FLOW_RUN_STATE=create with RUN_ID + WORKFLOW=release when runtime is
#     enabled, and FLOW_RUN_STATE=skip when flow.runtime.enabled is false.
#
# Prereq: jq (cascade-resolve.sh dependency). SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
RELEASE_MD="$PLUGIN_DIR/commands/release.md"
CASCADE="$PLUGIN_DIR/bin/cascade-resolve.sh"

REL_CLEANUP=()
_rel_cleanup() { local p; for p in "${REL_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _rel_cleanup EXIT

CONTENT=$(cat "$RELEASE_MD")

# --- source-presence: FlowRun wiring
_flow_test_begin "release.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=release" "$CONTENT" "names the release workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"

_flow_test_begin "release.md records activities at phase boundaries"
assert_contains "FlowActivity writes" "$CONTENT" "activity-write step documented"
assert_match 'preflight . bump . release_pr' "$CONTENT" "documents the first run's phase order (matches workflow yaml)"
assert_match 'preflight . tag' "$CONTENT" "documents the second run's phase order (matches workflow yaml)"
WF_PHASES=$(python3 -c 'import sys, yaml; print(" ".join(p["id"] for p in yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["phases"]))' "$PLUGIN_DIR/workflows/release.workflow.yaml")
assert_equal "preflight bump release_pr tag" "$WF_PHASES" "release.workflow.yaml phases"
assert_contains "ask_user_to_release" "$(cat "$PLUGIN_DIR/workflows/release.workflow.yaml")" "the workflow records the AskUserQuestion confirmation before the tag phase acts"

# The release asks its own question before the tag, the tag push and the
# release are created, and before the release for a tag already on origin.
# The release pull request run creates nothing that needs Tier 3, so it does
# not ask.
# _rel_section_line <section label> <pattern>: the first line matching the
# pattern inside the Phase 4 section headed ### `RELEASE_RUN=<label>`.
_rel_section_line() {
  awk -v head="### \`RELEASE_RUN=$1\`" -v pat="$2" '
    /^### / { p = (index($0, head) == 1) }
    /^## / { p = 0 }
    p && $0 ~ pat { print NR; exit }' "$RELEASE_MD"
}
_rel_asks_before() {
  local label="$1" fence="$2" ask gate run
  ask=$(_rel_section_line "$label" 'AskUserQuestion')
  gate=$(_rel_section_line "$label" 'Only after the user confirms')
  run=$(_rel_section_line "$label" "$fence")
  if [ -n "$ask" ] && [ -n "$gate" ] && [ -n "$run" ] && [ "$ask" -lt "$gate" ] && [ "$gate" -lt "$run" ]; then
    _flow_assert_pass "RELEASE_RUN=$label: AskUserQuestion (line $ask), then the confirmed-only gate (line $gate), then the block (line $run)"
  else
    _flow_assert_fail "RELEASE_RUN=$label must ask with AskUserQuestion and run its block only after the user confirms (ask='$ask' gate='$gate' block='$run')"
  fi
}

_flow_test_begin "release.md asks with AskUserQuestion before tagging and before publishing"
_rel_asks_before tag '^# RELEASE_TAG_BLOCK_BEGIN'
_rel_asks_before publish '^gh release create '
PR_ASK=$(_rel_section_line pr 'AskUserQuestion')
PR_FENCE=$(_rel_section_line pr '^# RELEASE_PR_BLOCK_BEGIN')
if [ -n "$PR_FENCE" ] && [ -z "$PR_ASK" ]; then
  _flow_assert_pass "RELEASE_RUN=pr: the release pull request run does not ask (Tier 2 only)"
else
  _flow_assert_fail "RELEASE_RUN=pr: expected its block and no AskUserQuestion (block='$PR_FENCE' ask='$PR_ASK')"
fi
assert_not_contains "this is not a question" "$CONTENT" "the preview no longer says no question follows"
if grep -qE 'git push origin <tag>` \| 3 \| \*\*Confirm\*\* — asks via `AskUserQuestion`' <<<"$CONTENT"; then
  _flow_assert_pass "the Tier table names the command's own question for the tag push"
else
  _flow_assert_fail "the Tier table names the command's own question for the tag push: no Tier table row matches /"'git push origin <tag>` \| 3 \| \*\*Confirm\*\* — asks via `AskUserQuestion`'"/"
fi

_flow_test_begin "release.md transitions the FlowRun to terminal state"
assert_contains "FlowRun terminal transition" "$CONTENT" "terminal-transition step documented"
assert_contains "state.status: completed" "$CONTENT" "completes the run on success"
assert_contains "cancelled" "$CONTENT" "cancels the run on failure (not left resumable)"

_flow_test_begin "release is FlowRun-only (no FlowGoal)"
assert_not_contains "goal-contract-capture" "$CONTENT" "release does not create a FlowGoal"
assert_contains "goal=" "$CONTENT" "documents goal linkage is null (release is not goal-bound)"

# --- functional: extract the entry block and run it under controlled settings
# _extract_run_block <out file> — the FLOW_RUN_BLOCK block, through assert_block (lib/assert.sh),
# which fails the test when the markers do not pair.
_extract_run_block() {
  assert_block "$RELEASE_MD" FLOW_RUN_BLOCK "$1"
}

_flow_test_begin "entry block emits FLOW_RUN_STATE=create when runtime enabled (default)"
WORK=$(mktemp -d -t flow-rel.XXXXXX); REL_CLEANUP+=("$WORK")
_extract_run_block "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=release" "$OUT" "workflow id emitted"
# Validate the emitted RUN_ID against the ACTUAL run.schema.json metadata.id
# pattern (not just a hand-written regex) — guards against id-format drift.
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
SCHEMA_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$SCHEMA_PAT"; then
  _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema metadata.id pattern"
else
  _flow_assert_fail "RUN_ID '$RUN_ID' violates run.schema pattern /$SCHEMA_PAT/"
fi

_flow_test_begin "entry block emits FLOW_RUN_STATE=skip when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-rel2.XXXXXX); REL_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip (no-op for v2 projects)"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"
