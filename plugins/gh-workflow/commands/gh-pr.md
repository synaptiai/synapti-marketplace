---
description: Use when ready to create a PR to run full code review, convention checks, and get reviewer suggestions before PR creation
argument-hint: [title]
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.

VARIABLE PERSISTENCE NOTE:
Bash variables (like DEFAULT_BRANCH, REPO, BRANCH) do NOT persist across separate tool calls.
Each Bash invocation is an independent process. Store values mentally from output and
substitute them in subsequent commands. When running parallel Bash calls, each must
define any variables it needs inline.
-->

# Create Pull Request

Decoupled PR creation workflow with full code review, quality gates, and intelligent reviewer suggestions.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive decisions, **TaskCreate/TaskUpdate** for tracking review progress, and the **suggest-users skill** for reviewer recommendations.

## Contract

**GOAL**: Create an open PR on GitHub that passes all quality checks with an assigned reviewer. Testable: `gh pr view --json number,state` returns a valid open PR number.

**CONSTRAINTS**:
- Never create PR from the default branch
- Never force push to default branch
- Never skip the code review phase (Phase 3 is mandatory)
- All P1 findings must be resolved OR explicitly acknowledged by user
- Read CLAUDE.md before starting and follow all project conventions

**FORMAT**: PR body follows `templates/pr-template.md`. All findings displayed before asking user for decisions.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- PR created without running code review (Phase 3 skipped)
- PR body is empty or uses generic placeholder text
- PR description does not match actual changes (misleading)
- PR created without user approval via AskUserQuestion
- PR targets wrong branch
- Uncommitted changes silently ignored

## Phase 1: Project Context & Capability Discovery

### Step 1.1: Read Project Context

Read CLAUDE.md using the **Read tool** (not cat/Bash):
- Try `.claude/CLAUDE.md` first, then `CLAUDE.md`
- Note quality commands, commit conventions, and project patterns
- If neither exists, proceed with auto-detected conventions

### Step 1.2: Capability Discovery

Invoke the **capability-discovery** skill using the **Skill tool** to discover quality commands, agents, and tech stack.

**After skill returns**, extract:
```
LINT_CMD="{detected lint command}"
TEST_CMD="{detected test command}"
TYPECHECK_CMD="{detected typecheck}"
```

Store for use in Phase 3. If a command is N/A, note as "N/A — skip".

**Graceful fallback**: If skill fails, detect from tech stack:

| Indicator | Commands |
|-----------|----------|
| pyproject.toml | `ruff check .`, `pytest` |
| package.json | `npm run lint`, `npm test` |
| tsconfig.json | `tsc --noEmit` |
| go.mod | `go vet ./...`, `go test ./...` |
| Cargo.toml | `cargo clippy`, `cargo test` |

## Phase 2: Pre-flight Verification

**Execute in parallel** (single message, multiple tool calls):

1. **Verify current branch and default branch**:
   ```bash
   BRANCH=$(git branch --show-current)
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
     echo "ERROR: Cannot create PR from default branch. Create a feature branch first."
     exit 1
   fi
   echo "Branch: $BRANCH, Default: $DEFAULT_BRANCH"
   ```

2. **Check for uncommitted changes**:
   ```bash
   git status --porcelain
   ```

