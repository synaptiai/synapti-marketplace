# Tests for interaction flows in visual verification — issue #218.
#
# Contract under test:
#   - A UI criterion whose text carries an interaction verb is verified by PERFORMING the
#     interaction, not by screenshotting the page before it. The skill states which criteria
#     qualify, the step grammar, and the `Step:` block shape.
#   - Only a tool that can click counts as interactive. The CLI screenshot fallback cannot,
#     so a flow never "runs" through it and reports a pass having done nothing.
#   - The verdict-judge's rule (d) is UNCHANGED: page-load coverage across every configured
#     viewport does not regress. A separate rule reads `Step:` blocks, and a criterion with an
#     interaction verb and no step block is an auto-FAIL with its own rationale.
#   - The console tool is `browser_console_messages`. An earlier name in this skill was one the
#     server does not expose, so the console check could never run and nothing said so.
#
# What these tests CANNOT show: that any of it drives a real browser. This repository is a
# markdown plugin with no UI and no dev server, so nothing here can execute a click. These
# assertions cover the contract and its consumers, which is what the repository can verify.
#
# Prereq: python3 for the JSON schema assertions. SKIPS gracefully if absent.

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
SKILL="$PLUGIN_DIR/skills/visual-verification/SKILL.md"
JUDGE="$PLUGIN_DIR/agents/verdict-judge.md"
VERDICT_FMT="$PLUGIN_DIR/references/verdict-output-format.md"
BUNDLE_FMT="$PLUGIN_DIR/references/evidence-bundle-format.md"
VIS_OUT="$PLUGIN_DIR/references/visual-verification-output.md"
INTEG="$PLUGIN_DIR/agents/integration-verifier.md"
SETTINGS="$PLUGIN_DIR/settings.json"
SCHEMA="$PLUGIN_DIR/schema.json"

# =============================================================================
# The tool name that does not exist
# =============================================================================

_flow_test_begin "no file names a browser tool the server does not expose"
# Verified against the Playwright MCP server's own documentation on 2026-09-21:
# the console tool is `browser_console_messages`. The wrong name was present
# twice, and a call to a tool that does not exist finds nothing and says
# nothing — the console check simply never ran.
#
# The needle is assembled rather than written out, because the criterion is
# that the string appears in NO file under plugins/flow, and this file is one
# of them. A test that had to spell the forbidden name would fail itself.
WRONG_TOOL="browser_console""_logs"
HITS=$(grep -rl "$WRONG_TOOL" "$PLUGIN_DIR" 2>/dev/null | wc -l | tr -d ' ')
assert_equal "0" "$HITS" "the non-existent console tool is named in no file under plugins/flow"

_flow_test_begin "the interactive tools the skill names are the ones the server has"
SKILL_TXT=$(cat "$SKILL")
for T in browser_navigate browser_snapshot browser_click browser_type \
         browser_take_screenshot browser_console_messages; do
  assert_contains "$T" "$SKILL_TXT" "the cascade names $T"
done

# =============================================================================
# Which criteria get a flow, and how a step is written
# =============================================================================

_flow_test_begin "the cue-verb list is stated, identically, everywhere it appears"
# A per-verb file-wide match is not a test: deleting the whole list still left
# click, type and navigate matching browser_click/browser_type/browser_navigate
# and select matching "selector". Assert the list as one string, in each file
# that repeats it, so the three copies cannot drift apart either.
VERBS="click, submit, type, select, toggle, open, navigate, drag"
SKILL_FLAT=$(printf '%s\n' "$SKILL_TXT" | tr '\n' ' ' | tr -s ' ')
assert_contains "$VERBS" "$SKILL_FLAT" "the skill states the list"
for F in "$JUDGE" "$BUNDLE_FMT" "$VIS_OUT"; do
  FLAT=$(printf '%s\n' "$(cat "$F")" | tr '\n' ' ' | tr -s ' ')
  assert_contains "$VERBS" "$FLAT" "$(basename "$F") states the same list"
done

_flow_test_begin "the step grammar is stated, with all four step kinds"
for STEP in "navigate <route>" "click <element>" "type <element> <text>" "expect <element or text>"; do
  assert_contains "$STEP" "$SKILL_TXT" "the grammar defines: $STEP"
