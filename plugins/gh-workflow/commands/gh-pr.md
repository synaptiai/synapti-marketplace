---
description: Use when ready to create a PR to run full code review, convention checks, and get reviewer suggestions before PR creation
argument-hint: [title]
allowed-tools: Bash, Read, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Create Pull Request

Decoupled PR creation workflow with full code review, convention checks, quality gates, and intelligent reviewer suggestions.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive decisions, **TaskCreate/TaskUpdate** for tracking review progress, and the **suggest-users skill** for reviewer recommendations.

## Contract

**GOAL**: Create an open PR on GitHub that passes all quality checks with an assigned reviewer. Testable: `gh pr view --json number,state` returns a valid open PR number.

**CONSTRAINTS**:
- Never create PR from the default branch
- Never force push to default branch
- Never skip the code review phase (Phase 3 is mandatory)
- All P1 findings must be resolved OR explicitly acknowledged by user
- Read CLAUDE.md before starting and follow all project conventions

**FORMAT**: PR body follows the template in `templates/pr-template.md`. All findings displayed before asking user for decisions.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- PR created without running code review (Phase 3 skipped)
- PR body is empty or uses generic placeholder text
- PR description does not match actual changes (misleading)
- PR created without user approval via AskUserQuestion
- PR targets wrong branch
- Uncommitted changes silently ignored

## Overview

This command creates a pull request after running comprehensive quality checks:
1. Pre-flight verification
2. Full code review (mandatory)
3. Convention compliance check
4. Reviewer suggestions based on file expertise
5. PR creation with user approval

## Phase 1: Pre-flight Verification

**Execute in parallel** (single message, multiple tool calls):

1. **Verify current branch**:
   ```bash
   BRANCH=$(git branch --show-current)
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')

   # Ensure not on default branch
   if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
     echo "ERROR: Cannot create PR from default branch"
   fi
   ```

2. **Check for uncommitted changes**:
   ```bash
   git status --porcelain
   ```

3. **Verify commits ahead of remote**:
   ```bash
   # Check if branch tracks remote
   git rev-parse --abbrev-ref @{upstream} 2>/dev/null

   # Count commits ahead
   git rev-list --count @{upstream}..HEAD 2>/dev/null || git rev-list --count $DEFAULT_BRANCH..HEAD
   ```

4. **Get repository info**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   ```

### Pre-flight Decision

If uncommitted changes detected, use **AskUserQuestion tool**:
- **Option 1**: "Run /gh-commit first" (Recommended) - Commit changes before PR
- **Option 2**: "Stash changes and continue" - Temporary save
- **Option 3**: "Discard changes and continue" - Lose uncommitted work
- **Option 4**: "Cancel PR creation" - Return to work

If no commits ahead:
```markdown
**No commits to create PR from.**

The branch `{branch}` has no commits ahead of `{default_branch}`.
Make changes and commit before creating a PR.
```

## Phase 2: Issue Detection

1. **Extract issue number from branch name**:
   ```bash
   # Pattern: feature/issue-{N}-desc, fix/issue-{N}-desc
   ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
   ```

2. **Fetch issue details** (if found):
   ```bash
   gh issue view $ISSUE_NUM --json title,body,labels
   ```

3. **Extract acceptance criteria** from issue body for verification

4. **If no issue linked**, note for PR body:
   ```markdown
   **Note**: No linked issue detected from branch name `{branch}`.
   Consider linking an issue in the PR body.
   ```

## Phase 3: Full Code Review (Mandatory)

This phase performs a comprehensive code review before PR creation.

### Step 3.1: Get the Diff

```bash
# Full diff against default branch
git diff $DEFAULT_BRANCH..HEAD

# List of changed files
git diff --name-only $DEFAULT_BRANCH..HEAD
```

### Step 3.2: Create Review Tasks

**Execute in parallel** (multiple TaskCreate calls):

```
TaskCreate:
  subject: "Review: Code Quality & Logic"
  description: "Analyze logic correctness, edge cases, error handling"
  activeForm: "Reviewing code quality"

TaskCreate:
  subject: "Review: Security Scan"
  description: "Check for hardcoded secrets, injection risks, data exposure"
  activeForm: "Security scanning"

TaskCreate:
  subject: "Review: TODO/Debug Check"
  description: "Find TODO comments, debug statements, console.log"
  activeForm: "Checking for debug code"

TaskCreate:
  subject: "Review: Test Coverage"
  description: "Verify tests exist for new functionality"
  activeForm: "Checking test coverage"
```

### Step 3.3: Execute Code Review

For each review task, mark in_progress, execute analysis, record findings, mark completed.

**Code Quality & Logic**:
- Logic correctness for all code paths
- Edge case handling (nulls, empty, boundaries)
- Error handling and recovery
- Resource management
- Unnecessary/duplicate code

**Security Scan**:
- No hardcoded secrets or credentials
- Input validation present
- No SQL/command injection risks
- Sensitive data not logged

**TODO/Debug Check**:
```bash
# Find TODO/FIXME comments in changed files
git diff --name-only $DEFAULT_BRANCH..HEAD | xargs grep -n "TODO\|FIXME\|XXX\|HACK" 2>/dev/null

