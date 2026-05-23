---
issue: 110
created: '2026-05-23T00:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-05-23T00:52:49Z'
  by: flow-start
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: verdict
  captured_at: '2026-05-23T01:23:11Z'
  result: PASS
---
# Issue #110 — v3 integration: wire FlowGoal + FlowRun into the 7 commands

Branch: `feature/issue-110-v3-command-integration`

## Summary

#109 shipped the v3 runtime layer as pure infrastructure (helpers + skills + schemas +
the `goal` command) but left the existing flow commands byte-identical to v2.4.0. This
issue wires those primitives into start/debug/address/review/pr/merge/release so goals +
runs are automatic. Amended by #111: review/address are FlowRun-only (no FlowGoal), and
the goal-creation default (`goalCreation: auto`) is owned by #111 — this issue does NOT
add a binary `requireGoalForStart` flip.

## Verified pre-state (2026-05-23)

- #109 merged (commit 34a8d75). All referenced helpers present: `flow-record-activity.sh`,
  `flow-goal-record.sh`, `flow-active-goal.sh`, `flow-record-evidence.sh`,
  `flow-record-verdict.sh`, `journal-record.sh`. All referenced skills present
  (`run-state-management`, `goal-contract-capture`, `goal-evaluator`, `goal-evidence-ledger`,
  `specification-capture`). `goal-evaluator-judge` is an **agent**, not a skill.
- None of the 7 commands wire `.flow` yet (confirmed by grep).
- **status.md + learn.md `.flow` mining already shipped with #109** (cycle-13): status has
  `### FlowGoal State` + `### Recent Runs`; learn has `### FlowRun Events` + Goal Failure
  Patterns. Passing tests: `flow-status-learn-v3.test.sh`, `flow-cycle14-behavioral.test.sh`.
  → AC6 main + AC7 are already satisfied. Remaining AC6 sub-part: status has NO triggers section.
