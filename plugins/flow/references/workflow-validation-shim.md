# Workflow Validation — schema step with the v3.0.x migration shim

Reference for Step 1 of the `workflow-validation` skill. The canonical schema-validation invocation for a FlowWorkflow YAML, including the `completion_gate.requires` → `completion_gate.documented_requirements` deprecation shim.

## Why the shim and the validator share one process

`python3 -m jsonschema -i <file> <schema>` re-reads the YAML from disk, which bypasses any in-memory migration. A project-local workflow that still uses the legacy `completion_gate.requires` field would then fail schema validation (the schema sets `additionalProperties: false`) despite the documented "accept legacy through v3.0.x" contract. The shim and `jsonschema.validate` therefore run in the same Python process, on the same in-memory document.

Shim behavior:

- `requires` present, `documented_requirements` absent → rename in memory, emit `WARN` on stderr.
- both present → drop the legacy `requires`, emit `WARN` on stderr (previously the schema rejected this with an opaque `additionalProperties` error).
- `requires` absent → no-op.

The legacy name will be rejected outright in v3.1.

## Canonical invocation

```bash
# Keep the working directory out of PYTHONPATH before python3 starts: the
# interpreter imports sitecustomize from each element at startup, and an
# empty element is the working directory. tests/syspath-guard.test.sh has the
# reasons; FLOW_USER_PYTHONPATH keeps the original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; _flow_rest="${PYTHONPATH-}:"; _flow_wd=$(pwd -P 2>/dev/null) || _flow_wd=""
while [ -n "$_flow_rest" ]; do _flow_e=${_flow_rest%%:*}; _flow_rest=${_flow_rest#*:}; case "$_flow_e" in /*) [ "$(command cd -P -- "$_flow_e" >/dev/null 2>&1 && pwd -P)" = "$_flow_wd" ] || _flow_pp="${_flow_pp:+$_flow_pp:}$_flow_e" ;; esac; done
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
python3 - "$WORKFLOW_PATH" "$SCHEMA_PATH" <<'PYEOF'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import yaml, json, jsonschema

workflow_path = sys.argv[1]
schema_path = sys.argv[2]

with open(workflow_path, "r", encoding="utf-8") as f:
    wf = yaml.safe_load(f)

# Pre-validation migration (v3.0.x deprecation shim).
gate = (wf or {}).get("completion_gate") or {}
if "requires" in gate and "documented_requirements" not in gate:
    gate["documented_requirements"] = gate.pop("requires")
    wf["completion_gate"] = gate
    print(
        f"WARN: {workflow_path}: completion_gate.requires is deprecated — "
        f"rename to completion_gate.documented_requirements (will be required in v3.1)",
        file=sys.stderr,
    )
elif "requires" in gate and "documented_requirements" in gate:
    del gate["requires"]
    wf["completion_gate"] = gate
    print(
        f"WARN: {workflow_path}: both completion_gate.requires (legacy) and "
        f".documented_requirements present — dropping legacy field. Remove from source.",
        file=sys.stderr,
    )

with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
try:
    jsonschema.validate(wf, schema)
    print("schema_valid: true")
except jsonschema.ValidationError as e:
    print(f"schema_valid: false\nerror: {e.message}")
    sys.exit(2)
PYEOF
```

`$WORKFLOW_PATH` is whichever YAML was actually loaded — the project-local `.flow/workflows/<id>.workflow.yaml` override when present, otherwise `plugins/flow/workflows/<id>.workflow.yaml`. `$SCHEMA_PATH` is `plugins/flow/schemas/v1/workflow.schema.json`. Exit 2 on schema failure; the skill then sets `overall: schema_invalid` and skips the cross-reference steps.

