---
description: "Execute a FlowTrigger target ONCE. Subcommands: trigger <id>. Does NOT schedule future execution."
argument-hint: "trigger <id>"
allowed-tools: Bash, Read, Skill, AskUserQuestion
---

# /flow:run — single-shot trigger executor

When a FlowTrigger's target needs to run NOW (manual invocation, loop iteration, hook fire), `/flow:run trigger <id>` is the entry point. It validates the trigger against safety policy, checks concurrency, and dispatches the target command exactly once.

## Required Skills

- `trigger-policy` — enforce mode (every invocation).

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
  printf '%s\n' "flow.triggers.enabled could not be read (cascade-resolve.sh exited $__cr_rc; its message is above), so /flow:run stops here." >&2
  exit 1
fi
if [ "$ENABLED" != "true" ]; then
  printf '%s\n' "flow.triggers.enabled is false — /flow:run is turned off in your settings."
  exit 0
fi
```

## Subcommand: `/flow:run trigger <id>`

1. Read `.flow/triggers/<id>.trigger.yaml`. Error if not found.
2. Check `metadata.enabled: true`. Error if disabled.
3. Invoke `Skill(trigger-policy)` in `enforce` mode. Abort on violation (Tier 3 deny, recursion deny, etc.).
4. Check `concurrency.policy`:
   - `skip_if_running` (default) — if a previous run for this trigger is in flight (a run does not record which trigger started it — `run.yaml` has no trigger field — so check `.flow/runs/` for runs whose `metadata.workflow` is the trigger's `target.workflow` and whose `state.status` is `active`, and treat any such run as in flight; a run under a symlinked `.flow`, `.flow/runs` or run directory, or whose `run.yaml` is itself a symlink, is not read and counts as absent — `bin/flow-mkdir.sh --check` refuses the directories), exit 0 with a notice.
   - `queue` — queue the run (logs a journal artifact only; nothing holds the run for later execution).
   - `cancel_previous` — find any in-flight runs and transition them to `cancelled` before starting.
5. Invoke `target.command` from the trigger YAML.
6. After target completes, append a `trigger-fired` artifact to the linked decision journal.

## Recursion enforcement

Recursion is checked when the trigger is validated, not while the target runs. `recursion_policy.triggered_runs_may_create_triggers`, `_modify_triggers` and `_enable_triggers` default to `false`, and `trigger-policy` (step 3 above) rejects a trigger that sets any of them to `true`. No command, hook or script detects at run time that a command was started by a trigger, so nothing stops the target command from creating, enabling or modifying a trigger; do not do so while running a trigger's target.

The target command's actions keep their tiers: the `tier-gate.sh` hook applies to every Bash command, so push, PR creation, issue creation and issue assignment follow `tiers.push`, `tiers.prCreate`, `tiers.issueCreate` and `tiers.issueAssign`, and merge, release and pushing or deleting a tag always ask. In `claude -p` an ask is a refusal.

## Anti-patterns

- ❌ Bypassing trigger-policy validation. Triggers fire without supervision; policy is the only gate.
- ❌ Treating concurrency.skip_if_running as a no-op when a stuck active run exists. A stuck active run is surfaced as a warning; nothing detects stale runs automatically.

## Critical references

- `plugins/flow/skills/trigger-policy/SKILL.md` — enforcement gate.
- `plugins/flow/commands/trigger.md` — trigger management.
- `plugins/flow/commands/watch.md` — watch-mode trigger creation.
- `plugins/flow/schemas/v1/trigger.schema.json` — trigger schema.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read `.flow/triggers/<id>.trigger.yaml` and validate via `Skill(trigger-policy)` | 1 | Autonomous, read-only |
| Concurrency check against `.flow/runs/` for in-flight runs of this trigger | 1 | Autonomous, read-only |
| Invoke `target.command` (the trigger's nominated next-action) and append the `trigger-fired` journal artifact | 1 | Autonomous, local file write. The target's own actions keep their tiers: push, PR creation, issue creation and issue assignment follow `tiers.push`, `tiers.prCreate`, `tiers.issueCreate` and `tiers.issueAssign` (default `journal`: run and write one breadcrumb to the git-ignored auto-log trail; `autonomous` runs; `confirm` asks); merge, release and pushing or deleting a tag always ask. `trigger-policy` also refuses a trigger whose `forbidden_actions` does not list `merge` and `release`. |
| Cancel previous in-flight runs (when `concurrency.policy: cancel_previous`) | 1 | Autonomous, local file write — transitions other runs to `cancelled` |

`/flow:run` itself never enforces a Tier 3 action; the trigger-policy hard-deny on merge/release is non-negotiable.
