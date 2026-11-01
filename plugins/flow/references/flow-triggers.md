# FlowTrigger — wake-up intent contracts

FlowTrigger is the flow plugin's project-local replacement for "background execution" — except flow makes NO claim to actually run things in the background. Plugins cannot invoke native `/loop` or scheduled tasks from plugin code. FlowTrigger artifacts declare WHEN flow should resume work and WHAT to do, but actual execution requires a runner: the user manually invoking `/loop`, a Stop hook firing, or CI invoking a workflow. The schema also defines `github_actions`, `local_cron` and `local_daemon` triggers, but flow ships no runner for them.

## Trigger types (in the default `allowedTypes`)

| Type | Runner | Mechanism |
|---|---|---|
| `manual` | User | User invokes `/flow:run trigger <id>` directly when ready |
| `hook` | Claude Code hook | A hook script (e.g., PostToolUse) invokes `/flow:run trigger <id>` programmatically |
| `loop_prompt` | User-invoked `/loop` | `/flow:watch` generates a loop-prompt file the user invokes with `/loop @.claude/flow-loop-<id>.md` |

## Trigger types (schema-valid, not in the default `allowedTypes`)

| Type | Runner | Mechanism |
|---|---|---|
| `github_actions` | GitHub Actions workflow | `entrypoint: .github/workflows/flow-trigger.yml` |
| `local_cron` | crontab | `schedule: "0 */2 * * *"` |
| `local_daemon` | Long-running local process | (Future adapter design) |

## Critical non-features

What FlowTrigger does NOT do:

1. **No native /loop invocation.** Flow CANNOT invoke `/loop` from plugin code. `/flow:watch` generates a loop-prompt file; the user invokes `/loop` themselves.
2. **No exactly-once guarantees.** Triggers describe wake-up intent; flow makes no claim that a trigger fires exactly once. Use idempotent target commands.
3. **No background execution.** Triggers don't run in the background — they document when SOMEONE (user, hook, runner) should invoke `/flow:run`.
4. **No Tier 3 autonomy.** `merge` and `release` are absolutely forbidden in every trigger's `policy.forbidden_actions`. Non-negotiable.
5. **No recursive trigger creation.** `recursion_policy.triggered_runs_may_create_triggers` defaults to false. Flipping requires explicit user authorization at trigger-creation time.

## Lifecycle

```
created → enabled  ↔  disabled → deleted
              │
              ↓
            fired (one or more times via /flow:run trigger <id>)
              │
              ↓
            stop_conditions met → user disables OR deletes
```

A trigger doesn't have its own state machine — `metadata.enabled` is the only mutable field. Each firing creates a separate FlowRun under `.flow/runs/`.

## Files

```
plugins/flow/triggers/templates/         # Plugin-shipped templates
├── pr-watch.trigger.yaml                  # Template for /flow:watch pr <N>
├── ci-failure.trigger.yaml                # Template for /flow:watch ci
├── issue-watch.trigger.yaml               # Template for /flow:watch issue <N> (read-only on GitHub)
├── issue-watch.loop.md                    # Its loop prompt
├── branch-watch.trigger.yaml              # Template for /flow:watch branch (merge the default branch in)
├── branch-watch.loop.md                   # Its loop prompt
└── nightly-maintenance.trigger.yaml       # Template for /flow:watch (manual setup)

.flow/triggers/                          # Project-local trigger artifacts
├── pr-123-watch.trigger.yaml             # Tracked — team-shared trigger
└── ci-failure-main.trigger.yaml          # Tracked

.claude/flow-loop-<id>.md                # Generated loop-prompt (NOT in flow plugin tree)
                                          # /flow:watch creates this; user invokes /loop on it
```

## Settings

| Key | Default | Description |
|---|---|---|
| `flow.triggers.enabled` | `true` | Master switch; `false` turns `/flow:trigger`, `/flow:watch` and `/flow:run` off and hides the triggers section of `/flow:status` |
| `flow.triggers.allowedTypes` | `[manual, hook, loop_prompt]` | `github_actions`, `local_cron` and `local_daemon` are schema-valid but allowed only when added here |
| `flow.triggers.allowAutonomousMerge` | `false` | Not read by any command, hook or script; setting it to `true` changes nothing. The `trigger-policy` skill (step 2) refuses every trigger whose `policy.forbidden_actions` does not list both `merge` and `release` |
| `flow.triggers.allowTriggerCreationFromTriggeredRun` | `false` | Not read by any command, hook or script. Each trigger's own `recursion_policy.triggered_runs_may_create_triggers`, `_modify_triggers` and `_enable_triggers` (default `false` in the trigger schema) decide this; `trigger-policy` step 3 rejects a trigger that sets any of them to `true`. Nothing checks at run time whether a command was started by a trigger |
| `flow.triggers.defaultConcurrency` | `skip_if_running` | Not read by any command, hook or script. Each trigger sets its own `concurrency.policy`, which defaults to `skip_if_running` in the trigger schema; `/flow:run trigger` and `/flow:trigger run` read that field |
| `flow.triggers.maxActiveTriggers` | `5` | Cap on enabled triggers per project |

## Composition with other v3 primitives

- **FlowGoal** — a trigger's `target.goal` field links to an active FlowGoal. The trigger's stop_conditions usually include `goal_status == achieved`.
- **FlowWorkflow** — a trigger's `target.workflow` field declares which workflow it expects to run (e.g., `address-pr` for a PR-watch trigger).
- **FlowRun** — every `/flow:run trigger <id>` invocation creates a new FlowRun. Repeated triggers create repeated runs; resumability still works per-run.

## /flow:watch UX (proof of plugin constraint)

```text
$ /flow:watch pr 123

Created .flow/triggers/pr-123-watch.trigger.yaml
Created .claude/flow-loop-pr-123.md

To start watch mode manually, invoke:

  /loop @.claude/flow-loop-pr-123.md

Flow cannot invoke /loop from a plugin. The /loop command is a Claude
Code built-in; only you can start it. The trigger YAML records that
you're watching this PR; the prompt file gives /loop the per-iteration
instructions.
```

## Policy report

The report the `trigger-policy` skill returns, in `validate` and `enforce` mode:

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

`bin/flow-trigger-schema-check.sh <trigger.yaml>` is the skill's step 1: it validates the trigger against `schemas/v1/trigger.schema.json` in the plugin it ships in, prints one `SCHEMA_ERROR=` line per error, and exits 0 (valid), 2 (schema errors) or 1 (the trigger or the schema could not be read, or python3, PyYAML or jsonschema is missing).

## References

- `plugins/flow/schemas/v1/trigger.schema.json` — schema definition
- `plugins/flow/triggers/templates/` — plugin templates
- `plugins/flow/skills/trigger-policy/SKILL.md` — enforcement
- `plugins/flow/commands/trigger.md` — `/flow:trigger`
- `plugins/flow/commands/watch.md` — `/flow:watch`
- `plugins/flow/commands/run.md` — `/flow:run`
- `plugins/flow/references/flow-goals.md` — FlowGoal composition
- `plugins/flow/references/flow-workflows.md` — FlowWorkflow composition
- `plugins/flow/references/flow-runtime-state.md` — `.flow/` directory layout
