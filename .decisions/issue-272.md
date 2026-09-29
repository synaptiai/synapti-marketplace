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
| 4 | End-to-end scenarios through the Stop hook cover all three | the scenarios of criteria 1-3, three groups in parallel through `xargs -P 3` (goal file) | PASS |

Each command runs only its own scenarios (`FLOW_E2E_SCENARIOS`): the whole suite takes about two minutes, and the Stop hook runs a trusted goal's commands with a 30 s limit each. The delta, symlink and guard scenarios beyond the three cases run in the full suite and are cited in the evidence bundle. A command also stays under the 1000 characters a `/flow:review` goal section keeps from one value.

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



A repository can commit `.flow`, `.flow/runs`, `.flow/goals` or `.decisions` (or a directory above a configured `journal.dir`) as a symlink to a directory outside the checkout. Every writer refused a symlink at the file it writes and followed one at a directory above it; a54b0d0f closed this for the evaluator's own writes only. The readers of `.flow/goals` followed it too. Decided with the user: closed in this pull request, as its own commits, and not as a goal criterion — the goal's criteria mirror the issue's.

The rule is `ensure_repo_dir()` in `bin/_repo_dir.py`, a module that imports no PyYAML and that `bin/_journal_atomic.py` re-exports: from the current directory, each component of the directory that exists must be a directory and not a symlink; with create, each missing component is made with `os.mkdir` only after the one above it passed. A `..` is walked as written, so a name that climbs out of a symlinked directory is refused. `acquire_lock()` applies it to the lockfile's directory, and every write in the module takes its lock first. Writers create their directories through it instead of `mkdir -p` or `os.makedirs`. `bin/flow-mkdir.sh` is the same rule for command blocks and skills; it needs python3 only, takes `--` before its directories (every caller passes it), and exits 2 for a refusal and 3 when the check could not run or a component could not be inspected or created. A path that does not end under the current directory (per-user state, a journal dir the user configured elsewhere) is outside the rule and is created as before. An absolute path that names the current directory through a symlink above it (macOS `/var` for `/private/var`) does end under it: when the string comparison fails, each prefix of the path is `stat()`ed, shortest first, and the first that is the current directory's own directory (`os.path.samestat`) makes the rest the components to walk; shortest first, so a committed link back to the top is still a component.

Reads, decided by the main session: no reader of `.flow/goals` reads a goal through a symlink, the same strict rule the writers follow. Each reader refuses a symlinked `.flow` or `.flow/goals` by `ensure_repo_dir()` (or `flow-mkdir.sh --check`) and a goal file that is itself a symlink, says so on stderr (`refusing — <path> is a symlink; goals are not read through it`), and treats the goal as absent. Goal trust is keyed on the repository where the check runs, so no verification command ran from such a goal, but the loop blocked or approved on a goal that belongs elsewhere and the gates answered with it. The readers of `.flow/runs` follow the same rule: a run reached through a symlinked `.flow`, `.flow/runs` or run directory is not read, is named on stderr (`… runs are not read through it`), and counts as absent.

`journal.dir`, decided by the user: a value set in the repository's settings (`.claude/settings.flow.json` or `.claude/settings.flow.local.json`) must resolve inside the repository; otherwise it is refused with a warning on stderr naming the value and the file, and the repository's settings are left out of the lookup — the user's `journal.dir` is used, or `.decisions` when the user sets none (`cascade-resolve.sh --no-repo-settings`), as for any setting a repository may not choose. A value set in the user's settings (`$FLOW_USER_SETTINGS` or `~/.claude/settings.flow.json`) may point anywhere and is written as configured, still through `ensure_repo_dir()` where it is under the repository. `bin/journal-dir.sh` is the one place the directory is resolved, and every journal reader and writer calls it: `journal-record.sh`, `journal-append.sh`, `flow-strip-auto-log.sh`, `commit-journal-churn.sh`, the auto-log, quality-run, task-completion and session-end-learn hooks, the `/flow:explain`, `/flow:learn`, `/flow:status`, `/flow:setup` and `/flow:address` blocks, the `/flow:start` journal block (`JOURNAL_INIT_BLOCK`), the `/flow:pr` journal section and the `/flow:resume` unlinked-change check. The specification-capture templates in `/flow:start`, `/flow:brainstorm` and `/flow:design`, and the prose that named `.decisions/issue-N.md`, name the resolved directory. Inside is `ensure_inside_repo()`, beside `ensure_repo_dir()`: the path ends under the physical current directory, compared by path components and not by string prefix, and passes `ensure_repo_dir()`'s walk. The file that set the value is found by reading the local file, then the project file, the cascade's order; the check runs only when the value the cascade printed is that file's.

