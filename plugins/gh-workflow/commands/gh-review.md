---
description: Use when assigned as reviewer or proactively reviewing PRs to perform multi-faceted code review with prioritized findings
argument-hint: <pr-number>
allowed-tools: Bash, Read, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill
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

## Contract

**GOAL**: Comprehensive review with prioritized findings and an explicit review decision. Testable: review comment posted via `gh pr review` with structured P1/P2/P3 findings.

**CONSTRAINTS**:
- Must checkout the PR branch and read actual files, not just analyze the diff
- Must check all 5 review facets (code quality, conventions, security, tests, requirements)
- When asserting code behaves a certain way, cite the specific file:line. If unable to cite, mark as UNVERIFIED
- Always display findings BEFORE asking user for review decision
- Never submit review without user approval

**FORMAT**: Findings synthesized into P1/P2/P3 priority table with file:line references. Review decision based on: 0 P1+P2 = Approve, 0 P1 = Comment, Any P1 = Request Changes.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Review submitted without reading the actual diff
- Review skips any of the 5 review facets
- P1 security issue missed (hardcoded secrets, injection vectors)
- Review posted without user explicitly approving the decision
- Findings shown after asking for decision (violates findings-first rule)
- Forgot to return to original branch after review

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

## Phase 3: Multi-Faceted Review (Parallel Agent Pipeline)

### Step 3.1: Dispatch Parallel Review Agents

Launch 3 specialized agents in parallel using the **Agent tool** (single message, 3 Agent tool calls):

| Agent | Subagent Type | Facets | Focus |
|-------|---------------|--------|-------|
| code-reviewer | gh-workflow:code-reviewer | Code Quality + Security | Logic, edge cases, error handling, security scan |
| convention-checker | gh-workflow:convention-checker | Conventions & Standards | Commit messages, branch naming, PR format, issue linkage |
| test-runner | gh-workflow:test-runner | Tests & Quality Commands | Lint, test, typecheck execution |

Each agent prompt should include:
- The PR diff (or instructions to obtain it)
- The PR branch name and number
- Instruction to return findings in P1/P2/P3 table format with file:line citations
- Instruction to operate as a sub-agent (see agent files for sub-agent protocol)

```
Execute 3 Agent tool calls in a single message:
- Agent call 1: code-reviewer — "Review PR #{N} for code quality, logic, security, edge cases. Return P1/P2/P3 findings table."
- Agent call 2: convention-checker — "Check PR #{N} conventions: commits, branch naming, PR format, issue linkage. Return findings."
- Agent call 3: test-runner — "Run quality commands (lint/test/typecheck) for PR #{N}. Return results table."
```

### Step 3.2: Requirements Compliance (Main Thread)

While agents run, execute Facet 5 in the main thread (requires issue context already gathered):

- Compare PR changes against issue acceptance criteria
- Verify each criterion is addressed
- Note any missing or partially implemented items
- Record findings with priority (P1/P2/P3)

### Step 3.3: Collect Agent Results

After all agents return:
- Collect P1/P2/P3 findings from each agent
- If any agent fails or times out → fall back to manual execution for that facet:
  - code-reviewer fails → execute code quality + security review manually
  - convention-checker fails → run convention checks via Bash
  - test-runner fails → run quality commands directly via Bash

### Step 3.4: Create Review Tasks (Tracking)

**Create tasks in parallel** to track completion of each facet:

```
TaskCreate: subject="Review: Code Quality & Security", status based on agent result
TaskCreate: subject="Review: Conventions & Standards", status based on agent result
TaskCreate: subject="Review: Tests & Quality Commands", status based on agent result
TaskCreate: subject="Review: Requirements Compliance", status based on main thread result
```

Mark each task completed as its results are incorporated into the synthesis.

## Phase 4: Finding Synthesis

After all review tasks/agents complete, merge findings through a structured process:

### Step 4.1: Collect

Gather raw findings from all review facets (or parallel agents if dispatched).

### Step 4.2: Deduplicate

- Same `file:line` or same issue described in different words → keep the **higher priority** version
- Note all sources that flagged the issue (e.g., "Flagged by: code-reviewer, test-runner")
- Identical findings from multiple sources = higher confidence

### Step 4.3: Prioritize

1. **P1 (Critical)**: Security findings first, then data corruption, then breaking changes
2. **P2 (Important)**: Logic errors first, then missing edge cases, then error handling
3. **P3 (Suggestions)**: Grouped by category (style, documentation, minor improvements)

### Step 4.4: Confidence Assessment

- Findings flagged by 2+ agents/facets independently = **high confidence**
- Single-source P1 with no code citation = **verify before including** — downgrade to P2 or mark UNVERIFIED
- Findings with `EVIDENCE: file:line` citations = higher confidence than inference-only

### Step 4.5: Unified Report

```markdown
## Review Findings Summary

### P1 - Critical (Blocks Merge)
| # | Category | Location | Issue | Suggested Fix | Flagged By |
|---|----------|----------|-------|---------------|------------|
| 1 | Security | file:line | [issue] | [fix] | code-reviewer |

### P2 - Important (Should Fix)
| # | Category | Location | Issue | Suggested Fix | Flagged By |
|---|----------|----------|-------|---------------|------------|

### P3 - Suggestions (Nice to Have)
| # | Category | Location | Issue | Suggested Fix | Flagged By |
|---|----------|----------|-------|---------------|------------|

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
