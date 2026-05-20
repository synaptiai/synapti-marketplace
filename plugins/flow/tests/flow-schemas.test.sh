# Tests for plugins/flow/schemas/v1/*.schema.json
#
# Contract:
#   - Every schema in schemas/v1/ has at least one positive fixture (validates).
#   - Every schema has at least one negative fixture (fails validation).
#   - Schemas use JSON Schema draft 2020-12 and are well-formed JSON.
#
# Prerequisites: python3 + PyYAML + jsonschema. SKIPS gracefully if any missing
# (CI provides them; a developer on a stripped system sees the skip rather
# than a cryptic failure).

# Skip the whole suite gracefully if Python dependencies are unavailable.
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
  _flow_assert_pass "SKIP: jsonschema not installed (pip install jsonschema)"
  return 0
fi

SCHEMA_DIR="$REPO_ROOT/plugins/flow/schemas/v1"
FIXTURE_DIR="$REPO_ROOT/plugins/flow/tests/fixtures"

# Helper: validate a YAML fixture against a schema. Echoes "ok" on success,
# "fail" on validation failure. Use the standalone `jsonschema` library via
# its Python API (the CLI's behavior across versions is inconsistent — some
# print "ok" on success, some are silent, and the exit codes are not stable
# across major versions).
_validate_fixture() {
  local schema_path="$1" fixture_path="$2"
  python3 - "$schema_path" "$fixture_path" <<'PYEOF' 2>&1
import sys
# Hostile-fork defense (matches journal-record.sh discipline).
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import json
import yaml
import jsonschema

schema_path, fixture_path = sys.argv[1:3]
with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
with open(fixture_path, "r", encoding="utf-8") as f:
    instance = yaml.safe_load(f)

try:
    jsonschema.validate(instance=instance, schema=schema)
    print("ok")
except jsonschema.ValidationError as e:
    # Print the first line of the validation error so the test can match
    # specific failure modes (missing-required vs invalid-enum etc.).
    print(f"fail: {str(e).splitlines()[0]}")
PYEOF
}