done

_flow_test_begin "element targets come from the accessibility tree, never a guess"
assert_contains "browser_snapshot" "$SKILL_TXT" "the snapshot is named as the source of targets"
assert_match "never from a selector|not from a selector|never.*guessed" "$SKILL_TXT" \
  "and guessing one is ruled out"

_flow_test_begin "the Step line shape is fixed"
assert_contains 'Step: {n}/{m} {action}' "$SKILL_TXT" "the skill shows the Step line"
assert_contains "Step: {n}/{m} {action}" "$(cat "$BUNDLE_FMT")" \
  "and the bundle format states the same shape"

_flow_test_begin "a scenario is bounded and says where it stopped"
# The bound is a rule, so it is in the skill; what happens on reaching it is
# procedure, so it is in the reference the skill points at.
assert_contains "maxFlowSteps" "$SKILL_TXT" "the step bound is named in the skill"
VIS_TXT=$(cat "$VIS_OUT")
assert_match "STOPS and reports the steps it completed" "$VIS_TXT" \
  "and the reference says reaching it stops rather than truncating silently"
assert_match "does not silently truncate" "$VIS_TXT" "stated as the rule it is"

# =============================================================================
# Only a tool that can click may run a flow
# =============================================================================

_flow_test_begin "the cascade says which entries can interact"
# The RULE is in the skill; the roster table is in the reference. Both are
# checked, and the CLI's own row is checked rather than the words appearing
# somewhere in the file — the prose also says a screenshot tool cannot click,
# so a file-wide match stayed green when the row itself was flipped to Yes.
# Collapse newlines before matching: these sentences wrap, and grep is
# line-oriented, so a needle spanning a line break silently never matches —
# which is how a garbled sentence passed a test written to catch it.
SKILL_FLAT=$(printf '%s\n' "$SKILL_TXT" | tr '\n' ' ' | tr -s ' ')
assert_contains "Playwright MCP and Chrome DevTools MCP are interactive" "$SKILL_FLAT" \
  "the skill names which tools can interact"
assert_contains "browser skills are **not**" "$SKILL_FLAT" \
  "and which cannot"
VIS_TXT=$(cat "$VIS_OUT")
assert_match "Interactive" "$VIS_TXT" "the reference roster carries an interactive column"
CLI_ROW=$(printf '%s\n' "$VIS_TXT" | grep 'npx playwright screenshot')
assert_match "\| No \|" "$CLI_ROW" "the CLI row is marked non-interactive"
assert_not_contains "| Yes |" "$CLI_ROW" "and is not marked interactive"

_flow_test_begin "no interactive tool is a skip or a block, never a silent pass"
assert_contains "SKIP_WARN" "$SKILL_TXT" "absence is SKIP_WARN by default"
assert_contains "BLOCKED" "$SKILL_TXT" "and BLOCKED when verification is required"
assert_match "[Nn]ever install silently|[Nn]ever install Playwright silently" "$SKILL_TXT" \
  "nothing is installed silently"

# =============================================================================
# Settings and schema
# =============================================================================

_flow_test_begin "settings.json carries the two new keys with the documented defaults"
RESULT=$(python3 - "$SETTINGS" <<'PYEOF'
import json, sys
vv = json.load(open(sys.argv[1]))["visualVerification"]
print("flows=%r maxFlowSteps=%r" % (vv.get("flows"), vv.get("maxFlowSteps")))
PYEOF
)
assert_contains "flows='on'" "$RESULT" "flows defaults to on"
assert_contains "maxFlowSteps=8" "$RESULT" "maxFlowSteps defaults to 8"

