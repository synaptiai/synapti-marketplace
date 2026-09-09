# Static lints for the verdict-judge Independence Protocol.
#
# Contract under test:
#   - agents/verdict-judge.md declares no file tools in its frontmatter
#     (no Read/Bash/Grep/Glob/Edit/Write) and says so in its body, so the
#     protocol ("never open a test file / screenshot") is enforced by the
#     tool list rather than by prose alone.
#   - agents/goal-evaluator-judge.md (which inherits the protocol) declares
#     no file tools either.
#   - references/evidence-bundle-format.md lists `### Visual analysis` as a
#     mandatory per-criterion subsection and its sample bundle carries the
#     per-viewport Observed: blocks the judge evaluates instead of images.
#   - commands/start.md and commands/pr.md enumerate `### Visual analysis`
#     when they describe the bundle, so the producer emits it.
#   - skills/visual-verification/SKILL.md's Output Format contains the
#     `Observed:` line the producer copies into the bundle.
#   - No agent, command, reference, or skill still tells the judge it may
#     read a screenshot.

FLOW_DIR="$REPO_ROOT/plugins/flow"
JUDGE="$FLOW_DIR/agents/verdict-judge.md"
GOAL_JUDGE="$FLOW_DIR/agents/goal-evaluator-judge.md"
BUNDLE_REF="$FLOW_DIR/references/evidence-bundle-format.md"
VERDICT_REF="$FLOW_DIR/references/verdict-output-format.md"
START_CMD="$FLOW_DIR/commands/start.md"
PR_CMD="$FLOW_DIR/commands/pr.md"
VISUAL_SKILL="$FLOW_DIR/skills/visual-verification/SKILL.md"
CVM_SKILL="$FLOW_DIR/skills/criterion-verification-map/SKILL.md"

# Frontmatter = lines between the first two `---` lines.
_frontmatter() {
  awk 'NR==1 && /^---$/ {fm=1; next} fm==1 && /^---$/ {exit} fm==1 {print}' "$1"
}
# Body = everything after the closing frontmatter `---`.
_body() {
  awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } {print}' "$1"
}

# --- Test 1: verdict-judge frontmatter keeps a `tools:` key with no file tools
_flow_test_begin "verdict-judge frontmatter declares no file tools"
assert_file_exists "$JUDGE" "verdict-judge agent exists"
JUDGE_FM=$(_frontmatter "$JUDGE")
TOOLS_LINE=$(printf '%s\n' "$JUDGE_FM" | grep -E '^tools:' || true)
assert_match '^tools:' "$TOOLS_LINE" "tools: key is present in frontmatter"
for TOOL in Read Bash Grep Glob Edit Write; do
  if printf '%s\n' "$TOOLS_LINE" | grep -qE "(^|[^A-Za-z])${TOOL}([^A-Za-z]|$)"; then
    _flow_assert_fail "verdict-judge tools list grants $TOOL: '$TOOLS_LINE'"
  else
    _flow_assert_pass "verdict-judge tools list does not grant $TOOL"
  fi
done

# --- Test 2: the body states the mechanical rule and its FAIL rationale
_flow_test_begin "verdict-judge body states it has no file tools"
JUDGE_BODY=$(_body "$JUDGE")
assert_contains "no file tools" "$JUDGE_BODY" "body contains 'no file tools'"
assert_contains "evidence not in bundle" "$JUDGE_BODY" "body names the 'evidence not in bundle' rationale"
assert_contains "### Visual analysis" "$JUDGE_BODY" "body reads the Visual analysis subsection"
assert_contains "Observed:" "$JUDGE_BODY" "body judges the Observed: sentences"
assert_not_contains "if you can read the screenshot" "$JUDGE_BODY" "old screenshot-reading rule is gone"

