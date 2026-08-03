---
issue: 143
created: '2026-08-03T11:53:19Z'
artifacts:
- type: specification
  captured_at: '2026-08-03T11:54:46Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: goal-created
  captured_at: '2026-08-03T11:57:32Z'
  goal_id: issue-143
  source: github_issue:143
- type: workflow-run
  captured_at: '2026-08-03T11:57:55Z'
  workflow: start-issue
  run_id: 2026-08-03T115319Z-issue-143
  status: active
- type: stranger-test
  captured_at: '2026-08-03T11:58:58Z'
  result: PASS
  task_count: 5
- type: verdict
  captured_at: '2026-08-03T12:11:27Z'
  result: PASS
- type: goal-evaluation
  captured_at: '2026-08-03T12:19:05Z'
  goal_id: issue-143
  result: achieved
  evidence_bundle: .flow/runs/2026-08-03T115319Z-issue-143
  failures: none
- type: review-cycle
  captured_at: '2026-08-03T12:57:58Z'
  cycle: 1
  path: B
  findings_count: 8
  pr: 153
---
# Issue #143 — enforce-allowed-actions.sh: find -exec / xargs -I{} bypass the action-ceiling backstop

**Title**: dossier: enforce-allowed-actions.sh's action-ceiling backstop can be bypassed via find -exec / xargs -I{}
**Labels**: bug, plugin

## Bundle note

This PR bundles three issues under one hook/policy-hardening theme, per user-approved
sequencing: #143 (this issue, driving `/flow:start`'s branch/goal/journal machinery),
#146 (`dossier-policy.sh` fork-PR hijack, `.decisions/issue-146.md`), and #148
(rotation telemetry not wired to CI job outputs, `.decisions/issue-148.md`). The three
fixes touch disjoint files and ship as separate atomic commits within one PR, which
closes all three issues.

## Specification

_Captured by specification-capture skill on 2026-08-03. Source: user-confirmed (resolved via
a direct AskUserQuestion interview, cross-checked against empirical reproduction on the
live script, before this skill was invoked)._

### Non-goals

- Not building a full POSIX/bash shell-grammar parser. This hook is a local/interactive-only
  backstop with zero CI reach (the CI refresh job's `--allowedTools` allowlist doesn't include
  `find`/`xargs`/a bare shell at all), so a grammar parser is disproportionate to the blast
  radius.
- Not closing every command that can embed an arbitrary sub-command in its arguments (GNU
  `parallel`, `awk 'system(...)'`, `perl -e 'exec(...)'`, `watch -x`, etc.) — only `find`
  (`-exec`/`-execdir`/`-ok`/`-okdir`) and `xargs` (`-I`/`-i`), the two named in the issue's
  acceptance criteria. The residual class is left as a documented, deliberately out-of-scope
  code comment, not a new tracked issue — no concrete forcing function exists for it yet,
  unlike this issue, which came from an actual review finding on PR #145's traffic.
- No code change needed for `xargs` specifically: empirically verified (direct reproduction
  against the live script) that `xargs -I{} curl {}` and `xargs -I{} pyscn {}` — both named in
  the issue body as unblocked — are in fact ALREADY blocked today, because `xargs` already
  matches the existing `WRAPPER` token list as a standalone word, which already flips the whole
  command into whitespace-boundary mode. Only `find` is a live gap. The issue's own
  reproduction claim about `xargs` does not hold against the current committed code and is
  treated as already resolved.
- Not touching `BOUND` (the strict no-wrapper anchor) or the `SCAN`/`BOUND_ACTIVE` derivation
  logic itself — the fix only widens the *trigger condition* that decides whether that
  derivation runs (see Interface contracts below for the final shape, which diverged from the
  original single-token-addition approach captured here).

  > **Superseded during review** (kept for audit trail, not current): the original design below
  > added `find` directly to the `WRAPPER` token-alternation group. A code-review pass on this
  > PR found that over-blocked any command merely containing the word "find" (not just actual
  > `find -exec` invocations), and the shipped fix instead uses a separate `FIND_EXEC` regex —
  > see the Interface contracts and Failure modes sections' correction notes below.

### Failure modes

