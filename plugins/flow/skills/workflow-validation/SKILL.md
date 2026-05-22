---
name: workflow-validation
description: "Validate a FlowWorkflow YAML at `plugins/flow/workflows/<id>.workflow.yaml` against `schemas/v1/workflow.schema.json` AND cross-reference the referenced skills/agents exist + every Tier 3 action is confirm-gated + no native /goal or /loop dependency is declared. Use when /flow:workflow validate is invoked, when CI runs the workflow schema gates, or when a new workflow is being authored. This skill MUST be consulted because schema validation alone catches shape errors; cross-reference validation catches the silent-correctness failures (typo'd skill name, Tier 3 escape, /goal dependency) that would otherwise ship to users."
allowed-tools: Bash, Read
agent: general-purpose
---

# Workflow Validation

You validate FlowWorkflow YAMLs at two levels: schema conformance + cross-reference correctness.

## Iron Law

**A workflow that schema-validates but references a non-existent skill is a bug waiting to fire at runtime. Cross-reference validation catches this at author-time so it never reaches the user.**

## Inputs

The invoking command MUST pass:
1. **Workflow id** — `start-issue | review-pr | address-pr | merge-pr | release | debug | design` (or a future custom workflow). Maps to `plugins/flow/workflows/<id>.workflow.yaml`.

## Outputs

Structured JSON report on stdout. Each violation entry includes `source_file` (the YAML path that failed) and `example` (a snippet showing the corrected form) so the caller can render actionable error messages without consulting the schema separately (F15):

```json
{
  "workflow_id": "start-issue",
  "source_file": "plugins/flow/workflows/start-issue.workflow.yaml",
  "schema_valid": true,
  "cross_reference_errors": [
    {
      "type": "missing_skill",
      "name": "specifcation-capture",
      "source_file": "plugins/flow/workflows/start-issue.workflow.yaml",
      "example": "required_skills:\n  - specification-capture  # correct spelling"
    }
  ],
  "tier3_violations": [],
  "native_slash_violations": [],
  "overall": "pass"
}
```

Exit code: 0 if `overall: pass`; 1 if any cross-reference, recursion, native-slash, or tier-3 violation; 2 if schema invalid.

**Per-violation field contract:**
- `source_file` — the YAML path (project-local override takes precedence over plugin default; whichever was actually loaded).
- `example` — a YAML snippet showing the corrected shape for this specific violation. The renderer in `commands/workflow.md:validate` prints `source_file` + `example` below each error.

## Workflow

### Step 1: Schema validation (with v3.0.x deprecation migration)

**Cycle-14 F4 (error-handler verifier)**: the previous documentation showed both an in-memory migration shim AND a `python3 -m jsonschema -i <file> <schema>` invocation. The CLI re-reads the file from disk, bypassing the in-memory shim entirely. Any project-local workflow with the legacy `completion_gate.requires` field would fail schema validation despite the documented "accept legacy through v3.0.x" contract. The shim and the validator must run in the same Python process. The canonical invocation is:

```bash
python3 - "$WORKFLOW_PATH" "$SCHEMA_PATH" <<'PYEOF'
import sys, yaml, json, jsonschema
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

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
    # Cycle-14 F3 (code-reviewer verifier): both fields present — drop legacy,
    # emit WARN. Previously the shim silently skipped this case and the schema
    # rejected the YAML with an opaque `additionalProperties` error.
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

If schema validation fails, populate `cross_reference_errors` with the first error and set `overall: schema_invalid`. Skip remaining steps.

### Step 2: Required-skills cross-reference

For each entry in `required_skills[]`:
```bash
[ -f "plugins/flow/skills/${skill_name}/SKILL.md" ]
```

Missing → `cross_reference_errors.append({"type": "missing_skill", "name": skill_name, "source_file": <loaded YAML path>, "example": "required_skills:\n  - <correct-skill-name>\n# check plugins/flow/skills/ for existing skill directory names"})`.

### Step 3: Required-agents cross-reference

For each entry in `required_agents[]`:
```bash
[ -f "plugins/flow/agents/${agent_name}.md" ]
```

Missing → `cross_reference_errors.append({"type": "missing_agent", "name": agent_name, "source_file": <loaded YAML path>, "example": "required_agents:\n  - <correct-agent-name>\n# check plugins/flow/agents/*.md for available agents"})`.

### Step 4: Activity-level skill/agent cross-reference

Walk `phases[].activities[]`. For each activity with a `skill` field, repeat the existence check from Step 2. For each `agent` field, repeat Step 3.

### Step 5: Tier classification check

In `tier_classification`, verify:
- `merge` is `confirm` (Tier 3 — Iron Law, hard fail)
- `release` is `confirm` (Tier 3 — Iron Law, hard fail)
- `tag_push` is `confirm` when present (Iron Law, hard fail)

Any of `merge`, `release`, or `tag_push` set to `autonomous` or `journal` → `tier3_violations.append({"action": ..., "value": ..., "expected": "confirm", "source_file": <loaded YAML path>, "example": "tier_classification:\n  merge: confirm  # Tier 3 must be confirm — non-negotiable per the Iron Law"})`. **Hard fail** (exit 1). This matches `trigger-policy/SKILL.md` Step 2 — the project's "No Irreversible Actions Without Approval" boundary is non-negotiable; a workflow that downgrades Tier 3 is broken by construction, not "legitimately overriding."

### Step 6: No-native-slash check

Grep the entire workflow YAML for `/goal\b`, `/loop\b`, `/schedule\b`, `/routine\b` outside of `description` fields. Any match that looks like an invoked dependency (e.g., `command: /goal foo`) → `native_slash_violations.append(...)`. Hard fail.

### Step 7: Completion gate documentation check

`completion_gate.documented_requirements` is advisory documentation, not an enforced check vocabulary — commands enforce their own gates (goal lifecycle, finding ledger, quality commands). This step only verifies the field is present and non-empty (already enforced by the schema's `minItems: 1`). No cross-reference to activity `evidence` fields is performed; the labels are free-text by design.

If a future version reintroduces enforcement, the registry of valid labels would live here. For v3.0.x, this step is a no-op beyond the schema check.

### Step 8: Overall verdict

| Condition | overall |
|---|---|
| schema fails | `schema_invalid` (exit 2) |
| any `native_slash_violations` | `native_slash_present` (exit 1) |
| any `tier3_violations` | `tier3_invalid` (exit 1 — Iron Law) |
| any `cross_reference_errors` | `cross_reference_failed` (exit 1) |
| else | `pass` (exit 0) |

## Anti-patterns

- ❌ Treating schema-valid as cross-reference-valid. Schema only catches shape; references catch identity.
- ❌ Treating Tier 3 downgrade as a soft warning. The "No Irreversible Actions Without Approval" boundary is non-negotiable.
- ❌ Accepting workflows that reference native `/goal`. Per the v3 non-goals — plugins cannot invoke native slash commands.

## Reuse map

- `plugins/flow/schemas/v1/workflow.schema.json` — schema this skill validates against.
- `plugins/flow/workflows/*.workflow.yaml` — workflows this skill validates.
- `plugins/flow/commands/workflow.md` — the `/flow:workflow` dispatcher that invokes this skill.
