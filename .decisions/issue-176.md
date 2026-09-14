---
issue: 176
created: '2026-09-14T15:06:23Z'
artifacts:
- type: specification
  captured_at: '2026-09-14T15:06:23Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-14T15:08:29Z'
  goal_id: issue-176
  from: draft
  to: active
  trigger: command
- type: workflow-run
  captured_at: '2026-09-14T15:12:01Z'
  workflow: start-issue
  run_id: 2026-09-14T145858Z-issue-176
  status: active
---
# Issue #176 — claim-scan cannot see bullets or table rows

## Specification

_Captured by specification-capture skill on 2026-09-14. Source: mixed (extracted-from-issue + drafted from codebase read)._

### Non-goals

- Not fixing `dossier-package-check.sh`'s analogous "clean result, invisible scope" shape (`CHECK_RESULT=CLEAN` with `CHECK_LINKS_CHECKED=0`) — noted in the issue as related but explicitly out of scope for this fix.
- Not changing the registration match algorithm itself (normalized literal-substring `grep -qF` against the approved-wording pool) — only which lines are fed into it. **Accepted residual risk** (confirmed live at PR-gate review, not merely theoretical): the substring match can silently approve an unscoped document sentence that happens to be a literal substring of a longer, differently-scoped approved wording — pre-existing since 2026-07-26, unrelated to this issue, made no worse in kind by this fix, but this fix increases exposure since table cells and bullets are the terse, fragment-like shape most likely to trigger it. Tracked as issue #200; a correct fix needs symmetric sentence-boundary handling on both the document and register sides, not a mechanical swap to exact matching.
- Not adding fuzzy/semantic matching for claims.
- Not changing the claim register file format or the `## Required qualifications` handling.
- Not touching frontmatter/header skip logic (`IN_HEADER`, lines 219-237) — that is a separate, correct mechanism.

### Failure modes