_flow_test_begin "schema.json constrains flows to an enum and maxFlowSteps to a bounded integer"
# Placed with the settings-schema assertions, following flow-agentteam-model.test.sh.
# tests/flow-schemas.test.sh validates the .flow/ artifact schemas under schemas/v1/
# and never reads schema.json, which is why the issue's original wording named
# the wrong file.
RESULT=$(python3 - "$SCHEMA" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))["properties"]["visualVerification"]["properties"]
f, m = p.get("flows", {}), p.get("maxFlowSteps", {})
print("flows_type=%s" % f.get("type"))
print("flows_enum=%s" % ",".join(f.get("enum", [])))
print("flows_default=%s" % f.get("default"))
print("steps_type=%s" % m.get("type"))
print("steps_default=%s" % m.get("default"))
print("steps_min=%s steps_max=%s" % (m.get("minimum"), m.get("maximum")))
PYEOF
)
assert_contains "flows_type=string" "$RESULT" "flows is a string, not a boolean"
assert_contains "flows_enum=on,off" "$RESULT" "constrained to on and off"
assert_contains "flows_default=on" "$RESULT" "defaulting to on"
assert_contains "steps_type=integer" "$RESULT" "maxFlowSteps is an integer"
assert_contains "steps_default=8" "$RESULT" "defaulting to 8"
assert_match "steps_min=[0-9]+ steps_max=[0-9]+" "$RESULT" "and bounded at both ends"

_flow_test_begin "a settings fixture with flows: true is rejected and \"off\" accepted"
# The point of the enum: `true` must not read as enabled anywhere.
RESULT=$(python3 - "$SCHEMA" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1]))
try:
    import jsonschema
except ImportError:
    print("SKIP: jsonschema not importable"); raise SystemExit(0)
sub = {"type": "object", "properties": {"visualVerification": schema["properties"]["visualVerification"]}}
for label, value in (("bool", True), ("string-off", "off"), ("string-bogus", "sometimes")):
    doc = {"visualVerification": {"flows": value}}
    try:
        jsonschema.validate(doc, sub)
        print("%s=accepted" % label)
    except jsonschema.ValidationError:
        print("%s=rejected" % label)
PYEOF
)
case "$RESULT" in
  SKIP*) _flow_assert_pass "SKIP: jsonschema not importable" ;;
  *)
    assert_contains "bool=rejected" "$RESULT" "flows: true is rejected"
    assert_contains "string-off=accepted" "$RESULT" "flows: \"off\" is accepted"
    assert_contains "string-bogus=rejected" "$RESULT" "a value outside the enum is rejected"
    ;;
esac

# =============================================================================
# The judge: rule (d) unchanged, a separate rule for steps
# =============================================================================

JUDGE_TXT=$(cat "$JUDGE")

_flow_test_begin "rule (d) still demands every configured viewport"
# The regression this guards: treating a step block as a viewport block would
# make a desktop-only flow fail rule (d) and every interaction criterion fail
# with it.
assert_contains "every configured viewport block reports \`Result: PASS\`" "$JUDGE_TXT" \
  "rule (d) is untouched"

_flow_test_begin "step blocks are additional to viewport blocks, never a replacement"
# The decision the whole judge rule rests on. If step blocks replaced viewport
# blocks, an interaction criterion would lose the render check on every
# viewport the flow did not run — which is what visual verification existed to
# do before this issue added flows. Asserted in the skill (the rule), the
# bundle format (the producer) and the judge (the consumer), because all three
# have to agree or the bundle and the gate disagree about what is required.
assert_contains "additional to viewport blocks, never" "$SKILL_FLAT" \
  "the skill states it"
BUNDLE_FLAT=$(printf '%s\n' "$(cat "$BUNDLE_FMT")" | tr '\n' ' ' | tr -s ' ')
assert_contains "additional to the viewport blocks, not a substitute" "$BUNDLE_FLAT" \
  "the bundle format states it"
JUDGE_FLAT=$(printf '%s\n' "$(cat "$JUDGE")" | tr '\n' ' ' | tr -s ' ')
assert_contains "does not satisfy rule (d)" "$JUDGE_FLAT" \
  "and the judge counts the two separately"

_flow_test_begin "a step block is not counted as a viewport block"
assert_match "does not satisfy rule \(d\)|not a viewport" "$JUDGE_TXT" \
  "the judge is told the two are counted separately"

_flow_test_begin "a criterion with an interaction verb needs a step block"
# The rationale string appears in the Step 1 list and again in rule (e).
# Asserting it once anywhere stayed green when one of the two was deleted, so
# assert both sites and the reason the rule exists.
COUNT=$(printf '%s\n' "$JUDGE_TXT" | grep -c "incomplete evidence — missing interaction steps on a ui criterion")
[ "$COUNT" -ge 2 ] && _flow_assert_pass "the rationale is stated at both decision points ($COUNT)" \
  || _flow_assert_fail "the rationale appears $COUNT time(s); Step 1 and rule (e) both need it"