# Find debug statements
git diff --name-only $DEFAULT_BRANCH..HEAD | xargs grep -n "console\.log\|print(\|debugger" 2>/dev/null
```

**Test Coverage**:
- New functionality has tests
- Edge cases tested
- Test assertions are meaningful

### Step 3.4: Run Quality Commands

Detect and run project quality commands:

```bash
# Check CLAUDE.md for commands
grep -E "(lint|test|check)" .claude/CLAUDE.md 2>/dev/null

# Or detect from tech stack
[ -f "pyproject.toml" ] && ruff check . 2>/dev/null
[ -f "package.json" ] && npm run lint 2>/dev/null
[ -f "go.mod" ] && go vet ./... 2>/dev/null
```

### Step 3.5: Synthesize Findings

```markdown
## Code Review Findings

### P1 - Critical (Blocks PR)
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|
| 1 | Security | src/api.ts:42 | Hardcoded API key | Use environment variable |

### P2 - Important (Should Fix)
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|
| 1 | Logic | src/util.ts:15 | Missing null check | Add guard clause |

### P3 - Suggestions
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|
| 1 | Style | src/index.ts:8 | Console.log present | Remove before merge |

### Quality Command Results
| Command | Status | Details |
|---------|--------|---------|
| ruff check | Pass/Fail | {details} |
| pytest | Pass/Fail | {details} |

### TODO/Debug Items
| File | Line | Content |
|------|------|---------|
| src/api.ts | 55 | // TODO: Add rate limiting |
```

### Step 3.6: P1 Issue Decision

If P1 (critical) issues found, use **AskUserQuestion tool**:
- **Option 1**: "Fix issues now" (Recommended) - Address P1 before PR
- **Option 2**: "Proceed anyway" - Create PR with known issues
- **Option 3**: "Cancel PR creation" - Return to fix issues

**Note**: If user chooses "Fix issues now", create tasks for each P1 and return to implementation.

## Phase 4: Convention Check

### Step 4.1: Commit Message Analysis

```bash
# Get all commit messages on this branch
git log $DEFAULT_BRANCH..HEAD --format="%s"
```

Check for conventional commit format:
- Starts with valid prefix (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
- Subject is present and descriptive
- No overly long subjects (>72 chars)

### Step 4.2: Branch Naming Check

Verify branch follows convention:
- `feature/issue-{N}-{desc}`
- `fix/issue-{N}-{desc}`
- `docs/issue-{N}-{desc}`

### Step 4.3: Convention Report

```markdown
## Convention Compliance

### Commit Messages
| Commit | Message | Status |
|--------|---------|--------|
| abc123 | feat: add validation | OK |
| def456 | fixed bug | Missing prefix |

### Branch Naming
- Branch: `{branch}`
- Pattern: {matches/does not match} expected format
- Linked Issue: #{N} or "none detected"

### Issues Found
- {list of convention issues}
```

If convention issues found, warn but don't block:
```markdown
**Convention Warning**: {N} issues found. Consider fixing before merge.
```

## Phase 5: Reviewer Suggestion

Invoke the **suggest-users skill** to recommend reviewers.

### Step 5.1: Gather Signals

**Execute in parallel**:

```bash
# Get changed files
CHANGED_FILES=$(git diff --name-only $DEFAULT_BRANCH..HEAD)

# Check CODEOWNERS
gh api repos/$REPO/contents/.github/CODEOWNERS --jq '.content' 2>/dev/null | base64 -d

# Get collaborators
gh api repos/$REPO/collaborators --jq '.[] | select(.permissions.push) | .login'

# Recent file contributors
git log --format='%an' --since="30 days ago" -- $CHANGED_FILES | sort | uniq -c | sort -rn

# Current review load
gh pr list --state open --json reviews --jq '[.[].reviews[].author.login] | group_by(.) | map({user: .[0], count: length})'
```

### Step 5.2: Calculate Scores

Apply suggest-users scoring algorithm:
- CODEOWNERS match: +50
- File commits: +10 per file
- Recent reviews: +5 per review (max 25)
- Open reviews: -3 per open review

### Step 5.3: Present Suggestions

```markdown
## Suggested Reviewers

Based on file ownership, expertise, and workload:

