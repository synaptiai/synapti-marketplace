---
issue: 354
created: '2026-11-16T12:56:10Z'
artifacts:
- type: escalation-asked
  captured_at: '2026-11-16T12:56:10Z'
  question_id: q-20261116T125609Z-c64bb1
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - 'In 1a the shipped next cannot launch a worker: every launch row of transitions.json
    reads facts that 1b'
  - 1c
  - 1e or 1g compute. So AC3 (every row through next)
  - AC4 (one worker)
  - AC5 (relaunch)
  - AC6 (w
- type: escalation-asked
  captured_at: '2026-11-16T12:56:12Z'
  question_id: q-20261116T125611Z-297f5f
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - '#354''s P5 go item says the cost part must come out go when P5 is re-run'
  - but that part measures what Claude Code reports for a resumed run
  - which the engine cannot change
  - so it stays no-go. The desig
- type: escalation-asked
  captured_at: '2026-11-16T12:56:14Z'
  question_id: q-20261116T125613Z-a7f8cf
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - 1a-1g merge to main with the factory off
  - but today off only means no probe record
  - and this Mac has one. From 1b on
  - each phase lets the shipped next do more.
- type: escalation-asked
  captured_at: '2026-11-16T12:56:16Z'
  question_id: q-20261116T125615Z-b44b95
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (planning)
  situation:
  - AC12 says 1a ends in a release
  - and the design asks for a live acceptance run before each release. In 1a the engine
    can launch nothing outside tests
  - and the plan puts the first live run and the first
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:49Z'
  escalation_field: options
  outcome:
  - A test-only entry point runs the engine's real next with fixture values for the
    facts later phases compute; flow-factory.sh cannot reach it; each later phase
    replaces its fixtures with the real facts. Meets AC3-AC6 and AC9 as written
  - but those scenarios do not run through the shipped wrapper.
  question_id: q-20261116T125609Z-c64bb1
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:52Z'
  escalation_field: options
  outcome:
  - Resume depends on P5's session parts only; the cost item is closed by an E2E test
    that the engine charges each run's own cost
  - and by a new P5 part engine_charge that a re-run records as go (about $0.75
  - asked at that step).
  question_id: q-20261116T125611Z-297f5f
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:54Z'
  escalation_field: options
  outcome:
  - Add flow.factory.enabled
  - 'default false: next and the acting person subcommands refuse with FACTORY_REFUSED=disabled
    unless it is true; status'
  - rebuild
  - probe and context --mode always work.
  question_id: q-20261116T125613Z-a7f8cf
- type: escalation-resolved
  captured_at: '2026-11-16T14:46:56Z'
  escalation_field: options
  outcome:
  - Merge 1a without a release
  - and release once the factory works end to end
  - 'editing AC12 in #354 to #360.'
  question_id: q-20261116T125615Z-b44b95
- type: design
  captured_at: '2026-11-16T14:59:20Z'
  chosen: Engine modules by area
- type: escalation-asked
  captured_at: '2026-11-16T15:00:15Z'
  question_id: q-20261116T150015Z-59020c
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (specification-capture)
  situation: 'Issue #354 states no non-goals; the specification needs them before
    planning.'
- type: escalation-asked
  captured_at: '2026-11-16T15:00:16Z'
  question_id: q-20261116T150016Z-eca1ab
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (specification-capture)
  situation: 'Issue #354 states no failure modes; the specification needs them before
    planning.'
- type: escalation-asked
  captured_at: '2026-11-16T15:00:17Z'
  question_id: q-20261116T150016Z-6a9446
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (specification-capture)
  situation: 'Issue #354 states no interface contracts; the specification needs them
    before planning.'
- type: escalation-asked
  captured_at: '2026-11-16T15:00:17Z'
  question_id: q-20261116T150017Z-fc8ce6
  blocking: 'yes'
  class: decision
  command: /flow:start 354 (specification-capture)
  situation: 'Issue #354 states no risk map; the specification needs them before planning.'
- type: escalation-resolved
  captured_at: '2026-11-16T15:08:03Z'
  escalation_field: options
  outcome: Accept the drafted non-goals.
  question_id: q-20261116T150015Z-59020c
- type: escalation-resolved
  captured_at: '2026-11-16T15:08:04Z'
  escalation_field: options
  outcome: Accept the drafted failure modes.
  question_id: q-20261116T150016Z-eca1ab
- type: escalation-resolved
  captured_at: '2026-11-16T15:08:05Z'
  escalation_field: options
  outcome: Accept the drafted interface contracts.
  question_id: q-20261116T150016Z-6a9446
- type: escalation-resolved
  captured_at: '2026-11-16T15:08:06Z'
  escalation_field: options
  outcome: Accept the drafted risk map.
  question_id: q-20261116T150017Z-fc8ce6
- type: specification
  captured_at: '2026-11-16T15:08:13Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-11-16T15:10:02Z'
  goal_id: issue-354
  source: start
- type: workflow-run
  captured_at: '2026-11-16T15:10:19Z'
  workflow: start-issue
  run_id: 2026-11-16T144941Z-issue-354
  status: active
- type: escalation-asked
  captured_at: '2026-11-16T16:19:56Z'
  question_id: q-20261116T161955Z-8ab43d
  blocking: soft
  class: decision
  command:
  - /flow:start 354 (planning
  - T5 settings)
  situation: design.json gives each worker stage a budget and a timeout but no turn
    limit; the launcher passes --max-turns on every run.
- type: escalation-asked
  captured_at: '2026-11-16T16:19:56Z'
  question_id: q-20261116T161956Z-1b5058
  blocking: soft
  class: decision
  command:
  - /flow:start 354 (planning
  - T5 settings)
  situation:
  - --max-budget-usd stops a run only after the turn that passes it
  - so the spend guard must allow each run to overshoot by one turn; the only measurement
    is P4's $0.048 on a $0.10 limit.
- type: escalation-asked
  captured_at: '2026-11-16T16:19:57Z'
  question_id: q-20261116T161957Z-492a4d
  blocking: soft
  class: decision
  command:
  - /flow:start 354 (planning
  - T5 settings)
  situation: A worker run that hits a usage limit pauses the job without counting
    an attempt; when the result gives no reset time the engine needs a default pause.
- type: escalation-resolved
  captured_at: '2026-11-16T17:20:52Z'
  escalation_field: options
  outcome:
  - Twice the dearest turn seen in the job so far
  - at least $0.50.
  question_id: q-20261116T161956Z-1b5058
- type: escalation-resolved
  captured_at: '2026-11-16T17:20:53Z'
  escalation_field: options
  outcome: Pause 3600 s.
  question_id: q-20261116T161957Z-492a4d
- type: escalation-asked
  captured_at: '2026-11-16T17:38:11Z'
  question_id: q-20261116T173811Z-5ca7ce
  blocking: soft
  class: decision
  command:
  - /flow:start 354 (planning
  - T5 settings)
  - asked again after the handover
  situation:
  - The launcher needs a turn limit policy for worker runs; claude -p and the Agent
    SDK default to no turn limit
  - and P5 showed --max-turns is accepted and enforced.
- type: escalation-resolved
  captured_at: '2026-11-16T17:38:16Z'
  escalation_field: options
  outcome: 'No turn limit: the launcher passes no --max-turns; budget and timeout
    bound every run'
  question_id: q-20261116T173811Z-5ca7ce
- type: escalation-resolved
  captured_at: '2026-11-16T17:38:17Z'
  escalation_field: situation
  outcome:
  - 'withdrawn: Superseded by q-20261116T173811Z-5ca7ce'
  - which offered no turn limit; the user chose it
  question_id: q-20261116T161955Z-8ab43d
- type: workflow-run
  captured_at: '2026-11-16T17:40:58Z'
  workflow: start-issue
  run_id: 2026-11-16T144941Z-issue-354
  status: active
- type: escalation-asked
  captured_at: '2026-11-16T17:51:36Z'
  question_id: q-20261116T175135Z-5b9bc1
  blocking: 'yes'
  class: decision
  command:
  - /flow:start 354 (PLAN
  - Stranger Test of T5)
  situation:
  - A worker run's limit is stage budget - spent - overshoot allowance
  - and a run that ends with no result is charged its limit + allowance. That charge
    uses up the whole remaining stage budget
  - so no fai
- type: escalation-resolved
  captured_at: '2026-11-16T18:00:15Z'
  escalation_field: options
  outcome:
  - Cap each run's limit at the stage budget divided by the attempts allowed (2)
  - so a killed first run leaves budget for the retry; charging stays limit + allowance
  question_id: q-20261116T175135Z-5b9bc1
- type: stranger-test
  captured_at: '2026-11-16T18:00:55Z'
  result: BLOCK
  task_count: 16
  failed_task: T5
- type: escalation-asked
  captured_at: '2026-11-16T18:25:00Z'
  question_id: q-20261116T182500Z-134b73
  blocking: 'yes'
  class: decision
  command:
  - /flow:start 354 (PLAN
  - Stranger Test fixes)
  situation:
  - The budget split decided in q-20261116T175135Z-5b9bc1 used 2 runs per stage
  - but the state table allows 3 (attempts_exhausted = attempt reached 2; each failed
    run adds 1)
  - so halves leave the third ru
- type: escalation-resolved
  captured_at: '2026-11-16T18:25:01Z'
  escalation_field: options
  outcome:
  - Cap each run's limit at the stage budget divided by 3
  - one share per run the table allows
  question_id: q-20261116T182500Z-134b73
- type: escalation-asked
  captured_at: '2026-11-16T20:10:02Z'
  question_id: q-20261116T201002Z-68886a
  blocking: 'yes'
  class: decision
  command:
  - /flow:start 354 (PLAN
  - Stranger Test gate)
  situation: Five independent Stranger Test rounds each blocked the 1a plan with real
    gaps; the fifth round's gaps were run-time details.
- type: escalation-resolved
  captured_at: '2026-11-16T20:10:03Z'
  escalation_field: options
  outcome: Start building after the round-5 fixes; a remaining wrong expectation shows
    up as a RED test failing for the wrong reason and is fixed then
  question_id: q-20261116T201002Z-68886a
- type: escalation-asked
  captured_at: '2026-11-16T22:01:31Z'
  question_id: q-20261116T220130Z-3fa5d2
  blocking: soft
  class: decision
  command:
  - /flow:start 354 (CODE
  - T8 report)
  situation:
  - Before relaunching a failed stage the engine snapshots and resets the job clone
    with git clean -fd; an untracked nested git repository survives clean -fd
  - keeps the tree dirty
  - and makes the snapshot
- type: escalation-resolved
  captured_at: '2026-11-16T22:01:31Z'
  escalation_field: options
  outcome:
  - Park the job for a person
  - with no snapshot and no reset
  - naming the folder
  question_id: q-20261116T220130Z-3fa5d2
- type: goal-evaluation
  captured_at: '2026-11-17T22:00:24Z'
  goal_id: issue-354
  result: pass
  evidence_bundle: .flow/runs/2026-11-16T144941Z-issue-354
  failures: none
  commit: 62b1261887c02eccda5adaa067d121afe1544131
  note: G1 first sidecar's limitation was wrong (said P5 engine_charge was never re-run
    live); superseded by evidence-g1-eval-62b12618-r2
