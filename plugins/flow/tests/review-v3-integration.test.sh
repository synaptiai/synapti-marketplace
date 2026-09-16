# Tests for the v3 runtime integration — FlowRun wiring in commands/review.md.
#
# Contract under test:
#   - review.md wires a FlowRun at the end of Phase 1 (FLOW_RUN_STATE block,
#     gated by flow.runtime.enabled), invokes Skill(run-state-management),
#     records activities at the consolidate/report boundaries, and transitions
#     the run to a terminal state at the end of the report phase.
#   - review is FlowRun-only (no FlowGoal) — a review session is bounded by the
#     PR and the PR's own review-thread state is the durable record.
#   - The entry block (between FLOW_RUN_BLOCK_BEGIN/END) is runnable: it emits
#     FLOW_RUN_STATE=create with RUN_ID + WORKFLOW=review-pr when runtime is
#     enabled, and FLOW_RUN_STATE=skip when flow.runtime.enabled is false.
#
# Prereq: jq (cascade-resolve.sh dependency). SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
REVIEW_MD="$PLUGIN_DIR/commands/review.md"
CASCADE="$PLUGIN_DIR/bin/cascade-resolve.sh"

REV_CLEANUP=()
_rev_cleanup() { local p; for p in "${REV_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _rev_cleanup EXIT

CONTENT=$(cat "$REVIEW_MD")

# --- source-presence: FlowRun wiring
_flow_test_begin "review.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=review-pr" "$CONTENT" "names the review-pr workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"

_flow_test_begin "review.md records activities at phase boundaries"
assert_contains "FlowActivity writes" "$CONTENT" "activity-write step documented"
assert_match 'preflight . fan-out . consolidate . report' "$CONTENT" "documents the review phase order"

_flow_test_begin "review.md transitions the FlowRun to terminal state"
assert_contains "FlowRun terminal transition" "$CONTENT" "terminal-transition step documented"
assert_contains "state.status: completed" "$CONTENT" "completes the run on success"
assert_contains "cancelled" "$CONTENT" "cancels the run on failure (not left resumable)"

_flow_test_begin "review is FlowRun-only (no FlowGoal)"
assert_not_contains "goal-contract-capture" "$CONTENT" "review does not create a FlowGoal"
assert_contains "creates NO FlowGoal" "$CONTENT" "documents review creates no goal"

# --- functional: extract the entry block and run it under controlled settings
_extract_run_block() {
  awk '/FLOW_RUN_BLOCK_BEGIN/{f=1;next} /FLOW_RUN_BLOCK_END/{f=0} f' "$REVIEW_MD"
}

_flow_test_begin "entry block emits FLOW_RUN_STATE=create when runtime enabled (default)"
WORK=$(mktemp -d -t flow-rev.XXXXXX); REV_CLEANUP+=("$WORK")
_extract_run_block > "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=review-pr" "$OUT" "workflow id emitted"
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
SCHEMA_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$SCHEMA_PAT"; then _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema"; else _flow_assert_fail "RUN_ID '$RUN_ID' violates /$SCHEMA_PAT/"; fi
assert_contains "review" "$RUN_ID" "RUN_ID carries the review slug"

_flow_test_begin "entry block emits FLOW_RUN_STATE=skip when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-rev2.XXXXXX); REV_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block > "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip (no-op for v2 projects)"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"

# --- #213 AC1: Phase 1 reads the FlowGoal -------------------------------------

RG_TMP=$(mktemp -d -t flow-rev213.XXXXXX); REV_CLEANUP+=("$RG_TMP")

_flow_test_begin "review.md Phase 1 carries a runnable FlowGoal block"
RG_MD="$REPO_ROOT/plugins/flow/commands/review.md"
_rg_block() {
  awk -v b="# FLOWGOAL_BLOCK_BEGIN" -v e="# FLOWGOAL_BLOCK_END" '
    { t = $0; sub(/^[ \t]+/, "", t) }
    t == b { f = 1; next }
    t == e { f = 0 }
    f' "$RG_MD"
}
_rg_block > "$RG_TMP/flowgoal.sh"
assert_match '[^[:space:]]' "$(cat "$RG_TMP/flowgoal.sh")" "FlowGoal block extracted"

# The goal arrives with the checkout, so every value in it is the author's data.
# Nothing in the block may hand a goal value to a shell.
RG_SRC=$(cat "$RG_TMP/flowgoal.sh")
assert_not_contains 'eval' "$RG_SRC" "no eval anywhere in the block"
assert_not_contains 'bash -c' "$RG_SRC" "no bash -c"
assert_not_contains 'sh -c' "$RG_SRC" "no sh -c"
# The python reader names the field because it reads it; what must never happen
# is a SHELL line touching a goal value, so assert on the shell half only.
awk '/<<.FLOW_GOAL_READ./ { skip = 1; next } /^FLOW_GOAL_READ$/ { skip = 0; next } !skip' \
  "$RG_TMP/flowgoal.sh" > "$RG_TMP/flowgoal-shell.sh"
assert_match '[^[:space:]]' "$(cat "$RG_TMP/flowgoal-shell.sh")" "shell half extracted"
assert_equal "0" "$(grep -c 'verification_command' "$RG_TMP/flowgoal-shell.sh" | tr -d ' ')" \
  "no shell line touches a verification_command value"
assert_equal "0" "$(grep -cE '\$\(.*(AC|GOAL_STATUS|RISK_MAP|verification)' "$RG_TMP/flowgoal-shell.sh" | tr -d ' ')" \
  "no command substitution over a goal value"

# _rg_run <dir> <LINKED> — runs the block; sets RG_OUT, RG_CODE.
_rg_run() {
  RG_OUT=$(cd "$1" && PATH="$RG_STUB:$PATH" LINKED="$2" PR_NUM=7 REPO=o/r \
    bash "$RG_TMP/flowgoal.sh" 2>"$RG_TMP/rg.err")
  RG_CODE=$?
}

mkdir -p "$RG_TMP/stub"
RG_STUB="$RG_TMP/stub"
cat > "$RG_STUB/gh" <<'STUB'
#!/usr/bin/env bash
# `gh pr diff --name-only` for the goal-edited check.
case "$1 $2" in
  "pr diff") printf '%s\n' "${STUB_DIFF_FILES:-plugins/flow/commands/review.md}"; exit 0 ;;
