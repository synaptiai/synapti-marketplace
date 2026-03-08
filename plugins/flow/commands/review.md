---
description: "[flow] Review a pull request with multi-faceted analysis. Supports both single-session parallel review and agent team adversarial review."
argument-hint: <pr-number>
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute independent operations simultaneously.
-->

# Review PR #$ARGUMENTS

Multi-faceted code review with parallel analysis. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `code-review-methodology` — 5-facet review, finding synthesis, adversarial protocol

## Phase 1: EXPLORE

**Parallel operations:**

```bash
# 1. PR details
gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName,changedFiles,additions,deletions,labels,author,reviews

# 2. Linked issue
gh pr view $ARGUMENTS --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#'

# 3. Previous reviews (follow-up detection)
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | "\(.state) by \(.author.login)"'

# 4. Checkout PR branch
gh pr checkout $ARGUMENTS

# 5. Diff
gh pr diff $ARGUMENTS --name-only
```

**Agent(Explore)**: "Read the changed files in this PR and understand the context. What modules are affected? What patterns are being followed or changed?"

Check for previous reviews — if this is a follow-up review, focus on changes since last review.

## Phase 2: PLAN

```
TaskCreate("Security review", "Check for OWASP top 10, secrets, injection, auth/authz")
TaskCreate("Code quality review", "Logic correctness, edge cases, error handling")
TaskCreate("Convention review", "Commit format, branch naming, code patterns")
TaskCreate("Test review", "Run quality commands, assess test coverage")
TaskCreate("Requirements review", "Map acceptance criteria to implementation")
TaskCreate("Error handling review", "Check for unhandled exceptions, silent failures, missing edge cases")
```

## Phase 3: CODE (Review Execution)

### Path A: Agent Teams (when `agentTeams: true`)

Invoke `team-coordination` skill. Spawn 3 teammates:

- **security-reviewer**: Independent security analysis
- **code-reviewer**: Quality and logic focus
- **convention-checker**: Convention validation

Adversarial protocol:
1. Each reviews independently
2. Share findings
3. Challenge each other's findings
4. Synthesize consensus + disputed items

### Path B: Single Session (default)

**Parallel Agent dispatch** — 3 agents in single message:

```
Agent(code-reviewer):
  "Review PR #$ARGUMENTS diff for quality, logic, edge cases, security.
   Return P1/P2/P3 findings with file:line."

Agent(convention-checker):
  "Validate commits, branch naming, conventions for PR #$ARGUMENTS."

Agent(test-runner):
  "Run quality commands for PR #$ARGUMENTS branch."

Agent(error-handler-inspector):
  "Inspect changed files in PR #$ARGUMENTS for error handling gaps,
   silent failures, unhandled exceptions. Return P1/P2/P3 findings."
```

**Main thread**: Requirements compliance — map acceptance criteria to implementation.

TaskUpdate each review task as agents complete.

## Phase 4: VERIFY

1. **TaskList**: Confirm all review facets complete
2. **Synthesize findings**: Deduplicate by file:line, prioritize P1/P2/P3
3. **Display findings** (finding-first pattern):

```markdown
## Review Summary for PR #$ARGUMENTS

### Findings: P1: {X}, P2: {Y}, P3: {Z}

### P1 — Critical
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|

### Requirements Adherence
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
```

4. **Determine review mode** — compare PR author vs current user:

   ```bash
   PR_AUTHOR=$(gh pr view $ARGUMENTS --json author --jq '.author.login')
   CURRENT_USER=$(gh api user --jq '.login')
   ```

5. **Self-review (own PR — PR_AUTHOR == CURRENT_USER)**:

   Fix-forward approach (max `fixForwardMaxIterations`, default 2):
   - P1 findings → fix immediately
   - P2 findings → fix immediately
   - P3 findings → fix if contained (<10 lines, same file)
   - After fixes: run targeted re-review of only changed files
   - No follow-up issue creation for fixable items — just fix them
   - If self-review fixed everything, suggest `/flow:pr` to update the PR

6. **External review (someone else's PR — PR_AUTHOR != CURRENT_USER)**:

   - P1 findings → `gh pr review $ARGUMENTS --request-changes --body "$BODY"`
   - P2 in already-touched files → include fix suggestion in review comment
   - P2/P3 in untouched files → follow-up issue workflow:

   Issues in files the PR already modifies are NOT out-of-scope — they should have been fixed under the Boy Scout Rule. Only flag them as informational.

   For findings in untouched files that warrant follow-up:
   Present the out-of-scope findings and use the AskUserQuestion tool with contextual options: "These findings are valid but out-of-scope for this PR. Which ones should become follow-up issues?"

   For each selected finding, create a GitHub issue using issue-crafting skill knowledge:
   - Title: concise, solution-agnostic description of the finding
   - Body: Context, Current State (file:line), Objective, Acceptance Criteria
   - Labels: select from repo labels based on finding category
   - Issue creation is Tier 2 (journal-and-proceed)

   ```bash
   gh issue create --title "{title}" --body "{body}" --label "{labels}"
   ```

   Include created issue numbers in the review comment body.

   - Clean → `gh pr review $ARGUMENTS --approve --body "$BODY"`

   **Note**: Reviewers should recognize `improve:` commits as legitimate Boy Scout cleanup — approve if they pass the proximity test.

7. **Post-review**: If self-review fixed everything, suggest `/flow:pr`. If external review, suggest `/flow:address $ARGUMENTS` for the PR author.
