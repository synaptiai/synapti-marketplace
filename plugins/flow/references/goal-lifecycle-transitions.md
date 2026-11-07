# FlowGoal lifecycle transitions

Reference for the `goal-lifecycle` and `goal-evaluator` skills. The tables here are the human-readable form of the transition table that `bin/flow-goal-record.sh --update-lifecycle` enforces (`LIFECYCLE_TRANSITIONS` in that script); if the two ever disagree, the script wins and this file is wrong.

## State diagram

```
       ┌────────────────────────────────────────────────────────┐
       ▼                                                        │
   ┌───────┐                                                    │
   │ draft │──┐                                                 │
   └───────┘  │                                                 │
              ▼                                                 │
       ┌──────────┐                                             │
       │  active  │────────────────────────────┐                │
       └──────────┘                            │                │
        │  │  │  │                             │                │
        │  │  │  └─→ waiting_for_ci    ────────┤                │
        │  │  └────→ waiting_for_user  ────────┤                │
        │  └───────→ blocked           ────────┤                │
        │                                      ▼                │
        ├──────────────────────────────→  achieved              │
        ├──────────────────────────────→  failed                │
        └──────────────────────────────→  cancelled  ───────────┘

       Terminal: {achieved, failed, cancelled}
       Resumable: {waiting_for_user, waiting_for_ci, blocked}
```

## Allowed transitions

| From | To | Trigger |
|---|---|---|
| `draft` | `active` | `goal-contract-capture` completes; `/flow:goal create` returns |
| `draft` | `cancelled` | user invokes `/flow:goal clear <id>` before activation |
| `active` | `waiting_for_user` | judge verdict `needs_human_review`; `AskUserQuestion` mid-evaluation; `/flow:goal pause` |
| `active` | `waiting_for_ci` | CI run pending; goal waits on an external signal |
| `active` | `blocked` | judge verdict `blocked` (with `blocker_type`); path-boundary violation |
| `active` | `achieved` | deterministic all-pass + (no fuzzy criteria OR judge `achieved`), confirmed by the user via `/flow:goal evaluate`; or, without a question, `/flow:start` at the end of VERIFY when every verification command ran and passed and the verdict judge passed every criterion without one (see below) |
| `active` | `failed` | budget exhausted (`continuation.max_iterations`); stuck pass-set for `flow.goals.failAfterStuckTurns` turns; deterministic `must_pass` FAIL with no fix path |
| `active` | `cancelled` | user invokes `/flow:goal clear <id>` |
| `waiting_for_user` | `active` | `AskUserQuestion` resolves; user runs `/flow:goal resume` |
| `waiting_for_user` | `cancelled` | user invokes `/flow:goal clear <id>` |
| `waiting_for_ci` | `active` | CI status reaches a terminal state |
| `waiting_for_ci` | `cancelled` | user invokes `/flow:goal clear <id>` |
| `blocked` | `active` | blocker resolved (manual fix, then `/flow:goal resume`) |
| `blocked` | `failed` | no automated trigger — a caller records an unresolvable blocker as `failed` through `goal-lifecycle` |
| `blocked` | `cancelled` | user invokes `/flow:goal clear <id>` |

A transition to the same status (`active → active`) is accepted by the helper so that repeated evaluations can update `last_evaluation` without a state change.

## Disallowed transitions

The helper rejects these with exit 1 and a stderr explanation:

- `terminal → any` — once `achieved`, `failed`, or `cancelled`, the goal is immutable. New work requires a new goal id, or the terminal goal's file removed first: `bin/flow-goal-record.sh --create` refuses to replace a terminal goal.
- `active → draft` — no going back to draft.
- `blocked → achieved` — must pass through `active` first, which forces an evaluation step.
- `waiting_for_* → achieved | failed | blocked` — resume to `active` first.

## `last_evaluation.result` mapping

| Result | Written when the new status is |
|---|---|
| `pass` | `achieved` |
| `incomplete` | `active` (evidence still missing) |
| `fail` | `active` with failing ACs named in `reason`, or `failed` |
| `blocked` | `blocked` |
| `needs_human_review` | `waiting_for_user` |

## Evaluator verdict → lifecycle status

Used by `goal-evaluator` Step 6. "Candidate" is the deterministic verdict from the verification commands; the judge column is the `goal-evaluator-judge` verdict when it ran.

