# Migrating from flow v2.x to v3.0

flow v3.0 is **purely additive**. Existing v2.x projects upgrade with zero behavioral change unless you opt in. This guide walks through enabling v3 features one at a time.

## What changes when you upgrade (v3.1)

v3.1 makes FlowGoals **invisible-by-default**: `flow.goals.goalCreation` defaults to `auto`, so goal/run/evidence artifacts are recorded for you rather than gated behind an opt-in. After upgrading without editing settings:

- `/flow:start <issue>` creates `.flow/goals/issue-<N>.goal.yaml` whenever the Spec Validation Gate passes with **≥1 acceptance criterion carrying a `verification_command`**. An issue that yields zero verifiable ACs (e.g. a spec-free `documentation`/`chore` issue) creates **no** goal, silently. All artifacts are local under `.flow/` — nothing is pushed, posted, or sent.
- `/flow:status` surfaces the active goal/run; `/flow:pr` and `/flow:merge` gate on goal **existence** — a branch whose goal isn't `achieved` is held back, but a branch with **no** goal is not blocked.
- The Stop hook fires but stays silent in the default `warn` mode unless an active goal lacks evidence.
- `/flow:learn`, `/flow:review`, `/flow:address` behave as before (review/address record a FlowRun but no user-facing goal).

There is **no consent prompt** — the v3.0 first-run onboarding `AskUserQuestion` was retired in v3.1. Writing local `.flow/` artifacts needs no confirmation.

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

`executeVerificationCommands: true` lets `/flow:goal evaluate` auto-run each AC's `verification_command`. Without it, evaluator returns `not_executed` and you must capture evidence manually.

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

### Step 3 — Enable workflows (optional, mostly informational)

Workflow YAMLs are machine-readable process contracts for each `/flow:*` command (`plugins/flow/workflows/*.workflow.yaml`). Enabling the feature lets you run `/flow:workflow list | inspect | validate | graph` to introspect them.

```json
{
  "flow": {
    "workflows": {
      "enabled": true
    }
  }
}
```

Recommended if you want to audit the process flow before each command. Has no effect on the commands themselves.

### Step 4 — Enable triggers + watch (optional)

Adds `/flow:trigger`, `/flow:watch`, and `/flow:run`. `/flow:watch pr <N>` creates a `.flow/triggers/pr-<N>-watch.trigger.yaml` plus a `.claude/flow-loop-pr-<N>.md` prompt file you invoke manually via native `/loop`.

```json
{
  "flow": {
    "triggers": {
      "enabled": true
    }
  }
}
```

Flow cannot invoke native `/loop` from plugin code — the generated prompt file is the handoff. See `flow-triggers.md`.

## Rolling back

If you opt in and decide v3 isn't a fit, **merge** the disable flags into your existing settings rather than overwriting the file (copying the snippet below verbatim into an existing `.claude/settings.flow.json` will wipe other keys like `agentTeams`, `tiers`, `conventions.commitTypes`):

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

`.flow/` directory and `.claude/settings.flow.json` stay on disk (no destructive cleanup) but no command reads them. `/flow:start` reverts to v2.4 behavior on the next invocation.

## What about the schema changes mentioned in the CHANGELOG?

3.0.0 adds six new JSON schemas under `plugins/flow/schemas/v1/`. These ship inside the plugin payload; existing v2 schemas at `plugins/flow/schemas/<skill>/input-schema.json` are unchanged. No migration is required for existing skill input contracts.

## What about my existing `.decisions/` journals?

Untouched. v3 adds new artifact types (`goal-created`, `goal-evaluation`, `workflow-run`, `activity-completed`, `evidence-captured`, `trigger-created`, `trigger-fired`, `run-state-transition`) appended via the same `journal-record.sh` helper. Old artifact types remain valid.
