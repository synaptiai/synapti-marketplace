#!/usr/bin/env bash
# [flow] Validate a skill's input payload against its JSON Schema.
#
# Usage:
#   validate-skill-input.sh <skill-name> '<json-input>'
#
# Looks up the schema at `${CLAUDE_PLUGIN_ROOT}/schemas/<skill-name>/input-schema.json`
# (with `${CLAUDE_PLUGIN_ROOT}` defaulting to `plugins/flow` for in-repo callers).
# Schemas ship inside the plugin payload so they are available at runtime to
# end-users who install the marketplace plugin via Claude Code — the previous
# `tests/skills/...` location was repo-only and not part of the install set.
#
# Exits:
#   0 — input validates against the schema
#   1 — input fails validation (rationale on stderr)
#   2 — schema not found, input is not valid JSON, or other infrastructure error
#
# Validation strategy: tries `import jsonschema` first for full Draft-07
# validation; if the package is not installed, falls back to a shape-check
# implemented in the standard `json` module (validates required fields, types,
# enums, patterns, minItems, minLength). The fallback covers the cases the
# flow plugin's contracts actually use; full jsonschema is recommended for
# stricter validation in CI but is not required.

set -euo pipefail

if [ $# -lt 2 ]; then
  cat <<'USAGE' >&2
Usage: validate-skill-input.sh <skill-name> '<json-input>'

Validates the JSON payload against ${CLAUDE_PLUGIN_ROOT}/schemas/<skill-name>/input-schema.json.
USAGE
  exit 2
fi

SKILL="$1"
INPUT="$2"

# Resolve the schema from inside the plugin payload (so it ships to end-users),
# then fall back to the repo-root layout for in-repo callers that pre-date the
# move (and to keep a single resolution surface across script versions).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  PLUGIN_ROOT="$REPO_ROOT/plugins/flow"
fi
SCHEMA="$PLUGIN_ROOT/schemas/$SKILL/input-schema.json"

if [ ! -f "$SCHEMA" ]; then
  echo "validate-skill-input.sh: schema not found at $SCHEMA" >&2
  exit 2
fi

python3 - "$SCHEMA" "$INPUT" <<'PYTHON'
import json
import sys

schema_path = sys.argv[1]
input_str = sys.argv[2]

try:
    input_data = json.loads(input_str)
except json.JSONDecodeError as e:
    print(f"validate-skill-input.sh: input is not valid JSON: {e}", file=sys.stderr)
    sys.exit(2)

with open(schema_path) as f:
    schema = json.load(f)

# Prefer full jsonschema validation when the package is installed.
try:
    import jsonschema  # type: ignore[import-not-found]
    try:
        jsonschema.validate(input_data, schema)
    except jsonschema.ValidationError as e:
        # `e.message` is the leaf reason; `list(e.absolute_path)` is the JSON
        # pointer to the offending field. Surface both for actionable feedback.
        path = "$"
        for component in e.absolute_path:
            path += f"[{component!r}]" if not isinstance(component, str) else f".{component}"
        print(f"validate-skill-input.sh: validation failed at {path}: {e.message}", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
except ImportError:
    pass

# Shape-check fallback (no third-party deps). Validates the subset of
# JSON Schema Draft-07 that flow's contracts use:
#   - type (object, array, string, integer, boolean)
#   - required (object only)
#   - properties (object only)
#   - items (array only)
#   - minItems (array only)
#   - minLength (string only)
#   - enum
#   - pattern (string only)

def validate(data, schema, path="$"):
    t = schema.get("type")
    if isinstance(t, list):
        # type can be a list of allowed types
        if not any(_type_matches(data, single) for single in t):
            raise ValueError(f"{path}: expected one of {t}, got {_typename(data)}")
        return  # pick the first matching subtype's constraints later if needed

    if t == "object":
        if not isinstance(data, dict):
            raise ValueError(f"{path}: expected object, got {_typename(data)}")
        for req in schema.get("required", []):
            if req not in data:
                raise ValueError(f"{path}: missing required field '{req}'")
        for key, subschema in schema.get("properties", {}).items():
            if key in data:
                validate(data[key], subschema, f"{path}.{key}")

    elif t == "array":
        if not isinstance(data, list):
            raise ValueError(f"{path}: expected array, got {_typename(data)}")
        if "minItems" in schema and len(data) < schema["minItems"]:
            raise ValueError(f"{path}: minItems={schema['minItems']}, got {len(data)}")
        if "items" in schema:
            for i, item in enumerate(data):
                validate(item, schema["items"], f"{path}[{i}]")

    elif t == "string":
        if not isinstance(data, str):
            raise ValueError(f"{path}: expected string, got {_typename(data)}")
        if "minLength" in schema and len(data) < schema["minLength"]:
            raise ValueError(f"{path}: minLength={schema['minLength']}, got {len(data)}")
        if "enum" in schema and data not in schema["enum"]:
            raise ValueError(f"{path}: '{data}' not in enum {schema['enum']}")
        if "pattern" in schema:
            import re
            if not re.search(schema["pattern"], data):
                raise ValueError(f"{path}: '{data}' does not match pattern '{schema['pattern']}'")

    elif t == "integer":
        if not isinstance(data, int) or isinstance(data, bool):
            raise ValueError(f"{path}: expected integer, got {_typename(data)}")

    elif t == "boolean":
        if not isinstance(data, bool):
            raise ValueError(f"{path}: expected boolean, got {_typename(data)}")

    elif t is None:
        # No type assertion; just check enum if present
        if "enum" in schema and data not in schema["enum"]:
            raise ValueError(f"{path}: '{data}' not in enum {schema['enum']}")


def _type_matches(data, t):
    return (
        (t == "object"  and isinstance(data, dict)) or
        (t == "array"   and isinstance(data, list)) or
        (t == "string"  and isinstance(data, str)) or
        (t == "integer" and isinstance(data, int) and not isinstance(data, bool)) or
        (t == "boolean" and isinstance(data, bool)) or
        (t == "number"  and isinstance(data, (int, float)) and not isinstance(data, bool)) or
        (t == "null"    and data is None)
    )


def _typename(data):
    if data is None:
        return "null"
    if isinstance(data, bool):
        return "boolean"
    if isinstance(data, int):
        return "integer"
    if isinstance(data, float):
        return "number"
    if isinstance(data, str):
        return "string"
    if isinstance(data, list):
        return "array"
    if isinstance(data, dict):
        return "object"
    return type(data).__name__


try:
    validate(input_data, schema)
except ValueError as e:
    print(f"validate-skill-input.sh: validation failed: {e}", file=sys.stderr)
    sys.exit(1)

# Surface the fact that we used the fallback so CI doesn't silently skip
# stricter checks (oneOf, allOf, format, etc.) the schema may declare.
print("validate-skill-input.sh: NOTE — jsonschema package not installed; used shape-check fallback "
      "(required/types/enums/patterns/minItems/minLength). Install `jsonschema` for full Draft-07 validation.",
      file=sys.stderr)
sys.exit(0)
PYTHON
