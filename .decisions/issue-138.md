---
issue: 138
created: '2026-08-02T20:53:11Z'
artifacts:
- type: specification
  captured_at: '2026-08-02T20:53:11Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: goal-created
  captured_at: '2026-08-02T20:53:11Z'
  goal_id: issue-138
  source: github_issue:138
- type: workflow-run
  captured_at: '2026-08-02T20:53:12Z'
  workflow: start-issue
  run_id: 2026-07-29T115831Z-issue-138
  status: active
- type: stranger-test
  captured_at: '2026-08-02T20:53:12Z'
  result: PASS
  task_count: 3
- type: verdict
  captured_at: '2026-08-02T20:53:12Z'
  result: PASS
- type: goal-evaluation
  captured_at: '2026-08-02T21:11:30Z'
  goal_id: issue-138
  result: achieved
  evidence_bundle: .flow/runs/2026-07-29T115831Z-issue-138
  failures: none
- type: workflow-run
  captured_at: '2026-08-02T22:48:02Z'
  workflow: start-issue
  run_id: 2026-07-29T115831Z-issue-138
  status: completed
- type: review-cycle
  captured_at: '2026-08-02T23:11:01Z'
  cycle: 1
  path: B
  findings_count: 8
  pr: 145
- type: review-cycle
  captured_at: '2026-08-03T00:03:42Z'
  cycle: 1
  path: A
  findings_count: 32
  pr: 145
---
# Issue #138 — Rolling-branch rotation, telemetry only

**Title**: dossier: make rolling-branch rotation observable (telemetry only) before any automated branch action is considered
**Labels**: enhancement, plugin

## Specification

_Captured by specification-capture skill on 2026-07-29. Source: mixed (non-goals extracted-from-issue; failure modes and interface contracts drafted and user-confirmed)._

### Non-goals

- Never close a pull request, delete a branch, or create a replacement branch, under any circumstance, as a result of this capability (issue body, AC2, verbatim).
- Never implement the actual rotation mechanism (closing/deleting/recreating the accumulating branch) — that requires its own dedicated proposal, backed by real observation data from this issue's work (issue body, "Context").
- Never modify, weaken, or bypass the existing destructive-action guard in the `publish` job's "Prepare the documentation branch" step (the `FOREIGN`-commit walk / `EXISTING_PR` check that gates `git push origin --delete`, `dossier-docs-refresh.yml:738-822`) — this issue's script and workflow step are read-only additions to the `policy` job and must never touch the `publish` job's write-permission code path.
- Never grant the new step more than the `policy` job's existing `contents: read` / `pull-requests: read` permission scope.

### Failure modes

