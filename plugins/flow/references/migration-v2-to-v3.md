# Migrating from Flow v2.x to v3.0

Flow v3.0 introduces a runtime layer (FlowGoal, FlowWorkflow, FlowTrigger, FlowRun, FlowActivity, FlowEvidence) on top of the existing flow plugin. **Existing v2.x users see no breaking changes by default** — the runtime layer is opt-in via `flow.goals.requireGoalForStart`, `flow.workflows.enabled`, and `flow.triggers.enabled`, all of which default to `false` or carefully chosen safe defaults at GA.

## What's new

| v2.x | v3.0 |
|---|---|
| Decision journal at `.decisions/issue-N.md` only | Decision journal + runtime state at `.flow/` |
| `verdict-judge` agent runs once per PR | `verdict-judge` unchanged + new `goal-evaluator-judge` for loop-time evaluation |
| `specification-capture` skill produces journal entries | Same; now also feeds FlowGoal contracts via `goal-contract-capture` |
| Stop hooks: none from flow | Stop hook in warn-default mode; opt-in `evaluator-loop` mode |
| Resumability: session-bound TODO tracking | Durable FlowRun + FlowActivity ledger; `/flow:resume` |
| Workflow structure: documented in command markdown | Same + machine-readable `*.workflow.yaml` (M4) |
| Trigger mechanism: none | FlowTrigger artifacts + `/flow:watch` (no native /loop invocation) |

## Settings changes

All v3 settings live under the `flow.*` namespace (cascade-resolved via `bin/cascade-resolve.sh`). Default values at GA:

```yaml
flow:
  runtime:
    enabled: true             # master switch for .flow/ layer
    stateDir: .flow
    runRetentionDays: 30
  goals:
    enabled: true             # master switch for FlowGoal feature
    requireGoalForStart: false  # /flow:start does NOT auto-create goals; users opt in via /flow:goal
    stopHookEnforcement: warn   # passive warning; no LLM cost
    failAfterStuckTurns: 3
    judge:
      model: haiku
      timeoutSeconds: 60
  workflows:
    enabled: false            # /flow:workflow opt-in
  triggers:
    enabled: false            # /flow:trigger opt-in
    allowedTypes: [manual, hook, loop_prompt]
    allowAutonomousMerge: false
    allowTriggerCreationFromTriggeredRun: false
    defaultConcurrency: skip_if_running
    maxActiveTriggers: 5
```

To disable the v3 runtime entirely (rollback to v2.x behavior):

```yaml
flow:
  runtime:
    enabled: false
  goals:
    enabled: false
```

This is a clean rollback — existing commands work identically to v2.x.

## File-tree changes

New plugin directories (all under `plugins/flow/`):
- `schemas/v1/` — 6 JSON Schemas (goal, run, activity, evidence, workflow, trigger)
- `workflows/` — 7 plugin-shipped FlowWorkflow definitions
- `triggers/templates/` — 3 plugin-shipped FlowTrigger templates
- `skills/goal-contract-capture/`, `goal-evaluator/`, `goal-evidence-ledger/`, `goal-lifecycle/`, `run-state-management/`, `workflow-validation/`, `trigger-policy/` — 7 new skills

New plugin files:
- `agents/goal-evaluator-judge.md`
- `commands/goal.md`, `workflow.md`, `trigger.md`, `watch.md`, `run.md`, `resume.md`
- `bin/_journal_atomic.py`, `flow-record-activity.sh`, `flow-record-evidence.sh`, `flow-goal-record.sh`
- `hooks/scripts/flow-goal-stop.sh`, `flow-goal-evaluator.sh`, `flow-run-deterministic-checks.sh`, `session-end-state.sh`
- `references/flow-goals.md`, `stop-hook-goal-enforcement.md`, `flow-runtime-state.md`, `flow-workflows.md`, `flow-triggers.md`, `migration-v2-to-v3.md`

