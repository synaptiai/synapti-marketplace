# Hello, FlowTrigger — quickstart

A 5-minute walkthrough of `/flow:trigger` and `/flow:watch`. By the end you'll have a PR-watch trigger that monitors a real (or synthetic) PR's CI + review state, with the loop running under your explicit control.

## Prerequisites

- flow installed (`claude plugins list | grep flow`)
- A git repository with at least one open PR (or willingness to create a synthetic one)
- `gh` CLI authenticated (`gh auth status` exits 0)
- `python3` with `PyYAML` available

## Step 1 — Check that triggers are on

Triggers are on by default (`flow.triggers.enabled: true`). If your settings turned them off, turn them back on:

```bash
jq '.flow.triggers.enabled = true' .claude/settings.flow.json > /tmp/s && mv /tmp/s .claude/settings.flow.json
```

Verify:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh" --default "true" '.flow.triggers.enabled'
# expect: true
```

## Step 2 — Pick a PR to watch

Note any PR number. For this walkthrough I'll use `PR=42`. If you don't have a real PR, create a synthetic one:

```bash
git checkout -b feature/synthetic-pr-test
printf '%s\n' "test" > test-file.txt
git add test-file.txt
git commit -m "test: synthetic PR for /flow:watch quickstart"
git push -u origin HEAD
gh pr create --title "Synthetic PR for /flow:watch test" --body "Quickstart artifact — close when done."
```

## Step 3 — Create a watch trigger

```text
/flow:watch pr 42
```

This does two things:

1. **Reads the template** at `plugins/flow/triggers/templates/pr-watch.trigger.yaml` and substitutes `${PR}`, `${REPO}`, `${BRANCH}`, `${NOW}`.
2. **Writes** `.flow/triggers/pr-42-watch.trigger.yaml` (the trigger) and `.claude/flow-loop-pr-42.md` (the loop prompt).

The trigger gets validated by `Skill(trigger-policy)` before write:
- Schema shape check
- `policy.forbidden_actions` MUST contain both `merge` and `release` — non-negotiable
- `recursion_policy` MUST deny: triggered runs can't modify or enable triggers, and can't create them unless `flow.triggers.allowTriggerCreationFromTriggeredRun` is true in your user settings
- `target.workflow` must resolve to an existing workflow YAML

If any check fails, the trigger is rejected and you see the violation. Fix the template or use a different one.

## Step 4 — Inspect what was created

```text
/flow:trigger inspect pr-42-watch
```

You'll see the trigger YAML:

```yaml
apiVersion: flow.synapti.ai/v1
kind: FlowTrigger
metadata:
  id: pr-42-watch
  enabled: true
trigger:
  type: loop_prompt
target:
  workflow: address-pr
  goal: pr-42-address
  command: '/flow:address 42'
policy:
  forbidden_actions:
    - merge
    - release
recursion_policy:
  triggered_runs_may_create_triggers: false
concurrency:
  policy: skip_if_running
```

And the loop prompt at `.claude/flow-loop-pr-42.md` contains the per-iteration instructions: check CI, check unresolved review comments, run `/flow:address` if comments exist, never merge, never release, stop when CI is green + zero unresolved threads.

## Step 5 — Start watch mode manually

Flow **cannot** invoke `/loop` from plugin code (architectural constraint of the Claude Code plugin model). You start it yourself:

```text
/loop @.claude/flow-loop-pr-42.md
```

The loop runs the per-iteration instructions until the stop conditions in the prompt are met. Each iteration:

1. Checks the PR's CI + review threads
2. If CI failed or review comments exist, runs `/flow:run trigger pr-42-watch`, which checks the trigger's policy and runs its target, `/flow:address 42`, once
3. If CI failed, diagnoses and proposes a fix
4. Each `/flow:run trigger` the loop runs records a `trigger-fired` artifact in the decision journal; an iteration with nothing to do records nothing
5. Checks the stop conditions; exits cleanly when they're met

The trigger YAML stays static (it's the policy contract); the loop prompt is the executable per-iteration behavior.

## Step 6 — Manage triggers

```text
/flow:trigger list             # show all triggers (plugin templates + project-local)
/flow:trigger disable pr-42-watch   # toggle metadata.enabled to false (/flow:run trigger then refuses to fire it)
/flow:trigger enable pr-42-watch    # re-enable (validates trigger-policy before flipping)
/flow:trigger run pr-42-watch       # single-shot execution of target.command (does NOT loop)
/flow:trigger delete pr-42-watch    # remove trigger YAML (AskUserQuestion confirmation required)
```

To stop watch mode, Ctrl-C the `/loop` invocation. `/flow:trigger disable pr-42-watch` makes `/flow:run trigger pr-42-watch` refuse to fire the trigger, but the loop prompt does not check `metadata.enabled`, so the `/loop` keeps running until you stop it.

## Step 7 — Single-shot execution

If you don't want a loop and just want to execute the trigger's target once:

```text
/flow:run trigger pr-42-watch
```

This invokes the trigger's `target.command` exactly once. Trigger-policy still refuses a trigger whose policy allows `merge` or `release`, and the tier hook asks before any merge or release the target runs.

## Common gotchas

- **Triggers describe wake-up intent; they don't guarantee background execution.** Only `manual | hook | loop_prompt` are in the default `flow.triggers.allowedTypes`. The runner-backed types (`github_actions`, `local_cron`, `local_daemon`) are valid schema, but flow ships no runner for them — adding them to `flow.triggers.allowedTypes` is a separate decision per project.
- **Recursion deny is a default, not a suggestion.** A trigger that fires `/flow:run trigger pr-42-watch` cannot also create new triggers. The trigger-policy skill refuses a trigger with `recursion_policy.triggered_runs_may_create_triggers: true` unless your user settings set `flow.triggers.allowTriggerCreationFromTriggeredRun` to `true` (a repository's own settings cannot), and refuses `_modify_triggers` or `_enable_triggers: true` whatever the setting.
- **maxActiveTriggers caps growth.** Default 5 active triggers per project. Hitting the cap requires `/flow:trigger disable <existing>` before creating a new one. The cascade-resolved `flow.triggers.maxActiveTriggers` setting can raise it.

## Next steps

- [`flow-triggers.md`](flow-triggers.md) — full FlowTrigger model + lifecycle + safety contract
- [`flow-workflows-quickstart.md`](flow-workflows-quickstart.md) — companion walkthrough for `/flow:workflow`
- [`flow-goals-quickstart.md`](flow-goals-quickstart.md) — companion walkthrough for `/flow:goal`
- [`../schemas/v1/trigger.schema.json`](../schemas/v1/trigger.schema.json) — schema source of truth
- [`../skills/trigger-policy/SKILL.md`](../skills/trigger-policy/SKILL.md) — safety enforcement detail
- [`../triggers/templates/`](../triggers/templates/) — plugin-shipped templates (pr-watch, ci-failure, issue-watch, branch-watch, nightly-maintenance)
