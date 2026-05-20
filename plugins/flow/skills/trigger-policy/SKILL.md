---
name: trigger-policy
description: "Enforce FlowTrigger safety rules — no autonomous merge, no recursive trigger creation, max active triggers, allowed_actions / forbidden_actions ACLs. Validates trigger YAMLs at `.flow/triggers/*.trigger.yaml` against `schemas/v1/trigger.schema.json` AND cross-checks policy.forbidden_actions includes merge + release; refuses triggers that grant Tier 3 autonomy. Use when /flow:trigger create, /flow:trigger run, or /flow:watch is invoked. This skill MUST be consulted because triggers can fire without user supervision — a trigger granting merge autonomy is the single fastest path to an untrusted-merge incident, and recursive trigger creation is the loop-bomb shape of the runtime layer."
allowed-tools: Bash, Read
context: fork
agent: general-purpose
---

# Trigger Policy

You own FlowTrigger safety. Triggers fire without direct user supervision in many cases (CI events, scheduled runs); the policy in this skill is the last line of defense against unintended-action triggers.

## Iron Law

**`merge` and `release` MUST appear in every trigger's `policy.forbidden_actions`. Triggers cannot grant Tier 3 autonomy regardless of any other configuration. This is non-negotiable.**

## Inputs

The invoking command MUST pass:
1. **Trigger YAML path** — either a template under `plugins/flow/triggers/templates/` or a project-local trigger at `.flow/triggers/<id>.trigger.yaml`.
2. **Mode** — `validate | enforce`. Validate is read-only (used by /flow:trigger validate); enforce is the gate before /flow:trigger run actually dispatches the target command.

## Outputs

Structured JSON report:

```json
{
  "trigger_id": "pr-123-watch",
  "schema_valid": true,
  "tier3_violations": [],
  "recursion_violations": [],
  "missing_required_forbidden": [],
  "concurrency_violations": [],
  "overall": "pass"
}
```

Exit code: 0 on pass; 1 on policy violation; 2 on schema invalid.

## Workflow

### Step 1: Schema validation

```bash
python3 -m jsonschema -i "${TRIGGER_YAML}" "plugins/flow/schemas/v1/trigger.schema.json"
```

Failure → `overall: schema_invalid` (exit 2).

### Step 2: Tier 3 absolute deny

Verify `policy.forbidden_actions` contains both `merge` AND `release`. Missing either → `tier3_violations.append({"action": "merge_or_release", "reason": "must be forbidden"})`. Hard fail.

### Step 3: Recursion policy check

Verify `recursion_policy.triggered_runs_may_create_triggers` is `false` (or unset; default is false). Same for `triggered_runs_may_modify_triggers` and `triggered_runs_may_enable_triggers`. Any set to `true` requires explicit Tier 3 authorization — surface as `recursion_violations` and require AskUserQuestion at /flow:trigger create time.

### Step 4: Allowed-types check

Verify `trigger.type` is in `flow.triggers.allowedTypes` (cascade-resolved; default `[manual, hook, loop_prompt]`). Trigger types `github_actions | local_cron | local_daemon` are valid schema but disabled in v3.0 — surface as `tier3_violations` if the project's setting doesn't permit them.

### Step 5: Active-trigger count

Count `.flow/triggers/*.trigger.yaml` files with `metadata.enabled: true` AND lifecycle != disabled. If count >= `flow.triggers.maxActiveTriggers` (cascade-resolved; default 5), refuse to enable a new trigger. The user must `/flow:trigger disable` an existing one first.

### Step 6: Concurrency sanity check

If `concurrency.policy: cancel_previous` is set on a trigger whose target invokes a Tier 2 action (e.g., push, commit), surface a warning — cancel_previous + Tier 2 can produce partial commits.

### Step 7: Compose overall verdict

| Condition | overall |
|---|---|
| schema fails | `schema_invalid` (exit 2) |
| `tier3_violations` non-empty | `tier3_violation` (exit 1; HARD FAIL) |
| `recursion_violations` non-empty | `recursion_violation` (exit 1) |
| `concurrency_violations` non-empty | `concurrency_warning` (exit 0 — soft warning) |
| else | `pass` (exit 0) |

## Anti-patterns

- ❌ Allowing a trigger that grants merge/release autonomy. Non-negotiable.
- ❌ Allowing recursive trigger creation without explicit user approval. Loop-bomb shape.
- ❌ Treating soft-warning concurrency violations as hard fails (over-blocks).
- ❌ Skipping the active-trigger count check — unbounded trigger growth defeats the maxActiveTriggers budget.

## Reuse map

- `plugins/flow/schemas/v1/trigger.schema.json` — schema this skill validates against.
- `plugins/flow/triggers/templates/` — plugin-shipped templates.
- `plugins/flow/commands/trigger.md` — `/flow:trigger` command that invokes this skill.
- `plugins/flow/commands/watch.md` — `/flow:watch` command that creates triggers from templates.
- `plugins/flow/references/flow-triggers.md` — user-facing trigger documentation.
