---
name: pr-lifecycle
description: "Reference document describing PR lifecycle: pre-flight gates (4 conditions), verification gate (5 conditions), body structure (7 sections), reviewer-suggestion algorithm (CODEOWNERS → file expertise → recent activity → workload balance), and finding-ledger merge prerequisite. Reference only (policy document; consumed by `/flow:pr` and `/flow:merge`)."
allowed-tools: Read
agent: general-purpose
disable-model-invocation: true
---

# PR Lifecycle

Reference document for the PR creation and pre-merge policy. The executable bash lives in `plugins/flow/commands/pr.md` (full creation flow) and `plugins/flow/commands/merge.md` (finding-ledger check). This skill describes **what those commands enforce and why**, so reviewers can audit the policy without reading shell.

## Iron Law

**NO PR WITHOUT VERIFICATION. Every PR must have proof that quality checks pass. "I think it works" is not a PR description.**

If you can't show test results, lint output, or verification evidence in the PR body, the PR is not ready.

## Pre-Flight Gate

Before any PR is created, four conditions are verified:

| # | Condition | Failure handling |
|---|-----------|------------------|
| 1 | Not on the default branch | Hard error — PRs are made from feature branches, never from `main` |
| 2 | At least one commit ahead of the default branch | Hard error — empty PRs are noise |
| 3 | No uncommitted changes | Warning — offer to commit first via `/flow:commit` |
| 4 | No existing open PR for this branch | Hard error — update the existing PR instead of creating a duplicate |

The runnable checks are in `plugins/flow/commands/pr.md` Phase 1 (EXPLORE). The command is the single source of truth.

## Verification Gate

Before the PR is created, every one of the following must hold. If any fail, stop:

1. All quality commands (lint, test, typecheck) pass — output captured for the PR body
2. Self-review completed against the `code-quality-principles` checklist
3. Change classification shows no out-of-context files
4. Every acceptance criterion has a "Met" or "Interpreted" status with concrete evidence
5. No P1 findings remain from code review

This gate is **mandatory**. Skipping it to "get the PR up quickly" creates reviewer burden and shifts the verification cost to whoever reads the PR.

For the canonical map of all eight quality gates flow enforces — Spec Validation, Stranger Test, Per-Task Verification, Runtime Verification, Evidence Completeness, Missing-Criterion Scan, Holdout Validation, and Finding-Ledger Merge — see [`gate-configuration.md`](../../references/gate-configuration.md#quality-gates).

## PR Body Structure

The PR body is generated from a fixed template plus review findings plus the decision journal. Sections, in order:

- **Summary** — 2-3 sentence description of what changed and why
- **Closes** — issue link
- **Changes** — bulleted list of key changes, grouped by area
- **Comprehension Report** — what was built, why, architecture decisions
- **Requirements Adherence** — table mapping each acceptance criterion to status and evidence (file:line)
- **Key Decisions** — public entries from the decision journal; internal redacted
- **Review Findings** — P1/P2/P3 summary from code review
- **Verification** — checklist confirming quality checks, self-review, runtime verification
- **Files Changed** — grouped by area with a brief description per group

Why this shape: reviewers should be able to skim **Summary → Requirements Adherence → Verification** in under thirty seconds and decide whether to do a deep read. A PR body that buries the acceptance-criterion mapping or omits verification evidence forces every reviewer to reconstruct context the author already had.

## Reviewer Suggestion Algorithm

Reviewer selection follows this priority cascade:

1. **CODEOWNERS match** — if the file paths in the diff have CODEOWNERS entries, those owners are first-priority candidates.
2. **File expertise** — recent contributors (last 30 days) to the same files in the diff.
3. **Recent activity** — contributors who have shipped to adjacent areas of the codebase recently.
4. **Workload balancing** — among equally-qualified candidates, prefer the one with fewer outstanding review requests.

The PR command surfaces the top 2-3 candidates with a one-line rationale per candidate. The author makes the final call.

## Push and Create — Tier 2

Both `git push -u origin <branch>` and `gh pr create` are **Tier 2** (journal-and-proceed): the agent executes them and logs the action, but does not require explicit human confirmation each time. This tier classification is recorded in `plugins/flow/commands/pr.md`.

After creation, the command verifies the PR exists via `gh pr view --json number,url,state,title` and surfaces the PR URL plus a suggested next step (`/flow:review {number}`).

## Merge Prerequisite: Finding-Ledger Check

Before a PR can be merged via `/flow:merge`, the **finding ledger** is checked to ensure all review findings have been resolved. The runnable parser lives in `plugins/flow/commands/merge.md` Phase 1 (Finding-Ledger Check).

### What the ledger tracks

PR comments carry two markers:

- **`FLOW_REVIEW_CYCLE:{N} FINDINGS:[...]`** — the finding IDs emitted during review cycle N
- **`FLOW_RESOLUTION_CYCLE:{N} RESOLVED:[...] ESCALATED:[...] DISPUTED:[...]`** — the disposition of each finding after `/flow:address`

The latest comment of each kind is parsed and compared.

### What blocks a merge

1. **Non-empty `ESCALATED` array** — `ESCALATED:[F3]` means at least one finding was escalated but not resolved. The merge gate blocks until every escalated item is resolved or the array is empty.
2. **Unmatched `FINDINGS`** — any finding ID present in `FLOW_REVIEW_CYCLE:FINDINGS` that has no corresponding entry in `FLOW_RESOLUTION_CYCLE:RESOLVED` is considered unresolved. The merge gate blocks until every finding has a matching `RESOLVED` entry.

### How to clear the gate

1. Run `/flow:address {pr_number}` to address remaining findings
2. Fix or respond to each unresolved finding until all appear in the `RESOLVED` array
3. Ensure the `ESCALATED` array is empty in the latest resolution comment
4. Re-run `/flow:merge {pr_number}`

This gate enforces the **"no incomplete shipments"** hard boundary from organizational governance. Merging with unresolved findings is a violation, not a judgment call.

## Rationalization Prevention

The PR pipeline blocks these recurring excuses by structure, not by exhortation:

| Excuse | Response |
|--------|----------|
| "I'll fix it after the PR is up" | Fix it now. Draft PRs accumulate, they don't improve. |
| "The reviewer will catch any issues" | You are the first reviewer. Don't outsource your job. |
| "It's a small change, no need for full pre-flight" | Small changes, same process. The cost of pre-flight is small; the cost of a malformed PR is reviewer time. |
| "CI will validate it" | CI validates what it tests. Pre-flight validates what CI doesn't. |

## Where the Bash Lives

This skill is reference-only. The runnable implementations are:

- **Pre-flight checks**: `plugins/flow/commands/pr.md` Phase 1 (EXPLORE)
- **PR body assembly + push + create**: `plugins/flow/commands/pr.md` Phase 4 (VERIFY)
- **Reviewer suggestion**: `plugins/flow/commands/pr.md` Phase 4 step 11
- **Finding-ledger merge gate**: `plugins/flow/commands/merge.md` Phase 1

When the policy needs to change — a new pre-flight check, a new PR body section, a new ledger marker — update the command and update this reference together. Keeping the bash and the rationale in lockstep prevents the silent drift that motivated this consolidation.
