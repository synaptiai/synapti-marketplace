# Migrating from flow v2.x to v3.0

Upgrading turns on four features by default: FlowGoals (`flow.goals.goalCreation: auto`), FlowRuns (`flow.runtime.enabled`), workflow definitions (`flow.workflows.enabled`) and triggers (`flow.triggers.enabled`). They write only local files under `.flow/`. This guide describes what each does and how to tune or turn it off.

## What changes when you upgrade (v3.1)

v3.1 makes FlowGoals **invisible-by-default**: `flow.goals.goalCreation` defaults to `auto`, so goal/run/evidence artifacts are recorded for you rather than gated behind an opt-in. After upgrading without editing settings:

- `/flow:start <issue>` creates `.flow/goals/issue-<N>.goal.yaml` whenever the Spec Validation Gate passes with **≥1 acceptance criterion carrying a `verification_command`**. An issue that yields zero verifiable ACs (e.g. a spec-free `documentation`/`chore` issue) creates **no** goal, silently. All artifacts are local under `.flow/` — nothing is pushed, posted, or sent.
- `/flow:status` surfaces the active goal/run; `/flow:pr` and `/flow:merge` gate on goal **existence** — a branch whose goal isn't `achieved` is held back, but a branch with **no** goal is not blocked.
- The Stop hook fires but stays silent in the default `warn` mode unless an active goal lacks evidence.
- `/flow:learn` records nothing under `.flow/`; `/flow:review` and `/flow:address` record a FlowRun but no goal.

Flow asks no consent question before writing local `.flow/` artifacts.

### Migrating the old `requireGoalForStart` flag

If your `.claude/settings.flow.json` set the v3.0 `flow.goals.requireGoalForStart` flag, it is honored via a **read-only** migration — your file is never rewritten:

| v3.0 setting | v3.1 behavior |
|---|---|
| `requireGoalForStart: true` | `goalCreation: always` |
| `requireGoalForStart: false` | `goalCreation: off` |
| absent | `goalCreation: auto` (default) |

To adopt the new key explicitly, replace `requireGoalForStart` with `goalCreation` in your settings.

### Opting out

- `goalCreation: off` — `/flow:start` won't auto-create goals (manual `/flow:goal create` still works); the pr/merge goal gate is disabled.
- `flow.goals.enabled: false` — disables the whole FlowGoal feature (Stop hook fast-paths, `/flow:goal` disabled).

## Tune goal behavior in optional steps

Each step is independent. Adopt them in the order below or skip ones that don't fit your workflow.

### Step 1 — Goals (on by default)

Goals are created automatically under `goalCreation: auto`. To require a goal on **every** `/flow:start` regardless of verifiable ACs, set `goalCreation: always`:

```json
{
  "flow": {
    "goals": {
      "goalCreation": "always",
      "executeVerificationCommands": true
    }
  }
}
```

`executeVerificationCommands: true` makes the Stop hook run every goal's `verification_command`, trusted or not. You rarely need it: goals created through flow are recorded in the per-user trust ledger (`bin/flow-goal-trust.sh`) and execute with the flag false; a goal that arrived with a checkout stays `not_executed` until you run `bin/flow-goal-trust.sh record --goal-file <goal>`. `/flow:goal evaluate` always executes verification commands when present.

Run `/flow:goal status` to confirm goal state. Walk through `flow-goals-quickstart.md` for a worked example.

### Step 2 — Enable active Stop-hook enforcement (optional)

Default mode (`warn`) is silent until a goal lacks evidence. Two stricter modes are available:

```json
{
  "flow": {
    "goals": {
      "stopHookEnforcement": "block"
    }
  }
}
```

- `block` — same checks as `warn`, but injects a `decision:block` so the incomplete-goal message becomes the next-turn prompt. $0/turn.
- `evaluator-loop` — spawns Haiku judge per turn, true `/goal` UX parity. ~$0.001/turn, throttled to 3 continuations / 5 min / session.

See `stop-hook-goal-enforcement.md` for the cost-vs-strictness comparison.

### Step 3 — Workflows (on by default, informational)

Workflow YAMLs are machine-readable process contracts for each `/flow:*` command (`plugins/flow/workflows/*.workflow.yaml`). `/flow:workflow list | inspect | validate | graph` introspects them. They have no effect on the commands themselves. To turn the feature off:

```json
{
  "flow": {
    "workflows": {
      "enabled": false
    }
  }
}
```

### Step 4 — Triggers and watch (on by default)

`/flow:trigger`, `/flow:watch` and `/flow:run` are available. `/flow:watch pr <N>` creates a `.flow/triggers/pr-<N>-watch.trigger.yaml` plus a `.claude/flow-loop-pr-<N>.md` prompt file you invoke manually via native `/loop`; `/flow:watch issue <N>` and `/flow:watch branch` create an issue watch and a branch watch the same way (see `commands/watch.md`). To turn the feature off:

```json
{
  "flow": {
    "triggers": {
      "enabled": false
    }
  }
}
```

Flow cannot invoke native `/loop` from plugin code — the generated prompt file is the handoff. See `flow-triggers.md`.

## Rolling back

To turn all four features off, **merge** the disable flags into your existing settings rather than overwriting the file (copying the snippet below verbatim into an existing `.claude/settings.flow.json` will wipe other keys like `agentTeams`, `tiers`, `conventions.commitTypes`):

```bash
# Use jq to merge the disable flags into the existing settings file:
jq '.flow.runtime.enabled = false |
    .flow.goals.enabled = false |
    .flow.workflows.enabled = false |
    .flow.triggers.enabled = false' \
   .claude/settings.flow.json > .claude/settings.flow.json.tmp \
  && mv .claude/settings.flow.json.tmp .claude/settings.flow.json
```

Or, if you prefer to edit by hand, ensure these keys exist alongside your other settings — do not replace the whole file:

```json
{
  "flow": {
    "runtime": { "enabled": false },
    "goals": { "enabled": false },
    "workflows": { "enabled": false },
    "triggers": { "enabled": false }
  }
}
```

The `.flow/` directory stays on disk (no destructive cleanup), and with these flags off flow creates no FlowRun or FlowGoal: `/flow:start` runs without either, and `/flow:pr` and `/flow:merge` apply no goal gate. `.claude/settings.flow.json` remains your project settings file, and every command reads it.

## What about the schema changes mentioned in the CHANGELOG?

3.0.0 adds six new JSON schemas under `plugins/flow/schemas/v1/`. These ship inside the plugin payload; existing v2 schemas at `plugins/flow/schemas/<skill>/input-schema.json` are unchanged. No migration is required for existing skill input contracts.

## What about my existing `.decisions/` journals?

Untouched. The FlowGoal and FlowRun features record four more artifact types (`goal-created`, `goal-evaluation`, `workflow-run`, `evidence-captured`) through the same `journal-record.sh` helper. Existing artifact types remain valid.
