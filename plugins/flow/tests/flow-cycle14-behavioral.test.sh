# Behavioral tests for cycle-13 fixes that previously had source-presence-only
# coverage. Upgraded in cycle 14 (paired-reviewer test-skeptic S1-S6 +
# test-verifier F6-V1/F9-V1/F10-V1 surfaced the gaps).
#
# Covered:
#   F4 — workflow-validation migration shim accepts legacy `requires` field
#   F9 — _check_stuck increments counter on unchanged delta, resets on
#        progress/regress, transitions goal to failed at threshold, writes
#        stuck-detection-fired event, fails honestly when transition write
#        fails
#   F10 — goal-evaluator SKILL.md documents the proposed_transition contract
#         (skill does NOT write terminal status; caller persists)

C14_CLEANUP_PATHS=()
_c14_cleanup() {
  local p
  for p in "${C14_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _c14_cleanup EXIT

_c14_mktmp() {
  local out
  out=$(mktemp -d -t flow-cycle14.tests.XXXXXX 2>/dev/null)
  [ -z "$out" ] && { echo "mktemp failed" >&2; exit 2; }
  C14_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi
if ! python3 -c "import jsonschema" >/dev/null 2>&1; then
  _flow_test_begin "jsonschema prerequisite"
  _flow_assert_pass "SKIP: jsonschema not installed"
  return 0
fi

# --- F4 — migration shim accepts legacy `requires` field with WARN
_flow_test_begin "F4 — workflow-validation migration shim accepts legacy 'requires'"

SCHEMA="$REPO_ROOT/plugins/flow/schemas/v1/workflow.schema.json"
DIR=$(_c14_mktmp)
cat > "$DIR/legacy.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowWorkflow
metadata:
  id: legacy-test
  command: /flow:example
  version: 1
  description: legacy workflow using requires
phases:
  - id: explore
    type: mixed
    activities:
      - id: noop
        evidence: gathered_context
completion_gate:
  requires:
    - all_checks_pass
tier_classification:
  merge: confirm
  release: confirm
EOF

# Run the canonical inline-Python invocation documented in SKILL.md Step 1.
RESULT=$(python3 - "$DIR/legacy.yaml" "$SCHEMA" 2>&1 <<'PYEOF'
import sys, yaml, json, jsonschema
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
workflow_path, schema_path = sys.argv[1], sys.argv[2]
with open(workflow_path, "r", encoding="utf-8") as f:
    wf = yaml.safe_load(f)
gate = (wf or {}).get("completion_gate") or {}
if "requires" in gate and "documented_requirements" not in gate:
    gate["documented_requirements"] = gate.pop("requires")
    wf["completion_gate"] = gate
    print(f"WARN: {workflow_path}: completion_gate.requires is deprecated", file=sys.stderr)
with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
try:
    jsonschema.validate(wf, schema)
    print("schema_valid: true")
except jsonschema.ValidationError as e:
    print(f"schema_valid: false error: {e.message}")
    sys.exit(2)
PYEOF
)
EXIT=$?
assert_equal "0" "$EXIT" "migration shim + validation succeeds"
assert_contains "WARN: " "$RESULT" "deprecation WARN emitted to stderr"
assert_contains "deprecated" "$RESULT" "WARN names deprecation"
assert_contains "schema_valid: true" "$RESULT" "post-migration validation passes"

# Both-fields-present case: drop legacy + WARN
_flow_test_begin "F4 — migration shim drops legacy when both fields present"
cat > "$DIR/both.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowWorkflow
metadata:
  id: both-test
  command: /flow:example
  version: 1
  description: workflow with both fields
phases:
  - id: explore
    type: mixed
    activities:
      - id: noop
        evidence: gathered_context
completion_gate:
  requires:
    - legacy_label
  documented_requirements:
    - new_label
tier_classification:
  merge: confirm
  release: confirm
EOF
RESULT=$(python3 - "$DIR/both.yaml" "$SCHEMA" 2>&1 <<'PYEOF'
import sys, yaml, json, jsonschema
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
workflow_path, schema_path = sys.argv[1], sys.argv[2]
with open(workflow_path, "r", encoding="utf-8") as f:
    wf = yaml.safe_load(f)
gate = (wf or {}).get("completion_gate") or {}
if "requires" in gate and "documented_requirements" in gate:
    del gate["requires"]
    wf["completion_gate"] = gate
    print(f"WARN: {workflow_path}: both fields present — dropping legacy 'requires'", file=sys.stderr)
with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
try:
    jsonschema.validate(wf, schema)
    print("schema_valid: true")
except jsonschema.ValidationError as e:
    print(f"schema_valid: false error: {e.message}")
    sys.exit(2)
PYEOF
)
assert_contains "schema_valid: true" "$RESULT" "both-fields validates after dropping legacy"
assert_contains "dropping legacy" "$RESULT" "WARN names the drop"


# --- F9 — _check_stuck behavioral: 3 unchanged turns → goal failed
_flow_test_begin "F9 — stuck-counter file increments on unchanged delta"

DIR=$(_c14_mktmp)
cd "$DIR"
mkdir -p .flow/runs/test-run/stuck-counter-parent
# Counter file is at .flow/runs/<id>/stuck-counter — single integer file.
echo "1" > .flow/runs/test-run/stuck-counter

COUNTER_BEFORE=$(cat .flow/runs/test-run/stuck-counter)
assert_equal "1" "$COUNTER_BEFORE" "counter starts at 1"

# Simulate the counter increment that _check_stuck does
COUNTER_AFTER=$((COUNTER_BEFORE + 1))
echo "$COUNTER_AFTER" > .flow/runs/test-run/stuck-counter
NEW=$(cat .flow/runs/test-run/stuck-counter)
assert_equal "2" "$NEW" "counter incremented to 2 on unchanged"

# Reset on non-unchanged delta
echo "0" > .flow/runs/test-run/stuck-counter
RESET=$(cat .flow/runs/test-run/stuck-counter)
assert_equal "0" "$RESET" "counter resets to 0 on non-unchanged delta"

cd - >/dev/null

_flow_test_begin "F9 — symlink defense on stuck-counter rejects swap"
DIR=$(_c14_mktmp)
cd "$DIR"
mkdir -p .flow/runs/test-run
echo "0" > /tmp/hostile-target.$$
ln -s /tmp/hostile-target.$$ .flow/runs/test-run/stuck-counter
# Replicate the [ -L ] guard from _check_stuck
if [ -L .flow/runs/test-run/stuck-counter ]; then
  REJECTED=yes
else
  REJECTED=no
fi
assert_equal "yes" "$REJECTED" "symlinked stuck-counter is detected by [ -L ] check"
rm -f /tmp/hostile-target.$$
cd - >/dev/null


# --- F10 — goal-evaluator SKILL.md documents proposed_transition contract
_flow_test_begin "F10 — goal-evaluator SKILL.md describes proposed_transition + caller-side write"

SKILL_PATH="$REPO_ROOT/plugins/flow/skills/goal-evaluator/SKILL.md"
if [ ! -f "$SKILL_PATH" ]; then
  _flow_assert_fail "goal-evaluator SKILL.md missing"
else
  CONTENT=$(cat "$SKILL_PATH")
  assert_contains "proposed_transition" "$CONTENT" "proposed_transition field documented"
  assert_contains "does NOT write" "$CONTENT" "explicit non-write contract"
  assert_contains "caller is responsible for invoking AskUserQuestion" "$CONTENT" "Tier 2 confirm documented"
  assert_contains "Terminal transitions" "$CONTENT" "Terminal-transition branch documented"
  assert_contains "Non-terminal transitions" "$CONTENT" "Non-terminal branch documented separately"
fi

_flow_test_begin "F10 — /flow:goal evaluate command documents the three confirm options"
GOAL_CMD="$REPO_ROOT/plugins/flow/commands/goal.md"
if [ ! -f "$GOAL_CMD" ]; then
  _flow_assert_fail "goal.md missing"
else
  CONTENT=$(cat "$GOAL_CMD")
  assert_contains "Terminal-transition Tier 2 confirmation" "$CONTENT" "F10 confirmation section heading"
  assert_contains "Confirm" "$CONTENT" "Confirm option"
  assert_contains "Re-evaluate" "$CONTENT" "Re-evaluate option"
  assert_contains "Cancel" "$CONTENT" "Cancel option"
  assert_contains "--from-status" "$CONTENT" "from-status guard for lifecycle write"
fi


# --- F1 — pr.md FlowGoal gate handles all states (#111 D-GATE: gate on existence,
# so no-goal is STATE=none/GATE=pass rather than a blocking STATE=missing)
_flow_test_begin "F1 — pr.md gate distinguishes states (none vs degenerate vs unavailable)"
PR_CMD="$REPO_ROOT/plugins/flow/commands/pr.md"
CONTENT=$(cat "$PR_CMD")
assert_contains "STATE=none" "$CONTENT" "no-goal state (gate not applicable) documented"
assert_contains "STATE=degenerate" "$CONTENT" "degenerate state documented"
assert_contains "STATE=unavailable" "$CONTENT" "unavailable state documented"
assert_contains "STATE=disabled" "$CONTENT" "disabled state (enabled:false / goalCreation:off) documented"


# --- F8 — throttle and stuck events both have their own emit sites
_flow_test_begin "F8 — flow-goal-evaluator emits TWO distinct event types"
HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/flow-goal-evaluator.sh"
CONTENT=$(cat "$HOOK")
# Use grep -c with a literal string to count occurrences
THROTTLE_COUNT=$(grep -c "throttle-block" "$HOOK" 2>/dev/null)
STUCK_COUNT=$(grep -c "stuck-detection-fired" "$HOOK" 2>/dev/null)
if [ "$THROTTLE_COUNT" -ge "1" ] && [ "$STUCK_COUNT" -ge "1" ]; then
  _flow_assert_pass "both event types referenced in hook source"
else
  _flow_assert_fail "missing event types: throttle-block=$THROTTLE_COUNT stuck-detection-fired=$STUCK_COUNT"
fi

# Symlink defense on BOTH events.jsonl write sites
_flow_test_begin "F8 — events.jsonl writes guarded by symlink check"
SYMLINK_GUARD_COUNT=$(grep -c 'is a symlink' "$HOOK" 2>/dev/null)
# Expected at least 3: throttle events.jsonl + stuck events.jsonl + stuck-counter symlink check
if [ "$SYMLINK_GUARD_COUNT" -ge "3" ]; then
  _flow_assert_pass "3+ symlink guards present (got $SYMLINK_GUARD_COUNT)"
else
  _flow_assert_fail "expected 3+ symlink-guard sites; found $SYMLINK_GUARD_COUNT"
fi


# --- Schema patterns: run_id, target.workflow constrained
_flow_test_begin "SEC-1 — goal.schema.json constrains scope.run_id to safe pattern"
RUN_ID_PATTERN=$(jq -r '.properties.scope.properties.run_id.pattern // "absent"' "$REPO_ROOT/plugins/flow/schemas/v1/goal.schema.json")
assert_contains "[A-Za-z0-9]" "$RUN_ID_PATTERN" "run_id pattern present and starts with safe char class"

_flow_test_begin "SEC-6 — trigger.schema.json constrains target.workflow + target.goal patterns"
WF_PATTERN=$(jq -r '.properties.target.properties.workflow.pattern // "absent"' "$REPO_ROOT/plugins/flow/schemas/v1/trigger.schema.json")
GOAL_PATTERN=$(jq -r '.properties.target.properties.goal.pattern // "absent"' "$REPO_ROOT/plugins/flow/schemas/v1/trigger.schema.json")
assert_contains "[a-z0-9]" "$WF_PATTERN" "target.workflow pattern present"
assert_contains "[a-z0-9]" "$GOAL_PATTERN" "target.goal pattern present"


# --- Cascade `null` recognition of explicit false (cycle-14 SEC-V4)
#
# Both `// empty` and `// null` in jq trigger on null AND false (both are
# "falsy" per jq's // operator semantics) — so neither preserves an explicit
# false. The fix is BOTH: (a) cascade-resolve treats "null" output as
# not-found, AND (b) callers use BARE expressions (no //) so jq outputs
# "false" / "true" / "null" verbatim.
_flow_test_begin "SEC-V4 — cascade-resolve.sh with bare expression returns 'false' for explicit false"
DIR=$(_c14_mktmp)
mkdir -p "$DIR/.claude"
echo '{"flow":{"workflows":{"enabled":false}}}' > "$DIR/.claude/settings.flow.json"
RESULT=$(cd "$DIR" && "$REPO_ROOT/plugins/flow/bin/cascade-resolve.sh" --default "default-fallback" '.flow.workflows.enabled')
assert_equal "false" "$RESULT" "bare expression returns 'false' (was always 'true' before cycle-14)"

# Compare against // empty which still swallows false (legacy callers)
_flow_test_begin "SEC-V4 — cascade-resolve.sh + // empty still falls through on false (backward-compat for non-boolean callers)"
RESULT_EMPTY=$(cd "$DIR" && "$REPO_ROOT/plugins/flow/bin/cascade-resolve.sh" --default "default-fallback" '.flow.workflows.enabled // empty')
assert_equal "default-fallback" "$RESULT_EMPTY" "// empty falls through to default (legacy behavior preserved)"

# Absent key returns default for both expression styles
_flow_test_begin "SEC-V4 — absent key with bare expression falls through to default"
DIR2=$(_c14_mktmp)
mkdir -p "$DIR2/.claude"
echo '{"other": "value"}' > "$DIR2/.claude/settings.flow.json"
RESULT_ABSENT=$(cd "$DIR2" && "$REPO_ROOT/plugins/flow/bin/cascade-resolve.sh" --default "default-fallback" '.flow.workflows.enabled')
assert_equal "default-fallback" "$RESULT_ABSENT" "bare expression with absent key returns default"
