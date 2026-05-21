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

Structured JSON report on stdout:

```json
{
  "workflow_id": "start-issue",
  "schema_valid": true,
  "cross_reference_errors": [],
  "tier_warnings": [],
  "native_slash_violations": [],
  "overall": "pass"
}
```

Exit code: 0 if `overall: pass`; 1 if any cross-reference or tier error; 2 if schema invalid.

## Workflow

### Step 1: Schema validation

Before invoking jsonschema, apply the **v3.0.x deprecation migration**: if the YAML has the legacy field `completion_gate.requires` and lacks the current field `completion_gate.documented_requirements`, rename it in-memory and emit a deprecation warning to stderr. This keeps project-local workflows authored against the v3.0.0 shape valid through v3.0.x; support is removed in v3.1.

```python
# Pre-validation migration (v3.0.x compatibility shim)
gate = wf.get("completion_gate") or {}
if "requires" in gate and "documented_requirements" not in gate:
    gate["documented_requirements"] = gate.pop("requires")
    print(f"WARN: {workflow_path}: completion_gate.requires is deprecated — rename to completion_gate.documented_requirements (will be required in v3.1)", file=sys.stderr)
    wf["completion_gate"] = gate
```

Then validate against the schema (the Python API rather than CLI for richer error formatting; the SKILL implementation reads the schema + workflow YAML and calls `jsonschema.validate`):

```bash
python3 -m jsonschema -i "plugins/flow/workflows/${ID}.workflow.yaml" "plugins/flow/schemas/v1/workflow.schema.json"
```

If schema validation fails, populate `cross_reference_errors` with the first error and set `overall: schema_invalid`. Skip remaining steps.

### Step 2: Required-skills cross-reference

For each entry in `required_skills[]`:
```bash
[ -f "plugins/flow/skills/${skill_name}/SKILL.md" ]
```

Missing → `cross_reference_errors.append({"type": "missing_skill", "name": skill_name})`.

### Step 3: Required-agents cross-reference

For each entry in `required_agents[]`:
```bash
[ -f "plugins/flow/agents/${agent_name}.md" ]
```

Missing → `cross_reference_errors.append({"type": "missing_agent", "name": agent_name})`.

### Step 4: Activity-level skill/agent cross-reference

Walk `phases[].activities[]`. For each activity with a `skill` field, repeat the existence check from Step 2. For each `agent` field, repeat Step 3.

### Step 5: Tier classification check

In `tier_classification`, verify:
- `merge` is `confirm` (Tier 3 — Iron Law, hard fail)
- `release` is `confirm` (Tier 3 — Iron Law, hard fail)
- `tag_push` is `confirm` when present (Iron Law, hard fail)

Any of `merge`, `release`, or `tag_push` set to `autonomous` or `journal` → `tier3_violations.append({"action": ..., "value": ..., "expected": "confirm"})`. **Hard fail** (exit 1). This matches `trigger-policy/SKILL.md` Step 2 — the project's "No Irreversible Actions Without Approval" boundary is non-negotiable; a workflow that downgrades Tier 3 is broken by construction, not "legitimately overriding."

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
