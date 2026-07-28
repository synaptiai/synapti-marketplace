---
issue: 135
created: '2026-07-28T12:10:04Z'
artifacts:
- type: workflow-run
  captured_at: '2026-07-28T12:10:04Z'
  workflow: review-pr
  run_id: 2026-07-28T120749Z-review
  status: active
---
# Decision Journal — Issue #135

**Title**: dossier: staleness should actively trigger re-verification; post-merge refresh suggestion must not depend on another plugin
**Branch**: feature/issue-135-staleness-trigger-and-local-merge
**Started**: 2026-07-28

Part 1 of 4 in the dossier post-merge/investor-doc-gap initiative (plan: `the-dossier-plugin-is-federated-toucan`). Epics 2-4 (issues #136, #137, #138) are separate, sequential/independent work.

## Specification

### Non-goals
- Epics 2-4 (vulnerability evidence ingestion, isolated scanner execution, rotation telemetry) — separate issues, not touched here.
- `plugins/dossier/triggers/templates/docs-refresh.trigger.yaml` — a pre-existing, already-shipped `FlowTrigger` template that dossier's `/dossier:setup` copies into `.flow/triggers/` and that depends on flow's trigger-policy skill. This already couples dossier to flow, but it is a different feature (an opt-in local loop trigger) than this issue's scope (staleness-driven scheduled sweep + local-merge hook), and it is not mentioned in issue #135's acceptance criteria. Not modified by this work; flagged separately as a pre-existing item worth a future look, not fixed here.
- `hooks/scripts/stale-header-stamp.sh` — a different staleness-adjacent check (warns when an edited doc's `last-verified` didn't move) that is edit-triggered, not age-threshold-triggered. Not consolidated into the new shared script; it answers a different question.
- No change to the actual prose-generation machinery in `/dossier:refresh` Phase 4 (`dossier-doc-drafter` agent) — the stale-triggered path reuses existing re-verification/evidence-collection machinery and must NOT redraft a document whose claims still hold, per `references/change-triggers-and-blast-radius.md`'s existing "verification pass, not a redraft" rule.
- No widening of `engagement.allowedActions` — the `onLocalMerge: run` path invokes the existing `/dossier:refresh`, itself already bounded by `enforce-allowed-actions.sh`; this issue adds no new action class.
- Zero changes to any file under `plugins/flow/`.

### Failure modes
- `jq` missing at hook-invocation time → the merge-detection hook is advisory (suggest/run), so it fails OPEN (`exit 0`, silent no-op) — unlike `enforce-allowed-actions.sh`, which is a security ceiling and fails CLOSED. Blocking a shell command because a suggestion feature couldn't parse its JSON input would be a correctness regression with no compensating safety benefit.
- Merge-shape detection false positive (a non-merge command incorrectly matched) → bounded blast radius: at most a suggestion is printed, or `/dossier:refresh` runs (itself read-mostly and confined by the existing output-root/action-ceiling hooks). Never destructive.
- Merge-shape detection false negative (a real merge missed) → acceptable degradation for a `suggest`/`run` UX feature; the weekly staleness sweep and path-filtered CI trigger remain the durable coverage paths. Not a correctness bug to chase exhaustively.
- `dossier-resolve-config.sh` non-executable/missing → keep restrictive defaults (`onLocalMerge` behaves as `off`; staleness sweep does not force a run), matching the fail-safe pattern in `enforce-allowed-actions.sh` when its resolver is absent.
- Staleness sweep fires with a fresh/nonexistent package (`00-control` absent) → no-op, zero stale documents, no crash.
- Staleness sweep triggered on a non-`schedule` event → must never force `should_run=true` from staleness alone (explicit AC #1: "on a scheduled cadence").
- Many documents stale simultaneously → the sweep must cap how many it re-verifies in one run (explicit AC #3), never unbounded.
- `status.md`'s existing emitted scalar fields (`STALENESS_THRESHOLD_DAYS`, `DOCUMENTS_STALE`, `DOCUMENTS_UNDATED`, `OLDEST_VERIFICATION`) must stay byte-identical after the computation moves into the shared script — a silent format drift would break the `/dossier:status` dashboard's existing contract with nothing to catch it except this task's golden-fixture check.

### Interface contracts
- New script `plugins/dossier/bin/dossier-staleness-check.sh`: reads `dossier.refresh.stalenessDays` (default 90) and a new `dossier.refresh.maxStaleDocsPerSweep` (default 5) via `dossier-resolve-config.sh`; walks `<outputRoot>/**/*.md`; for each, parses `last-verified:` header exactly as `status.md`/`dossier-evidence.sh` do today (`awk -F': *' '/^last-verified:/{print $2; exit}'`). Emits the same scalar fields `status.md` emits today, plus a new bounded field naming which stale documents are eligible for this sweep's re-verification pass, capped at `maxStaleDocsPerSweep`.
- `dossier.local.onFlowMerge` (enum `suggest`/`run`/`off`, default `suggest`) is renamed to `dossier.local.onLocalMerge`, same enum/default/semantics, across `schema.json`, `settings.json`, `templates/config.example.json`, and this repo's own `.claude/settings.dossier.json`.
- New hook script `plugins/dossier/hooks/scripts/detect-local-merge.sh`, registered as a `PostToolUse` entry matching `Bash` in `plugins/dossier/hooks/hooks.json`, following the existing `stale-header-stamp.sh`/`enforce-allowed-actions.sh` pattern: `INPUT=$(cat)`, `.tool_input.command` via `jq`, config via `dossier-resolve-config.sh`. Detects `git merge`, a `git pull` that produces a merge commit, and `gh pr merge`, landing on the repository's default branch.
- `dossier-policy.sh` gains a new rule, evaluated only when `EVT=schedule`: if the existing "no relevant paths"/"below threshold" exits would otherwise fire, first consult `dossier-staleness-check.sh`; if it reports ≥1 stale document, override to `should_run=true reason=stale-sweep` and surface the bounded document list as a new output field.
- `dossier-evidence.sh` and `status.md` are refactored to call the shared script instead of each re-implementing the age/threshold loop.

## Spec Validation Gate

| # | Acceptance Criterion | Verification Command | Gate Status |
|---|---|---|---|
| 1 | A document past its staleness threshold, with no other trigger, gets a real re-verification pass on a scheduled cadence — reproducible test, not just docs | `bash plugins/dossier/tests/run.sh staleness-trigger.test.sh` (new fixture: schedule event + planted stale doc + no path-filter-relevant diff → `should_run=true reason=stale-sweep`) | PASS |
| 2 | A staleness-triggered re-verification never rewrites a document whose claims still hold — only `last-verified` advances | The redraft-vs-verify decision itself happens inside an LLM agent dispatch (`commands/refresh.md` Phase 4), which a bash suite cannot execute or assert body-identity against. What is mechanically verified instead: `refresh-staleness.test.sh` asserts `refresh.md`'s prose documents the correct `class:"stale"` branch, the no-drift/drift-found split, and routes verification through the evidence-collector agent rather than the drafter — a structural, not behavioral, check | PASS |
| 3 | A single scheduled sweep never re-verifies an unbounded number of documents even if many are stale simultaneously | Fixture: plant N > `maxStaleDocsPerSweep` stale docs; assert the emitted eligible-for-sweep list length equals the cap, not N | PASS |
| 4 | The post-merge refresh suggestion behaves correctly with the flow plugin entirely absent — proven by a test | New `plugins/dossier/tests/local-merge-hook.test.sh`: invoke `detect-local-merge.sh` directly with a `git merge` command payload in an environment/fixture where no `plugins/flow` directory exists; assert correct `suggest`/`run`/`off` behavior per config | PASS |
| 5 | The full dossier test suite passes | `bash plugins/dossier/tests/run.sh` | PASS |
| 6 | `/dossier:status` (or its bash block) against this repo's own `docs/dossier` package reflects the new behavior accurately | Run `commands/status.md`'s bash block (or the equivalent direct script invocation) against `docs/dossier` after the change lands; manually inspect the Freshness/Automation rows for accuracy | PASS |

All 6 ACs PASS — proceeding to PLAN.

## Stranger Test

A zero-context agent given this journal's Interface Contracts (exact script names, config key names/defaults, hook registration shape, and the existing file:line patterns to mirror) plus the Spec Validation Gate's verification commands could implement and verify every acceptance criterion without further clarification. **PASS.**

<!-- auto-log: 2026-07-28 11:27 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-135.md -->

<!-- auto-log: 2026-07-28 11:29 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 11:30 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 11:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 11:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 11:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 11:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/commands/status.md -->

<!-- auto-log: 2026-07-28 11:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 11:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 11:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 11:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 11:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 11:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 11:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 11:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/settings.json -->

<!-- auto-log: 2026-07-28 11:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/config.example.json -->

<!-- auto-log: 2026-07-28 11:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/schema.json -->

<!-- auto-log: 2026-07-28 11:39 commit "feat(dossier): consolidate staleness computation into dossier-staleness-check.sh" -->

<!-- auto-log: 2026-07-28 11:40 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 11:41 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-07-28 11:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-07-28 11:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-07-28 11:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-07-28 11:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-07-28 11:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 11:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 11:48 commit "feat(dossier): staleness actively triggers a schedule-only sweep in dossier-policy.sh" -->

<!-- auto-log: 2026-07-28 11:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-blast-radius.sh -->

<!-- auto-log: 2026-07-28 11:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-blast-radius.sh -->

<!-- auto-log: 2026-07-28 11:50 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-blast-radius.sh -->

<!-- auto-log: 2026-07-28 11:50 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/blast-radius-staleness.test.sh -->

<!-- auto-log: 2026-07-28 11:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-blast-radius.sh -->

<!-- auto-log: 2026-07-28 11:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 11:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 11:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-07-28 11:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 11:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 11:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 11:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 11:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 11:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 11:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/commands/refresh.md -->

<!-- auto-log: 2026-07-28 11:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/commands/refresh.md -->

<!-- auto-log: 2026-07-28 11:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/commands/refresh.md -->

<!-- auto-log: 2026-07-28 11:56 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/refresh-staleness.test.sh -->

<!-- auto-log: 2026-07-28 11:57 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-config.test.sh -->

<!-- auto-log: 2026-07-28 11:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/schema.json -->

<!-- auto-log: 2026-07-28 11:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/settings.json -->

<!-- auto-log: 2026-07-28 11:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/config.example.json -->

<!-- auto-log: 2026-07-28 11:58 Edit /Users/danielbentes/synapti-marketplace/.claude/settings.dossier.json -->

<!-- auto-log: 2026-07-28 11:59 commit "feat(dossier): route stale-only documents through verification, not redraft" -->

<!-- auto-log: 2026-07-28 11:59 commit "feat(dossier): rename dossier.local.onFlowMerge to onLocalMerge" -->

<!-- auto-log: 2026-07-28 12:01 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 12:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 12:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 12:02 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/detect-local-merge.sh -->

<!-- auto-log: 2026-07-28 12:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/detect-local-merge.sh -->

<!-- auto-log: 2026-07-28 12:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 12:04 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/hooks.json -->

<!-- auto-log: 2026-07-28 12:04 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-07-28 12:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 13:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 13:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 13:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 13:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-07-28 13:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/commands/status.md -->

<!-- auto-log: 2026-07-28 13:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 13:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 13:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 13:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 13:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 13:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 13:25 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-msg-review-fixes.txt -->

<!-- auto-log: 2026-07-28 13:25 commit "fix(dossier): address review findings on staleness-check and policy" -->

<!-- auto-log: 2026-07-28 13:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 13:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 13:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 13:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 13:31 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 13:31 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 13:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-07-28 13:35 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-msg-narrow-sec3.txt -->

<!-- auto-log: 2026-07-28 13:35 commit "fix(dossier): narrow SEC-3 canonical-doc gate to the sweep list only" -->

<!-- auto-log: 2026-07-28 14:09 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T120749Z-review/run.yaml -->

<!-- auto-log: 2026-07-28 14:09 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T120749Z-review/run.yaml -->

<!-- auto-log: 2026-07-28 14:09 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T120749Z-review/run.yaml -->

<!-- auto-log: 2026-07-28 14:09 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T120749Z-review/run.yaml -->

<!-- auto-log: 2026-07-28 14:11 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T120749Z-review/run.yaml -->

<!-- auto-log: 2026-07-28 14:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 14:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 14:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 14:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-staleness-check.sh -->

<!-- auto-log: 2026-07-28 14:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/detect-local-merge.sh -->

<!-- auto-log: 2026-07-28 14:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/detect-local-merge.sh -->

<!-- auto-log: 2026-07-28 14:21 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 14:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/detect-local-merge.sh -->

<!-- auto-log: 2026-07-28 14:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 14:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/local-merge-hook.test.sh -->

<!-- auto-log: 2026-07-28 14:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 14:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/refresh-staleness.test.sh -->

<!-- auto-log: 2026-07-28 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/refresh-staleness.test.sh -->

<!-- auto-log: 2026-07-28 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/refresh-staleness.test.sh -->

<!-- auto-log: 2026-07-28 14:25 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-blast-radius.sh -->

<!-- auto-log: 2026-07-28 14:25 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-evidence.sh -->

<!-- auto-log: 2026-07-28 14:25 Edit /Users/danielbentes/synapti-marketplace/docs/dossier/02-architecture/components-and-codebase.md -->

<!-- auto-log: 2026-07-28 14:25 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-135.md -->

<!-- auto-log: 2026-07-28 14:28 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-msg-review-fixforward.txt -->

<!-- auto-log: 2026-07-28 14:28 commit "fix(dossier): fix-forward P1/P2 findings from PR #139 review" -->

<!-- auto-log: 2026-07-28 14:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-check.test.sh -->

<!-- auto-log: 2026-07-28 14:34 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-msg-holdout-coverage.txt -->