- **Timeouts** — none; this is a synchronous, local, single-pass text scan with no network or long-running I/O.
- **Partial failures** — n/a; the script processes one file at a time in a loop and a parse failure on one line must not abort the whole file (existing `continue`-based control flow preserved).
- **Invalid input** — a malformed table row (unbalanced `|`, e.g. a stray pipe inside inline code that wasn't stripped) must not crash the script; worst case is an extra/missing empty cell, not a non-zero exit from a parse error.
- **Missing context** — if the claim register file is absent or empty (`REGISTER_PRESENT=0`), the existing behavior (report registration is not being checked) is unchanged; this fix only changes what counts as a candidate sentence, not what happens when there's nothing to check it against.

### Interface contracts

- CLI contract unchanged: `dossier-claim-scan.sh [--file <path>] [--json] [--output-root <dir>]`, exit codes unchanged (0 clean / 1 findings / 2 leak / 3 missing dir).
- Plain-text summary output gains one new line, e.g. `CLAIM_SCAN_LINE_CLASSES_EXAMINED=paragraph,bullet,blockquote,table-cell` (exact classes list, heading/fence excluded) — additive, does not remove or reorder the four existing `CLAIM_SCAN_*` lines (`dossier-claim-scan.sh:295-298`).
- `--json` output object gains a parallel key (e.g. `"line_classes_examined": ["paragraph","bullet","blockquote","table-cell"]`) alongside the existing `leaks`/`prohibited`/`unregistered`/`register_present`/`hits` keys (`dossier-claim-scan.sh:283-293`) — additive, existing keys unchanged.
- `unregistered` hit rows (`HITS_FILE`, `dossier-claim-scan.sh:273-274`) keep their existing `unregistered\t<file>\t<line>\t<redacted-excerpt>` shape for hits found in bullets/blockquotes/table-cells — no new hit-row format.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| table row splitting | splits on every `\|` without skipping the header/separator row, so `| Field | Value |` and `\|---\|---\|` themselves get scored as candidate sentences | fixture table `\| Field \| Value \|` / `\|---\|---\|` / `\| Region \| eu-west-1 \|` with no matching register row → right: 0 unregistered hits from header/separator, only genuine declarative cell content considered; wrong: header row `Field, Value` flagged as an unregistered claim |
| bullet marker stripping | strips only `- ` but not `* `, or strips the marker but leaves a leading space that defeats the word-floor/normalize trim | bullet `* There are no binaries and no bundles; you can read every hook before you install it` (from the issue's own real example) → right: examined as a sentence, flagged unregistered; wrong: still skipped because only `- ` markers are handled |
| line-class exemption boundary | the new selector accidentally treats fenced-code content or heading text as candidate prose (i.e. only removes the skip for `\|`/`- `/`* `/`> ` but the `IN_FENCE` or `#` check gets reordered/broken) | fixture with a heading `# 99.99% availability` and a fenced code block containing the same sentence as prose → right: 0 hits from both; wrong: heading or fence content flagged |
| blockquote handling | blockquote text is stripped of the `> ` marker but multi-line blockquotes (`> line1` / `> line2`) get concatenated or truncated, corrupting the sentence before normalization | two-line blockquote whose declarative claim only reads correctly across both lines → right: each line is still evaluated as its own sentence per the existing per-line loop (matches how bullets/paragraphs are already handled per-line, not batched) so at least the line containing the claim is flagged; wrong: script errors or silently drops the second line |
| new summary field placement | the new `LINE_CLASSES_EXAMINED` field is computed once from static config rather than reflecting what the loop actually processed this run, e.g. printed even when `--file` scoped to a doc with zero bullets/tables | fixture with a paragraph-only file (no bullets, no tables) → right: field still lists all classes the *scanner is capable of* examining (this is a capability disclosure, not a per-file "classes present" count — matches issue's ask to make the *scope* legible, not to report what happened to be in this one file); confirmed against the issue's exact wording: "emit the covered line classes alongside the count" |

<!-- auto-log: 2026-09-14 17:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-14 17:21 commit "fix(dossier): claim-scan now examines bullets, blockquotes, and table cells" -->

<!-- auto-log: 2026-09-14 17:21 Write /tmp/activity-code-176.yaml -->

<!-- auto-log: 2026-09-14 17:21 Edit /tmp/activity-code-176.yaml -->

<!-- auto-log: 2026-09-14 17:21 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-09-14T145858Z-issue-176/run.yaml -->

<!-- auto-log: 2026-09-14 17:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:24 commit "test(dossier): prove registered bullet/table/blockquote claims round-trip" -->

<!-- auto-log: 2026-09-14 17:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:28 commit "fix(dossier): attribute a held table row's findings to its own line" -->

<!-- auto-log: 2026-09-14 17:39 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_dossier_claim_scan_scope_gaps.md -->

<!-- auto-log: 2026-09-14 17:39 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-14 17:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:50 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 17:53 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 17:54 commit "fix(dossier): fix crash and code-span mis-split found in code review" -->

<!-- auto-log: 2026-09-14 18:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 18:11 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 18:11 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 18:12 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 18:13 commit "fix(dossier): protect escaped backslashes from the table-cell pipe split" -->

<!-- auto-log: 2026-09-14 18:13 Write /tmp/followup-redact-residue.md -->

<!-- auto-log: 2026-09-14 18:13 Write /tmp/followup-scan-perf.md -->

<!-- auto-log: 2026-09-14 18:14 Edit /tmp/followup-scan-perf.md -->

<!-- auto-log: 2026-09-14 18:14 Edit /tmp/followup-scan-perf.md -->

<!-- auto-log: 2026-09-14 19:57 Write /tmp/evidence-bundle-176.md -->

<!-- auto-log: 2026-09-14 20:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 20:04 commit "test(dossier): pin the escaped-pipe no-split case the escape marker exists for" -->

<!-- auto-log: 2026-09-14 20:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 20:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 20:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-14 20:23 commit "fix(dossier): flush table state before crossing a fenced code block" -->

<!-- auto-log: 2026-09-14 20:33 Write /tmp/followup-substring-match.md -->

<!-- auto-log: 2026-09-14 20:42 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-176.md -->

<!-- auto-log: 2026-09-14 20:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-14 20:48 commit "docs(dossier): pin two-line blockquote coverage, annotate accepted risk" -->

<!-- auto-log: 2026-09-14 21:10 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-test-runner/feedback_sequential_suites.md -->

<!-- auto-log: 2026-09-14 21:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-14 21:20 commit "docs(dossier): describe the final state in CHANGELOG, not just the first fix" -->