- type: goal-evaluation
  captured_at: '2026-11-18T00:28:08Z'
  goal_id: issue-354
  result: achieved
  trigger: user
  evidence_bundle: .flow/runs/2026-11-16T144941Z-issue-354
  failures: none
- type: goal-evaluation
  captured_at: '2026-11-18T05:10:45Z'
  goal_id: issue-354
  result: pass
  evidence_bundle: .flow/runs/2026-11-16T144941Z-issue-354
  failures: none
  commit: 031190b09548b6b51d25db4182c2833152959d66
  note: All 15 checks re-run after the review fixes; sidecars evidence-*-eval-031190b0
    supersede the 62b12618 ones. The goal file's evidence_ref values still name the
    62b12618 sidecars, because flow-goal-record.sh refuses to update an achieved goal.
- type: review-cycle
  captured_at: '2026-11-18T05:14:28Z'
  cycle: 1
  path: B
  findings_count: 3
  pr: 382
- type: workflow-run
  captured_at: '2026-11-18T06:26:31Z'
  workflow: start-issue
  run_id: 2026-11-16T144941Z-issue-354
  status: completed
---

## Design

## Design

### Risky files
- `plugins/flow/schema.json` — 4 fix commits among the last 200 commits
- `plugins/flow/references/gate-configuration.md` — 8 fix commits among the last 200 commits
- `plugins/flow/CHANGELOG.md` — 12 fix commits among the last 200 commits
- `plugins/flow/tests/lib/e2e.sh` — 4 fix commits among the last 200 commits

