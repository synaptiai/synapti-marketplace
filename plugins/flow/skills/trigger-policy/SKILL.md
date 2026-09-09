---
name: trigger-policy
description: "Enforce FlowTrigger safety rules — no autonomous merge, no recursive trigger creation, max active triggers, allowed_actions / forbidden_actions ACLs. Validates trigger YAMLs at `.flow/triggers/*.trigger.yaml` against `schemas/v1/trigger.schema.json` AND cross-checks policy.forbidden_actions includes merge + release; refuses triggers that grant Tier 3 autonomy. Use when /flow:trigger create, /flow:trigger run, or /flow:watch is invoked. This skill MUST be consulted because triggers can fire without user supervision — a trigger granting merge autonomy is the single fastest path to an untrusted-merge incident, and recursive trigger creation is the loop-bomb shape of the runtime layer."
allowed-tools: Bash, Read
agent: general-purpose
---

# Trigger Policy

## Contract

Iron law: `merge` and `release` MUST appear in every trigger's `policy.forbidden_actions` — triggers cannot grant Tier 3 autonomy regardless of any other configuration. Invoked in `validate` mode (read-only) by `/flow:trigger create|enable|validate` and by `/flow:watch` step 4 before a trigger YAML is written or enabled, and in `enforce` mode by `/flow:run` step 3 and `/flow:trigger run` before the target command is dispatched. Returns the JSON report below with exit 0 (pass or soft warning), 1 (policy violation), or 2 (schema invalid); the caller aborts on non-zero. Permitted skips: none — every step runs; the only non-blocking outcome is `concurrency_warning`.

## Inputs

The invoking command MUST pass:

1. **Trigger YAML path** — a template under `plugins/flow/triggers/templates/` or a project-local `.flow/triggers/<id>.trigger.yaml`.
2. **Mode** — `validate | enforce`.

## Output

```json
{
  "trigger_id": "pr-123-watch",
  "schema_valid": true,
  "tier3_violations": [],
  "recursion_violations": [],
  "missing_required_forbidden": [],
  "cross_reference_violations": [],
  "concurrency_violations": [],
  "overall": "pass"
}
```

## Steps

1. **Schema validation**: `python3 -m jsonschema -i "${TRIGGER_YAML}" "plugins/flow/schemas/v1/trigger.schema.json"`. Failure → `overall: schema_invalid` (exit 2).
2. **Tier 3 absolute deny**: `policy.forbidden_actions` must contain both `merge` AND `release`. Missing either → `tier3_violations.append({"action": "merge_or_release", "reason": "must be forbidden"})`. Hard fail.
3. **Recursion policy**: `recursion_policy.triggered_runs_may_create_triggers`, `triggered_runs_may_modify_triggers`, and `triggered_runs_may_enable_triggers` must be `false` or unset (default false). Any `true` → `recursion_violations`; enabling it requires explicit Tier 3 authorization via AskUserQuestion at `/flow:trigger create` time.
4. **Allowed types**: `trigger.type` must be in `flow.triggers.allowedTypes` (cascade-resolved; default `[manual, hook, loop_prompt]`). `github_actions | local_cron | local_daemon` are schema-valid but disabled in v3.0 — surface as `tier3_violations` unless the project's setting permits them.
5. **Active-trigger count**: count `.flow/triggers/*.trigger.yaml` with `metadata.enabled: true` and lifecycle != disabled. If count >= `flow.triggers.maxActiveTriggers` (cascade-resolved; default 5), refuse to enable a new trigger — the user must `/flow:trigger disable` one first.
6. **Concurrency sanity**: `concurrency.policy: cancel_previous` on a trigger whose target invokes a Tier 2 action (push, commit) → `concurrency_violations` warning; cancel_previous + Tier 2 can produce partial commits. Soft warning only — never a hard fail.
7. **Target workflow cross-reference**: when `target.workflow` is set, the workflow must exist at `plugins/flow/workflows/${WF}.workflow.yaml` or `.flow/workflows/${WF}.workflow.yaml` (`[ -f "$PLUGIN_PATH" ] || [ -f "$LOCAL_PATH" ]`). Missing → `cross_reference_violations.append({"type": "missing_target_workflow", "name": target_workflow, "checked_paths": [PLUGIN_PATH, LOCAL_PATH]})`. **Hard fail** (exit 1) — a trigger pointing at a non-existent workflow is broken by construction; this catches typos (`address` vs `address-pr`) at creation rather than when `/flow:run trigger <id>` dispatches. When `target.workflow` is absent (`target.command` only), this step is a no-op.
8. **Overall verdict**:

| Condition | overall |
|---|---|
| schema fails | `schema_invalid` (exit 2) |
| `tier3_violations` non-empty | `tier3_violation` (exit 1; HARD FAIL) |
| `recursion_violations` non-empty | `recursion_violation` (exit 1) |
| `cross_reference_violations` non-empty | `cross_reference_failed` (exit 1; HARD FAIL — missing target workflow) |
| `concurrency_violations` non-empty | `concurrency_warning` (exit 0 — soft warning) |
| else | `pass` (exit 0) |

## Reuse map

- `plugins/flow/schemas/v1/trigger.schema.json` — schema validated against.
- `plugins/flow/triggers/templates/` — plugin-shipped templates.
- `plugins/flow/commands/trigger.md`, `watch.md`, `run.md` — invoking commands.
- `plugins/flow/references/flow-triggers.md` — user-facing trigger documentation.