- Settings: `workflows.enabled=false`, `triggers.enabled=false` (AC8 flips both → true);
  `goals.enabled=true` already; `goalCreation` absent (owned by #111).
- Test baseline: `bash plugins/flow/tests/run.sh` → TOTAL pass=646 fail=0.

## Design decisions

- **Skill-owned writes.** Commands do NOT inline FlowRun/FlowGoal YAML composition. They
  invoke `Skill(run-state-management)` (run create + activity + state transition) and
  `Skill(goal-contract-capture)` / `Skill(goal-evaluator)` (start/debug only). The skills own
  the file layout; commands pass workflow id, run id, context, phase.
- **Surgical insertion.** Add hook points at existing phase boundaries; do NOT restructure
  command logic (non-goal). FlowRun create at entry; activity write at each phase boundary;
  terminal transition + `workflow-run` artifact update at completion.
- **Per-#111 split.** start/debug: FlowGoal + FlowRun. review/address/release: FlowRun only.
  pr/merge: read the active goal and gate on `lifecycle.status: achieved`.
- **Gating asymmetry (AC4 vs AC5).** `/flow:pr` gate has an override path (six-field
  AskUserQuestion escalation → `escalation-resolved` artifact). `/flow:merge` gate is Tier 3,
  NO override beyond the existing merge confirmation — refuse if goal not achieved or any
  linked FlowRun still `active`.
- **Test pattern.** Each new `tests/<cmd>-v3-integration.test.sh` is a source-presence +
  behavioral test mirroring `flow-agentteam-model.test.sh`: assert the command markdown wires
  the helper/skill, and (where feasible) extract+run the entry bash block against a scratch
  repo to assert a valid `.flow/runs/<id>/run.yaml` (and `.flow/goals/*.goal.yaml` for
  start/debug; NO goal file for review/address — #111 AC-3) is produced.

## Specification

### Non-goals
- Path B / agent-team review behavior, model selection — unrelated (#112, shipped).
- Restructuring command markdown beyond surgical hook-point additions — preserve phase structure.
- The `goalCreation` 3-state default and any `requireGoalForStart` flip — owned by #111 AC-1.
- FlowGoal creation for `/flow:review` and `/flow:address` — #111 AC-3 makes them FlowRun-only.
- Re-implementing status/learn `.flow` mining — already shipped with #109 (only add the missing triggers section to status).
- Polyglot Windows hook wrapper — separate pre-existing tech-debt PR.
- New goal-creation default flip for review/address — out by construction (FlowRun-only).

### Failure modes
- `python3` / PyYAML missing → helpers exit 2 with a clear stderr message; command surfaces
  it as a blocked activity rather than crashing (helpers already degrade gracefully).
- No active goal when `/flow:pr` or `/flow:merge` runs → `flow-active-goal.sh` exits 1;
  treat as "no goal to gate" only when `flow.goals.enabled` is false OR the workflow that
  created the branch was review/address (FlowRun-only). Otherwise (start/debug-derived branch
  with goals enabled) a missing goal is itself a gate failure → escalate.
- `>1` active goal → `flow-active-goal.sh` exits 3 (degenerate); pr/merge refuse and point to
  `/flow:goal history`.
- Run dir already exists for the computed run id → run-state-management uses an ISO-timestamp
  id so collisions are implausible; if it occurs, the create is race-safe (dir-absent invariant).
- `flow.goals.enabled=false` → goal creation + gates are no-ops; FlowRun wiring still runs
  (runs are gated by `flow.runtime.enabled`, default true).

### Interface contracts
- FlowRun create: `Skill(run-state-management)` writes `.flow/runs/<ISO-id>/run.yaml`
  conforming to `schemas/v1/run.schema.json` with `state.status: active`.
- Journal artifact: `bin/journal-record.sh --issue <N> --type workflow-run --metadata
  workflow=<id> --metadata run_id=<id> --metadata status=active|completed`.
- FlowGoal create (start/debug): `Skill(goal-contract-capture)` writes
  `.flow/goals/issue-<N>.goal.yaml`; debug uses run id-derived slug when no issue.
- pr/merge gate read: `bin/flow-active-goal.sh --status` (0=found, 1=none, 2=infra, 3=degenerate)
  and `--ac-summary` for the missing-evidence escalation body.
- Settings: `flow.workflows.enabled: true`, `flow.triggers.enabled: true` in settings.json;
  schema unchanged (already enums/booleans).
- Each new test file: `bash plugins/flow/tests/<cmd>-v3-integration.test.sh` passes under the
  zero-dependency harness; `bash plugins/flow/tests/run.sh` exits 0 with count ≥ 646 + new asserts.

## Acceptance criteria → verification command map

| # | AC | Verification |
|---|----|--------------|
| 1 | 7 commands write FlowRun at entry + phase boundaries | `tests/<cmd>-v3-integration.test.sh` asserts run.yaml created + activity-write wiring present |
| 2 | 7 commands write `workflow-run` journal artifacts | test asserts `journal-record.sh ... --type workflow-run` wired per command |
| 3 | start/debug create FlowGoals; review/address FlowRun-only | start/debug tests assert goal file; review/address tests assert NO goal file |
| 4 | pr blocks when goal not `achieved` (override) | `tests/pr-v3-integration.test.sh` asserts gate + override escalation wiring |
| 5 | merge blocks when goal not `achieved` (no override) | `tests/merge-v3-integration.test.sh` asserts gate, no override |
| 6 | status reads `.flow` + shows goal/run/triggers | existing status-learn-v3 test (goal/run) + new triggers-section assert |
| 7 | learn mines `events.jsonl` for stuck patterns | existing `flow-status-learn-v3.test.sh` (already green) |
| 8 | settings workflows.enabled+triggers.enabled true | `python3 -c` enum/flag assert in a test |
| 9 | 7 new integration test files pass | `bash plugins/flow/tests/run.sh` exits 0 |
| 10 | existing per-command tests pass unchanged | full-suite run, no regressions |
| 11 | `run.sh` exits 0 | exit code check |
| 12 | CHANGELOG entry | grep CHANGELOG for the integration entry |

<!-- auto-log: 2026-05-23 02:53 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-110.md -->

<!-- auto-log: 2026-05-23 02:58 commit "feat(flow): wire FlowRun into release.md (#110)" -->

<!-- auto-log: 2026-05-23 02:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 03:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 03:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-05-23 03:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 03:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-05-23 03:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-05-23 03:00 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-23 03:00 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/address-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:01 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/start-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/start-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:01 commit "feat(flow): wire FlowRun into start.md linked to FlowGoal (#110)" -->

<!-- auto-log: 2026-05-23 03:03 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-23 03:03 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-23 03:03 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/pr-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-23 03:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-23 03:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-23 03:05 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/merge-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:05 commit "feat(flow): wire FlowRun into pr/merge/review/address (#110)" -->

<!-- auto-log: 2026-05-23 03:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/debug.md -->

<!-- auto-log: 2026-05-23 03:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/debug.md -->

<!-- auto-log: 2026-05-23 03:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/debug.md -->

<!-- auto-log: 2026-05-23 03:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/specification-capture/SKILL.md -->

<!-- auto-log: 2026-05-23 03:07 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/debug-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/debug.md -->

<!-- auto-log: 2026-05-23 03:07 commit "feat(flow): wire FlowRun + FlowGoal into debug.md (#110)" -->

<!-- auto-log: 2026-05-23 03:08 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-23 03:09 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-23 03:09 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/settings.json -->

<!-- auto-log: 2026-05-23 03:09 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/CHANGELOG.md -->

<!-- auto-log: 2026-05-23 03:09 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/status-triggers-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:10 commit "feat(flow): status Active Triggers section + enable workflows/triggers defaults (#110)" -->

<!-- auto-log: 2026-05-23 03:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/release.md -->

<!-- auto-log: 2026-05-23 03:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-23 03:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-23 03:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 03:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-05-23 03:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/debug.md -->

<!-- auto-log: 2026-05-23 03:18 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/release.md -->

<!-- auto-log: 2026-05-23 03:18 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/release.md -->

<!-- auto-log: 2026-05-23 03:18 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/run-state-management/SKILL.md -->

<!-- auto-log: 2026-05-23 03:18 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/workflows/review-pr.workflow.yaml -->

<!-- auto-log: 2026-05-23 03:18 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/workflows/review-pr.workflow.yaml -->

<!-- auto-log: 2026-05-23 03:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/workflows/review-pr.workflow.yaml -->

<!-- auto-log: 2026-05-23 03:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/workflows/address-pr.workflow.yaml -->

<!-- auto-log: 2026-05-23 03:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/workflows/address-pr.workflow.yaml -->

<!-- auto-log: 2026-05-23 03:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/workflows/address-pr.workflow.yaml -->

<!-- auto-log: 2026-05-23 03:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-23 03:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-23 03:20 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-23 03:20 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-23 03:20 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/release-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:20 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/release-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:20 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/start-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:20 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/merge-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:21 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/debug-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:21 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:21 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/address-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:21 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/status-triggers-v3-integration.test.sh -->

<!-- auto-log: 2026-05-23 03:22 commit "fix(flow): self-review findings — schema-valid run/goal ids, workflow-yaml reconciliation (#110)" -->