3. **Count commits ahead**:
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git rev-list --count $DEFAULT_BRANCH..HEAD
   ```

4. **Check for existing PR on this branch**:
   ```bash
   BRANCH=$(git branch --show-current)
   gh pr list --head $BRANCH --json number,url,state
   ```

5. **Get repository info**:
   ```bash
   gh repo view --json nameWithOwner --jq '.nameWithOwner'
   ```

### Step 2.1: Pre-flight Decisions

**If on default branch** → stop:
> Cannot create PR from the default branch. Create a feature branch, make changes, commit, then run `/gh-pr`.

**If PR already exists** for this branch:
> PR already exists for branch `{branch}`: PR #{number} ({url}). Push new commits to update the existing PR, or close it first to create a new one.

**If no commits ahead** → stop:
> No commits to create PR from. Branch `{branch}` has no commits ahead of `{default_branch}`.

**If uncommitted changes** detected, use **AskUserQuestion tool**:
- **Option 1**: "Run /gh-commit first" (Recommended) - Commit changes before PR
- **Option 2**: "Stash changes and continue" - Temporary save
- **Option 3**: "Discard changes and continue" - Lose uncommitted work
- **Option 4**: "Cancel PR creation" - Return to work

## Phase 3: Full Code Review (Mandatory)

This is the core of gh-pr — comprehensive quality review before creating the PR.

### Step 3.1: Issue Detection

```bash
# Extract issue number from branch name
BRANCH=$(git branch --show-current)
ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
```

If found, fetch issue details:
```bash
gh issue view $ISSUE_NUM --json title,body,labels
```

Extract acceptance criteria for verification. If no issue linked, note for PR body.

### Step 3.2: Get the Diff

```bash
git diff $DEFAULT_BRANCH..HEAD
git diff --name-only $DEFAULT_BRANCH..HEAD
```

### Step 3.3: Dispatch Review Agents & Comprehension Skills (Preferred)

Launch 3 specialized agents **and** 2 comprehension skills in parallel using the **Agent tool** and **Skill tool** (single message, 5 tool calls):

| Tool | Focus |
|------|-------|
| Agent: code-reviewer | Code quality, logic, security, edge cases, error handling |
| Agent: convention-checker | Commit messages, branch naming, PR format, issue linkage |
| Agent: test-runner | Lint, test, typecheck execution |
| Skill: decision-journal | Summarize mode — condense journal for PR body |
| Skill: comprehension-report | Generate architecture narrative from diff + journal + issue |

```
Execute 5 tool calls in a single message:
- Agent call 1: code-reviewer — "Pre-PR self-review. Analyze diff between $DEFAULT_BRANCH and HEAD. Return P1/P2/P3 findings table with file:line citations."
- Agent call 2: convention-checker — "Pre-PR convention check. Verify commits, branch naming, and change organization. Return findings."
- Agent call 3: test-runner — "Pre-PR quality gate. Run lint/test/typecheck commands. Return results table."
- Skill call 4: decision-journal — "Mode: summarize. Issue number: {ISSUE_NUM}. Sensitivity filter: redact internal entries."
- Skill call 5: comprehension-report — "Generate comprehension report for Issue #{ISSUE_NUM}."
```

Each agent/skill runs independently and returns structured output.

**If no decision journal exists** (standalone gh-pr without gh-start): The comprehension-report skill generates an ad-hoc report from diff and issue alone. The decision-journal skill returns "No decision journal found" — include a notice in the PR body instead of the Decision Summary section.

**Graceful fallback**: If any agent fails, fall back to inline execution for that facet:

**Code review fallback**: Read `references/code-review-checklist.md` (relative to the gh-workflow plugin directory) and follow its instructions for manual review.

**Convention fallback**:
```bash
# Commit messages
git log $DEFAULT_BRANCH..HEAD --format="%s"
# Check for conventional commit format: feat:, fix:, docs:, refactor:, test:, chore:

# Branch naming
git branch --show-current
# Verify: feature/issue-{N}-{desc}, fix/issue-{N}-{desc}, docs/issue-{N}-{desc}
```

**Quality commands fallback**: Run quality commands from Phase 1 directly:
```
- Bash call 1: {lint_cmd}
- Bash call 2: {test_cmd}
- Bash call 3: {typecheck_cmd}
```

### Step 3.4: Create Review Tasks (Tracking)

After agents return (or fallback execution completes), **create tasks in parallel** to track completion of each review facet. These ensure no facet is silently skipped:

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

TaskCreate:
  subject: "Review: Conventions & Standards"
  description: "Commit messages, branch naming, PR format, issue linkage"
  activeForm: "Checking conventions"
```

Mark each task as completed when its corresponding agent results are collected and incorporated into the synthesis. If an agent covered multiple facets (e.g., code-reviewer handles both Code Quality and Security), mark each task individually based on whether findings were reported for that facet.

**Why track these separately**: Agents may focus on high-signal findings and skip lower-priority checks like TODO/debug cleanup or test coverage gaps. Individual tasks ensure each facet gets explicit attention — either confirmed clean or with findings recorded.

### Step 3.5: Quality Verification Loop

If any quality command (from agent or fallback) failed, apply bounded verification:

1. Parse error output to identify root cause
2. Fix the issue inline immediately (Edit tool, not TaskCreate)
3. Commit the fix: `git commit -m "fix: [what was fixed]"`
4. Re-run ALL quality commands in parallel
5. **Max 3 iterations**. After 3 failures → include failures as P1 findings in Step 3.8

### Step 3.6: Runtime Verification (if available)

Invoke the **runtime-verification** skill using the **Skill tool**.

Include results in findings synthesis:
- Passed runtime tests = positive signals
- Failed runtime tests = P2 findings

**Graceful fallback**: If skill fails, check inline:
```bash
ls verify.sh scripts/verify* playwright.config.* cypress.config.* 2>/dev/null
cat package.json 2>/dev/null | grep -E '"(dev|start|serve|e2e|test:e2e)"'
```
If capabilities found, run them. If nothing found, skip with note "No runtime verification configured."

### Step 3.7: Synthesize Findings

