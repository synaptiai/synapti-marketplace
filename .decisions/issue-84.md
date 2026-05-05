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
| 1 | `### Findings Ledger` section appears | `grep -F '### Findings Ledger' plugins/flow/commands/status.md` returns the new instruction block | PASS |
| 2 | Counts across author's + assignee's open PRs | Dry-run the bash queries against current repo state; verify count matches `gh pr view` markers manually | PASS |
| 3 | Reuses parsing from merge.md | `grep -l finding-ledger-parser plugins/flow/commands/{status,merge}.md` returns both | PASS |
| 4 | P2 in fix-forward annotation | Dry-run on PR with P2 in FINDINGS but not in RESOLVED → output contains `(in fix-forward)` | PASS |
| 5 | P3 ESCALATED annotation | Dry-run on PR with P3 in ESCALATED → output contains `(ESCALATED — ...)` | PASS |
| 6 | Empty state renders cleanly | Repo with no markers → output contains `No open findings` and no error | PASS |
| 7 | Format matches slides.md mockup | `diff` rendered output line against slides.md:802-810 format | PASS |

## Stranger Test
PASS — single task: edit `commands/status.md` to add the Findings Ledger section with inline bash queries that cite `references/finding-ledger-parser.md`. New file `references/finding-ledger-parser.md` carries the canonical queries. A zero-context agent reading the issue + this journal could execute and verify.

## Decisions

- **2026-05-06** — Read both markers (FLOW_REVIEW_CYCLE for priority, FLOW_RESOLUTION_CYCLE for state). Issue body said "RESOLUTION_CYCLE only" but slide format requires priority labels.
- **2026-05-06** — PR scope = author OR assignee (matches issue wording, user confirmed default).
- **2026-05-06** — Dedup via `references/finding-ledger-parser.md` (soft dedup, fits existing convention).
- **2026-05-06** — Tier Summary section explicitly out of scope; Tier Summary work was deferred when PR #91 was closed and issue #90 marked not-planned.

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
