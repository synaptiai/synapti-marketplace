# Tests for the v3 runtime integration — FlowRun wiring in commands/address.md.
#
# Contract under test:
#   - address.md wires a FlowRun at the end of Phase 1 (FLOW_RUN_STATE block,
#     gated by flow.runtime.enabled), invokes Skill(run-state-management),
#     records activities per resolved finding at the categorize→resolve→verify
#     boundaries, captures verification-evidence sidecars via
#     goal-evidence-ledger, and transitions the run to a terminal state.
#   - address is FlowRun-only (no FlowGoal) — the PR's review-thread state is
#     the durable record of feedback resolution.
#   - The entry block (between FLOW_RUN_BLOCK_BEGIN/END) is runnable: it emits
#     FLOW_RUN_STATE=create with RUN_ID + WORKFLOW=address-pr when runtime is
#     enabled, and FLOW_RUN_STATE=skip when flow.runtime.enabled is false.
#
# Prereq: jq (cascade-resolve.sh dependency). SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
ADDRESS_MD="$PLUGIN_DIR/commands/address.md"
CASCADE="$PLUGIN_DIR/bin/cascade-resolve.sh"

ADDR_CLEANUP=()
_addr_cleanup() { local p; for p in "${ADDR_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _addr_cleanup EXIT

CONTENT=$(cat "$ADDRESS_MD")

# --- source-presence: FlowRun wiring
_flow_test_begin "address.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=address-pr" "$CONTENT" "names the address-pr workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"

_flow_test_begin "address.md records activities at phase boundaries"
assert_contains "FlowActivity writes" "$CONTENT" "activity-write step documented"
assert_match 'preflight . categorize . resolve . verify' "$CONTENT" "documents the address phase order"
assert_contains "goal-evidence-ledger" "$CONTENT" "captures verification-evidence sidecar"

_flow_test_begin "address.md transitions the FlowRun to terminal state"
assert_contains "FlowRun terminal transition" "$CONTENT" "terminal-transition step documented"
assert_contains "state.status: completed" "$CONTENT" "completes the run on success"
assert_contains "cancelled" "$CONTENT" "cancels the run on failure (not left resumable)"

_flow_test_begin "address is FlowRun-only (no FlowGoal)"
assert_not_contains "goal-contract-capture" "$CONTENT" "address does not create a FlowGoal"
assert_contains "creates NO FlowGoal" "$CONTENT" "documents address is FlowRun-only"

# --- functional: extract the entry block and run it under controlled settings
_extract_run_block() {
  awk '/FLOW_RUN_BLOCK_BEGIN/{f=1;next} /FLOW_RUN_BLOCK_END/{f=0} f' "$ADDRESS_MD"
}

_flow_test_begin "entry block emits FLOW_RUN_STATE=create when runtime enabled (default)"
WORK=$(mktemp -d -t flow-addr.XXXXXX); ADDR_CLEANUP+=("$WORK")
_extract_run_block > "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=address-pr" "$OUT" "workflow id emitted"
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
SCHEMA_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$SCHEMA_PAT"; then _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema"; else _flow_assert_fail "RUN_ID '$RUN_ID' violates /$SCHEMA_PAT/"; fi
assert_contains "address" "$RUN_ID" "RUN_ID carries the address slug"

_flow_test_begin "entry block emits FLOW_RUN_STATE=skip when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-addr2.XXXXXX); ADDR_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block > "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip (no-op for v2 projects)"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"

# --- finding-dismissed: a rejected finding is recorded, not just replied to ---
# A Pushback is the one disposition where a human states grounds for rejecting a
# finding. Replying in the thread and moving on teaches nothing: the same finding
# comes back next cycle. The artifact is what /flow:learn clusters on.
SCHEMA_MD="$PLUGIN_DIR/references/decision-journal-schema.md"
SCHEMA=$(cat "$SCHEMA_MD")

_flow_test_begin "decision-journal-schema documents finding-dismissed"
assert_contains "| \`finding-dismissed\` |" "$SCHEMA" "the artifact type has a table row"
for F in "pr: <int>" "cycle: <int>" "finding_id: <string>" "category: <string>" "location: <string>" "by: address" "evidence: <string>"; do
  assert_contains "$F" "$SCHEMA" "the row names the $F field"
done

_flow_test_begin "the finding-dismissed reason vocabulary is a closed set"
# Free text clusters with nothing, which is the whole point of recording it.
for R in factually-incorrect breaks-test contradicts-claude-md critic-evidence critic-unrefuted-concern self-review-refuted; do
  assert_contains "\`$R\`" "$SCHEMA" "reason '$R' is documented"
done
assert_contains "closed set" "$SCHEMA" "the schema says the set is closed"
# Each reason has to say what evidence the emitter records, or the closed set is
# a vocabulary with no teeth.
assert_match 'Evidence the emitter must record' "$SCHEMA" "each reason names its required evidence"
# dropped-finding and finding-dismissed are different records; conflating them
# would let a consolidation loss read as a team decision.
assert_match 'different records and both are kept' "$SCHEMA" "the two artifact types are distinguished"

_flow_test_begin "address.md Phase 3 emits finding-dismissed for a Pushback"
assert_contains "finding-dismissed" "$CONTENT" "address.md names the artifact type"
assert_contains "FINDING_DISMISSED_BLOCK_BEGIN" "$CONTENT" "the emit is an extractable block"
assert_contains "FINDING_DISMISSED_BLOCK_END" "$CONTENT" "the block is delimited"

_flow_test_begin "address.md Phase 1 parses the review-cycle markers"
# Without the ledger ids a dismissal can only be keyed to a GitHub comment id,
# which is not stable across cycles and joins to nothing.
assert_contains "FLOW_REVIEW_CYCLE" "$CONTENT" "address.md reads the review-cycle markers"
assert_contains "finding-ledger-parser" "$CONTENT" "and cites the canonical parser"

_flow_test_begin "address.md Phase 3 fills the DISPUTED array"
# The array already exists in templates/resolution-comment.md and /flow:merge
# already gates on it; nothing filled it.
assert_contains "DISPUTED" "$CONTENT" "address.md names the DISPUTED array"

# --- functional: the emit block writes the artifact with the right fields
_extract_dismissed_block() {
  awk '/# FINDING_DISMISSED_BLOCK_BEGIN/{f=1;next} /# FINDING_DISMISSED_BLOCK_END/{f=0} f' "$ADDRESS_MD"
}

_flow_test_begin "the finding-dismissed block records every field"
WORK3=$(mktemp -d -t flow-addr3.XXXXXX); ADDR_CLEANUP+=("$WORK3")
mkdir -p "$WORK3/.decisions"
_extract_dismissed_block > "$WORK3/dismiss.sh"
if [ ! -s "$WORK3/dismiss.sh" ]; then
  _flow_assert_fail "FINDING_DISMISSED_BLOCK extracted empty — the block does not exist yet"
else
  OUT3=$(cd "$WORK3" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    ISSUE=214 PR_NUM=7 CYCLE_NUMBER=2 FINDING_ID=F3 CATEGORY=correctness \
    LOCATION="plugins/flow/bin/x.sh:42" REASON=breaks-test \
    EVIDENCE="tests/x.test.sh::asserts the guard fires" \
    bash dismiss.sh 2>&1)
  ART=$(cd "$WORK3" && python3 -c "
import yaml
d=yaml.safe_load(open('.decisions/issue-214.md').read().split('---')[1])
a=[x for x in (d.get('artifacts') or []) if x.get('type')=='finding-dismissed']
print(a[-1] if a else 'NONE')
" 2>/dev/null)
  assert_not_contains "NONE" "$ART" "an artifact was written"
  assert_contains "'finding_id': 'F3'" "$ART" "the ledger id is recorded, not a comment id"
  assert_contains "'reason': 'breaks-test'" "$ART" "the reason is recorded"
  assert_contains "'by': 'address'" "$ART" "the emitting command is recorded"
  assert_contains "'category': 'correctness'" "$ART" "the category is recorded"
  assert_contains "x.sh:42" "$ART" "the location is recorded"
  assert_contains "asserts the guard fires" "$ART" "the evidence is recorded"
fi

_flow_test_begin "the finding-dismissed block refuses a reason outside the closed set"
WORK4=$(mktemp -d -t flow-addr4.XXXXXX); ADDR_CLEANUP+=("$WORK4")
mkdir -p "$WORK4/.decisions"
_extract_dismissed_block > "$WORK4/dismiss.sh"
if [ ! -s "$WORK4/dismiss.sh" ]; then
  _flow_assert_fail "FINDING_DISMISSED_BLOCK extracted empty — the block does not exist yet"
else
  OUT4=$(cd "$WORK4" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    ISSUE=214 PR_NUM=7 CYCLE_NUMBER=2 FINDING_ID=F3 CATEGORY=correctness \
    LOCATION="a.sh:1" REASON=i-just-disagree EVIDENCE="none" \
    bash dismiss.sh 2>&1); RC4=$?
  if [ "$RC4" -ne 0 ]; then
    _flow_assert_pass "a reason outside the closed set is refused (exit $RC4)"
  else
    _flow_assert_fail "an arbitrary reason was accepted; the closed set is not enforced"
  fi
  assert_match 'i-just-disagree|reason' "$OUT4" "the refusal names what was wrong"
  COUNT=$(cd "$WORK4" && grep -c 'finding-dismissed' .decisions/issue-214.md 2>/dev/null || echo 0)
  assert_equal "0" "$COUNT" "and nothing was written"
fi