| Rank | User | Score | Reasons |
|------|------|-------|---------|
| 1 | @alice | 75 | CODEOWNERS match, 2 file commits |
| 2 | @bob | 45 | 4 recent reviews, low workload |
| 3 | @carol | 30 | 3 commits to changed files |
```

Use **AskUserQuestion tool**:
- **Option 1**: "@alice (Recommended)" - Top ranked
- **Option 2**: "@bob" - Active reviewer
- **Option 3**: "@carol" - File expertise
- **Option 4**: "No reviewer" - Skip reviewer assignment

## Phase 6: Push

```bash
# Push with upstream tracking
git push -u origin $BRANCH
```

If push fails due to remote changes:
```bash
# Fetch and check for conflicts
git fetch origin $BRANCH
git log HEAD..origin/$BRANCH --oneline
```

Use **AskUserQuestion tool** if conflicts:
- **Option 1**: "Pull and rebase" - Rebase local on remote
- **Option 2**: "Force push" - Override remote (caution)
- **Option 3**: "Cancel" - Resolve manually

## Phase 7: Label Selection

```bash
# Fetch available labels
gh label list
```

Suggest labels based on:
- Issue labels (if linked)
- Change type (feature, fix, docs)
- File paths (e.g., plugin-related changes)

Use **AskUserQuestion tool**:
- **Option 1**: "Apply suggested: {label1}, {label2}" (Recommended)
- **Option 2**: "Choose different labels"
- **Option 3**: "No labels"

## Phase 8: PR Preview & Creation

### Step 8.1: Generate PR Content

**Title Format**:
```
{type}: {description} (fixes #{issue})
```
or
```
{type}: {description} (#{issue})
```
(Use `fixes` for auto-close, omit for linked-only)

**Body Template**:
```markdown
## Closes Issue

closes #{issue}

## Summary

{2-3 sentence description of changes}

## Changes

- {Change 1}
- {Change 2}
- {Change 3}

## Review Summary

**Code Review**: {Passed / N issues found}
**Convention Check**: {Passed / N warnings}
**Quality Commands**: {Passed / Failed}

### Findings Addressed
{If any P1/P2 issues were fixed, list them}

## Verification

- [x] Code review completed
- [x] Convention check completed
- [x] Quality commands passed
- [x] All acceptance criteria met

## Files Changed

{List of changed files with brief descriptions}

## Checklist

- [x] Commits follow conventional format
- [x] No uncommitted changes
- [x] Tests pass (if applicable)
```

### Step 8.2: Preview and Approval

**Display full preview FIRST**:

```markdown
## PR Preview

**Title**: feat: add user validation (fixes #42)
**Target**: feature/issue-42-validation → main
**Reviewer**: @alice
**Labels**: enhancement

---
{Complete PR body from template}
---

**Files**:
- src/api/users.ts (modified)
- src/api/users.test.ts (created)
- docs/api.md (modified)
```

**Then** use **AskUserQuestion tool**:
- **Option 1**: "Create this PR" (Recommended)
- **Option 2**: "Edit title"
- **Option 3**: "Edit body"
- **Option 4**: "Cancel PR creation"

### Step 8.3: Create PR

```bash
gh pr create \
  --base $DEFAULT_BRANCH \
  --title "{title}" \
  --body "{body}" \
  --assignee @me \
  --reviewer "{selected_reviewer}" \
  --label "{labels}"
```

## Phase 9: Verification

```bash
# Verify PR was created
gh pr view --json number,title,url,state

# Get PR number for reference
PR_NUM=$(gh pr view --json number --jq '.number')
```

```markdown
## PR Created Successfully

**PR**: #{PR_NUM}
**URL**: {pr_url}
**Status**: Open

### Summary
- **Title**: {title}
- **Target**: {branch} → {default_branch}
- **Reviewer**: @{reviewer}
- **Labels**: {labels}

### Next Steps
1. Wait for reviewer feedback
2. Address comments with `/gh-address {PR_NUM}`
3. Merge with `/gh-merge {PR_NUM}` when approved
```

## Arguments

- `$ARGUMENTS`: Optional PR title
  - If provided, uses as title (skips generation)
  - Example: `/gh-pr feat: add new validation`

## Rules

- **Full review is mandatory** - Cannot skip Phase 3
- **Always preview before creating** - User must see full PR content
- **Show findings first** - Display review results before asking decisions
- **Dynamic configuration** - Never hardcode branches, labels, or users
- **Respect user choices** - Don't auto-proceed without approval
- **No force push to default** - Block force push to main/master

## Error Handling

### No Commits

```markdown
**Cannot create PR**: No commits ahead of {default_branch}.

Make changes and commit first, then run `/gh-pr`.
```

### On Default Branch

```markdown
**Cannot create PR from {default_branch}**.

Create a feature branch first:
1. `git checkout -b feature/issue-N-description`
2. Make changes
3. Commit
4. Run `/gh-pr`
```

### PR Already Exists

```bash
# Check for existing PR
gh pr list --head $BRANCH --json number,url
```

If PR exists:
```markdown
**PR already exists for branch {branch}**:
- PR #{number}: {url}

To update: push new commits and they'll appear in the existing PR.
To create new: close existing PR first.
```

## Integration

This command works with the gh-workflow:

- **After `/gh-start`**: Called when user chooses "Create PR now"
- **After `/gh-commit`**: Create PR from committed changes
- **Before `/gh-review`**: Reviewer uses this to review

**Typical Flow**:
```
/gh-start 42      # Branch, implement
/gh-commit        # Commit changes
/gh-pr            # Create PR with full review
```
