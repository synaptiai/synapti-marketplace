# FlowWorkflow — machine-readable process contracts

FlowWorkflow YAMLs at `plugins/flow/workflows/<id>.workflow.yaml` are the inspectable contract for each `/flow:*` command. The command markdown remains Claude's execution manual; this YAML is what `/flow:workflow validate` checks for shape + cross-reference integrity.

## What a FlowWorkflow declares

| Section | Purpose |
|---|---|
| `metadata` | id, command (e.g. `/flow:start`), version, description |
| `inputs` | typed inputs the command accepts |
| `required_skills` | skills the command MUST be able to invoke (existence-checked) |
| `required_agents` | agents the command MUST be able to dispatch (existence-checked) |
| `phases` | ordered list of phases, each with type + activities |
| `completion_gate.requires` | conditions that MUST be true for the workflow to be "complete" |
| `tier_classification` | per-action tier (autonomous \| journal \| confirm) |

The full schema lives at `plugins/flow/schemas/v1/workflow.schema.json`.

## Workflows shipped in M4

| Workflow | Command | Phases (high-level) |
|---|---|---|
| `start-issue` | `/flow:start` | preflight → explore → plan → code (loop over ACs) → verify (parallel) |
| `review-pr` | `/flow:review` | preflight → fan-out (parallel reviewers) → consolidate → report |
| `address-pr` | `/flow:address` | preflight → categorize → resolve (loop over findings) → verify |
| `merge-pr` | `/flow:merge` | preflight → verify → confirm (AskUserQuestion) → merge |
| `release` | `/flow:release` | preflight → bump → confirm (AskUserQuestion) → tag |
| `debug` | `/flow:debug` | preflight → reproduce → diagnose → fix → verify |
| `design` | `/flow:design` | preflight → explore → design |

## Validation rules

`/flow:workflow validate <id>` enforces:

1. **Schema validity** — the file matches `workflow.schema.json` shape.
2. **`required_skills` existence** — every referenced skill has a `plugins/flow/skills/<name>/SKILL.md`.
3. **`required_agents` existence** — every referenced agent has a `plugins/flow/agents/<name>.md`.
4. **Per-activity references** — activities with `skill:` or `agent:` fields are existence-checked too.
5. **Tier 3 confirm-gating** — `merge` and `release` MUST be `confirm`. Soft fail for other Tier 3 actions.
6. **No native-slash invocations** — no `/goal`, `/loop`, `/schedule`, `/routine` as invoked commands. Hard fail.
7. **Completion gate dependency mapping** — every entry in `completion_gate.requires` corresponds to an activity output.

## Project-local overrides

Teams that need to customize a workflow can drop a `.flow/workflows/<id>.workflow.yaml` file alongside the plugin's default. `/flow:workflow inspect <id>` and `/flow:workflow graph <id>` read the local override when present; the plugin default is the fallback.

Project-local workflows are committed by default (per the gitignore policy). Truly per-developer overrides should use `.local.workflow.yaml` suffix and add to personal gitignore.

## Phase types

| Phase type | Meaning |
|---|---|
| `bash` | Plain shell-based phase (preflight, simple gates) |
| `mixed` | Combination of bash, skill, and agent activities |
| `agent` | Phase dispatches to an agent (e.g., implementation-planner) |
| `loop` | Iterates over a collection (e.g., `loop_over: goal.acceptance_criteria`) |
| `parallel_then_judge` | Activities run in parallel; a judge consolidates results |

## Gate types

| Gate type | Meaning |
|---|---|
| `blocking` | Phase MUST pass before next phase begins (e.g., preflight) |
| `spec_validation` | Spec Validation Gate (criterion-verification-map produces evidence) |
| `stranger_test` | Stranger Test (zero-context agent could execute) |
| `completion` | Workflow's completion_gate check |
| `none` | No gate (default) |

## Activity types

| Activity type | Meaning |
|---|---|
| `bash` | Pure shell command |
| `skill` | Invoke a named skill (skill: field required) |
| `agent` | Dispatch a named agent (agent: field required) |
| `task` | Implementation task within a code phase |
| `gate` | Gate evaluation (gate: field required) |
| `evaluation` | Run an evaluator (often command: /flow:goal evaluate) |
| `external` | External wait (e.g., AskUserQuestion, CI completion) |

## Settings

| Key | Default | Description |
|---|---|---|
| `flow.workflows.enabled` | `false` (M4 default) | Master switch for `/flow:workflow` command |

Default is `false` because workflows are inspectable documents — most users don't need to run `/flow:workflow` interactively. Teams flip to `true` for CI integration.

## References

- `plugins/flow/schemas/v1/workflow.schema.json` — schema definition
- `plugins/flow/workflows/*.workflow.yaml` — plugin-shipped definitions
- `plugins/flow/skills/workflow-validation/SKILL.md` — validation logic
- `plugins/flow/commands/workflow.md` — `/flow:workflow` command
- `plugins/flow/references/flow-goals.md` — FlowGoal model (referenced by every workflow's goal-creation activity)
- `plugins/flow/references/flow-runtime-state.md` — `.flow/` directory layout
