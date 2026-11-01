---
description: "Manage FlowTrigger artifacts at .flow/triggers/. Subcommands: list, inspect <id>, enable <id>, disable <id>, run <id>, delete <id>. Triggers describe wake-up intent; they do NOT guarantee background execution."
argument-hint: "<subcommand> [id]"
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill
---

# /flow:trigger — FlowTrigger management

Flow cannot invoke native `/loop`, scheduled tasks, or any external runner from plugin code. FlowTrigger artifacts at `.flow/triggers/<id>.trigger.yaml` describe **wake-up intent** — they declare when flow SHOULD resume work and what command to invoke, but actual execution requires manual user invocation (trigger types manual, hook, loop_prompt). The schema also defines github_actions and local_cron, but no runner for them ships and `flow.triggers.allowedTypes` excludes them by default.

## Required Skills

- `trigger-policy` — every subcommand that creates / enables / runs a trigger.

```!
# Inline the Required Skills above so their rules are in context before the
# first phase runs (commands cannot preload skills from frontmatter). Ambient
# skills load whole; dispatched skills (context: fork / agent:) load their
# `## Contract` section and run in full when this command invokes
# Skill(<name>). Output per `references/command-output-format.md`.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-load-skills.sh" trigger-policy

true
```

## Pre-flight

```bash
# A non-zero exit means the setting could not be read (cascade-resolve.sh
# says why on stderr): that is not the same as false, so say so and stop.
__cr_rc=0
ENABLED=$("$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh" \
  --default "true" '.flow.triggers.enabled') || __cr_rc=$?
if [ "$__cr_rc" -ne 0 ]; then
  printf '%s\n' "flow.triggers.enabled could not be read (cascade-resolve.sh exited $__cr_rc; its message is above), so /flow:trigger stops here." >&2
  exit 1
fi
if [ "$ENABLED" != "true" ]; then
  printf '%s\n' "flow.triggers.enabled is false — /flow:trigger is turned off in your settings." >&2
  printf '%s\n' "Turn it back on in .claude/settings.flow.local.json: { \"flow\": { \"triggers\": { \"enabled\": true } } }"
  exit 0
fi

# Never through a symlink: a repository can commit .flow as a link to a
# directory outside the checkout, where the trigger would then be written.
# Exit 1 is that refusal; exit 3 is a check that could not run (python3
# missing), which is not a symlink: say which, and create nothing.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-mkdir.sh" -- .flow/triggers || { [ $? -eq 3 ] && exit 3; exit 1; }
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

Execute the target command ONCE. Does NOT schedule future execution. Run it exactly as `/flow:run trigger <id>` does (`commands/run.md`): validate the trigger with `Skill(trigger-policy)` in `enforce` mode and abort on a violation, run the concurrency check below and apply its `CONCURRENCY_POLICY` to its `IN_FLIGHT` runs as `/flow:run` step 4 says, invoke the trigger's `target.command` (for a PR watch, `/flow:address <N>`) so that the FlowRun it creates records `metadata.trigger: <id>`, and append a `trigger-fired` artifact to the linked decision journal.

```bash
# TRIGGER_RUN_CONCURRENCY_BLOCK_BEGIN
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
RUN_ARGS=$(printf '%s' "$_RAW" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//')
TRIGGER_ID=""
case "$RUN_ARGS" in *" "*) TRIGGER_ID=${RUN_ARGS#* } ;; esac
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-trigger-concurrency.sh" "$TRIGGER_ID"
# TRIGGER_RUN_CONCURRENCY_BLOCK_END
```

### `/flow:trigger delete <id>`

Remove the trigger YAML. Confirmation via AskUserQuestion (Tier 3 — irreversible removal of a possibly-enabled trigger).

## Architectural notes

- **No native /loop invocation.** This is the canonical project-local replacement.
- **Recursion denied.** `recursion_policy.triggered_runs_may_create_triggers`, `_modify_triggers` and `_enable_triggers` default to `false`, and `trigger-policy` rejects a trigger that sets any of them to `true`. Nothing checks at run time whether a triggered command creates, enables or modifies a trigger.
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
| `/flow:trigger enable <id>` / `disable <id>` — toggle `metadata.enabled` after validation | 1 | Autonomous, local file write — `Skill(trigger-policy)` validates before write; atomic via `_journal_atomic.py` |
| `/flow:trigger run <id>` — single-shot execution of target | 1 | Autonomous, as `/flow:run trigger <id>`; the target command's own actions keep their tiers (push, PR creation, issue creation and issue assignment follow `tiers.*`; merge, release and pushing or deleting a tag always ask), and `trigger-policy` refuses a trigger that does not forbid merge and release |
| `/flow:trigger delete <id>` — irreversible removal of trigger YAML | 3 | **Confirm** via AskUserQuestion (deletes a possibly-enabled trigger) |
