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

4. **Review decision**:
   - P1 findings → `gh pr review $ARGUMENTS --request-changes --body "$BODY"`
   - P2 only → `gh pr review $ARGUMENTS --comment --body "$BODY"`
   - Clean → `gh pr review $ARGUMENTS --approve --body "$BODY"`

5. **Follow-up issues for out-of-scope findings**:

   If P2 or P3 findings are valid but out-of-scope for this PR (pre-existing issues, architectural concerns, or improvements unrelated to the PR's objective):

   Present the out-of-scope findings and use the AskUserQuestion tool with contextual options: "These findings are valid but out-of-scope for this PR. Which ones should become follow-up issues?"

   For each selected finding, create a GitHub issue using issue-crafting skill knowledge:
   - Title: concise, solution-agnostic description of the finding
   - Body: use the issue body template structure:
     - **Context**: "Discovered during review of PR #$ARGUMENTS ({PR title})"
     - **Current State**: the finding description with file:line citation
     - **Objective**: what should be achieved (outcome, not method)
     - **Acceptance Criteria**: observable behaviors that prove the fix
   - Labels: select from repo labels based on finding category
   - Issue creation is Tier 2 (journal-and-proceed)

   ```bash
   gh issue create --title "{title}" --body "{body}" --label "{labels}"
   ```

   Verify each created issue:
   ```bash
   gh issue view <N> --json number,title,state,labels
   ```

   Include created issue numbers in the review comment body so they are linked to the PR.

6. **Post-review**: Suggest `/flow:address $ARGUMENTS` for the PR author.
