---
issue: 148
created: '2026-08-03T11:53:19Z'
---
# Issue #148 — rotation-check telemetry fields aren't surfaced as job outputs

**Title**: dossier: rotation-check telemetry fields aren't surfaced as job outputs, undercutting the observation-period rationale
**Labels**: enhancement, plugin

## Bundle note

Part of the hook/policy-hardening bundle driven by `/flow:start` on #143 (see
`.decisions/issue-143.md`). Hand-authored journal, same reasoning as `.decisions/issue-146.md`.

## Specification

### Non-goals

- Not wiring any downstream consumer of these outputs (a scheduled aggregation step,
  a future rotation-design phase) — deliberately, per the issue's own text: "makes the
  data available to any future consumer... without committing to what that consumer
  looks like yet."
- Not changing `dossier-rotation-check.sh` itself — it already supports `--github-output`
  (confirmed by reading the script), so this is a workflow-YAML-only change.
- Not resolving the naming collision by nesting fields under a single JSON blob output —
  every existing output in this job (`should_run`/`reason`/`base_sha`/...) is a flat key,
  and a JSON-blob output would diverge from that convention for no benefit this issue asks
  for.

### Failure modes

- **Timeouts** — none — no new command execution, only new `outputs:` map wiring around
  an already-running step.
- **Partial failures** — the rotation step carries `continue-on-error: true` (pre-existing,
  unchanged). On a soft failure, its `--github-output` writes may be partial or absent, so
  the new `rotation_*` outputs may resolve empty — this matches the script's own existing
  `would_rotate=unknown` degradation pattern and is not a new failure mode; downstream jobs
  don't consume these outputs yet (see Non-goals), so an empty value has no consumer to
  mislead today.
- **Invalid input** — none — no new input surface; outputs are sourced from a script that
  already validates/degrades its own inputs.
- **Missing context** — none — no new config/env dependency.

### Interface contracts

- **Naming collision, discovered during specification, not anticipated by the issue's own
  suggested fix**: the script emits keys `reason` and `docs_branch`, both of which already
  exist as outputs of the policy job's `decide` step (`steps.decide.outputs.reason`,
  `steps.decide.outputs.docs_branch`). Adding them unmodified to the same job's `outputs:`
  map would collide. Resolved (user-confirmed): prefix every rotation-sourced output with
  `rotation_`, and drop `docs_branch` entirely (redundant — both steps resolve it from the
  identical `dossier.ci.rollingBranch` config in the same job run, so it can never differ
  within one execution).
- `id: rotation` added to the "Check whether the documentation branch would rotate" step.
- `--github-output "$GITHUB_OUTPUT"` added to that step's script invocation.
- Policy job `outputs:` map gains: `rotation_would_rotate`, `rotation_reason`,
  `rotation_age_days`, `rotation_age_source`, `rotation_accumulated_files`,
  `rotation_accumulated_lines`, `rotation_policy` — each `${{ steps.rotation.outputs.<key> }}`
  where `<key>` is the script's own unprefixed field name.

## Acceptance Criteria (as validated)

1. The rotation-check step has `id: rotation` and passes `--github-output "$GITHUB_OUTPUT"`.
   Verification: `bash plugins/dossier/tests/run.sh workflow-template.test.sh`
2. The policy job's `outputs:` map exposes all seven rotation fields under a `rotation_`
   prefix, with no key collision against the job's existing `should_run`/`reason`/
   `base_sha`/`head_sha`/`base_source`/`docs_branch`/`existing_pr`/`max_turns`/`model_arg`/
   `stale_docs` outputs. Verification: same test file, new assertions per key.
3. The full dossier test suite passes with no regression. Verification: `bash
   plugins/dossier/tests/run.sh`

## Stranger Test

PASS — inherits task #79 from `.decisions/issue-143.md`'s Stranger Test, which named the
exact step name, exact field list, exact prefix convention, and exact verification file.

## Verification

- `bash plugins/dossier/tests/run.sh workflow-template.test.sh` — RED-confirmed first
  (9 new failures: `id: rotation`, `--github-output`, and the 7 `rotation_*` outputs
  all missing), GREEN after the fix — 109/109, no regression to the pre-existing
  100 assertions.
- One test-authoring bug found and fixed during RED->GREEN: the initial
  `assert_not_contains "reason: ..."` collision check matched as a substring of the
  legitimate `rotation_reason: ...` line; anchored with a leading 6-space indentation
  prefix to check the exact YAML key position instead of a bare substring.
- YAML still parses cleanly after placeholder substitution (existing
  workflow-template.test.sh check, unaffected).
