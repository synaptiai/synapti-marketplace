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
| `active` | `achieved` | deterministic all-pass + (no fuzzy criteria OR judge `achieved`), confirmed by the user via `/flow:goal evaluate` |
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

- `terminal → any` — once `achieved`, `failed`, or `cancelled`, the goal is immutable. New work requires a new goal id.
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

Terminal rows are returned by the skill as `proposed_transition` and written by the caller after user confirmation; the Stop-hook evaluator-loop path records the verdict with `bin/flow-record-verdict.sh` and approves the stop with a hint instead (no `AskUserQuestion` inside a hook).

## Related

- `plugins/flow/skills/goal-lifecycle/SKILL.md` — the skill that mediates every transition.
- `plugins/flow/skills/goal-evaluator/SKILL.md` — produces the candidate and judge verdicts.
- `plugins/flow/bin/flow-goal-record.sh` — the enforcing writer.
- `plugins/flow/references/flow-goals.md` — user-facing FlowGoal documentation.
