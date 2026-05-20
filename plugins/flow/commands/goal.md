---
description: "Manage FlowGoal completion contracts — create, inspect, evaluate, pause/resume/clear. Use /flow:goal <subcommand> [args]; subcommands: status (default, no args), create <kind> [id], inspect <id>, evaluate <id>, pause <id>, resume <id>, clear <id>, history. Flow plugins cannot invoke native Claude /goal; this command is the project-local replacement."
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill, Agent
---

# /flow:goal — FlowGoal lifecycle management

Project-local replacement for the session-only Claude Code `/goal` built-in. Flow cannot invoke `/goal` from plugin code — instead this command writes durable `.flow/goals/<id>.goal.yaml` artifacts that the Stop hook (`flow-goal-stop.sh`), evaluator, and `/flow:status` all read.

## Required Skills

Invoke these skills as part of the subcommand workflows below:

- `goal-contract-capture` — every `create` subcommand
- `goal-evaluator` — every `evaluate` subcommand
- `goal-lifecycle` — every state-transition subcommand (pause, resume, clear, after evaluate)
- `goal-evidence-ledger` — when evaluator captures new evidence sidecars

## Pre-flight

Before any subcommand:

```bash
# Resolve flow.goals.enabled (default true in M2)
ENABLED=$("${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" \
  --default "true" '.flow.goals.enabled // empty')
if [ "$ENABLED" != "true" ]; then
  echo "flow.goals.enabled is false — /flow:goal is disabled in this project's settings cascade." >&2
  exit 0
fi

# Resolve stopHookEnforcement (warn | block | evaluator-loop)
STOP_MODE=$("${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" \
  --default "warn" '.flow.goals.stopHookEnforcement // empty')

mkdir -p .flow/goals
```

## Subcommands

### `/flow:goal` — default (no arguments)

Equivalent to `/flow:goal status`. Shows the active goal for the current branch/PR.

### `/flow:goal status`

Read-only summary of the active goal:

```bash
ACTIVE_GOAL=$(python3 - <<'PYEOF'
import sys, glob, yaml
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
for path in sorted(glob.glob('.flow/goals/*.goal.yaml')):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
        if data.get('lifecycle', {}).get('status') == 'active':
            print(path)
            break
    except Exception:
        continue
PYEOF
)
```

If no active goal: print `No active FlowGoal. Use /flow:goal create to start one.`

If active goal exists, format:

```
Active FlowGoal:   <id>
Outcome:           <objective.outcome>
Lifecycle:         <lifecycle.status> (turns: <turns_evaluated>/<max_iterations>)

Acceptance criteria:
  <id> <status>  <text> (evidence: <evidence_ref or 'pending'>)
  ...

Last evaluation:   <last_evaluation.at> — <last_evaluation.result>
Reason:            <last_evaluation.reason>

Stop hook mode:    <stopHookEnforcement value>
Next safe action:  /flow:goal evaluate <id>
```

### `/flow:goal create <kind> [id]`

Where `<kind>` is one of `issue | pr-review | pr-address | adhoc`. Dispatches to `goal-contract-capture` skill with the right invocation reason.

Examples:
- `/flow:goal create issue` — captures the issue from current branch (`feature/issue-{N}-...`), id defaults to `issue-{N}`
- `/flow:goal create issue 42` — explicit issue number
- `/flow:goal create pr-review 123` — captures review goal for PR #123
- `/flow:goal create pr-address 123` — captures address goal for PR #123
- `/flow:goal create adhoc <id>` — user-supplied outcome via AskUserQuestion

Workflow:
1. Resolve `<id>` from `<kind>` + branch state.
2. Pre-flight check: refuse if `.flow/goals/<id>.goal.yaml` already exists with non-terminal status.
3. Invoke `Skill(goal-contract-capture)` with the inputs documented in its SKILL.md.
4. After the skill writes the YAML, transition `lifecycle: draft → active` via `Skill(goal-lifecycle)`.
5. Print: `Created .flow/goals/<id>.goal.yaml (status: active).`

