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
assert_contains "Absent or invalid confidence is MEDIUM" "$CONF_SECTION" "absent confidence counts as MEDIUM (the sentence itself, not any MEDIUM)"
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

# --- AC2 / AC7: review.md routes and posts through flow-finding-route.sh -----

REVIEW_MD="$PLUGIN_DIR/commands/review.md"

# _fc_phase4_step <n> — the text of Phase 4 step <n>, from its `<n>. **`
# line to the next step's line (or the next `## ` heading). Headings inside
# fenced code blocks are example text, not document structure.
_fc_phase4_step() {
  awk -v n="$1" '
    /^[[:space:]]*```/ { fence = !fence }
    /^## Phase 4: VERIFY/ { p4 = 1; next }
    p4 && !fence && /^## / { exit }
    p4 && $0 ~ ("^" n "\\. \\*\\*") { f = 1; print; next }
    p4 && f && $0 ~ ("^" (n + 1) "\\. \\*\\*") { exit }
    f { print }
  ' "${2:-$REVIEW_MD}"
}

# _fc_block <NAME> [file] — the lines between `# <NAME>_BEGIN` and
# `# <NAME>_END`; the markers may be indented, as they are inside list items.
_fc_block() {
  awk -v b="# $1_BEGIN" -v e="# $1_END" '
    { t = $0; sub(/^[ \t]+/, "", t) }
    t == b { f = 1; next }
    t == e { f = 0 }
    f' "${2:-$REVIEW_MD}"
}

STEP6=$(_fc_phase4_step 6)
STEP7=$(_fc_phase4_step 7)

_flow_test_begin "step extraction reaches its input (and fails when a step heading is removed)"
assert_match '[^[:space:]]' "$STEP6" "step 6 extracted"
assert_match '[^[:space:]]' "$STEP7" "step 7 extracted"
FC_TMP=$(mktemp -d -t finding-confidence.XXXXXX)
trap 'rm -rf "$FC_TMP"' EXIT
grep -v '^6\. \*\*' "$REVIEW_MD" > "$FC_TMP/review-no-step6.md"
assert_equal "" "$(_fc_phase4_step 6 "$FC_TMP/review-no-step6.md")" "no step 6 heading → nothing extracted"

_flow_test_begin "AC2: step 6 routes LOW findings on an external PR to Needs investigation"
assert_contains 'On an external review, LOW-confidence findings at any priority go to a `#### Needs investigation` section and are excluded from the review decision and from the `FLOW_REVIEW_CYCLE` marker; their priority is shown there and never changed.' "$STEP6" "the routing rule is stated"
assert_contains "flow-finding-route.sh" "$STEP6" "names the script"
assert_contains "--mode external" "$STEP6" "names the external mode"

_flow_test_begin "AC2: step 7 states the marker exclusion and posts through the script"
assert_contains 'No LOW-confidence row is written to the `FLOW_REVIEW_CYCLE` marker.' "$STEP7" "exclusion stated in the marker step"
assert_contains "# FINDING_ROUTE_BLOCK_BEGIN" "$STEP7" "routing block lives in step 7"
assert_contains "# FINDING_POST_BLOCK_BEGIN" "$STEP7" "posting block lives in step 7"
assert_not_contains 'legacy **5-field** marker' "$STEP7" "Path B no longer emits 5-field"
assert_not_contains "5-field form is preserved ONLY" "$(cat "$REVIEW_MD")" "A.6 no longer reserves 5-field for Path B"
assert_contains "names the orchestration that ran" "$STEP7" "review-cycle path metadata is the orchestration"
assert_not_contains '(7-field marker), `B` when Path B (5-field marker)' "$STEP7" "path is no longer inferred from marker width"

_flow_test_begin "AC4: Path B prompts ask the schema agents for confidence"
PATH_B=$(awk '/^### Path B: Single Session/ { f = 1 } /^## Phase 4/ { f = 0 } f' "$REVIEW_MD")
assert_equal "3" "$(grep -c 'confidence (HIGH, MEDIUM or LOW) per finding' <<<"$PATH_B")" "code-reviewer, error-handler-inspector and security-reviewer prompts"
assert_contains "Needs investigation: {N}" "$(_fc_phase4_step 3)" "step 3 display header carries the separate LOW count"

# --- executable blocks ---------------------------------------------------------

FC_STUB="$FC_TMP/bin"
mkdir -p "$FC_STUB"
cat > "$FC_STUB/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo "o/r"; exit 0 ;;
  "api user") printf '%s\n' "${STUB_USER:-}"; exit 0 ;;
  "issue list") exit 0 ;;
  "pr view")
    case "$*" in
      *closingIssuesReferences*)
        # Apply --jq the way gh does, to the closing references in STUB_CLOSING.
        while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && FILTER="$2"; shift; done
        CLOSING=${STUB_CLOSING:-}
        [ -n "$CLOSING" ] || CLOSING='{"closingIssuesReferences":[]}'
        printf '%s' "$CLOSING" | jq -r "$FILTER"
        exit ;;
      *author*) printf '%s\n' "${STUB_AUTHOR:-}"; exit 0 ;;
      *body*) printf '%s\n' "${STUB_BODY:-}"; exit 0 ;;
      *number*) echo "55"; exit 0 ;;
    esac
    exit 1 ;;
  "pr review")
    printf '%s\n' "$@" > "$GH_LOG"
    while [ $# -gt 0 ]; do
      if [ "$1" = "--body-file" ]; then cp "$2" "$GH_BODY"; fi
      shift
    done
    exit 0 ;;
esac
exit 1
STUB
chmod +x "$FC_STUB/gh"

# _fc_closing <number>... — closingIssuesReferences JSON naming issues of o/r,
# the repository the stub's `gh repo view` reports.
_fc_closing() {
  local refs="" n
  for n in "$@"; do
    refs="${refs:+$refs,}{\"number\":$n,\"repository\":{\"name\":\"r\",\"owner\":{\"login\":\"o\"}}}"
  done
  printf '{"closingIssuesReferences":[%s]}' "$refs"
}

_fc_block "FINDING_ROUTE_BLOCK" > "$FC_TMP/route-block.sh"
_fc_block "FINDING_POST_BLOCK" > "$FC_TMP/post-block.sh"

# _fc_route <mode> <rows> — runs the routing block with its heredoc
# placeholder replaced by <rows>. Sets ROUTE_OUT, ROUTE_ERR, ROUTE_CODE.
_fc_route() {
  printf '%s\n' "$2" > "$FC_TMP/rows.in"
  awk -v rows="$FC_TMP/rows.in" '
    /^\{one row per consolidated finding/ { while ((getline l < rows) > 0) print l; next }
    { print }
  ' "$FC_TMP/route-block.sh" > "$FC_TMP/route-run.sh"
  ROUTE_OUT=$(cd "$FC_TMP" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    REVIEW_MODE="$1" PR_NUM=7 "${FC_SHELL:-bash}" "$FC_TMP/route-run.sh" 2>"$FC_TMP/route.err")
  ROUTE_CODE=$?
  ROUTE_ERR=$(cat "$FC_TMP/route.err")
}

# _fc_post <mode> <rows> <finding-total> <body> — runs the posting block.
# Sets POST_OUT, POST_ERR, POST_CODE, GH_ARGS (empty when gh was not called)
# and POSTED (the body gh received).
_fc_post() {
  printf '%s\n' "$2" > "$FC_TMP/rows"
  printf '%s\n' "$4" > "$FC_TMP/body.md"
  rm -f "$FC_TMP/gh.log" "$FC_TMP/gh.body"
  POST_OUT=$(cd "$FC_TMP" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    GH_LOG="$FC_TMP/gh.log" GH_BODY="$FC_TMP/gh.body" \
    REVIEW_MODE="$1" PR_NUM=7 CYCLE_NUMBER="${FC_CYCLE:-2}" FINDING_ROWS_FILE="$FC_TMP/rows" \
    FINDING_TOTAL="$3" BODY_FILE="$FC_TMP/body.md" "${FC_SHELL:-bash}" "$FC_TMP/post-block.sh" 2>"$FC_TMP/post.err")
  POST_CODE=$?
  POST_ERR=$(cat "$FC_TMP/post.err")
  GH_ARGS=$(cat "$FC_TMP/gh.log" 2>/dev/null)
  POSTED=$(cat "$FC_TMP/gh.body" 2>/dev/null)
}

FC_MIXED='F1|P2|correctness|src/b.sh:4|HIGH|consensus|code-reviewer
F2|P1|correctness|src/c.sh:9|LOW|kept|code-reviewer'
# A one-finding external body: the P3 bullet renders the counted finding.
FC_P3_BODY='### Findings: P1: 0, P2: 0, P3: 1 · Needs investigation: 0

#### P3 — Suggestions
- **F1 · docs · `a.md:1`** — Stale link. _(MEDIUM · unchallenged)_'

FC_MIXED_BODY='## Review: PR #7

### Findings: P1: 0, P2: 1, P3: 0 · Needs investigation: 1

#### P2 — Important
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · correctness · `src/b.sh:4`**<br>Wrong bound. _(HIGH · consensus)_ | Use `<`. |

#### Needs investigation
- **F2 · P1 · correctness · `src/c.sh:9`** — Looks like a race.
  Pattern: shared counter without a lock. Confirm or refute: a concurrent test.'

_flow_test_begin "routing block: writes the rows and prints the routed values"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/route-block.sh")" "routing block extracted"
_fc_route external "$FC_MIXED"
assert_exit 0 "$ROUTE_CODE" "routed"
assert_match '^FINDING_ROWS_FILE=.+' "$ROUTE_OUT" "prints the rows file path"
assert_contains "NEEDS_INVESTIGATION=F2" "$ROUTE_OUT" "prints the investigation ids"
assert_contains "DECISION=REQUEST_CHANGES" "$ROUTE_OUT" "prints the decision"
assert_contains "FINDINGS_HEADER=P1: 0, P2: 1, P3: 0 · Needs investigation: 1" "$ROUTE_OUT" "prints the header the body must carry"
_fc_route external '{one row per consolidated finding: ID|PRIORITY|category|location|CONFIDENCE|disposition|agent}'
assert_exit 1 "$ROUTE_CODE" "a placeholder left unreplaced is rejected, not routed as a clean review"
_fc_route self 'F1|P2|edge-case|src/e.sh:5|LOW|unchallenged|code-reviewer'
assert_exit 1 "$ROUTE_CODE" "self mode with a LOW row stops"
assert_contains "return to step 5" "$ROUTE_ERR" "sends the reviewer back to step 5"

_flow_test_begin "risk: marker vs decision — the posted marker carries no LOW row"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/post-block.sh")" "posting block extracted"
_fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY"
assert_exit 0 "$POST_CODE" "posted"
assert_contains "<!-- FLOW_REVIEW_CYCLE:2 FINDINGS:[F1|P2|correctness|src/b.sh:4|open|HIGH|consensus] -->" "$POSTED" "marker holds F1 only"
assert_not_contains "F2|" "$POSTED" "no F2 marker row"
assert_contains "--request-changes" "$GH_ARGS" "decision from the HIGH P2"
assert_contains "--repo" "$GH_ARGS" "repository pinned"
assert_contains "POSTED_AS=--request-changes POST_EXIT=0" "$POST_OUT" "block reports what it posted"

_flow_test_begin "risk: header counts — a body that counts the LOW finding is refused"
WRONG_BODY=${FC_MIXED_BODY/P1: 0, P2: 1, P3: 0 · Needs investigation: 1/P1: 1, P2: 1, P3: 0 · Needs investigation: 0}
_fc_post external "$FC_MIXED" 2 "$WRONG_BODY"
assert_exit 1 "$POST_CODE" "refused"
assert_contains "P1: 0, P2: 1, P3: 0 · Needs investigation: 1" "$POST_ERR" "names the header the counts require"
assert_equal "" "$GH_ARGS" "gh was not called"

_flow_test_begin "a LOW finding missing from the Needs investigation section is refused"
NO_ENTRY_BODY=$(grep -v '^- \*\*F2 · ' <<<"$FC_MIXED_BODY")
_fc_post external "$FC_MIXED" 2 "$NO_ENTRY_BODY"
assert_exit 1 "$POST_CODE" "refused"
assert_contains "F2" "$POST_ERR" "names the missing id"
assert_equal "" "$GH_ARGS" "gh was not called"

_flow_test_begin "risk: only-LOW decision — an external review whose only finding is LOW approves"
_fc_post external 'F1|P1|security|src/d.sh:2|LOW|kept|security-reviewer' 1 '## Review: PR #7

### Findings: P1: 0, P2: 0, P3: 0 · Needs investigation: 1

#### Needs investigation
- **F1 · P1 · security · `src/d.sh:2`** — Possible injection.
  Pattern: string concatenation into a query. Confirm or refute: a payload test.'
assert_exit 0 "$POST_CODE" "posted"
assert_contains "--approve" "$GH_ARGS" "approves"
assert_not_contains "--request-changes" "$GH_ARGS" "does not request changes"
assert_contains "FINDINGS:[] -->" "$POSTED" "empty marker"

_flow_test_begin "posting block refuses unsafe or inconsistent input, and posts a plain comment"
_fc_post self 'F1|P2|edge-case|src/e.sh:5|LOW|unchallenged|code-reviewer' 1 '## Self-Review Summary'
assert_exit 1 "$POST_CODE" "own PR with a LOW row refused"
assert_contains "return to step 5" "$POST_ERR" "sends the reviewer back to step 5"
assert_equal "" "$GH_ARGS" "gh not called for an unresolved LOW row"
_fc_post external 'F1|P3|docs|a.md:1|MEDIUM|unchallenged|code-reviewer' 2 "$FC_P3_BODY"
assert_exit 1 "$POST_CODE" "synthesized 2 findings but the rows file holds 1"
assert_equal "" "$GH_ARGS" "gh not called on a count mismatch"
_fc_post external 'F1|P3|docs|a.md:1|MEDIUM|unchallenged|code-reviewer' 1 "$FC_P3_BODY
<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[] -->"
assert_exit 1 "$POST_CODE" "a body that already carries a marker is refused"
assert_equal "" "$GH_ARGS" "gh not called when the body has a marker"
_fc_post external 'F1|P3|docs|a.md:1|MEDIUM|unchallenged|code-reviewer' 1 "$FC_P3_BODY"
assert_exit 0 "$POST_CODE" "a MEDIUM P3 posts: $POST_ERR"
assert_contains "--comment" "$GH_ARGS" "as a comment"
_fc_post self 'F1|P2|edge-case|src/e.sh:5|HIGH|unchallenged|code-reviewer' 1 '## Self-Review Summary'
assert_exit 0 "$POST_CODE" "own PR with the finding re-recorded HIGH posts"
assert_contains "--comment" "$GH_ARGS" "self-review is a comment"
assert_contains "F1|P2|edge-case|src/e.sh:5|open|HIGH|unchallenged" "$POSTED" "7-field row"
(cd "$FC_TMP" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" GH_LOG="$FC_TMP/gh.log" GH_BODY="$FC_TMP/gh.body" \
  REVIEW_MODE=external PR_NUM=7 FINDING_ROWS_FILE="$FC_TMP/rows" FINDING_TOTAL=1 BODY_FILE="$FC_TMP/body.md" \
  bash "$FC_TMP/post-block.sh" >/dev/null 2>"$FC_TMP/post.err"); MISSING_CODE=$?
assert_exit 1 "$MISSING_CODE" "unset CYCLE_NUMBER refused"
assert_contains "CYCLE_NUMBER" "$(cat "$FC_TMP/post.err")" "names the missing value"

# The model runs these fences in the user's shell, which is often zsh.
_flow_test_begin "routing and posting blocks behave the same under zsh"
if command -v zsh >/dev/null 2>&1; then
  FC_SHELL=zsh
  _fc_route external "$FC_MIXED"
  assert_exit 0 "$ROUTE_CODE" "zsh: routed"
  assert_contains "FINDINGS_HEADER=P1: 0, P2: 1, P3: 0 · Needs investigation: 1" "$ROUTE_OUT" "zsh: header"
  _fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY"
  assert_exit 0 "$POST_CODE" "zsh: posted"
  assert_contains "<!-- FLOW_REVIEW_CYCLE:2 FINDINGS:[F1|P2|correctness|src/b.sh:4|open|HIGH|consensus] -->" "$POSTED" "zsh: marker holds F1 only"
  assert_contains "--request-changes" "$GH_ARGS" "zsh: decision"
  _fc_post external "$FC_MIXED" 2 "$NO_ENTRY_BODY"
  assert_exit 1 "$POST_CODE" "zsh: missing Needs investigation entry refused"
  unset FC_SHELL
else
  _flow_assert_pass "SKIP: zsh not installed"
fi

# --- AC3: own-PR LOW findings end fixed, refuted or escalated -----------------

_flow_test_begin "missing context: step 4 refuses to choose a review mode from empty identities"
_fc_block "REVIEW_MODE_BLOCK" > "$FC_TMP/mode-block.sh"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/mode-block.sh")" "review-mode block extracted"
_fc_mode() {
  MODE_OUT=$(cd "$FC_TMP" && PATH="$FC_STUB:$PATH" STUB_AUTHOR="$1" STUB_USER="$2" PR_NUM=7 \
    bash "$FC_TMP/mode-block.sh" 2>"$FC_TMP/mode.err")
  MODE_CODE=$?
  MODE_ERR=$(cat "$FC_TMP/mode.err")
}
_fc_mode "" ""
assert_exit 1 "$MODE_CODE" "author and user both empty → refused"
assert_not_contains "REVIEW_MODE=self" "$MODE_OUT" "two empty strings are not treated as the same person"
assert_contains "ERROR" "$MODE_ERR" "says why"
_fc_mode "alice" ""
assert_exit 1 "$MODE_CODE" "empty current user → refused"
_fc_mode "" "alice"
assert_exit 1 "$MODE_CODE" "empty PR author → refused"
_fc_mode "alice" "alice"
assert_exit 0 "$MODE_CODE" "same person"
assert_contains "REVIEW_MODE=self" "$MODE_OUT" "own PR → self"
_fc_mode "alice" "bob"
assert_exit 0 "$MODE_CODE" "different people"
assert_contains "REVIEW_MODE=external" "$MODE_OUT" "someone else's PR → external"

STEP5=$(_fc_phase4_step 5)
_flow_test_begin "AC3: step 5 ends every LOW finding fixed (HIGH), refuted or escalated"
assert_match '[^[:space:]]' "$STEP5" "step 5 extracted"
assert_contains "fails on the current code" "$STEP5" "confirmation is a failing test or command"
assert_contains "re-record the finding HIGH" "$STEP5" "a confirmed finding is fixed and recorded HIGH"
assert_contains "reason=self-review-refuted" "$STEP5" "a refuted finding is recorded as dropped-finding"
assert_contains "--type dropped-finding" "$STEP5" "the record is a dropped-finding artifact"
assert_contains "re-record it MEDIUM" "$STEP5" "an unsettled finding is escalated at MEDIUM"
assert_contains "ESCALATED" "$STEP5" "the escalated id goes to the resolution marker"
assert_contains "--mode self" "$STEP5" "the routing in step 7 blocks unresolved LOW rows"
assert_not_contains "#### Needs investigation" "$STEP5" "own-PR LOW findings are not posted as open investigations"

_flow_test_begin "risk: exclusion scope — a refuted own-PR finding is journaled as dropped-finding"
_fc_block "DROPPED_FINDING_BLOCK" > "$FC_TMP/dropped-block.sh"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/dropped-block.sh")" "dropped-finding block extracted"
mkdir -p "$FC_TMP/journal-repo"
(cd "$FC_TMP/journal-repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ISSUE=42 CYCLE_NUMBER=1 PR_NUM=7 FINDING_ID=F1 FACET=code-reviewer \
  bash "$FC_TMP/dropped-block.sh" >/dev/null 2>"$FC_TMP/dropped.err"); DROP_CODE=$?
assert_exit 0 "$DROP_CODE" "block ran"
_fc_last_artifact() {
  python3 - "$1" <<'PY'
import sys, yaml
c = open(sys.argv[1]).read()
end = c.find("\n---\n", 4)
art = yaml.safe_load(c[4:end])["artifacts"][-1]
print(" ".join("{}={}".format(k, art[k]) for k in ("type", "reason", "finding_id", "facet", "cycle", "pr")))
PY
}
if [ -f "$FC_TMP/journal-repo/.decisions/issue-42.md" ]; then
  assert_equal "type=dropped-finding reason=self-review-refuted finding_id=F1 facet=code-reviewer cycle=1 pr=7" \
    "$(_fc_last_artifact "$FC_TMP/journal-repo/.decisions/issue-42.md")" "artifact read back from the journal manifest"
else
  _flow_assert_fail "no journal written: $(cat "$FC_TMP/dropped.err")"
fi
(cd "$FC_TMP/journal-repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" ISSUE=42 CYCLE_NUMBER=1 PR_NUM=7 FACET=code-reviewer \
  bash "$FC_TMP/dropped-block.sh" >/dev/null 2>&1); DROP_CODE=$?
assert_exit 1 "$DROP_CODE" "missing FINDING_ID refused"

_flow_test_begin "AC3: the journal schema documents self-review-refuted"
JOURNAL_SCHEMA=$(cat "$PLUGIN_DIR/references/decision-journal-schema.md")
DROPPED_ROW=$(grep '^| `dropped-finding`' <<<"$JOURNAL_SCHEMA")
assert_contains "Phase 4 step 5" "$DROPPED_ROW" "row names the self-review producer"
assert_contains "pr.md" "$DROPPED_ROW" "row names the /flow:pr producer"
assert_contains '`self-review-refuted`' "$JOURNAL_SCHEMA" "reason value documented"

_flow_test_begin "/flow:pr applies the same LOW protocol and journals refuted findings"
PR_MD="$PLUGIN_DIR/commands/pr.md"
PR_PHASE3=$(awk '/^## Phase 3/ { f = 1 } /^## Phase 4/ { f = 0 } f' "$PR_MD")
assert_equal "3" "$(grep -c 'confidence (HIGH, MEDIUM or LOW) per finding' <<<"$PR_PHASE3")" "code-reviewer, security-reviewer and error-handler-inspector prompts ask for confidence"
PR_STEP6=$(awk '/^6\. \*\*Display findings\*\*/ { f = 1; print; next } f && /^7\. \*\*/ { exit } f' "$PR_MD")
assert_contains "fails on the current code" "$PR_STEP6" "confirmation rule"
assert_contains "REFUTED" "$PR_STEP6" "refuted findings are carried to the manifest step"
assert_contains "### Needs investigation" "$PR_STEP6" "outcomes are listed in the PR body"
_fc_block "PR_MANIFEST_BLOCK" "$PR_MD" > "$FC_TMP/pr-manifest.sh"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/pr-manifest.sh")" "manifest block extracted"
mkdir -p "$FC_TMP/pr-repo"
(cd "$FC_TMP/pr-repo" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" BRANCH=fix/issue-42-x TOTAL_FINDINGS=3 \
  REFUTED="F3:code-reviewer,ERR-2:error-handler-inspector" bash "$FC_TMP/pr-manifest.sh" >/dev/null 2>"$FC_TMP/pr.err"); PRM_CODE=$?
assert_exit 0 "$PRM_CODE" "manifest block ran"
if [ -f "$FC_TMP/pr-repo/.decisions/issue-42.md" ]; then
  PR_ARTIFACTS=$(python3 - "$FC_TMP/pr-repo/.decisions/issue-42.md" <<'PY'
import sys, yaml
c = open(sys.argv[1]).read()
end = c.find("\n---\n", 4)
for a in yaml.safe_load(c[4:end])["artifacts"]:
    print(" ".join("{}={}".format(k, a.get(k)) for k in ("type", "finding_id", "facet", "reason", "pr")))
PY
)
  assert_contains "type=review-cycle finding_id=None facet=None reason=None pr=55" "$PR_ARTIFACTS" "review-cycle recorded"
  assert_contains "type=dropped-finding finding_id=F3 facet=code-reviewer reason=self-review-refuted pr=55" "$PR_ARTIFACTS" "first refuted finding"
  assert_contains "type=dropped-finding finding_id=ERR-2 facet=error-handler-inspector reason=self-review-refuted pr=55" "$PR_ARTIFACTS" "second refuted finding"
  assert_equal "2" "$(grep -c 'type=dropped-finding' <<<"$PR_ARTIFACTS")" "exactly two drops"
else
  _flow_assert_fail "no journal written: $(cat "$FC_TMP/pr.err")"
fi

# --- AC5: templates keep LOW findings out of the counts ------------------------

TEMPLATES="$PLUGIN_DIR/templates"
REVIEW_TMPL=$(cat "$TEMPLATES/review-comment.md")

_flow_test_begin "risk: header counts — the external template counts LOW findings separately"
assert_contains "### Findings: P1: {p1_count}, P2: {p2_count}, P3: {p3_count} · Needs investigation: {needs_investigation_count}" "$REVIEW_TMPL" "header carries a separate Needs investigation count"
_fc_line() { grep -n -m1 -F "$1" "$2" | cut -d: -f1; }
P3_LINE=$(_fc_line "#### P3" "$TEMPLATES/review-comment.md")
NI_LINE=$(_fc_line "#### Needs investigation" "$TEMPLATES/review-comment.md")
RA_LINE=$(_fc_line "#### Requirements Adherence" "$TEMPLATES/review-comment.md")
if [ -n "$P3_LINE" ] && [ -n "$NI_LINE" ] && [ -n "$RA_LINE" ] && [ "$P3_LINE" -lt "$NI_LINE" ] && [ "$NI_LINE" -lt "$RA_LINE" ]; then
  _flow_assert_pass "Needs investigation sits after P3 and before Requirements Adherence"
else
  _flow_assert_fail "section order P3=$P3_LINE NeedsInvestigation=$NI_LINE Requirements=$RA_LINE"
fi
NI_SECTION=$(awk '/^#### Needs investigation/ { f = 1; next } /^#### / { f = 0 } f' "$TEMPLATES/review-comment.md")
assert_contains "Pattern:" "$NI_SECTION" "entry names the triggering pattern"
assert_contains "Confirm or refute:" "$NI_SECTION" "entry names what would settle it"
assert_contains "**{ID} · {priority} · {category}" "$NI_SECTION" "entry shape matches what the posting block checks"

_flow_test_begin "AC5: self-review and PR-body templates list LOW outcomes apart from the counts"
SELF_TMPL_TEXT=$(cat "$TEMPLATES/self-review-comment.md")
SELF_NI=$(awk '/^### Needs investigation/ { f = 1; next } /^### / { f = 0 } f' "$TEMPLATES/self-review-comment.md")
assert_contains "Confirmed" "$SELF_NI" "confirmed outcome"
assert_contains "Refuted" "$SELF_NI" "refuted outcome"
assert_contains "Unsettled" "$SELF_NI" "escalated outcome"
assert_contains "Every LOW-confidence finding confirmed, refuted or escalated" "$SELF_TMPL_TEXT" "verification checklist item"
PR_BODY_FILE="$TEMPLATES/pr-body.md"
LAST_P3_ROW=$(grep -n '^| P3 |' "$PR_BODY_FILE" | tail -1 | cut -d: -f1)
PR_NI_LINE=$(_fc_line "### Needs investigation" "$PR_BODY_FILE")
if [ -n "$LAST_P3_ROW" ] && [ -n "$PR_NI_LINE" ] && [ "$PR_NI_LINE" -gt "$LAST_P3_ROW" ]; then
  _flow_assert_pass "pr-body Needs investigation follows the count table"
else
  _flow_assert_fail "pr-body order: P3 row=$LAST_P3_ROW NeedsInvestigation=$PR_NI_LINE"
fi
assert_not_contains "| Needs investigation" "$(cat "$PR_BODY_FILE")" "LOW findings are not a row of the count table"

_flow_test_begin "no template carries a marker the posting block would refuse"
TEMPLATES_EXAMINED=0
for T in "$TEMPLATES"/*.md; do
  TEMPLATES_EXAMINED=$((TEMPLATES_EXAMINED + 1))
  assert_not_contains "FLOW_REVIEW_CYCLE:" "$(cat "$T")" "$(basename "$T") has no FLOW_REVIEW_CYCLE marker"
done
assert_match '^[1-9][0-9]*$' "$TEMPLATES_EXAMINED" "templates examined: $TEMPLATES_EXAMINED"

# --- sweep: retired statements and LOW marker rows ------------------------------

# _fc_sweep <dir>... — scans markdown, YAML and shell files for statements
# #212 made false and for FLOW_REVIEW_CYCLE rows whose confidence is LOW.
# Marker rows are parsed into fields, so LOW in a category or path is not a
# hit. Prints FILES=<n> MARKERS=<n> HITS=<n>, then one line per hit.
_fc_sweep() {
  local files
  files=$(find "$@" -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.sh' \) ! -name CHANGELOG.md 2>/dev/null | sort)
  if [ -z "$files" ]; then
    echo "FILES=0 MARKERS=0 HITS=0"
    return
  fi
  printf '%s\n' "$files" | while IFS= read -r f; do printf '%s\0' "$f"; done | xargs -0 awk '
    BEGIN {
      n = split("5-field form is preserved ONLY|paired-reviewer mode only|Path B emits 5-field|only in paired-reviewer / Path A mode|legacy **5-field** marker|Only High-confidence P1s block merge|only P1 findings with HIGH confidence should block merge|Agents SHOULD assign|MEDIUM at best|Single-session reviews omit it", retired, "|")
    }
    FNR == 1 { files++ }
    {
      for (i = 1; i <= n; i++) if (index($0, retired[i])) { hits++; out = out FILENAME ":" FNR ": retired: " retired[i] "\n" }
      line = $0
      while (match(line, /FINDINGS:\[[^]]*\]/)) {
        block = substr(line, RSTART + 10, RLENGTH - 11)
        line = substr(line, RSTART + RLENGTH)
        markers++
        rc = split(block, rows, ",")
        for (r = 1; r <= rc; r++) {
          fc = split(rows[r], f, "|")
          if (fc >= 7 && f[6] == "LOW") { hits++; out = out FILENAME ":" FNR ": LOW marker row: " rows[r] "\n" }
        }
      }
    }
    END { printf "FILES=%d MARKERS=%d HITS=%d\n%s", files, markers, hits, out }
  '
}

_flow_test_begin "sweep: fires on planted wording, stays silent on look-alikes, reports an empty input"
SWEEP=$(_fc_sweep "$FC_FIXTURES/sweep-fire")
assert_match '^FILES=1 MARKERS=1 HITS=2$' "$(head -1 <<<"$SWEEP")" "planted retired phrase and LOW row both caught"
SWEEP=$(_fc_sweep "$FC_FIXTURES/sweep-silent")
assert_equal "FILES=1 MARKERS=1 HITS=0" "$(head -1 <<<"$SWEEP")" "LOW in a category or path is not a LOW row"
mkdir -p "$FC_TMP/empty-sweep"
SWEEP=$(_fc_sweep "$FC_TMP/empty-sweep")
assert_equal "FILES=0 MARKERS=0 HITS=0" "$(head -1 <<<"$SWEEP")" "nothing to scan is reported as zero files"

_flow_test_begin "sweep: the flow plugin carries no retired statement and no LOW marker row"
SWEEP=$(_fc_sweep "$PLUGIN_DIR/commands" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/references" "$PLUGIN_DIR/skills" "$PLUGIN_DIR/templates" "$PLUGIN_DIR/workflows" "$PLUGIN_DIR/README.md")
SWEEP_HEAD=$(head -1 <<<"$SWEEP")
EXPECTED_FILES=$(find "$PLUGIN_DIR/commands" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/references" "$PLUGIN_DIR/skills" "$PLUGIN_DIR/templates" "$PLUGIN_DIR/workflows" "$PLUGIN_DIR/README.md" -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.sh' \) | wc -l | tr -d ' ')
assert_match "^FILES=$EXPECTED_FILES " "$SWEEP_HEAD" "every file found by an independent find was scanned ($SWEEP_HEAD)"
assert_match ' MARKERS=[1-9][0-9]* ' "$SWEEP_HEAD" "marker examples were reached"
assert_match ' HITS=0$' "$SWEEP_HEAD" "no hits: $(tail -n +2 <<<"$SWEEP" | head -5)"

# --- self-review findings on the first draft of #212 ---------------------------

_flow_test_begin "posting: a body quoting marker syntax cannot smuggle a LOW id to the merge parser"
SMUGGLE_BODY="$FC_MIXED_BODY
  The old marker read FINDINGS:[F2|P1|x|y|open] before this change."
_fc_post external "$FC_MIXED" 2 "$SMUGGLE_BODY"
assert_exit 1 "$POST_CODE" "refused"
assert_contains "FINDINGS:[" "$POST_ERR" "names the marker syntax found"
assert_equal "" "$GH_ARGS" "gh not called"
# RESOLVED, ESCALATED and DISPUTED are read only from issue comments
# (merge.md, status.md), never from a review body, so mentioning them posts.
_fc_post self 'F1|P2|edge-case|src/e.sh:5|HIGH|unchallenged|code-reviewer' 1 '## Self-Review Summary

The resolution comment will carry RESOLVED:[F1] ESCALATED:[] DISPUTED:[].'
assert_exit 0 "$POST_CODE" "a self-review body naming the resolution arrays posts"

_flow_test_begin "posting: the findings header must match the routed counts as a whole line"
PADDED_BODY=${FC_MIXED_BODY/Needs investigation: 1/Needs investigation: 12}
_fc_post external "$FC_MIXED" 2 "$PADDED_BODY"
assert_exit 1 "$POST_CODE" "one extra digit is refused"
assert_equal "" "$GH_ARGS" "gh not called"

_flow_test_begin "posting: the cycle number must be a positive integer"
for BAD_CYCLE in '{N} -->' 0 2a; do
  FC_CYCLE="$BAD_CYCLE" _fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY"
  assert_exit 1 "$POST_CODE" "cycle '$BAD_CYCLE' refused"
  assert_equal "" "$GH_ARGS" "gh not called for cycle '$BAD_CYCLE'"
done
FC_CYCLE=11 _fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY"
assert_exit 0 "$POST_CODE" "cycle 11 accepted"
assert_contains "FLOW_REVIEW_CYCLE:11 FINDINGS:[" "$POSTED" "marker carries cycle 11"

_flow_test_begin "posting: a LOW finding rendered in a priority table is refused"
LEAK_ROW='| **F2 · correctness · `src/c.sh:9`**<br>Looks like a race. _(LOW · kept)_ | Add a lock. |'
LEAK_BODY="$FC_MIXED_BODY"
LEAK_BODY=${LEAK_BODY/'#### P2 — Important'/"#### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
$LEAK_ROW

#### P2 — Important"}
_fc_post external "$FC_MIXED" 2 "$LEAK_BODY"
assert_exit 1 "$POST_CODE" "refused"
assert_contains "_(LOW" "$POST_ERR" "names the leaked line"
assert_equal "" "$GH_ARGS" "gh not called"
_fc_post external "$FC_MIXED" 2 "${LEAK_BODY/_(LOW · kept)_/_(low · kept)_}"
assert_exit 1 "$POST_CODE" "a lower-case low suffix is refused too"
# The same row without a LOW suffix: only the id count can catch it.
_fc_post external "$FC_MIXED" 2 "${LEAK_BODY/_(LOW · kept)_/_(HIGH · kept)_}"
assert_exit 1 "$POST_CODE" "a LOW id relabelled HIGH in a priority table is refused"
assert_contains "F2" "$POST_ERR" "names the id"
assert_equal "" "$GH_ARGS" "gh not called"

_flow_test_begin "posting: no markdown construct hides a relabelled LOW row (round-3 bodies)"
# Each construct made the earlier heading parser lose track of where the
# Needs investigation section ended. The checks now read the whole body, so
# every one of these is refused whatever the construct.
HIGH_ROW='| **F2 · correctness · `src/c.sh:9`**<br>Looks like a race. _(HIGH · kept)_ | Add a lock. |'
FC_ROUND3=0
for CONSTRUCT in \
  $'~~~\n```\n~~~' \
  $'```diff\n```bash\n```' \
  $'````\n```\n````' \
  $'Blocking findings\n---' \
  $'Blocking findings\n===' \
  '> ### Blocking findings' \
  '<h3>Blocking findings</h3>' \
  '####### Seven hashes'; do
  _fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY

$CONSTRUCT

| Finding | Suggested Fix |
|---------|---------------|
$HIGH_ROW"
  assert_exit 1 "$POST_CODE" "refused after: $(printf '%s' "$CONSTRUCT" | tr '\n' ' ')"
  assert_equal "" "$GH_ARGS" "gh not called after: $(printf '%s' "$CONSTRUCT" | tr '\n' ' ')"
  FC_ROUND3=$((FC_ROUND3 + 1))
done
assert_equal "8" "$FC_ROUND3" "all eight constructs examined"

_flow_test_begin "posting: a LOW finding needs exactly one entry, in the entry shape, at its routed priority"
# Entry removed, row present: no entry.
_fc_post external "$FC_MIXED" 2 "$(grep -v '^- \*\*F2 · ' <<<"$FC_MIXED_BODY")
$HIGH_ROW"
assert_exit 1 "$POST_CODE" "a LOW id present only as a table row is refused"
assert_contains "no Needs investigation entry" "$POST_ERR" "says the entry is missing"
# The priority shown must be the routed one (F2 is P1).
PRI_BODY=${FC_MIXED_BODY/\*\*F2 · P1 · /**F2 · P3 · }
assert_contains "- **F2 · P3 · correctness" "$PRI_BODY" "the entry under test shows P3 in the entry shape"
_fc_post external "$FC_MIXED" 2 "$PRI_BODY"
assert_exit 1 "$POST_CODE" "an entry that changes the priority is refused"
assert_contains "no Needs investigation entry opening: - **F2 · P1 · " "$POST_ERR" "names the routed priority"
# A P3 bullet in the table's id shape counts as a second rendering.
_fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY

#### P3 — Suggestions
- **F2 · correctness · \`src/c.sh:9\`** — Looks like a race. _(MEDIUM · kept)_"
assert_exit 1 "$POST_CODE" "a LOW id repeated as a P3 bullet is refused"
# Two entries for one id.
_fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY
- **F2 · P1 · correctness · \`src/c.sh:9\`** — Looks like a race."
assert_exit 1 "$POST_CODE" "a LOW id rendered twice is refused"
# F21 is not F2: an id that extends another id is not a second rendering.
F21_BODY=$(awk '/^\| \*\*F1 · / { print; print "| **F21 · docs · `a.md:3`**<br>Stale link. _(HIGH · consensus)_ | Update it. |"; next } { print }' <<<"${FC_MIXED_BODY/P2: 1, P3: 0/P2: 2, P3: 0}")
_fc_post external "F1|P2|correctness|src/b.sh:4|HIGH|consensus|code-reviewer
F21|P2|docs|a.md:3|HIGH|consensus|code-reviewer
F2|P1|correctness|src/c.sh:9|LOW|kept|code-reviewer" 3 "$F21_BODY"
assert_exit 0 "$POST_CODE" "F21 beside a LOW F2 posts: $POST_ERR"

_flow_test_begin "posting: a LOW finding filed under a priority heading is refused (round 4)"
# The entry shape alone says what a LOW finding looks like, not where it sits.
UNDER_P1='## Review: PR #7

### Findings: P1: 0, P2: 1, P3: 0 · Needs investigation: 1

#### P1 — Critical (Blocks Merge)
- **F2 · P1 · correctness · `src/c.sh:9`** — Looks like a race.

#### P2 — Important
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · correctness · `src/b.sh:4`**<br>Wrong bound. _(HIGH · consensus)_ | Use `<`. |

#### Needs investigation
(none)'
_fc_post external "$FC_MIXED" 2 "$UNDER_P1"
assert_exit 1 "$POST_CODE" "an entry under #### P1 is refused"
assert_equal "" "$GH_ARGS" "gh not called"
# No Needs investigation heading at all.
_fc_post external "$FC_MIXED" 2 "$(grep -v '^#### Needs investigation$' <<<"$FC_MIXED_BODY")"
assert_exit 1 "$POST_CODE" "a body with no #### Needs investigation heading is refused"
assert_contains "Needs investigation" "$POST_ERR" "names the missing heading"
# Two headings: which one holds the entry is not knowable from a count.
_fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY

#### Needs investigation
(none)"
assert_exit 1 "$POST_CODE" "two Needs investigation headings are refused"
# A priority section opened after the Needs investigation heading.
_fc_post external "$FC_MIXED" 2 "$(grep -v '^- \*\*F2 · ' <<<"$FC_MIXED_BODY")

#### P1 — Critical (Blocks Merge)
- **F2 · P1 · correctness · \`src/c.sh:9\`** — Looks like a race."
assert_exit 1 "$POST_CODE" "a priority heading after the section is refused"
assert_equal "" "$GH_ARGS" "gh not called"
# A table row that carries the priority field, with no entry: the bullet anchor
# is the only check that separates it from an entry.
_fc_post external "$FC_MIXED" 2 "$(grep -v '^- \*\*F2 · ' <<<"$FC_MIXED_BODY")
| **F2 · P1 · correctness · \`src/c.sh:9\`**<br>Looks like a race. | Add a lock. |"
assert_exit 1 "$POST_CODE" "a table row in the section is not an entry"
assert_contains "no Needs investigation entry" "$POST_ERR" "says the entry is missing"

_flow_test_begin "posting: a counted finding is rendered once, and never in the entry shape (round 4)"
# A counted finding rendered only as a Needs investigation entry would tell the
# author it never blocks the merge, while its marker row blocks /flow:merge.
COUNTED_AS_ENTRY='## Review: PR #7

### Findings: P1: 0, P2: 1, P3: 0 · Needs investigation: 1

#### Needs investigation
- **F1 · P2 · correctness · `src/b.sh:4`** — Wrong bound.
- **F2 · P1 · correctness · `src/c.sh:9`** — Looks like a race.'
_fc_post external "$FC_MIXED" 2 "$COUNTED_AS_ENTRY"
assert_exit 1 "$POST_CODE" "a counted finding in the entry shape is refused"
assert_contains "F1" "$POST_ERR" "names the counted id"
assert_equal "" "$GH_ARGS" "gh not called"
# Absent altogether: the marker would carry an id the author never saw.
_fc_post external "$FC_MIXED" 2 "$(grep -v '^| \*\*F1 · ' <<<"$FC_MIXED_BODY")"
assert_exit 1 "$POST_CODE" "a counted finding missing from the body is refused"
assert_contains "F1" "$POST_ERR" "names the missing id"
# Rendered twice.
_fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY
Repeated: **F1 · correctness · src/b.sh:4** — Wrong bound."
assert_exit 1 "$POST_CODE" "a counted finding rendered twice is refused"
# The counted finding rendered as a P3 bullet, in the template's shape, posts.
_fc_post external 'F1|P3|docs|a.md:1|MEDIUM|unchallenged|code-reviewer' 1 "$FC_P3_BODY"
assert_exit 0 "$POST_CODE" "a P3 bullet carrying the id posts: $POST_ERR"

_flow_test_begin "posting: the Needs investigation section has an end as well as a start (round 5)"
# The section runs from its heading to the next #### heading, whatever that
# heading says. A finding on the wrong side of either edge is refused.
FC_ROUND5=0
# A counted finding rendered inside the section reads as "does not block the
# merge" while its marker row blocks /flow:merge.
_fc_post external "$FC_MIXED" 2 '## Review: PR #7

### Findings: P1: 0, P2: 1, P3: 0 · Needs investigation: 1

#### Needs investigation
- **F1 · correctness · `src/b.sh:4`** — Wrong bound. _(HIGH · consensus)_
- **F2 · P1 · correctness · `src/c.sh:9`** — Looks like a race.'
assert_exit 1 "$POST_CODE" "a counted finding inside the section is refused"
assert_contains "F1" "$POST_ERR" "names the counted id"
assert_equal "" "$GH_ARGS" "gh not called"
FC_ROUND5=$((FC_ROUND5 + 1))
# A LOW entry below the section, under whatever heading follows it. The last
# two spellings are priority headings the old `#### P1 ` match did not see.
for LATE_HEADING in '#### What Looks Good' '#### P1: Critical (Blocks Merge)' '#### P1—Critical (Blocks Merge)' '#### Requirements Adherence'; do
  _fc_post external "$FC_MIXED" 2 "$(grep -v '^- \*\*F2 · ' <<<"$FC_MIXED_BODY")
(none)

$LATE_HEADING
- **F2 · P1 · correctness · \`src/c.sh:9\`** — Looks like a race."
  assert_exit 1 "$POST_CODE" "an entry under '$LATE_HEADING' is refused"
  assert_equal "" "$GH_ARGS" "gh not called for '$LATE_HEADING'"
  FC_ROUND5=$((FC_ROUND5 + 1))
done
assert_equal "5" "$FC_ROUND5" "all five placements examined"
# A line that quotes the heading inline is not the heading: the body posts, and
# the entry below the real heading is found.
_fc_post external "$FC_MIXED" 2 "Its LOW findings are listed under #### Needs investigation below.

$FC_MIXED_BODY"
assert_exit 0 "$POST_CODE" "a prose mention of the heading does not move the section: $POST_ERR"
assert_contains "--request-changes" "$GH_ARGS" "posted"

# Two headings, with or without LOW findings: which one bounds the section is
# not readable, so nothing is posted.
_fc_post external 'F1|P3|docs|a.md:1|MEDIUM|unchallenged|code-reviewer' 1 "$FC_P3_BODY

#### Needs investigation
(none)

#### Needs investigation
(none)"
assert_exit 1 "$POST_CODE" "two headings are refused even with no LOW finding"
assert_equal "" "$GH_ARGS" "gh not called"

_flow_test_begin "posting: every counted finding is checked, not only the first (round 5)"
FC_TWO_COUNTED='F1|P2|correctness|src/b.sh:4|HIGH|consensus|code-reviewer
F3|P3|docs|a.md:2|MEDIUM|unchallenged|code-reviewer'
FC_TWO_COUNTED_BODY='## Review: PR #7

### Findings: P1: 0, P2: 1, P3: 1 · Needs investigation: 0

#### P2 — Important
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · correctness · `src/b.sh:4`**<br>Wrong bound. _(HIGH · consensus)_ | Use `<`. |

#### P3 — Suggestions
- **F3 · docs · `a.md:2`** — Stale link. _(MEDIUM · unchallenged)_'
_fc_post external "$FC_TWO_COUNTED" 2 "$FC_TWO_COUNTED_BODY"
assert_exit 0 "$POST_CODE" "both counted findings rendered: $POST_ERR"
# A counted finding written in the entry shape outside the section says the
# same wrong thing as one written inside it.
_fc_post external "$FC_TWO_COUNTED" 2 "${FC_TWO_COUNTED_BODY/- \*\*F3 · docs · /- **F3 · P3 · docs · }"
assert_exit 1 "$POST_CODE" "a counted finding in the entry shape under a priority heading is refused"
assert_contains "F3" "$POST_ERR" "names the id"
_fc_post external "$FC_TWO_COUNTED" 2 "$(grep -v '^- \*\*F3 · ' <<<"$FC_TWO_COUNTED_BODY")"
assert_exit 1 "$POST_CODE" "the second counted finding missing is refused"
assert_contains "F3" "$POST_ERR" "names the second id, not only the first"
assert_equal "" "$GH_ARGS" "gh not called"

_flow_test_begin "routing and posting print the counted total for the review-cycle manifest"
_fc_route external 'F1|P1|security|src/a.sh:1|HIGH|consensus|security-reviewer
F2|P3|docs|a.md:2|MEDIUM|unchallenged|code-reviewer
F3|P2|correctness|src/c.sh:9|LOW|kept|code-reviewer'
assert_equal "COUNT_TOTAL=2" "$(grep '^COUNT_TOTAL=' <<<"$ROUTE_OUT")" "P1 + P3 counted, the LOW P2 not (hand count: 2)"
_fc_route external "$FC_MIXED"
assert_equal "COUNT_TOTAL=1" "$(grep '^COUNT_TOTAL=' <<<"$ROUTE_OUT")" "routing block: one counted finding (the LOW one is not counted)"
_fc_post external "$FC_MIXED" 2 "$FC_MIXED_BODY"
assert_equal "COUNT_TOTAL=1" "$(grep '^COUNT_TOTAL=' <<<"$POST_OUT")" "posting block prints the same total"
STEP7_NOW=$(_fc_phase4_step 7)
assert_contains 'findings_count="$COUNT_TOTAL"' "$STEP7_NOW" "manifest emit uses the printed total"
assert_not_contains 'findings_count=$TOTAL' "$STEP7_NOW" "no unset TOTAL"
assert_contains 'the synthesized findings minus any refuted in step 5' "$STEP7_NOW" "FINDING_TOTAL excludes refuted findings"

_flow_test_begin "dropped-finding block resolves the linked issue itself and skips cleanly without one"
mkdir -p "$FC_TMP/journal-repo2"
(cd "$FC_TMP/journal-repo2" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 43)" \
  CYCLE_NUMBER=1 PR_NUM=7 FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >"$FC_TMP/d2.out" 2>"$FC_TMP/d2.err"); D2_CODE=$?
assert_exit 0 "$D2_CODE" "issue resolved from the PR body"
if [ -f "$FC_TMP/journal-repo2/.decisions/issue-43.md" ]; then
  assert_equal "type=dropped-finding reason=self-review-refuted finding_id=F4 facet=security-reviewer cycle=1 pr=7" \
    "$(_fc_last_artifact "$FC_TMP/journal-repo2/.decisions/issue-43.md")" "recorded against issue 43"
else
  _flow_assert_fail "no journal for issue 43: $(cat "$FC_TMP/d2.err")"
fi
mkdir -p "$FC_TMP/journal-repo3"
(cd "$FC_TMP/journal-repo3" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing)" STUB_BODY="Closes #43" \
  CYCLE_NUMBER=1 PR_NUM=7 FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >"$FC_TMP/d3.out" 2>"$FC_TMP/d3.err"); D3_CODE=$?
assert_exit 0 "$D3_CODE" "no linked issue is not an error"
assert_contains "DROPPED_FINDING=skipped" "$(cat "$FC_TMP/d3.out")" "says the record was skipped (body text does not link an issue)"
assert_equal "" "$(ls "$FC_TMP/journal-repo3/.decisions" 2>/dev/null)" "no journal written"

_flow_test_begin "prose made false by the first draft is corrected"
PARSER_NOW=$(cat "$PLUGIN_DIR/references/finding-ledger-parser.md")
assert_not_contains 'Source: `templates/review-comment.md`' "$PARSER_NOW" "marker source is the posting block, not a template"
assert_not_contains "They are emitted by review and resolution templates" "$PARSER_NOW" "emitters named correctly"
assert_not_contains "No emitter pre-validates the disposition string" "$PARSER_NOW" "emitter-side validation documented"
assert_contains "%5D" "$PARSER_NOW" "percent-encoding of category and location documented in the parser reference"
assert_contains "%5D" "$(cat "$PLUGIN_DIR/references/finding-schema.md")" "percent-encoding documented in the finding schema"
assert_contains "only when the producer gave none" "$(_fc_phase4_step 2)" "step 2 keeps a producer's confidence (Path A holdout consensus stays HIGH)"
assert_contains "do not re-enter step 7" "$(awk '/^6\. \*\*Display findings\*\*/ { f = 1; print; next } f && /^7\. \*\*/ { exit } f' "$PLUGIN_DIR/commands/pr.md")" "escalated LOW findings do not loop in /flow:pr"
assert_match '^7\. \*\*If P1 or P2 findings that are not escalated\*\*' "$(cat "$PLUGIN_DIR/commands/pr.md")" "step 7's condition excludes escalated findings"
MERGE_TEXT=$(cat "$PLUGIN_DIR/commands/merge.md")
assert_not_contains "self-review template carries in its format-guide comment" "$MERGE_TEXT" "merge seed comment no longer says a template carries a marker"
assert_contains "the form the" "$MERGE_TEXT" "merge seed comment names where the placeholder form appears"

# --- second self-review round -------------------------------------------------

_flow_test_begin "dropped-finding block fails closed when the pull request cannot be read"
cat > "$FC_STUB/gh-fail" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo "o/r"; exit 0 ;;
  "pr view") echo "HTTP 502" >&2; exit 1 ;;
esac
exit 1
STUB
chmod +x "$FC_STUB/gh-fail"
mkdir -p "$FC_TMP/failstub" "$FC_TMP/journal-repo4"
cp "$FC_STUB/gh-fail" "$FC_TMP/failstub/gh"
(cd "$FC_TMP/journal-repo4" && PATH="$FC_TMP/failstub:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  CYCLE_NUMBER=1 PR_NUM=7 FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >"$FC_TMP/d4.out" 2>"$FC_TMP/d4.err"); D4_CODE=$?
assert_exit 1 "$D4_CODE" "an unreadable pull request is an error"
assert_not_contains "skipped" "$(cat "$FC_TMP/d4.out")" "not reported as a pull request without an issue"

_flow_test_begin "the linked issue is one GitHub lists as closing, never text in the body"
# Bodies that fooled a keyword regex: a mention before the keyword, a word
# ending in a keyword, and a keyword quoted in a code span or a fence.
FC_TRAPS=0
for TRAP_BODY in \
  $'Follows up on #210 and the #333 colour.\n\nCloses #212' \
  'hotfix #210, see Closes #212' \
  'unresolved #210 (Closes #212)' \
  $'`Closes #12` is the old form.\n\nCloses #212' \
  $'```\nFixes #12\n```\nCloses #212'; do
  FC_TRAPS=$((FC_TRAPS + 1))
  mkdir -p "$FC_TMP/journal-trap-$FC_TRAPS"
  (cd "$FC_TMP/journal-trap-$FC_TRAPS" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_BODY="$TRAP_BODY" STUB_CLOSING="$(_fc_closing 212)" \
    CYCLE_NUMBER=1 PR_NUM=7 FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >/dev/null 2>"$FC_TMP/d5.err"); D5_CODE=$?
  assert_exit 0 "$D5_CODE" "trap $FC_TRAPS recorded: $(cat "$FC_TMP/d5.err")"
  assert_equal "issue-212.md" "$(ls "$FC_TMP/journal-trap-$FC_TRAPS/.decisions" 2>/dev/null | grep -v '\.lock$')" "trap $FC_TRAPS: only issue 212's journal"
done
assert_equal "5" "$FC_TRAPS" "all five bodies examined"
mkdir -p "$FC_TMP/journal-repo6"
(cd "$FC_TMP/journal-repo6" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 219 213)" \
  CYCLE_NUMBER=1 PR_NUM=7 FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >/dev/null 2>"$FC_TMP/d6.err")
assert_equal "issue-213.md" "$(ls "$FC_TMP/journal-repo6/.decisions" 2>/dev/null | grep -v '\.lock$')" "a pull request closing two issues records against the lower"
mkdir -p "$FC_TMP/journal-bad"
for BAD in '' 0 07 7a; do
  (cd "$FC_TMP/journal-bad" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 213)" \
    CYCLE_NUMBER="$BAD" PR_NUM=7 FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >/dev/null 2>&1); D7_CODE=$?
  assert_exit 1 "$D7_CODE" "dropped-finding block refuses CYCLE_NUMBER '$BAD'"
  (cd "$FC_TMP/journal-bad" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 213)" \
    CYCLE_NUMBER=1 PR_NUM="$BAD" FINDING_ID=F4 FACET=security-reviewer bash "$FC_TMP/dropped-block.sh" >/dev/null 2>&1); D7_CODE=$?
  assert_exit 1 "$D7_CODE" "dropped-finding block refuses PR_NUM '$BAD'"
done
assert_equal "" "$(ls "$FC_TMP/journal-bad/.decisions" 2>/dev/null | grep -v '\.lock$')" "nothing recorded for a bad number"

_flow_test_begin "review-cycle manifest block refuses empty or non-numeric values"
_fc_block "REVIEW_CYCLE_MANIFEST_BLOCK" > "$FC_TMP/manifest-block.sh"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/manifest-block.sh")" "manifest block extracted"
sed 's/path={A|B}/path=B/' "$FC_TMP/manifest-block.sh" > "$FC_TMP/manifest-run.sh"
mkdir -p "$FC_TMP/journal-repo7"
(cd "$FC_TMP/journal-repo7" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 42)" \
  CYCLE_NUMBER=2 PR_NUM=7 bash "$FC_TMP/manifest-run.sh" >/dev/null 2>"$FC_TMP/m1.err"); M1_CODE=$?
assert_exit 1 "$M1_CODE" "COUNT_TOTAL unset → refused"
assert_equal "" "$(ls "$FC_TMP/journal-repo7/.decisions" 2>/dev/null)" "nothing written"
# _fc_manifest <PR_NUM> <CYCLE_NUMBER> <COUNT_TOTAL> — runs the block in a
# scratch repository; sets M_CODE.
mkdir -p "$FC_TMP/journal-manifest-bad" "$FC_TMP/journal-manifest-zero"
_fc_manifest() {
  (cd "$FC_TMP/${4:-journal-manifest-bad}" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 42)" \
    PR_NUM="$1" CYCLE_NUMBER="$2" COUNT_TOTAL="$3" bash "$FC_TMP/manifest-run.sh" >/dev/null 2>&1)
  M_CODE=$?
}
FC_BAD_VALUES=0
for BAD in '' 7a '{N} -->' -1 0 08; do
  _fc_manifest "$BAD" 2 3; assert_exit 1 "$M_CODE" "PR_NUM '$BAD' refused"
  _fc_manifest 7 "$BAD" 3; assert_exit 1 "$M_CODE" "CYCLE_NUMBER '$BAD' refused"
  FC_BAD_VALUES=$((FC_BAD_VALUES + 1))
done
for BAD in '' 7a '{N} -->' -1 08; do
  _fc_manifest 7 2 "$BAD"; assert_exit 1 "$M_CODE" "COUNT_TOTAL '$BAD' refused"
  FC_BAD_VALUES=$((FC_BAD_VALUES + 1))
done
assert_equal "11" "$FC_BAD_VALUES" "every bad value examined"
assert_equal "" "$(ls "$FC_TMP/journal-manifest-bad/.decisions" 2>/dev/null | grep -v '\.lock$')" "nothing written for a bad value"
_fc_manifest 7 2 0 journal-manifest-zero
assert_exit 0 "$M_CODE" "COUNT_TOTAL 0 is a clean review, not an error"
assert_file_exists "$FC_TMP/journal-manifest-zero/.decisions/issue-42.md" "the clean review is recorded"
(cd "$FC_TMP/journal-repo7" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 42)" \
  CYCLE_NUMBER=2 PR_NUM=7 COUNT_TOTAL=3 bash "$FC_TMP/manifest-run.sh" >/dev/null 2>"$FC_TMP/m2.err"); M2_CODE=$?
assert_exit 0 "$M2_CODE" "valid values recorded"
if [ -f "$FC_TMP/journal-repo7/.decisions/issue-42.md" ]; then
  M_ART=$(python3 - "$FC_TMP/journal-repo7/.decisions/issue-42.md" <<'PY'
import sys, yaml
c = open(sys.argv[1]).read()
end = c.find("\n---\n", 4)
a = yaml.safe_load(c[4:end])["artifacts"][-1]
print("type={} cycle={!r} findings_count={!r} path={} pr={!r}".format(a["type"], a["cycle"], a["findings_count"], a["path"], a["pr"]))
PY
)
  assert_equal "type=review-cycle cycle=2 findings_count=3 path=B pr=7" "$M_ART" "integers recorded, read back from the manifest"
else
  _flow_assert_fail "no manifest written: $(cat "$FC_TMP/m2.err")"
fi

_flow_test_begin "every issue lookup asks GitHub for the closing issue: A.4, Phase 1, merge"
_fc_block "CHALLENGE_DROPPED_FINDING_BLOCK" > "$FC_TMP/challenge-dropped.sh"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/challenge-dropped.sh")" "A.4 dropped-finding block extracted"
mkdir -p "$FC_TMP/journal-a4"
(cd "$FC_TMP/journal-a4" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_BODY="hotfix #210" STUB_CLOSING="$(_fc_closing 212)" \
  CYCLE_NUMBER=3 PR_NUM=7 FINDING_ID=F9 FACET=code-reviewer REASON="both variants disagreed" bash "$FC_TMP/challenge-dropped.sh" >"$FC_TMP/a4.out" 2>"$FC_TMP/a4.err"); A4_CODE=$?
assert_exit 0 "$A4_CODE" "A.4 block records: $(cat "$FC_TMP/a4.err")"
if [ -f "$FC_TMP/journal-a4/.decisions/issue-212.md" ]; then
  assert_equal "type=dropped-finding reason=both variants disagreed finding_id=F9 facet=code-reviewer cycle=3 pr=7" \
    "$(_fc_last_artifact "$FC_TMP/journal-a4/.decisions/issue-212.md")" "recorded against the closing issue, reason kept whole"
else
  _flow_assert_fail "A.4 block wrote no journal for issue 212: $(cat "$FC_TMP/a4.err")"
fi
mkdir -p "$FC_TMP/journal-a4-none"
(cd "$FC_TMP/journal-a4-none" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing)" \
  CYCLE_NUMBER=3 PR_NUM=7 FINDING_ID=F9 FACET=code-reviewer REASON="both variants disagreed" bash "$FC_TMP/challenge-dropped.sh" >"$FC_TMP/a4n.out" 2>/dev/null); A4N_CODE=$?
assert_exit 0 "$A4N_CODE" "no closing issue is not an error"
assert_contains "DROPPED_FINDING=skipped" "$(cat "$FC_TMP/a4n.out")" "A.4 block says it skipped"
mkdir -p "$FC_TMP/journal-manifest-none"
(cd "$FC_TMP/journal-manifest-none" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing)" \
  PR_NUM=7 CYCLE_NUMBER=2 COUNT_TOTAL=1 bash "$FC_TMP/manifest-run.sh" >"$FC_TMP/mn.out" 2>/dev/null); MN_CODE=$?
assert_exit 0 "$MN_CODE" "no closing issue is not an error for the manifest"
assert_contains "REVIEW_CYCLE_RECORD=skipped" "$(cat "$FC_TMP/mn.out")" "the manifest block says it skipped"
(cd "$FC_TMP/journal-a4-none" && PATH="$FC_TMP/failstub:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
  CYCLE_NUMBER=3 PR_NUM=7 FINDING_ID=F9 FACET=code-reviewer REASON=x bash "$FC_TMP/challenge-dropped.sh" >/dev/null 2>&1); A4F_CODE=$?
assert_exit 1 "$A4F_CODE" "A.4 block fails closed when GitHub cannot be read"
(cd "$FC_TMP/journal-a4-none" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing 212)" \
  CYCLE_NUMBER=3 PR_NUM=7 FINDING_ID=F9 FACET=code-reviewer bash "$FC_TMP/challenge-dropped.sh" >/dev/null 2>&1); A4R_CODE=$?
assert_exit 1 "$A4R_CODE" "A.4 block refuses a missing REASON"
assert_equal "" "$(ls "$FC_TMP/journal-a4-none/.decisions" 2>/dev/null | grep -v '\.lock$')" "nothing recorded by the refused runs"

_fc_block "ESCALATION_RESOLVED_BLOCK" "$PLUGIN_DIR/commands/merge.md" > "$FC_TMP/merge-escalation.sh"
assert_match '[^[:space:]]' "$(cat "$FC_TMP/merge-escalation.sh")" "merge escalation block extracted"
sed -e 's/"\$ARGUMENTS"/"7"/' -e 's/{FIELD}/options/' -e 's/{OUTCOME}/kept the fix/' "$FC_TMP/merge-escalation.sh" > "$FC_TMP/merge-escalation-run.sh"
mkdir -p "$FC_TMP/journal-merge"
(cd "$FC_TMP/journal-merge" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_BODY=$'Follows #210.\n\nCloses #212' STUB_CLOSING="$(_fc_closing 212)" \
  bash "$FC_TMP/merge-escalation-run.sh" >/dev/null 2>"$FC_TMP/merge.err"); MERGE_CODE=$?
assert_exit 0 "$MERGE_CODE" "merge block records: $(cat "$FC_TMP/merge.err")"
assert_equal "issue-212.md" "$(ls "$FC_TMP/journal-merge/.decisions" 2>/dev/null | grep -v '\.lock$')" "merge records against the closing issue, not the first #N"
mkdir -p "$FC_TMP/journal-merge-none"
(cd "$FC_TMP/journal-merge-none" && PATH="$FC_STUB:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" STUB_CLOSING="$(_fc_closing)" \
  bash "$FC_TMP/merge-escalation-run.sh" >"$FC_TMP/en.out" 2>/dev/null); EN_CODE=$?
assert_exit 0 "$EN_CODE" "no closing issue is not an error for the merge record"
assert_contains "ESCALATION_RECORD=skipped" "$(cat "$FC_TMP/en.out")" "the merge block says it skipped"

PREFLIGHT_LINK=$(awk '/### Linked Issue/ { f = 1 } f { print } f && /LINKED_ISSUE=/ { exit }' "$REVIEW_MD")
assert_contains "flow-pr-linked-issue.sh" "$PREFLIGHT_LINK" "Phase 1 prints the issue the helper resolves"
assert_contains "never in the bold" "$STEP7" "step 7 tells the reviewer how to write prior-cycle ids"
assert_contains "flow-pr-linked-issue.sh" "$(_fc_phase4_step 7)" "the review-cycle manifest resolves the issue with the helper"
assert_contains "flow-pr-linked-issue.sh" "$(awk '/^\*\*FlowRun terminal transition\*\*/ { print }' "$REVIEW_MD")" "the workflow-run record names the helper"

_flow_test_begin "sweep: no command parses an issue number out of pull request text"
# _fc_lookup_sweep <dir> — prints FILES=<examined> HITS=<lines that grep a
# #N or a closing keyword out of text>.
_fc_lookup_sweep() {
  local files hits
  files=$(find "$1" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  hits=$(grep -rnE '(grep -[A-Za-z]*o[A-Za-z]*|sed )' "$1" --include='*.md' 2>/dev/null | grep -cE '#\\?\(?\[0-9\]' | tr -d ' ')
  printf 'FILES=%s HITS=%s' "$files" "$hits"
}
assert_equal "FILES=1 HITS=4" "$(_fc_lookup_sweep "$FC_FIXTURES/lookup-sweep-fire")" "fires on all four spellings of the retired lookups"
assert_equal "FILES=1 HITS=0" "$(_fc_lookup_sweep "$FC_FIXTURES/lookup-sweep-silent")" "silent on the helper call and on prose mentioning #N"
assert_equal "FILES=0 HITS=0" "$(_fc_lookup_sweep "$FC_TMP/no-such-dir")" "an empty input examines nothing"
FC_LOOKUP=$(_fc_lookup_sweep "$PLUGIN_DIR/commands")
assert_match '^FILES=([2-9][0-9]|[1-9][0-9][0-9]) ' "$FC_LOOKUP" "the command directory was examined"
assert_contains "HITS=0" "$FC_LOOKUP" "no command greps an issue number out of text"

_flow_test_begin "real template: a body rendered from review-comment.md posts through the block"
awk '
  /^\{/ { next }
  { gsub(/\{p1_count\}/, "0"); gsub(/\{p2_count\}/, "1"); gsub(/\{p3_count\}/, "0"); gsub(/\{needs_investigation_count\}/, "1"); gsub(/\{pr_number\}/, "7") }
  /^\| \*\*\{ID\} · \{category\}/ { next }
  /^- \*\*\{ID\} · \{category\}/ { next }
  /^- \*\*\{ID\} · \{priority\}/ { print "- **F2 · P1 · correctness · `src/c.sh:9`** — Looks like a race."; next }
  /^  Pattern: \{what triggered/ { print "  Pattern: shared counter without a lock. Confirm or refute: a concurrent test."; next }
  /^#### P2 — Important/ { print; getline; print; getline; print; print "| **F1 · correctness · `src/b.sh:4`**<br>Wrong bound. _(HIGH · consensus)_ | Use `<`. |"; next }
  { print }
' "$TEMPLATES/review-comment.md" > "$FC_TMP/rendered-review.md"
assert_contains "### Findings: P1: 0, P2: 1, P3: 0 · Needs investigation: 1" "$(cat "$FC_TMP/rendered-review.md")" "rendered header"
_fc_post external "$FC_MIXED" 2 "$(cat "$FC_TMP/rendered-review.md")"
assert_exit 0 "$POST_CODE" "the rendered template posts (its closing comment trips no guard): $POST_ERR"
assert_contains "--request-changes" "$GH_ARGS" "decision from the HIGH P2"
assert_equal "1" "$(grep -c 'FLOW_REVIEW_CYCLE:2 FINDINGS:\[' <<<"$POSTED")" "exactly one marker in the posted body"