### Options
1. **Inside the probe module** — changes `_flow_factory.py` (7969 lines) to hold the engine as well as the probes, and its `main` to dispatch every subcommand; reuses everything in that module; adds only the launcher script (the design needs it as its own process, recognised by its command line) and `_flow_factory_schema.py` (named by the design); risk: the module grows past 12000 lines, the early worker check forces all of it to parse under old Pythons forever, and every build task edits one file, so the work runs one task at a time.
2. **One engine module beside the probe module** — adds `_flow_factory_engine.py` (jobs, table, next pass, person subcommands, staleness, git) plus `_flow_factory_launch.py`, `_flow_factory_schema.py` and `_flow_factory_caller.py`; reuses the probe module's helpers by import; risk: a module of several thousand lines that four or five build tasks edit at once.
3. **Engine modules by area (the plan's split)** — adds `_flow_factory_schema.py`, `_jobs`, `_table`, `_launch`, `_git`, `_caller`, `_staleness`, `_next`, `_person`, each owned by one build task; `_flow_factory.py` changes only in `main` (dispatch) and the probe functions 1a must change; risk: more interfaces between modules, fixed before the build starts.

### Chosen
Engine modules by area — option 2 also meets the criteria, but its single engine module would make the parallel build tasks edit one file; option 3 gives each task files it alone owns, with the interfaces fixed first.

### Reuses
- `plugins/flow/bin/_journal_atomic.py`: `acquire_lock` (:164, with a timeout), `write_json_file` (:880), `append_jsonl` (:928) for every job-state write
- `plugins/flow/bin/flow-mkdir.sh` for every directory the engine creates
- `plugins/flow/bin/_flow_factory.py`: `Refused` (:569), `which_real` (:867), `main_checkout` (:923), `factory_dir` (:946), `launch_env` (:2409), `PROBE_MODEL` (:2424), `run_costs` (:2576), `run_cmd` (:2976), `PERSON_SUBCOMMANDS` (:4285), `WRAPPED_FORMS` (:4289), `factory_lock` (:6914)
- `plugins/flow/bin/_flow_stream.py` `json_values` for stream-json
- `docs/flow-factory/check_transitions.py` (its `Checker` builds the test witnesses) and `test_check_transitions.sh`
- `plugins/flow/bin/cascade-resolve.sh` for settings (the `flow.factory.*` keys are read from the user view only, as design `settings_keys` says)
- `plugins/flow/tests/lib/e2e.sh` and the stand-ins in `plugins/flow/tests/fixtures/factory/`

### Does not add
- No second copy of the state table in code: the engine reads `plugins/flow/references/factory-transitions.json`.
- No GitHub write, no tier-gate change and no `factory-state-guard.sh` (1b).
- No real worktree, bootstrap or worker sandbox (1c); git runs in fixture clones only.
- No path from `flow-factory.sh` to the test entry point or to a fixture fact provider.
- No turn counter (P5 turn_limit is go), and no `maxStageAttempts` reading (the table says 2).
- No release and no version change.
- No new helper in `tests/lib/e2e.sh`; factory helpers go in a new `tests/lib/factory-e2e.sh`.
- No settings key outside design `settings_keys`, and only the keys 1a reads.

### Invariants
- Only the engine writes job state, always under the job lock and through `_journal_atomic.py`; the global lock is taken before a job lock, and every lock wait has a timeout.
- Every job move is a row of `references/factory-transitions.json`; anything else exits 3 with `TRANSITION_REFUSED` or `EVENT_REFUSED` and changes nothing.
- `references/factory-transitions.json` equals `docs/flow-factory/transitions.json` byte for byte, and the checker passes on it.
- With no factory setting, `flow-factory.sh context --mode` prints `FACTORY_MODE=off` and starts no Python.
- With `flow.factory.enabled` not true, `next` and the acting person subcommands exit 5 with `FACTORY_REFUSED=disabled` and change nothing.
- A person subcommand run from a worker (FLOW_FACTORY_JOB, FLOW_FACTORY_DIRECTIVE or FLOW_FACTORY_IO set, as design person_channels names them, or a live lease's launcher or claude process among its ancestors) exits 4 with `PERSON_ONLY_REFUSED` before any other check and changes nothing.
- Each run is charged its own cost (`model_usage_since_last_result`), never the session total, and every launch names `--model`.

## Specification

## Specification

_Captured by specification-capture skill on 2026-11-16. Source: mixed (from-design for the Does not add and Invariants items; user-confirmed drafts from the 1a plan for the rest)._

### Non-goals

- No GitHub write is sent: the outbox holds items and nothing sends them (1b).
- No tier-gate change and no `factory-state-guard.sh` (1b).
- No worker area, real job clone, bootstrap, ports, worker token or worker sandbox (1c); git runs only in fixture clones.
- No headless runner, scheduled runner, interactive executor, `wait`, `question` or `await` (1c).
- No factory mode in flow's commands or the ask policy (1d).
- No gate or protected-path check (1e); gate rows are driven by fixtures only.
- No cost cap (1g).
- No path from `flow-factory.sh` to the test entry point or to a fixture fact provider.
- No second copy of the state table in code: the engine reads `plugins/flow/references/factory-transitions.json`.
- No turn counter, and no reading of `maxStageAttempts` (the table says 2).
- No release and no change to the flow version.
- No new helper in `plugins/flow/tests/lib/e2e.sh`; factory helpers go in `plugins/flow/tests/lib/factory-e2e.sh`.
- No settings key outside design.json `settings_keys`, and only the keys 1a reads.
- No separate OS user for workers.
- No change to any flow behaviour while the factory is off.

### Failure modes

- **Timeouts** — Every lock wait has a timeout. `next` stops starting work as it nears `nextBudgetSeconds` and returns. A stage past its timeout gets SIGTERM, then SIGKILL after 30 s. A lease with no heartbeat for `leaseSeconds` is revoked only after the launcher (pid and start time) is checked. A probe holding its lock never blocks `next`.
- **Partial failures** — A killed claude gives a stage_failed report (rows 39, 39d); a killed launcher stops the heartbeat and gives lease expiry (rows 39l, 39ld). A process group that survives the kill is recorded and parks the job at the next launch (row 43g). A dirty tree is snapshotted, untracked files included, to `refs/flow-factory/issue-N/snapshot-<k>`, then reset and cleaned, and the relaunch starts a fresh session. A run with no result event is charged its limit plus one turn's allowance. An unreadable or invalid job.json is listed as unreadable, and `rebuild` restores it from events.jsonl.
- **Invalid input** — A move outside the table exits 3 (`TRANSITION_REFUSED` or `EVENT_REFUSED`) and changes nothing. A fact combination with no winning row moves nothing. A report from a revoked lease, from a pid other than the lease's launcher, or from a claude descendant is refused. A malformed directive id or a symlinked pending report is refused. A person subcommand from a worker exits 4 with `PERSON_ONLY_REFUSED` before any other check.
- **Missing context** — No probe record, or a recorded interpreter that is missing or fails vetting: exit 5 with a `next:` line, never PATH python. `flow.factory.enabled` not true: `next` and the acting person subcommands exit 5 with `FACTORY_REFUSED=disabled`. Stale platform record: `next` syncs and moves jobs, starts no worker, counts no attempt, and prints the re-run command. Failed environment re-run: no launch, and a `PAUSED` status line. `ps` unreadable during the ancestry walk: the caller is refused. Usage limit: `paused_until` is set and no attempt is counted. No controlling terminal, or inside a session, for a person subcommand: exit 4 with `PERSON_CONFIRM_REQUIRED`.

### Interface contracts

- Only the engine writes job state, always under the job lock and through `plugins/flow/bin/_journal_atomic.py`; the global lock is taken before a job lock, and every lock wait has a timeout. (from-design)
- Every job move is a row of `plugins/flow/references/factory-transitions.json`; that file equals `docs/flow-factory/transitions.json` byte for byte and passes `check_transitions.py`. (from-design)
- Exit codes: 0 answered; 2 usage error; 3 `TRANSITION_REFUSED=<from>-><to>: <reason>` or `EVENT_REFUSED=<event> state=<state>`; 4 `PERSON_ONLY_REFUSED=<reason>` or `PERSON_CONFIRM_REQUIRED next: run <command> in a terminal`; 5 `FACTORY_REFUSED=<reason>` or `PROBES_STALE=<group>`. Every refusal is one stdout line.
- With no factory setting, `flow-factory.sh context --mode` prints `FACTORY_MODE=off` and starts no Python. With `flow.factory.enabled` not true, `next` and the acting person subcommands exit 5 with `FACTORY_REFUSED=disabled` and change nothing. (from-design)
- A person subcommand run from a worker (FLOW_FACTORY_JOB, FLOW_FACTORY_DIRECTIVE or FLOW_FACTORY_IO set, as design person_channels names them, or a live lease's launcher or claude process among its ancestors) exits 4 with `PERSON_ONLY_REFUSED` before any other check and changes nothing. (from-design)
- `next` prints JSON lines (person items, then status lines), then exactly one of `wait`, `idle` or `done`.
- job.json and directive files validate against `plugins/flow/schemas/v1/factory-job.schema.json` and `factory-directive.schema.json` under both the stdlib validator and jsonschema.
- The worker environment is built from nothing; FLOW_FACTORY_JOB_KEY, FLOW_FACTORY_ISSUE, FLOW_FACTORY_BRANCH and FLOW_FACTORY_GOAL_ID equal job.json and in/job.env; every launch names `--model` (`worker.model`, else the probe record's platform model).
- Launcher command line: `<recorded python> -E <plugin>/bin/_flow_factory_launch.py --factory-dir <abs> <directive-id>`; the launcher applies its own report in its own process.
- Each run is charged its own cost, the sum of `model_usage_since_last_result`, never the session total. (from-design)
- events.jsonl line: event, from, row, to or stay, effects applied and deferred, attempt, channel, caller, time.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| worker refusal order and record lookup | the worker check runs after argument parsing or job lookup, or the record is found from the cwd's checkout | person subcommand from a process with every FLOW_FACTORY_* cleared, cwd in another clone, a live launcher ancestor, bad arguments, job outside the event's states → right: exit 4 `PERSON_ONLY_REFUSED=lease_ancestor`; wrong: exit 2, 3 or 5 |
| row precedence of derived facts | the confirm park (row 40, precedence 45) is taken before the pre-push check (row 21f, precedence 44) | open_pr stage success with both inputs true → right: row 21f wins and no push intent is recorded; wrong: row 40 parks and records a push intent |
| relaunch kind after a dirty tree | resume is keyed on "a session id exists", and the snapshot leaves out untracked files | failed stage with a recorded session id, a modified tracked file and a new untracked file → right: both files in the snapshot ref, relaunch carries `--session-id`; wrong: relaunch carries `--resume`, or the untracked file is lost |
| cost charged per run | a resumed run is charged `total_cost_usd` | resumed run with a session total of $1.20 and `model_usage_since_last_result` summing to $0.23 → right: job spend rises by $0.23; wrong: by $1.20 |
| two concurrent `next` calls | both launch the same job, or one blocks behind the other's lock | two `next` started together, one job due, concurrency 1 → right: one directive and one lease, both return within `nextBudgetSeconds`; wrong: two launches, or a return after the budget |
| partial platform re-run | the group's current version hides an entry still stamped with the old one | platform group stamped with the installed claude version, P5 entry with an older one → right: stale, no worker, no attempt, re-run line printed; wrong: a worker launches |

## Spec Validation Gate

| # | Acceptance criterion | Verification command | Gate |
|---|---|---|---|
| AC1 | No factory setting: `context --mode` prints `FACTORY_MODE=off` without Python; existing suites unchanged | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-wrapper.test.sh` (the existing suites: AC11's full run) | PASS |
| AC2 | Checker passes on the shipped table; mutation test rejects every broken edit | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-transitions.test.sh` | PASS |
| AC3 | Every row driven through `next` with fixtures; off-table move refused with its own exit code | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine.test.sh` | PASS |
| AC4 | Two `next` at once launch one worker; `next` within its budget | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-next.test.sh` | PASS |
| AC5 | Killed worker relaunched; dirty-tree relaunch fresh; old edits in a snapshot ref | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-next.test.sh plugins/flow/tests/e2e-factory-engine-git.test.sh` | PASS |
| AC6 | Worker env holds job key, issue, branch, goal id equal to the record | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-launch.test.sh` | PASS |
| AC7 | Each person-only command from a worker, every wrapped form: `PERSON_ONLY_REFUSED` | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-refusal.test.sh` | PASS |
| AC8 | No record or missing interpreter: status line naming the next step | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-wrapper.test.sh` | PASS |
| AC9 | Stale platform record: sync and moves, no worker, no attempt, re-run command | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-probes.test.sh` | PASS |
| AC10 | `rebuild` from the event log; `status` prints every job and status line | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-person.test.sh` | PASS |
| AC11 | E2E through the harness, an artifact per scenario, full suite before the push | `FLOW_E2E_ARTIFACT_DIR="$(mktemp -d)" plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-*.test.sh`, and `plugins/flow/tests/run.sh` (full suite) before the push | PASS |
| AC12 | Merges without a release; flow version unchanged and in sync | `v=$(jq -r .version plugins/flow/.claude-plugin/plugin.json); [ "$v" = "$(git show origin/main:plugins/flow/.claude-plugin/plugin.json \| jq -r .version)" ] && jq -e --arg v "$v" '.plugins[] \| select(.name=="flow") \| .version == $v' .claude-plugin/marketplace.json` | PASS |
| G1 | P5 cost scope: the engine charges `model_usage_since_last_result` | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-launch.test.sh`, then the P5 re-run (asked first) records `engine_charge` go: `jq -e '.probes.P5.parts.engine_charge.result == "go"' docs/flow-factory/probes.json` | PASS |
| G2 | Worker model named on every launch | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-launch.test.sh` | PASS |
| G3 | Budget limit overshoot allowed for | `plugins/flow/tests/run.sh plugins/flow/tests/e2e-factory-engine-launch.test.sh` | PASS |

## Stranger Test

BLOCK — T2, T3, T4, T5, T7, T10, T11, T16 (16 tasks reviewed by an independent agent on 2026-11-16, against d7d098bc). The plan's own PASS was not independent. Main gaps: a directive field `max_turns` left after the no-turn-limit decision; the stage-budget arithmetic left no budget for a relaunch after a run with no result (decided: each run's limit is capped at the stage budget ÷ 2, question q-20261116T175135Z-5b9bc1); no test for the allowance rising above its $0.50 floor; a probe-record pattern the export would break; T16 steps that would rewrite the released 3.17.0 entry and the merged release wording; and five scenario errors in T3, T4 and T11. The plan is being corrected, and the test is run again before any code.

Rounds 2-5 (2026-11-16, each an independent agent): round 2 blocked T11, T12 and T13; round 3 blocked T2, T3, T6, T11, T12 and T13; round 4 blocked T1, T3, T3b, T10 and T11; round 5 blocked T3, T4, T7, T9, T10, T11 and T13. Every gap was fixed in the plan. Among them: tests that could have written into the main checkout's factory folder or read the person's settings, now all run in the scratch folder and home; a stage allowed three runs while the budget split assumed two (now thirds); start times compared with and without the padding `ps` prints on macOS. After round 5 the user decided to start building without a sixth round; a remaining wrong expectation will show as a test that fails for the wrong reason when it is first run.

## Build decisions not in the plan

Taken while building, each inside a decision already made; listed so a reviewer can check them.

- A launch the launcher refused without recording a reason leaves the job waiting forever, because the spawned launch writes nowhere `next` reads. A directive with no lease and no result after `leaseSeconds` therefore expires as `lease_expired`, with no charge (T11).
- When a table row kills a live worker (rows 52, 53, 54 and the like), that run is charged its limit plus the allowance, as a run lost at lease expiry is (T11).
- For a worker launch, an exhausted stage budget prints `PAUSED stage_budget_exhausted …` and creates no directive; a missing prompt template prints `PAUSED prompt_missing … next: add templates/factory/<t>.prompt.md to the plugin` (T11).
- A nested repository inside an untracked folder is found by walking that folder without following symlinks, bounded at 20 levels and 10000 entries; past the bound the job parks with `NESTED_REPOSITORY_SCAN_LIMIT` rather than missing one (T8 follow-up, under the nested-repository decision).
- The engine runs with PYTHONPATH unset and PYTHONSAFEPATH=1, keeping the original in FLOW_USER_PYTHONPATH, so none of its child processes can start a Python found through an outside PYTHONPATH (T4).
- The probe export writes paths from the top of the checkout that holds the copy, so an export from a linked worktree stays correct after its branch merges.
- T7 (launcher) and T11 (next pass) were written before their tests, against the repository's rule. Each was checked instead by single-change mutants: 29 for T7 and 7 for T11, every one caught by its target scenario.
