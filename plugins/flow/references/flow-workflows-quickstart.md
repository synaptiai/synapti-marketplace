# Hello, FlowWorkflow — quickstart

A 5-minute walkthrough of the `/flow:workflow` inspection commands. By the end you'll have validated a workflow, rendered its phase graph, and understood why workflows are inspectable contracts rather than execution gates.

## Prerequisites

- flow installed (`claude plugins list | grep flow`)
- A git repository (any one — workflows are read-only inspections, no working tree changes)
- `python3` with `PyYAML` available (`python3 -c 'import yaml'` exits 0)
- The `jsonschema` Python module (`python3 -c 'import jsonschema'` exits 0; `pip install jsonschema` if absent) — `validate` needs it for the schema step

## Step 1 — Check that workflows are on

Workflows are on by default (`flow.workflows.enabled: true`). If your settings turned them off, turn them back on:

```bash
jq '.flow.workflows.enabled = true' .claude/settings.flow.json > /tmp/s && mv /tmp/s .claude/settings.flow.json
```

Verify:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh" --default "true" '.flow.workflows.enabled'
# expect: true
```

## Step 2 — List shipped workflows

```text
/flow:workflow list
```

You'll see the 7 plugin-shipped workflows, each with its command and its `metadata.description` (shortened here):

```
Plugin-shipped workflows:
  address-pr      /flow:address        Address PR review feedback — categorize findings, resolve surgically, verify.
  debug           /flow:debug          Debug a specific failure — reproduce, root-cause, fix, verify.
  design          /flow:design         Design or review architecture for a feature or system. ...
  merge-pr        /flow:merge          Merge an approved PR — verify approval, CI green, goal achieved; ...
  release         /flow:release        Create a release in two runs — open a release pull request ...
  review-pr       /flow:review         Review a pull request — fan-out reviewers, consolidate findings, post comments.
  start-issue     /flow:start          Start work on a GitHub issue — preflight, spec capture, plan, code, verify.
```

The `list` subcommand also surfaces project-local overrides at `.flow/workflows/*.workflow.yaml` (none yet — we'll add one in Step 6).

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
     2.2 fetch_repo_context (bash)
     2.3 specification_capture (skill skill=specification-capture)
     2.4 spec_validation_gate (gate)
  3. plan (agent)
     3.1 goal_creation (skill skill=goal-contract-capture)
     ...

COMPLETION GATE (advisory documentation, not enforced)
------------------------------------------------------
  - all_quality_checks_pass
  - goal_status_achieved
  - ...

TIER CLASSIFICATION
-------------------
  branch_creation           autonomous
  file_edits                autonomous
  commits                   autonomous
  issue_assignment          journal
  push                      journal
  pr_create                 journal
  merge                     confirm
  release                   confirm
```

Use `graph` when you want to understand the high-level shape of a command without reading its full markdown.

## Step 6 — Project-local overrides

To customize a workflow for your project (e.g., adding a security-scan phase to `address-pr`), copy the plugin default from the installed plugin root (resolved as `references/plugin-root-resolution.md` describes) and edit:

```bash
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")"
mkdir -p .flow/workflows
cp "$FLOW_ROOT/workflows/address-pr.workflow.yaml" .flow/workflows/address-pr.workflow.yaml
$EDITOR .flow/workflows/address-pr.workflow.yaml
```

`/flow:workflow inspect address-pr` and `/flow:workflow graph address-pr` now read your local override (shadows the plugin default). Run `validate` after editing to catch shape mistakes.

Project-local overrides are committed by default (matches gitignore policy in `references/flow-runtime-state.md`). An override must be named `<id>.workflow.yaml`; a file such as `address-pr.local.workflow.yaml` is a separate workflow with the id `address-pr.local` and overrides nothing. To keep an override to yourself, add its file to your personal gitignore.

## Common gotchas

- **`completion_gate.documented_requirements` is advisory**: the labels are documentation, not a check vocabulary. Commands enforce their own gates. If you need actual enforcement, change the command's markdown — the workflow YAML can't gate execution.
- **`completion_gate.requires` (legacy name)**: some workflows use `requires` instead of `documented_requirements`. The validation skill accepts it with a deprecation warning on stderr; rename it to `documented_requirements`.
- **Tier 3 downgrade is a hard fail**: don't set `merge: autonomous` to "test something" — the validation skill rejects it and refuses to ship. If you need autonomous merge for a specific use case, that's a different conversation about your tier policy, not a workflow change.

## Next steps

- [`flow-workflows.md`](flow-workflows.md) — full FlowWorkflow model + validation rules
- [`flow-triggers-quickstart.md`](flow-triggers-quickstart.md) — companion walkthrough for `/flow:trigger` and `/flow:watch`
- [`flow-goals-quickstart.md`](flow-goals-quickstart.md) — companion walkthrough for `/flow:goal` (5-minute FlowGoal demo)
- [`../schemas/v1/workflow.schema.json`](../schemas/v1/workflow.schema.json) — schema source of truth
- [`../skills/workflow-validation/SKILL.md`](../skills/workflow-validation/SKILL.md) — validation logic detail
