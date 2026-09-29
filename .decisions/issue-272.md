---
issue: 272
created: '2026-09-29T09:05:02Z'
artifacts:
- type: specification
  captured_at: '2026-09-29T09:05:02Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-29T09:07:40Z'
  goal_id: issue-272
  source: github_issue
---

## Specification

_Captured by specification-capture skill on 2026-09-29. Source: drafted from issue #272 and the evaluator code, each element confirmed by the user._

### Non-goals

- The judge path is unchanged: when no must_pass criterion fails deterministically, the delta still comes from the judge.
- `failAfterStuckTurns`, its default of 3, the turn budget and the throttle are unchanged.
- Which criteria fail, and the continuation prompt that names them, are unchanged.
- No change to `/flow:goal evaluate` or to the manual evaluator.

### Failure modes

- **Timeout:** none — the comparison reads and writes one local file; no process or network call is added.
- **Partial failure:** the previous-failures file cannot be written (disk full, permission): the turn is recorded as `unchanged`, as today, with a stderr note. The stuck counter's own fail-closed rule is untouched, so the loop cannot run forever.
- **Invalid input:** the previous-failures file is unreadable, is a symlink, or holds an id that is not a criterion id: it is treated as absent (`unchanged`, as today), and a symlink is never written through.
- **Missing context:** no previous record (the first failing turn, or the first failing turn after a passing turn reset the count): `unchanged`, as today.

### Interface contracts

- Delta values stay the existing enum: `made_progress | unchanged | regressed`. For a goal with a run, the deterministic path's delta is written to `.flow/runs/<id>/last-verdict.json` as today, now computed.
- The previous turn's deterministically failing set (must_pass criterion ids plus path violations) is stored next to the stuck counter: `.flow/runs/<id>/stuck-failing` for a goal with a run, `<FLOW_STATE_DIR>/stuck/<key>-<goal>.failing` without one. One entry per line, sorted, unique. It is removed wherever the stuck counter is removed.
- Delta rule, comparing this turn's set C with the previous set P:
  - P absent: `unchanged`
  - C == P: `unchanged`
  - C contains an entry not in P: `regressed`
  - otherwise (C a strict subset of P): `made_progress`
- Only `unchanged` increments the stuck counter, as today; any other delta resets it.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| set comparison | Any change in the set counts as progress, so swapping one failure for another ({AC1} then {AC2}) resets the counter | {AC1} then {AC2}: expected `regressed`; the wrong version records `made_progress` |
| baseline after a passing turn | A passing turn leaves the old set on disk, so a later failure is compared with a set from before the pass | {AC1, AC2}, then all pass, then {AC1}: expected `unchanged` (no baseline); the wrong version records `made_progress` |
| set identity | The lists are compared in the order the checks report them, or with duplicates, so the same failures in another order count as a change | the same two failures reported in either order: expected `unchanged` |
| recorded delta | The computed delta drives the stuck counter, but `last-verdict.json` still records the literal `unchanged` | goal with a run, {AC1, AC2} then {AC2}: `last-verdict.json` has delta `made_progress` |

## Spec Validation Gate


| # | Acceptance criterion | Verification command | Gate |
|---|---|---|---|
| 1 | Two failing criteria fixed one per turn, `failAfterStuckTurns=2`: not failed | `FLOW_E2E_SCENARIOS=goal-fixed-one-per-turn plugins/flow/tests/run.sh e2e-goal-stuck.test.sh` | PASS |
| 2 | The same failures for `failAfterStuckTurns` turns: still failed | `FLOW_E2E_SCENARIOS=goal-same-failures,goal-stuck plugins/flow/tests/run.sh e2e-goal-stuck.test.sh` | PASS |
| 3 | A newly failing criterion is recorded as regressed | `FLOW_E2E_SCENARIOS=goal-regressed,goal-swapped-failure plugins/flow/tests/run.sh e2e-goal-stuck.test.sh` | PASS |
| 4 | End-to-end scenarios through the Stop hook cover all three | the nineteen delta scenarios in ten parallel groups of at most two (goal file) | PASS |

Each command runs only its own scenarios (`FLOW_E2E_SCENARIOS`): the whole suite takes about two minutes, and the Stop hook runs a trusted goal's commands with a 30 s limit each.

## Plan


Four tasks, in order:

1. The ways it can be wrong (E17-E26) and their Stop-hook scenarios, run first against the unchanged evaluator (RED: 29 failures, all in the new scenarios).
2. `_failing_delta` in `hooks/scripts/flow-goal-evaluator.sh`: build the failing set, compare it with the kept one, keep this turn's; `_reset_stuck` removes the kept set with the counter. One mutant per risk row and per guard (symlink, foreign id, failed write, path violations).
3. `references/stop-hook-goal-enforcement.md`, `references/flow-goals.md`, CHANGELOG.
4. `FLOW_E2E_SCENARIOS` for `e2e-goal-stuck.test.sh`, so each criterion's command fits the Stop hook's limit; every artifact byte-identical to the unfiltered run before the change.

Decisions taken while building:
- A path violation is kept as `path:<file>` and a criterion id bare. Without the prefix, the rule that a kept set naming a non-criterion is ignored would discard every set holding a path.
- Which ids are criteria comes from this turn's check report, not from re-reading the goal.
- A turn that fails no must_pass check and no path boundary, but that the judge decides, also clears the kept set (E27, E30). It is the same rule as for a turn that passes every check: {AC1, AC2}, a judge turn, then {AC2} is `unchanged`, not `made_progress`. The stuck counter still follows the judge's delta.
- The run directory of a goal with a run is created at the start of each turn, before any stuck state is read or written, and every step decides where the goal's state lives from that one result (E28). `.flow/runs/` is not tracked, so a fresh clone or worktree has none.
- It is never created through a symlinked `.flow` or `.flow/runs`, and a run directory that is a symlink or lies under one is refused, as flow-record-verdict.sh refuses one: the goal keeps its state in per-user storage and no run file is written (E29).
