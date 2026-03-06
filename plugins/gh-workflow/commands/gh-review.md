---
description: Use when assigned as reviewer or proactively reviewing PRs to perform multi-faceted code review with prioritized findings
argument-hint: <pr-number-or-url>
allowed-tools: Bash, Read, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.

VARIABLE PERSISTENCE NOTE:
Bash variables (like DEFAULT_BRANCH, REPO) do NOT persist across separate tool calls.
Each Bash invocation is an independent process. Store values mentally from output and
substitute them in subsequent commands. When running parallel Bash calls, each must
define any variables it needs inline.
-->

# Review PR #$ARGUMENTS

Review a pull request with multi-faceted analysis, task tracking, and prioritized findings.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to confirm review decisions, and **TaskCreate/TaskUpdate** tools to track review facets.

## Contract

**GOAL**: Comprehensive review with prioritized findings and an explicit review decision. Testable: review comment posted via `gh pr review` with structured P1/P2/P3 findings.

**CONSTRAINTS**:
- Must checkout the PR branch and read actual files, not just analyze the diff
- Must check 5 core review facets: (1) Code Quality, (2) Security, (3) Conventions, (4) Tests, (5) Requirements — plus (6) Comprehension Assessment if enabled via `gh-review-comprehension-check` config (default: `true`)
- When asserting code behaves a certain way, cite the specific file:line. If unable to cite, mark as UNVERIFIED
- Always display findings BEFORE asking user for review decision
- Never submit review without user approval
- Always return to original branch when done (including on cancel/error)

**FORMAT**: Findings synthesized into P1/P2/P3 priority table with file:line references. Review decision based on: 0 P1+P2 = Approve, 0 P1 = Comment, Any P1 = Request Changes.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Review submitted without reading the actual diff
- Review skips any of the 5 core review facets (or Facet 6 when enabled)
- P1 security issue missed (hardcoded secrets, injection vectors)
- Review posted without user explicitly approving the decision
- Findings shown after asking for decision (violates findings-first rule)
- Forgot to return to original branch after review

## Phase 1: Context Gathering

### Step 1.1: Normalize Input

`$ARGUMENTS` can be a PR number (e.g., `42`) or a full URL (e.g., `https://github.com/owner/repo/pull/42`). Extract the PR number:

```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+$')
[[ -n "$PR_NUM" ]] || { echo "ERROR: Could not extract PR number from: '$ARGUMENTS'"; exit 1; }
echo "PR number: $PR_NUM"
```

Use the extracted `PR_NUM` in all subsequent commands.

### Step 1.2: Gather Context (Parallel)

**Execute in parallel** (single message, multiple tool calls). Each call defines `REPO` independently:

1. **Save current branch**:
   ```bash
   git branch --show-current
   ```

2. **Fetch PR details**:
   ```bash
   gh pr view $PR_NUM --json title,body,headRefName,baseRefName,additions,deletions,changedFiles,commits,files,reviews
   ```

3. **Fetch review comments** (inline code comments):
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/pulls/$PR_NUM/comments
   ```

4. **Fetch PR conversation** (general discussion comments):
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$PR_NUM/comments
   ```

5. **Extract linked issue number from PR body**:
   ```bash
   gh pr view $PR_NUM --json body --jq '.body' | grep -oiE '(closes|fixes|resolves)\s*#[0-9]+' | grep -oE '[0-9]+'
   ```

**If PR not found** (gh pr view fails): Report error and stop:
> "PR #$PR_NUM not found. Verify the PR number and try again."

### Step 1.3: Fetch Linked Issue (Sequential)

