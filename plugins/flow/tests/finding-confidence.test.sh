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