Project-local generated directories (`.flow/`):
- `.flow/goals/` — tracked (team-shared goal contracts)
- `.flow/workflows/` — tracked (project overrides)
- `.flow/triggers/` — mixed (non-.local tracked; .local gitignored)
- `.flow/runs/` — gitignored
- `.flow/evidence/` — gitignored

The repo `.gitignore` was updated (M1) with the split policy.

## Refactored code

`bin/journal-record.sh` — the Python heredoc body (lines 120-295 in v2.x) was extracted into `bin/_journal_atomic.py` (M1). The CLI surface, exit codes, and stderr messages are byte-identical; all 14 existing tests in `journal-record.test.sh` pass unchanged after the refactor.

If your code depends on `journal-record.sh`'s observable behavior, no changes are needed. If you import `_journal_atomic.py` from a custom helper, follow the patterns in `flow-record-activity.sh` and `flow-record-evidence.sh`.

## Removed features

None. v3.0 is purely additive.

## Hook registration changes

`hooks/hooks.json` gained two new entries:

```json
"Stop": [{"hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/flow-goal-stop.sh"}]}],
"SessionEnd": [{"matcher": "", "hooks": [
  {"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-end-learn.sh"},   // existing
  {"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-end-state.sh"}    // new in M3
]}]
```

The new Stop hook is silent (`{"decision":"approve","reason":"no active flow goal"}`) for users who haven't created any FlowGoals. The new SessionEnd entry only prints a notice when an active FlowRun exists.

## Behavioral changes (when goals are opted in)

When a user sets `flow.goals.requireGoalForStart: true`:
- `/flow:start <issue>` creates `.flow/goals/issue-<N>.goal.yaml` after the Spec Validation Gate.
- The Stop hook fires after every turn; in `warn` mode (default), it nudges when ACs lack evidence.
- `/flow:pr` checks goal status before allowing PR creation.
- `/flow:merge` requires `lifecycle.status: achieved`.

When integration commits land (deferred to a follow-up PR), these behaviors become default. Until then, users invoke `/flow:goal create` directly.

## Test totals

| Milestone | Tests added | Total at end of milestone |
|---|---|---|
| Baseline v2.4.0 | — | 186 |
| M1 | +57 (schemas, helpers, refactor verification) | 243 |
| M2 | +12 (Stop hook) | 255 |
| M3 | 0 (infrastructure only) | 255 |
| M4 | 0 (inline schema validation in M5+) | 255 |
| M5 | 0 (inline schema validation) | 255-259 |

Test additions for per-skill, per-command, and full workflow integration are deferred to follow-up PRs.

## Version timeline

| Milestone | Plugin version | Marketplace version |
|---|---|---|
| v2.4.0 (baseline) | 2.4.0 | matches |
| M1-M5 (in-flight) | 2.4.0 (unchanged through milestone commits) | unchanged |
| M6 GA | 3.0.0 | bumped per existing repo cadence |

## What ships in the v3 GA PR

- M1: Runtime state foundation (schemas, atomic helpers, manifest extensions, `.gitignore`)
- M2: FlowGoal v1 (skills, agent, command, Stop hook, settings)
- M3: FlowRun + FlowActivity infrastructure (skill, command, SessionEnd hook, reference)
- M4: FlowWorkflow YAMLs + validation (schema, 7 workflows, skill, command, reference)
- M5: FlowTrigger + watch mode (schema, templates, skill, commands, reference)
- M6: Migration guide, README updates, version bump to 3.0.0

## What's deferred to follow-up PRs

