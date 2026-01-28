---
description: Review a pull request with checklist and approval workflow
argument-hint: <pr-number>
allowed-tools: Bash, Read, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Review PR #$ARGUMENTS

Review a pull request with multi-faceted analysis, task tracking, and prioritized findings.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to confirm review decisions, and **TaskCreate/TaskUpdate** tools to track review facets.

## Phase 1: Context Gathering

**Execute in parallel** (single message, multiple tool calls):

1. **Save current branch**:
   ```bash
   git branch --show-current
   ```

2. **Get repository info for API calls**:
   ```bash
   # Get owner/repo dynamically - never hardcode
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   ```

3. **Fetch PR details and any existing reviews/comments**:
   ```bash
   gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName,additions,deletions,changedFiles,commits,files,reviews
   gh api repos/$REPO/pulls/$ARGUMENTS/comments
   ```

4. **Fetch PR conversation** (general discussion comments):
   ```bash
   gh api repos/$REPO/issues/$ARGUMENTS/comments
   ```

5. **Extract and fetch linked issue**:
   ```bash
   # Extract issue number from PR body (looks for "closes #X", "fixes #X", etc.)
   gh pr view $ARGUMENTS --json body --jq '.body' | grep -oiE '(closes|fixes|resolves)\s*#[0-9]+' | grep -oE '[0-9]+'
   ```

   If linked issue found:
   ```bash
   # Fetch full issue with acceptance criteria
   gh issue view {linked-issue} --json title,body,comments

   # Fetch all issue comments
   gh api repos/$REPO/issues/{linked-issue}/comments
   ```

6. **Cross-reference checklist**: Create a verification list from issue acceptance criteria to check against implementation

7. **If previous reviews or comments exist**: This is a follow-up review. You MUST:
   - Read through ALL previous review comments
   - Track each piece of feedback that was given
   - Later verify each item was addressed (fixed or explained)
   - Note: You're still doing a FULL review - previous reviewers may have missed things

## Phase 1.5: Review Capability Discovery

Before detailed review, check for available review helpers:

**Execute in parallel**:

1. **Check for custom review agents**:
   ```bash
   ls .claude/agents/*review* plugins/*/agents/*review* 2>/dev/null
   ls .claude/agents/*convention* plugins/*/agents/*convention* 2>/dev/null
   ls .claude/agents/*test* plugins/*/agents/*test* 2>/dev/null
   ```

2. **Check for quality skills**:
   ```bash
   ls .claude/skills/*lint* .claude/skills/*test* plugins/*/skills/ 2>/dev/null
   ```

3. **Parse CLAUDE.md for quality commands**:
   ```bash
   grep -E "(lint|test|check)" .claude/CLAUDE.md 2>/dev/null
   ```

Note available capabilities for use in review facets.

## Phase 2: Checkout and Diff Analysis

1. **Checkout the PR branch** (CRITICAL - never review from wrong branch):
   ```bash
   git fetch origin {headRefName}
   git checkout {headRefName}
   ```

2. **Get the full diff**:
   ```bash
   gh pr diff $ARGUMENTS
   ```

3. **Read all changed files in parallel** - use the Read tool on each modified file to understand the full context

## Phase 3: Multi-Faceted Review

### Step 3.1: Create Review Tasks

**Create all review facet tasks in parallel** (single message, multiple TaskCreate calls):

```
TaskCreate:
  subject: "Review: Code Quality & Logic"
  description: "Analyze logic correctness, edge cases, error handling, null checks"
  activeForm: "Reviewing code quality"

TaskCreate:
  subject: "Review: Conventions & Standards"
  description: "Check commit messages, branch naming, PR format, issue linkage"
  activeForm: "Checking conventions"

TaskCreate:
  subject: "Review: Security & Best Practices"
  description: "Scan for security issues, hardcoded secrets, exposed credentials"
  activeForm: "Security review"

TaskCreate:
  subject: "Review: Tests & Quality Commands"
  description: "Run lint/test commands, verify coverage if applicable"
  activeForm: "Running quality checks"

TaskCreate:
  subject: "Review: Requirements Compliance"
  description: "Verify all acceptance criteria from linked issue are addressed"
  activeForm: "Checking requirements"
```

### Step 3.2: Execute Review Facets

For each review task:

1. **Mark in progress**: `TaskUpdate: taskId={id}, status=in_progress`

2. **Execute the facet analysis**:

   **Code Quality & Logic**:
   - Logic correctness for all code paths
   - Edge case handling (nulls, empty, boundaries)
   - Error handling and recovery
   - Resource management (memory, connections)

   **Conventions & Standards**:
   - Commits follow conventional format (`feat:`, `fix:`, etc.)
   - Branch naming follows pattern (`feature/issue-N-desc`)
   - PR description follows template
   - Issue linked correctly (`closes #X`)

   **Security & Best Practices**:
   - No hardcoded secrets or credentials
   - Input validation present
   - No SQL/command injection risks
   - Sensitive data not logged

   **Tests & Quality Commands**:
   ```bash
   # Run based on detected tech stack
   ruff check . 2>/dev/null || npm run lint 2>/dev/null || go vet ./... 2>/dev/null
   pytest 2>/dev/null || npm test 2>/dev/null || go test ./... 2>/dev/null
   ```

   **Requirements Compliance**:
   - Compare PR changes against issue acceptance criteria
   - Verify each criterion is addressed
   - Note any missing or partially implemented items

3. **Record findings** with priority:
   - **P1 (Critical)**: Blocks merge - security, data corruption, breaking changes
   - **P2 (Important)**: Should fix - logic issues, missing edge cases
   - **P3 (Suggestions)**: Nice to have - style, minor improvements

4. **Mark complete**: `TaskUpdate: taskId={id}, status=completed`

