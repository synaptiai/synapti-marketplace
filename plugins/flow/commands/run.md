---
description: "Execute a FlowTrigger target ONCE. Subcommands: trigger <id>. Does NOT schedule future execution. Use /flow:run trigger <id>."
allowed-tools: Bash, Read, Skill, AskUserQuestion
---

# /flow:run — single-shot trigger executor

When a FlowTrigger's target needs to run NOW (manual invocation, loop iteration, hook fire), `/flow:run trigger <id>` is the entry point. It validates the trigger against safety policy, checks concurrency, and dispatches the target command exactly once.

## Required Skills

- `trigger-policy` — enforce mode (every invocation).

## Pre-flight

```bash
ENABLED=$("${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" \
  --default "false" '.flow.triggers.enabled // empty')
[ "$ENABLED" != "true" ] && { echo "flow.triggers.enabled is false"; exit 0; }
```

## Subcommand: `/flow:run trigger <id>`

1. Read `.flow/triggers/<id>.trigger.yaml`. Error if not found.
2. Check `metadata.enabled: true`. Error if disabled.
3. Invoke `Skill(trigger-policy)` in `enforce` mode. Abort on violation (Tier 3 deny, recursion deny, etc.).
4. Check `concurrency.policy`:
   - `skip_if_running` (default) — if a previous run for this trigger is in flight (check `.flow/runs/` for runs with metadata.trigger=<id> and state.status=active), exit 0 with a notice.
   - `queue` — queue the run (M5 logs a journal artifact; full queue is M6+).
   - `cancel_previous` — find any in-flight runs and transition them to `cancelled` before starting.
5. Set env var `FLOW_TRIGGERED_RUN=true` (target commands consult this for recursion policy enforcement).
6. Invoke `target.command` from the trigger YAML.
7. After target completes, append a `trigger-fired` artifact to the linked decision journal.

## Recursion enforcement

When `FLOW_TRIGGERED_RUN=true`:
- The target command's pre-flight check refuses to create / enable / modify triggers (unless `recursion_policy.triggered_runs_may_*` is true, which requires explicit AskUserQuestion at trigger-creation time).
- The target command's tier classification has `merge` and `release` hard-overridden to `confirm` regardless of trigger settings.

## Anti-patterns

- ❌ Bypassing trigger-policy validation. Triggers fire without supervision; policy is the only gate.
- ❌ Treating concurrency.skip_if_running as a no-op when a stuck active run exists. M6 adds a "stale run" detection; M5 surfaces this as a warning.
- ❌ Allowing FLOW_TRIGGERED_RUN to be set when not actually triggered. Manual invocation must NOT set the env var.

## Critical references

- `plugins/flow/skills/trigger-policy/SKILL.md` — enforcement gate.
- `plugins/flow/commands/trigger.md` — trigger management.
- `plugins/flow/commands/watch.md` — watch-mode trigger creation.
- `plugins/flow/schemas/v1/trigger.schema.json` — trigger schema.
