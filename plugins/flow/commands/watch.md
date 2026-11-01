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
  printf '%s\n' "flow.triggers.enabled could not be read (cascade-resolve.sh exited $__cr_rc; its message is above), so /flow:watch stops here." >&2
  exit 1
fi
if [ "$ENABLED" != "true" ]; then
  printf '%s\n' "flow.triggers.enabled is false in your flow settings, so /flow:watch is turned off. Set it to true to use watch mode."
  exit 0
fi

# Never through a symlink: a repository can commit .flow as a link to a
# directory outside the checkout, where the trigger would then be written.
# Exit 1 is that refusal; exit 3 is a check that could not run (python3
# missing), which is not a symlink: say which, and create nothing.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-mkdir.sh" -- .flow/triggers || { [ $? -eq 3 ] && exit 3; exit 1; }
mkdir -p .claude
# The templates of the plugin, wherever flow is installed (never plugins/flow under
# the working directory, which only the flow repository itself has).
TEMPLATE_DIR="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/triggers/templates"
printf '%s\n' "TEMPLATE_DIR=$TEMPLATE_DIR"
```

## Subcommands

### `/flow:watch pr <N>`

Create a PR-watch trigger that monitors PR #N's CI + review state.

1. Read the template `pr-watch.trigger.yaml` in the `TEMPLATE_DIR` the pre-flight printed (the plugin root's `triggers/templates/`, resolved as `references/plugin-root-resolution.md` describes).
2. Substitute `${PR}` → N, `${REPO}` → from `gh repo view`, `${BRANCH}` → from PR metadata, `${NOW}` → current ISO timestamp.
3. Write to `.flow/triggers/pr-<N>-watch.trigger.yaml`.
4. Invoke `Skill(trigger-policy)` in `validate` mode. Abort on violation.
5. Generate `.claude/flow-loop-pr-<N>.md` with the watch-mode prompt.
6. Print the manual invocation instructions.

### `/flow:watch ci`

Create a CI-failure trigger that fires on CI status changes for the current branch.

1. Read the template `ci-failure.trigger.yaml` in the `TEMPLATE_DIR` the pre-flight printed.
2. Substitute `${BRANCH}` → the current branch (`git branch --show-current`; refuse a detached HEAD), `${BRANCH_SLUG}` → the branch name lowercased, each run of characters other than `a-z` and `0-9` replaced by one `-`, leading and trailing `-` removed, and cut to 53 characters (the trigger id `ci-failure-<slug>` must match `^[a-z0-9][a-z0-9-]{0,63}$`), `${REPO}` → from `gh repo view`, `${NOW}` → current ISO timestamp.
3. Write to `.flow/triggers/ci-failure-<slug>.trigger.yaml`. Do not overwrite an existing file.
4. Invoke `Skill(trigger-policy)` in `validate` mode. Abort on violation.
5. Generate `.claude/flow-loop-ci-failure-<slug>.md` with the watch-mode prompt.
6. Print the manual invocation instructions.

### `/flow:watch issue <N>`

Create an issue-watch trigger that follows issue #N, read-only on GitHub. Each iteration reads the issue; when its comments, labels, assignees or state changed since the last iteration, it writes a summary to the issue's decision journal and prints it; when the issue is assigned to you and has no branch, it suggests `/flow:start N`. It stops when the issue is closed.

1. Run the block below. It reads the repository and the issue's state from GitHub, refuses a closed issue, and runs `bin/flow-watch-create.sh`, which fills the plugin's `issue-watch.trigger.yaml` template (`${ISSUE}`, `${REPO}`, `${NOW}`), checks it against the schema and the trigger-policy rules, and writes `.flow/triggers/issue-<N>-watch.trigger.yaml` and the loop prompt `.claude/flow-loop-issue-<N>-watch.md` (from `issue-watch.loop.md`). An existing trigger is never overwritten (`WATCH_STATE=exists`).
2. Invoke `Skill(trigger-policy)` in `validate` mode on the trigger file. On a violation, delete both files and abort.
3. Print the manual invocation instructions (see Output).

```bash
# WATCH_ISSUE_BLOCK_BEGIN
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
WATCH_ARGS=$(printf '%s' "$_RAW" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//')
ISSUE_NUM=""
case "$WATCH_ARGS" in *" "*) ISSUE_NUM=${WATCH_ARGS#* } ;; esac
case "$ISSUE_NUM" in
  ''|*[!0-9]*|0*)
    printf '%s\n' "WATCH_STATE=refused"
    printf '%s\n' "REFUSED=\"give the issue number: /flow:watch issue <N>\""
    exit 1 ;;
esac
WATCH_CREATE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-watch-create.sh"
if [ ! -x "$WATCH_CREATE" ]; then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"flow-watch-create.sh missing or non-executable at $WATCH_CREATE — reinstall or upgrade the flow plugin\""
  exit 1
fi
if ! REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || [ -z "$REPO" ]; then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"gh could not name this repository\""
  exit 1
fi
if ! ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state --jq .state); then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"gh could not read issue #$ISSUE_NUM\""
  exit 1
fi
if [ "$ISSUE_STATE" != "OPEN" ]; then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"issue #$ISSUE_NUM is closed; there is nothing to watch\""
  exit 1