- **Timeouts** — none — this is a synchronous regex-based hook with no I/O or network calls
  that could hang; nothing to time out.
- **Partial failures** — none — the fix is a single-line regex alternation addition with no
  multi-step operation that could partially complete.
- **Invalid input** — **superseded during review, correction**: the paragraph originally here
  described `find . -name "npm test"` as an accepted over-block tradeoff, matching the original
  bare-`find`-in-`WRAPPER` design. A code-review pass on this PR demonstrated live that this
  tradeoff class is broader than "npm test" specifically — it swept in any command merely
  containing the word "find" (e.g. a commit message `git commit -m "docs: find and document the
  test workflow"`), not just actual `find -exec` invocations. The shipped fix (a dedicated
  `FIND_EXEC` regex requiring `find` to co-occur with `-exec`/`-execdir`/`-ok`/`-okdir`) resolves
  this rather than accepting it: `hooks.test.sh` now asserts `find . -name "npm test"` and the
  commit-message case both correctly return RC=0 (not blocked).
- **Missing context** — none — no new config/env dependency is introduced; the fix reuses the
  existing `WRAPPER` variable, which is already resolved unconditionally at hook-invocation
  time with no external state.

### Interface contracts

- **Superseded during review** (final shipped shape): a new `FIND_EXEC` regex variable,
  `'(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*find([[:space:]]|$).*[[:space:]]-(exec|execdir|ok|okdir)([[:space:]]|$)'`,
  requiring `find` to actually co-occur with one of its four sub-command-execution primaries.
  The trigger condition for boundary-widening becomes
  `grep -qE "$WRAPPER" || grep -qE "$FIND_EXEC"` — `find` itself is never added to `WRAPPER`.
  No change to `BOUND`, `BOUND_ACTIVE`'s own derivation logic, or the `SCAN` sed rewrite — only
  the condition that decides whether that derivation runs. (Superseded original design, kept
  for audit trail: adding the literal alternative `find` to `WRAPPER` directly. See the
  Non-goals and Failure modes correction notes above for why this was replaced.)
- No change to any deny-block's own detection regex (`runTests`/`runBuild`/`networkAccess`/
  `runSecurityScan`/`runCodeQualityScan`) — the fix is entirely upstream of them, in the shared
  `WRAPPER`/`BOUND_ACTIVE` mechanism they all consume. This is what makes the fix apply to
  "every existing deny-block... not just newly-added ones" (AC1) without touching five separate
  blocks.
- Test additions land in `plugins/dossier/tests/hooks.test.sh` only, following the file's
  existing loop-based `"sees through the wrapper: $BAD"` assertion pattern (see the existing
  wrapper-indirection loops around line 122 and line 190).
- The existing "Known limitation, not fixed here (issue synaptiai/synapti-marketplace#143)"
  comment block (lines 94-107) is revised, not deleted: it documents what got fixed (`find`)
  and what remains a deliberately out-of-scope residual class (`parallel`/`awk`/`perl`/etc.),
  per the Non-goals above.

<!-- auto-log: 2026-08-03 13:56 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-143.goal.yaml -->

<!-- auto-log: 2026-08-03 13:57 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-143.goal.yaml -->

<!-- auto-log: 2026-08-03 13:57 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-143.goal.yaml -->

<!-- auto-log: 2026-08-03 13:57 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-143-lifecycle-active.yaml -->

<!-- auto-log: 2026-08-03 13:57 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-08-03T115319Z-issue-143/run.yaml -->

## Acceptance Criteria (as validated)

1. `find ... -exec <denied-command> ...`, `find ... -execdir <denied-command> ...`, and
   `xargs -I{} <denied-command> {}` (and their common flag variants) are correctly denied
   when the corresponding capability is off, for every existing deny-block (`runTests`,
   `runBuild`, `networkAccess`, `runSecurityScan`, `runCodeQualityScan`), not just
   newly-added ones. Verification: `bash plugins/dossier/tests/run.sh hooks.test.sh`
2. The fix does not regress any existing passing case in `plugins/dossier/tests/hooks.test.sh`
   (the wrapper-indirection and grep-about-a-command cases especially). Verification: same
   command, full file green (98/98 as of the final `FIND_EXEC` shape, up from 85/85 pre-fix).
