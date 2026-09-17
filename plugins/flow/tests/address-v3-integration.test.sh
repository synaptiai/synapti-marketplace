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
import re
_t=open('.decisions/issue-214.md',encoding='utf-8').read()
_m=re.match(r'---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)',_t,re.S)
d=yaml.safe_load(_m.group(1))
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
PHASE3_DISPUTED=$(awk '/^3\. The id reaches the/{f=1} f{print} f && /^```bash/{exit}' "$ADDRESS_MD")
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
import re
_t=open('.decisions/issue-214.md',encoding='utf-8').read()
_m=re.match(r'---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)',_t,re.S)
d=yaml.safe_load(_m.group(1))
a=[x for x in (d.get('artifacts') or []) if x.get('type')=='finding-dismissed']
print(a[-1] if a else 'NONE')
" 2>/dev/null)
  DOUT=$(cd "$WORKD" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$PWD" \
    ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
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
  ( cd "$WORKE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKE" \
      ISSUE=214 PR_NUM="$1" CYCLE_NUMBER="$2" FINDING_ID="$3" CATEGORY=c \
      LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" \
      bash dismiss.sh >/dev/null 2>&1 )
}
_dismiss_one 234 2 F7
_dismiss_one 234 3 F3
# A dismissal on a DIFFERENT pull request, in the same journal, must not appear.
_dismiss_one 999 1 F99
DOUT2=$(cd "$WORKE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKE" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
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
DOUT3=$(cd "$WORKF" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKF" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_not_contains "D1" "$DOUT3" "a dropped finding never reaches the array"
assert_contains "DISPUTED_STATE=none" "$DOUT3" "and the journal read as having no dismissals"

_flow_test_begin "an array that could not be built is not an empty array"
# The whole defect class: a failed read that prints DISPUTED:[] tells the merge
# gate nothing was disputed. Each of these must report unavailable AND print no
# DISPUTED= line at all, so there is nothing for step 9 to paste.
WORKG=$(mktemp -d -t flow-disp4.XXXXXX); ADDR_CLEANUP+=("$WORKG")
mkdir -p "$WORKG/.decisions"
_extract_disputed_block > "$WORKG/disputed.sh"
_disputed_run() { ( cd "$WORKG" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKG" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1 ); }

OUT_A=$(_disputed_run)   # no journal file at all
# A journal that is not there is NOT an absence. It is indistinguishable from
# reading the wrong path (a relative .decisions resolved from a subdirectory)
# and from a journal that vanished between the Phase 3 write and this read.
# The shape that IS a real absence — a journal that exists with no frontmatter
# at all — is covered by its own case below.
assert_contains "DISPUTED_STATE=unavailable" "$OUT_A" "a missing journal is unknown, not empty"
assert_not_contains "DISPUTED=" "$OUT_A" "and offers no array for pasting"

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
assert_not_contains "DISPUTED=" "$OUT_D" "and offers no array"

# An ISSUE that is not a positive integer. This is the malformed-issue arm, not
# the closes-no-issue arm — `none` fails the digit test, so the `''` case never
# matches. Both are unavailable and neither offers an array, which is what this
# asserts; the closes-no-issue arm and its DISPUTED_REASON_CODE are covered
# separately, under a stub plugin root, because reaching it needs the
# linked-issue helper to succeed and return nothing.
OUT_E=$( cd "$WORKG" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKG" \
  ISSUE=none PR_NUM=234 bash disputed.sh 2>&1 || true )
assert_contains "DISPUTED_STATE=unavailable" "$OUT_E" "a malformed linked issue is unavailable, not empty"
assert_not_contains "DISPUTED=" "$OUT_E" "and offers no array"
assert_not_contains "DISPUTED_REASON_CODE=" "$OUT_E" "and does not claim the pull request closes no issue"

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
# The refusal is conditional, and the condition matters: a pull request that
# closes no issue has nothing to record AND nowhere to record it, so stopping
# there would drop the comment Phase 5 calls mandatory on every issue-less pull
# request. Step 9 must give both branches — and must give them the right way
# round.
#
# Asserted PER BULLET, not per step. Matching "post the comment" and "do not
# post" anywhere in step 9 passes just as well against a document that swaps
# the two branches, which is the one error that matters here: it posts an empty
# array on every unreadable journal and erases every earlier dismissal.
BULLET_YES=$(printf '%s\n' "$STEP9" | awk '/- \*\*`DISPUTED_REASON_CODE=no-linked-issue`/{f=1} f && /- \*\*No `DISPUTED_REASON_CODE` line/{f=0} f')
BULLET_NO=$(printf '%s\n' "$STEP9" | awk '/- \*\*No `DISPUTED_REASON_CODE` line/{f=1} f && /^     Never skip/{f=0} f')
assert_match 'no-linked-issue' "$BULLET_YES" "the posting branch is the no-linked-issue code"
assert_match 'Post the comment|post the comment' "$BULLET_YES" "and that branch posts"
assert_not_contains "Do not post" "$BULLET_YES" "and is not also told to stop"
assert_match 'Do not post|do not post' "$BULLET_NO" "the other branch stops"
assert_not_contains "post the comment with" "$BULLET_NO" "and is not also told to post"
# The branch keys on a code the block emits, not on REASON prose: REASON carries
# journal-derived text, so "closes no issue" can be written into it by the file
# being read.
assert_match 'DISPUTED_REASON_CODE' "$STEP9" "step 9 branches on the machine-readable code"
assert_match 'grep -qx|line-anchored' "$STEP9" "and matches it as a whole line"
# Even the no-linked-issue branch is not unconditional: a pull request can close
# an issue in cycle 2 and lose the keyword before cycle 3.
# The case the branch does not cover is stated with its remedy rather than
# denied, and the claim it rests on is checked against merge.md above.
assert_match 'ISSUE=' "$BULLET_YES" "the uncovered earlier-issue case names its one-variable remedy"
assert_match 'opens no gate' "$BULLET_YES" "and says why no gate is opened by it"
assert_match 'cumulative' "$STEP9" "and says why this run's activity is the wrong signal"
assert_match 'mandatory' "$STEP9" "and says the comment is never skipped silently"

_flow_test_begin "every remaining exit path is unavailable, and none offers an array"
# The bundle claims EVERY failure path reports unavailable and prints no
# DISPUTED= line. Three were covered above through the reader; the six below
# are the guards around it. Guards 5 and 6 were added with the shared reader and
# this count is checked against them, not remembered.
WORKI=$(mktemp -d -t flow-disp6.XXXXXX); ADDR_CLEANUP+=("$WORKI")
mkdir -p "$WORKI/.decisions" "$WORKI/nopy"
_extract_disputed_block > "$WORKI/disputed.sh"
# A journal that WOULD produce an array, so each failure below is the guard
# firing rather than an empty directory.
cat > "$WORKI/.decisions/issue-214.md" <<'JOURNAL'
---
issue: 214
artifacts:
- type: finding-dismissed
  pr: 234
  cycle: 3
  finding_id: F3
  reason: breaks-test
---
# journal
JOURNAL
# Confirm the fixture is not itself the reason: the happy path must work here.
BASE=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKI" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED=[F3]" "$BASE" "the fixture does produce an array when nothing is broken"

# 1. A pull request number that is not a number.
OUT_P=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKI" \
  ISSUE=214 PR_NUM="12x" bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_P" "a non-numeric pull request number is unavailable"
assert_not_contains "DISPUTED=" "$OUT_P" "and offers no array"

# 2. python3 present but unusable. The probe must catch it, because `import yaml`
#    sits above the first print in the reader.
cat > "$WORKI/nopy/python3" <<'STUB'
#!/usr/bin/env bash
exit 127
STUB
chmod +x "$WORKI/nopy/python3"
OUT_Y=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" PATH="$WORKI/nopy:$PATH" HOME="$WORKI" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_Y" "an unusable interpreter is unavailable"
assert_match 'PyYAML|python3' "$OUT_Y" "and the reason names the dependency"
assert_not_contains "DISPUTED=" "$OUT_Y" "and offers no array"

# 3. A reader that dies mutely. The probe passes, the reader starts, and then it
#    produces no STATE line — which without the wrapper reads as an empty array.
cat > "$WORKI/nopy/python3" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"import yaml"*) exit 0 ;;   # the probe succeeds
  *) exit 9 ;;                 # the reader does not
esac
STUB
chmod +x "$WORKI/nopy/python3"
OUT_M=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" PATH="$WORKI/nopy:$PATH" HOME="$WORKI" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_M" "a reader that dies mutely is unavailable"
assert_not_contains "DISPUTED=" "$OUT_M" "and offers no array"

# 4. No ISSUE in the environment and no repository to resolve one from. This is
#    the path that reaches gh; the stub makes it fail the way an unauthenticated
#    or offline run does.
mkdir -p "$WORKI/nogh"
cat > "$WORKI/nogh/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$WORKI/nogh/gh"
OUT_R=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" PATH="$WORKI/nogh:$PATH" HOME="$WORKI" \
  PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_R" "an unresolvable repository is unavailable"
assert_not_contains "DISPUTED=" "$OUT_R" "and offers no array"

# 5. An unresolvable plugin root, so cascade-resolve.sh cannot run and the
#    journal directory comes back empty. The guard was written but nothing
#    reached it, so nothing pinned that it reports rather than proceeding
#    against an empty directory — which would have printed a clean empty array.
mkdir -p "$WORKI/empty-home"
OUT_NOROOT=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$WORKI/nonexistent" HOME="$WORKI/empty-home" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_NOROOT" "an unresolvable plugin root is unavailable"
assert_not_contains "DISPUTED=" "$OUT_NOROOT" "and offers no array"

# 6. The shared reader missing from an otherwise working plugin root. The import
#    sits above the first print, so without this guard the block dies before any
#    STATE line — and a missing STATE line reads exactly like an empty array.
mkdir -p "$WORKI/halfroot/bin"
cp "$PLUGIN_DIR/bin/cascade-resolve.sh" "$WORKI/halfroot/bin/cascade-resolve.sh"
cp "$PLUGIN_DIR/bin/flow-pr-linked-issue.sh" "$WORKI/halfroot/bin/flow-pr-linked-issue.sh"
chmod +x "$WORKI/halfroot/bin/cascade-resolve.sh" "$WORKI/halfroot/bin/flow-pr-linked-issue.sh"
OUT_NOREADER=$(cd "$WORKI" && CLAUDE_PLUGIN_ROOT="$WORKI/halfroot" HOME="$WORKI" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_NOREADER" "a missing shared reader is unavailable"
assert_not_contains "DISPUTED=" "$OUT_NOREADER" "and offers no array"


# --- what the block derives, it must derive in the test too -----------------
# Every emitter run above presets ISSUE and PR_NUM. PR_NUM is the value the
# agent supplies; ISSUE is the one production derives through `gh repo view` and
# flow-pr-linked-issue.sh. Presetting both meant neither resolution path was
# ever executed, which is how a block that could never run at all shipped green.
_flow_test_begin "the block refuses when its input is not set, and says which"
WORKJ=$(mktemp -d -t flow-disp7.XXXXXX); ADDR_CLEANUP+=("$WORKJ")
mkdir -p "$WORKJ/.decisions"
_extract_disputed_block > "$WORKJ/disputed.sh"
OUT_U=$(cd "$WORKJ" && env -u PR_NUM -u ISSUE CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKJ" \
  bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_U" "an unset pull request number is unavailable"
assert_match 'is not set' "$OUT_U" "and the reason says it is unset, not that it is malformed"
assert_not_contains "is not a number" "$OUT_U" "unset is not reported as non-numeric"
assert_not_contains "DISPUTED=" "$OUT_U" "and offers no array"

_flow_test_begin "the block derives the issue when it is not given one"
# The helper is called by absolute path, so it cannot be stubbed on PATH; stub
# the `gh` it calls instead, which is what production depends on.
WORKK=$(mktemp -d -t flow-disp8.XXXXXX); ADDR_CLEANUP+=("$WORKK")
mkdir -p "$WORKK/.decisions" "$WORKK/stub"
cat > "$WORKK/.decisions/issue-808.md" <<'JOURNAL'
---
issue: 808
artifacts:
- type: finding-dismissed
  pr: 234
  cycle: 1
  finding_id: F5
  reason: breaks-test
---
# journal
JOURNAL
# `gh pr view --json … --jq …` applies the filter inside gh, so the stub serves
# what the filter would have produced, not the raw payload.
cat > "$WORKK/stub/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *nameWithOwner*)              echo "acme/widgets" ;;
  *closingIssuesReferences*)    echo "808" ;;
  *)                            echo "" ;;
esac
STUB
chmod +x "$WORKK/stub/gh"
_extract_disputed_block > "$WORKK/disputed.sh"
OUT_DER=$(cd "$WORKK" && env -u ISSUE PATH="$WORKK/stub:$PATH" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKK" PR_NUM=234 bash disputed.sh 2>&1)
if printf '%s' "$OUT_DER" | grep -q 'DISPUTED=\[F5\]'; then
  _flow_assert_pass "the array is built from the issue the block resolved itself"
else
  _flow_assert_fail "the derived-issue path did not reach the journal: $(printf '%s' "$OUT_DER" | tr '\n' ' ')"
fi

_flow_test_begin "the emitter reads the journal where the writer actually wrote it"
# bin/journal-record.sh OVERWRITES JOURNAL_DIR from the settings cascade, so an
# emitter reading the environment variable disagreed with the writer whenever
# journal.dir was configured — and .claude/settings.flow.json is a committed,
# project-shared tier. The stale journal at the default path is what made the
# disagreement print a confident empty array.
WORKL=$(mktemp -d -t flow-disp9.XXXXXX); ADDR_CLEANUP+=("$WORKL")
mkdir -p "$WORKL/.claude" "$WORKL/.decisions"
printf '%s\n' '{"journal":{"dir":"docs/decisions"}}' > "$WORKL/.claude/settings.flow.json"
_extract_dismissed_block > "$WORKL/dismiss.sh"
_extract_disputed_block > "$WORKL/disputed.sh"
printf -- '---\nissue: 214\nartifacts: []\n---\n# stale, at the DEFAULT path\n' \
  > "$WORKL/.decisions/issue-214.md"
( cd "$WORKL" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKL" \
    ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID=F3 CATEGORY=c \
    LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" bash dismiss.sh >/dev/null 2>&1 )
assert_equal "1" "$([ -f "$WORKL/docs/decisions/issue-214.md" ] && echo 1 || echo 0)" \
  "the writer followed the configured journal.dir"
OUT_CFG=$(cd "$WORKL" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKL" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED=[F3]" "$OUT_CFG" "and the emitter read the same file"
assert_not_contains "DISPUTED_STATE=none" "$OUT_CFG" "not the stale journal at the default path"

_flow_test_begin "a --- inside a journal value does not truncate the manifest"
# Journal values are writer-accepted free text and an evidence string quoting a
# diff header is ordinary content. Splitting the manifest on the first `---`
# anywhere dropped every artifact after it and printed the shorter array with
# no indication anything was missing.
WORKM=$(mktemp -d -t flow-disp10.XXXXXX); ADDR_CLEANUP+=("$WORKM")
mkdir -p "$WORKM/.decisions"
_extract_dismissed_block > "$WORKM/dismiss.sh"
_extract_disputed_block > "$WORKM/disputed.sh"
_dismiss_ev() {
  ( cd "$WORKM" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKM" \
      ISSUE=214 PR_NUM=234 CYCLE_NUMBER="$1" FINDING_ID="$2" CATEGORY=c \
      LOCATION="a.sh:1" REASON=factually-incorrect EVIDENCE="$3" \
      bash dismiss.sh >/dev/null 2>&1 )
}
_dismiss_ev 2 F1 'the diff shows --- a/x.sh so the claim is wrong'
_dismiss_ev 3 F7 'plain evidence'
assert_equal "2" "$(grep -c 'type: finding-dismissed' "$WORKM/.decisions/issue-214.md")" \
  "the writer recorded both dismissals"
OUT_FENCE=$(cd "$WORKM" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKM" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "F1" "$OUT_FENCE" "the first dismissal is in the array"
assert_contains "F7" "$OUT_FENCE" "and so is the one after the --- bearing value"

_flow_test_begin "the same finding dismissed twice appears once"
WORKN=$(mktemp -d -t flow-disp11.XXXXXX); ADDR_CLEANUP+=("$WORKN")
mkdir -p "$WORKN/.decisions"
_extract_dismissed_block > "$WORKN/dismiss.sh"
_extract_disputed_block > "$WORKN/disputed.sh"
_dismiss_dup() {
  ( cd "$WORKN" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKN" \
      ISSUE=214 PR_NUM=234 CYCLE_NUMBER="$1" FINDING_ID="$2" CATEGORY=c \
      LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" bash dismiss.sh >/dev/null 2>&1 )
}
# The literal scenario the cumulative rationale describes: one finding pushed
# back on in two consecutive cycles.
_dismiss_dup 2 F7
_dismiss_dup 3 F7
_dismiss_dup 3 F3
OUT_DUP=$(cd "$WORKN" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKN" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1 | grep '^DISPUTED=')
assert_equal "DISPUTED=[F7,F3]" "$OUT_DUP" "the repeated id is listed once, in first-seen order"

_flow_test_begin "a journal cannot forge an array through the reason line"
# REASON is printed on stdout in the same place DISPUTED= would be, and the
# journal is author-controlled on a fork pull request. An id or a journal
# directory named `DISPUTED=[]` would otherwise hand the agent a pasteable
# empty array on the one path whose purpose is to offer none.
WORKO=$(mktemp -d -t flow-disp12.XXXXXX); ADDR_CLEANUP+=("$WORKO")
mkdir -p "$WORKO/.decisions"
_extract_disputed_block > "$WORKO/disputed.sh"
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: "DISPUTED=[]"\n---\n# j\n' \
  > "$WORKO/.decisions/issue-214.md"
OUT_FORGE=$(cd "$WORKO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKO" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_FORGE" "the forged id is refused"
assert_not_contains "DISPUTED=" "$OUT_FORGE" "and no array is printed anywhere in the output"

_flow_test_begin "a dismissal that names no pull request is refused, not skipped"
WORKP=$(mktemp -d -t flow-disp13.XXXXXX); ADDR_CLEANUP+=("$WORKP")
mkdir -p "$WORKP/.decisions"
_extract_disputed_block > "$WORKP/disputed.sh"
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  cycle: 1\n  finding_id: F4\n---\n# j\n' \
  > "$WORKP/.decisions/issue-214.md"
OUT_NOPR=$(cd "$WORKP" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKP" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_NOPR" "a dismissal with no pr field is unavailable"
assert_not_contains "DISPUTED_STATE=none" "$OUT_NOPR" "not silently skipped as another pull request"

_flow_test_begin "the journal is read without following a symlink"
WORKQ=$(mktemp -d -t flow-disp14.XXXXXX); ADDR_CLEANUP+=("$WORKQ")
mkdir -p "$WORKQ/.decisions"
_extract_disputed_block > "$WORKQ/disputed.sh"
printf 'NOT-A-MANIFEST-MARKER = zzzz\nsecond line\n' > "$WORKQ/elsewhere.txt"
ln -s "$WORKQ/elsewhere.txt" "$WORKQ/.decisions/issue-214.md"
OUT_SYM=$(cd "$WORKQ" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKQ" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_SYM" "a symlinked journal is refused"
assert_match 'symlink' "$OUT_SYM" "and the reason says so"
assert_not_contains "NOT-A-MANIFEST-MARKER" "$OUT_SYM" "and no byte of the target is echoed"

_flow_test_begin "a parse failure does not echo the file it failed on"
WORKR=$(mktemp -d -t flow-disp15.XXXXXX); ADDR_CLEANUP+=("$WORKR")
mkdir -p "$WORKR/.decisions"
_extract_disputed_block > "$WORKR/disputed.sh"
printf -- '---\nSENSITIVE-PAYLOAD-MARKER: [unclosed\n---\n# j\n' > "$WORKR/.decisions/issue-214.md"
OUT_ECHO=$(cd "$WORKR" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKR" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_ECHO" "an unparseable manifest is unavailable"
assert_not_contains "SENSITIVE-PAYLOAD-MARKER" "$OUT_ECHO" "and the file contents are not quoted back"

_flow_test_begin "a finding id that is not a string is refused"
WORKS=$(mktemp -d -t flow-disp16.XXXXXX); ADDR_CLEANUP+=("$WORKS")
mkdir -p "$WORKS/.decisions"
_extract_disputed_block > "$WORKS/disputed.sh"
# `yes` is the YAML boolean. str() would make it "True", which passes the
# allowlist and puts an id in the array that matches no real finding.
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: yes\n---\n# j\n' \
  > "$WORKS/.decisions/issue-214.md"
OUT_BOOL=$(cd "$WORKS" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKS" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_BOOL" "a boolean finding id is refused"
assert_not_contains "True" "$OUT_BOOL" "and never becomes the string True"
# Refused, not crashed. Without the type guard the boolean reaches re.match,
# which raises, and the wrapper turns that into the same `unavailable` — so
# asserting only the state cannot tell a clean refusal from a dead reader.
assert_match 'not a string' "$OUT_BOOL" "and the reason names the type, rather than a reader that died"
assert_not_contains "did not complete" "$OUT_BOOL" "the reader refused it rather than crashing on it"

_flow_test_begin "the reader does not import from the checked-out working tree"
# address.md runs `gh pr checkout` before this block, so the working directory
# holds whatever the pull request author put there. `python3 -c` and a bare
# heredoc both put the CWD on sys.path.
WORKT=$(mktemp -d -t flow-disp17.XXXXXX); ADDR_CLEANUP+=("$WORKT")
mkdir -p "$WORKT/.decisions"
_extract_disputed_block > "$WORKT/disputed.sh"
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: F3\n---\n# j\n' \
  > "$WORKT/.decisions/issue-214.md"
cat > "$WORKT/yaml.py" <<'HOSTILE'
import os
open(os.path.join(os.path.dirname(__file__), "IMPORTED"), "w").write("x")
def safe_load(*a, **k): return {}
class SafeLoader: pass
class YAMLError(Exception): pass
HOSTILE
OUT_IMP=$(cd "$WORKT" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKT" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_equal "0" "$([ -f "$WORKT/IMPORTED" ] && echo 1 || echo 0)" \
  "a yaml.py in the working tree is never imported"
assert_contains "DISPUTED=[F3]" "$OUT_IMP" "and the real parser still read the journal"
# The source assertion: both invocations must drop the working directory, or a
# future edit reintroduces it without any test noticing.
DISPUTED_SRC=$(_extract_disputed_block)
assert_equal "2" "$(printf '%s\n' "$DISPUTED_SRC" | grep -c 'PYTHONSAFEPATH=1')" \
  "the probe and the reader are both invoked with PYTHONSAFEPATH"
assert_equal "2" "$(printf '%s\n' "$DISPUTED_SRC" | grep -c 'sys.path\[:\]')" \
  "and both scrub sys.path explicitly, for interpreters older than 3.11"

_flow_test_begin "a manifest that is not a manifest is never quoted back"
# The reason is printed on stdout and reported onward. yaml.load raises a plain
# ValueError out of its typed-scalar constructors, UnicodeDecodeError is a
# ValueError subclass, and an explicit tag raises KeyError carrying the whole
# scalar — so catching ValueError and printing it echoed file bytes, and two of
# these were not caught at all.
WORKU=$(mktemp -d -t flow-disp18.XXXXXX); ADDR_CLEANUP+=("$WORKU")
mkdir -p "$WORKU/.decisions"
_extract_disputed_block > "$WORKU/disputed.sh"
_echo_run() { ( cd "$WORKU" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKU" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1 ); }

printf -- '---\nissue: 214\nartifacts: !!int "x LEAKMARKER y"\n---\n# j\n' > "$WORKU/.decisions/issue-214.md"
OUT_V=$(_echo_run)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_V" "a typed-scalar failure is unavailable"
assert_not_contains "LEAKMARKER" "$OUT_V" "and the scalar is not echoed"

printf -- '---\nissue: 214\nartifacts: !!bool "LEAKMARKER2"\n---\n# j\n' > "$WORKU/.decisions/issue-214.md"
OUT_W=$(_echo_run)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_W" "an explicit-tag failure is unavailable"
assert_not_contains "LEAKMARKER2" "$OUT_W" "and the scalar is not echoed"
assert_not_contains "Traceback" "$OUT_W" "and it is caught rather than crashing"

printf -- '---\nLEAKMARKER3: \200\201\n---\n' > "$WORKU/.decisions/issue-214.md"
OUT_X=$(_echo_run)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_X" "an undecodable journal is unavailable"
assert_not_contains "LEAKMARKER3" "$OUT_X" "and the bytes are not echoed"

_flow_test_begin "the marker token the parser reads is neutralised, not just the block's own"
# references/finding-ledger-parser.md extracts the array with
# grep -o 'DISPUTED:\[[^]]*\]'. Guarding only `DISPUTED=` guards the wrong
# spelling of the same attack, and journal.dir is author-controlled through the
# committed .claude/settings.flow.json.
WORKV=$(mktemp -d -t flow-disp19.XXXXXX); ADDR_CLEANUP+=("$WORKV")
mkdir -p "$WORKV/.decisions"
_extract_disputed_block > "$WORKV/disputed.sh"
# Channel 1: the finding id, which the refusal quotes back.
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: "DISPUTED:[PWNED]"\n---\n# j\n' \
  > "$WORKV/.decisions/issue-214.md"
OUT_TOK=$(cd "$WORKV" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKV" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_TOK" "the forged id is refused"
assert_not_contains "DISPUTED:[PWNED]" "$OUT_TOK" "the marker-shaped token does not survive"
assert_contains "DISPUTED%3a" "$OUT_TOK" "it is percent-escaped instead, in the lowercase form that cannot re-form a token"
# Channel 2: the journal directory, which reaches the path-bearing messages.
# journal.dir is author-controlled through the committed settings file.
WORKV2=$(mktemp -d -t flow-disp19b.XXXXXX); ADDR_CLEANUP+=("$WORKV2")
mkdir -p "$WORKV2/.claude" "$WORKV2/zz DISPUTED:[PWNED] zz"
printf '%s\n' '{"journal":{"dir":"zz DISPUTED:[PWNED] zz"}}' > "$WORKV2/.claude/settings.flow.json"
ln -s "$WORKV2/elsewhere.txt" "$WORKV2/zz DISPUTED:[PWNED] zz/issue-214.md"
_extract_disputed_block > "$WORKV2/disputed.sh"
OUT_TOK2=$(cd "$WORKV2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKV2" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_not_contains "DISPUTED:[PWNED]" "$OUT_TOK2" "nor through the journal directory"
assert_contains "DISPUTED%3a" "$OUT_TOK2" "which is escaped the same way"


_flow_test_begin "a journal with no manifest is empty, not unreadable"
# 9 of this repository own 41 journals have no manifest fence. Reporting that
# shape as unavailable stopped the mandatory resolution comment on every pull
# request whose issue had one.
WORKX=$(mktemp -d -t flow-disp20.XXXXXX); ADDR_CLEANUP+=("$WORKX")
mkdir -p "$WORKX/.decisions"
_extract_disputed_block > "$WORKX/disputed.sh"
printf '# Decision Journal\n\nsome prose, no frontmatter at all\n' > "$WORKX/.decisions/issue-214.md"
OUT_NM=$(cd "$WORKX" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKX" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=none" "$OUT_NM" "a journal with no manifest records no dismissal"
assert_contains "DISPUTED=[]" "$OUT_NM" "and the empty array is a true statement"
# A DAMAGED fence is a different thing and must still be unreadable, or this
# relaxation would swallow a mangled manifest too.
printf 'stray preamble\n---\nartifacts:\n- type: finding-dismissed\n---\n' > "$WORKX/.decisions/issue-214.md"
OUT_DM=$(cd "$WORKX" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKX" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_DM" "a damaged fence is still unreadable"
assert_not_contains "DISPUTED=" "$OUT_DM" "and offers no array"

_flow_test_begin "a pull request number with a leading zero is refused on both sides"
# journal-record.sh coerces pr to an int, so PR_NUM=0234 wrote `pr: 234` and the
# string comparison on read matched nothing: a confident empty array.
WORKY=$(mktemp -d -t flow-disp21.XXXXXX); ADDR_CLEANUP+=("$WORKY")
mkdir -p "$WORKY/.decisions"
_extract_dismissed_block > "$WORKY/dismiss.sh"
_extract_disputed_block > "$WORKY/disputed.sh"
OUT_ZW=$(cd "$WORKY" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKY" \
  ISSUE=214 PR_NUM=0234 CYCLE_NUMBER=3 FINDING_ID=F3 CATEGORY=c \
  LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" bash dismiss.sh 2>&1); RC_ZW=$?
if [ "$RC_ZW" -ne 0 ]; then
  _flow_assert_pass "the writer refuses a leading zero (exit $RC_ZW)"
else
  _flow_assert_fail "the writer recorded 0234 as 234; the reader will never find it"
fi
OUT_ZR=$(cd "$WORKY" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKY" \
  ISSUE=214 PR_NUM=0234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_ZR" "and the reader refuses it too"
assert_not_contains "DISPUTED_STATE=none" "$OUT_ZR" "rather than reporting no dismissals"
# The number is compared as a number, so a journal written by any other route
# still matches.
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: F3\n---\n# j\n' \
  > "$WORKY/.decisions/issue-214.md"
OUT_ZN=$(cd "$WORKY" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKY" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED=[F3]" "$OUT_ZN" "a well-formed number still matches"
# pr is documented `<int>` in references/decision-journal-schema.md, and the
# loop refuses a non-string finding_id ten lines further down. int() was wider
# than both: bool is an int subclass so `pr: yes` joined pull request #1, and a
# float truncated into whichever request it rounded to. Refuse, do not coerce.
for BADPR in 'yes' '234.7' '234.0'; do
  printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: %s\n  finding_id: F8\n---\n# j\n' "$BADPR" \
    > "$WORKY/.decisions/issue-214.md"
  OUT_ZF=$(cd "$WORKY" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKY" \
    ISSUE=214 PR_NUM=1 bash disputed.sh 2>&1)
  assert_contains "DISPUTED_STATE=unavailable" "$OUT_ZF" "pr: $BADPR is refused, not coerced"
  assert_not_contains "DISPUTED=[F8]" "$OUT_ZF" "pr: $BADPR never joins a pull request it does not name"
done
# A digit string still works, for a journal written by some other route.
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: "234"\n  finding_id: F8\n---\n# j\n' \
  > "$WORKY/.decisions/issue-214.md"
OUT_ZS=$(cd "$WORKY" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKY" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED=[F8]" "$OUT_ZS" "a digit string is still a pull request number"

_flow_test_begin "a block the agent is told to run is one the agent can see"
# references/command-output-format.md: a `!` block is pre-executed at command
# load, its stdout REPLACES the fence, and the source is not visible to the
# agent. A run-once-per-finding block in a `!` fence therefore runs once, at
# load, with every value unset — and the agent never sees the block it is told
# to run. Nothing pinned the fence type in either direction.
for BLOCK in FINDING_DISMISSED_BLOCK DISPUTED_ARRAY_BLOCK; do
  FENCE=$(grep -B1 "^# ${BLOCK}_BEGIN" "$ADDRESS_MD" | head -1)
  assert_equal '```bash' "$FENCE" "$BLOCK is a bash fence, so the agent can run it"
done

_flow_test_begin "the escaper cannot be made to assemble the token it removes"
# `%3D` ends in D. Escaping `RESOLVED=` inside `RESOLVED=ISPUTED:[X]` produced
# `RESOLVED%3DISPUTED:[X]`, which contains the exact string
# references/finding-ledger-parser.md greps with 'DISPUTED:\[[^]]*\]'. The
# escape must reach a fixed point, or it manufactures the token it exists to
# remove — and this payload was inert before the escaper was added.
WORKZ=$(mktemp -d -t flow-disp22.XXXXXX); ADDR_CLEANUP+=("$WORKZ")
mkdir -p "$WORKZ/.decisions"
_extract_disputed_block > "$WORKZ/disputed.sh"
for PAYLOAD in 'RESOLVED=ISPUTED:[PWNED]' 'RESOLVED=ISPUTED=[]' 'ESCALATED=ISPUTED:[X]' 'RESOLVED=ISPUTED=ISPUTED:[Y]'; do
  printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: "%s"\n---\n# j\n' "$PAYLOAD" \
    > "$WORKZ/.decisions/issue-214.md"
  OUT_ESC=$(cd "$WORKZ" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKZ" \
    ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
  LEAK=$(printf '%s' "$OUT_ESC" | grep -oE 'DISPUTED[:=]\[[^]]*\]' | head -1)
  if [ -z "$LEAK" ]; then
    _flow_assert_pass "payload '$PAYLOAD' assembles no array"
  else
    _flow_assert_fail "payload '$PAYLOAD' produced a parseable '$LEAK' in the output"
  fi
done

_flow_test_begin "a manifest the writer refuses is not read as an empty one"
# A first fence pair that is blank, a comment, or null yields fm=None. The
# writer refuses that file outright (exit 2, "existing frontmatter is not a
# YAML mapping"), so a reader reporting it as `none` accepts what the writer
# rejects — the disagreement this block exists to remove. The nine
# manifest-less journals in this repo are NOT this shape: they fail
# text.startswith("---") first and never reach yaml.load.
WORKAA=$(mktemp -d -t flow-disp23.XXXXXX); ADDR_CLEANUP+=("$WORKAA")
mkdir -p "$WORKAA/.decisions"
_extract_disputed_block > "$WORKAA/disputed.sh"
for FENCE in '---\n\n---\n' '---\n# just a comment\n---\n' '---\nnull\n---\n'; do
  printf -- "${FENCE}artifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: FHIDDEN\n" \
    > "$WORKAA/.decisions/issue-214.md"
  OUT_BF=$(cd "$WORKAA" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAA" \
    ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
  assert_contains "DISPUTED_STATE=unavailable" "$OUT_BF" "fence ${FENCE}: an empty first fence is unreadable, not empty"
  assert_not_contains "DISPUTED=[]" "$OUT_BF" "fence ${FENCE}: and offers no array"
done

_flow_test_begin "a journal that disappears between the write and the read is not an absence"
# Phase 4 runs the checked-out pull request's own lint and test commands
# between the Phase 3 write and the Phase 5 read. If the journal goes away in
# that window, `none` states that nothing was disputed when a dismissal was
# recorded minutes earlier.
#
# This reaches the same ENOENT branch as the missing-journal case above. It is
# kept because it pins the TRANSITION rather than the branch: the array is read
# back first, so the file is shown to have been readable and to have named a
# dismissal before it went away. The other case cannot show that.
WORKAB=$(mktemp -d -t flow-disp24.XXXXXX); ADDR_CLEANUP+=("$WORKAB")
mkdir -p "$WORKAB/.decisions"
_extract_dismissed_block > "$WORKAB/dismiss.sh"
_extract_disputed_block > "$WORKAB/disputed.sh"
( cd "$WORKAB" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAB" \
    ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID=F1 CATEGORY=c \
    LOCATION="a.sh:1" REASON=breaks-test EVIDENCE=e bash dismiss.sh >/dev/null 2>&1 )
OUT_BEFORE=$(cd "$WORKAB" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAB" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED=[F1]" "$OUT_BEFORE" "the dismissal is on record"
rm -f "$WORKAB/.decisions/issue-214.md"
OUT_AFTER=$(cd "$WORKAB" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAB" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_AFTER" "a vanished journal is unknown, not empty"
assert_not_contains "DISPUTED=[]" "$OUT_AFTER" "and offers no array to post"

_flow_test_begin "a settings file that cannot be parsed is reported, not swallowed"
# bin/journal-record.sh lets cascade-resolve.sh's per-source parse WARN through
# on the write side. A reader that hid it would leave a corrupt
# .claude/settings.flow.json loud on one side and silent on the other. The
# sibling marker block already has this test; this one was the exception.
WORKAC=$(mktemp -d -t flow-disp25.XXXXXX); ADDR_CLEANUP+=("$WORKAC")
mkdir -p "$WORKAC/.claude" "$WORKAC/.decisions"
printf '%s\n' '{"journal": {"dir" BROKEN' > "$WORKAC/.claude/settings.flow.json"
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: F2\n---\n# j\n' \
  > "$WORKAC/.decisions/issue-214.md"
_extract_disputed_block > "$WORKAC/disputed.sh"
ERR_W=$(cd "$WORKAC" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAC" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1 >/dev/null)
OUT_W2=$(cd "$WORKAC" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAC" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>/dev/null)
assert_match 'WARN' "$ERR_W" "the unparseable settings file is named on stderr"
assert_contains "DISPUTED=[F2]" "$OUT_W2" "and the default directory still resolves"

_flow_test_begin "the escape is a fixed point by construction, not by iteration count"
# The iterated escaper had a cap. `%3D` ends in `D`, so each pass re-supplied
# the leading character of the next token: a payload carrying one `ISPUTED=`
# layer per pass walks straight through any finite number of passes and the
# last layer ships unescaped. Ten layers defeat a ten-pass cap exactly.
#
# The channel is `journal.dir`, not a journal field. .claude/settings.flow.json
# is a tracked file, so a fork pull request carries its own, and the path built
# from it reaches the REASON through ONE escape. The artifact fields happen to
# pass through two — the branch message escapes the field, then bail escapes
# the message — so a payload aimed there needs twice the depth and is cut by
# the 200-character truncation first. Two applications of a capped escape is
# not a property anyone designed, and it holds only for the branches that
# happen to nest; this test uses the branch that does not.
#
# The assertion is the PROPERTY, not the one payload: across every nesting
# depth, no marker token in any spelling may survive into output that
# references/finding-ledger-parser.md reads.
WORKAD=$(mktemp -d -t flow-disp26.XXXXXX); ADDR_CLEANUP+=("$WORKAD")
mkdir -p "$WORKAD/.decisions" "$WORKAD/.claude"
_extract_disputed_block > "$WORKAD/disputed.sh"
printf -- '---\nissue: 214\nartifacts: []\n---\n# j\n' > "$WORKAD/.decisions/issue-214.md"
# The last pair is not a nesting payload: it is the key step 9 branches on.
# Nothing else fed it through the escape, so dropping it from MARKER_TOKENS left
# every suite green while a settings-controlled string could render it verbatim.
for DEPTH in 9 10 11 14; do
  for TAIL in '[PWNED]' 'ISPUTED:[PWNED]' 'DISPUTED_REASON_CODE=no-linked-issue'; do
    NEST=$(awk -v n="$DEPTH" -v t="$TAIL" \
      'BEGIN{s="RESOLVED=";for(i=0;i<n;i++)s=s "ISPUTED=";print s t}')
    printf '{"journal": {"dir": "%s"}}\n' "$NEST" > "$WORKAD/.claude/settings.flow.json"
    OUT_N=$(cd "$WORKAD" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAD" \
      ISSUE=214 PR_NUM=234 bash disputed.sh 2>/dev/null)
    assert_contains "DISPUTED_STATE=unavailable" "$OUT_N" "depth $DEPTH: a journal that is not there is unreadable"
    SURVIVOR=$(printf '%s' "$OUT_N" | grep -v '^DISPUTED_STATE=' \
      | grep -oE '(DISPUTED_REASON_CODE|DISPUTED|RESOLVED|ESCALATED)[:=]' | head -1)
    if [ -z "$SURVIVOR" ]; then
      _flow_assert_pass "depth $DEPTH: no marker token survives the escape"
    else
      _flow_assert_fail "depth $DEPTH: the escaper emitted a live '$SURVIVOR' into REASON"
    fi
  done
done

_flow_test_begin "the reader calls a fence a manifest only where the writer does"
# bin/_journal_atomic.parse_frontmatter requires exactly `---\n`; the readers
# accepted `---` plus trailing whitespace. A journal opening `--- ` therefore
# has NO manifest as far as every write is concerned — journal-record.sh
# prepends a fresh one and keeps the old text as body — while the reader
# parsed the old text as the whole truth. The array came back `ok` and short:
# a confident partial answer, which is the defect class this issue exists to
# remove.
WORKAE=$(mktemp -d -t flow-disp27.XXXXXX); ADDR_CLEANUP+=("$WORKAE")
mkdir -p "$WORKAE/.decisions"
_extract_disputed_block > "$WORKAE/disputed.sh"
printf -- '--- \nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: FSTALE\n---\n# j\n' \
  > "$WORKAE/.decisions/issue-214.md"
OUT_TS=$(cd "$WORKAE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAE" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_not_contains "DISPUTED_STATE=ok" "$OUT_TS" "a fence the writer does not see is not read as a manifest"
assert_not_contains "DISPUTED=[FSTALE]" "$OUT_TS" "and no array is built from it"
assert_contains "DISPUTED_STATE=unavailable" "$OUT_TS" "it is reported as damage, not as absence"
# The predicate is the writer's own, so agreement is checked against the
# writer rather than asserted about it.
WRITER_SEES=$(cd "$WORKAE" && PYTHONSAFEPATH=1 PYTHONPATH="$PLUGIN_DIR/bin" python3 -c 'import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
from _journal_atomic import parse_frontmatter
m, _ = parse_frontmatter(open(".decisions/issue-214.md", encoding="utf-8").read())
print("manifest" if m is not None else "no-manifest")' 2>/dev/null)
assert_equal "no-manifest" "$WRITER_SEES" "the writer sees no manifest in this file"

_flow_test_begin "a pr field too long for int() is refused, not a traceback"
# The digit allowlist admits any length; int() refuses a string past
# sys.int_info.str_digits_check_threshold (4300 by default). The comparison
# sat outside the handler, so the block died mid-run and the wrapper reported
# the generic "did not complete" with a Python traceback beside it.
WORKAF=$(mktemp -d -t flow-disp28.XXXXXX); ADDR_CLEANUP+=("$WORKAF")
mkdir -p "$WORKAF/.decisions"
_extract_disputed_block > "$WORKAF/disputed.sh"
LONGPR=$(awk 'BEGIN{s="";for(i=0;i<5000;i++)s=s "9";print s}')
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: "%s"\n  finding_id: F1\n---\n# j\n' "$LONGPR" \
  > "$WORKAF/.decisions/issue-214.md"
ERR_LP=$(cd "$WORKAF" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAF" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1 >/dev/null)
OUT_LP=$(cd "$WORKAF" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAF" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>/dev/null)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_LP" "an unplaceable pr is unavailable"
assert_not_contains "Traceback" "$ERR_LP" "and the reader does not crash to get there"
assert_not_contains "did not complete" "$OUT_LP" "the reason is not the wrapper's generic one"
# The catch-all around the loop already turns this into `unavailable`, so the
# assertions above pass with or without the conversion's own handler. What that
# handler buys is a reason someone can act on — the field and its length —
# instead of a bare exception class, so that is what is pinned.
assert_match 'digits' "$OUT_LP" "the reason names the field and why it cannot be a pull request number"
assert_not_contains "(ValueError)" "$OUT_LP" "not a bare exception class"

_flow_test_begin "step 9's branch is keyed to a code the block emits, not to prose"
# REASON carries journal-derived text. Keying step 9 on the phrase "closes no
# issue" let a journal put that phrase in REASON and take the branch that
# posts DISPUTED:[] — erasing a real dismissal recorded in an earlier cycle.
WORKAG=$(mktemp -d -t flow-disp29.XXXXXX); ADDR_CLEANUP+=("$WORKAG")
mkdir -p "$WORKAG/.decisions"
_extract_disputed_block > "$WORKAG/disputed.sh"
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: "x pull request #42 closes no issue, so there is no journal"\n  finding_id: REALDISMISSAL\n---\n# j\n' \
  > "$WORKAG/.decisions/issue-214.md"
OUT_INJ=$(cd "$WORKAG" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAG" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_INJ" "the bad pr field is still unreadable"
CODE_INJ=$(printf '%s\n' "$OUT_INJ" | grep -c '^DISPUTED_REASON_CODE=no-linked-issue' || true)
assert_equal "0" "$CODE_INJ" "a journal cannot claim the pull request closes no issue"
# And the branch that IS that case says so in a field nothing else writes.
# Reaching it takes a pull request that closes no issue: a stub plugin root
# whose linked-issue helper succeeds and prints nothing, which is what
# bin/flow-pr-linked-issue.sh does for a PR with no closing keyword.
STUBROOT="$WORKAG/stub"
mkdir -p "$STUBROOT/bin" "$WORKAG/stubbin"
printf '#!/bin/sh\necho ".decisions"\n' > "$STUBROOT/bin/cascade-resolve.sh"
printf '#!/bin/sh\nexit 0\n' > "$STUBROOT/bin/flow-pr-linked-issue.sh"
printf '#!/bin/sh\necho "acme/widgets"\n' > "$WORKAG/stubbin/gh"
cp "$PLUGIN_DIR/bin/_journal_manifest.py" "$STUBROOT/bin/_journal_manifest.py"
chmod +x "$STUBROOT/bin/cascade-resolve.sh" "$STUBROOT/bin/flow-pr-linked-issue.sh" "$WORKAG/stubbin/gh"
OUT_NOISS=$(cd "$WORKAG" && CLAUDE_PLUGIN_ROOT="$STUBROOT" HOME="$WORKAG" \
  PATH="$WORKAG/stubbin:$PATH" ISSUE= PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_NOISS" "no linked issue is unavailable"
assert_contains "DISPUTED_REASON_CODE=no-linked-issue" "$OUT_NOISS" "and carries a machine-readable code"
# The code is the branch's own, so no other failure path may emit it.
for OTHER_NAME in injected-reason trailing-space-fence overlong-pr; do
  case "$OTHER_NAME" in
    injected-reason)       OTHER="$OUT_INJ" ;;
    trailing-space-fence)  OTHER="$OUT_TS" ;;
    overlong-pr)           OTHER="$OUT_LP" ;;
  esac
  assert_not_contains "DISPUTED_REASON_CODE=" "$OTHER" "$OTHER_NAME does not claim the no-issue branch"
done

_flow_test_begin "both readers share one implementation rather than one description"
# Three review rounds running, a sweep across the two hand-copied readers
# missed one: address.md gained O_NONBLOCK and learn.md did not, and both
# drifted from the writer's fence. A copy that must be kept in step by hand
# is the defect, not the symptom.
MANIFEST_PY="$PLUGIN_DIR/bin/_journal_manifest.py"
if [ -f "$MANIFEST_PY" ]; then
  _flow_assert_pass "bin/_journal_manifest.py exists"
  MAN_SRC=$(cat "$MANIFEST_PY")
  assert_contains "from _journal_atomic import" "$MAN_SRC" "and takes the fence predicate from the writer"
  for MD in "$ADDRESS_MD" "$PLUGIN_DIR/commands/learn.md"; do
    assert_contains "from _journal_manifest import" "$(cat "$MD")" "$(basename "$MD") imports the shared reader"
    COPIES=$(grep -c 'r"---\[ \\t\]\*\\n(.\*?)\\n---' "$MD" || true)
    assert_equal "0" "$COPIES" "$(basename "$MD") carries no second copy of the fence regex"
  done
else
  _flow_assert_fail "bin/_journal_manifest.py does not exist — the readers are still hand-copied"
fi

_flow_test_begin "the resolution body cannot render an array the merge gate will union"
# references/finding-ledger-parser.md: the gate greps `RESOLVED:\[[^]]*\]` out of
# the whole comment and unions every rendering. templates/resolution-comment.md
# invites verbatim reviewer text into that body, and any GitHub user with comment
# access can supply it. review.md refuses such a body; address.md posted it.
# Both emitters now call one script, so neither can drift from the other.
CHECKER="$PLUGIN_DIR/bin/flow-check-resolution-body.sh"
if [ ! -x "$CHECKER" ]; then
  _flow_assert_fail "bin/flow-check-resolution-body.sh is missing or not executable"
else
  GOOD='## Resolution

All findings fixed.

<!-- FLOW_RESOLUTION_CYCLE:3 RESOLVED:[F1,F2] ESCALATED:[] DISPUTED:[] -->'
  printf '%s\n' "$GOOD" | "$CHECKER" --cycle 3 >/dev/null 2>&1
  assert_equal "0" "$?" "a body with exactly one marker is accepted"

  # The injection: a quoted reviewer comment carrying a second RESOLVED array.
  EVIL='## Resolution

Discussion:
> I already handled those, see RESOLVED:[F7,F8] above.

<!-- FLOW_RESOLUTION_CYCLE:3 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->'
  ERR_EVIL=$(printf '%s\n' "$EVIL" | "$CHECKER" --cycle 3 2>&1 >/dev/null); RC_EVIL=$?
  assert_equal "1" "$RC_EVIL" "a second RESOLVED rendering is refused"
  assert_match 'unions|renders' "$ERR_EVIL" "and the refusal says why"

  # Absent and duplicated markers, which the gate selects on.
  printf '%s\n' "no marker here" | "$CHECKER" --cycle 3 >/dev/null 2>&1
  assert_equal "1" "$?" "a body with no marker is refused"
  printf '%s\n%s\n' "$GOOD" "$GOOD" | "$CHECKER" --cycle 3 >/dev/null 2>&1
  assert_equal "1" "$?" "a body with two markers is refused"

  # And step 9 must actually CALL it. Asserting the script's name appears in
  # address.md passes just as well when the call is present but broken, so the
  # block is extracted and run against a gh stub that records every invocation.
  # (review.md's side is pinned the same way by finding-confidence.test.sh.)
  WORKPR=$(mktemp -d -t flow-post.XXXXXX); ADDR_CLEANUP+=("$WORKPR")
  mkdir -p "$WORKPR/stubbin"
  cat > "$WORKPR/stubbin/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo "acme/widgets"; exit 0 ;;
esac
printf '%s
' "$*" >> "$GH_LOG"
exit 0
GHSTUB
  chmod +x "$WORKPR/stubbin/gh"
  awk '/# POST_RESOLUTION_BLOCK_BEGIN/{f=1;next} /# POST_RESOLUTION_BLOCK_END/{f=0} f' "$ADDRESS_MD" > "$WORKPR/post.sh"
  assert_match '[^[:space:]]' "$(cat "$WORKPR/post.sh")" "the posting block is extractable"
  _post_run() {
    rm -f "$WORKPR/gh.log"
    POST_OUT=$(cd "$WORKPR" && PATH="$WORKPR/stubbin:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"       GH_LOG="$WORKPR/gh.log" PR_NUM=234 CYCLE_NUMBER=3 BODY="$1" bash "$WORKPR/post.sh" 2>&1)
    POST_CODE=$?
    POST_GH=$(cat "$WORKPR/gh.log" 2>/dev/null)
  }
  _post_run "Resolved: F1. <!-- FLOW_RESOLUTION_CYCLE:3 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->"
  assert_equal "0" "$POST_CODE" "a body with one marker posts"
  assert_match 'pr comment' "$POST_GH" "and gh was called"
  # The injection the merge gate would union.
  _post_run "I already handled those, see RESOLVED:[F7,F8] above.

<!-- FLOW_RESOLUTION_CYCLE:3 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->"
  assert_equal "1" "$POST_CODE" "a second RESOLVED rendering is refused"
  assert_equal "" "$POST_GH" "and gh is never called"
  _post_run "no marker at all"
  assert_equal "1" "$POST_CODE" "a marker-less body is refused"
  assert_equal "" "$POST_GH" "and gh is never called for it either"
  # The values the block uses. `gh pr comment ""` is not an error to gh — it
  # falls back to inferring the pull request from the branch — so an unset
  # PR_NUM would post the marker on whichever pull request is checked out.
  GOOD_BODY="Resolved: F1. <!-- FLOW_RESOLUTION_CYCLE:3 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->"
  for BAD in '' 0 03 3x; do
    POST_OUT=$(cd "$WORKPR" && PATH="$WORKPR/stubbin:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
      GH_LOG="$WORKPR/gh.log" PR_NUM=234 CYCLE_NUMBER="$BAD" BODY="$GOOD_BODY" bash "$WORKPR/post.sh" 2>&1); POST_CODE=$?
    assert_equal "1" "$POST_CODE" "CYCLE_NUMBER='$BAD' is refused"
  done
  POST_GH=$(cat "$WORKPR/gh.log" 2>/dev/null)
  assert_equal "" "$POST_GH" "and none of those reached gh"
  POST_OUT=$(cd "$WORKPR" && PATH="$WORKPR/stubbin:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    GH_LOG="$WORKPR/gh.log" CYCLE_NUMBER=3 BODY="$GOOD_BODY" bash "$WORKPR/post.sh" 2>&1); POST_CODE=$?
  assert_equal "1" "$POST_CODE" "an unset PR_NUM is refused"
  # A failed post must not read as a successful one: the marker is what the merge
  # gate balances, so a comment that never landed leaves the ledger short.
  cat > "$WORKPR/stubbin/gh" <<'GHFAIL'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo "acme/widgets"; exit 0 ;;
esac
exit 7
GHFAIL
  chmod +x "$WORKPR/stubbin/gh"
  POST_OUT=$(cd "$WORKPR" && PATH="$WORKPR/stubbin:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    PR_NUM=234 CYCLE_NUMBER=3 BODY="$GOOD_BODY" bash "$WORKPR/post.sh" 2>&1); POST_CODE=$?
  assert_equal "1" "$POST_CODE" "a failed gh pr comment is an error, not a silent success"
  assert_contains "RES_EXIT=7" "$POST_OUT" "and the exit is reported"
fi

_flow_test_begin "the resolution-body checker returns when its stdin is closed"
# `$(cat)` deadlocks here: with fd 0 closed, command substitution allocates the
# pipe read end AS fd 0, and the parent then blocks on the substitution holding
# the write end. A merge-gate helper that hangs is worse than one that refuses.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  TMO7=$(command -v timeout || command -v gtimeout)
  ( "$TMO7" 6 bash "$CHECKER" --cycle 3 0<&- >/dev/null 2>&1 ); RC_HANG=$?
  if [ "$RC_HANG" -eq 124 ]; then
    _flow_assert_fail "the checker hung on a closed stdin (timed out after 6s)"
  else
    _flow_assert_pass "the checker returns rather than waiting for input that cannot come"
    assert_equal "1" "$RC_HANG" "and refuses, because an unread body is an empty one"
  fi
else
  _flow_assert_pass "SKIP: neither timeout nor gtimeout is installed"
fi

_flow_test_begin "every runnable fence in step 9 is a marked, testable block"
# The earlier-cycle pre-check shipped as an unmarked ```bash fence inside step 9
# prose. It referenced $REPO and $TRUST_LIST, which no fence defines, checked no
# exit status, and the prose read its empty stdout as "nothing to worry about" —
# the exact defect class this issue exists to remove, in the fix for it.
# A fence the agent is told to run is code. Unmarked code is untested code.
# Every fence type that RUNS. A ```! fence is pre-executed at command load, so it
# is the more dangerous of the two and the one the first version of this test
# missed — it counted ```bash only, and an unmarked ```! fence sailed through.
# The two counters live in variables, not inline, so the negative case below
# runs THE SAME program over a mutated copy. An earlier version re-wrote the
# regex inside the fixture, which pinned a copy of the rule rather than the rule:
# narrowing the real scanner back to bare "```" left every assertion green.
FENCE_SCAN='/^9\. \*\*Post resolution comment\*\*/{f=1} f && /^10\./{f=0} f && /^ *```(bash|!)[ \t]*$/{c++} END{print c+0}'
MARKER_SCAN='/^9\. \*\*Post resolution comment\*\*/{f=1} f && /^10\./{f=0} f && /_BLOCK_BEGIN/{c++} END{print c+0}'
STEP9_FENCES=$(awk "$FENCE_SCAN" "$ADDRESS_MD")
STEP9_MARKED=$(awk "$MARKER_SCAN" "$ADDRESS_MD")
assert_equal "$STEP9_FENCES" "$STEP9_MARKED" "every runnable fence in step 9 carries BEGIN/END markers"
# The negative case: the same scan over a copy carrying an unmarked inline-! fence
# inside step 9. An inline-! fence is pre-executed at command load, so it is the
# more dangerous of the two to leave unmarked, and it is the arm this test added.
WORKNEG=$(mktemp -d -t flow-fenceneg.XXXXXX); ADDR_CLEANUP+=("$WORKNEG")
awk '{ if ($0 ~ /^10\. \*\*Update PR body review cycle state\*\*/ && !done) {
         print "```!"
         print "echo \"STATE=ok\""
         print "```"
         done=1
       }
       print }' "$ADDRESS_MD" > "$WORKNEG/address-bad.md"
assert_match '[^[:space:]]' "$(cat "$WORKNEG/address-bad.md")" "the mutated copy exists"
NEG_F=$(awk "$FENCE_SCAN" "$WORKNEG/address-bad.md")
NEG_M=$(awk "$MARKER_SCAN" "$WORKNEG/address-bad.md")
if [ "$NEG_F" -ne "$NEG_M" ]; then
  _flow_assert_pass "the scan catches an unmarked inline-! fence ($NEG_F fences vs $NEG_M markers)"
else
  _flow_assert_fail "an unmarked inline-! fence was not counted ($NEG_F vs $NEG_M)"
fi
# A trailing space after the info string. CommonMark trims the info string, so
# '```! ' is the same fence as '```!' to the executor while an exact-shape scan
# misses it — a one-space bypass of the whole guard. The mutated copy uses the
# form the exact-shape version would miss.
awk '{ if ($0 ~ /^10\. \*\*Update PR body review cycle state\*\*/ && !done) {
         print "```!\t"
         print "echo \"STATE=ok\""
         print "```"
         done=1
       }
       print }' "$ADDRESS_MD" > "$WORKNEG/address-ws.md"
NEG_WS_F=$(awk "$FENCE_SCAN" "$WORKNEG/address-ws.md")
NEG_WS_M=$(awk "$MARKER_SCAN" "$WORKNEG/address-ws.md")
if [ "$NEG_WS_F" -ne "$NEG_WS_M" ]; then
  _flow_assert_pass "a trailing space after the info string does not hide a fence ($NEG_WS_F vs $NEG_WS_M)"
else
  _flow_assert_fail "an opener with a trailing space was not counted ($NEG_WS_F vs $NEG_WS_M)"
fi
# And the fence TYPES the shared scan recognises. Run through the SAME program as
# the live check, so narrowing the real scanner breaks these too.
# Tabs as well as spaces. The tolerance is a space-or-tab class, and fixtures
# carrying only spaces pinned half of it: narrowing the shared scanner to spaces
# left the whole suite green. CommonMark trims the info string's trailing
# whitespace however it is spelled, so an inline-bang opener followed by a tab is
# the same fence to an executor while a spaces-only scanner misses it.
for KNOWN in '```bash' '```!' '```bash   ' '```! ' $'```!\t' $'```bash\t'; do
  printf '9. **Post resolution comment**\n%s\necho x\n```\n' "$KNOWN" > "$WORKNEG/probe.md"
  N=$(awk "$FENCE_SCAN" "$WORKNEG/probe.md")
  assert_equal "1" "$N" "the scan recognises the opener '$KNOWN'"
done
for UNKNOWN in '```sh' '```zsh' '``` shell'; do
  printf '9. **Post resolution comment**\n%s\necho x\n```\n' "$UNKNOWN" > "$WORKNEG/probe.md"
  N=$(awk "$FENCE_SCAN" "$WORKNEG/probe.md")
  assert_equal "0" "$N" "the scan does not claim to recognise '$UNKNOWN'"
done

_flow_test_begin "an issue-less pull request is told how to include earlier dismissals"
# A pull request can close an issue in cycle 2 and lose the keyword before cycle
# 3. Posting DISPUTED:[] then drops that record. merge.md never reads DISPUTED
# (0 occurrences), so no gate is bypassed — the loss is the /flow:status
# classification, and the recovery is to name the earlier issue. The block
# already honours a pre-set ISSUE, so the remedy is one variable. It is stated
# in the machine output, not only in prose, because that is what the agent reads.
assert_equal "0" "$(grep -c 'DISPUTED' "$PLUGIN_DIR/commands/merge.md")" "merge.md still does not read DISPUTED"
assert_match 'ISSUE=' "$(awk '/^# DISPUTED_ARRAY_BLOCK_BEGIN/{f=1} /^# DISPUTED_ARRAY_BLOCK_END/{f=0} f' "$ADDRESS_MD" | grep 'REASON=.*closes no issue')" \
  "the no-linked-issue REASON names the ISSUE= remedy"

_flow_test_begin "a manifest the writer refuses to parse is never an empty one"
WORKAI=$(mktemp -d -t flow-disp31.XXXXXX); ADDR_CLEANUP+=("$WORKAI")
mkdir -p "$WORKAI/.decisions"
_extract_disputed_block > "$WORKAI/disputed.sh"
# An opening fence with no closing fence. bin/_journal_atomic.py raises on this
# and refuses to overwrite the file; a reader calling it empty accepts what the
# writer rejects. Nothing pinned it.
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: FUNCLOSED\n' \
  > "$WORKAI/.decisions/issue-214.md"
OUT_UC=$(cd "$WORKAI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAI" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_UC" "an unclosed fence is unreadable, not empty"
assert_not_contains "DISPUTED=" "$OUT_UC" "and offers no array"
# artifacts present but not a list.
printf -- '---\nissue: 214\nartifacts: 42\n---\n# j\n' > "$WORKAI/.decisions/issue-214.md"
OUT_AL=$(cd "$WORKAI" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAI" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_AL" "a scalar artifacts key is unreadable, not empty"
assert_not_contains "DISPUTED=" "$OUT_AL" "and offers no array either"

_flow_test_begin "a finding id longer than the writer accepts is refused"
# The id goes into a GitHub comment as part of the DISPUTED array. The reader
# bounds every other file-derived value it prints; this one was unbounded, and
# the writer did not bound it either. Both sides now cap at the same number, so
# the reader still refuses exactly what the writer refuses.
WORKAJ=$(mktemp -d -t flow-disp32.XXXXXX); ADDR_CLEANUP+=("$WORKAJ")
mkdir -p "$WORKAJ/.decisions"
_extract_disputed_block > "$WORKAJ/disputed.sh"
_extract_dismissed_block > "$WORKAJ/dismiss.sh"
LONGID=$(awk 'BEGIN{s="F";for(i=0;i<300;i++)s=s "a";print s}')
printf -- '---\nissue: 214\nartifacts:\n- type: finding-dismissed\n  pr: 234\n  finding_id: %s\n---\n# j\n' "$LONGID" \
  > "$WORKAJ/.decisions/issue-214.md"
OUT_LI=$(cd "$WORKAJ" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" HOME="$WORKAJ" \
  ISSUE=214 PR_NUM=234 bash disputed.sh 2>&1)
assert_contains "DISPUTED_STATE=unavailable" "$OUT_LI" "an overlong id is refused by the reader"
assert_not_contains "$LONGID" "$OUT_LI" "and is not echoed back whole"
OUT_LW=$(cd "$WORKAJ" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID="$LONGID" CATEGORY=c \
  LOCATION="a.sh:1" REASON=breaks-test EVIDENCE="e" bash dismiss.sh 2>&1); RC_LW=$?
assert_equal "2" "$RC_LW" "and the writer refuses to record it in the first place"
