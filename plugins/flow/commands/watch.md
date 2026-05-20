---
description: "Create a FlowTrigger from a template AND generate a /loop prompt file the user invokes manually. Subcommands: pr <N>, ci, issue <N>, branch. Flow CANNOT invoke /loop from plugin code; this command prepares the prompt and tells the user how to start the loop themselves."
argument-hint: "<subcommand> [N]"
allowed-tools: Bash, Read, Write, AskUserQuestion, Skill
---

# /flow:watch — generate watch-mode trigger + loop prompt

Watch mode is flow's project-local replacement for "long-running monitoring of CI / PR / issue state." Plugins cannot invoke `/loop` directly, so this command does two things:

1. Creates a FlowTrigger YAML at `.flow/triggers/<id>.trigger.yaml` from a plugin-shipped template
2. Generates a loop-prompt file at `.claude/flow-loop-<id>.md` that the user invokes with `/loop @.claude/flow-loop-<id>.md`

The user manually starts the loop. Flow does NOT invoke `/loop` from plugin code.

## Required Skills

- `trigger-policy` — validates the generated trigger conforms to safety policy.

## Pre-flight

```bash
ENABLED=$("${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" \
  --default "false" '.flow.triggers.enabled // empty')
if [ "$ENABLED" != "true" ]; then
  echo "flow.triggers.enabled is false — /flow:watch is opt-in."
  exit 0
fi

mkdir -p .flow/triggers .claude
```

## Subcommands

### `/flow:watch pr <N>`

Create a PR-watch trigger that monitors PR #N's CI + review state.

1. Read template `plugins/flow/triggers/templates/pr-watch.trigger.yaml`.
2. Substitute `${PR}` → N, `${REPO}` → from `gh repo view`, `${BRANCH}` → from PR metadata, `${NOW}` → current ISO timestamp.
3. Write to `.flow/triggers/pr-<N>-watch.trigger.yaml`.
4. Invoke `Skill(trigger-policy)` in `validate` mode. Abort on violation.
5. Generate `.claude/flow-loop-pr-<N>.md` with the watch-mode prompt.
6. Print the manual invocation instructions.

### `/flow:watch ci`

Create a CI-failure trigger that fires on CI status changes for the current branch.

### `/flow:watch issue <N>`

Create an issue-watch trigger that monitors issue #N for status changes.

### `/flow:watch branch`

Create a branch-watch trigger for the current branch (general maintenance).

## Generated loop-prompt content

The generated `.claude/flow-loop-<id>.md` file contains:

```markdown
# Watch mode: <description>

You are running flow watch mode for <target>.

Read these files on each iteration:
- .flow/triggers/<id>.trigger.yaml — the trigger config (allowed_actions, stop_conditions, policy)
- .flow/goals/<linked-goal>.goal.yaml — the active FlowGoal, if any
- .flow/runs/ — latest run state for this branch/PR

On each iteration:
1. Check CI status (gh pr checks <N>)
2. Check unresolved review comments (gh pr view <N> --json reviewThreads)
3. If CI failed, diagnose: fetch failing job logs, propose a fix
4. If review comments exist, run /flow:address <N>
5. If changes were made, run the workflow's verification from the FlowGoal contract
6. Commit and push only if the trigger's policy.allowed_actions permits
7. **Never merge**. **Never release**. Tier 3 actions are forbidden by trigger policy.
8. **Never create or modify triggers**. Recursion is denied by default.
9. Stop when ALL of these are true:
   - <stop_condition_1>
   - <stop_condition_2>
   - ...
10. Record each iteration via /flow:run trigger <id> (writes a trigger-fired artifact)

When all stop conditions are met, exit cleanly with a summary.
```

## Output (after successful creation)

```text
Created .flow/triggers/pr-<N>-watch.trigger.yaml
Created .claude/flow-loop-pr-<N>.md

To start watch mode manually, invoke:

  /loop @.claude/flow-loop-pr-<N>.md

Flow cannot invoke /loop from a plugin. The /loop command is a Claude Code
built-in; only you can start it. The trigger YAML records that you're
watching this PR; the prompt file gives /loop the per-iteration instructions.

To stop watch mode: Ctrl-C the /loop, or invoke /flow:trigger disable pr-<N>-watch.
```

## Architectural notes

- **The prompt is the loop's source of truth.** Flow's trigger YAML stays static (read by each iteration); the prompt file tells the loop what to DO each iteration.
- **No native /loop invocation by plugin.** Repeated explicitly in the output because the constraint is the entire reason this command exists.
- **Stop conditions are evaluated in the prompt, not by the plugin.** The loop iterations check `gh pr checks` etc. and stop themselves when the conditions are met.

## Critical references

- `plugins/flow/triggers/templates/pr-watch.trigger.yaml` — PR watch template
- `plugins/flow/triggers/templates/ci-failure.trigger.yaml` — CI failure template
- `plugins/flow/triggers/templates/nightly-maintenance.trigger.yaml` — Maintenance template
- `plugins/flow/commands/trigger.md` — `/flow:trigger` (manage triggers)
- `plugins/flow/commands/run.md` — `/flow:run trigger <id>` (single-shot executor)
- `plugins/flow/references/flow-triggers.md` — full trigger documentation