3. The approach is documented as classifying command structure rather than enumerating more
   literal indirection tokens, so a future new indirection shape doesn't require another
   narrowing/widening round. Verification: `grep -n "FIND_EXEC"
   plugins/dossier/hooks/scripts/enforce-allowed-actions.sh` + manual read of the revised
   comment block.
4. Covered by new test cases in `hooks.test.sh` for each denied-command class named above.
   Verification: same command as AC1/AC2.

## Stranger Test

PASS — 5 tasks reviewed. Each names exact file paths/lines, the exact regex/field
changes, the exact existing-code precedent being mirrored (PR #145's SEC-1 fix for
task 3; the existing WRAPPER token-list mechanism for tasks 1-2; the should_run/reason
outputs pattern for task 4), and an exact verification command. Task 2 (AC3, comment
documentation) carries one fuzzy/manual verification component (does the revised
comment read as structural framing) alongside its automated grep check — flagged
explicitly in the FlowGoal contract rather than silently treated as fully automatable.

<!-- auto-log: 2026-08-03 13:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-08-03 14:00 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 14:01 commit "fix(dossier): classify find/xargs as WRAPPER commands, closing the -exec/-I{} action-ceiling bypass" -->

<!-- auto-log: 2026-08-03 14:01 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 14:02 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 14:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 14:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 14:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:04 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 14:04 commit "fix(dossier): scope dossier-policy.sh's EXISTING_PR lookup to same-repo PRs" -->

<!-- auto-log: 2026-08-03 14:04 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 14:04 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 14:05 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 14:05 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 14:05 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 14:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 14:06 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 14:06 commit "feat(dossier): surface rotation-check telemetry as policy job outputs" -->

## Verification

- Full suite: `bash plugins/dossier/tests/run.sh` — 1882/1882 (up from 1852 pre-bundle).
- `shellcheck -S warning -x plugins/dossier/tests/*.sh plugins/dossier/bin/*.sh
  plugins/dossier/hooks/scripts/*.sh` — clean, exit 0, across every script in the plugin.
