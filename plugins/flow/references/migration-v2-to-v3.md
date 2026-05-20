# Migrating from flow v2.x to v3.0

flow v3.0 is **purely additive**. Existing v2.x projects upgrade with zero behavioral change unless you opt in. This guide walks through enabling v3 features one at a time.

## What "no change" means

After upgrading to v3.0 without editing settings:

- `/flow:start <issue>` runs exactly as in v2.x — no goal is created, no `.flow/` directory appears.
- The Stop hook fires but exits silently (default mode is `warn`, and `warn` is itself silent when no active FlowGoal exists).
- `/flow:status`, `/flow:learn`, `/flow:pr`, `/flow:merge`, `/flow:review`, `/flow:address` behave identically to v2.4.
- No new files are created in your repo.

The new v3 commands (`/flow:goal`, `/flow:resume`, `/flow:workflow`, `/flow:trigger`, `/flow:watch`, `/flow:run`) are available but only have effect when their feature flags are enabled.

## Enable v3 in four optional steps

Each step is independent. Adopt them in the order below or skip ones that don't fit your workflow.

### Step 1 — Enable goals (recommended starting point)

Adds durable completion contracts to `/flow:start`. After the Spec Validation Gate passes, a `.flow/goals/issue-<N>.goal.yaml` is created with `lifecycle.status: active`. `/flow:pr` and `/flow:merge` will require the goal to be `achieved` before proceeding (override path: six-field escalation).

Add to `.claude/settings.flow.json` (create the file if it doesn't exist):

```json
{
  "flow": {
    "goals": {
      "requireGoalForStart": true,
      "executeVerificationCommands": true
    }
  }
}
```

`executeVerificationCommands: true` lets `/flow:goal evaluate` auto-run each AC's `verification_command`. Without it, evaluator returns `not_executed` and you must capture evidence manually.

Run `/flow:goal status` to confirm v3 is on. Walk through `flow-goals-quickstart.md` for a worked example.

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

If you opt in and decide v3 isn't a fit:

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
