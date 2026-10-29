---
issue: 314
created: '2026-10-29T10:14:15Z'
artifacts:
- type: specification
  captured_at: '2026-10-29T10:14:15Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-10-29T12:08:40Z'
  goal_id: issue-314
  source: issue
- type: workflow-run
  captured_at: '2026-10-29T12:09:59Z'
  workflow: start-issue
  run_id: 2026-10-29T100336Z-issue-314
  status: active
- type: review-cycle
  captured_at: '2026-10-29T12:09:59Z'
  cycle: 1
  path: B
  findings_count: 14
  pr: 315
- type: goal-evaluation
  captured_at: '2026-10-29T12:11:41Z'
  goal_id: issue-314
  from: active
  to: waiting_for_ci
  trigger: command
  reason: ci-running
- type: verdict
  captured_at: '2026-10-29T12:35:42Z'
  result: PASS
  pr: 315
- type: goal-evaluation
  captured_at: '2026-10-29T12:35:49Z'
  goal_id: issue-314
  from: waiting_for_ci
  to: active
  trigger: command
  reason: ci-finished
- type: goal-evaluation
  captured_at: '2026-10-29T12:35:49Z'
  goal_id: issue-314
  from: active
  to: achieved
  trigger: evaluator
  reason: verdict-pass
- type: workflow-run
  captured_at: '2026-10-29T12:36:07Z'
  workflow: start-issue
  run_id: 2026-10-29T100336Z-issue-314
  status: completed
---
# Issue #314: split the Linux flow test job

Branch: feature/issue-314-split-linux-flow-tests (from origin/main 53285b73).

## Decision: approach

User chose (2026-10-29) to split the Linux job into 4 shards over raising the limit to 60 min. Measurements: passing Linux runs 31-41 min (slowest 41 min, run 38721713936, 2026-10-15). Per-file times from one run (40837192187, main, 2026-10-29, 37.7 min): round-robin by sorted name gives shards of 8.5, 11.2, 5.4, 12.7 min. Balance rests on that one run; re-measure from the PR's own CI jobs.


## Specification



_Captured by specification-capture skill on 2026-10-29. Source: user-confirmed._

"The suite" and "the slowest passing run" in the acceptance criteria are read per Linux job once the suite is split.

### Non-goals

- No test file is made faster.
- macOS stays one job with its 45-minute limit.
- The set of tests run does not change: each file runs in exactly one Linux job.
- Files are assigned round-robin by sorted name, with no timing-based balancing.

### Failure modes

- **Timeouts** — each Linux shard job has its own 20-minute limit; only that shard shows cancelled.
- **Partial failures** — fail-fast stays off, so every shard reports and uploads its own artifacts.
- **Invalid input** — a malformed FLOW_TEST_SHARD (not K/N, K<1, K>N, N<1, non-digits) makes run.sh exit 2 with a message and run no file.
- **Missing context** — FLOW_TEST_SHARD unset means run all files, as today.

### Interface contracts

- run.sh reads FLOW_TEST_SHARD=K/N (integers, 1<=K<=N) and runs the files whose 0-based position i in its list has i mod N = K-1; it prints `run.sh: shard K/N runs X of Y files` and unsets the variable so suites do not inherit it.
- The CI matrix has entries {os, shard, shards}: Linux 1..4 of 4, macOS 1 of 1; artifact names are `flow-e2e-<os>-<shard>-of-<shards>`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| shard index base | off by one: i mod N = K instead of K-1 | files a..e, shards 1/2 and 2/2 → right: {a,c,e} and {b,d}; wrong: a file dropped or shard 2 empty |
| explicit file arguments | selection applied only to the glob | 3 named files with 1/3 → right: 1 file runs; wrong: all 3 run |
| variable inheritance | suites see FLOW_TEST_SHARD | a fixture test prints FLOW_TEST_SHARD → right: unset; wrong: 1/2 |
| value validation | malformed values accepted | 0/4, 5/4, 1/0, a/b, 1/4x → right: exit 2, no file runs; wrong: some files run |

## Review and verification


- Six review rounds (2026-10-29). The run.sh change drew no P1 or P2 in any round. Every P2 was in the CI workflow test: a wrong workflow that still passed. Text matching gave way to a PyYAML check, then deny-lists gave way to exact comparison of every step of both jobs, the triggers and the top-level keys, with the matrix checked by meaning (parts 1..N per OS, a floor of 20 min for Linux and 45 for macOS). The check guards against mistakes; a pull request can edit it along with the workflow.
- After round 6 (3 P2, 3 P3), the user chose to fix all six and open the PR without another review round.
- Mutation: 78 mutant workflows from the reviews; all are refused except three actionlint rejects and three with the same parsed content (`04`, `2_0`, a row in block layout). The run.sh mutants (index base, unset, leading zero, K>N, empty part, no slash) all fail run-shard.test.sh.
- Local run at e68cec83..a652ed44: the four parts together ran each of the 101 files once. Parts 2-4 passed. Part 1 had 5 SIGINT-timing failures in e2e-flow-dir-symlinks.test.sh while four parts ran at once on one laptop; the file alone passed 1266/0 on the same commit.
- Acceptance criteria are measured on the pull request's CI run with ~/flow-310-work/check-ac.sh <run-id>.

## Verdict


- Verdict PASS on both criteria (2026-10-29), from flow-tests runs 40871146691 (head fcbf9ad9) and 40869949651 (head afb40923). The slowest Linux part was 806 s: × 1.3 = 1048 s ≤ 1200 s, and the 20-minute limit leaves 49% headroom. macOS took 22.6 and 21.2 minutes against its 45-minute limit.
- The first judgement failed criterion 1 on the evidence bundle: three risk-map rows had no input and expected value, and no line number. With the rows and line numbers added, it passed.
- run.sh also rejects K or N with a leading zero or more than four digits (01/4, 1/04, 99999/99999). That rule is stricter than the specification's list of malformed values; the code comment and run-shard.test.sh:97-102 state it.