- `bash -n` on every modified/new file — clean.
- Each of the three bundled fixes (#143, #146, #148) TDD RED-confirmed against the
  unpatched code first, then GREEN after its own fix, with per-file regression checks
  (staleness-trigger.test.sh for #146; no cross-file breakage anywhere for #143/#148).
- One test-authoring bug caught and fixed during #148's RED->GREEN cycle: an
  assert_not_contains collision check matched as a substring of its own sibling
  assertion; fixed by anchoring on exact YAML key position.

### Review-driven fix-forward (PR #153's `/flow:review`, Path A paired-reviewer protocol)

A 10-agent paired-reviewer pass (5 facets x {skeptic, verifier}) plus 2 holdout-validation
lenses converged on several findings beyond the three original fixes, all fixed in the same
PR before merge:

- **ERR-2 / P1 (doubly-confirmed)**: `enforce-allowed-actions.sh`'s config-resolver call could
  return an empty `OUTPUT_ROOT`, which — read literally — meant "the empty string is the output
  root," silently defeating the inertness check. Fixed with an explicit non-empty fallback.
- **P1/P2/P3 (convergent)**: the hook's jq-parse-failure check ran after the inertness check,
  so a malformed payload on a non-dossier command could still surface a spurious BLOCKED.
  Reordered so inertness is decided before any JSON parsing.
- **P2 (code-verifier)**: the bare `find` token in `WRAPPER` over-blocked commands like
  `find . -name "npm test"` that never use `-exec`. Replaced with a dedicated `FIND_EXEC` regex
  requiring `find` to actually co-occur with `-exec`/`-execdir`/`-ok`/`-okdir`.
- **P2 (cross-facet convergent, raised independently by security-skeptic and code-skeptic)**:
  the `EXISTING_PR` lookup in `dossier-policy.sh` had no `--limit`, unlike the file's own
  circuit-breaker precedent. Added `--limit 100`.
- **P2/P3 (triple-convergent)**: `write_summary()`'s "Existing docs PR" row couldn't distinguish
  a genuinely-confirmed `none` from an `unknown (lookup failed)` state. Fixed with an explicit
  `elif` branch.
- **SEC-1 (security-skeptic)**: `dossier-docs-refresh.yml`'s branch-recreate guard checked
  `existing_pr_lookup_failed = "true"`, which fails OPEN on any other value (including absent).
  Inverted to `!= "false"`, which fails closed on unexpected/absent values too.
- **ERR-1 (error-handler skeptic+verifier auto-consensus)**: the same file's `git rev-list` call
  feeding the FOREIGN-commit-detection loop never checked its own exit status, so a rev-list
  failure was indistinguishable from "genuinely no foreign commits." Added explicit exit-status
  capture and a refusal path matching the file's existing FOREIGN/lookup-failed refusal pattern.
- Both YAML fixes got new line-order-aware static assertions in `workflow-template.test.sh`
  (a plain `assert_contains` cannot detect a correct-looking guard that is unreachable because
  it was moved after the code path it's meant to gate).
- One shellcheck warning (SC2034, an unused captured-but-discarded command substitution in a
  new test scenario) found and fixed during this pass.

Final: `bash plugins/dossier/tests/run.sh` — 1912/1912 (up from 1882 pre-review-pass, 1852
pre-bundle). `shellcheck -S warning -x` across every touched script — clean, exit 0.

<!-- auto-log: 2026-08-03 14:12 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-AC1.yaml -->

<!-- auto-log: 2026-08-03 14:12 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-AC2.yaml -->

<!-- auto-log: 2026-08-03 14:12 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-AC3.yaml -->

<!-- auto-log: 2026-08-03 14:12 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-AC4.yaml -->

<!-- auto-log: 2026-08-03 14:18 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/verdict-issue-143.json -->

<!-- auto-log: 2026-08-03 14:26 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-143-lifecycle-achieved.yaml -->

<!-- auto-log: 2026-08-03 14:28 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/cmd_backslash.txt -->

<!-- auto-log: 2026-08-03 14:41 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 14:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 14:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 14:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 14:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 14:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 14:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 14:46 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-08-03 14:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 14:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 14:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 14:49 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 14:49 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 14:50 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-143.md -->

<!-- auto-log: 2026-08-03 14:55 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 14:55 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 14:56 commit "fix(dossier): guard the docs-branch recreate path against a failed PR lookup" -->

<!-- auto-log: 2026-08-03 14:57 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr-150-body.md -->

<!-- auto-log: 2026-08-03 15:03 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-08-03T130332Z-review/run.yaml -->

<!-- auto-log: 2026-08-03 15:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 15:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 15:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 15:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-08-03 15:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-08-03 15:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-08-03 15:24 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-08-03 15:25 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 15:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 15:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-policy.sh -->

<!-- auto-log: 2026-08-03 15:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 15:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 15:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 15:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 15:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-08-03 15:37 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 15:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 15:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-146.md -->

<!-- auto-log: 2026-08-03 15:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 15:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 15:39 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-148.md -->

<!-- auto-log: 2026-08-03 15:40 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/policy-existing-pr.test.sh -->

<!-- auto-log: 2026-08-03 15:41 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-143.md -->

<!-- auto-log: 2026-08-03 15:45 commit "fix(dossier): fail closed on hook ordering/empty-resolver gaps, narrow find matching to its exec-family flags" -->

<!-- auto-log: 2026-08-03 15:45 commit "fix(dossier): paginate the EXISTING_PR lookup and distinguish a failed lookup from a confirmed none" -->

<!-- auto-log: 2026-08-03 15:45 commit "fix(dossier): fail closed on an ambiguous PR-lookup signal and verify rev-list's exit status before trusting its output" -->

<!-- auto-log: 2026-08-03 15:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-08-03 15:55 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-143.md -->

<!-- auto-log: 2026-08-03 15:55 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-143.md -->

<!-- auto-log: 2026-08-03 15:56 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-143.md -->

<!-- auto-log: 2026-08-03 15:56 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-143.md -->

<!-- auto-log: 2026-08-03 15:57 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr-153-self-review.md -->

<!-- auto-log: 2026-08-03 15:57 commit "fix(dossier): capture git rev-list's stderr separately from its stdout" -->
