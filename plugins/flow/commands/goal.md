---
description: "Manage FlowGoal completion contracts — create, inspect, evaluate, pause/resume/clear, history. Use when starting a goal-driven task, when checking active-goal state, or when finalizing the verdict after evidence is collected. Captures acceptance criteria with verification commands, runs deterministic checks, and dispatches the goal-evaluator-judge for fuzzy criteria."
argument-hint: "[subcommand] [args]"
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
# Resolve flow.goals.enabled (default true)
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
Delta:             <made_progress | unchanged | regressed>  (from .flow/runs/<run-id>/last-verdict.json — see references/flow-goals.md § Verdict delta semantics)

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

After the skill produces a verdict, **the command (not the skill) persists it via `bin/flow-record-verdict.sh`**. The skill returns the structured verdict in-memory; the command is the single owner of the write. This eliminates the prior double-write where both the skill's Step 8 and the command's heredoc wrote sequentially, with the command's write silently winning. See `skills/goal-evaluator/SKILL.md` Step 8 for the current contract.

```bash
# After Skill(goal-evaluator) returns the structured verdict, write it
# to a temp JSON file and invoke the helper. The skill does NOT write —
# this command is the canonical caller. The Stop-hook evaluator-loop is
# the OTHER caller (it computes its own verdict via the judge subprocess
# and calls the same helper). Two callers, one helper, one write per turn.
TMP=$(mktemp -t flow-verdict.XXXXXX.json)
trap 'rm -f "$TMP"' EXIT
jq -n \
  --arg v "<verdict>" \
  --argjson c <confidence> \
  --arg d "<delta>" \
  --arg r "<reason>" \
  --arg h "<next_step_hint>" \
  '{verdict:$v, confidence:$c, delta:$d, reason:$r, next_step_hint:$h, source:"command"}' > "$TMP"
"${CLAUDE_PLUGIN_ROOT}/bin/flow-record-verdict.sh" \
  --run-id "<run-id-from-goal.scope.run_id>" \
  --verdict-file "$TMP" \
  || echo "command: last-verdict.json write failed; next turn's delta will be 'unchanged'" >&2
```

Skipping the write breaks delta computation for the next turn (everything becomes "unchanged"). Helper failure is **non-fatal** — surface to stderr via the `||` clause, never abort the command's lifecycle update.

**F10 — Terminal-transition Tier 2 confirmation**:

When `Skill(goal-evaluator)` returns a `proposed_transition` to `achieved` or `failed`, the command (NOT the skill) is responsible for writing the terminal lifecycle status — gated by AskUserQuestion. The skill leaves the goal at its current non-terminal status; this step finalizes (or rejects) the transition.

```text
AskUserQuestion: "FlowGoal $GOAL_ID evaluation produced verdict: <achieved|failed>.
                  Confirm transition to terminal status '<proposed_to>'?
                  Reason: <proposed_reason>"

Options:
  1. Confirm — write the terminal lifecycle status now (recommended when the verdict matches your expectations)
  2. Re-evaluate — invoke /flow:goal evaluate again (use when you expect more progress on the next run)
  3. Cancel — keep the goal at its current non-terminal status (use when the verdict feels premature or you want to pause)
```

On **Confirm**, write the lifecycle update:

```bash
LIFE_TMP=$(mktemp -t flow-lifecycle.XXXXXX.yaml)
trap 'rm -f "$LIFE_TMP"' EXIT
cat > "$LIFE_TMP" <<EOF
status: ${PROPOSED_TO}
last_evaluation:
  result: ${VERDICT_RESULT}
  reason: ${PROPOSED_REASON}
  at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
"${CLAUDE_PLUGIN_ROOT}/bin/flow-goal-record.sh" --update-lifecycle \
  --goal-id "$GOAL_ID" \
  --lifecycle-file "$LIFE_TMP" \
  --from-status "$CURRENT_FROM_STATUS"
```

On **Re-evaluate**, recursively invoke `/flow:goal evaluate $GOAL_ID` for another pass.

On **Cancel**, exit cleanly. The goal stays at its current non-terminal status; the verdict has been persisted to `last-verdict.json` (so next-turn delta is correct) but lifecycle is unchanged.

For **non-terminal transitions** (`active`, `blocked`, `waiting_for_user`, `waiting_for_ci`), the skill writes lifecycle itself per Step 6 of `goal-evaluator/SKILL.md` — no AskUserQuestion is needed for these reversible states.

Print the resulting verdict + per-AC table. If lifecycle transitioned to `achieved`, print celebration. If `failed`, print the failing AC + suggested next action.

**When any AC has `last_result.reason: not_executed`** (the Stop hook's deterministic-checks runner skipped the command because `flow.goals.executeVerificationCommands` defaults to `false`), append this hint to the printed output:

> Set `flow.goals.executeVerificationCommands: true` in `.claude/settings.flow.json` to let the Stop hook auto-run each AC's `verification_command` during evaluator-loop and deterministic-check passes. This setting governs the Stop hook path (`bin/flow-run-deterministic-checks.sh`); `/flow:goal evaluate` always executes verification commands when present, so the hint applies only to ACs whose last evaluation came from a Stop hook pass.

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

## Critical references

- `plugins/flow/skills/goal-contract-capture/SKILL.md` — contract authoring
- `plugins/flow/skills/goal-evaluator/SKILL.md` — evaluation loop
- `plugins/flow/skills/goal-lifecycle/SKILL.md` — state transitions
- `plugins/flow/agents/goal-evaluator-judge.md` — independent judge agent
- `plugins/flow/references/flow-goals.md` — user-facing FlowGoal model doc
- `plugins/flow/references/stop-hook-goal-enforcement.md` — Stop hook architecture
- `plugins/flow/schemas/v1/goal.schema.json` — the schema goals validate against

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| `/flow:goal` (default) / `status` — read goal yaml, render summary | 1 | Autonomous, read-only |
| `/flow:goal inspect <id>` — full YAML + events + transition log | 1 | Autonomous, read-only |
| `/flow:goal history` — list all goals with filters | 1 | Autonomous, read-only |
| `/flow:goal create <kind>` — invoke `Skill(goal-contract-capture)`, write `.flow/goals/<id>.goal.yaml`, transition draft→active | 2 | Journal-and-proceed (writes a goal artifact + lifecycle transition) |
| `/flow:goal evaluate <id>` — non-terminal verdict — invoke `Skill(goal-evaluator)`, persist verdict, update lifecycle | 1 | Autonomous |
| `/flow:goal evaluate <id>` — terminal verdict (`achieved` / `failed`) | 2 | **Confirm** via AskUserQuestion (per F10 — see "Terminal-state confirmation" below) |
| `/flow:goal pause <id>` — active → waiting_for_user | 1 | Autonomous; reason via AskUserQuestion if not `--reason` |
| `/flow:goal resume <id>` — waiting → active | 1 | Autonomous |
| `/flow:goal clear <id>` — non-terminal → cancelled | 2 | **Confirm** via AskUserQuestion (irreversible) |