# --- Test 3: goal-evaluator-judge inherits the protocol mechanically
_flow_test_begin "goal-evaluator-judge frontmatter declares no file tools"
GOAL_FM=$(_frontmatter "$GOAL_JUDGE")
GOAL_TOOLS=$(printf '%s\n' "$GOAL_FM" | grep -E '^tools:' || true)
assert_match '^tools:' "$GOAL_TOOLS" "tools: key is present in goal-evaluator-judge frontmatter"
for TOOL in Read Bash Grep Glob Edit Write; do
  if printf '%s\n' "$GOAL_TOOLS" | grep -qE "(^|[^A-Za-z])${TOOL}([^A-Za-z]|$)"; then
    _flow_assert_fail "goal-evaluator-judge tools list grants $TOOL: '$GOAL_TOOLS'"
  else
    _flow_assert_pass "goal-evaluator-judge tools list does not grant $TOOL"
  fi
done

# --- Test 4: the bundle format makes Visual analysis mandatory
_flow_test_begin "evidence-bundle-format lists Visual analysis as mandatory"
BUNDLE=$(cat "$BUNDLE_REF")
TABLE_ROW=$(printf '%s\n' "$BUNDLE" | grep -E '^\| `### Visual analysis` \|' || true)
assert_match 'Visual analysis' "$TABLE_ROW" "mandatory-subsections table has a Visual analysis row"
assert_match 'auto-FAIL' "$TABLE_ROW" "Visual analysis row is an auto-FAIL trigger"
assert_match '`ui`' "$TABLE_ROW" "Visual analysis row is conditioned on the ui type"
assert_contains "none — criterion type {type} has no visual surface" "$BUNDLE" "non-ui none form is documented"
assert_contains "Viewport: desktop 1280x720" "$BUNDLE" "sample bundle carries a desktop viewport block"
assert_contains "Viewport: mobile 375x812" "$BUNDLE" "sample bundle carries a mobile viewport block"
assert_match '^Observed: ' "$BUNDLE" "sample bundle carries Observed: sentences"
assert_contains "no file tools" "$BUNDLE" "bundle format states the judge has no file tools"

# --- Test 5: the verdict output shape carries the Visual analysis column
_flow_test_begin "verdict-output-format carries the Visual Analysis column and rationale phrases"
VERDICT=$(cat "$VERDICT_REF")
assert_contains "Visual Analysis Present?" "$VERDICT" "coverage scan has the Visual Analysis column"
assert_contains "visual analysis does not show required state" "$VERDICT" "Step 2 visual rationale phrase listed"
assert_contains "evidence not in bundle" "$VERDICT" "evidence-not-in-bundle rationale phrase listed"

# --- Test 6: producers enumerate the subsection
_flow_test_begin "start.md and pr.md enumerate ### Visual analysis"
assert_contains '`### Visual analysis`' "$(cat "$START_CMD")" "start.md Phase 4 step 5 enumerates the subsection"
assert_contains '`### Visual analysis`' "$(cat "$PR_CMD")" "pr.md enumerates the subsection"
assert_contains '`### Visual analysis`' "$(cat "$CVM_SKILL")" "criterion-verification-map produces the subsection"

# --- Test 7: the visual-verification skill emits the Observed: line
_flow_test_begin "visual-verification output format contains Observed:"
OUTPUT_SECTION=$(awk '/^## Output Format/ {on=1; next} on && /^## / {exit} on {print}' "$VISUAL_SKILL")
assert_contains "Observed:" "$OUTPUT_SECTION" "Output Format section contains Observed:"
assert_contains "### Visual analysis" "$OUTPUT_SECTION" "Output Format section carries the Visual analysis heading"
assert_contains "Viewport:" "$OUTPUT_SECTION" "Output Format section carries the Viewport: line"

# --- Test 8: nothing in the plugin still lets the judge read screenshots
_flow_test_begin "no agent, command, reference, or skill tells the judge to read a screenshot"
OFFENDERS=$(grep -rl "if you can read the screenshot" \
  "$FLOW_DIR/agents" "$FLOW_DIR/commands" "$FLOW_DIR/references" "$FLOW_DIR/skills" 2>/dev/null || true)
assert_equal "" "$OFFENDERS" "no file contains 'if you can read the screenshot'"
