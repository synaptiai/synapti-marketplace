---
description: Start work on a GitHub issue - branch, implement, and prepare for PR
argument-hint: <issue-number>
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Skill
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Start Work on Issue #$ARGUMENTS

Complete workflow from issue assignment through implementation with task-based tracking. Ends with option to create PR via `/gh-pr` or continue working.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive dialogues at key decision points, and **TaskCreate/TaskUpdate** tools for tracking implementation progress.

## Phase 1: Setup

**Execute these in parallel** (single message, multiple tool calls):

1. **Fetch the issue**:
   ```bash
   gh issue view $ARGUMENTS
   ```

2. **Fetch all issue comments for full context**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '.[] | "---\n**@\(.user.login)** on \(.created_at):\n\(.body)\n"'
   ```

3. **Fetch issue timeline for related context**:
   ```bash
   gh api repos/$REPO/issues/$ARGUMENTS/timeline --jq '.[] | select(.event == "cross-referenced" or .event == "referenced") | "\(.event): \(.source.issue.title // .commit_id)"'
   ```

4. **Check for linked issues/PRs**:
   ```bash
   gh api repos/$REPO/issues/$ARGUMENTS --jq '.body' | grep -oE '#[0-9]+'
   ```

5. **Review all comments and linked issues** before confirming setup with user

6. **Assign the issue to yourself**:
   ```bash
   gh issue edit $ARGUMENTS --add-assignee @me
   ```

7. **Detect default branch and ensure on latest**:
   ```bash
   # Get default branch dynamically
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
   ```

8. **Determine branch type** - If ambiguous, **use the AskUserQuestion tool**:

   When issue type is unclear (could be feature or fix), ask:
   - **Option 1**: "feature/issue-{number}-{desc}" - New functionality
   - **Option 2**: "fix/issue-{number}-{desc}" - Bug fix
   - **Option 3**: "docs/issue-{number}-{desc}" - Documentation only

   ```bash
   git checkout -b {branch-name}
   ```

9. **Confirm setup** with user before beginning implementation

## Phase 1.5: Capability Discovery

Before implementation, discover available project capabilities:

**Execute these in parallel**:

1. **Check for custom skills** that could help:
   ```bash
   ls .claude/skills/*/SKILL.md plugins/*/skills/*/SKILL.md 2>/dev/null
   ```

2. **Check for custom agents** available:
   ```bash
   ls .claude/agents/*.md plugins/*/agents/*.md 2>/dev/null
   ```

3. **Parse CLAUDE.md** for quality commands:
   ```bash
   grep -E "(lint|test|check|format|typecheck):" .claude/CLAUDE.md 2>/dev/null
   grep -E "(ruff|pytest|npm run|go vet|cargo)" .claude/CLAUDE.md 2>/dev/null
   ```

4. **Detect tech stack**:
   ```bash
   ls pyproject.toml package.json tsconfig.json go.mod Cargo.toml 2>/dev/null
   ```

Note available capabilities for use in quality checks phase.

## Phase 2: Task-Based Implementation

### Step 2.1: Create Task Breakdown

Parse issue acceptance criteria and create tasks using **TaskCreate**:

For each acceptance criterion found in the issue:
```
TaskCreate:
  subject: "[Criterion summary - imperative form]"
  description: "[Full criterion text from issue]\n\nImplementation notes: [any technical context]"
  activeForm: "Implementing [criterion]"
```

Example breakdown:
- Issue says "Users can filter by date" → Task: "Add date filtering to search endpoint"
- Issue says "Validation errors show helpful messages" → Task: "Implement validation error formatting"

### Step 2.2: Work Through Tasks Systematically

For each task from TaskList:

1. **Mark task in progress**:
   ```
   TaskUpdate: taskId={id}, status=in_progress
   ```

2. **Implement the requirement**:
   - Reference similar existing code patterns
   - Follow project guidelines (CLAUDE.md)
   - Write tests alongside implementation (if applicable)

3. **Incremental commit** (when logical unit complete):
   - Commit after each task or meaningful progress
   - Use conventional commit format
   - Reference task in commit if helpful

4. **Mark task complete**:
   ```
   TaskUpdate: taskId={id}, status=completed
   ```

5. **Check progress**:
   ```
   TaskList
   ```

### Step 2.3: Progress Tracking

After each task completion, show progress:
```
## Implementation Progress
| Task | Status |
|------|--------|
| [task 1] | Completed |
| [task 2] | In Progress |
| [task 3] | Pending |

Progress: 1/3 tasks completed
```

## Phase 3: Quality Checks (Dynamic Discovery)

### Step 3.1: Discover Quality Tools

In priority order:

1. **Check CLAUDE.md** for explicit commands:
   ```bash
   grep -E "(lint|test|check)" .claude/CLAUDE.md 2>/dev/null
   ```

2. **Fallback to tech stack detection**:
   | Indicator | Commands |
   |-----------|----------|
   | pyproject.toml | `ruff check .`, `pytest` |
   | package.json | `npm run lint`, `npm test` |
   | tsconfig.json | `tsc --noEmit` |
   | go.mod | `go vet ./...`, `go test ./...` |
   | Cargo.toml | `cargo clippy`, `cargo test` |

### Step 3.2: Execute Quality Checks

**Run in parallel** (all quality tools at once):

```bash
# Python
ruff check . 2>/dev/null
pytest 2>/dev/null

# TypeScript/JavaScript
npm run lint 2>/dev/null
npm test 2>/dev/null

# Go
go vet ./... 2>/dev/null
go test ./... 2>/dev/null
```

### Step 3.3: Handle Failures

If checks fail, create tasks for fixes:
```
TaskCreate:
  subject: "Fix: [failure type]"
  description: "[Error message and location]"
  activeForm: "Fixing [error]"
```

Work through fix tasks, then re-run checks.

### Step 3.4: Verify All Tasks Complete

```
TaskList
```

If incomplete tasks remain, **use AskUserQuestion tool**:
- "Complete remaining tasks before PR"
- "Create PR noting partial implementation"
- "Mark remaining as out-of-scope"

## Phase 3.5: Code Review (Self-Review)

Before creating PR, perform systematic code review on the diff:

```bash
# Get the diff to review
git diff origin/$DEFAULT_BRANCH..HEAD
```

**Review Checklist** (only analyze new code in diff):

1. **Unnecessary/Duplicate Code**
   - Identify redundant logic
   - Check for copy-paste duplication
   - Look for dead code paths

2. **Type Safety & Language Gotchas**
   - TypeScript: proper typing, no unnecessary `any`
   - Python: type hints, pyright compliance
   - Watch for common footguns

3. **Code Bloat**
   - Remove unnecessary comments
   - Delete debug code/console.logs
   - Remove commented-out code

4. **Complexity**
   - Simplify overly complicated logic
   - Extract complex conditions into named functions
   - Reduce nesting depth

5. **Naming**
   - Variable names are clear and descriptive
   - Function names describe what they do
   - Consistent naming patterns

6. **Pattern Consistency**
   - Use established project patterns
   - Don't introduce conflicting approaches
   - Check CLAUDE.md for conventions

7. **NO PLACEHOLDERS**
   - No mocks, demo data, placeholder code, stubs in src
   - All implementations must be production-ready

**Output Format**:
```
## Code Review Findings

### Issues Found
| # | Type | Location | Issue | Fix |
|---|------|----------|-------|-----|
| 1 | Duplicate | file:line | [desc] | [fix] |

### Fixes Applied
- [x] Fixed: [description]
```

After identifying issues:
1. Create tasks for each fix: `TaskCreate: subject="Fix: [issue]"`
2. Implement fixes
3. Re-run linters and type checkers
4. Verify all issues resolved

## Phase 3.6: Test Review (Self-Review)

Review tests in the current diff:

**Coverage Check**:
- Missing tests for new behavior/branches?
- Edge cases, boundary values, error paths?
- Negative cases, invalid inputs, failure modes?

**Assertion Quality**:
- Checking behavior, not implementation details?
- Weak assertions (too generic, no failure message)?
- Over-asserting unimportant details?

**Test Design**:
- Descriptive names (given/when/then or AAA)?
- Clear intent, minimal mental overhead?
- Magic values → constants/factories/helpers?
- Duplicated setup → fixtures/parametrized tests?

**Output Format**:
```
## Test Review Findings

### Missing Coverage
| Behavior | Suggested Test |
|----------|----------------|
| [behavior] | [test name and approach] |

### Issues Found
| # | Type | Test | Issue | Fix |
|---|------|------|-------|-----|
| 1 | Weak assertion | test_foo | [desc] | [fix] |

### Fixes Applied
- [x] Added: test_edge_case_X
- [x] Fixed: improved assertions in test_Y
```

After identifying issues:
1. Create tasks for each improvement
2. Implement new/improved tests
3. Run test suite
4. Verify all tests pass

## Phase 3.7: Pre-PR Gate (Mandatory)

Before proceeding to PR creation, verify ALL of the following:

**Completeness Check**:
```
TaskList
```
- [ ] All tasks status=completed
- [ ] No pending or in_progress tasks
- [ ] If incomplete tasks exist → resolve or explicitly scope out

**Quality Gate**:
- [ ] Linter passes (zero errors)
- [ ] Type checker passes (zero errors)
- [ ] All tests pass
- [ ] Code review issues addressed
- [ ] Test review issues addressed

**Production Readiness**:
- [ ] No mocks/stubs/placeholders in src code
- [ ] No TODO comments for shipped code
- [ ] No debug/console output left
- [ ] All implementations are complete

**If ANY gate fails**:
1. Create tasks for each failure
2. Address all issues
3. Re-run this gate
4. Only proceed when all checks pass

## Phase 4: Ready for PR

**All quality gates passed.** Implementation is complete and ready for pull request.

### Step 4.1: Final Commit Check

Ensure all changes are committed:

```bash
# Check for uncommitted changes
git status --porcelain

# If uncommitted changes exist, prompt for action
```

If uncommitted changes exist, **use AskUserQuestion tool**:
- **Option 1**: "Run /gh-commit first" (Recommended) - Commit remaining changes
- **Option 2**: "Continue without committing" - Changes will not be in PR

### Step 4.2: Display Summary

```markdown
## Implementation Complete

**Branch**: {branch-name}
**Issue**: #{issue-number} - {issue-title}
**Commits**: {N} commits ahead of {default-branch}

### Tasks Completed
| Task | Status |
|------|--------|
| {task 1} | Completed |
| {task 2} | Completed |
| {task 3} | Completed |

**Progress**: {M}/{M} tasks completed

### Quality Gates
- [x] All tasks completed
- [x] Code review (self-review) passed
- [x] Test review passed
- [x] Linter passed
- [x] Type checker passed
- [x] All tests pass

### Files Changed
- {file1} (created)
- {file2} (modified)
- {file3} (modified)
```

### Step 4.3: Next Step Selection

**Use the AskUserQuestion tool** to determine next action:

- **Option 1**: "Create PR now" (Recommended) - Invoke `/gh-pr` workflow for full PR creation with reviewer suggestions
- **Option 2**: "Defer to /gh-pr later" - End gh-start, create PR manually with `/gh-pr`
- **Option 3**: "Make more changes first" - Continue working, commit with `/gh-commit` when ready

### If Option 1 Selected (Create PR Now)

Inform the user:
```markdown
**Creating PR...**

Running `/gh-pr` workflow which includes:
1. Full code review (with P1/P2/P3 findings)
2. Convention compliance check
3. Reviewer suggestions based on file expertise
4. PR preview and creation

Please follow the prompts in the `/gh-pr` workflow.
```

Then invoke the gh-pr workflow (the user should run `/gh-pr`).

### If Option 2 Selected (Defer)

```markdown
## Implementation Ready

Your changes are committed and ready for PR creation.

**When you're ready**, run:
```
/gh-pr
```

This will:
- Run full code review
- Check conventions
- Suggest reviewers
- Create PR with your approval
```

### If Option 3 Selected (Continue Working)

```markdown
## Continue Working

Make additional changes, then:
1. Run `/gh-commit` to commit changes
2. Run `/gh-pr` when ready to create PR

**Current Status**:
- Branch: {branch}
- Commits: {N} ahead of {default-branch}
- Tasks: {M}/{M} completed
```

## Arguments

- `$ARGUMENTS`: Issue number (required)
- To override base branch: mention it in your message (e.g., "start 42, target release branch")

## Rules

- **Always detect default branch dynamically** - never assume `main` or `master`
- Commits must follow conventional format
- **ALWAYS display findings BEFORE asking questions** - users must see status and summaries before being asked for decisions
- **Use the AskUserQuestion tool** at decision points:
  - Branch type selection (when ambiguous)
  - Incomplete tasks handling
  - Next step selection (PR now / defer / continue)
- **Use TaskCreate/TaskUpdate** to track implementation progress
- **Run parallel operations** when possible (multiple API calls, file reads)
- **Do not create PR directly** - offer choice to invoke `/gh-pr` or defer

## Success Criteria

Before completing, verify:
- [ ] Issue assigned to user
- [ ] Branch created from latest default branch
- [ ] All acceptance criteria from issue addressed
- [ ] All implementation tasks completed
- [ ] Code review (self-review) passed
- [ ] Test review (self-review) passed
- [ ] Pre-PR gate passed (lint, tests, no placeholders)
- [ ] User presented with next step options
- [ ] User informed of how to proceed (create PR or continue)

## Related Commands

- **`/gh-commit`**: Context-aware commits with change classification
- **`/gh-pr`**: Create PR with full review and reviewer suggestions
- **`/gh-review`**: Review a pull request
- **`/gh-address`**: Address PR review comments