# --- Test 1: every schema is well-formed JSON
_flow_test_begin "all schemas are well-formed JSON"
for schema in "$SCHEMA_DIR"/*.schema.json; do
  ERR=$(jq . "$schema" 2>&1 >/dev/null)
  EXIT=$?
  assert_exit 0 "$EXIT" "$(basename "$schema") parses as JSON"
done

# --- Test 2: every schema is a valid JSON Schema document
_flow_test_begin "all schemas are valid JSON Schema documents"
for schema in "$SCHEMA_DIR"/*.schema.json; do
  RESULT=$(python3 - "$schema" <<'PYEOF' 2>&1
import sys, json, jsonschema
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
with open(sys.argv[1], "r", encoding="utf-8") as f:
    schema = json.load(f)
try:
    jsonschema.Draft202012Validator.check_schema(schema)
    print("ok")
except jsonschema.SchemaError as e:
    print(f"schema-invalid: {e}")
PYEOF
)
  assert_equal "ok" "$RESULT" "$(basename "$schema") passes Draft202012Validator.check_schema"
done

# --- Test 3: FlowGoal positive fixture validates
_flow_test_begin "goal/valid.yaml validates against goal.schema.json"
RESULT=$(_validate_fixture "$SCHEMA_DIR/goal.schema.json" "$FIXTURE_DIR/goal/valid.yaml")
assert_equal "ok" "$RESULT" "goal/valid.yaml validates"

# --- Test 4: FlowGoal negative fixtures fail validation
_flow_test_begin "goal/missing-required.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/goal.schema.json" "$FIXTURE_DIR/goal/missing-required.yaml")
assert_contains "fail" "$RESULT" "missing required fields rejected"

_flow_test_begin "goal/invalid-status.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/goal.schema.json" "$FIXTURE_DIR/goal/invalid-status.yaml")
assert_contains "fail" "$RESULT" "invalid status enum rejected"

_flow_test_begin "goal/invalid-apiversion.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/goal.schema.json" "$FIXTURE_DIR/goal/invalid-apiversion.yaml")
assert_contains "fail" "$RESULT" "non-v1 apiVersion rejected"

# --- Test 5: FlowRun positive fixture validates
_flow_test_begin "run/valid.yaml validates against run.schema.json"
RESULT=$(_validate_fixture "$SCHEMA_DIR/run.schema.json" "$FIXTURE_DIR/run/valid.yaml")
assert_equal "ok" "$RESULT" "run/valid.yaml validates"

# --- Test 6: FlowRun negative fixture fails
_flow_test_begin "run/missing-required.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/run.schema.json" "$FIXTURE_DIR/run/missing-required.yaml")
assert_contains "fail" "$RESULT" "missing state rejected"

# --- Test 7: FlowActivity positive
_flow_test_begin "activity/valid.yaml validates against activity.schema.json"
RESULT=$(_validate_fixture "$SCHEMA_DIR/activity.schema.json" "$FIXTURE_DIR/activity/valid.yaml")
assert_equal "ok" "$RESULT" "activity/valid.yaml validates"

# --- Test 8: FlowActivity negative
_flow_test_begin "activity/missing-required.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/activity.schema.json" "$FIXTURE_DIR/activity/missing-required.yaml")
assert_contains "fail" "$RESULT" "missing activity block rejected"

# --- Test 9: FlowEvidence positive
_flow_test_begin "evidence/valid.yaml validates against evidence.schema.json"
RESULT=$(_validate_fixture "$SCHEMA_DIR/evidence.schema.json" "$FIXTURE_DIR/evidence/valid.yaml")
assert_equal "ok" "$RESULT" "evidence/valid.yaml validates"

# --- Test 10: FlowEvidence negative
_flow_test_begin "evidence/missing-required.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/evidence.schema.json" "$FIXTURE_DIR/evidence/missing-required.yaml")
assert_contains "fail" "$RESULT" "missing evidence block rejected"

# --- Test 11: FlowWorkflow positive
_flow_test_begin "workflow/valid.yaml validates against workflow.schema.json"
RESULT=$(_validate_fixture "$SCHEMA_DIR/workflow.schema.json" "$FIXTURE_DIR/workflow/valid.yaml")
assert_equal "ok" "$RESULT" "workflow/valid.yaml validates"

# --- Test 12: FlowWorkflow negative
_flow_test_begin "workflow/missing-required.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/workflow.schema.json" "$FIXTURE_DIR/workflow/missing-required.yaml")
assert_contains "fail" "$RESULT" "missing workflow required fields rejected"

# --- Test 13: FlowTrigger positive
_flow_test_begin "trigger/valid.yaml validates against trigger.schema.json"
RESULT=$(_validate_fixture "$SCHEMA_DIR/trigger.schema.json" "$FIXTURE_DIR/trigger/valid.yaml")
assert_equal "ok" "$RESULT" "trigger/valid.yaml validates"

# --- Test 14: FlowTrigger negative — missing required fields
_flow_test_begin "trigger/missing-required.yaml is rejected"
RESULT=$(_validate_fixture "$SCHEMA_DIR/trigger.schema.json" "$FIXTURE_DIR/trigger/missing-required.yaml")
assert_contains "fail" "$RESULT" "missing trigger required fields rejected"

# --- Test 15: FlowTrigger negative — empty forbidden_actions (Tier-3 deny missing)
# Schema-enforced (not just documented): forbidden_actions MUST contain
# 'merge' and 'release'. Empty array fails schema validation deterministically.
_flow_test_begin "trigger/missing-tier3-deny.yaml is rejected (Tier-3 schema enforcement)"
RESULT=$(_validate_fixture "$SCHEMA_DIR/trigger.schema.json" "$FIXTURE_DIR/trigger/missing-tier3-deny.yaml")
assert_contains "fail" "$RESULT" "forbidden_actions without merge+release rejected"

# --- Test 16: every plugin-shipped workflow validates against the schema
_flow_test_begin "all plugin workflows validate against workflow.schema.json"
WORKFLOW_FAILURES=0
for wf in "$REPO_ROOT"/plugins/flow/workflows/*.workflow.yaml; do
  RESULT=$(_validate_fixture "$SCHEMA_DIR/workflow.schema.json" "$wf")
  if [ "$RESULT" != "ok" ]; then
    WORKFLOW_FAILURES=$((WORKFLOW_FAILURES + 1))
    echo "  -> $(basename "$wf"): $RESULT" >&2
  fi
done
assert_equal "0" "$WORKFLOW_FAILURES" "all 7 plugin workflows validate"

# --- Test 17: every plugin-shipped trigger template validates against the schema
# Templates use ${VAR} placeholders; we substitute trivial values so YAML
# parses correctly, then validate.
_flow_test_begin "all plugin trigger templates validate against trigger.schema.json"
TRIGGER_FAILURES=0
for tt in "$REPO_ROOT"/plugins/flow/triggers/templates/*.trigger.yaml; do
  TMP=$(mktemp -t trigger-fixture.XXXXXX.yaml)
  # Substitute placeholders with regex-conformant values. Branch and repo
  # must avoid '/' because the trigger metadata.id pattern only permits
  # [a-z0-9-] (the slug is built from these).
  sed -e 's/\${PR}/42/g' \
      -e 's|\${BRANCH}|feature-example|g' \
      -e 's|\${REPO}|example-example|g' \
      -e "s|\\\${NOW}|2026-05-20T14:30:00Z|g" \
      -e 's/\${ISSUE}/100/g' \
      "$tt" > "$TMP"
  RESULT=$(_validate_fixture "$SCHEMA_DIR/trigger.schema.json" "$TMP")
  rm -f "$TMP"
  if [ "$RESULT" != "ok" ]; then
    TRIGGER_FAILURES=$((TRIGGER_FAILURES + 1))
    echo "  -> $(basename "$tt"): $RESULT" >&2
  fi
done
assert_equal "0" "$TRIGGER_FAILURES" "all 3 plugin trigger templates validate after \${VAR} substitution"