assert_match "screenshot of the page before the interaction is not evidence" "$JUDGE_TXT" \
  "and the judge is told why a page screenshot does not stand in for a step"
assert_contains "incomplete evidence — missing interaction steps on a ui criterion" \
  "$(cat "$VERDICT_FMT")" "and the output format publishes the same string"
assert_contains "incomplete evidence — missing interaction steps on a ui criterion" \
  "$(cat "$BUNDLE_FMT")" "and the bundle format names it as an auto-FAIL"

_flow_test_begin "a failing step fails the criterion"
assert_match "Step:.*\`Result: FAIL\`|\`Result: FAIL\`.*Step:" "$JUDGE_TXT" \
  "a step reporting FAIL is a failure"

_flow_test_begin "the coverage scan reports whether steps are present"
assert_contains "Interaction Steps Present?" "$(cat "$VERDICT_FMT")" \
  "the scan table has its own column"

_flow_test_begin "the judge still never opens a screenshot or a video"
assert_match "never opens it|never the image" "$JUDGE_TXT" \
  "the judge reads sentences, not media"

# =============================================================================
# Video is conditional and load-bearing on nothing
# =============================================================================

_flow_test_begin "video is recorded when available and required never"
assert_contains "browser_start_video" "$SKILL_TXT" "the tool is named"
assert_match "not.*a skip, a warning or a finding|absence is \*\*not\*\*" "$SKILL_TXT" \
  "and its absence changes nothing"

_flow_test_begin "no result value depends on video"
# The result vocabulary is the gate. If video leaked into it, a missing
# capability would start failing runs.
# The vocabulary moved to the reference during the restructure. Slicing the
# skill left an EMPTY string, and an assert_not_contains on "" passes for any
# implementation — this is the test guarding the unverifiable-capability risk,
# so it asserts the slice is non-empty before asserting what is absent from it.
VOCAB=$(printf '%s\n' "$(cat "$VIS_OUT")" | sed -n '/^## Result vocabulary$/,/^## /p')
assert_contains "SKIP_WARN" "$VOCAB" "the vocabulary section was found and is non-empty"
assert_contains "BLOCKED" "$VOCAB" "and carries every value"
# The section may SAY that no value depends on video — that is the guarantee.
# What must not happen is a result VALUE whose meaning involves it, so check
# the table rows rather than the prose.
VOCAB_ROWS=$(printf '%s\n' "$VOCAB" | grep '^| `')
assert_contains "SKIP_WARN" "$VOCAB_ROWS" "the rows were found"
assert_not_contains "video" "$VOCAB_ROWS" "no result value's meaning involves video"
assert_not_contains "Video" "$VOCAB_ROWS" "in either case"
assert_match "no value depends on whether video" "$VOCAB" \
  "and the section says so explicitly"

# =============================================================================
# The skill is given what it needs to derive a scenario at all
# =============================================================================

_flow_test_begin "integration-verifier passes the criteria text and the risk-map rows"
INTEG_TXT=$(cat "$INTEG")
assert_match "FULL TEXT|full text" "$INTEG_TXT" "the criteria are passed verbatim, not summarised"
assert_contains "Risk-map rows" "$INTEG_TXT" "and the risk-map rows are passed"

_flow_test_begin "the reference shows a completed flow"
VIS_TXT=$(cat "$VIS_OUT")
assert_contains "Step: 1/3 navigate /signup" "$VIS_TXT" "the example has a first step"
assert_contains "Step: 3/3 click" "$VIS_TXT" "and a last step"
# Every step gets a block: a flow reporting only its final state cannot show
# that the error appeared BECAUSE of the interaction.
COUNT=$(printf '%s\n' "$VIS_TXT" | grep -c '^Step: ')
[ "$COUNT" -ge 3 ] && _flow_assert_pass "every step carries its own block ($COUNT)" \
  || _flow_assert_fail "only $COUNT step block(s); the example should show each step"
assert_match "AFTER this step|AFTER the step|after that step" "$VIS_TXT" \
  "and Observed: describes the page after the step"

