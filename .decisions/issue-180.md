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
- type: goal-evaluation
  captured_at: '2026-09-15T07:55:16Z'
  goal_id: issue-180
  result: achieved
  evidence_bundle: .flow/runs/2026-09-15T000000Z-issue-180
- type: goal-evaluation
  captured_at: '2026-09-15T08:33:00Z'
  goal_id: issue-180
  result: achieved
  note: evidence_refreshed_post_review_fixes
- type: review-cycle
  captured_at: '2026-09-15T08:57:11Z'
  cycle: 1
  path: B
  findings_count: 12
  pr: 208
---
# Issue #180 — G18 and the verbatim-collection rule are in direct conflict

## Specification

### Non-goals

- Does NOT implement Option 1's heading/round-based scoping instead of explicit markers — markers are strictly more precise and do not depend on the exact wording of a round heading, so choosing between "Option 1 or 2" (the issue's own framing) resolves to Option 2's mechanism scoped the way Option 1 asked: the intersection, not a third design.
- Does NOT implement Option 3 (link out to `.dossier/runs/<id>/` instead of inlining) — deliberately rejected per the issue's own reasoning: it would lose the property that the committed package carries its own evidence.
- Does NOT add abuse-detection tooling for a document author who manually inserts fake verbatim markers to dodge G18 — mitigated structurally instead, by scoping marker-honoring to `07-verification/documentation-verification-report.md` only; markers anywhere else are inert HTML comments and the text between them is scanned like any other prose.
- Does NOT change `dossier-claim-scan.sh` or any other dossier linter to honor the same markers — this fix is `dossier-prose-lint.sh`-specific, and that boundary is documented explicitly (AC5) rather than assumed.
- Does NOT touch the `--help` hardcoded-range truncation bug (`sed -n '2,Np'`) present in 16 other `plugins/dossier/bin/*.sh` scripts that share the same pattern (confirmed via `grep -n "sed -n '2," plugins/dossier/bin/*.sh` — 18 raw matches, minus the two already fixed with the self-terminating form: `dossier-scaffold.sh` from issue #178, and `dossier-prose-lint.sh` from this PR). Only `dossier-prose-lint.sh`'s own `--help` is fixed in this PR. The other 16 are pre-existing and unrelated to this issue's scope; filed as a separate follow-up issue rather than swept here.

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
| Unclosed code fence (added post-self-review, F1) | An unbalanced ` ``` ` reads as clean instead of erroring — the pre-existing `in_fence` toggle had no unclosed sentinel (unlike `in_header`), so every remaining line silently reads as still-fenced and dictionary-hit prose after it is never scanned; a fence left open inside a verbatim block can also swallow the real `END` marker | Fixture: unclosed fence with dictionary-hit prose after it → `scan_error`, not `0`. Second fixture: unclosed fence inside a verbatim block, swallowing the real `END` → exactly one `scan_error`, reported as the fence (root cause), not the verbatim block |
| File-scoping, bare relative path (added post-self-review, F2) | The `case "$f" in */07-verification/...` pattern requires a literal `/` before the suffix, so a bare relative path exactly equal to the suffix (no leading directory) loses the exemption | Fixture: `cd` into the fixture package root, invoke `--file` with the bare relative path → `verbatim_blocks == 1`, not `0` |
| File-scoping, decoy path in `--output-root` (added post-security-review, SEC-1) | The suffix-only `case` match had no path-boundary anchor, so `--output-root` (which walks the whole tree) honored the exemption for ANY file whose tail matched the suffix, not just the one real canonical file — a decoy nested at `<root>/decoy/07-verification/documentation-verification-report.md` could dodge G18 for its own violating prose | Fixture: a clean canonical file plus a decoy file at a non-canonical path sharing only the filename, both under one `--output-root`, violating prose in the decoy's markers → package still fails (`blocking_violations > 0`), decoy's `verbatim_blocks == 0` |
| Marker regex, look-alike prefix (added post-code-review, F3) | `^<!-- DOSSIER_VERBATIM_BEGIN`/`END` with no trailing delimiter matches any line starting with that prefix, including an unrelated comment like `<!-- DOSSIER_VERBATIM_BEGINNING_OF_SOMETHING_ELSE -->`, opening or closing a real exemption for prose never meant to be marked verbatim | Fixture: a BEGIN look-alike prefix → the sentence after it is still counted, not exempted. Second fixture: an END look-alike prefix inside a real block → the sentence after it stays exempt until the genuine END |

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

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/prose-lint.test.sh -->

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-09-15 08:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/prose-clarity/SKILL.md -->

<!-- auto-log: 2026-09-15 08:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/prose-lint.test.sh -->

<!-- auto-log: 2026-09-15 08:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 08:04 commit "fix(dossier): unclosed-fence scan error and bare-relative-path scoping" -->

<!-- auto-log: 2026-09-15 08:04 commit "docs(dossier): correct claim-scan scoping claim, tighten exemption wording" -->

<!-- auto-log: 2026-09-15 08:07 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-180.md -->

<!-- auto-log: 2026-09-15 10:06 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_verbatim_marker_path_scoping_gap.md -->

<!-- auto-log: 2026-09-15 10:06 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-15 10:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/prose-lint.test.sh -->

<!-- auto-log: 2026-09-15 10:08 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/feedback_dossier_bin_verification_technique.md -->

<!-- auto-log: 2026-09-15 10:08 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/MEMORY.md -->

<!-- auto-log: 2026-09-15 10:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 10:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-09-15 10:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 10:11 commit "fix(dossier): anchor --output-root verbatim scoping to the exact path" -->

<!-- auto-log: 2026-09-15 10:11 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-180.md -->

<!-- auto-log: 2026-09-15 10:16 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/project_dossier_bin_verification_technique.md -->

<!-- auto-log: 2026-09-15 10:16 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/MEMORY.md -->

<!-- auto-log: 2026-09-15 10:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/prose-lint.test.sh -->

<!-- auto-log: 2026-09-15 10:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 10:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-prose-lint.sh -->

<!-- auto-log: 2026-09-15 10:24 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 10:24 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-180.md -->

<!-- auto-log: 2026-09-15 10:24 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-180.goal.yaml -->

<!-- auto-log: 2026-09-15 10:24 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-180.md -->

<!-- auto-log: 2026-09-15 10:26 commit "docs(dossier): correct the --help truncation follow-up's script count" -->

<!-- auto-log: 2026-09-15 10:33 Write /tmp/pr-180-body.md -->
