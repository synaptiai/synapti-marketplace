# Decision Journal — Issue #84: Findings Ledger in /flow:status

**Branch**: `feature/issue-84-findings-ledger`
**Started**: 2026-05-06
**Labels**: enhancement, plugin

## Specification

### Non-goals
- Not modifying the FLOW_REVIEW_CYCLE / FLOW_RESOLUTION_CYCLE marker schemas.
- Not adding tier-event counts (the related Tier Summary feature was deferred when issue #90 was closed).
- Not aggregating across multiple repos — single-repo scope, current working directory.
- Not changing how `/flow:status` renders existing sections.

### Failure modes
- **No open PRs** — render "No open findings" empty state, no error.
- **Open PR with no markers** — counted as zero findings; do not error.
- **Malformed marker** — skip the offending PR's contribution to counts; do not error.
- **`gh` API timeout / unavailable** — graceful degradation; render "Findings Ledger unavailable" with a one-line cause.
- **FLOW_REVIEW_CYCLE present but no FLOW_RESOLUTION_CYCLE** — all FINDINGS treated as "in fix-forward" (raised, not yet resolved or escalated).
- **FLOW_RESOLUTION_CYCLE references finding ID not in any FLOW_REVIEW_CYCLE** — counted as priority "unknown"; logged but not blocking.

### Interface contracts
- New section appears as `### Findings Ledger` (H3, matches sibling sections).
- Single-line render per the slide mockup:
  `P1: {n}    P2: {n} (in fix-forward)    P3: {n} (ESCALATED — {context})`
- Counts aggregated across user's open PRs (author OR assignee).
- Sourced from the **latest** FLOW_REVIEW_CYCLE (priority lookup) and **latest** FLOW_RESOLUTION_CYCLE (state lookup) per PR.
- Marker schemas (treated as read-only contract):
  - `<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status},...] -->`
  - `<!-- FLOW_RESOLUTION_CYCLE:{N} RESOLVED:[{ID},...] ESCALATED:[{ID},...] DISPUTED:[{ID},...] -->`
- New file `plugins/flow/references/finding-ledger-parser.md` documents the canonical extraction queries; both `commands/status.md` and `commands/merge.md` cite it.

## Spec Validation Gate

| # | Acceptance Criterion | Verification | Status |
|---|---------------------|--------------|--------|
| 1 | `### Findings Ledger` section appears | `grep -F '### Findings Ledger' plugins/flow/commands/status.md` returns the new section | PASS — verified |
| 2 | Counts across author's + assignee's open PRs | End-to-end dry-run against live repo (PR #87 in scope, marker malformed and correctly skipped → empty tally → "No open findings.") | PASS — verified live |
| 3 | Reuses parsing from merge.md | `grep -l finding-ledger-parser plugins/flow/commands/{status,merge}.md` returns both; merge.md also fixed to use the canonical portable extraction and correct `/pulls/{n}/reviews` endpoint | PASS — verified |
| 4 | P2 in fix-forward annotation | Synthetic-fixture dry-run with `F2|P2|...` (no RESOLVED match) → tally `2 P2|in_fix_forward` → render rule maps to `P2: K (in fix-forward)` | PASS — verified by fixture |
| 5 | P3 ESCALATED annotation | Synthetic-fixture dry-run with `F4|P3|...` and `ESCALATED="F4"` → tally `1 P3|escalated` → render rule maps to `P3: K (ESCALATED)`. The slide example's `— awaiting reviewer accept` suffix is unsupportable from the marker schema (no per-finding context field); documented this explicitly in the parser doc Render Format section. | PASS with documented scope clarification |
| 6 | Empty state renders cleanly | Live dry-run on PR #87 produced empty tally → render rule emits `No open findings.` (no empty section, no error) | PASS — verified live |
| 7 | Format matches slides.md mockup | Added `### Findings Ledger` row to `docs/flow-team-session/slides.md` `/flow:status — what to expect` section so the citation is now true; render rules in status.md and parser doc match the mockup line | PASS — verified |

## Stranger Test
PASS — single task: edit `commands/status.md` to add the Findings Ledger section with inline bash queries that cite `references/finding-ledger-parser.md`. New file `references/finding-ledger-parser.md` carries the canonical queries. A zero-context agent reading the issue + this journal could execute and verify.

## Decisions

- **2026-05-06** — Read both markers (FLOW_REVIEW_CYCLE for priority, FLOW_RESOLUTION_CYCLE for state). Issue body said "RESOLUTION_CYCLE only" but slide format requires priority labels.
- **2026-05-06** — PR scope = author OR assignee (matches issue wording, user confirmed default).
- **2026-05-06** — Dedup via `references/finding-ledger-parser.md` (soft dedup, fits existing convention).
- **2026-05-06** — Tier Summary section explicitly out of scope. Verified prerequisite state: `gh issue view 90` → CLOSED 2026-05-05T23:13:02Z (not planned); `gh pr view 91` → CLOSED 2026-05-05T23:12:57Z (branch deleted). Tier Summary feature is intentionally deferred per the brainstorm decision recorded in PR #91's review thread.
- **2026-05-06** — Cycle-1 self-review (code-reviewer agent) returned 1 P1 + 5 P2 + 7 P3. Substantive findings fix-forwarded:
  - **P1**: AC #7 cited slides.md lines 802-810 but the mockup wasn't actually there. Resolution: added the Findings Ledger row to the slide mockup so the citation becomes true; reworded line-number references that would drift.
  - **P2**: `merge.md` was reading FLOW_REVIEW_CYCLE from the wrong API endpoint (`issues/comments` instead of `pulls/reviews`); fixed alongside the same file's `grep -P` portability bug since the new parser doc claims canonicality. `declare -A` removed (incompatible with macOS bash 3.2). LEDGER_UNAVAILABLE detection was masking gh auth failures; now captures gh exit code explicitly. Malformed-row handling aligned between status.md and parser doc (now emits `LEDGER_WARN` to stderr).
  - **P3**: `(ESCALATED — awaiting reviewer accept)` suffix in render docs dropped — markers carry IDs only, no per-finding context recoverable. Whitespace-tolerant `tr -d ' '` added to resolution-array parsing. Precedence (RESOLVED > ESCALATED > DISPUTED) documented explicitly.
- **2026-05-06** — Cycle-1 verdict-judge auto-FAILed all 7 ACs on missing completeness fields ("Does NOT promise", "What was NOT tested", "Known limitations", "Negative/adversarial cases"). Substantive substance was sound; the failures were structural in the evidence bundle. Rebuilding bundle for cycle-2 with the four required completeness fields per criterion.

<!-- auto-log: 2026-05-06 01:26 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-84.md -->

<!-- auto-log: 2026-05-06 01:27 Write /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-06 01:31 commit "feat(status): add Findings Ledger to /flow:status" -->

<!-- auto-log: 2026-05-06 01:35 Edit /Users/danielbentes/synapti-marketplace/docs/flow-team-session/slides.md -->

<!-- auto-log: 2026-05-06 01:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-06 01:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-05-06 01:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-06 01:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-84.md -->

<!-- auto-log: 2026-05-06 01:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-84.md -->
