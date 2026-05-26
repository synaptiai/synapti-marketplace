# Tests that completion_gate.requires was renamed to documented_requirements.
#
# Contract:
#   - Schema accepts the new name (documented_requirements)
#   - Schema REJECTS the old name (requires) because additionalProperties:false
#   - All 7 shipped workflow YAMLs use the new name
#   - workflow-validation skill is documented to accept both during v3.0.x

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml, jsonschema" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML+jsonschema prerequisite"
  _flow_assert_pass "SKIP: PyYAML or jsonschema not installed"
  return 0
fi

SCHEMA="$REPO_ROOT/plugins/flow/schemas/v1/workflow.schema.json"

# --- Test 1: shipped workflows use the new field name
_flow_test_begin "all 7 plugin workflows use completion_gate.documented_requirements"
FOUND_OLD=""
FOUND_NEW=0
for wf in "$REPO_ROOT"/plugins/flow/workflows/*.workflow.yaml; do
  if grep -q "^  requires:" "$wf"; then
    FOUND_OLD="${FOUND_OLD}$(basename "$wf"),"
  fi
  if grep -q "^  documented_requirements:" "$wf"; then
    FOUND_NEW=$((FOUND_NEW + 1))
  fi
done
FOUND_OLD="${FOUND_OLD%,}"
assert_equal "" "$FOUND_OLD" "no workflow still uses the old 'requires' field"
assert_equal "7" "$FOUND_NEW" "all 7 plugin workflows have documented_requirements"

# --- Test 2: schema validates the new shape
_flow_test_begin "schema validates documented_requirements"
TMP=$(mktemp -d -t flow-rename-test.XXXXXX)
cat > "$TMP/valid.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowWorkflow
metadata:
  id: rename-test
  command: /flow:example
  version: 1
  description: Schema validates new completion_gate.documented_requirements
phases:
  - id: explore
    type: mixed
    activities:
      - id: noop
        evidence: gathered_context
completion_gate:
  documented_requirements:
    - all_checks_pass
tier_classification:
  merge: confirm
  release: confirm
EOF
OUT=$(python3 -c "
import yaml, json, jsonschema, sys
with open('$SCHEMA') as f: s = json.load(f)
with open('$TMP/valid.yaml') as f: d = yaml.safe_load(f)
try:
    jsonschema.validate(d, s)
    print('ok')
except jsonschema.ValidationError as e:
    print('fail:', e.message)
" 2>&1)
assert_equal "ok" "$OUT" "schema accepts documented_requirements"

# --- Test 3: schema REJECTS the legacy field name (additionalProperties:false)
_flow_test_begin "schema rejects legacy 'requires' field"
cat > "$TMP/legacy.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowWorkflow
metadata:
  id: rename-test
  command: /flow:example
  version: 1
  description: Schema should reject the legacy requires field
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
OUT=$(python3 -c "
import yaml, json, jsonschema, sys
with open('$SCHEMA') as f: s = json.load(f)
with open('$TMP/legacy.yaml') as f: d = yaml.safe_load(f)
try:
    jsonschema.validate(d, s)
    print('ok')
except jsonschema.ValidationError as e:
    print('rejected')
" 2>&1)
assert_equal "rejected" "$OUT" "schema rejects 'requires' (legacy name relies on migration shim in workflow-validation skill, not on schema acceptance)"

rm -rf "$TMP"