- Integration into existing commands (start.md, debug.md, address.md, review.md, pr.md, merge.md, release.md) — i.e., making them write FlowRun records, create FlowGoals automatically, and consult goal lifecycle.
- Per-skill / per-command unit tests for M3-M5 deliverables.
- Polyglot Windows wrapper for hook scripts (existing tech debt; separate cleanup PR).
- `/flow:status` and `/flow:learn` extensions to read from `.flow/`.
(`last-verdict.json` persistence and cross-judge enforcement — previously listed here as deferred — closed in cycle-3 of PR #109. See the cycle-3 follow-on below.)

## Cycle-2 follow-on to PR #109 (Independence Protocol enforcement)

After the M1-M6 commits, a self-review cycle on PR #109 surfaced an Independence Protocol violation in the evaluator-loop Stop hook. Cycle-2 ships a fix that is purely additive and changes nothing about the user-visible feature set:

- New module `bin/_flow_evidence_bundle.py` assembles the judge prompt from the goal contract + deterministic report + evidence sidecars. Replaces the old inline shell prompt-builder that embedded `tail -n 4 $TRANSCRIPT`. The transcript is no longer read by any hook code path.
- Every section in the bundle is wrapped in `<<<UNTRUSTED_*>>>` fences. The judge's system prompt instructs the model to treat fenced content as data, never instructions — defense against prompt injection inside hostile goal YAML fields.
- `agents/goal-evaluator-judge.md` updated to declare `tools: []` (was `tools: Read`). The spec now agrees with `--disallowedTools '*'` in the invocation; the judge cannot Read files, and the spec doesn't claim otherwise.
- 19 new test assertions in `flow-evidence-bundle.test.sh` cover the bundle structure, prompt-injection containment, raw-output truncation, path-traversal refusal, symlink defense, and a regression guard that asserts the transcript content NEVER leaks into the bundle.

No user action required. The change is internal to evaluator-loop mode (opt-in via `flow.goals.stopHookEnforcement: evaluator-loop`); warn-mode behavior is unchanged.

## Cycle-3 follow-on to PR #109 (close the last two gaps)

Cycle-2 left two items deferred: `last-verdict.json` had a reader but no writer (delta computation always fell back to "unchanged"), and the spec's "never pass on `llm_judge_report` alone" rule was judge-time discipline only — nothing stopped a regression. Cycle-3 closes both:

- New `bin/flow-record-verdict.sh` (CLI helper, validates required keys + enums + confidence range before writing) is invoked at every verdict-producing site: the evaluator-loop hook after `claude --print` returns, and the `/flow:goal evaluate` command after the skill produces a verdict. `last-verdict.json` is now produced wherever verdicts are produced.
- The assembler in `bin/_flow_evidence_bundle.py` now emits an `### Evidence coverage analysis` header at the top of `<<<UNTRUSTED_EVIDENCE_LEDGER>>>`. Per-AC classification (`deterministic`, `mixed`, `judge_only`, `none`) makes the cross-check rule impossible to miss — judge-only ACs are explicitly flagged `CROSS-CHECK REQUIRED`. The judge spec at `agents/goal-evaluator-judge.md` now references this header as authoritative.
- New `_journal_atomic.write_json_file` helper mirrors `write_yaml_file` (same O_NOFOLLOW + flock + tempfile+rename+fsync defenses) so the verdict producer reuses the established atomic-write pattern.
- 35 new test assertions (10 cases in `flow-record-verdict.test.sh` + 4 cases in `flow-evidence-bundle.test.sh` covering coverage analysis). All 330 tests pass.

`references/stop-hook-goal-enforcement.md` "What's NOT yet enforced" section is now empty — both gaps closed.

## Critical references

- `plugins/flow/references/flow-goals.md` — FlowGoal model
- `plugins/flow/references/flow-runtime-state.md` — `.flow/` directory layout
- `plugins/flow/references/flow-workflows.md` — FlowWorkflow model
- `plugins/flow/references/flow-triggers.md` — FlowTrigger model
- `plugins/flow/references/stop-hook-goal-enforcement.md` — Stop hook architecture
- `docs/plans/flow-v3-goals-workflows-triggers-plan.md` — Original v3 design (local-only, gitignored)
