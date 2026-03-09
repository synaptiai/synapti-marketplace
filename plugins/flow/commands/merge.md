---
description: "[flow] Merge an approved pull request. Verifies prerequisites (approval, checks, conversations), displays assessment, and requires explicit human confirmation. Tier 3 — never autonomous."
argument-hint: <pr-number>
allowed-tools: Bash, Read, AskUserQuestion
---

# Merge PR #$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. This is non-negotiable even in autonomous mode.

## Required Skills

- `merge-and-release` — prerequisite verification, merge execution

## Phase 1: Verify Prerequisites

**Parallel checks:**

```bash
# 1. PR status
gh pr view $ARGUMENTS --json reviewDecision,statusCheckRollup,mergeable,mergeStateStatus,title,headRefName

# 2. Reviews
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | "\(.state) by \(.author.login) at \(.submittedAt)"'

# 3. Unresolved conversations
gh pr view $ARGUMENTS --json reviewThreads --jq '[.reviewThreads[] | select(.isResolved == false)] | length'

# 4. Stale approval check
gh pr view $ARGUMENTS --json reviews,commits --jq '{
  last_approval: [.reviews[] | select(.state == "APPROVED")] | sort_by(.submittedAt) | last | .submittedAt,
  last_commit: .commits | last | .committedDate
}'
```

## Phase 2: Display Assessment

```markdown
## Merge Assessment for PR #$ARGUMENTS

| Check | Status | Details |
|-------|--------|---------|
| Approval | {Pass/Fail} | {N approvals, latest by @X} |
| CI Checks | {Pass/Fail} | {N passed, M failed} |
| Mergeable | {Pass/Fail} | {No conflicts / Has conflicts} |
| Conversations | {Pass/Fail} | {All resolved / N unresolved} |
| Stale Approval | {OK/Warning} | {Fresh / Commits after approval} |

**Merge strategy**: {from settings.merge.strategy, default: squash}
**Delete branch**: {from settings.merge.deleteBranch, default: true}
```

If any check fails, explain what needs to be fixed and suggest actions.

## Phase 3: Confirm and Execute

Use the AskUserQuestion tool with contextual options to confirm: "PR #$ARGUMENTS is ready to merge. Proceed with squash merge and branch deletion?"

Only after the user confirms via the tool:

```bash
# Read merge settings
STRATEGY="squash"  # or from settings
DELETE_FLAG="--delete-branch"  # or from settings

gh pr merge $ARGUMENTS --$STRATEGY $DELETE_FLAG
```

## Phase 4: Post-Merge

```bash
# Verify merge
gh pr view $ARGUMENTS --json state --jq '.state'

# Switch to default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git checkout $DEFAULT_BRANCH
git pull origin $DEFAULT_BRANCH
```

Suggest: `/flow:release {type}` if this completes a milestone.