fi
"$WATCH_CREATE" --kind issue --repo "$REPO" --now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --issue "$ISSUE_NUM"
# WATCH_ISSUE_BLOCK_END
```

### `/flow:watch branch`

Create a branch-watch trigger for the current branch. Each iteration merges the default branch in when it has moved (a merge commit: never a rebase, never a force push), runs the quality checks, fixes failures the merge introduced, and commits and pushes. Merging a pull request, releasing, deleting a branch, force-pushing and rebasing are forbidden. It stops when the branch's pull request is merged or the branch is deleted.

1. Run the block below. It reads the current branch, the repository and its default branch, refuses the default branch itself and a detached HEAD, and runs `bin/flow-watch-create.sh`, which fills the plugin's `branch-watch.trigger.yaml` template (`${BRANCH}`, `${BRANCH_SLUG}` — the branch name made into an id —, `${DEFAULT_BRANCH}`, `${REPO}`, `${NOW}`), checks it against the schema and the trigger-policy rules, and writes `.flow/triggers/branch-<slug>-watch.trigger.yaml` and the loop prompt `.claude/flow-loop-branch-<slug>-watch.md` (from `branch-watch.loop.md`). An existing trigger is never overwritten (`WATCH_STATE=exists`).
2. Invoke `Skill(trigger-policy)` in `validate` mode on the trigger file. On a violation, delete both files and abort.
3. Print the manual invocation instructions (see Output).

```bash
# WATCH_BRANCH_BLOCK_BEGIN
WATCH_CREATE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-watch-create.sh"
if [ ! -x "$WATCH_CREATE" ]; then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"flow-watch-create.sh missing or non-executable at $WATCH_CREATE — reinstall or upgrade the flow plugin\""
  exit 1
fi
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"HEAD is detached; check out the branch to watch first\""
  exit 1
fi
if ! REPO_LINE=$(gh repo view --json nameWithOwner,defaultBranchRef --jq '.nameWithOwner + " " + .defaultBranchRef.name') \
   || [ -z "$REPO_LINE" ]; then
  printf '%s\n' "WATCH_STATE=refused"
  printf '%s\n' "REFUSED=\"gh could not name this repository and its default branch\""
  exit 1
fi
"$WATCH_CREATE" --kind branch --repo "${REPO_LINE%% *}" --now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --branch "$BRANCH" --default-branch "${REPO_LINE#* }"
# WATCH_BRANCH_BLOCK_END
```

## Generated loop-prompt content

For `issue <N>` and `branch`, the loop prompt comes from the plugin's `issue-watch.loop.md` and `branch-watch.loop.md` templates. For `pr <N>`, the generated `.claude/flow-loop-<id>.md` file contains:

```markdown
# Watch mode: <description>

You are running flow watch mode for <target>.

Read these files on each iteration:
- .flow/triggers/<id>.trigger.yaml — the trigger config (allowed_actions, stop_conditions, policy)
- .flow/goals/<linked-goal>.goal.yaml — the active FlowGoal, if any
- .flow/runs/ — latest run state for this branch/PR

Read none of them through a symlink: when .flow, .flow/goals, .flow/runs, a run directory or a file in it (run.yaml, last-verdict.json, events.jsonl) is one, skip it and say so.

On each iteration:
1. Check CI status (gh pr checks <N>)
2. Check unresolved review comments (gh pr view <N> --json reviewThreads)
3. If CI failed, diagnose: fetch failing job logs, propose a fix
4. If CI failed or review comments exist, run /flow:run trigger <id>: it checks the trigger's policy and runs the trigger's target (/flow:address <N>) once
5. If changes were made, run the workflow's verification from the FlowGoal contract
6. Commit and push only if the trigger's policy.allowed_actions permits
7. **Never merge**. **Never release**. Tier 3 actions are forbidden by trigger policy.
8. **Never create or modify triggers**. Recursion is denied by default.
9. Stop when ALL of these are true:
   - <stop_condition_1>
   - <stop_condition_2>
   - ...
10. Each /flow:run trigger <id> writes a trigger-fired artifact; an iteration with nothing to do runs nothing

When all stop conditions are met, exit cleanly with a summary.
```

## Output (after successful creation)

Shown for `pr <N>`; for `issue <N>` and `branch` the files are the `TRIGGER_FILE` and `LOOP_FILE` the block printed, and the trigger id is its `TRIGGER_ID`.

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

Paths below are relative to the flow plugin root (`references/plugin-root-resolution.md`).

- `triggers/templates/pr-watch.trigger.yaml` — PR watch template
- `triggers/templates/issue-watch.trigger.yaml` and `issue-watch.loop.md` — issue watch template and loop prompt
- `triggers/templates/branch-watch.trigger.yaml` and `branch-watch.loop.md` — branch watch template and loop prompt
- `triggers/templates/ci-failure.trigger.yaml` — CI failure template
- `triggers/templates/nightly-maintenance.trigger.yaml` — Maintenance template
- `bin/flow-watch-create.sh` — fills, checks and writes the issue and branch watches
- `commands/trigger.md` — `/flow:trigger` (manage triggers)
- `commands/run.md` — `/flow:run trigger <id>` (single-shot executor)
- `references/flow-triggers.md` — full trigger documentation

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read a template under the plugin root's `triggers/templates/` | 1 | Autonomous, read-only |
| Read the repository, issue state and current branch (`gh repo view`, `gh issue view`, `git branch`) | 1 | Autonomous, read-only |
| Substitute template variables (`${PR}`, `${ISSUE}`, `${REPO}`, `${BRANCH}`, `${BRANCH_SLUG}`, `${DEFAULT_BRANCH}`, `${NOW}`) | 1 | Autonomous |
| Write `.flow/triggers/<id>.trigger.yaml` (validated via `Skill(trigger-policy)`) | 2 | Journal-and-proceed — atomic write after validation |
| Write `.claude/flow-loop-<id>.md` (the prompt the user feeds to `/loop`) | 2 | Journal-and-proceed — produces a discrete artifact for `/loop` |
| Print manual invocation instructions for `/loop @<path>` | 1 | Autonomous, output-only |

`/flow:watch` never invokes `/loop` itself — the plugin model forbids native-slash invocation. The user must start the loop manually with the printed instruction.
