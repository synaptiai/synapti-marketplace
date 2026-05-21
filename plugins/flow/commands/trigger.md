---
description: "Manage FlowTrigger artifacts at .flow/triggers/. Subcommands: list, inspect <id>, enable <id>, disable <id>, run <id>, delete <id>. Triggers describe wake-up intent; they do NOT guarantee background execution."
argument-hint: "<subcommand> [id]"
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill
---

# /flow:trigger — FlowTrigger management

Flow cannot invoke native `/loop`, scheduled tasks, or any external runner from plugin code. FlowTrigger artifacts at `.flow/triggers/<id>.trigger.yaml` describe **wake-up intent** — they declare when flow SHOULD resume work and what command to invoke, but actual execution requires manual user invocation (v3.0: manual | hook | loop_prompt) or an external runner (v3.1+: github_actions | local_cron).

## Required Skills

- `trigger-policy` — every subcommand that creates / enables / runs a trigger.

## Pre-flight

```bash
ENABLED=$("${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" \
  --default "false" '.flow.triggers.enabled')
if [ "$ENABLED" != "true" ]; then
  echo "flow.triggers.enabled is false — /flow:trigger is opt-in." >&2
  echo "Enable in .claude/settings.flow.local.json: { \"flow\": { \"triggers\": { \"enabled\": true } } }"
  exit 0
fi

mkdir -p .flow/triggers
```

## Subcommands

### `/flow:trigger list`

List all triggers (plugin-shipped templates + project-local).

### `/flow:trigger inspect <id>`

Print the trigger YAML's full contents.

### `/flow:trigger enable <id>` / `/flow:trigger disable <id>`

Toggle `metadata.enabled` in the trigger YAML. Atomic via `_journal_atomic.py` lock acquisition.

Before enabling: invoke `Skill(trigger-policy)` in `validate` mode. Refuse to enable if policy violations exist.

### `/flow:trigger run <id>`

Execute the target command ONCE. Does NOT schedule future execution. Sequence:

1. Invoke `Skill(trigger-policy)` in `enforce` mode. Abort on policy violation.
2. Check `concurrency.policy` — if `skip_if_running` and a prior run is in flight, exit 0 with a notice.
3. Set the env var `FLOW_TRIGGERED_RUN=true` so the target command knows it was trigger-fired (recursion_policy applies).
4. Invoke `target.command` (e.g., `/flow:run trigger pr-123-watch` which itself delegates to the trigger's workflow).
5. Append a `trigger-fired` artifact to the linked decision journal.

### `/flow:trigger delete <id>`

Remove the trigger YAML. Confirmation via AskUserQuestion (Tier 2 — irreversible removal of a possibly-enabled trigger).

## Architectural notes

- **No native /loop invocation.** This is the canonical project-local replacement.
- **Recursion deny by default.** `recursion_policy.triggered_runs_may_create_triggers: false` is the default; flipping to true requires explicit AskUserQuestion.
- **Tier 3 forbidden.** `policy.forbidden_actions` MUST include both `merge` and `release`. The `trigger-policy` skill rejects triggers that don't.

## Critical references

- `plugins/flow/skills/trigger-policy/SKILL.md` — safety enforcement.
- `plugins/flow/schemas/v1/trigger.schema.json` — trigger document schema.
- `plugins/flow/triggers/templates/` — plugin-shipped templates.
- `plugins/flow/commands/watch.md` — `/flow:watch` (creates triggers from templates).
- `plugins/flow/commands/run.md` — `/flow:run trigger <id>` (single-shot executor).
- `plugins/flow/references/flow-triggers.md` — user-facing documentation.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| `/flow:trigger list` / `inspect <id>` — read `.flow/triggers/` | 1 | Autonomous, read-only |
| `/flow:trigger enable <id>` / `disable <id>` — toggle `metadata.enabled` after validation | 2 | Journal-and-proceed — `Skill(trigger-policy)` validates before write; atomic via `_journal_atomic.py` |
| `/flow:trigger run <id>` — single-shot execution of target | 2 | Journal-and-proceed — delegates to `/flow:run trigger <id>`; tier3-forbidden actions remain blocked by `trigger-policy` |
| `/flow:trigger delete <id>` — irreversible removal of trigger YAML | 2 | **Confirm** via AskUserQuestion (deletes a possibly-enabled trigger) |
