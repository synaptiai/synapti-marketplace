---
name: repo-config
description: Use when needing to get the default branch, detect repository settings, fetch available labels, get repo info for API calls, or when any gh-workflow command needs dynamic repository configuration instead of hardcoded values.
version: 1.0.0
---

# Repository Configuration

This skill provides dynamic repository configuration for all gh-workflow commands, auto-detecting settings so commands work in any repository without hardcoding.

Use TodoWrite to track these mandatory steps:

<required>
1. Fetch default branch dynamically (never hardcode `main` or `master`)
2. Fetch labels dynamically (never assume labels exist)
3. Get repository owner/name for API calls (never hardcode)
</required>

## Quick Reference

### Get Repository Info

```bash
# Full repository details
gh repo view --json name,owner,defaultBranchRef,url,description

# Just the default branch
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'

# Repository owner/name
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

### Get Labels

```bash
# List all labels (always fetch dynamically, never hardcode)
gh label list

# Check if specific label exists
gh label list --search "bug"
```

### Detect Branch Naming Convention

```bash
# Analyze existing branches for patterns
git branch -r --list 'origin/feature/*' | head -5
git branch -r --list 'origin/fix/*' | head -5

# Check recent branch names
git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin/ | head -10
```

### Detect Commit Convention

```bash
# Analyze recent commits for patterns
git log --oneline -20 | head -20
```

## Configuration Detection

### Default Branch

Always detect dynamically:
```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
```

Common values: `main`, `master`, `develop`

### Repository Identification

```bash
# Get owner/repo for API calls
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# Use in gh api calls
gh api repos/$REPO/pulls/123/comments
```

### Label Strategy

**Never hardcode labels.** Always fetch dynamically:

```bash
# Get available labels
gh label list

# Present to user with AskUserQuestion tool
# Let user select from actual available labels
```

### Branch Naming Patterns

Detect from existing branches or use defaults:

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feature/issue-{N}-{desc}` | `feature/issue-42-add-login` |
| Fix | `fix/issue-{N}-{desc}` | `fix/issue-13-typo` |
| Docs | `docs/issue-{N}-{desc}` | `docs/issue-7-readme` |

### Commit Conventions

Detect or default to conventional commits:

| Prefix | Usage |
|--------|-------|
| `feat:` | New features |
| `fix:` | Bug fixes |
| `docs:` | Documentation |
| `refactor:` | Code refactoring |
| `test:` | Test changes |
| `chore:` | Maintenance |

## Usage in Commands

### Before Any Repository Operation

```bash
# Step 1: Get repo info
REPO_INFO=$(gh repo view --json nameWithOwner,defaultBranchRef)
REPO=$(echo $REPO_INFO | jq -r '.nameWithOwner')
DEFAULT_BRANCH=$(echo $REPO_INFO | jq -r '.defaultBranchRef.name')

# Step 2: Use detected values
gh pr create --base $DEFAULT_BRANCH ...
gh api repos/$REPO/pulls/123/comments
```

### For Label Operations

```bash
# Step 1: Fetch available labels
gh label list

# Step 2: Use AskUserQuestion tool to let user select
# Step 3: Apply selected labels
gh issue create --label "selected-label"
```

## Best Practices

<good-example>
1. **Never hardcode repository names** - use `gh repo view --json nameWithOwner`
2. **Never hardcode branch names** - use `gh repo view --json defaultBranchRef`
3. **Never hardcode labels** - use `gh label list` and let me select
4. **Detect conventions** - analyze existing branches/commits before assuming
5. **Provide sensible defaults** - if detection fails, use common conventions
</good-example>

<bad-example>
- Hardcoding `main` or `master` as the default branch
- Assuming labels like `bug`, `enhancement` exist without checking
- Using fixed repository owner/name strings
</bad-example>

## Integration Points

All gh-workflow commands should:
1. Reference this skill for configuration patterns
2. Use dynamic detection instead of hardcoded values
3. Fall back to sensible defaults if detection fails
4. Use the **AskUserQuestion tool** when user input is needed

## Grep Patterns

To find configuration usage in the codebase:

```bash
# Find hardcoded branch references
grep -r "main\|master" --include="*.md" plugins/

# Find label references
grep -r "label" --include="*.md" plugins/

# Find gh repo commands
grep -r "gh repo\|gh issue\|gh pr" --include="*.md" plugins/
```

## Error Handling

If `gh` commands fail, check:
- Is the user authenticated? `gh auth status`
- Is this a git repository? `git rev-parse --git-dir`
- Does the repository have a GitHub remote? `git remote -v`

Report clear, actionable error messages.
