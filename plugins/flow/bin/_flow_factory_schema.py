"""A standard-library JSON Schema validator for the factory's own records.

The factory engine checks job.json, directives, leases, results, stored
events and shell report lines against schemas/v1/factory-job.schema.json and
schemas/v1/factory-directive.schema.json. jsonschema is an optional
dependency, so the engine cannot rely on it; this module implements the part
of Draft 2020-12 those two schemas use, and the test
tests/e2e-factory-engine-schema.test.sh checks that it gives jsonschema's
verdict on every fixture and on each keyword's edge values.

Supported keywords: type (one name or a list), required, properties,
additionalProperties (false or a schema), enum, const, minimum, maximum,
minLength, pattern, items, $ref (to #/$defs/<name> in the same file), oneOf
and anyOf. $schema, $id, $defs, title, description and $comment are
annotations. A schema that uses any other keyword, anywhere in the file, is
refused when it is loaded with SchemaUnsupported(<keyword>), so a keyword
this module would ignore can never be ignored silently.

API:
  load(schema_path) -> dict            reads and checks the schema
  validate(instance, schema_path, def_name=None) -> list of str
      def_name validates against #/$defs/<def_name> instead of the top level.
      Each error is "<json path>: <message>". The path is the dotted keys and
      [index] parts from the top, "$" for the top itself; a missing required
      field and a key additionalProperties refuses are reported at the field's
      own path (a job without state gives "state: is required"). Errors come
      in a fixed order: the errors of a $ref the node holds, then the node's
      type (nothing else is checked at a node of the wrong type), then const,
      enum and the number and string keywords, then required in the schema's
      order, keys that are not allowed in sorted order, each property in the
      schema's order, array items in order, and last anyOf and oneOf.
"""

# The guard below must stay verbatim (tests/syspath-guard.test.sh matches it)
# and must run before the other imports, so ruff's rules on one import per
# line and imports at the top do not apply to this file.
# ruff: noqa: E401, E402
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import json
import re

ANNOTATIONS = frozenset(["$schema", "$id", "$defs", "title", "description", "$comment"])
KEYWORDS = frozenset(["type", "required", "properties", "additionalProperties", "enum", "const", "minimum",
                      "maximum", "minLength", "pattern", "items", "$ref", "oneOf", "anyOf"])
TYPES = frozenset(["object", "array", "string", "integer", "number", "boolean", "null"])
REF_PREFIX = "#/$defs/"


class SchemaUnsupported(Exception):
    """The schema uses something this validator does not implement. The
    message is the keyword (or, for a $ref or type it cannot follow, the
    keyword and the value)."""

    def __init__(self, keyword):
        Exception.__init__(self, keyword)
        self.keyword = keyword


def _check(node, defs):
    """Refuse every keyword outside the subset, in the whole schema: $defs
    entries nothing references and branches no instance reaches included.
    Property names and enum or const values are data, not keywords."""
    if isinstance(node, bool):
        return
    if not isinstance(node, dict):
        raise SchemaUnsupported("schema that is not an object or a boolean")
    for key, value in node.items():
        if key in ANNOTATIONS:
            continue
        if key not in KEYWORDS:
            raise SchemaUnsupported(key)
        if key == "type":
            names = value if isinstance(value, list) else [value]
            for name in names:
                if name not in TYPES:
                    raise SchemaUnsupported("type %s" % json.dumps(name))
        elif key == "$ref":
            if not (isinstance(value, str) and value.startswith(REF_PREFIX) and value[len(REF_PREFIX):] in defs):
                raise SchemaUnsupported("$ref %s" % json.dumps(value))
        elif key == "pattern":
            try:
                re.compile(value)
            except (re.error, TypeError):
                raise SchemaUnsupported("pattern %s" % json.dumps(value))
        elif key == "properties":
            for sub in value.values():
                _check(sub, defs)
        elif key in ("additionalProperties", "items"):
            _check(value, defs)
        elif key in ("oneOf", "anyOf"):
            if not isinstance(value, list) or not value:
                raise SchemaUnsupported(key)
            for sub in value:
                _check(sub, defs)
    for sub in node.get("$defs", {}).values():
        _check(sub, defs)