esac
exit 1
STUB
chmod +x "$RG_STUB/gh"

_flow_test_begin "FlowGoal: a goal on the head is read, and its values are printed not run"
RG_REPO="$RG_TMP/withgoal"
mkdir -p "$RG_REPO/.flow/goals"
cp "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$RG_REPO/.flow/goals/issue-42.goal.yaml"
_rg_run "$RG_REPO" 42
assert_exit 0 "$RG_CODE" "block ran: $(cat "$RG_TMP/rg.err")"
assert_contains "STATE=ok" "$RG_OUT" "the goal was read"
assert_contains "GOAL_PATH=.flow/goals/issue-42.goal.yaml" "$RG_OUT" "names the path it read"
assert_contains "GOAL_STATUS=" "$RG_OUT" "reports the lifecycle status"
assert_match 'AC=AC1\|' "$RG_OUT" "one AC line per criterion, id first"
assert_contains "NON_GOAL=" "$RG_OUT" "non-goals are handed over"
assert_contains "CONTRACT=" "$RG_OUT" "interface contracts are handed over"
assert_match 'RISK_MAP=.*\|goal$' "$RG_OUT" "a row from the goal is labelled as coming from the goal"
assert_contains "RISK_MAP_SOURCE=goal" "$RG_OUT" "and the source is stated"

_flow_test_begin "FlowGoal: a verification_command is data, never a command"
RG_PWNED="$RG_TMP/pwned-marker"
RG_EVIL="$RG_TMP/evil"
mkdir -p "$RG_EVIL/.flow/goals"
cat > "$RG_EVIL/.flow/goals/issue-42.goal.yaml" <<YAML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria:
    - id: AC1
      text: 'a criterion'
      verification_command: '\$(touch $RG_PWNED)'
lifecycle: {status: active}
YAML
_rg_run "$RG_EVIL" 42
assert_exit 0 "$RG_CODE" "block ran"
assert_contains 'touch' "$RG_OUT" "the command text is shown to the reader"
if [ -e "$RG_PWNED" ]; then
  _flow_assert_fail "the block executed a verification_command: $RG_PWNED exists"
else
  _flow_assert_pass "reading the goal created no file — the value was never evaluated"
fi

_flow_test_begin "FlowGoal: absent is not the same as unreadable"
RG_NONE="$RG_TMP/nogoal"
mkdir -p "$RG_NONE"
_rg_run "$RG_NONE" 42
assert_contains "STATE=none" "$RG_OUT" "no goal file on the head is STATE=none"
_rg_run "$RG_NONE" none
assert_contains "STATE=none" "$RG_OUT" "no linked issue is STATE=none"
RG_BAD="$RG_TMP/badgoal"
mkdir -p "$RG_BAD/.flow/goals"
printf ': not: yaml:\n  - [\n' > "$RG_BAD/.flow/goals/issue-42.goal.yaml"
_rg_run "$RG_BAD" 42
assert_contains "STATE=unavailable" "$RG_OUT" "a goal that does not parse is unavailable, not absent"
assert_not_contains "STATE=none" "$RG_OUT" "never reported as no goal"
assert_contains "REASON=" "$RG_OUT" "and says why"

_flow_test_begin "FlowGoal: a goal with no risk map hands the reviewer the derivation rule"
RG_NORISK="$RG_TMP/norisk"
mkdir -p "$RG_NORISK/.flow/goals"
cat > "$RG_NORISK/.flow/goals/issue-42.goal.yaml" <<'YAML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria:
    - id: AC1
      text: 'a criterion'
      verification_command: 'make test'
