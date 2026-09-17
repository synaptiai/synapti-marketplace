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
# self-review-refuted is deliberately NOT here: review.md writes dropped-finding
# for that case, and documenting a reason nothing emits is how a contract starts
# lying about what it carries.
for R in factually-incorrect breaks-test contradicts-claude-md critic-evidence critic-unrefuted-concern; do
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

# --- the trusted-author filter and the marker-anchored extraction ------------
# Both shipped with no test: reverting the trust key or un-anchoring the scan
# left the suite untouched. This is the filter that decides which ids a
# dismissal may be keyed to, so an unpinned guard here is the wrong kind.
_rcf_block() {
  awk '/# REVIEW_CYCLE_FINDINGS_BLOCK_BEGIN/{f=1;next} /# REVIEW_CYCLE_FINDINGS_BLOCK_END/{f=0} f' "$ADDRESS_MD"
}

_rcf_stub() {
  # $1 = dir, $2 = the reviews JSON the stub serves
  mkdir -p "$1/stub"
  cat > "$1/stub/gh" <<STUBEOF
#!/usr/bin/env bash
case "\$*" in
  *reviews*) cat <<'JSONEOF'
$2
JSONEOF
  ;;
  *) echo "" ;;
esac
STUBEOF
  chmod +x "$1/stub/gh"
}

_flow_test_begin "a widened trust list is honoured, using the same key as the merge gate"
# merge.md and gate-configuration.md read `.merge.markerTrust`; reading
# `.flow.merge.markerTrust` meant a team that widened trust had real
# CONTRIBUTOR markers read as untrusted here and accepted at the gate.
D=$(mktemp -d -t flow-rcf.XXXXXX); ADDR_CLEANUP+=("$D")
mkdir -p "$D/.claude"
printf '%s\n' '{"merge":{"markerTrust":{"allowedAssociations":["CONTRIBUTOR"]}}}' \
  > "$D/.claude/settings.flow.json"