def load(schema_path):
    """Read a schema file and refuse it when it uses anything outside the
    subset. Raises OSError or ValueError when the file cannot be read as
    JSON, and SchemaUnsupported as above."""
    with open(schema_path, encoding="utf-8") as f:
        schema = json.load(f)
    defs = schema.get("$defs", {}) if isinstance(schema, dict) else {}
    _check(schema, defs)
    return schema


def _is_type(value, name):
    # JSON booleans are never numbers, and a number with no fractional part
    # is an integer (Draft 2020-12, as jsonschema decides it).
    if name == "null":
        return value is None
    if name == "boolean":
        return isinstance(value, bool)
    if name == "string":
        return isinstance(value, str)
    if name == "object":
        return isinstance(value, dict)
    if name == "array":
        return isinstance(value, list)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    if name == "number":
        return True
    return isinstance(value, int) or value.is_integer()


def _type_name(value):
    for name in ("null", "boolean", "integer", "number", "string", "array", "object"):
        if _is_type(value, name):
            return name
    return type(value).__name__


def _equal(a, b):
    # JSON equality: true is not 1, 1.0 is 1, and containers compare deeply.
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_equal(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


def _path(parts):
    out = ""
    for part in parts:
        if isinstance(part, int):
            out += "[%d]" % part
        else:
            out = part if not out else out + "." + part
    return out or "$"


def _is_number(value):
    return _is_type(value, "number")


def _validate(value, node, defs, parts, errors):
    if node is True:
        return
    if node is False:
        errors.append("%s: is not allowed" % _path(parts))
        return
    if "$ref" in node:
        _validate(value, defs[node["$ref"][len(REF_PREFIX):]], defs, parts, errors)
    if "type" in node:
        names = node["type"] if isinstance(node["type"], list) else [node["type"]]
        if not any(_is_type(value, n) for n in names):
            errors.append("%s: expected %s, got %s" % (_path(parts), " or ".join(names), _type_name(value)))
            return
    where = _path(parts)
    if "const" in node and not _equal(value, node["const"]):
        errors.append("%s: must be %s" % (where, json.dumps(node["const"])))
    if "enum" in node and not any(_equal(value, v) for v in node["enum"]):
        errors.append("%s: %s is not one of the allowed values" % (where, json.dumps(value)))
    if _is_number(value):
        if "minimum" in node and value < node["minimum"]:
            errors.append("%s: %s is less than %s" % (where, json.dumps(value), json.dumps(node["minimum"])))
        if "maximum" in node and value > node["maximum"]:
            errors.append("%s: %s is more than %s" % (where, json.dumps(value), json.dumps(node["maximum"])))
    if isinstance(value, str):
        if "minLength" in node and len(value) < node["minLength"]:
            errors.append("%s: is shorter than %d characters" % (where, node["minLength"]))
        if "pattern" in node and re.search(node["pattern"], value) is None:
            errors.append("%s: does not match %s" % (where, node["pattern"]))
    if isinstance(value, dict):
        props = node.get("properties", {})
        for key in node.get("required", []):
            if key not in value:
                errors.append("%s: is required" % _path(parts + [key]))
        extra = node.get("additionalProperties", True)
        for key in sorted(k for k in value if k not in props):
            _validate(value[key], extra, defs, parts + [key], errors)
        for key, sub in props.items():
            if key in value:
                _validate(value[key], sub, defs, parts + [key], errors)
    if isinstance(value, list) and "items" in node:
        for i, item in enumerate(value):
            _validate(item, node["items"], defs, parts + [i], errors)
    if "anyOf" in node:
        if not any(not _errors(value, sub, defs, parts) for sub in node["anyOf"]):
            errors.append("%s: matches none of the anyOf schemas" % where)
    if "oneOf" in node:
        matched = sum(1 for sub in node["oneOf"] if not _errors(value, sub, defs, parts))
        if matched != 1:
            errors.append("%s: matches %d of the oneOf schemas, not exactly one" % (where, matched))


def _errors(value, node, defs, parts):
    errors = []
    _validate(value, node, defs, parts, errors)
    return errors


def validate(instance, schema_path, def_name=None):
    """Return the errors of instance against the schema file, or against its
    $defs entry def_name; an empty list means valid."""
    schema = load(schema_path)
    defs = schema.get("$defs", {}) if isinstance(schema, dict) else {}
    node = schema
    if def_name is not None:
        if def_name not in defs:
            raise KeyError("%s has no $defs entry %s" % (schema_path, def_name))
        node = defs[def_name]
    return _errors(instance, node, defs, [])
