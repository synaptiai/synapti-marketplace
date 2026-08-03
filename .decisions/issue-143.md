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
  logic — the fix is entirely a `WRAPPER`-token-list addition (one alternative, `find`, added
  to the existing token-alternation group).

### Failure modes

- **Timeouts** — none — this is a synchronous regex-based hook with no I/O or network calls
  that could hang; nothing to time out.
- **Partial failures** — none — the fix is a single-line regex alternation addition with no
  multi-step operation that could partially complete.
- **Invalid input** — a wrapper-mode false positive: `find . -name "npm test"` (no `-exec` at
  all, just a filename pattern that happens to contain a denied phrase) becomes over-blocked
  once `find` is a `WRAPPER` token, because `WRAPPER`-mode makes every whitespace run a
  boundary. This is the SAME accepted-tradeoff class already documented and shipped for every
  other `WRAPPER` token (e.g. `timeout 5 grep -r "npm test" docs/` is already over-blocked
  today) — not a new failure mode being introduced, but pinned down with an explicit regression
  test for the first time (previously this tradeoff class was only ever documented in a
  comment, never asserted in `hooks.test.sh`).
- **Missing context** — none — no new config/env dependency is introduced; the fix reuses the
  existing `WRAPPER` variable, which is already resolved unconditionally at hook-invocation
  time with no external state.

### Interface contracts

- `WRAPPER` regex in `plugins/dossier/hooks/scripts/enforce-allowed-actions.sh`: add the
  literal alternative `find` to the existing token-alternation group (alongside
  `bash|sh|zsh|...|python|python3`), preserving the exact same anchoring/lookaround structure.
  No new variables, no new functions, no change to `BOUND`, `BOUND_ACTIVE` derivation, or the
  `SCAN` sed rewrite.
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