- **Timeouts** — none — the new script performs only local `git` operations plus a single optional `gh pr list`/`gh pr view` call under the same network conditions as the existing `policy` job's `EXISTING_PR` lookup (`dossier-policy.sh:390`); no new timeout surface is introduced beyond what that job already tolerates.
- **Partial failures** — when the `gh` CLI is absent or its API call fails, the script degrades to a git-only age determination (oldest `Dossier-Generated: true` commit on the docs branch) rather than failing outright, and logs an explicit `note()` (following `dossier-policy.sh:451/461`'s convention) rather than the silent-empty pattern the issue implicitly reacts to (`dossier-policy.sh:390`, `dossier-docs-refresh.yml:720`). If BOTH the PR lookup and the commit-based fallback are unable to produce an age, `would_rotate` is reported as the literal string `unknown`, never coerced to `false`.
- **Invalid input** — a non-numeric or missing `dossier.ci.thresholds.rotationMaxAccumulatedLines` config value falls back to the documented default (5000) rather than crashing the script or corrupting the `--github-output` line format, matching the malformed-env-var handling precedent established in `dossier-scan-security.sh`/`dossier-scan-quality.sh` (issue #137, PR #144).
- **Missing context** — when the rolling documentation branch does not exist on the remote at all (`git ls-remote --exit-code --heads origin "$DOCS_BRANCH"` fails), the script reports a distinct `no-branch` cold-start state — `would_rotate=false` with an honest, specific reason ("the rolling branch does not exist yet; nothing to rotate") — never silently reporting "0 lines changed / would not rotate" as if a branch had been measured and found small.

### Interface contracts

- New script `plugins/dossier/bin/dossier-rotation-check.sh`. CLI contract mirrors `dossier-staleness-check.sh`/`dossier-policy.sh`: `[--github-output <file>] [--summary <file>]`. Untrusted values (`BASE_REF`, `GH_TOKEN`) bound via environment only, never argv. Exit 0 = a decision was reached (`would_rotate` may be `true`/`false`/`unknown`); exit 1 = infrastructure failure (missing `git`/`jq`, not inside a git repository); exit 2 = bad arguments.
- Emitted key=value fields (stdout + `--github-output` file, using `emit()`'s existing sanitization contract): `would_rotate` (`true`|`false`|`unknown`), `reason` (human-readable string), `age_days` (integer or empty), `age_source` (`pr_created_at`|`branch_commits`|`no-branch`|`unknown`), `accumulated_files` (integer or empty), `accumulated_lines` (integer or empty), `docs_branch`, `rotation_policy` (`none`|`weekly`|`monthly`).
- New schema field `dossier.ci.thresholds.rotationMaxAccumulatedLines` (integer, minimum 1, default 5000) added to `schema.json`, `settings.json`, and `templates/config.example.json` alongside the existing `thresholds` block — resolvable via the standard `DOSSIER_CI_THRESHOLDS_ROTATION_MAX_ACCUMULATED_LINES` environment override.
- New workflow step "Check whether the documentation branch would rotate" inside the `policy` job of `dossier-docs-refresh.yml`, placed after the existing `Decide` step, running unconditionally (no `if:` gate on `steps.decide.outputs.should_run`), writing its determination to `$GITHUB_STEP_SUMMARY` via the same append pattern the `Decide` and evidence-bundle steps already use. Executes entirely within the `policy` job's existing `contents: read` / `pull-requests: read` permission scope — no new permission is granted.

## Acceptance Criteria (as validated)

1. Every pipeline run records a clear, human-readable determination of whether branch rotation would currently be warranted, and the specific reason.
2. No pipeline run, under any circumstance, closes a pull request, deletes a branch, or creates a replacement branch as a result of this capability — it is purely observational.
3. The determination logic is exercised by tests covering both "would rotate" and "would not rotate" scenarios.
4. **Reworded (user-confirmed 2026-07-29)** — original: "After a period of real observation on this repository's own pipeline runs, there is enough recorded data to make an informed decision about whether an actual (non-destructive-by-design) rotation mechanism is worth proposing as separate, future work." Not verifiable by any command today — it describes a future outcome, not a testable property of this PR. Reworded to: `age_days`, `accumulated_files`, and `accumulated_lines` are always computed and emitted in a stable, parseable format across every state (no-branch, PR-anchored, commit-anchored, degraded-lookup) — including when `rollingBranchRotation=none` — so that a real multi-week observation period actually produces usable data. This is what makes the literal AC4 achievable in the future rather than deferred indefinitely with no mechanism to ever satisfy it.
5. The full dossier test suite passes.

## Stranger Test

PASS — 3 tasks reviewed (implementation-planner agent). Task 59 (script + workflow wiring + AC1/AC3/AC4 tests), Task 60 (schema/config triad + AC2 negative/safety assertions, depends on 59), Task 61 (full-suite verification, depends on 59+60). Each task description embeds the concrete algorithm, exact command sequences, file paths, and test-fixture patterns needed to execute with no other context. Three design gaps the planner found and resolved before finalizing (each verified empirically, not assumed): (1) `dossier.ci.thresholds.rotationMaxAccumulatedLines` must resolve through `dossier-resolve-config.sh`, not `cascade-resolve.sh` — the latter explicitly skips the `DOSSIER_*` env-override layer the tests depend on; (2) `git ls-remote` exit code 2 (ref absent) must be distinguished from any other non-zero exit (transport/auth failure) — only exit 2 is a genuine `no-branch` cold start, everything else is `age_source=unknown`; (3) `actions/checkout@v4` with `fetch-depth: 0` does not create remote-tracking refs for branches other than the one checked out (confirmed by the `publish` job's own explicit `git fetch` calls for `BASE_REF`/`DOCS_BRANCH`) — the new script must fetch both itself.

<!-- auto-log: 2026-08-02 22:53 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-138.md -->

<!-- auto-log: 2026-08-02 23:06 commit "fix(dossier): address review findings for rotation-check telemetry (#138)" -->

<!-- auto-log: 2026-08-02 23:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-02 23:07 commit "test(dossier): assert age_days is also emitted under rollingBranchRotation=none" -->

<!-- auto-log: 2026-08-02 23:11 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/verdict-issue-138.json -->

<!-- auto-log: 2026-08-03 00:44 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/lifecycle-issue-138-achieved.yaml -->

<!-- auto-log: 2026-08-03 00:47 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/complete_run.py -->

<!-- auto-log: 2026-08-03 00:49 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-convention-checker/feedback_dont_run_dossier_test_suite.md -->

<!-- auto-log: 2026-08-03 00:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 00:52 commit "test(dossier): assert on die_infra's message, silencing SC2034" -->

<!-- auto-log: 2026-08-03 00:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 00:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 00:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 00:56 commit "fix(dossier): add continue-on-error to rotation-check, fix --help range" -->

<!-- auto-log: 2026-08-03 00:56 commit "fix(dossier): add continue-on-error to rotation-check, fix --help range" -->

<!-- auto-log: 2026-08-03 00:57 commit "fix(dossier): add continue-on-error to rotation-check, fix --help range" -->

<!-- auto-log: 2026-08-03 00:58 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/feedback_dont_execute_dossier_tests_directly.md -->

<!-- auto-log: 2026-08-03 00:58 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_concurrent_flow_sessions.md -->

<!-- auto-log: 2026-08-03 00:58 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-08-03 00:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:00 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:00 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:06 commit "fix(dossier): guard empty config overrides, sanitize job-summary output" -->

<!-- auto-log: 2026-08-03 01:10 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr-body-138.md -->

<!-- auto-log: 2026-08-03 01:14 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:15 commit "fix(dossier): sanitize die_infra's summary output for defense-in-depth" -->

<!-- auto-log: 2026-08-03 01:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:38 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:39 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:39 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:41 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:42 commit "fix(dossier): address remaining P2 findings from PR #145 Path A review" -->

<!-- auto-log: 2026-08-03 01:45 commit "fix(dossier): address remaining P2 findings from PR #145 Path A review" -->

<!-- auto-log: 2026-08-03 01:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:50 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:51 commit "fix(dossier): address remaining P2 findings from PR #145 Path A review" -->

<!-- auto-log: 2026-08-03 01:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:53 commit "fix(dossier): route config-resolver infra failures through die_infra" -->

<!-- auto-log: 2026-08-03 01:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 01:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:57 commit "fix(dossier): route config-resolver infra failures through die_infra" -->

<!-- auto-log: 2026-08-03 01:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:58 commit "fix(dossier): route config-resolver infra failures through die_infra" -->

<!-- auto-log: 2026-08-03 01:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 01:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 02:00 commit "fix(dossier): neutralize markdown-active note() text; close 3 test gaps" -->

<!-- auto-log: 2026-08-03 02:01 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/review-145-cycle1.md -->

<!-- auto-log: 2026-08-03 02:02 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/resolution-145-cycle1.md -->

<!-- auto-log: 2026-08-03 02:03 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr145-current-body.md -->

<!-- auto-log: 2026-08-03 02:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 02:08 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/test-no-gh-path.sh -->
