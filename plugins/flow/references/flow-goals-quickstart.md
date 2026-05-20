# Hello, FlowGoal — quickstart

A 5-minute walkthrough of the v3 runtime layer on a synthetic issue. By the end you'll have a FlowGoal in `active`, an evaluation that produces a verdict, and a clear picture of how the pieces fit together.

## Prerequisites

- flow v3.0.0 installed (`claude plugins list | grep flow`)
- A git repository (any one — a scratch repo works)
- `python3` with `PyYAML` available (`python3 -c 'import yaml'` exits 0)

If you've never run `/flow:start` in this project, the first invocation will prompt you to enable v3 — answer **Enable v3** and the prompt will not fire again.

## Step 1 — Enable v3 explicitly (skip if you've already onboarded)

In an existing project where you skipped the onboarding prompt or you want to opt in without re-running `/flow:start`, write `.claude/settings.flow.json`:

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

These two flags do the load-bearing work:

- `requireGoalForStart: true` — `/flow:start <issue>` will auto-create a FlowGoal after the Spec Validation Gate passes.
- `executeVerificationCommands: true` — `/flow:goal evaluate` will run each AC's `verification_command` and capture the output as evidence. Without this, evaluations report `not_executed` for every command-backed AC.

## Step 2 — Create a synthetic issue

```bash
gh issue create \
  --title "Add a sum() helper to the utils module" \
  --body "## Acceptance Criteria
- [ ] sum(2, 3) returns 5
  verification_command: python3 -c 'from utils import sum; assert sum(2, 3) == 5'
- [ ] sum() rejects non-numeric input
  verification_command: python3 -c 'from utils import sum; sum(\"a\", \"b\")' 2>&1 | grep -q TypeError"
```

Note the issue number gh prints — let's call it `N`.

## Step 3 — Start the workflow

```text
/flow:start N
```

What happens:

1. Phase 0 PRE-FLIGHT validates clean git state, gh auth, etc.
2. Phase 1 EXPLORE fetches the issue, runs `specification-capture`, and the Spec Validation Gate confirms each AC has a `verification_command`.
3. After the gate passes, you see this in the output:
   ```
   FlowGoal created: issue-N at .flow/goals/issue-N.goal.yaml (status: active)
   ```
4. Phase 2+ proceed normally — branch creation, task decomposition, code, verify.

## Step 4 — Inspect the goal

```text
/flow:goal inspect issue-N
```

You'll see the full YAML: outcome, acceptance criteria with verification commands, specification (non-goals, failure modes, interface contracts), evaluator binding, lifecycle.

## Step 5 — Evaluate

After you've implemented and committed:

```text
/flow:goal evaluate issue-N
```

The evaluator:

1. Runs each AC's `verification_command` (because `executeVerificationCommands: true`).
2. Captures stdout/stderr/exit_code as evidence sidecars at `.flow/runs/<run-id>/evidence/`.
3. Decides per-AC status: `pass` (deterministic command succeeded), `evidence_collected` (output captured, judge needed), or `fail`.
4. If any ACs are fuzzy (no `verification_command`), dispatches `Agent(goal-evaluator-judge)` with the evidence bundle.
5. Transitions lifecycle: all-pass → `achieved`; any-fail → stays `active` with `last_evaluation.reason` set; blocked → `blocked`.

You'll see a per-AC table and the verdict.

## Step 6 — Confirm `achieved`

```text
/flow:goal status
```

If lifecycle is `achieved`, the goal is complete. `/flow:pr` and `/flow:merge` from this point require the goal to be `achieved` (with `requireGoalForStart: true`).

## Common adjustments

- **Stop hook noise**: default is `warn` (silent unless goal exists and lacks evidence). Set `flow.goals.stopHookEnforcement: evaluator-loop` for active Haiku-judge-per-turn enforcement (~$0.001/turn). See `stop-hook-goal-enforcement.md`.
- **Adhoc goals (no issue)**: `/flow:goal create adhoc my-id` — the journal artifact lands in `.decisions/session-<date>.md` per the goal-lifecycle skill's session-scoped fallback.
- **Pausing**: `/flow:goal pause issue-N` transitions to `waiting_for_user`. Resume with `/flow:goal resume issue-N`.

## Next steps

- `flow-goals.md` — full FlowGoal model + lifecycle state machine
- `stop-hook-goal-enforcement.md` — three Stop-hook modes (`warn`, `block`, `evaluator-loop`) with cost characteristics
- `flow-runtime-state.md` — `.flow/` directory layout and gitignore policy
- `migration-v2-to-v3.md` — step-by-step v2 → v3 opt-in (for projects already using flow v2.x)
