---
description: "Display a read-only overview of workflow state including assigned issues, open PRs, pending reviews, branch state, and decision journal health. Use when checking current development status."
allowed-tools: Bash, Read
---

# Workflow Status

Read-only overview of the current development state. No skills needed — pure observation.

## Gather State

Execute all queries in parallel:

```bash
# 1. Current branch and uncommitted changes
git branch --show-current
git status --short | head -20

# 2. Commits ahead of default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git rev-list --count "$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo "0"

# 3. Assigned issues
gh issue list --assignee @me --state open --limit 10 --json number,title,labels

# 4. Open PRs (authored)
gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup

# 5. PRs needing my review
gh pr list --search "review-requested:@me" --state open --json number,title,author

# 6. Decision journal health
JOURNAL_DIR=".decisions"
[ -d "$JOURNAL_DIR" ] && ls -la "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l || echo "0"

# 7. Learning pending
[ -f "$HOME/.claude/flow-learn-pending" ] && echo "LEARNING PENDING: $(cat $HOME/.claude/flow-learn-pending)" || echo "No pending learning"
```

## Display

```markdown
## Flow Status

### Current Branch
- **Branch**: {branch name}
- **Commits ahead**: {N} ahead of {default branch}
- **Uncommitted changes**: {count} files

### My Issues (Open)
| # | Title | Labels |
|---|-------|--------|
| {N} | {title} | {labels} |

### My PRs
| # | Title | Status | Checks |
|---|-------|--------|--------|
| {N} | {title} | {review status} | {check status} |

### Awaiting My Review
| # | Title | Author |
|---|-------|--------|
| {N} | {title} | @{author} |

### Decision Journal
- **Journals**: {N} active
- **Learning**: {pending/none}

### Suggested Next Action
{Based on state, suggest the most useful /flow command}
```

## Suggestions Logic

| State | Suggestion |
|-------|-----------|
| On default branch, no assigned issues | "Assign an issue or `/flow:start <N>`" |
| On default branch, has assigned issue | "`/flow:start {first-issue-number}`" |
| On feature branch, uncommitted changes | "`/flow:commit`" |
| On feature branch, commits ahead, no PR | "`/flow:pr`" |
| Has PR with review comments | "`/flow:address {pr-number}`" |
| Has PR approved | "`/flow:merge {pr-number}`" |
| PRs awaiting review | "`/flow:review {first-pr-number}`" |
| Learning pending | "`/flow:learn`" |