# =============================================================================
# Review cycle 1 — the auto-FAIL must not fire on a flow that never ran
# =============================================================================

_flow_test_begin "the producer says why no flow ran, and the judge accepts that"
# The defect: with flows off, or no interactive browser tool, a criterion
# describing a user action had no Step: block — and the judge auto-FAILed it.
# The judge receives only the criteria, the bundle and the holdout output; it
# never sees settings.json, so it cannot tell a correctly skipped flow from an
# omitted one. Without the marker, every interaction criterion fails on every
# repository with flows off or no Playwright MCP.
JUDGE_FLAT=$(printf '%s\n' "$(cat "$JUDGE")" | tr '\n' ' ' | tr -s ' ')
BUNDLE_FLAT=$(printf '%s\n' "$(cat "$BUNDLE_FMT")" | tr '\n' ' ' | tr -s ' ')
# The skill has TWO marker sites — flows off / no interactive tool, and no
# interaction in the criterion. A single contains-check stayed green when one
# was deleted, so count them.
MARKERS=$(printf '%s\n' "$SKILL_TXT" | grep -c 'Flows: none')
[ "$MARKERS" -ge 2 ] && _flow_assert_pass "the skill writes the marker on both paths ($MARKERS)" \
  || _flow_assert_fail "the skill names the marker $MARKERS time(s); both paths need it"
assert_match "off, or no interactive.*write .Flows: none" "$SKILL_FLAT" \
  "including when flows are off or no interactive tool was found"
assert_contains "Flows: none" "$BUNDLE_FLAT" "the bundle format defines it"
assert_contains "no \`Flows: none — {reason}\` line" "$JUDGE_FLAT" \
  "and the judge's auto-FAIL requires its absence"
assert_match "never sees|receive no settings|cannot determine that yourself" "$JUDGE_FLAT" \
  "with the reason it cannot decide this itself"

_flow_test_begin "each reason for not running a flow has a spelling"
# Check the spellings in the reference AND in the producer skill and the
# judge. The judge recognises a legitimate reason by its spelling alone, so
# producer and consumer drifting apart silently breaks the marker.
VIS_FLAT=$(printf '%s\n' "$(cat "$VIS_OUT")" | tr '\n' ' ' | tr -s ' ')
JUDGE_REASONS=$(printf '%s\n' "$(cat "$JUDGE")" | tr '\n' ' ' | tr -s ' ')
for R in "visualVerification.flows=off" "no interactive tool" "no interaction"; do
  assert_contains "$R" "$VIS_FLAT" "the reference spells: $R"
  assert_contains "$R" "$JUDGE_REASONS" "and the judge accepts exactly: $R"
done
assert_contains "Flows: none — no interaction" "$SKILL_FLAT" \
  "the producer skill uses the same spelling it will be judged by"
# Slice the Step 1 bullet. A file-wide match was satisfied by an unrelated
# pre-existing "producer non-conforming" sentence, so deleting the new
# enforcement left the suite green — the unbounded-reason defect was pinned
# by nothing.
STEP1_RULE=$(printf '%s\n' "$(cat "$JUDGE")" | grep 'one of exactly three')
assert_contains "producer non-conforming" "$STEP1_RULE" \
  "the reason set is enforced in the rule that uses it"
assert_contains "does NOT suppress this auto-FAIL" "$STEP1_RULE" \
  "and a non-conforming reason does not suppress the auto-FAIL"

_flow_test_begin "the producer is told to copy the step blocks"
# The blocks the skill makes never reached the bundle: the copy instruction
# named viewport blocks only, so the judge auto-FAILed the very criterion the
# feature exists to verify — on the happy path, with everything working.
assert_match "Copy every .Step:. block" "$BUNDLE_FLAT" \
  "the bundle format's copy step includes them"
START_FLAT=$(printf '%s\n' "$(cat "$PLUGIN_DIR/commands/start.md")" | tr '\n' ' ' | tr -s ' ')
assert_contains "Step:" "$START_FLAT" "and so does the bundle assembly in start.md"

