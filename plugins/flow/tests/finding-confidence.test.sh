# Tests for issue #212: finding confidence decides what a finding may demand.
#
# Contract (.decisions/issue-212.md § Specification and § Plan decisions):
#   - skills/code-review-methodology/SKILL.md carries one rule for how
#     confidence enters the review decision, and its decision table agrees
#     with that rule (HIGH and MEDIUM decide; LOW goes to Needs investigation).
#   - The contradiction checker below is itself tested: it must fire on the
#     methodology as it shipped before #212, stay silent on a consistent one,
#     and fail when its input is missing.

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
FC_FIXTURES="$PLUGIN_DIR/tests/fixtures/finding-confidence"
METHODOLOGY="$PLUGIN_DIR/skills/code-review-methodology/SKILL.md"

# _fc_section <file> <heading-line> — the lines under a `## ` heading, up to
# the next `## ` heading.
_fc_section() {
  awk -v h="$2" '$0 == h { f = 1; next } /^## / { f = 0 } f' "$1"
}

# _fc_check_decision_rule <file> — parses the "Confidence and signal" section
# and the "Review decision" table. Prints SECTIONS=<n> and TABLE_ROWS=<n>.
# Exit 2: a section is missing or the table has no rows (nothing examined).
# Exit 1: the rule and the table contradict each other:
#   - the section says "Only High-confidence P1s block merge" while a row
#     reads `Any P1 | REQUEST_CHANGES` (the pre-#212 contradiction), or
#   - the section routes LOW to "Needs investigation" while a row still reads
#     an unconditional `Any P1` or `Any P2` → REQUEST_CHANGES.
# Exit 0: consistent. Rows are parsed into cells, so prose that quotes a row
# does not count as a row.
_fc_check_decision_rule() {
  local file="$1" sections=0 conf rows row_count
  grep -qx '## Confidence and signal' "$file" && sections=$((sections + 1))
  grep -qx '## Review decision' "$file" && sections=$((sections + 1))
  conf=$(_fc_section "$file" '## Confidence and signal')
  rows=$(_fc_section "$file" '## Review decision' | awk -F'|' '
    /^\|/ {
      n++
      if (n == 1) next
      c1 = $2; c2 = $3
      gsub(/^[ \t]+|[ \t]+$/, "", c1); gsub(/^[ \t]+|[ \t]+$/, "", c2)
      if (c1 ~ /^-+$/) next
      print c1 "\t" c2
    }')
  if [ -n "$rows" ]; then
    row_count=$(grep -c . <<<"$rows")
  else
    row_count=0
  fi
  echo "SECTIONS=$sections"
  echo "TABLE_ROWS=$row_count"
  [ "$sections" -eq 2 ] && [ "$row_count" -gt 0 ] || return 2
  local c1 c2 unconditional_p1=0 unconditional_p2=0
  while IFS=$'\t' read -r c1 c2; do
    [ "$c2" = "REQUEST_CHANGES" ] || continue
    [ "$c1" = "Any P1" ] && unconditional_p1=1
    [ "$c1" = "Any P2" ] && unconditional_p2=1
  done <<<"$rows"
  case "$conf" in
    *"Only High-confidence P1s block merge"*)
      [ "$unconditional_p1" -eq 1 ] && return 1 ;;
  esac
  case "$conf" in
    *"Needs investigation"*)
      [ $((unconditional_p1 + unconditional_p2)) -gt 0 ] && return 1 ;;
  esac
  return 0
}

# _fc_run_check <file> — runs the checker; sets CHECK_OUT and CHECK_CODE.
_fc_run_check() {
  CHECK_OUT=$(_fc_check_decision_rule "$1")
  CHECK_CODE=$?
}

# --- AC1: the checker can fire, stay silent, and notice missing input --------

_flow_test_begin "AC1 checker: fires on the methodology as shipped before #212"
_fc_run_check "$FC_FIXTURES/methodology-before.md"
assert_exit 1 "$CHECK_CODE" "phrase + unconditional Any P1 row → contradiction"
assert_contains "TABLE_ROWS=4" "$CHECK_OUT" "examined the four table rows"

_flow_test_begin "AC1 checker: stays silent on a consistent rule and conditional rows"
_fc_run_check "$FC_FIXTURES/methodology-conditional.md"
assert_exit 0 "$CHECK_CODE" "consistent"
assert_contains "SECTIONS=2" "$CHECK_OUT" "both sections found"
assert_contains "TABLE_ROWS=4" "$CHECK_OUT" "four rows examined"

