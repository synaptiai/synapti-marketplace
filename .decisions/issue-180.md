---
issue: 180
created: '2026-09-14T22:59:43Z'
artifacts:
- type: specification
  captured_at: '2026-09-14T22:59:43Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-14T23:01:16Z'
  goal_id: issue-180
  ac_count: 5
- type: workflow-run
  captured_at: '2026-09-14T23:01:29Z'
  workflow: start-issue
  run_id: 2026-09-15T000000Z-issue-180
  status: active
- type: goal-amendment
  captured_at: '2026-09-14T23:14:07Z'
  reason: verification_command_and_allowed_paths_fix
  by: implementation-planner-review
- type: stranger-test
  captured_at: '2026-09-14T23:14:19Z'
  result: PASS
  task_count: 5
---
# Issue #180 — G18 and the verbatim-collection rule are in direct conflict

## Specification

### Non-goals

- Does NOT implement Option 1's heading/round-based scoping instead of explicit markers — markers are strictly more precise and do not depend on the exact wording of a round heading, so choosing between "Option 1 or 2" (the issue's own framing) resolves to Option 2's mechanism scoped the way Option 1 asked: the intersection, not a third design.
- Does NOT implement Option 3 (link out to `.dossier/runs/<id>/` instead of inlining) — deliberately rejected per the issue's own reasoning: it would lose the property that the committed package carries its own evidence.
- Does NOT add abuse-detection tooling for a document author who manually inserts fake verbatim markers to dodge G18 — mitigated structurally instead, by scoping marker-honoring to `07-verification/documentation-verification-report.md` only; markers anywhere else are inert HTML comments and the text between them is scanned like any other prose.
- Does NOT change `dossier-claim-scan.sh` or any other dossier linter to honor the same markers — this fix is `dossier-prose-lint.sh`-specific, and that boundary is documented explicitly (AC5) rather than assumed.
- Does NOT touch the `--help` hardcoded-range truncation bug (`sed -n '2,Np'`) present in 17 other `plugins/dossier/bin/*.sh` scripts that share the same pattern (confirmed via `grep -n "sed -n '2," plugins/dossier/bin/*.sh`). Only `dossier-prose-lint.sh`'s own `--help` is fixed in this PR, because this issue's changes grow that specific file's header comment and would make its existing truncation worse. The other 17 are pre-existing and unrelated to this issue's scope; filed as a separate follow-up issue rather than swept here.

### Failure modes

- Timeout / partial failure: none — pure text-processing change, no network or long-running I/O introduced.
- Invalid input: a verbatim marker pair present in a file other than the verification report — handled by the file-scoping check (AC1); markers are inert there, body scanned normally, never an error.
- Missing context: none — self-contained within `dossier-prose-lint.sh` and `commands/audit.md`.
- Malformed markers (unclosed `BEGIN`, nested `BEGIN`): explicitly in scope, not a generic "error case" — covered directly by AC3 (`scan_error`, never a silent 0).

### Interface contracts

- New CLI-observable JSON fields added by `dossier-prose-lint.sh --json`: top-level `verbatim_blocks` (int) and `verbatim_lines_skipped` (int); mirrored per-file inside each `files[]` entry when nonzero for that file. Additive only — no existing field removed or renamed, so `dossier-gate.sh`'s G18 check (which reads only `blocking_violations` via an anchored `sed` extraction) is unaffected.
- Marker literal text: `<!-- DOSSIER_VERBATIM_BEGIN -->` and `<!-- DOSSIER_VERBATIM_END -->`, matched as a line-start prefix (`^<!-- DOSSIER_VERBATIM_BEGIN`, `^<!-- DOSSIER_VERBATIM_END`) — consistent with the existing single-line `<!-- DOSSIER_AUDIT ... -->` marker convention already used in `commands/audit.md` Phase 3.
- File-scoping match: a path-suffix test equivalent to `case "$f" in */07-verification/documentation-verification-report.md)` — works whether the linter is invoked via `--output-root` (full relative path under the package root) or `--file` (any path ending in that suffix, including test fixtures).
- Malformed-marker disposition (fixed contract, not left to implementation discretion): unclosed `BEGIN` → scan_error; `BEGIN` nested inside an already-open block → scan_error; stray `END` with no open `BEGIN` → ignored, no state change, no error.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| File-scoping | Marker honored in every file, not just the verification report (Option 2's original generic form, which reopens the gaming surface) | Fixture: identical hard-category-violating sentence placed inside markers in a non-`07-verification` file → still flagged, `blocking_violations > 0` |
| Malformed-marker exit | Unclosed or nested `BEGIN` silently exempts the rest of the file (reads as 0 violations) instead of erroring | Fixture: `BEGIN` with no matching `END`, followed by clearly-violating prose → `scan_error` recorded; the file's contribution to `blocking_violations` reflects the error path, never a clean 0 |
| Paragraph-count boundary | The `para_sentences` counter is not reset when entering/leaving a verbatim block, so a paragraph whose sentences straddle the block boundary mis-triggers (or wrongly suppresses) `long_paragraph` | Fixture: 3 short sentences, a verbatim block, then 4 more short sentences (7 total — the exact count that trips `para_sentences==7` if counted continuously) → no `long_paragraph` finding, because the toggle resets the counter on both sides |
| Code-fence interaction | Marker text recognized even inside a ` ``` ` fenced code block, letting an example snippet accidentally toggle verbatim state | Fixture: marker-looking text inside a fenced code block, with real violating prose immediately after the fence closes → the fenced text does not toggle state; the real prose after the fence is still scanned and flagged |

## Stranger Test

PASS — 5 tasks reviewed (implementation-planner agent dispatch). One precondition satisfied inline rather than left implicit: the planner found `.flow/goals/issue-180.goal.yaml`'s AC1-3 `verification_command` named the wrong test file (`bin-scripts.test.sh` instead of `prose-lint.test.sh`, which actually holds this linter's fixture helpers) and `allowed_paths` omitted `plugins/dossier/tests/prose-lint.test.sh`. Fixed directly in the goal file (recorded as a `goal-amendment` artifact) rather than left for the executing task to discover silently.

Task boundaries: Task 1 bundles AC1+AC2+AC3 (one awk-program edit region, one test file, four risk-map rows each with its own fixture). Task 2 = AC4 (audit.md). Task 3 = AC5 (docs), sequenced after 1 and 2 so it documents the finished mechanism. Task 4 files the follow-up issue for the pre-existing 17-script `--help` truncation bug (confirmed via live `gh issue list` that no such issue exists yet, so the Non-goals claim above is not yet true until this task runs). Task 5 is the final full-suite + CHANGELOG + self-review gate.


<!-- auto-log: 2026-09-15 01:00 Write /Users/danielbentes/synapti-marketplace/.flow/goals/issue-180.goal.yaml -->

<!-- auto-log: 2026-09-15 01:14 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-180.md -->

<!-- auto-log: 2026-09-15 01:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/prose-lint.test.sh -->

<!-- auto-log: 2026-09-15 01:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 01:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/commands/audit.md -->

<!-- auto-log: 2026-09-15 01:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-09-15 01:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/prose-clarity/SKILL.md -->

<!-- auto-log: 2026-09-15 01:21 commit "docs(dossier): document the verbatim-marker G18 exemption" -->

<!-- auto-log: 2026-09-15 07:40 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 07:41 commit "docs(dossier): CHANGELOG entry for the G18 verbatim-collection fix" -->