### `/flow:goal inspect <id>`

Read-only deep dump:
- Print the goal's full YAML frontmatter
- Print the last 3 entries from `.flow/runs/<run-id>/events.jsonl` filtered to events about this goal
- Print the transition log (lifecycle history) from the linked journal artifacts

### `/flow:goal evaluate <id>`

Invoke `Skill(goal-evaluator)` with `trigger=command`. The skill runs deterministic checks, optionally dispatches `Agent(goal-evaluator-judge)`, and transitions lifecycle. This is the primary user-facing way to advance a goal's state.

Print the resulting verdict + per-AC table. If lifecycle transitioned to `achieved`, print celebration. If `failed`, print the failing AC + suggested next action.

### `/flow:goal pause <id>`

Transition `active → waiting_for_user` via `Skill(goal-lifecycle)`. Use when stepping away mid-flow and the Stop hook should fall silent.

Reason for the lifecycle transition is collected via AskUserQuestion if not provided as `--reason "..."`.

### `/flow:goal resume <id>`

Transition `{waiting_for_user, waiting_for_ci, blocked} → active` via `Skill(goal-lifecycle)`. Used after the external condition is resolved (CI green, user responded, blocker fixed).

### `/flow:goal clear <id>`

Transition `<any non-terminal> → cancelled` via `Skill(goal-lifecycle)`. The goal YAML stays in `.flow/goals/` as audit trail; status is terminal.

Confirmation via AskUserQuestion is mandatory (Tier 2 action: cancels potentially in-flight work).

### `/flow:goal history`

List all `.flow/goals/*.goal.yaml` files with one line per goal:

```
<id>  <status>  <outcome (truncated)>  <created_at>
```

Filter via flag:
- `--status <enum>` — only goals in the given lifecycle status
- `--linked <issue|pr>` — only goals linked to a specific issue or PR

## Stop hook interaction

This command does NOT directly invoke the Stop hook. The Stop hook (`hooks/scripts/flow-goal-stop.sh`) fires on every conversation turn and reads the `.flow/goals/` directory independently. If the user runs `/flow:goal pause` or `/flow:goal clear`, the Stop hook silences itself on the next turn because no goal has `status: active`.

When `flow.goals.stopHookEnforcement: evaluator-loop`, the Stop hook spawns `Skill(goal-evaluator)` automatically — equivalent to running `/flow:goal evaluate <active>` after every turn, with throttling and budget enforcement.

## Architectural notes

- **No native /goal invocation.** This command exists because plugins cannot call Claude Code's native `/goal`. There is no `SlashCommand` tool; the only post-turn surface available to plugins is the `Stop` hook. See `references/stop-hook-goal-enforcement.md` for the full mechanism.
- **Tier classification.** `status`, `inspect`, `history` are read-only (Tier 1 — autonomous). `create`, `evaluate` are journal (Tier 2). `pause`, `resume`, `clear` are journal (Tier 2). NONE of this command's subcommands are Tier 3.
- **Coexistence with /flow:start.** When `flow.goals.requireGoalForStart: true` (default), `/flow:start <issue>` calls this command's `create issue <N>` internally after the Spec Validation Gate. Users running `/flow:start` never need to invoke `/flow:goal create` explicitly.

## Critical references

- `plugins/flow/skills/goal-contract-capture/SKILL.md` — contract authoring
- `plugins/flow/skills/goal-evaluator/SKILL.md` — evaluation loop
- `plugins/flow/skills/goal-lifecycle/SKILL.md` — state transitions
- `plugins/flow/agents/goal-evaluator-judge.md` — independent judge agent
- `plugins/flow/references/flow-goals.md` — user-facing FlowGoal model doc
- `plugins/flow/references/stop-hook-goal-enforcement.md` — Stop hook architecture
- `plugins/flow/schemas/v1/goal.schema.json` — the schema goals validate against
