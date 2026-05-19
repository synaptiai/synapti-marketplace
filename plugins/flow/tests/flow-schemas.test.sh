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
