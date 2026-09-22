# Tests for the evidence-grounded critic pass — issue #215.
#
# Contract under test:
#   - agents/finding-critic.md exists, reads the code (Read, Grep, Glob, LSP) and cannot
#     write it, carries memory: none, states the three-verdict grammar, and forbids
#     re-prioritizing, re-categorizing, dropping and adding findings.
#   - The grammar IS the result being reproduced. A critic allowed to disagree without
#     evidence measured F1 0.457 against 0.495 for no critic at all, so an off-grammar
#     line must be no verdict, and a finding with no verdict must survive untouched.
#   - commands/review.md (Path B) and commands/pr.md (Phase 4) carry a grounding step
#     gated on review.groundingCritic whose re-pass rule is "cite code or drop" for BOTH
#     disagree forms, and both say Path A is unchanged.
#   - settings.json carries review.groundingCritic="off"; schema.json accepts only off and
#     on; the extracted gate block rejects "true", "1" and an empty resolution with a WARN
#     and falls back to off.
#   - The FLOW_REVIEW_CYCLE marker keeps seven fields: `grounding` is a synthesis-time and
#     journal field, not a marker field.
#
# Prereq: jq for the schema.json assertions. SKIPS gracefully if unavailable.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
CRITIC="$PLUGIN_DIR/agents/finding-critic.md"
REVIEW_MD="$PLUGIN_DIR/commands/review.md"
PR_MD="$PLUGIN_DIR/commands/pr.md"
SETTINGS="$PLUGIN_DIR/settings.json"
SCHEMA="$PLUGIN_DIR/schema.json"
FINDING_SCHEMA="$PLUGIN_DIR/references/finding-schema.md"
JOURNAL_SCHEMA="$PLUGIN_DIR/references/decision-journal-schema.md"
PAIRED="$PLUGIN_DIR/references/paired-review-protocol.md"
METHODOLOGY="$PLUGIN_DIR/skills/code-review-methodology/SKILL.md"

