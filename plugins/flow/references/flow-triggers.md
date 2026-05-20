# FlowTrigger — wake-up intent contracts

FlowTrigger is the flow plugin's project-local replacement for "background execution" — except flow makes NO claim to actually run things in the background. Plugins cannot invoke native `/loop` or scheduled tasks from plugin code. FlowTrigger artifacts declare WHEN flow should resume work and WHAT to do, but actual execution requires a runner: the user manually invoking `/loop`, a Stop hook firing, CI invoking a workflow, or (v3.1+) an external runner like GitHub Actions or local cron.

## Trigger types (v3.0)

| Type | Runner | Mechanism |
|---|---|---|
| `manual` | User | User invokes `/flow:run trigger <id>` directly when ready |
| `hook` | Claude Code hook | A hook script (e.g., PostToolUse) invokes `/flow:run trigger <id>` programmatically |
| `loop_prompt` | User-invoked `/loop` | `/flow:watch` generates a loop-prompt file the user invokes with `/loop @.claude/flow-loop-<id>.md` |

## Trigger types (v3.1+ — design only, NOT shipped in v3.0)

| Type | Runner | Mechanism |
|---|---|---|
| `github_actions` | GitHub Actions workflow | `entrypoint: .github/workflows/flow-trigger.yml` |
| `local_cron` | crontab | `schedule: "0 */2 * * *"` |
| `local_daemon` | Long-running local process | (Future adapter design) |

## Critical non-features

Per the v3 non-goals — explicit about what FlowTrigger does NOT do:

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
└── nightly-maintenance.trigger.yaml       # Template for /flow:watch (manual setup)

.flow/triggers/                          # Project-local trigger artifacts
├── pr-123-watch.trigger.yaml             # Tracked — team-shared trigger
├── ci-failure-main.trigger.yaml          # Tracked
└── pr-456-debug.local.yaml               # GITIGNORED — per-developer

.claude/flow-loop-<id>.md                # Generated loop-prompt (NOT in flow plugin tree)
                                          # /flow:watch creates this; user invokes /loop on it
```

## Settings

| Key | Default | Description |
|---|---|---|
| `flow.triggers.enabled` | `false` | Master switch |
| `flow.triggers.allowedTypes` | `[manual, hook, loop_prompt]` | v3.1+ types are valid schema but disabled until shipped |
| `flow.triggers.allowAutonomousMerge` | `false` | Hard-coded non-negotiable |
| `flow.triggers.allowTriggerCreationFromTriggeredRun` | `false` | Recursion default |
| `flow.triggers.defaultConcurrency` | `skip_if_running` | When triggers fire on top of in-flight runs |
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
