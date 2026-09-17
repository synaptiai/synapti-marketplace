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
# Phase 3 points at the emitter rather than asking for a hand copy; Phase 5 is
# where the comment is posted.
PHASE3_DISPUTED=$(awk '/^3\. The id reaches the/{f=1} f{print} f && /^```!/{exit}' "$ADDRESS_MD")
assert_contains "DISPUTED" "$PHASE3_DISPUTED" "Phase 3 instructs that the id goes in the array"
assert_contains "DISPUTED_ARRAY_BLOCK" "$PHASE3_DISPUTED" "naming the block that carries it there"
assert_match 'do not transcribe|not transcribed' "$PHASE3_DISPUTED" "and saying not to copy it by hand"
assert_match 'same ledger ids|ledger id' "$CONTENT" "and that it is the ledger id, not another"
# Anchor on the numbered step, not the phrase: the first match of the phrase is
# a TaskCreate subject far above it.
POST_STEP=$(awk '/^9\. \*\*Post resolution comment\*\*/{f=1} f{print} f && /gh pr comment/{exit}' "$ADDRESS_MD")
assert_contains "DISPUTED" "$POST_STEP" "and the posting step repeats it where the comment is built"
# The posting step no longer names the WRITER block, because it no longer asks
# anyone to copy ids across from it. It names the EMITTER, which derives the
# array from the artifacts that block wrote.
assert_match 'DISPUTED_ARRAY_BLOCK' "$POST_STEP" "naming the block that builds the array it posts"
assert_match 'finding-dismissed' "$POST_STEP" "and the artifacts the array is derived from"

# --- the artifact and the marker carry the same id ---------------------------
# AC2 asks that a dismissed finding reach BOTH surfaces with the same id. That
# was unassertable while the DISPUTED array was composed by hand in the comment
# body: nothing could run, so nothing could fail. The array is now emitted from
# the artifacts, and these tests run the writer and the emitter against one
# journal in one sandbox.
_extract_disputed_block() {
  awk '/# DISPUTED_ARRAY_BLOCK_BEGIN/{f=1;next} /# DISPUTED_ARRAY_BLOCK_END/{f=0} f' "$ADDRESS_MD"
}

_flow_test_begin "a dismissed finding reaches the artifact and the marker with the same id"
WORKD=$(mktemp -d -t flow-disp.XXXXXX); ADDR_CLEANUP+=("$WORKD")
mkdir -p "$WORKD/.decisions"
_extract_dismissed_block > "$WORKD/dismiss.sh"
_extract_disputed_block > "$WORKD/disputed.sh"
if [ ! -s "$WORKD/disputed.sh" ]; then
  _flow_assert_fail "DISPUTED_ARRAY_BLOCK extracted empty — the emitter does not exist"
