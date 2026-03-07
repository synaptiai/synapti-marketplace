---
description: "[flow] Create a pull request with full code review, quality gates, comprehension report, and reviewer suggestions. Runs parallel agent review before PR creation."
argument-hint: [title]
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Create Pull Request

Full PR creation workflow with multi-faceted review, quality gates, and structured PR body. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `pr-lifecycle` — pre-flight, PR body, reviewer suggestion
- `code-review-methodology` — 5-facet review synthesis
- `capability-discovery` — detect quality commands and agents

## Phase 1: EXPLORE

**Parallel operations:**

```bash
# 1. Pre-flight checks
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
[ "$BRANCH" = "$DEFAULT_BRANCH" ] && echo "ERROR: Cannot create PR from default branch" && exit 1
echo "BRANCH=$BRANCH DEFAULT=$DEFAULT_BRANCH"

# 2. Commits and changes
git rev-list --count "$DEFAULT_BRANCH"..HEAD
git status --porcelain
git diff --stat "$DEFAULT_BRANCH"...HEAD

# 3. Issue context
ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
[ -n "$ISSUE_NUM" ] && gh issue view $ISSUE_NUM --json title,body,labels

# 4. Existing PR check
gh pr list --head "$BRANCH" --state open --json number,url

# 5. Decision journal
JOURNAL_DIR=".decisions"
[ -n "$ISSUE_NUM" ] && [ -f "$JOURNAL_DIR/issue-$ISSUE_NUM.md" ] && cat "$JOURNAL_DIR/issue-$ISSUE_NUM.md"
```

**Skill invocation:** `Skill(capability-discovery)` — detect quality commands.

If uncommitted changes exist, offer to run `/flow:commit` first.
If PR already exists, offer to update instead.

## Phase 2: PLAN

Create review tasks:

```
TaskCreate("Code quality and logic review", "Review diff for logic errors, edge cases, error handling")
TaskCreate("Security scan", "Check for OWASP top 10, secrets, auth issues")
TaskCreate("Convention check", "Validate commits, branch naming, patterns")
TaskCreate("Quality commands", "Run lint, test, typecheck")
TaskCreate("Requirements compliance", "Map acceptance criteria to implementation")
```

Get the diff for review:

```bash
git diff "$DEFAULT_BRANCH"...HEAD
```

## Phase 3: CODE (Review Execution)

**Parallel Agent dispatch** — 3 agents in a single message:

```
Agent(code-reviewer):
  "Review the branch diff against $DEFAULT_BRANCH for code quality,
   logic correctness, edge cases, and security. Return P1/P2/P3 findings
   with file:line citations."

Agent(convention-checker):
  "Validate commit messages, branch naming, and code conventions
   against project standards. Return findings."

Agent(test-runner):
  "Discover and run quality commands (lint, test, typecheck).
   Return structured results table."
```

**Main thread** (while agents run in parallel if using background agents, or after if foreground):
- Requirements compliance check: map acceptance criteria → implementation evidence
- TaskUpdate for requirements task

After agents return, TaskUpdate each review task with findings.

## Phase 4: VERIFY

1. **Synthesize findings**: Deduplicate by file:line, prioritize P1 > P2 > P3
2. **TaskList**: Confirm all review tasks complete
3. **Display findings** (finding-first pattern):
   - P1 findings → must fix before PR
   - P2 findings → should fix, ask user
   - P3 findings → note in PR body
4. **If P1 findings**: Fix them, re-run review
5. **Generate PR body** from template + findings + journal + comprehension report
6. **Push** (Tier 2: journal-and-proceed):
   ```bash
   git push -u origin $BRANCH
   ```
7. **Create PR** (Tier 2):
   ```bash
   gh pr create --title "$TITLE" --body "$BODY"
   ```
8. **Suggest reviewers** using pr-lifecycle skill algorithm
9. **Verify**: `gh pr view --json number,url`

Display PR URL and next steps.
