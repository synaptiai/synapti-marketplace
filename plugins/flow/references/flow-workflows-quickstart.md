# Hello, FlowWorkflow — quickstart

A 5-minute walkthrough of the `/flow:workflow` inspection commands. By the end you'll have validated a workflow, rendered its phase graph, and understood why workflows are inspectable contracts rather than execution gates.

## Prerequisites

- flow v3.0.0 installed (`claude plugins list | grep flow`)
- A git repository (any one — workflows are read-only inspections, no working tree changes)
- `python3` with `PyYAML` available (`python3 -c 'import yaml'` exits 0)
- `python3 -m jsonschema` available — `pip install jsonschema` if absent (the validation skill degrades to schema-skipped with a stderr warn when missing)

## Step 1 — Enable workflows

Workflows are opt-in. When you ran `/flow:start` for the first time after upgrading to v3.0.0, the **Enable v3** answer turned on both `flow.goals` and `flow.workflows`. If you skipped onboarding or want to enable workflows explicitly:

```bash
jq '.flow.workflows.enabled = true' .claude/settings.flow.json > /tmp/s && mv /tmp/s .claude/settings.flow.json
```

Verify:

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" --default "false" '.flow.workflows.enabled'
# expect: true
```

## Step 2 — List shipped workflows

```text
/flow:workflow list
```

You'll see the 7 plugin-shipped workflows:

```
start-issue   /flow:start    Issue → branch → spec → code → verify
review-pr     /flow:review   PR → parallel review → consolidate
address-pr    /flow:address  PR → resolve findings → verify
merge-pr      /flow:merge    PR → verify gates → confirm → merge
release       /flow:release  Version bump → tag → push
debug         /flow:debug    Reproduce → diagnose → fix → verify
design        /flow:design   Explore → propose → record decision
```

The `list` subcommand also surfaces project-local overrides at `.flow/workflows/*.workflow.yaml` (none yet — we'll add one in Step 5).

## Step 3 — Inspect a workflow

```text
/flow:workflow inspect start-issue
```

You'll see the full YAML: metadata, required_skills, phases (with activities), `completion_gate.documented_requirements`, and `tier_classification`.

Key things to notice:
- **Phases are sequential** (`preflight → explore → plan → code → verify`)
- **Activities under each phase** name the skill, agent, or command invoked
- **`completion_gate.documented_requirements`** lists what "complete" means — but this is **advisory documentation**, not an enforced gate. Commands enforce their own gates (goal lifecycle, finding ledger, quality commands).
- **`tier_classification`** declares which actions need confirmation (Tier 3) vs run autonomously

## Step 4 — Validate a workflow

```text
/flow:workflow validate start-issue
```

The validation skill checks:
1. Schema shape (against `plugins/flow/schemas/v1/workflow.schema.json`)
2. Every `required_skills[]` entry has a corresponding `plugins/flow/skills/<name>/SKILL.md`
3. Every `required_agents[]` entry has a corresponding `plugins/flow/agents/<name>.md`
4. Activity-level skill/agent references exist
5. Tier 3 actions (`merge`, `release`, `tag_push`) are gated `confirm` — Iron Law (hard fail)
6. No native slash invocations (`/goal`, `/loop`, `/schedule`, `/routine`)

Validation output is structured JSON. Each violation includes `source_file` + `example` (the corrected snippet) so you can fix the YAML directly. Expected output for a healthy workflow:

```json
{"workflow_id":"start-issue","schema_valid":true,"cross_reference_errors":[],"tier3_violations":[],"native_slash_violations":[],"overall":"pass"}
```

Exit code 0 on `pass`; 1 on cross-reference / tier3 / native-slash violation; 2 on schema-invalid.

## Step 5 — Render the phase graph

```text
/flow:workflow graph start-issue
```

A textual DAG of the workflow's phase/activity structure:

```
Workflow: start-issue
Command:  /flow:start
Version:  1

PHASES
------
  1. preflight (bash) [blocking]
     1.1 preflight_issue_start (bash)
     ...
  2. explore (mixed)
     2.1 fetch_issue_context (bash)
     2.2 specification_capture (skill skill=specification-capture)
     2.3 spec_validation_gate (gate)
     2.4 goal_contract_capture (skill skill=goal-contract-capture)
  3. plan (agent) [completion]
     ...

COMPLETION GATE (advisory documentation, not enforced)
------------------------------------------------------
  - all_quality_checks_pass
  - goal_status_achieved
  - ...

TIER CLASSIFICATION
-------------------
  branch_creation           autonomous
  commits                   autonomous
  merge                     confirm
  release                   confirm
```

Use `graph` when you want to understand the high-level shape of a command without reading its full markdown.

## Step 6 — Project-local overrides

To customize a workflow for your project (e.g., adding a security-scan phase to `address-pr`), copy the plugin default and edit:

```bash
mkdir -p .flow/workflows
cp plugins/flow/workflows/address-pr.workflow.yaml .flow/workflows/address-pr.workflow.yaml
$EDITOR .flow/workflows/address-pr.workflow.yaml
```

`/flow:workflow inspect address-pr` and `/flow:workflow graph address-pr` now read your local override (shadows the plugin default). Run `validate` after editing to catch shape mistakes.

Project-local overrides are committed by default (matches gitignore policy in `references/flow-runtime-state.md`). Truly per-developer experimentation should use a `.local.workflow.yaml` suffix and add to personal `.gitignore`.

## Common gotchas

- **`completion_gate.documented_requirements` is advisory**: the labels are documentation, not a check vocabulary. Commands enforce their own gates. If you need actual enforcement, change the command's markdown — the workflow YAML can't gate execution.
- **`completion_gate.requires` (legacy name)**: workflows authored against v3.0.0-rc shapes may still use `requires` instead of `documented_requirements`. The validation skill accepts both during v3.0.x with a deprecation warning. Rename before v3.1.
- **Tier 3 downgrade is a hard fail**: don't set `merge: autonomous` to "test something" — the validation skill rejects it and refuses to ship. If you need autonomous merge for a specific use case, that's a different conversation about your tier policy, not a workflow change.

## Next steps

- `flow-workflows.md` — full FlowWorkflow model + validation rules
- `flow-triggers-quickstart.md` — companion walkthrough for `/flow:trigger` and `/flow:watch`
- `flow-goals-quickstart.md` — companion walkthrough for `/flow:goal` (5-minute FlowGoal demo)
- `plugins/flow/schemas/v1/workflow.schema.json` — schema source of truth
- `plugins/flow/skills/workflow-validation/SKILL.md` — validation logic detail
