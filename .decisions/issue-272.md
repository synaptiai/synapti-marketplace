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

## Symlinked directories under .flow

A repository can commit `.flow`, `.flow/runs`, `.flow/goals` or `.decisions` (or a directory above a configured `journal.dir`) as a symlink to a directory outside the checkout. Every writer refused a symlink at the file it writes and followed one at a directory above it; a54b0d0f closed this for the evaluator's own writes only. Decided with the user: closed in this pull request, as its own commits, and not as a goal criterion — the goal's criteria mirror the issue's.

The rule is `ensure_repo_dir()` in `bin/_journal_atomic.py`: from the current directory, each component of the directory that exists must be a directory and not a symlink; with create, each missing component is made with `os.mkdir` only after the one above it passed. A `..` is walked as written, so a name that climbs out of a symlinked directory is refused. `acquire_lock()` applies it to the lockfile's directory, and every write in the module takes its lock first. Writers create their directories through it instead of `mkdir -p` or `os.makedirs`. `bin/flow-mkdir.sh` is the same rule for command blocks and skills. A path that does not end under the current directory (per-user state, a journal dir configured elsewhere) is outside the rule and is created as before.

Decisions taken while building:
- Anchored at the physical current directory, not `git rev-parse --show-toplevel`: every writer names its files relative to the current directory, where flow runs (the working-tree top), neither hardened sibling calls git, and the check runs on every Edit/Write hook. The limit: a writer run from a subdirectory is checked from there down.
- Strict, like the evaluator's `pwd -P` rule: a symlink is refused even when it points inside the repository.
- One check point in the module, `acquire_lock()`, and none inside `_atomic_write`, `append_body` or `append_jsonl`: no current writer reaches those before the lock's check or its own, so no scenario could tell such a check apart. For the same reason `flow-goal-record.sh --update-lifecycle` and the SessionEnd hook rely on the lock's check and have no check of their own.
- A directory swapped for a symlink between the check and the open is out of scope: the content is committed before flow runs.
- With a symlinked `.flow` the Stop hook still reads the goal through the link (`flow-active-goal.sh` refuses only a symlinked `.flow/goals`) but can no longer update its lifecycle, so its turns are not counted against the budget and stuck detection cannot fail it; the loop ends at the throttle. `goal-symlink-flow` in `e2e-goal-stuck.test.sh` passes with this.
- The SessionEnd hook's notice was printed to a stderr the hook discarded; it now reaches the terminal, with the refusals, and counts only the runs it wrote to.

| Writer | Reached from | Wrote through a symlinked parent before | Now |
|---|---|---|---|
| `bin/flow-record-verdict.sh` | `/flow:goal evaluate`; the Stop hook, which refuses a symlinked run directory before it calls this | yes: run directory, `last-verdict.json`, lock | run directory created through the rule; exit 2 |
| `bin/flow-record-activity.sh` | run-state-management, every phase boundary | yes: `activities/`, `evidence/`, the activity, lock, `events.jsonl` | same; exit 2 |
| `bin/flow-record-evidence.sh` | goal-evidence-ledger | yes: `evidence/`, the sidecar, lock | same; exit 2 |
| `bin/flow-goal-record.sh --create` | goal-contract-capture (`/flow:start`, `/flow:goal create`, `/flow:debug`) | yes: `.flow/goals`, the goal, lock | `.flow/goals` created through the rule; exit 2 |
| `bin/flow-goal-record.sh --update-lifecycle` | the Stop hook on every turn it blocks; `/flow:goal` lifecycle block; goal-lifecycle | yes: the goal rewritten and its lock created in the link's target | refused at the lock; exit 2, where a refused lock was a traceback and exit 1 |
| `bin/journal-record.sh` | every command's manifest emit, e.g. the `/flow:start` Stranger Test block | yes: journal directory, journal, lock | journal directory created through the rule; exit 2 |
| `bin/journal-append.sh` | `/flow:brainstorm` and `/flow:design` decision blocks; the auto-log hooks | yes: the same | same; exit 2 |
| `hooks/scripts/session-end-state.sh` | SessionEnd | yes: `events.jsonl` and its lock in every active run found through the link, silently | refused per run, on stderr; exit 0 |
| `bin/flow-strip-auto-log.sh` | `/flow:setup` strip block | yes, under a symlinked parent of `journal.dir` (a symlinked journal dir was refused) | `flow-mkdir.sh --check` before the scan; exit 2 |
| `commands/trigger.md`, `commands/watch.md` pre-flights | `/flow:trigger`, `/flow:watch` | yes: `mkdir -p .flow/triggers`, where the trigger is then written | `flow-mkdir.sh`; exit 1 |
| `commands/goal.md` pre-flight | `/flow:goal` | yes: `mkdir -p .flow/goals` | removed; `flow-goal-record.sh --create` makes it |
| `commands/start.md` journal block | `/flow:start` | the journal header was then written through a symlinked `.decisions` | `flow-mkdir.sh`; exit 1, and the command stops |
| run-state-management run creation | every command that creates a run | `run.yaml` was written through a symlinked `.flow` or `.flow/runs` | a block creates the run directory with `flow-mkdir.sh`; refused means no run |
| `hooks/scripts/flow-goal-evaluator.sh` | Stop hook | no (a54b0d0f) | unchanged |
| `bin/promote-proposal.sh` (`.flow/review-exceptions.md`) | `/flow:learn` promote | no: it refuses a symlinked `.flow`, the only directory below the top | unchanged |
| `hooks/scripts/log-file-changes.sh`, `log-commits.sh` | PostToolUse | no: the journal dir must resolve physically inside the repository, and `auto-log/` is checked | unchanged; `journal-append.sh` now checks too |
| `bin/commit-journal-churn.sh` | `/flow:pr` | no: `git add` does not stage a path beyond a symlink | unchanged |
| `bin/_flow_evidence_bundle.py`, `bin/_journal_manifest.py`, `bin/flow-mine-corrections.sh`, `bin/flow-active-goal.sh` | readers | not writers | — |
| `flow-goal-trust.sh`, `flow-quality-ledger.sh`, `session-end-learn.sh`, the Stop hook's session state | hooks and helpers | write under `~/.claude`, not the repository | outside the rule |

Open, for the user to decide:
- Reads: `flow-active-goal.sh` follows a symlinked `.flow` to read a goal (it refuses only a symlinked `.flow/goals`), and the Stop hook's own scan in `flow-goal-stop.sh` follows either. Refusing `.flow` in the reader makes `goal-symlink-flow` approve instead of block.
- A repository-controlled `journal.dir` outside the checkout: `journal-record.sh` warns on `..` and writes, `journal-append.sh` writes, `flow-strip-auto-log.sh` refuses. The outcome is the same as this class (writes outside the checkout) by another mechanism, and refusing it changes configured setups.

Scenarios: `plugins/flow/tests/e2e-flow-dir-symlinks.test.sh`, ways it can be wrong L1-L15. Against the plugin at 9b706669: pass=29 fail=73; after the fix: pass=102 fail=0. Eighteen mutants, each run on a copy of the plugin, all killed.