_flow_test_begin "a failing step fails the criterion however the flow was triggered"
# A flow can be triggered by a risk-map row rather than the criterion's
# wording. Gating the failure clause on a cue verb meant a step reporting FAIL
# in a risk-map-triggered flow was read by no rule at all, and the criterion
# passed on its page-load blocks.
assert_match "Whenever step blocks are present" "$JUDGE_FLAT" \
  "the failure clause is not conditioned on the trigger"
assert_match "a failing step is a failing step" "$JUDGE_FLAT" "and says so"

_flow_test_begin "an Observed: that does not describe the step fails, as for a viewport"
assert_match "does not describe the page after that step . FAIL" "$JUDGE_FLAT" \
  "rule (e) states the same consequence rule (d) does"

_flow_test_begin "the coverage scan template carries the new column"
# The column was defined in the semantics table but absent from the template
# the judge emits, and the old assertion grepped the whole file so it matched
# the definition and never noticed the template.
HEADER=$(grep '^| # | Criterion |' "$VERDICT_FMT" | head -1)
assert_contains "Interaction Steps Present?" "$HEADER" "the emitted header row has it"
assert_match "Interaction Steps Present" "$JUDGE_FLAT" "and the judge enumerates it"
# The value that records "skipped, with a stated reason" was pinned nowhere —
# replacing it with a bare N/A everywhere left the suite green, and a bare
# N/A loses the very fact the value exists to carry.
# Assert the SEMANTICS, not just the value: the value also appears in the
# column's type list, so deleting the clause that gives it meaning left a
# bare-`N/A` mutant alive.
VOF_FLAT=$(printf '%s\n' "$(cat "$VERDICT_FMT")" | tr '\n' ' ' | tr -s ' ')
assert_contains 'N/A (no flow: {reason})' "$VOF_FLAT" "the value exists"
assert_match "quoting that reason so the scan records why" "$VOF_FLAT" \
  "and the scan records WHY the interaction was not exercised"
assert_contains 'N/A (no flow: {reason})' "$(cat "$JUDGE")" \
  "and the judge enumerates the same value"
assert_match "Yes. whenever any .Step:. block is present" "$JUDGE_FLAT" \
  "and a step block takes precedence over the marker"

_flow_test_begin "both dispatch paths hand the skill what it needs"
# integration-verifier was updated; the /flow:start path was not, and the skill
# runs in its own context so the criteria text is exactly what it lacks.
# Slice the dispatch itself. A file-wide match was satisfied by start.md's
# pre-existing plan-time "Risk areas: {risk-map rows ...}" line, which has
# nothing to do with the Phase 4 dispatch — so deleting the clause from the
# dispatch left the suite green.
INTEG_DISPATCH=$(printf '%s\n' "$(cat "$INTEG")" | tr '\n' ' ' | tr -s ' ')
assert_match "full text|FULL TEXT" "$INTEG_DISPATCH" "integration-verifier passes the criteria verbatim"
assert_match "[Rr]isk-map row" "$INTEG_DISPATCH" "integration-verifier passes the risk-map rows"
START_DISPATCH=$(grep -A4 'invoke `Skill(visual-verification)` in parallel' \
  "$PLUGIN_DIR/commands/start.md" | tr '\n' ' ' | tr -s ' ')
assert_match "full text|FULL TEXT" "$START_DISPATCH" \
  "the /flow:start dispatch itself passes the criteria verbatim"
assert_match "[Rr]isk-map row" "$START_DISPATCH" \
  "and the risk-map rows, in that same dispatch"

_flow_test_begin "every consumer knows about BOTH halves of the contract"
# The feature has two halves: the step blocks, and the marker that explains
# their absence. Asserting only the first left five mutants on the second
# surviving green — every consumer could forget the marker and the suite
# would not notice, which is precisely the regression cycle 1 fixed.
for F in "$PLUGIN_DIR/commands/start.md" \
         "$PLUGIN_DIR/skills/criterion-verification-map/SKILL.md" \
         "$PLUGIN_DIR/references/gate-configuration.md" \
         "$PLUGIN_DIR/references/verdict-output-format.md" \
         "$PLUGIN_DIR/references/evidence-bundle-format.md" \
         "$PLUGIN_DIR/agents/verdict-judge.md"; do
  C=$(cat "$F")
  assert_contains "Step:" "$C" "$(basename "$F") mentions the step blocks"
  assert_contains "Flows: none —" "$C" \
    "$(basename \"$F\") uses the marker spelling the judge matches on"