Decisions taken while building:
- Anchored at the physical current directory, not `git rev-parse --show-toplevel`: every writer names its files relative to the current directory, where flow runs (the working-tree top), neither hardened sibling calls git, and the check runs on every Edit/Write hook. The limit: a writer run from a subdirectory is checked from there down, and one run from outside the repository with an absolute path into it (`journal-append.sh --file` from another directory) is outside the rule and writes through a symlinked `.decisions`. Open, for the user to decide: anchoring at the nearest ancestor of the working directory that holds `.git` closes the subdirectory case but reverses this decision; anchoring at the path's own repository closes both but would refuse per-user state under a home directory that is itself a repository with a symlinked `~/.claude`. The auto-log hooks, the one caller that passes an absolute `--file` from another directory, apply their own physical containment.
- Strict: a symlink is refused even when it points inside the repository. The same holds for a repository's `journal.dir`: a symlinked component makes it "not inside", so the resolver never hands a writer a repository path the writer would refuse.
- One check point in the module, `acquire_lock()`, and none inside `_atomic_write`, `append_body` or `append_jsonl`: no current writer reaches those before the lock's check or its own, so no scenario could tell such a check apart. For the same reason `flow-goal-record.sh --update-lifecycle` and the SessionEnd hook rely on the lock's check and have no check of their own.
- A directory swapped for a symlink between the check and the open is out of scope: the content is committed before flow runs.
- The SessionEnd hook's notice was printed to a stderr the hook discarded; it now reaches the terminal, with the refusals, and counts only the runs it wrote to.
- The Stop hook approves a refused goal with `no active flow goal: <the refusal>`, in every mode, before the evaluator loop is reached; `goal-symlink-flow` in `e2e-goal-stuck.test.sh` expects that on both turns, with no per-user stuck state kept.
- `flow-active-goal.sh` answers a refusal with exit 2, not the 1 of "no goal": `/flow:merge` and `/flow:pr` read 1 as "gate not applicable" and proceed, so a 1 would open their gates in a repository that commits a symlinked `.flow`. They read 2 as blocked; the evaluator loop reads it as no active goal. A `.flow` or `.flow/goals` that exists and is not a directory is refused the same way, as the writers refuse it.
- The gates discard the helper's stderr, so a refusal read as `flow-active-goal.sh exited 2`. The `/flow:merge` and `/flow:pr` gates, the `/flow:status` goal section and the `gh issue create` hook now ask the helper again in their failure arm and append the first line of its stderr, one line, control characters blanked: `flow-active-goal.sh exited 2: refusing — .flow is a symlink; goals are not read through it`. Exit 2 keeps its meaning. The second call is deterministic for a refusal; one run that captured both streams would need a temporary file in every block.
- `commands/review.md` reads the goal from GitHub at the pull request's commit, not from the working tree, and has no check. The prose readers (`/flow:goal inspect`, `history` and the create pre-flight, `/flow:resume`, the goal-evaluator skill) carry the rule as an instruction; no scenario covers them.
- The fallback behind a refused repository `journal.dir` is `cascade-resolve.sh --no-repo-settings`, which refuses to answer when the script itself lies inside the repository being checked (the plugin's own checkout, when it is dogfooded); `.decisions` is used then.
- An absolute repository `journal.dir` may name the repository through a symlink above it; what counts is the directory it reaches, by the prefix rule above.
- A check that could not run is reported as could-not-check, never as refused and never as absent: `/flow:status` recent runs and `/flow:learn` answer unavailable, the `/flow:resume` pre-flight cannot tell, the run read and the `/flow:start` goal block (blocked) say the check did not run, the `/flow:start` journal, `/flow:trigger`, `/flow:watch` and run-creation blocks exit 3 where a refusal exits 1, and the strip says it cannot check. The Stop hook's scan and the `/flow:goal status` scan report a `.flow/goals` that cannot be inspected as unknown. `journal-dir.sh` is the one reader where it withholds: a repository `journal.dir` it cannot check is not used, with a warning that says so, and the user's value or `.decisions` is. `flow-active-goal.sh`, the resume scan and the evidence bundle keep one outcome for both (exit 2, or the run left out) and say which in their message.
- A relative `journal.dir` that starts with `-` is printed by `journal-dir.sh` as `./<name>`, so no command downstream reads it as an option; with that, the `--` every `flow-mkdir.sh` caller passes changes nothing a scenario can see for those callers, and is kept as the helper's stated contract.
- `journal-record.sh` does not warn on `..`, and the strip does not refuse `..` or an absolute path outside the repository of its own accord: a repository's value reaches neither outside the repository, and the user's own value, or a directory given to the strip on its command line, is the user's choice.
- The auto-log hooks keep their own containment: a relative journal dir that resolves outside the repository gets no breadcrumb, whichever file set it. A user's relative `journal.dir` that climbs out with `..` therefore gets journal entries but no auto-log trail; an absolute one gets both. The hooks discard the resolver's warning, as they discarded the cascade's.
- The resolver runs Python only when a repository file sets `journal.dir`, and needs no PyYAML for it.
- The `/flow:start` journal block keeps its exit behaviour: a refused repository value falls back like every other writer and the block goes on; a journal directory that is a symlink, lies under one, or is not a directory exits 1 and the command stops. The `/flow:resume` unlinked-change check matches the journal directory as a prefix of the repository-relative paths git reports, so an absolute `journal.dir` inside the repository is never matched and a change there counts as unlinked.
- Run readers: `/flow:learn` and `/flow:status` check `.flow/runs` with `flow-mkdir.sh --check` and leave out a run directory that is a symlink, with a note for each. The `/flow:resume` pre-flight checks `.flow/runs`, its scan checks each run directory from the repository top (which refuses a symlinked `.flow` or `.flow/runs` for every run under it, so a separate check on `.flow/runs` there changed nothing a scenario could see and was removed), and its run read checks the run directory and `run.yaml`. `bin/_flow_evidence_bundle.py` applies `ensure_repo_dir()` to the run directory it is given and assembles the bundle as for a goal with no run directory when it is refused; the evaluator loop already passes no run directory it refused, so this covers another caller. The SessionEnd hook reads `run.yaml` through a symlinked `.flow` to find active runs but writes nothing there, refusing each run on stderr, as before.
- Prose readers of runs (`/flow:goal status` delta and `inspect` events, `/flow:run`'s concurrency check, the `/flow:watch` loop prompt) carry the rule as an instruction; no scenario covers them.

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
| `hooks/scripts/flow-goal-evaluator.sh` | Stop hook | no (a54b0d0f) | creates and checks its run directory with `flow-mkdir.sh`, as every writer does; the hand-written `pwd -P` check was correct but untested where `.flow/runs` links to a target that already holds the run directory (E33, E34) |
| `bin/promote-proposal.sh` (`.flow/review-exceptions.md`) | `/flow:learn` promote | no: it refuses a symlinked `.flow`, the only directory below the top | unchanged |
| `hooks/scripts/log-file-changes.sh`, `log-commits.sh` | PostToolUse | no: the journal dir must resolve physically inside the repository, and `auto-log/` is checked | unchanged; `journal-append.sh` now checks too |
| `bin/commit-journal-churn.sh` | `/flow:pr` | no: `git add` does not stage a path beyond a symlink | unchanged |
| `bin/_flow_evidence_bundle.py`, `bin/_journal_manifest.py`, `bin/flow-mine-corrections.sh` | readers | not writers | — |
| `flow-goal-trust.sh`, `flow-quality-ledger.sh`, `session-end-learn.sh`, the Stop hook's session state | hooks and helpers | write under `~/.claude`, not the repository | outside the rule |

| Reader of `.flow/goals` | Reached from | Read a goal through a symlink before | Now |
|---|---|---|---|
| `hooks/scripts/flow-goal-stop.sh` scan | Stop hook, every turn, every mode | yes: through `.flow`, `.flow/goals` or a goal file | refused on stderr; approve, no active goal |
| `bin/flow-active-goal.sh` | `/flow:merge`, `/flow:pr` and `/flow:status` gates, `/flow:start`, the evaluator loop, the `gh issue create` hook | yes through `.flow`; `.flow/goals` and a goal file were refused | refused on stderr; exit 2 |
| `commands/goal.md` status scan | `/flow:goal status` | yes | `STATE=none`; a goal file that is a symlink is named as not read |
| `commands/learn.md` goal listing | `/flow:learn` | yes: listed for Phase 2 to read | not listed; `GOAL_FILE_COUNT=0` |
| `commands/start.md` goal block | `/flow:start <N>` | yes: resumed | not resumed; `FLOW_GOAL_STATE=create` |
| `commands/review.md` | `/flow:review` | no: read from GitHub at the pull request's commit | unchanged |

| Reader of `.flow/runs` | Reached from | Read a run through a symlink before | Now |
|---|---|---|---|
| `commands/learn.md` run events listing | `/flow:learn` | yes: listed for Phase 2 to read, through a symlinked `.flow` or `.flow/runs` | not listed; `RUN_EVENT_FILE_COUNT=0`; a symlinked run directory named |
| `commands/resume.md` pre-flight, scan, run read | `/flow:resume` | yes: an active run resumed | "No FlowRuns exist", `STATE=none`, or exit 1 for a named run |
| `commands/status.md` recent runs | `/flow:status` | yes: listed with its verdict and events | `STATE=empty`; a symlinked run directory left out before the three most recent are taken |
| `bin/_flow_evidence_bundle.py` | the evaluator loop's judge | only when handed such a directory; the loop never hands one | evidence and previous verdict left out, refusal on stderr |
| `hooks/scripts/flow-goal-evaluator.sh` | Stop hook | no (a54b0d0f) | creates and checks its run directory with `flow-mkdir.sh`, as every writer does; the hand-written `pwd -P` check was correct but untested where `.flow/runs` links to a target that already holds the run directory (E33, E34) |
| `hooks/scripts/session-end-state.sh` | SessionEnd | reads `run.yaml` to find active runs; writes refused per run | unchanged |

Scenarios: `plugins/flow/tests/e2e-flow-dir-symlinks.test.sh`, ways it can be wrong L1-L40 (and E33-E34 in `e2e-goal-stuck.test.sh`). L1-L15, the writers: against the plugin at 9b706669, pass=29 fail=73; with the writers' rule, pass=102 fail=0; eighteen mutants, all killed. L16-L30, goal reads and `journal.dir`: against the plugin at 309fb822, pass=182 fail=55, every new scenario failing but the six controls; at 8a5bdce1, pass=237 fail=0; twenty-three mutants, all killed. L31-L37, the user's `journal.dir` behind a refused one, the journal readers that named `.decisions`, run reads and the gates' refusal text: against the plugin at adcc5989, pass=286 fail=45, every new scenario failing but the controls; at 26f88178, pass=331 fail=0. Eighteen mutants: seventeen killed; the one that survived removed the `/flow:resume` scan's check on `.flow/runs`, and that check was removed from the code. Review round 2, L38-L40 and E33-E34: against the plugin before each fix (at 7245a654 for the check that cannot run, aef7f8b0 for option-like names, d6b7a954 for paths through `/var`), every new scenario failed; the E33 and E34 scenarios pass on the correct check and fail on a plain `[ -d ] && [ ! -L ]`. At a642ef75, e2e-flow-dir-symlinks pass=426 fail=0 and e2e-goal-stuck pass=358 fail=0. Twenty-two mutants, twenty-one killed; the one that survived made a missing python3 exit 2, in a branch no scenario could reach with python3 on PATH, and the branch was removed. `start-journal-link` finds the journal block by its marker. The scenarios that set a repository `journal.dir` under a symlink or climbing out with `..` (`journal-record-parent-link`, `journal-append-parent-link`, `strip-parent-link`, `journal-dotdot-link`) set it in the user's settings, so the writer's own check is what refuses it; the repository's value is covered by `journal-append-repo-parent-link` and its siblings.