_flow_test_begin "AC1 checker: fails when the table or the section is missing"
_fc_run_check "$FC_FIXTURES/methodology-no-table.md"
assert_exit 2 "$CHECK_CODE" "no table rows → nothing examined"
assert_contains "TABLE_ROWS=0" "$CHECK_OUT" "reports zero rows"
_fc_run_check "$FC_FIXTURES/methodology-no-section.md"
assert_exit 2 "$CHECK_CODE" "no Confidence and signal section"
assert_contains "SECTIONS=1" "$CHECK_OUT" "reports one section"

_flow_test_begin "AC1 checker: fires on the new rule beside an unconditional Any P2 row"
_fc_run_check "$FC_FIXTURES/methodology-new-rule-any-p2.md"
assert_exit 1 "$CHECK_CODE" "LOW routed to investigation but Any P2 still blocks"

_flow_test_begin "AC1 checker: prose that quotes a row is not a row"
_fc_run_check "$FC_FIXTURES/methodology-prose-mentions-any-p1.md"
assert_exit 0 "$CHECK_CODE" "quoted 'Any P1 | REQUEST_CHANGES' in prose does not fire"

# --- AC1: the real methodology -----------------------------------------------

_flow_test_begin "AC1: code-review-methodology carries one confidence rule"
_fc_run_check "$METHODOLOGY"
assert_exit 0 "$CHECK_CODE" "rule and decision table agree"
assert_contains "SECTIONS=2" "$CHECK_OUT" "both sections present"
assert_contains "TABLE_ROWS=4" "$CHECK_OUT" "four decision rows"
CONF_SECTION=$(_fc_section "$METHODOLOGY" '## Confidence and signal')
assert_not_contains "Only High-confidence P1s block merge" "$CONF_SECTION" "the retired phrase is gone (a MEDIUM P1 blocks too)"
assert_not_contains "include only as P1" "$CONF_SECTION" "LOW is no longer limited to P1"
assert_contains "Needs investigation" "$CONF_SECTION" "LOW findings go to Needs investigation"
assert_contains "MEDIUM" "$CONF_SECTION" "absent confidence counts as MEDIUM"
assert_contains "commands/review.md\` Phase 4 step 5" "$CONF_SECTION" "points own-PR handling to the self-review step (asserted under AC3)"
assert_contains "flow-finding-route.sh" "$CONF_SECTION" "names the script that applies the rule"

# --- AC4: confidence is required of the four schema agents -------------------

SCHEMA="$PLUGIN_DIR/references/finding-schema.md"
SCHEMA_CONTENT=$(cat "$SCHEMA")

_flow_test_begin "AC4: finding-schema.md lists confidence as a required agent field"
REQUIRED_TABLE=$(_fc_section "$SCHEMA" '## Required fields')
REQUIRED_CONF_ROW=$(awk -F'|' '/^\|/ { c = $2; gsub(/^[ \t`]+|[ \t`]+$/, "", c); if (c == "confidence") print }' <<<"$REQUIRED_TABLE")
assert_match 'HIGH.*MEDIUM.*LOW' "$REQUIRED_CONF_ROW" "confidence row in the Required fields table"
assert_not_contains "## Optional field (added by orchestrator" "$SCHEMA_CONTENT" "no longer an optional orchestrator field"
assert_not_contains "Agents SHOULD assign" "$SCHEMA_CONTENT" "no SHOULD wording"

_flow_test_begin "AC4: the absent-value rule is MEDIUM plus LEDGER_WARN, never LOW"
assert_contains "LEDGER_WARN: PR#<N> finding '<id>' from <agent> has no confidence — treated as MEDIUM" "$SCHEMA_CONTENT" "absent-confidence warning, same text the script prints"
assert_contains "LEDGER_WARN: PR#<N> finding '<id>' from <agent> has invalid confidence '<value>' — treated as MEDIUM" "$SCHEMA_CONTENT" "invalid-confidence warning, same text the script prints"
assert_not_contains "treated as LOW" "$SCHEMA_CONTENT" "absence never demotes to LOW"

_flow_test_begin "AC4: the three-tier rule maps pattern match to LOW at any priority"
GUIDANCE=$(_fc_section "$SCHEMA" '## Confidence guidance')
PATTERN_ROW=$(grep -i '^| Pattern-match' <<<"$GUIDANCE")
assert_match '\| LOW' "$PATTERN_ROW" "pattern match → LOW"
assert_not_contains "only flag at P1" "$PATTERN_ROW" "LOW is not limited to P1"
assert_match '^\| Verified by running.*\| HIGH' "$GUIDANCE" "running code or a test → HIGH"
assert_match '^\| LSP diagnostic.*\| HIGH' "$GUIDANCE" "LSP diagnostic → HIGH"
assert_match '^\| Verified by reading the full code path \| MEDIUM' "$GUIDANCE" "reading the code path → MEDIUM"
assert_not_contains "only P1 findings with HIGH confidence should block merge" "$SCHEMA_CONTENT" "retired blocking sentence removed"