CLEANUP_PATHS=()
_gc_cleanup() {
  local p
  for p in "${CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _gc_cleanup EXIT

# =============================================================================
# AC1 — the agent file
# =============================================================================

_flow_test_begin "agents/finding-critic.md exists"
assert_file_exists "$CRITIC" "the critic agent file is present"

CRITIC_TXT=$(cat "$CRITIC" 2>/dev/null)
# Assert the file was actually read: an empty needle search over an empty file
# passes every contains-assertion below for the wrong reason.
CRITIC_LINES=$(printf '%s\n' "$CRITIC_TXT" | wc -l | tr -d ' ')
assert_match '^[1-9][0-9]+$' "$CRITIC_LINES" "the critic file has content (read $CRITIC_LINES lines)"

_flow_test_begin "finding-critic frontmatter grants read tools only"
# Bind to the frontmatter `tools:` line, not to the whole file: the body says
# in prose that the critic has no Bash, and a file-wide assert_not_contains
# would fail on that sentence rather than on a real grant.
TOOLS_LINE=$(awk '/^---$/{n++; next} n==1 && /^tools:/{print; exit}' "$CRITIC")
assert_equal "tools: Read, Grep, Glob, LSP" "$TOOLS_LINE" "tools line is exactly the four read tools"
assert_not_contains "Write" "$TOOLS_LINE" "tools line does not grant Write"
assert_not_contains "Edit" "$TOOLS_LINE" "tools line does not grant Edit"
assert_not_contains "Bash" "$TOOLS_LINE" "tools line does not grant Bash"

_flow_test_begin "finding-critic frontmatter carries memory: none"
MEMORY_LINE=$(awk '/^---$/{n++; next} n==1 && /^memory:/{print; exit}' "$CRITIC")
assert_equal "memory: none" "$MEMORY_LINE" "memory is none"

_flow_test_begin "finding-critic states all three verdict tokens"
assert_contains "<id> AGREE" "$CRITIC_TXT" "AGREE verdict shape"
assert_contains "<id> DISAGREE_EVIDENCE: <file:line>" "$CRITIC_TXT" "DISAGREE_EVIDENCE verdict shape with a citation slot"
assert_contains "<id> DISAGREE_CONCERN: <objection>" "$CRITIC_TXT" "DISAGREE_CONCERN verdict shape"

_flow_test_begin "finding-critic prohibits re-ranking, dropping and adding findings"
# Bind to the negation. `assert_contains "re-prioritize"` also passes on a file
# that says the critic MAY re-prioritize, which is the failure this assertion
# exists to catch. NEG is assembled from pieces so the needle never appears
# literally in this file.
NEG="may n""ot "
for PHRASE in "re-prioritize a finding" "re-categorize a finding" "drop a finding" "add a finding"; do
  assert_contains "$NEG$PHRASE" "$CRITIC_TXT" "the critic is forbidden to $PHRASE"
done
# And nothing in the file grants any of them.
assert_not_contains "may re-prioritize" "$CRITIC_TXT" "no sentence permits re-prioritizing"
assert_not_contains "may drop" "$CRITIC_TXT" "no sentence permits dropping"
assert_not_contains "may add a finding" "$CRITIC_TXT" "no sentence permits adding a finding"

_flow_test_begin "finding-critic pins the off-grammar line as no verdict"
# The 0.457 row: an unconstrained disagreement must not be able to cost a
# finding its place. The must-stay-silent case of the same rule is that a
# well-formed DISAGREE_EVIDENCE line IS a verdict.
assert_contains "is not a verdict" "$CRITIC_TXT" "an off-grammar line is stated to be no verdict"
assert_match 'DISAGREE:.*(not|never)' "$CRITIC_TXT" "a bare DISAGREE is explicitly rejected"

# =============================================================================
# AC2 — the grounding step in both commands
# =============================================================================

REVIEW_TXT=$(cat "$REVIEW_MD")
PR_TXT=$(cat "$PR_MD")

_flow_test_begin "both commands gate the grounding step on review.groundingCritic"
for PAIR in "review.md:$REVIEW_TXT" "pr.md:$PR_TXT"; do
  NAME="${PAIR%%:*}"; BODY="${PAIR#*:}"
  assert_contains "review.groundingCritic" "$BODY" "$NAME names the setting"
  assert_contains "GROUNDING_CRITIC_BEGIN" "$BODY" "$NAME carries the gate block sentinel"
  assert_contains "GROUNDING_CRITIC=" "$BODY" "$NAME emits GROUNDING_CRITIC"
  assert_contains "off|on) ;;" "$BODY" "$NAME validates against the off|on allowlist"
  assert_contains "Agent(finding-critic)" "$BODY" "$NAME dispatches the critic"
done

_flow_test_begin "the re-pass rule is 'cite code or drop' for BOTH disagree forms"
for PAIR in "review.md:$REVIEW_TXT" "pr.md:$PR_TXT"; do
  NAME="${PAIR%%:*}"; BODY="${PAIR#*:}"
  assert_contains "cite code or drop" "$BODY" "$NAME states the rule by name"
  assert_match 'DISAGREE_EVIDENCE.*(drop|revise)' "$BODY" "$NAME gives DISAGREE_EVIDENCE the rule"
  assert_match 'DISAGREE_CONCERN.*(cite|drop)' "$BODY" "$NAME gives DISAGREE_CONCERN the rule"
  assert_contains "A reply without a citation drops the finding" "$BODY" "$NAME: an uncited reply drops"
done

_flow_test_begin "an off-grammar critic line never removes a finding"
for PAIR in "review.md:$REVIEW_TXT" "pr.md:$PR_TXT"; do
  NAME="${PAIR%%:*}"; BODY="${PAIR#*:}"
  assert_contains "is not a verdict" "$BODY" "$NAME states that an off-grammar line is no verdict"
  assert_contains "treated as a finding the critic never saw" "$BODY" "$NAME: no verdict means untouched"
done

_flow_test_begin "P3 findings never enter the critic"
for PAIR in "review.md:$REVIEW_TXT" "pr.md:$PR_TXT"; do
  NAME="${PAIR%%:*}"; BODY="${PAIR#*:}"
  assert_contains "P3 findings never enter the critic" "$BODY" "$NAME excludes P3"
done

_flow_test_begin "both commands state that Path A is unchanged by the grounding pass"
assert_match 'Path A.*(unchanged|not changed)' "$REVIEW_TXT" "review.md says Path A is unchanged"
assert_match 'Path A.*(unchanged|not changed)' "$PR_TXT" "pr.md says Path A is unchanged"

_flow_test_begin "the grounding step sits before finding routing"
# Routing (flow-finding-route.sh) consumes the confidence the grounding pass
# assigns, so a grounding block placed after it would be read by nothing.
GROUND_AT=$(printf '%s\n' "$REVIEW_TXT" | grep -n 'GROUNDING_CRITIC_BEGIN' | head -1 | cut -d: -f1)
ROUTE_AT=$(printf '%s\n' "$REVIEW_TXT" | grep -n 'flow-finding-route.sh' | tail -1 | cut -d: -f1)
assert_match '^[0-9]+$' "$GROUND_AT" "the gate block was located in review.md (line $GROUND_AT)"
assert_match '^[0-9]+$' "$ROUTE_AT" "the routing step was located in review.md (line $ROUTE_AT)"
if [ -n "$GROUND_AT" ] && [ -n "$ROUTE_AT" ] && [ "$GROUND_AT" -lt "$ROUTE_AT" ]; then
  _flow_assert_pass "grounding precedes routing ($GROUND_AT < $ROUTE_AT)"
else
  _flow_assert_fail "grounding must precede routing (grounding=$GROUND_AT routing=$ROUTE_AT)"
fi

# =============================================================================
# AC3 — settings.json and schema.json
# =============================================================================

_flow_test_begin "settings.json carries review.groundingCritic=off"
VAL=$(jq -r '.review.groundingCritic // empty' "$SETTINGS" 2>/dev/null)
assert_equal "off" "$VAL" "the shipped default is off"

_flow_test_begin "schema.json constrains review.groundingCritic to off|on"
ENUM=$(jq -r '.properties.review.properties.groundingCritic.enum | join(",")' "$SCHEMA" 2>/dev/null)
assert_equal "off,on" "$ENUM" "schema enum is exactly off,on"
DEF=$(jq -r '.properties.review.properties.groundingCritic.default // empty' "$SCHEMA" 2>/dev/null)
assert_equal "off" "$DEF" "schema default is off"
TYPE=$(jq -r '.properties.review.properties.groundingCritic.type // empty' "$SCHEMA" 2>/dev/null)
assert_equal "string" "$TYPE" "the setting is a string, so a third mode can be added later"

_flow_test_begin "schema rejects \"true\" and accepts \"on\""
IDX_TRUE=$(jq -r '.properties.review.properties.groundingCritic.enum | index("true")' "$SCHEMA" 2>/dev/null)
assert_equal "null" "$IDX_TRUE" "\"true\" is not an accepted value"
IDX_ON=$(jq -r '.properties.review.properties.groundingCritic.enum | index("on")' "$SCHEMA" 2>/dev/null)
assert_match '^[0-9]+$' "$IDX_ON" "\"on\" is an accepted value"
IDX_SHIPPED=$(jq -r --arg v "$VAL" '.properties.review.properties.groundingCritic.enum | index($v)' "$SCHEMA" 2>/dev/null)
assert_match '^[0-9]+$' "$IDX_SHIPPED" "the shipped value '$VAL' is inside the enum"

# --- functional: the extracted gate block ------------------------------------
# Same harness shape as tests/flow-agentteam-model.test.sh: stub cascade-resolve
# so the resolved value is controlled, source the block, read what it emits.
_run_grounding_block() {
  local stub_value="$1"
  local work; work=$(mktemp -d -t flow-gc-blk.XXXXXX)
  CLEANUP_PATHS+=("$work")
  mkdir -p "$work/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$stub_value" > "$work/bin/cascade-resolve.sh"
  chmod +x "$work/bin/cascade-resolve.sh"
  awk '/GROUNDING_CRITIC_BEGIN/{f=1;next} /GROUNDING_CRITIC_END/{f=0} f' "$REVIEW_MD" > "$work/block.sh"
  # An empty extraction would make every assertion below vacuous.
  [ -s "$work/block.sh" ] || printf '%s\n' "EXTRACTION_EMPTY" >&2
  ( set +u; CLAUDE_PLUGIN_ROOT="$work"; . "$work/block.sh" ) 2>"$work/err"
  cat "$work/err" >&2
  # This function is always called inside $(...), so the CLEANUP_PATHS append
  # above happens in a subshell the EXIT trap never sees. Remove the directory
  # here; the trap entry is belt and braces for paths added outside a command
  # substitution.
  rm -rf "$work" 2>/dev/null
}

_flow_test_begin "gate block: the block extracts and is non-empty"
BLOCK_ERR=$(_run_grounding_block "off" 2>&1 >/dev/null)
assert_not_contains "EXTRACTION_EMPTY" "$BLOCK_ERR" "the sentinels delimit a real block"

_flow_test_begin "gate block: 'on' passes the allowlist silently"
OUT=$(_run_grounding_block "on" 2>/dev/null)
ERR=$(_run_grounding_block "on" 2>&1 >/dev/null)
assert_contains "GROUNDING_CRITIC=on" "$OUT" "on is accepted"
assert_not_contains "WARN" "$ERR" "a valid value warns about nothing"

_flow_test_begin "gate block: 'off' passes the allowlist silently"
OUT=$(_run_grounding_block "off" 2>/dev/null)
ERR=$(_run_grounding_block "off" 2>&1 >/dev/null)
assert_contains "GROUNDING_CRITIC=off" "$OUT" "off is accepted"
assert_not_contains "WARN" "$ERR" "a valid value warns about nothing"

_flow_test_begin "gate block: 'true' is rejected with a WARN, not coerced to on"
OUT=$(_run_grounding_block "true" 2>/dev/null)
ERR=$(_run_grounding_block "true" 2>&1 >/dev/null)
assert_contains "GROUNDING_CRITIC=off" "$OUT" "true falls back to off"
assert_not_contains "GROUNDING_CRITIC=on" "$OUT" "true is never read as on"
assert_contains "WARN" "$ERR" "the rejection is loud"

_flow_test_begin "gate block: '1' is rejected with a WARN"
OUT=$(_run_grounding_block "1" 2>/dev/null)
ERR=$(_run_grounding_block "1" 2>&1 >/dev/null)
assert_contains "GROUNDING_CRITIC=off" "$OUT" "1 falls back to off"
assert_contains "WARN" "$ERR" "the rejection is loud"

_flow_test_begin "gate block: an empty resolution falls back to off with a WARN"
OUT=$(_run_grounding_block "" 2>/dev/null)
ERR=$(_run_grounding_block "" 2>&1 >/dev/null)
assert_contains "GROUNDING_CRITIC=off" "$OUT" "an empty resolution is off"
assert_contains "WARN" "$ERR" "the rejection is loud"

# =============================================================================
# AC4 — the two reference documents
# =============================================================================

FS_TXT=$(cat "$FINDING_SCHEMA")
JS_TXT=$(cat "$JOURNAL_SCHEMA")

_flow_test_begin "finding-schema documents the grounding field"
assert_contains '`grounding`' "$FS_TXT" "the field is named"
assert_contains "agreed" "$FS_TXT" "the agreed value is documented"
assert_contains "cited" "$FS_TXT" "the cited value is documented"

_flow_test_begin "grounding stays out of the marker row and the rendered suffix"
# The marker is parsed by bin/flow-finding-route.sh, commands/merge.md and
# commands/status.md. An eighth field would break all three.
assert_contains "F1|P1|security|src/auth.ts:42|open|HIGH|consensus" "$FS_TXT" "the canonical marker row is still 7 fields"
MARKER_ROW="F1|P1|security|src/auth.ts:42|open|HIGH|consensus"
FIELD_COUNT=$(printf '%s\n' "$MARKER_ROW" | awk -F'|' '{print NF}')
assert_equal "7" "$FIELD_COUNT" "the documented row has seven fields"
assert_not_contains "|grounding" "$FS_TXT" "no marker row carries a grounding field"

_flow_test_begin "decision-journal-schema documents both dropped-finding reasons"
assert_contains "critic-evidence" "$JS_TXT" "critic-evidence is documented"
assert_contains "critic-unrefuted-concern" "$JS_TXT" "critic-unrefuted-concern is documented"
# The values already existed as `finding-dismissed` reasons. The claim under
# test is that they are documented for `dropped-finding`, which is a different
# record: assert they appear in the dropped-finding reason paragraph.
DROPPED_PARA=$(printf '%s\n' "$JS_TXT" | grep '`dropped-finding` reason values')
assert_contains "critic-evidence" "$DROPPED_PARA" "the dropped-finding reason paragraph names critic-evidence"
assert_contains "critic-unrefuted-concern" "$DROPPED_PARA" "the dropped-finding reason paragraph names critic-unrefuted-concern"

# =============================================================================
# AC5 — where the pass sits relative to Path A
# =============================================================================

_flow_test_begin "paired-review-protocol places the grounding pass and keeps Path A unchanged"
PAIRED_TXT=$(cat "$PAIRED")
assert_contains "finding-critic" "$PAIRED_TXT" "the protocol names the critic"
assert_contains "groundingCritic" "$PAIRED_TXT" "the protocol names the setting"
assert_match 'Path A.*(unchanged|not changed)' "$PAIRED_TXT" "Path A is stated unchanged"
assert_contains "Path B" "$PAIRED_TXT" "the pass is placed on Path B"

_flow_test_begin "code-review-methodology places the grounding pass and keeps Path A unchanged"
METH_TXT=$(cat "$METHODOLOGY")
assert_contains "finding-critic" "$METH_TXT" "the skill names the critic"
assert_contains "groundingCritic" "$METH_TXT" "the skill names the setting"
assert_match 'Path A.*(unchanged|not changed)' "$METH_TXT" "Path A is stated unchanged"

# =============================================================================
# Roster check: the critic is reachable from the places that dispatch it
# =============================================================================

_flow_test_begin "every file that dispatches the critic names an agent that exists"
DISPATCHERS=$(grep -rl 'Agent(finding-critic)' "$PLUGIN_DIR/commands" 2>/dev/null | wc -l | tr -d ' ')
assert_equal "2" "$DISPATCHERS" "review.md and pr.md both dispatch it (found $DISPATCHERS)"
AGENT_NAME=$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$CRITIC")
assert_equal "finding-critic" "$AGENT_NAME" "the agent's declared name matches the dispatch"

# =============================================================================
# Drift guard: the two command copies of the grounding step must stay identical
# =============================================================================
# There is no include mechanism for command documents, so the step is written
# twice. Issue #218's worst review cycle was two command files whose duplicated
# text had drifted apart, so the duplication is pinned rather than trusted:
# everything between the shared sentinels must be byte-identical, and only the
# per-file preamble above the sentinels may differ.

_gc_shared() {
  awk '/GROUNDING_PASS_SHARED_BEGIN/{f=1;next} /GROUNDING_PASS_SHARED_END/{f=0} f' "$1"
}

_flow_test_begin "the shared grounding step is present in both commands"
SHARED_REVIEW=$(_gc_shared "$REVIEW_MD")
SHARED_PR=$(_gc_shared "$PR_MD")
SHARED_LINES=$(printf '%s\n' "$SHARED_REVIEW" | wc -l | tr -d ' ')
# An empty or one-line extraction would make the equality below vacuously true.
assert_match '^[1-9][0-9]+$' "$SHARED_LINES" "review.md's shared region has content ($SHARED_LINES lines)"
PR_SHARED_LINES=$(printf '%s\n' "$SHARED_PR" | wc -l | tr -d ' ')
assert_equal "$SHARED_LINES" "$PR_SHARED_LINES" "both shared regions are the same length"

_flow_test_begin "the two copies of the grounding step have not drifted"
if [ "$SHARED_REVIEW" = "$SHARED_PR" ]; then
  _flow_assert_pass "review.md and pr.md carry byte-identical shared grounding text"
else
  _flow_assert_fail "the shared grounding text has drifted between review.md and pr.md"
  diff <(printf '%s\n' "$SHARED_REVIEW") <(printf '%s\n' "$SHARED_PR") >&2
fi

_flow_test_begin "only a cited survivor is stamped HIGH"
# AGREE is the critic's default and covers "I cannot refute it" as well as "I
# read the code and it is right" (agents/finding-critic.md). Stamping an
# unrefuted LOW pattern-match HIGH would promote it into a merge blocker.
for _GC_FILE in "$REVIEW_MD" "$PR_MD"; do
  _GC_BLOCK=$(_gc_shared "$_GC_FILE")
  _GC_STAMP=$(printf '%s\n' "$_GC_BLOCK" | grep 'Stamp the survivors')
  assert_contains 'Only `grounding: cited` is stamped confidence HIGH' "$_GC_STAMP" \
    "$(basename "$_GC_FILE"): HIGH is reserved for a survivor with a citation"
  assert_contains 'keeps the confidence synthesis assigned' "$_GC_STAMP" \
    "$(basename "$_GC_FILE"): an unrefuted AGREE keeps its synthesis confidence"
  assert_not_contains 'and confidence HIGH' "$_GC_STAMP" \
    "$(basename "$_GC_FILE"): survival alone no longer stamps HIGH"
done

_flow_test_begin "each command keeps its own preamble outside the shared region"
# The preamble is where the two files legitimately differ: review.md has two
# dispatch paths and pr.md has one. If the preambles were identical too, one of
# them would be saying something untrue about its own command.
PRE_REVIEW=$(grep -n 'GROUNDING_PASS_SHARED_BEGIN' "$REVIEW_MD" | cut -d: -f1)
PRE_PR=$(grep -n 'GROUNDING_PASS_SHARED_BEGIN' "$PR_MD" | cut -d: -f1)
assert_match '^[0-9]+$' "$PRE_REVIEW" "review.md's shared region was located"
assert_match '^[0-9]+$' "$PRE_PR" "pr.md's shared region was located"
PRE_REVIEW_TXT=$(sed -n "$((PRE_REVIEW - 2))p" "$REVIEW_MD")
PRE_PR_TXT=$(sed -n "$((PRE_PR - 2))p" "$PR_MD")
assert_contains "Grounding pass" "$PRE_REVIEW_TXT" "review.md's preamble introduces the pass"
assert_contains "Grounding pass" "$PRE_PR_TXT" "pr.md's preamble introduces the pass"

_flow_test_begin "review.md skips the grounding pass on a Path A run"
# /flow:review Phase 4 is reached by BOTH dispatch paths: Path A and Path B
# share the synthesis step, so "Path B only" has to be said in the preamble or
# it is not said anywhere. pr.md has no Path A, so only review.md needs it.
assert_contains "USE_PATH_A=0" "$PRE_REVIEW_TXT" "review.md ties the pass to the Path B gate value"
assert_contains "USE_PATH_A=1" "$PRE_REVIEW_TXT" "review.md says what to do on a Path A run"
assert_not_contains "USE_PATH_A" "$SHARED_REVIEW" "the gate value stays in the preamble, not the shared text"

# =============================================================================
# Functional: the real resolver, not only the stub
# =============================================================================
# Every gate-block assertion above stubs cascade-resolve.sh. A stub cannot
# catch a wrong argument signature: the block's `2>/dev/null` plus the `*)`
# fallback would turn that into GROUNDING_CRITIC=off, which is also what a
# correctly-resolved default looks like.

_flow_test_begin "cascade-resolve resolves the shipped default through the plugin tier"
CASCADE="$PLUGIN_DIR/bin/cascade-resolve.sh"
RESOLVED=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$CASCADE" --default off '.review.groundingCritic // empty' 2>/dev/null)
assert_equal "off" "$RESOLVED" "the plugin tier resolves review.groundingCritic to off"

_flow_test_begin "cascade-resolve honours a project-local override"
GC_SCRATCH=$(mktemp -d -t flow-gc-cas.XXXXXX)
CLEANUP_PATHS+=("$GC_SCRATCH")
mkdir -p "$GC_SCRATCH/.claude"
printf '%s\n' '{"review":{"groundingCritic":"on"}}' > "$GC_SCRATCH/.claude/settings.flow.local.json"
RESOLVED_ON=$( cd "$GC_SCRATCH" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$CASCADE" --default off '.review.groundingCritic // empty' 2>/dev/null )
assert_equal "on" "$RESOLVED_ON" "a local settings.flow.local.json override resolves to on"

_flow_test_begin "the gate block run against the real resolver yields the shipped default"
GC_REAL=$(mktemp -d -t flow-gc-real.XXXXXX)
CLEANUP_PATHS+=("$GC_REAL")
awk '/GROUNDING_CRITIC_BEGIN/{f=1;next} /GROUNDING_CRITIC_END/{f=0} f' "$REVIEW_MD" > "$GC_REAL/block.sh"
REAL_OUT=$( cd "$GC_REAL" && set +u; CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"; . "$GC_REAL/block.sh" 2>"$GC_REAL/err" )
REAL_ERR=$(cat "$GC_REAL/err")
assert_contains "GROUNDING_CRITIC=off" "$REAL_OUT" "the real resolver drives the block to off"
assert_not_contains "WARN" "$REAL_ERR" "the real resolver produces a value the allowlist accepts"

# =============================================================================
# Roster: the README agent count tracks the agents directory
# =============================================================================

_flow_test_begin "README's agent roster counts the critic"
README_MD="$PLUGIN_DIR/README.md"
AGENT_FILES=$(ls -1 "$PLUGIN_DIR"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
assert_match '^[1-9][0-9]*$' "$AGENT_FILES" "the agents directory was read ($AGENT_FILES files)"
README_N=$(grep -oE 'AGENTS \(([0-9]+)\)' "$README_MD" | grep -oE '[0-9]+' | head -1)
assert_equal "$AGENT_FILES" "$README_N" "README AGENTS ($README_N) equals $AGENT_FILES agent files"
assert_contains "finding-critic" "$(cat "$README_MD")" "README lists the critic by name"
