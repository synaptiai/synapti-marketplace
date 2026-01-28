---
description: Show workflow status overview - assigned issues, open PRs, review requests
allowed-tools: Bash
---

# Workflow Status

Quick overview of current GitHub workflow state.

## Process

1. **Show assigned issues**:
   ```bash
   gh issue list --assignee @me --state open --json number,title,labels
   ```

2. **Show your open PRs**:
   ```bash
   gh pr list --author @me --state open --json number,title,reviewDecision,statusCheckRollup
   ```

3. **Show PRs awaiting your review**:
   ```bash
   gh pr list --search "review-requested:@me" --json number,title,author
   ```

4. **Show PRs with unaddressed feedback** (your PRs with changes requested):
   ```bash
   gh pr list --author @me --search "review:changes_requested" --json number,title
   ```

## Output Format

```
## Workflow Status

### Your Assigned Issues (N)
- #12 Issue title [bug]
- #15 Another issue [enhancement]

### Your Open PRs (N)
- #20 PR title - Approved, checks passing
- #22 PR title - Changes requested

### Awaiting Your Review (N)
- #18 PR title by @author

### Needs Attention (N)
- #22 Has unaddressed review feedback
```

## Status Indicators

| Status | Meaning |
|--------|---------|
| Approved | PR has been approved by reviewers |
| Changes requested | PR needs updates based on review feedback |
| Checks passing | All CI checks are green |
| Checks failing | One or more CI checks failed |
| Awaiting review | PR is waiting for review |

## Usage

```bash
# Show workflow status
/gh-workflow:gh-status
```

## Rules

- This command is read-only (no modifications)
- Shows only items relevant to the current user
- Highlights items that need attention
- Groups information by category for quick scanning
