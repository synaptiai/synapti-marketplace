---
name: pr-lifecycle
description: "Create pull requests with pre-flight verification, PR body generation, reviewer suggestion, comprehension narrative, and label selection. Handle push and PR creation as Tier 2 operations. Use when preparing or creating a pull request."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
context: fork
agent: general-purpose
---

# PR Lifecycle

Domain skill for the full PR creation process.

## Iron Law

**NO PR WITHOUT VERIFICATION. Every PR must have proof that quality checks pass. "I think it works" is not a PR description.**

If you can't show test results, lint output, or verification evidence in the PR body, the PR is not ready.

## Pre-Flight Checks

All checks run in parallel:

```bash
# 1. Not on default branch
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
[ "$BRANCH" = "$DEFAULT_BRANCH" ] && echo "ERROR: On default branch" && exit 1

# 2. Commits ahead
git rev-list --count "$DEFAULT_BRANCH"..HEAD

# 3. No uncommitted changes
git status --porcelain

# 4. No existing PR
gh pr list --head "$BRANCH" --state open --json number
```

Fail if: on default branch, no commits ahead, or PR already exists.

Warn if: uncommitted changes (offer to commit first).

## PR Body Structure

Generate from template + review findings + decision journal:

```markdown
## Summary
{2-3 sentence description of what changed and why}

Closes #{issue_number}

## Changes
{Bullet list of key changes, grouped by area}

## Comprehension Report
{Generated narrative: what was built, why, architecture decisions}

### Requirements Adherence
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | {criterion} | Met | {file:line} |

### Key Decisions
{From decision journal — public entries only, internal redacted}

## Review Findings
{P1/P2/P3 summary from code review}

## Verification
- [ ] Quality checks pass (lint, test, typecheck)
- [ ] Self-review completed
- [ ] Runtime verification (if applicable)

## Files Changed
{Grouped by area with brief description per group}
```

## Verification Gate

Before creating the PR, confirm ALL of these. If any fail, stop:

1. All quality commands (lint, test, typecheck) pass — show output
2. Self-review completed (code-quality-principles checklist)
3. Change classification shows no out-of-context files
4. Every acceptance criterion has a "Met" or "Interpreted" status with evidence
5. No P1 findings remain from code review

This gate is mandatory. Skipping it to "get the PR up quickly" creates reviewer burden.

## Reviewer Suggestion

Algorithm: CODEOWNERS match → file expertise → recent activity → workload balancing.

```bash
# Get contributors for changed files
git log --format='%an' --since='30 days ago' -- $(git diff --name-only $DEFAULT_BRANCH...HEAD) | sort | uniq -c | sort -rn | head -5
# Check CODEOWNERS
cat .github/CODEOWNERS 2>/dev/null
```

Present top 2-3 suggestions with rationale.

## Push and Create

Both are Tier 2 (journal-and-proceed):

```bash
# Push (Tier 2)
git push -u origin $BRANCH

# Create PR (Tier 2)
gh pr create --title "$TITLE" --body "$BODY" --label "$LABELS"
```

## Post-Creation Verification

```bash
gh pr view --json number,url,state,title
```

Display PR URL and suggest: `/flow:review {number}` for self-review or share with team.

## Merge Prerequisite: Finding-Ledger Check

Before a PR can be merged via `/flow:merge`, the finding ledger is checked to ensure all review findings have been resolved.

### What it does

Parses PR comments for `FLOW_RESOLUTION_CYCLE` and `FLOW_REVIEW_CYCLE` markers:

- **`FLOW_REVIEW_CYCLE:{N} FINDINGS:[...]`** — the finding IDs emitted during review
- **`FLOW_RESOLUTION_CYCLE:{N} RESOLVED:[...] ESCALATED:[...] DISPUTED:[...]`** — the disposition of each finding after `/flow:address`

The check extracts the latest of each marker and compares them.

### What triggers a block

1. **Non-empty ESCALATED array** — `ESCALATED:[F3]` means at least one finding was escalated but not resolved. The merge gate blocks until every escalated item is resolved or the ESCALATED array is empty.
2. **Unmatched FINDINGS** — any finding ID present in `FLOW_REVIEW_CYCLE:FINDINGS` that has no corresponding entry in `FLOW_RESOLUTION_CYCLE:RESOLVED` is considered unresolved. The merge gate blocks until every finding has a matching RESOLVED entry.

### How to resolve

1. Run `/flow:address {pr_number}` to address remaining findings
2. Fix or respond to each unresolved finding until all are in the RESOLVED array
3. Ensure the ESCALATED array is empty in the latest resolution comment
4. Re-run `/flow:merge {pr_number}`

This gate enforces the "no incomplete shipments" hard boundary from organizational governance.

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "I'll fix it after the PR is up" | Fix it now. Draft PRs accumulate, they don't improve. |
| "The reviewer will catch any issues" | You are the first reviewer. Don't outsource your job. |
| "It's a small change, no need for full pre-flight" | Small changes, same process. |
| "CI will validate it" | CI validates what it tests. Pre-flight validates what it doesn't. |