If a linked issue was found in Step 1.2:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh issue view {linked-issue} --json title,body,comments
gh api repos/$REPO/issues/{linked-issue}/comments
```

Create a **verification list** from issue acceptance criteria to check against the implementation.

### Step 1.4: Check for Previous Reviews

If previous reviews or comments exist, this is a **follow-up review**:
- Read through ALL previous review comments
- Track each piece of feedback that was given
- Later verify each item was addressed (fixed or explained)
- You're still doing a FULL review — previous reviewers may have missed things

## Phase 2: Capability Discovery

Before detailed review, discover available review helpers by invoking the **capability-discovery** skill using the **Skill tool**.

The skill returns available agents, skills, quality commands, and tech stack detection.

**After skill returns**, note:
- Available review agents (code-reviewer, convention-checker, test-runner)
- Quality commands for test execution
- Tech stack for context

**Graceful fallback**: If the Skill tool invocation fails, discover inline:

**Execute in parallel**:

1. **Check for review agents**:
   ```bash
   ls .claude/agents/*review* .claude/agents/*convention* .claude/agents/*test* plugins/*/agents/*review* plugins/*/agents/*convention* plugins/*/agents/*test* 2>/dev/null
   ```

2. **Parse CLAUDE.md for quality commands**:
   ```bash
   grep -E "(lint|test|check)" .claude/CLAUDE.md 2>/dev/null
   ```

## Phase 3: Checkout and Diff Analysis

1. **Checkout the PR branch** (CRITICAL — never review from wrong branch):
   ```bash
   git fetch origin {headRefName}
   git checkout {headRefName}
   ```

2. **Get the full diff**:
   ```bash
   gh pr diff $PR_NUM
   ```

3. **Read changed files in parallel** using the Read tool to understand full context.
   - For PRs with **≤15 changed files**: read all changed files
   - For PRs with **>15 changed files**: read files with the most additions/deletions first; prioritize source files over generated/config files; use the diff for remaining files

## Phase 4: Multi-Faceted Review (Parallel Agent Pipeline)

### Step 4.1: Dispatch Parallel Review Agents

Launch 3 specialized agents in parallel using the **Agent tool** (single message, 3 Agent tool calls):

| Agent | Facets Covered | Focus |
|-------|---------------|-------|
| code-reviewer | (1) Code Quality + (2) Security | Logic, edge cases, error handling, security scan |
| convention-checker | (3) Conventions & Standards | Commit messages, branch naming, PR format, issue linkage |
| test-runner | (4) Tests & Quality Commands | Lint, test, typecheck execution |

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

**Severity mapping**: The convention-checker returns Blocking/Warning/Info levels. Map these to the unified P1/P2/P3 scale:
- Blocking → P1
- Warning → P2
- Info → P3

### Step 4.2: Requirements Compliance — Facet (5), Main Thread

While agents run, execute the requirements review in the main thread (requires issue context from Phase 1):

- Compare PR changes against issue acceptance criteria
- Verify each criterion is addressed
- Note any missing or partially implemented items
- Record findings with priority (P1 for missing requirements, P2 for partial, P3 for suggestions)

### Step 4.2b: Comprehension Assessment — Facet (6), Main Thread

**Check configuration** — read `gh-review-comprehension-check` from CLAUDE.md. Default: `true`. If `false`, skip this facet.

While agents run, also evaluate comprehension signals:

1. **Check PR body for Comprehension Report section**:
   - If present: Verify Requirements Adherence table against actual acceptance criteria. Flag mismatches between claimed status and diff evidence (e.g., criterion marked "Met" but no matching code found → P2 finding).
   - If absent: Add P2 finding: "PR lacks comprehension report — consider regenerating with `/gh-pr`"

2. **Select comprehension review questions**: Read `references/comprehension-review-questions.md` and select 2-3 targeted questions based on the diff's complexity areas. Match question categories to code patterns in the diff (new modules → "New Module Creation" questions, new dependencies → "Dependency / Library Integration" questions, etc.).

3. **Add questions as P3 findings** in the synthesis:

```markdown
### Comprehension Assessment
| Area | Report Status | Questions |
|------|--------------|-----------|
| {area from diff} | {Present/Missing/Mismatch} | "{selected question}" |
```

**Key design choice**: Comprehension questions are always P3 (suggestions). They cannot block a merge.

### Step 4.3: Collect Agent Results

After all agents return:
- Collect findings from each agent, applying the severity mapping from Step 4.1
- If any agent fails or times out → fall back to manual execution for that facet:
  - code-reviewer fails → execute code quality + security review manually
  - convention-checker fails → run convention checks via Bash
  - test-runner fails → run quality commands directly via Bash

### Step 4.4: Create Review Tasks (Tracking)

**Create tasks in parallel** to track completion of each facet:

```
TaskCreate: subject="Review: Code Quality & Security", status based on agent result
TaskCreate: subject="Review: Conventions & Standards", status based on agent result
TaskCreate: subject="Review: Tests & Quality Commands", status based on agent result
TaskCreate: subject="Review: Requirements Compliance", status based on main thread result
TaskCreate: subject="Review: Comprehension Assessment", status based on Step 4.2b result
```

Mark each task completed as its results are incorporated into the synthesis.

## Phase 5: Finding Synthesis

After all review tasks/agents complete, merge findings through a structured process:

### Step 5.1: Deduplicate

- Same `file:line` or same issue described in different words → keep the **higher priority** version
- Note all sources that flagged the issue (e.g., "Flagged by: code-reviewer, test-runner")
- Identical findings from multiple sources = higher confidence

### Step 5.2: Prioritize

1. **P1 (Critical)**: Security findings first, then data corruption, then breaking changes. Must fix before merge.
2. **P2 (Important)**: Logic errors first, then missing edge cases, then error handling. Should fix.
3. **P3 (Suggestions)**: Grouped by category (style, documentation, minor improvements). Nice to have.

### Step 5.3: Confidence Assessment

- Findings flagged by 2+ agents/facets independently = **high confidence**
- Single-source P1 with no code citation = **verify before including** — downgrade to P2 or mark UNVERIFIED
- Findings with `EVIDENCE: file:line` citations = higher confidence than inference-only

### Step 5.4: Unified Report

Present findings using this format:

```markdown
## Review Findings Summary

### Previous Feedback Status (follow-up reviews only)
| Feedback | Status |
|----------|--------|
| [Issue 1 summary] | Fixed / Not addressed / Explained |

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

### Remaining Concerns (follow-up reviews only)
- [Any unresolved items from previous review]
```

When no issues are found in a category, explicitly state "None found." rather than omitting the section. This confirms the check was performed.

### Review Decision Logic

Based on findings:
- **0 P1 and 0 P2**: Recommend APPROVE
- **0 P1 but some P2**: Recommend COMMENT with suggestions
- **Any P1**: Recommend REQUEST CHANGES with required fixes

## Phase 6: Review Submission

### Step 6.1: Detect Self-Review

```bash
PR_AUTHOR=$(gh pr view $PR_NUM --json author --jq '.author.login')
CURRENT_USER=$(gh api user --jq '.login')
[[ "$PR_AUTHOR" == "$CURRENT_USER" ]] && echo "SELF_REVIEW" || echo "PEER_REVIEW"
```

### Step 6.2: Present Findings

**First**, display your complete findings using the synthesis format from Phase 5. The user MUST see the detailed findings BEFORE being asked to make any decision.

### Step 6.3: Decision

**If PEER_REVIEW** — invoke the AskUserQuestion tool with:
- **Option 1**: "Approve - All requirements met"
- **Option 2**: "Request changes - Critical issues found"
- **Option 3**: "Comment only - Questions/suggestions, no blockers"
- **Option 4**: "Need more context before deciding"

If option 4, use the AskUserQuestion tool to ask specific clarifying questions.

**If SELF_REVIEW** — GitHub does not allow approving or requesting changes on your own PR. Skip the decision prompt and proceed directly to posting as a comment. The value of self-review is the analysis itself — solo developers still get the full P1/P2/P3 findings to act on before requesting external review.

### Step 6.4: Preview and Approval

Show the review comment that will be submitted, then use the **AskUserQuestion tool**:
- **Option 1**: "Submit this review" (Recommended)
- **Option 2**: "Edit review content first"
- **Option 3**: "Cancel review submission"

**Do not submit review without explicit approval.**

### Step 6.5: Submit Review

```bash
# Peer review — based on decision from Step 6.3
gh pr review $PR_NUM --approve --body "REVIEW"
gh pr review $PR_NUM --request-changes --body "REVIEW"
gh pr review $PR_NUM --comment --body "REVIEW"

# Self-review — always comment only
gh pr review $PR_NUM --comment --body "REVIEW"
```

### Step 6.6: Return to Original Branch

Always return — including on cancel or error:
```bash
git checkout {original-branch}
```

## Arguments

- `$ARGUMENTS`: PR number or PR URL (required). Examples: `42`, `https://github.com/owner/repo/pull/42`

## Rules

- ALWAYS checkout the PR branch before reviewing content
- Read the actual files, don't just rely on the diff
- Be constructive and specific in feedback
- Distinguish critical issues from suggestions using P1/P2/P3
- Return to original branch when done (including on cancel/error)
- **Always get repository info dynamically** — never hardcode owner/repo
- **ALWAYS display findings BEFORE asking questions** — users must see the evidence before making decisions
- **Use parallel operations** when possible (multiple file reads, TaskCreate calls)
- **Use the AskUserQuestion tool** at decision points:
  - Review decision (approve/request changes/comment)
  - Clarifying questions when findings are ambiguous
  - Review submission approval