else
  # pr, cycle and finding_id are all different values, so an emitter that read
  # the wrong field prints a visibly wrong array rather than an accidental match.
  ( cd "$WORKD" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
      ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID=F3 CATEGORY=correctness \
      LOCATION="plugins/flow/bin/x.sh:42" REASON=breaks-test \
      EVIDENCE="tests/x.test.sh::asserts the guard fires" \
      bash dismiss.sh >/dev/null 2>&1 )
  MANIFEST=$(cd "$WORKD" && python3 -c "
import yaml
d=yaml.safe_load(open('.decisions/issue-214.md').read().split('---')[1])
a=[x for x in (d.get('artifacts') or []) if x.get('type')=='finding-dismissed']
print(a[-1] if a else 'NONE')
" 2>/dev/null)
  DOUT=$(cd "$WORKD" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    ISSUE=214 PR_NUM=234 JOURNAL_DIR=.decisions bash disputed.sh 2>&1)
  # Both halves of the conjunction, asserted on one run of one id.
  assert_contains "'finding_id': 'F3'" "$MANIFEST" "the artifact carries the ledger id"
  assert_contains "DISPUTED_STATE=ok" "$DOUT" "the emitter built an array"
  assert_contains "DISPUTED=[F3]" "$DOUT" "and the marker carries the same id"
  # The discriminators: neither the pull request number nor the cycle is the id.
  assert_not_contains "DISPUTED=[234]" "$DOUT" "the array is not the pull request number"
  assert_not_contains "DISPUTED=[3]" "$DOUT" "the array is not the cycle number"
fi

_flow_test_begin "the array is cumulative over the pull request, not just this cycle"
# Both consumers in references/finding-ledger-parser.md take `| last`: the newest
# resolution comment is read as the complete disposition. A cycle filter would
# drop a cycle-2 dismissal from the cycle-3 marker and reclassify it as
# in_fix_forward.
WORKE=$(mktemp -d -t flow-disp2.XXXXXX); ADDR_CLEANUP+=("$WORKE")
mkdir -p "$WORKE/.decisions"
_extract_dismissed_block > "$WORKE/dismiss.sh"
_extract_disputed_block > "$WORKE/disputed.sh"
_dismiss_one() {
  ( cd "$WORKE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
      ISSUE=214 PR_NUM="$1" CYCLE_NUMBER="$2" FINDING_ID="$3" CATEGORY=c \
      LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" \
      bash dismiss.sh >/dev/null 2>&1 )
}
_dismiss_one 234 2 F7
_dismiss_one 234 3 F3
# A dismissal on a DIFFERENT pull request, in the same journal, must not appear.
_dismiss_one 999 1 F99
DOUT2=$(cd "$WORKE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  ISSUE=214 PR_NUM=234 JOURNAL_DIR=.decisions bash disputed.sh 2>&1)
assert_contains "F7" "$DOUT2" "a dismissal from an earlier cycle is still in the array"
assert_contains "F3" "$DOUT2" "and so is this cycle's"
assert_not_contains "F99" "$DOUT2" "a dismissal on another pull request is not"

_flow_test_begin "a dropped-finding is not a dispute"
WORKF=$(mktemp -d -t flow-disp3.XXXXXX); ADDR_CLEANUP+=("$WORKF")
mkdir -p "$WORKF/.decisions"
_extract_disputed_block > "$WORKF/disputed.sh"
cat > "$WORKF/.decisions/issue-214.md" <<'JOURNAL'
---
issue: 214
artifacts:
- type: dropped-finding
  pr: 234
  cycle: 1
  finding_id: D1
  reason: unchallenged
---
# journal
JOURNAL
DOUT3=$(cd "$WORKF" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  ISSUE=214 PR_NUM=234 JOURNAL_DIR=.decisions bash disputed.sh 2>&1)
assert_not_contains "D1" "$DOUT3" "a dropped finding never reaches the array"
assert_contains "DISPUTED_STATE=none" "$DOUT3" "and the journal read as having no dismissals"

_flow_test_begin "an array that could not be built is not an empty array"
# The whole defect class: a failed read that prints DISPUTED:[] tells the merge
# gate nothing was disputed. Each of these must report unavailable AND print no
# DISPUTED= line at all, so there is nothing for step 9 to paste.
WORKG=$(mktemp -d -t flow-disp4.XXXXXX); ADDR_CLEANUP+=("$WORKG")
mkdir -p "$WORKG/.decisions"
_extract_disputed_block > "$WORKG/disputed.sh"
_disputed_run() { ( cd "$WORKG" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  ISSUE=214 PR_NUM=234 JOURNAL_DIR=.decisions bash disputed.sh 2>&1 ); }

OUT_A=$(_disputed_run)   # no journal file at all
assert_contains "DISPUTED_STATE=unavailable" "$OUT_A" "a missing journal is unavailable, not empty"
assert_not_contains "DISPUTED=" "$OUT_A" "and no array is offered for pasting"

printf -- '---\nissue: 214\nartifacts: [oops\n---\n# j\n' > "$WORKG/.decisions/issue-214.md"
OUT_B=$(_disputed_run)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_B" "an unparseable manifest is unavailable"
assert_not_contains "DISPUTED=" "$OUT_B" "and offers no array"

printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: "F3,F9"\n---\n# j\n' > "$WORKG/.decisions/issue-214.md"
OUT_C=$(_disputed_run)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_C" "a journal-injected id is refused"
assert_not_contains "DISPUTED=" "$OUT_C" "and offers no array"

printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: "*"\n---\n# j\n' > "$WORKG/.decisions/issue-214.md"
OUT_D=$(_disputed_run)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_D" "a glob id is refused"

# A pull request that closes no issue: dismissals may have happened with nowhere
# to record them, so this is unavailable, NOT none. ISSUE is set to a
# non-numeric value so the branch is reached without a network call.
OUT_E=$( cd "$WORKG" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  ISSUE=none PR_NUM=234 JOURNAL_DIR=.decisions bash disputed.sh 2>&1 || true )
assert_contains "DISPUTED_STATE=unavailable" "$OUT_E" "no linked issue is unavailable, not empty"
assert_not_contains "DISPUTED=" "$OUT_E" "and offers no array"

_flow_test_begin "the writer refuses an id the marker parser cannot carry"
# finding-ledger-parser.md splits the array on `,` and `]` and matches with a
# POSIX case glob, so these ids inject rows or match every RESOLVED list.
WORKH=$(mktemp -d -t flow-disp5.XXXXXX); ADDR_CLEANUP+=("$WORKH")
mkdir -p "$WORKH/.decisions"
_extract_dismissed_block > "$WORKH/dismiss.sh"
for BAD in 'F3,F9' '*' 'F3]' '3F'; do
  OUTB=$(cd "$WORKH" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID="$BAD" CATEGORY=c \
    LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" \
    bash dismiss.sh 2>&1); RCB=$?
  if [ "$RCB" -ne 0 ]; then
    _flow_assert_pass "the id '$BAD' is refused (exit $RCB)"
  else
    _flow_assert_fail "the id '$BAD' was recorded; it would corrupt the DISPUTED array"
  fi
done
# A legitimate hyphenated id is NOT refused, or the guard is just a blanket no.
OUTOK=$(cd "$WORKH" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID="SEC-2" CATEGORY=c \
  LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" \
  bash dismiss.sh 2>&1); RCOK=$?
assert_exit 0 "$RCOK" "a hyphenated ledger id is still accepted"

_flow_test_begin "step 9 refuses to post a marker whose array could not be built"
STEP9=$(awk '/^9\. \*\*Post resolution comment\*\*/{f=1} f && /^10\./{f=0} f' "$ADDRESS_MD")
assert_contains "DISPUTED_ARRAY_BLOCK" "$STEP9" "step 9 runs the emitter"
assert_contains "DISPUTED_STATE=unavailable" "$STEP9" "and names the unavailable state"
assert_match 'Do not post|do not post' "$STEP9" "and says not to post the comment on it"