Before synthesizing, verify all review tasks from Step 3.4 are marked completed:
```
TaskList
```
Any incomplete tasks indicate a review facet that was not covered — address it before proceeding.

Merge all findings from agents (or fallbacks). Deduplicate by file:line — keep the higher priority version. Add "Flagged By" when multiple sources found the same issue.

```markdown
## Code Review Findings

### P1 - Critical (Blocks PR)
| # | Category | Location | Issue | Fix | Flagged By |
|---|----------|----------|-------|-----|------------|

### P2 - Important (Should Fix)
| # | Category | Location | Issue | Fix | Flagged By |
|---|----------|----------|-------|-----|------------|

### P3 - Suggestions
| # | Category | Location | Issue | Fix | Flagged By |
|---|----------|----------|-------|-----|------------|

### Quality Command Results
| Command | Status | Details |
|---------|--------|---------|

### Convention Compliance
| Check | Status | Details |
|-------|--------|---------|
| Commit messages | Pass/Fail | [details] |
| Branch naming | Pass/Fail | [details] |
```

When no issues are found in a category, state "None found."

### Step 3.8: P1 Issue Decision

If P1 (critical) issues found, use **AskUserQuestion tool**:
- **Option 1**: "Fix issues now" (Recommended) - Create tasks for each P1, fix, re-run checks
- **Option 2**: "Proceed anyway" - Create PR with known issues
- **Option 3**: "Cancel PR creation" - Return to fix issues

## Phase 4: Reviewer Suggestion

Invoke the **suggest-users** skill using the **Skill tool** to recommend reviewers based on file ownership, expertise, and workload.

The skill returns ranked suggestions with reasoning. Present them using the **AskUserQuestion tool**:
- **Option 1**: "@{top_ranked} (Recommended)" - Top ranked reviewer
- **Option 2**: "@{second_ranked}" - Second ranked
- **Option 3**: "@{third_ranked}" - Third ranked
- **Option 4**: "No reviewer" - Skip reviewer assignment

**Graceful fallback**: If skill fails, gather signals inline:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
# CODEOWNERS
gh api repos/$REPO/contents/.github/CODEOWNERS --jq '.content' 2>/dev/null | base64 -d
# Collaborators
gh api repos/$REPO/collaborators --jq '.[] | select(.permissions.push) | .login'
# Recent contributors to changed files
git log --format='%an' --since="30 days ago" -- $(git diff --name-only $DEFAULT_BRANCH..HEAD) | sort | uniq -c | sort -rn
```

Present ranked suggestions using the **AskUserQuestion tool**.

## Phase 5: Push

**Note**: Pushing before PR creation is required — GitHub needs the branch on the remote. If the user cancels PR creation later, the branch remains pushed (this is safe and normal).

```bash
git push -u origin $BRANCH
```

If push fails due to remote changes:
```bash
git fetch origin $BRANCH
git log HEAD..origin/$BRANCH --oneline
```

Use **AskUserQuestion tool** if conflicts:
- **Option 1**: "Pull and rebase" - Rebase local on remote
- **Option 2**: "Force push" - Override remote (caution)
- **Option 3**: "Cancel" - Resolve manually

## Phase 6: Label Selection

```bash
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

## Phase 7: PR Preview & Creation

### Step 7.1: Generate PR Content

Read `templates/pr-template.md` (relative to the gh-workflow plugin directory) and populate all sections from the review context:
- **Issue**: Number and acceptance criteria from Phase 3 Step 3.1
- **Summary**: 2–3 sentence description derived from commits and diff
- **Changes**: Key changes list from diff analysis
- **Comprehension Report**: Output from comprehension-report skill (Step 3.3, Skill call 5)
- **Decision Summary**: Output from decision-journal summarize mode (Step 3.3, Skill call 4)
- **Review Summary**: Code review, convention, and quality results from Phase 3
- **Verification**: Checklist of completed checks
- **Files Changed**: From diff with brief descriptions
- **Acceptance Criteria**: Checked off from issue

**Check configuration** — read `.commands.ghPrComprehensionReport` and `.commands.ghPrDecisionSummary` from settings. Default: `true`. If `false`, omit the respective section from the PR body.

**Title Format**:
```
{type}: {description} (fixes #{issue})
```
Use `fixes` for auto-close, or just `(#{issue})` for linked-only. If `$ARGUMENTS` was provided, use it as the title.

### Step 7.2: Preview and Approval

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

### Step 7.3: Create PR

```bash
gh pr create \
  --base $DEFAULT_BRANCH \
  --title "{title}" \
  --body "{body}" \
  --assignee @me \
  --reviewer "{selected_reviewer}" \
  --label "{labels}"
```

## Phase 8: Verification

```bash
gh pr view --json number,title,url,state
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