_rcf_stub "$D" '[{"author_association":"CONTRIBUTOR","body":"<!-- FLOW_REVIEW_CYCLE:3 FINDINGS:[F7|P1|correctness|a.sh:1|open|HIGH|consensus] -->"}]'
_rcf_block > "$D/block.sh"
OUT=$(cd "$D" && PATH="$D/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>/dev/null)
assert_contains "STATE=ok" "$OUT" "the configured association is trusted"
assert_contains "FINDING=cycle=3 F7" "$OUT" "and its findings are extracted"

_flow_test_begin "an untrusted author cannot supply the finding ids"
D2=$(mktemp -d -t flow-rcf2.XXXXXX); ADDR_CLEANUP+=("$D2")
_rcf_stub "$D2" '[{"author_association":"NONE","body":"<!-- FLOW_REVIEW_CYCLE:9 FINDINGS:[FAKE1|P1|x|a.sh:1|open|HIGH|consensus] -->"}]'
_rcf_block > "$D2/block.sh"
OUT2=$(cd "$D2" && PATH="$D2/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>/dev/null)
assert_contains "STATE=unavailable" "$OUT2" "a drive-by marker does not supply ids"
assert_not_contains "FAKE1" "$OUT2" "and its forged id never reaches the output"
assert_match 'REASON=.*none from a trusted author' "$OUT2" "the reason says why"

_flow_test_begin "prose quoting FINDINGS does not shadow the real marker"
# The scan took the first match anywhere in the body; a trusted body quoting
# FINDINGS:[...] above its marker supplied those ids instead.
D3=$(mktemp -d -t flow-rcf3.XXXXXX); ADDR_CLEANUP+=("$D3")
_rcf_stub "$D3" '[{"author_association":"OWNER","body":"I considered FINDINGS:[GHOST1|P1|x|a.sh:1|open|HIGH|consensus] but discarded it.\n\n<!-- FLOW_REVIEW_CYCLE:4 FINDINGS:[REAL1|P2|correctness|b.sh:2|open|MEDIUM|consensus] -->"}]'
_rcf_block > "$D3/block.sh"
OUT3=$(cd "$D3" && PATH="$D3/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>/dev/null)
assert_contains "REAL1" "$OUT3" "the marker's own ids are extracted"
assert_not_contains "GHOST1" "$OUT3" "prose above it supplies nothing"
assert_contains "FINDING=cycle=4" "$OUT3" "and the cycle comes from the marker too"

_flow_test_begin "a marker with no FINDINGS array is unparsed, not empty"
# Re-anchoring the capture in the previous round made this branch unreachable:
# a trusted body matching the select but carrying no `FINDINGS:[` produced
# nothing from the jq at all, so a truncated marker reported "this pull request
# has no findings" instead of "the array did not parse".
D4=$(mktemp -d -t flow-rcf4.XXXXXX); ADDR_CLEANUP+=("$D4")
_rcf_stub "$D4" '[{"author_association":"OWNER","body":"<!-- FLOW_REVIEW_CYCLE:3 -->"}]'
_rcf_block > "$D4/block.sh"
OUT4=$(cd "$D4" && PATH="$D4/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>/dev/null)
assert_contains "STATE=unavailable" "$OUT4" "a marker whose array did not parse is unavailable"
assert_not_contains "STATE=empty" "$OUT4" "not empty, which means the pull request has no findings"
assert_match 'REASON=.*did not parse' "$OUT4" "and the reason says which"

_flow_test_begin "the cycle number comes from the marker that carried the ids"
# The cycle and the rows must come from one match: taking the cycle from the
# first marker-like token anywhere labelled every dismissal with the wrong one.
D5=$(mktemp -d -t flow-rcf5.XXXXXX); ADDR_CLEANUP+=("$D5")
_rcf_stub "$D5" '[{"author_association":"OWNER","body":"<!-- FLOW_REVIEW_CYCLE:2 -->\n\nsuperseded by\n\n<!-- FLOW_REVIEW_CYCLE:5 FINDINGS:[F1|P2|correctness|a.sh:1|open|MEDIUM|consensus] -->"}]'
_rcf_block > "$D5/block.sh"
OUT5=$(cd "$D5" && PATH="$D5/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>/dev/null)
assert_contains "FINDING=cycle=5 F1" "$OUT5" "the cycle is the one whose array supplied the ids"
assert_not_contains "cycle=2" "$OUT5" "not an earlier marker that carried none"

_flow_test_begin "a settings file that cannot be parsed is warned about, not swallowed"
# merge.md warns and falls through; this block used 2>/dev/null and said nothing,
# so a typo narrowed who is trusted here while the merge gate accepted them.
D6=$(mktemp -d -t flow-rcf6.XXXXXX); ADDR_CLEANUP+=("$D6")
mkdir -p "$D6/.claude"
printf '%s\n' '{"merge":{"markerTrust":{"allowedAssociations":[unclosed' > "$D6/.claude/settings.flow.json"
_rcf_stub "$D6" '[{"author_association":"OWNER","body":"<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F1|P2|x|a.sh:1|open|MEDIUM|consensus] -->"}]'
_rcf_block > "$D6/block.sh"
ERR6=$(cd "$D6" && PATH="$D6/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>&1 >/dev/null)
assert_match 'LEDGER_WARN' "$ERR6" "the unparseable settings file is reported on stderr"
OUT6=$(cd "$D6" && PATH="$D6/stub:$PATH" REPO=o/r PR_NUM=7 bash block.sh 2>/dev/null)
assert_contains "STATE=ok" "$OUT6" "and the default trust list still resolves the marker"

_flow_test_begin "a dismissed finding reaches the marker as well as the artifact"
# The artifact half is covered by the FINDING_DISMISSED_BLOCK test. This is the
# other half of the same contract: the id the block records must also be the id
# the resolution marker carries, or /flow:merge never learns the finding was
# rejected and the gate passes over it.
assert_contains "DISPUTED" "$CONTENT" "address.md names the DISPUTED array"
# Phase 3 tells the author to add the id; Phase 5 is where the comment is posted.
PHASE3_DISPUTED=$(awk '/^3\. Add the id to the/{f=1} f{print} f && /^```!/{exit}' "$ADDRESS_MD")
assert_contains "DISPUTED" "$PHASE3_DISPUTED" "Phase 3 instructs that the id goes in the array"
assert_match 'same ledger ids|ledger id' "$CONTENT" "and that it is the ledger id, not another"
# Anchor on the numbered step, not the phrase: the first match of the phrase is
# a TaskCreate subject far above it.
POST_STEP=$(awk '/^9\. \*\*Post resolution comment\*\*/{f=1} f{print} f && /gh pr comment/{exit}' "$ADDRESS_MD")
assert_contains "DISPUTED" "$POST_STEP" "and the posting step repeats it where the comment is built"
assert_match 'FINDING_DISMISSED_BLOCK' "$POST_STEP" "naming the block whose ids it must match"