specification:
  non_goals: ['nothing here']
lifecycle: {status: active}
YAML
_rg_run "$RG_NORISK" 42
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "with no rows in the goal the reviewer derives them"
assert_equal "0" "$(printf '%s\n' "$RG_OUT" | grep -c '^RISK_MAP=')" "and the block invents none itself"

_flow_test_begin "FlowGoal: a pull request that edits its own goal is flagged"
STUB_DIFF_FILES=".flow/goals/issue-42.goal.yaml" _rg_run "$RG_REPO" 42
assert_contains "GOAL_EDITED=yes" "$RG_OUT" "editing the goal under review is reported"
_rg_run "$RG_REPO" 42
assert_contains "GOAL_EDITED=no" "$RG_OUT" "a diff that leaves it alone is not"

# --- #213 AC2: the risk map reaches the two places that can check it ----------

_flow_test_begin "holdout-validation is handed risk-map coverage, and the reviewer is handed the rows"
RG_REVIEW=$(cat "$RG_MD")
# Every holdout dispatch — both Path A lenses and Path B — must offer the
# coverage list, or the skill's risk-map step has nothing to read and skips.
RG_DISPATCHES=$(printf '%s\n' "$RG_REVIEW" | grep -c 'Evidence bundle draft:')
assert_equal "3" "$RG_DISPATCHES" "three dispatches: two Path A lenses and Path B"
RG_WITH_COVERAGE=$(printf '%s\n' "$RG_REVIEW" | grep -c 'Evidence bundle draft:.*Risk map coverage')
assert_equal "3" "$RG_WITH_COVERAGE" "each one hands over the coverage list"
assert_contains 'area> → <test file:line' "$RG_REVIEW" "the shape of a coverage row is stated"
assert_contains 'RISK_MAP_SOURCE' "$RG_REVIEW" "and the reviewer is told where the rows came from"

RG_REVIEWER=$(cat "$REPO_ROOT/plugins/flow/agents/code-reviewer.md")
assert_match 'Risk areas:' "$RG_REVIEWER" "the reviewer names Risk areas"
assert_contains 'Inputs' "$RG_REVIEWER" "Step 4 states its inputs"
# The rule at Step 4 already consumes `Risk areas:` rows; the gap was that
# nothing handed them over, so the rule could never fire.
RG_STEP4=$(printf '%s\n' "$RG_REVIEWER" | awk '/^### Step 4/ { f = 1 } f && /^### Step 5/ { f = 0 } f')
assert_contains 'Risk areas:' "$RG_STEP4" "Step 4 names the input"
assert_contains 'source' "$RG_STEP4" "and says a derived row is marked as derived"

# --- #213 AC4: one true statement about which commands create goals ----------

_flow_test_begin "the references do not claim review or address creates a goal"
# commands/review.md and commands/address.md both say they are FlowRun-only and
# create no FlowGoal; flow-goals.md said the opposite, and a reader had no way
# to tell which was true.
RG_REFS=$(grep -rl '' "$REPO_ROOT/plugins/flow/references/" | wc -l | tr -d ' ')
assert_match '^[1-9]' "$RG_REFS" "the references directory was examined"
assert_equal "0" "$(grep -rc 'pr-<N>-review\.goal\.yaml' "$REPO_ROOT/plugins/flow/references/" 2>/dev/null | awk -F: '{t+=$2} END {print t+0}')" \
  "no reference claims review creates a goal"
assert_equal "0" "$(grep -rc 'pr-<N>-address\.goal\.yaml' "$REPO_ROOT/plugins/flow/references/" 2>/dev/null | awk -F: '{t+=$2} END {print t+0}')" \
  "no reference claims address creates a goal"
RG_GOALS_DOC=$(cat "$REPO_ROOT/plugins/flow/references/flow-goals.md")
assert_contains 'FlowRun-only' "$RG_GOALS_DOC" "and it states what they do instead"

# --- #213 AC5: the review workflow declares the goal it may read -------------

_flow_test_begin "review-pr.workflow.yaml documents the optional goal input"
RG_WF="$REPO_ROOT/plugins/flow/workflows/review-pr.workflow.yaml"
assert_file_exists "$RG_WF" "the workflow exists"
RG_WF_TXT=$(cat "$RG_WF")
assert_contains 'goal' "$RG_WF_TXT" "the goal input is declared"
assert_match 'required: false' "$RG_WF_TXT" "and is optional — a pull request without a goal still reviews"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  RG_WF_INPUTS=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('$RG_WF'))
i = (d.get('inputs') or {})
print('goal_path' in i, (i.get('goal_path') or {}).get('required'))
")
  assert_equal "True False" "$RG_WF_INPUTS" "goal_path is declared and not required"
else
  _flow_assert_pass "SKIP: PyYAML unavailable"
fi