| Deterministic candidate | Judge verdict | Final `lifecycle.status` | Written by |
|---|---|---|---|
| `pass` (all `must_pass` green, no fuzzy criteria) | (judge skipped) | `achieved` | caller, after AskUserQuestion |
| `pass` + fuzzy criteria | `achieved` | `achieved` | caller, after AskUserQuestion |
| `pass` + fuzzy criteria | `not_achieved` | `active` (continue) | skill |
| `fail` | (judge may run for context) | `active` (continue; failing ACs surfaced) | skill |
| `incomplete` | `not_achieved` | `active` | skill |
| `incomplete` | `blocked` (with `blocker_type`) | `blocked` | skill |
| `incomplete` | `needs_human_review` | `waiting_for_user` | skill |
| `path_boundary_violation` | (judge skipped) | `blocked` | skill |
| stuck for `failAfterStuckTurns` turns (stop-hook trigger) | any | `failed` | caller / evaluator-loop hook |
| `continuation.max_iterations` used and a must_pass check still fails (stop-hook trigger) | none (judge not run) | `failed` | evaluator-loop hook |

### `/flow:start` at the end of VERIFY: `achieved` without a question

`/flow:start` Phase 4 step 9a (`GOAL_EVALUATE_BLOCK` in `commands/start.md`) evaluates the run's own goal once the completion gate holds, and writes `achieved` itself when the evaluation is `pass`: the goal is in the trust ledger, every verification command ran and exited 0, no file is outside the goal's allowed paths, and the verdict judge passed every criterion that has no command. Any other result keeps the goal `active` and records the result and the criteria not met in `last_evaluation`. The write merges into the lifecycle, so `turns_evaluated`, `current_phase` and `current_activity` are kept.

The confirmation `/flow:goal evaluate` asks for is not asked here, for these reasons:

- The question in `/flow:goal evaluate` exists because a person runs that command at any time, on whatever evidence happens to be there. At the end of VERIFY the evidence is this run's: the commands just ran on the code the run produced, and the independent verdict judge saw the evidence bundle.
- Asking there turned the check into a routine prompt: `/flow:start` never evaluated, so `/flow:pr` asked on almost every run, including runs whose criteria had all passed, and a run without a person watching could not get past it.
- What `achieved` unlocks still goes through a person: the merge is a Tier 3 action, confirmed every time, and the review findings ledger gates it separately.
- A goal that is not in the trust ledger is never moved to `achieved` here: its commands are not run, so the result is `incomplete`; and when `flow.goals.executeVerificationCommands: true` runs them anyway and they pass, the result is still `incomplete`, with a reason that says the goal is not in the trust ledger, so `/flow:pr` asks.

So `/flow:pr`'s goal gate asks only when the goal was evaluated and is not met, or `/flow:start` did not reach the end of VERIFY.

Terminal rows are returned by the skill as `proposed_transition` and written by the caller after user confirmation; the Stop-hook evaluator-loop path records the verdict with `bin/flow-record-verdict.sh` and approves the stop with a hint instead (no `AskUserQuestion` inside a hook). The two stop-hook rows are the exception: the hook writes `failed` itself, because nobody is there to confirm and continuing would keep the agent working on a goal it cannot reach.

The Stop-hook evaluator-loop cannot ask: it records the verdict and approves the stop with a hint to run `/flow:goal evaluate <id>`. It writes one terminal status itself, `failed`, on stuck detection and when the turn budget is used up on a turn that would block again. Stuck detection belongs to the Stop hook: in evaluator-loop mode it counts consecutive `unchanged` turns against `flow.goals.failAfterStuckTurns` (default 3) and writes `failed` with reason `stuck_no_progress` itself. The goal-evaluator skill does not count turns.

`last-verdict.json` has one writer per path: the caller of the goal-evaluator skill (`commands/goal.md` or `flow-goal-evaluator.sh`) through `bin/flow-record-verdict.sh`, never the skill. Two writers race and the last one wins.

## Related

- `plugins/flow/skills/goal-lifecycle/SKILL.md` — the skill that mediates every transition.
- `plugins/flow/skills/goal-evaluator/SKILL.md` — produces the candidate and judge verdicts.
- `plugins/flow/bin/flow-goal-record.sh` — the enforcing writer.
- `plugins/flow/references/flow-goals.md` — user-facing FlowGoal documentation.
