---
issue: 146
created: '2026-08-03T12:01:00Z'
---
# Issue #146 — dossier-policy.sh: gh pr list --head is unscoped by repo

**Title**: dossier-policy.sh: gh pr list --head is unscoped by repo, allowing a fork PR to hijack the docs-refresh publish flow
**Labels**: bug, plugin

## Bundle note

Part of the hook/policy-hardening bundle driven by `/flow:start` on #143 (see
`.decisions/issue-143.md`). This journal is hand-authored, matching the same
Specification/AC/Verification schema `/flow:start`'s own skills would have produced,
since `/flow:start` was not run separately against this issue number — the
bundle's mechanics were resolved via a direct user interview before implementation
began (see the `## Bundle note` in `.decisions/issue-143.md`).

## Specification

### Non-goals

- Not touching `dossier-rotation-check.sh`'s own `gh pr list --head` call — it already
  carries this exact fix (`isCrossRepository == false` filtering), shipped in PR #145's
  SEC-1. This issue is the pre-existing original that fix was copied from.
- Not touching either of the two OTHER `gh pr list` call sites in this codebase
  (`dossier-policy.sh:448` circuit-breaker count, `dossier-docs-refresh.yml:736`
  publish-job circuit-breaker audit) — both use `--state all --label`, never `--head`,
  so they are not affected by this vulnerability class: a fork PR would need the
  privileged `dossier:generated` label already applied by a write-token job to be
  counted, which an external contributor cannot do on their own fork PR.
- Not adding a generic "always filter cross-repo PRs" helper function — this is a
  single, narrow, already-proven fix pattern (identical to PR #145's), not a new
  abstraction.

### Failure modes

- **Timeouts** — none — no new network call; same `gh pr list` invocation, filtered
  more precisely.
- **Partial failures** — none — `gh` unavailability is already handled by the
  surrounding `command -v gh` guard (degradation: publish rediscovers the PR anyway).
- **Invalid input** — a fork PR opening a branch with the exact same name as
  `$DOCS_BRANCH` (e.g. `docs/dossier`) must never be selected in place of, or ahead
  of, the real same-repo PR — this is the exact exploit shape the issue describes.
- **Missing context** — none — no new config/env dependency.

### Interface contracts

- `dossier-policy.sh:390`: `EXISTING_PR=$(gh pr list --head "$DOCS_BRANCH" --state open
  --json number,isCrossRepository --jq '[.[] | select(.isCrossRepository == false)][0].number
  // empty' 2>/dev/null)` — adds `isCrossRepository` to the requested JSON fields and
  filters it out before taking `.[0]`, mirroring PR #145's SEC-1 fix verbatim.
- New test file `plugins/dossier/tests/policy-existing-pr.test.sh`, using a fake `gh`
  stub on `PATH` that applies the real `--jq` filter via actual `jq` (not a fixed
  echo), porting `rotation-check.test.sh`'s scenario-17 technique.

## Acceptance Criteria (as validated)

1. `EXISTING_PR` resolution in `dossier-policy.sh` filters out cross-repository PRs
   before selecting the first match. Verification: `bash plugins/dossier/tests/run.sh
   policy-existing-pr.test.sh`
2. A cross-repository decoy PR (same branch name, more recently created) never masks
   or is preferred over the real same-repo PR. Verification: same test, scenario
   asserting the same-repo PR's number is returned, not the decoy's.
3. The full dossier test suite passes with no regression. Verification: `bash
   plugins/dossier/tests/run.sh`

## Stranger Test

PASS — inherits task #78 from `.decisions/issue-143.md`'s Stranger Test, which named
the exact file:line, the exact existing-code precedent (PR #145 SEC-1) being mirrored,
and the exact test technique to port.

## Verification

- New regression test: `bash plugins/dossier/tests/run.sh policy-existing-pr.test.sh` —
  6/6, RED-confirmed against the unpatched script first (fork decoy #99 won over the
  real PR #7), GREEN after the fix.
- No regression: `bash plugins/dossier/tests/run.sh staleness-trigger.test.sh
  policy-existing-pr.test.sh` — 20/20.
- `shellcheck -S warning -x plugins/dossier/bin/dossier-policy.sh
  plugins/dossier/tests/policy-existing-pr.test.sh` — clean, exit 0.
- `bash -n` on both modified/new files — clean.

### Review-driven follow-up (P1, fixed in the same PR)

The error-handler-inspector review pass on the bundle PR found that this fix's own
`gh pr list` call swallows the lookup's exit code — pre-existing shape, not introduced
here, but now demonstrably reachable: a transient `gh` failure leaves `existing_pr`
empty, indistinguishable from a genuine no-PR result, and the publish job's branch-
preparation step treats that emptiness as license to delete and recreate the
documentation branch whenever it already exists with no foreign commits — exactly the
steady state whenever a real docs PR IS open. Fixed by adding a new
`existing_pr_lookup_failed` output (set on both a `gh pr list` failure and `gh`
unavailability) and a matching guard in the publish job that refuses the destructive
recreate path when the signal is set, rather than delete-and-rebuild — same posture as
the file's own FOREIGN-commits refusal a few lines above it. New test scenarios 4/5 in
`policy-existing-pr.test.sh`; new static assertions in `workflow-template.test.sh`.
Final: `bash plugins/dossier/tests/run.sh policy-existing-pr.test.sh` — 13/13.