_flow_test_begin "AC4: the confidence suffix is rendered on both review paths"
assert_not_contains "only in paired-reviewer / Path A mode" "$SCHEMA_CONTENT" "suffix no longer Path-A-only"
assert_not_contains "Path B emits 5-field" "$SCHEMA_CONTENT" "Path B emits the 7-field marker"

# _fc_rows_missing_suffix <file> — for every example finding row, which opens
# with a bold finding id followed by ` · ` (`| **F1 · category · ...`), checks
# that the Finding cell ends with _(HIGH)_, _(MEDIUM)_ or _(LOW)_. Other
# bold-first table rows (`| **Introduced** |`, `| **P1** |`) are not findings.
# Escaped pipes (`\|`) inside a cell are not cell boundaries.
# Prints EXAMINED=<rows> MISSING=<rows>.
_fc_rows_missing_suffix() {
  awk '
    /^\| \*\*[A-Za-z][A-Za-z0-9_-]* · / {
      line = $0
      gsub(/\\\|/, "", line)
      split(line, cells, "|")
      cell = cells[2]
      gsub(/[ \t]+$/, "", cell)
      examined++
      if (cell !~ /_\((HIGH|MEDIUM|LOW)\)_$/) missing++
    }
    END { printf "EXAMINED=%d MISSING=%d\n", examined, missing }
  ' "$1"
}

_flow_test_begin "AC4 row checker: fires on a missing suffix, silent when every row has one"
assert_equal "EXAMINED=2 MISSING=1" "$(_fc_rows_missing_suffix "$FC_FIXTURES/agent-example-missing-suffix.md")" "one row without a suffix is caught"
assert_equal "EXAMINED=3 MISSING=0" "$(_fc_rows_missing_suffix "$FC_FIXTURES/agent-example-all-suffixed.md")" "three suffixed rows, one with an escaped pipe, pass"
assert_equal "EXAMINED=0 MISSING=0" "$(_fc_rows_missing_suffix "$FC_FIXTURES/methodology-conditional.md")" "a file with no finding rows reports zero examined"

_flow_test_begin "AC4: each of the four schema agents requires confidence per finding"
AGENT_SENTENCE='Every finding MUST carry a confidence suffix `_(HIGH|MEDIUM|LOW)_` under the three-tier rule in `references/finding-schema.md`: running code or a test, or an LSP diagnostic → HIGH; reading the code path → MEDIUM; pattern match only → LOW.'
AGENTS_EXAMINED=0
for AGENT in code-reviewer security-reviewer error-handler-inspector integration-verifier; do
  AGENT_FILE="$PLUGIN_DIR/agents/$AGENT.md"
  if [ ! -f "$AGENT_FILE" ]; then
    _flow_assert_fail "$AGENT: agent file missing"
    continue
  fi
  AGENTS_EXAMINED=$((AGENTS_EXAMINED + 1))
  assert_contains "$AGENT_SENTENCE" "$(cat "$AGENT_FILE")" "$AGENT states the requirement"
  ROW_REPORT=$(_fc_rows_missing_suffix "$AGENT_FILE")
  assert_match '^EXAMINED=[1-9][0-9]* MISSING=0$' "$ROW_REPORT" "$AGENT example rows all carry a suffix ($ROW_REPORT)"
done
assert_equal "4" "$AGENTS_EXAMINED" "four agent files examined"
assert_not_contains "MEDIUM at best" "$(cat "$PLUGIN_DIR/agents/error-handler-inspector.md")" "error-handler-inspector no longer caps pattern matches at MEDIUM"

_flow_test_begin "7-field marker on both paths in the parser reference and the row schema"
PARSER_CONTENT=$(cat "$PLUGIN_DIR/references/finding-ledger-parser.md")
assert_not_contains "paired-reviewer mode only" "$PARSER_CONTENT" "confidence and disposition are not Path-A-only"
assert_not_contains "The 7-field form is emitted only when" "$PARSER_CONTENT" "7-field not limited to Path A"
assert_not_contains "and the inline review in \`/flow:pr\`" "$PARSER_CONTENT" "no claim that /flow:pr posts a resolution marker"
assert_contains "Two emitters" "$PARSER_CONTENT" "resolution-marker emitter anchor kept"
assert_contains "issue-comments stream" "$PARSER_CONTENT" "resolution-marker placement anchor kept"
assert_not_contains "omitted (Path B 5-field marker)" "$(cat "$REPO_ROOT/tests/finding-schema/row-schema.json")" "row schema describes disposition on both paths"
assert_not_contains "6-field finding data model" "$(cat "$PLUGIN_DIR/README.md")" "README counts the seven agent fields"