## Phase 4: Finding Synthesis

After all review tasks complete, consolidate findings:

```markdown
## Review Findings Summary

### P1 - Critical (Blocks Merge)
| # | Category | Location | Issue | Suggested Fix |
|---|----------|----------|-------|---------------|
| 1 | Security | file:line | [issue] | [fix] |

### P2 - Important (Should Fix)
| # | Category | Location | Issue | Suggested Fix |
|---|----------|----------|-------|---------------|

### P3 - Suggestions (Nice to Have)
| # | Category | Location | Issue | Suggested Fix |
|---|----------|----------|-------|---------------|

### Requirements Checklist
| Criterion | Status | Notes |
|-----------|--------|-------|
| [From issue] | Met / Partial / Missing | [details] |

### What Looks Good
- [Positive observations]

### Questions
- [Any clarifying questions for the author]
```

**Note**: When no issues are found in a category, explicitly state "None found." rather than omitting the section. This confirms the check was performed.

### Review Decision Logic

Based on findings:
- **0 P1 and 0 P2**: Recommend APPROVE
- **0 P1 but some P2**: Recommend COMMENT with suggestions
- **Any P1**: Recommend REQUEST CHANGES with required fixes

## Phase 5: Review Submission

1. **Present review findings to the user** (REQUIRED before any question):

   **First**, display your complete findings using the synthesis format above.

   **Then, and only then**, invoke the AskUserQuestion tool with:
   - **Option 1**: "Approve - All requirements met"
   - **Option 2**: "Request changes - Critical issues found"
   - **Option 3**: "Comment only - Questions/suggestions, no blockers"
   - **Option 4**: "Need more context before deciding"

   **IMPORTANT**: The user MUST see the detailed findings BEFORE being asked to make a decision.

   If option 4, **use the AskUserQuestion tool** to ask specific clarifying questions.

2. **Preview review and get approval using the AskUserQuestion tool**:

   Show the review comment that will be submitted, then ask:
   - **Option 1**: "Submit this review" (Recommended)
   - **Option 2**: "Edit review content first"
   - **Option 3**: "Cancel review submission"

   **Do not submit review without explicit approval.**

3. **Submit review**:
   ```bash
   # Approve
   gh pr review $ARGUMENTS --approve --body "REVIEW"

   # Request changes
   gh pr review $ARGUMENTS --request-changes --body "REVIEW"

   # Comment only
   gh pr review $ARGUMENTS --comment --body "REVIEW"
   ```

4. **Return to original branch**:
   ```bash
   git checkout {original-branch}
   ```

## Review Checklist (Quick Reference)

### Issue Requirements (if linked)
- [ ] All acceptance criteria from issue are addressed
- [ ] All tasks from issue checklist are completed
- [ ] Implementation matches issue objective

### Conventions
- [ ] Commits follow conventional format (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`)
- [ ] PR description follows template structure
- [ ] `closes #X` links issue correctly (if applicable)
- [ ] PR targets correct default branch

### Code Quality
- [ ] Logic is correct and handles edge cases
- [ ] No obvious bugs or security vulnerabilities
- [ ] Code style consistent with project conventions
- [ ] No hardcoded secrets or credentials
- [ ] Error handling is appropriate

### Documentation
- [ ] README updated if user-facing changes
- [ ] PR description is complete and accurate
- [ ] Any breaking changes clearly documented

### Tests (if applicable)
- [ ] Tests pass
- [ ] New functionality has appropriate test coverage
- [ ] Edge cases considered

## Review Format

Use this structure for review comments:

```markdown
## Review: [Approve | Needs Changes | Comment]

[1-2 sentence overall assessment]

### P1 - Critical Issues (Blocks Merge)

**1. [Issue Title]** (`path/to/file:line`)

[Description of the problem]

[Suggested fix or question]

### P2 - Important Issues (Should Fix)

- [Issue description] (`file:line`)

### P3 - Suggestions (Non-blocking)

- [Suggestion 1]
- [Suggestion 2]

### What Looks Good

- [Positive point 1]
- [Positive point 2]

### Questions

1. [Any clarifying questions]
```

### Follow-up Review Format

When reviewing a PR that has previous reviews, use this structure:

```markdown
## Follow-up Review: [Approve | Needs Changes]

[Overall assessment of changes since last review]

### Previous Feedback Status

| Feedback | Status |
|----------|--------|
| [Issue 1 summary] | Fixed / Not addressed / Explained |
| [Issue 2 summary] | Fixed / Not addressed / Explained |

### New Issues Found (if any)

**1. [Issue Title]** (`path/to/file:line`)

[Description]

### Remaining Concerns

- [Any unresolved items from previous review]

### Ready to Merge

[Yes/No and brief explanation]
```

## Priority Definitions

- **P1 (Critical)**: Must fix before merge - security vulnerabilities, data corruption, breaking functionality, blocking bugs
- **P2 (Important)**: Should fix - logic errors, missing edge cases, poor error handling, code smells
- **P3 (Suggestion)**: Nice to have - style improvements, minor refactoring, documentation gaps

## Rules

- ALWAYS checkout the PR branch before reviewing content
- Read the actual files, don't just rely on the diff
- Be constructive and specific in feedback
- Distinguish critical issues from suggestions using P1/P2/P3
- Return to original branch when done
- **Always get repository info dynamically** - never hardcode owner/repo
- **ALWAYS display findings BEFORE asking questions** - users must see the evidence before making decisions
- **Use parallel operations** when possible (multiple file reads, TaskCreate calls)
- **Use the AskUserQuestion tool** at decision points:
  - Review decision (approve/request changes/comment)
  - Clarifying questions when findings are ambiguous
  - Review submission approval