done

_flow_test_begin "the Step placeholder is spelled one way"
# Needle assembled, like the non-existent tool name above: this file lives
# under plugins/flow, so spelling the forbidden form would fail the assertion
# on the test that makes it.
OLD_SPELLING="Step: <n>""/<m> <action>"
HITS=$(grep -rl "$OLD_SPELLING" "$PLUGIN_DIR" 2>/dev/null | wc -l | tr -d ' ')
assert_equal "0" "$HITS" "no file uses the angle-bracket spelling"
assert_contains "Step: {n}/{m} {action}" "$SKILL_FLAT" "the brace spelling is the one in use"

# =============================================================================
# Review cycle 3 — the reason set and the producer must not contradict
# =============================================================================

_flow_test_begin "every shape the producer is told to emit is one the judge accepts"
# The defect: one fix restricted the marker's reason to exactly three strings,
# another told the producer to emit a `Flows:` line naming undriven viewports —
# which is none of the three. The shape one rule demanded was the shape the
# other rejected, so the producer had to emit a non-conforming line or state a
# reason that was false (`Flows: none` while a desktop flow had run).
#
# The rule now: a `Flows:` line means NO flow ran, and carries one of three
# reasons. Nothing may instruct the producer to write it for a partial run.
SKILL_TXT=$(cat "$SKILL")
JUDGE_TXT=$(cat "$JUDGE")
BUNDLE_TXT=$(cat "$BUNDLE_FMT")
for F in "$SKILL" "$JUDGE" "$BUNDLE_FMT" "$VIS_OUT"; do
  assert_not_contains "viewports left undriven" "$(cat "$F")" \
    "$(basename "$F") does not ask for a reason outside the permitted set"
  assert_not_contains "left undriven in a" "$(cat "$F")" \
    "$(basename "$F") does not spell one either"
done

_flow_test_begin "a Flows line and step blocks are exclusive"
# The both-case had no defined Coverage Scan value and no legal spelling: a
# criterion with a desktop flow cannot truthfully say `Flows: none`.
BUNDLE_FLAT=$(printf '%s\n' "$BUNDLE_TXT" | tr '\n' ' ' | tr -s ' ')
assert_contains "The two are exclusive on one criterion" "$BUNDLE_FLAT" \
  "the bundle format states the contract"
assert_match "stopped at the step bound carries the blocks it completed, not a" "$BUNDLE_FLAT" \
  "and says a partial run carries its blocks rather than the marker"
assert_not_contains "Both may appear on one criterion" "$BUNDLE_FLAT" \
  "the combination is no longer permitted"

_flow_test_begin "a viewport-specific criterion is still judged on where it ran"
# The rule survives the cut; only the unspellable escape hatch is gone. The
# judge reads the Viewport: line of the step blocks that exist, rather than
# demanding a marker for the ones that do not.
JUDGE_FLAT=$(printf '%s\n' "$JUDGE_TXT" | tr '\n' ' ' | tr -s ' ')
assert_match "driven only on desktop has not been verified where it claims to apply" "$JUDGE_FLAT" \
  "the intent is kept"
assert_match "judge that on the .Viewport:. line" "$JUDGE_FLAT" \
  "and is judged from evidence the bundle actually carries"

_flow_test_begin "the decision recorded in the journal is the one implemented"
# Requiring a flow on every viewport was considered and rejected up front; a
# review fix reintroduced a narrower version of it without going back to that
# decision. The journal is the record, so it has to agree with the code.
# Flattened: the sentence wraps, and a literal match on wrapped prose fails
# silently — the same shape that let a garbled sentence pass on #217.
JOURNAL=$(printf '%s\n' "$(cat "$REPO_ROOT/.decisions/issue-218.md")" | tr '\n' ' ' | tr -s ' ')
assert_contains "Rejected: requiring flows on every viewport" "$JOURNAL" \
  "the journal records the rejection"
assert_contains "reintroduced a narrower version" "$JOURNAL" \
  "and records that a review fix reintroduced it, and was cut"
assert_not_contains "there must be a \`Step:\` block for each" "$JUDGE_TXT" \
  "and the judge does not require one per viewport"
