#!/usr/bin/env bash
# Validate the canonical finding-row schema against fixtures from each
# reviewer agent's expected output. Catches schema drift between
# references/finding-schema.md and the actual rows agents produce.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$DIR/row-schema.json"
FIXTURES="$DIR/fixtures.json"

if [ ! -f "$SCHEMA" ] || [ ! -f "$FIXTURES" ]; then
  echo "FATAL: schema or fixtures missing" >&2
  exit 2
fi

PASS=0
FAIL=0

# We bypass bin/validate-skill-input.sh here because that script discovers
# schemas under tests/skills/<name>/; the finding-schema is repo-level, not
# skill-scoped. The validation logic is the same: jsonschema if available,
# shape-check fallback otherwise.
validate_row() {
  python3 - "$SCHEMA" "$1" <<'PYTHON'
import json
import re
import sys

schema_path = sys.argv[1]
row_str = sys.argv[2]

try:
    row = json.loads(row_str)
except json.JSONDecodeError as e:
    print(f"row is not valid JSON: {e}", file=sys.stderr)
    sys.exit(2)

with open(schema_path) as f:
    schema = json.load(f)

try:
    import jsonschema
    try:
        jsonschema.validate(row, schema)
    except jsonschema.ValidationError as e:
        print(f"validation failed: {e.message}", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
except ImportError:
    pass

# Shape-check fallback (same subset bin/validate-skill-input.sh enforces).
def validate(data, schema, path="$"):
    t = schema.get("type")
    if t == "object":
        if not isinstance(data, dict):
            raise ValueError(f"{path}: expected object, got {type(data).__name__}")
        for req in schema.get("required", []):
            if req not in data:
                raise ValueError(f"{path}: missing required field '{req}'")
        for key, sub in schema.get("properties", {}).items():
            if key in data:
                validate(data[key], sub, f"{path}.{key}")
    elif t == "string":
        if not isinstance(data, str):
            raise ValueError(f"{path}: expected string, got {type(data).__name__}")
        if "minLength" in schema and len(data) < schema["minLength"]:
            raise ValueError(f"{path}: minLength={schema['minLength']}")
        if "enum" in schema and data not in schema["enum"]:
            raise ValueError(f"{path}: '{data}' not in enum {schema['enum']}")
        if "pattern" in schema and not re.search(schema["pattern"], data):
            raise ValueError(f"{path}: '{data}' does not match pattern '{schema['pattern']}'")
    elif t == "array":
        if not isinstance(data, list):
            raise ValueError(f"{path}: expected array, got {type(data).__name__}")

try:
    validate(row, schema)
except ValueError as e:
    print(f"validation failed: {e}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYTHON
}

# Iterate VALID fixtures — every one MUST validate.
echo "=== Valid fixtures (all must validate) ==="
COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['valid']))" "$FIXTURES")
for i in $(seq 0 $((COUNT - 1))); do
  ROW=$(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['valid'][int(sys.argv[2])]))" "$FIXTURES" "$i")
  ID=$(echo "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  if validate_row "$ROW" >/dev/null 2>&1; then
    echo "PASS: valid fixture #$i (id=$ID) validates"
    PASS=$((PASS + 1))
  else
    REASON=$(validate_row "$ROW" 2>&1 >/dev/null)
    echo "FAIL: valid fixture #$i (id=$ID) should validate but did not: $REASON"
    FAIL=$((FAIL + 1))
  fi
done

# Iterate INVALID fixtures — every one MUST fail validation.
echo ""
echo "=== Invalid fixtures (all must fail) ==="
COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['invalid']))" "$FIXTURES")
for i in $(seq 0 $((COUNT - 1))); do
  ROW=$(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['invalid'][int(sys.argv[2])]))" "$FIXTURES" "$i")
  WHY=$(echo "$ROW" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('_why','(no reason)'))")
  # Strip the _why field before validating (it's metadata, not part of the schema)
  CLEAN_ROW=$(echo "$ROW" | python3 -c "import json,sys; d=json.load(sys.stdin); d.pop('_why',None); print(json.dumps(d))")
  if validate_row "$CLEAN_ROW" >/dev/null 2>&1; then
    echo "FAIL: invalid fixture #$i should have failed but validated. Reason was: $WHY"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: invalid fixture #$i correctly rejected — $WHY"
    PASS=$((PASS + 1))
  fi
done

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
