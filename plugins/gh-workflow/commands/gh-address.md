---
description: Use after receiving PR review feedback to systematically address comments, verify fixes, and re-request review
argument-hint: <pr-number-or-url>
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.

VARIABLE PERSISTENCE NOTE:
Bash variables (like REPO, PR_NUM) do NOT persist across separate tool calls.
Each Bash invocation is an independent process. Store values mentally from output and
substitute them in subsequent commands. When running parallel Bash calls, each must
define any variables it needs inline.
-->

# Address PR #$ARGUMENTS Comments

Systematically address review feedback on a pull request with task tracking and quality verification.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to clarify ambiguous feedback, and **TaskCreate/TaskUpdate** tools to track feedback resolution.

## Contract

**GOAL**: All review feedback items addressed with verification that fixes don't introduce new issues. Testable: each feedback item has a corresponding commit and response in the summary comment.

**CONSTRAINTS**:
- Address ALL comments (either fix or explain why not)
- Each fix should be a separate, focused commit
- Run quality & review gate before pushing
- Never push without explicit user approval

**FORMAT**: Summary comment posted on PR with feedback-to-action mapping table, thread status, and verification checklist.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Any feedback item silently ignored (not addressed or explained)
- Changes pushed without running quality checks (tests, lint)
- Fix commit modifies files not related to the feedback without user approval
- Response posted before changes are pushed
- User not shown changes summary and response preview before approval

## Phase 1: Context & Feedback Gathering

### Step 1.1: Normalize Input

`$ARGUMENTS` can be a PR number (e.g., `42`) or a full URL (e.g., `https://github.com/owner/repo/pull/42`). Extract the PR number:

```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+$')
[[ -n "$PR_NUM" ]] || { echo "ERROR: Could not extract PR number from: '$ARGUMENTS'"; exit 1; }
echo "PR number: $PR_NUM"
```

Use the extracted `PR_NUM` in all subsequent commands.

### Step 1.2: Read Project Context

Read CLAUDE.md using the **Read tool** (not cat/Bash) to extract quality commands and conventions:
- Try `.claude/CLAUDE.md` first, then `CLAUDE.md`
- Note lint, test, and typecheck commands for Phases 5–6
- Note commit conventions for Phase 4 commits

### Step 1.3: Gather Feedback (Parallel)

**Execute in parallel** (single message, multiple Bash tool calls). Each call defines `REPO` independently:

1. **Fetch PR details and reviews**:
   ```bash
   gh pr view $PR_NUM --json title,headRefName,baseRefName,state,reviews
   ```

2. **Fetch review comments** (inline code comments):
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/pulls/$PR_NUM/comments
   ```

3. **Fetch PR conversation** (general discussion comments):
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$PR_NUM/comments
   ```

4. **Check for resolved/unresolved threads**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/pulls/$PR_NUM/comments --jq '[.[] | select(.in_reply_to_id == null)] | length'
   ```

**If PR not found** (gh pr view fails): Report error and stop:
> "PR #$PR_NUM not found. Verify the PR number and try again."

### Step 1.4: Checkout PR Branch (Sequential)

This depends on `headRefName` from Step 1.3, so it must run after:

```bash
git fetch origin {headRefName}
git checkout {headRefName}
```

## Phase 2: Capability Discovery

Invoke the **capability-discovery** skill using the **Skill tool** to discover quality commands and available agents.

**After skill returns**, extract:
```
LINT_CMD="{detected lint command}"
TEST_CMD="{detected test command}"
TYPECHECK_CMD="{detected typecheck}"
```

Store these for Phase 5. If a command is not applicable, note as "N/A — skip".

**Graceful fallback**: If the Skill tool invocation fails and CLAUDE.md didn't provide commands, detect from tech stack:

| Indicator | Commands |
|-----------|----------|
| pyproject.toml | `ruff check .`, `pytest` |
| package.json | `npm run lint`, `npm test` |
| tsconfig.json | `tsc --noEmit` |
| go.mod | `go vet ./...`, `go test ./...` |
| Cargo.toml | `cargo clippy`, `cargo test` |

## Phase 3: Create Feedback Tasks

For each review comment/feedback item, create a tracking task:

```
TaskCreate:
  subject: "Address: [Brief summary of feedback]"
  description: |
    **Reviewer**: @{reviewer}
    **Location**: {file}:{line}
    **Comment**: {full comment text}

    **Action needed**: [fix/discuss/clarify]
  activeForm: "Addressing [feedback summary]"
```

Group related feedback into single tasks where appropriate. Categorize each item:
- **P1 (Critical)**: Must be fixed. Each fix = separate commit.
- **P2 (Important)**: Should be fixed. Group related fixes if appropriate.
- **P3 (Suggestion)**: Implement if agreeable. It's okay to respectfully disagree with reasoning.
- **Question**: Answer in the response comment. Make code changes if the answer reveals an issue.

## Phase 4: Work Through Feedback

### Surgical Change Principle

When addressing each feedback item:
- **Change ONLY what the feedback requires** — do not refactor adjacent code
- **If you notice other issues** while fixing, create a separate task rather than fixing inline
- **Verify scope** after each fix: `git diff --stat` should show only files directly related to the feedback
- **One commit per feedback item** — keeps changes traceable and reversible

**FAILURE CONDITION**: A fix commit that modifies files not mentioned in the feedback without explicit user approval.

For each feedback task:

1. **Mark in progress**: `TaskUpdate: taskId={id}, status=in_progress`

2. **Read and understand the feedback**

3. **Read the relevant content context**

4. **If feedback is ambiguous, use the AskUserQuestion tool** to clarify:
   - Quote the unclear comment
   - Present your interpretation options:
     - **Option 1**: "I interpret this as [interpretation A]"
     - **Option 2**: "I interpret this as [interpretation B]"
     - **Option 3**: "I need more context to understand"

5. **If you disagree with feedback, use the AskUserQuestion tool**:
   - **Option 1**: "Implement the suggested change anyway"
   - **Option 2**: "Push back with explanation"
   - **Option 3**: "Discuss further before deciding"

6. **Make the necessary changes**

7. **Commit with a descriptive message**:
   ```bash
   # Good - specific and clear
   git commit -m "fix: correct broken link per review feedback"
   git commit -m "fix: update validation logic as suggested"
   git commit -m "docs: clarify usage instructions per review"
   ```

8. **Mark task complete**: `TaskUpdate: taskId={id}, status=completed`

## Phase 5: Quality Checks

Use the quality commands discovered in Phase 2 (LINT_CMD, TEST_CMD, TYPECHECK_CMD). Skip any that are N/A.

### Step 5.1: Quality Verification Loop (Bounded)

Execute a bounded fix-verify cycle. **Fix immediately — do not create tasks** for lint/test failures. These are mechanical fixes.

**Iteration 1 (and up to 3 total):**

1. **Run all quality commands in parallel** (3 Bash tool calls in a single message):
   ```
   - Bash call 1: {lint_cmd}       # e.g., ruff check . 2>&1
   - Bash call 2: {test_cmd}       # e.g., pytest 2>&1
   - Bash call 3: {typecheck_cmd}  # e.g., tsc --noEmit 2>&1
   ```

2. **If ALL pass** → proceed to Phase 6

3. **If ANY fail**:
   - Parse error output to identify root cause (file, line, error type)
   - Fix the issue inline immediately (Edit tool, not TaskCreate)
   - Commit the fix: `git commit -m "fix: [what was fixed]"`
   - Re-run ALL checks (go back to step 1)

4. **Max 3 iterations**. After 3 failed iterations → escalate to user via **AskUserQuestion tool**:
   - **Option 1**: "Show me the failures, I'll fix manually"
   - **Option 2**: "Push with known failures and note in response"
   - **Option 3**: "Abort — I need to investigate"

## Phase 6: Code Review (Self-Review on Fixes)

This is the most critical gate. Reviewer feedback is being addressed — introducing new issues here means another review cycle. The goal is to make this the **last round** of review on this PR.

### Step 6.1: Get the Fix Diff

```bash
git diff origin/{baseRefName}..HEAD
```

### Step 6.2: Systematic Review

Read the **code review checklist** from `references/code-review-checklist.md` (relative to the gh-workflow plugin directory) and follow its instructions. The checklist covers:
- Agent-assisted review (preferred, using `code-reviewer` agent if available from Phase 2 discovery)
- Manual review fallback with 7-point checklist
- Output format for findings

Focus the review on fix commits specifically — verify each fix:
- Addresses the **actual concern** raised by the reviewer, not just the surface symptom
- Does not introduce new issues, duplication, or complexity
- Does not touch files outside the scope of the feedback
- Does not leave debug code, placeholders, or TODOs
- Uses patterns consistent with the rest of the codebase

### Step 6.3: Track and Resolve Findings

**Task creation policy for review findings** — because this is an address cycle where regressions mean another full review round, be thorough:

- **P1/P2 findings**: Create tasks via `TaskCreate: subject="Fix: [issue]"`, implement fixes, re-run quality checks (Phase 5 Step 5.1)
- **P3 findings**: Fix inline immediately, commit

After all finding tasks are completed:
```
TaskList
```
Verify all review finding tasks are status=completed.

### Step 6.4: Re-Run Quality Checks

If any fixes were made during review, re-run ALL quality commands in parallel to confirm nothing broke:

```
- Bash call 1: {lint_cmd}
- Bash call 2: {test_cmd}
- Bash call 3: {typecheck_cmd}
```

If failures → apply the same bounded loop from Phase 5 Step 5.1 (max 3 iterations).

## Phase 7: Test Review (Self-Review on Fixes)

If tests were added or modified as part of addressing feedback:

Read the **test review checklist** from `references/test-review-checklist.md` (relative to the gh-workflow plugin directory) and follow its instructions. The checklist covers:
- Coverage gaps (missing behavior, edge cases, error paths)
- Assertion quality
- Test design patterns
- Output format for findings

After identifying issues:
1. Create tasks for missing coverage and significant issues
2. Implement new/improved tests
3. Run test suite
4. Verify all tests pass

**Skip if**: No tests were added or modified during Phase 4.

## Phase 8: Pre-Push Gate (Mandatory)

Before proceeding to response preparation, verify ALL of the following. This gate exists because pushing incomplete or broken fixes means another review cycle — the whole point of `/gh-address` is to resolve feedback definitively.

**Completeness Check**:
```
TaskList
```
- [ ] All feedback tasks from Phase 3 are status=completed
- [ ] All review finding tasks from Phase 6 are status=completed
- [ ] No pending or in_progress tasks

**Quality Gate**:
- [ ] Linter passes (zero errors)
- [ ] Type checker passes (zero errors)
- [ ] All tests pass
- [ ] Code review findings addressed
- [ ] Test review findings addressed (if applicable)

**Fix Quality**:
- [ ] Each fix addresses the actual reviewer concern
- [ ] No mocks/stubs/placeholders in src code
- [ ] No TODO comments or debug code left
- [ ] Fix commits are scoped — no unrelated changes
- [ ] All implementations are complete

**If ANY gate fails**:
1. Fix inline immediately, re-run checks
2. Max 3 iterations before escalating to user via AskUserQuestion
3. Only proceed when all checks pass

## Phase 9: Prepare Response

1. **Preview response and get approval using the AskUserQuestion tool**:

   **First**, display a complete summary of what was done:
   ```
   ## Changes Summary

   ### Feedback Addressed
   | Comment | Action Taken | Status |
   |---------|--------------|--------|
   | [Reviewer comment 1] | [What you changed] | Fixed |
   | [Reviewer comment 2] | [Explanation] | Discussed |

   ### Commits Made
   - `abc1234` - fix: description
   - `def5678` - fix: description

   ### Quality Verification
   - [x] Lint passes
   - [x] Tests pass
   - [x] Code review on fixes: no new issues

   ### Response Comment Preview
   [Show the exact comment that will be posted]
   ```

   **Then, and only then**, invoke the AskUserQuestion tool with:
   - **Option 1**: "Push changes and post this response" (Recommended)
   - **Option 2**: "Edit response comment first"
   - **Option 3**: "Make additional changes before pushing"

   **IMPORTANT**: The user MUST see the complete summary and response preview BEFORE being asked to approve. Never ask for approval without first showing what will be pushed and posted.

   **Do not push without explicit approval.**

2. **Push changes**:
   ```bash
   git push
   ```

3. **Post summary comment**:
    ```bash
    gh pr comment $PR_NUM --body "RESPONSE"
    ```

### Response Comment Format

Use this structure for the summary comment:

```markdown
## Addressed Review Feedback

Thanks for the review! Here's what I've addressed:

### Changes Made

**1. [Feedback summary]**
- [What was changed]
- Commit: `abc1234`

**2. [Feedback summary]**
- [What was changed]
- Commit: `def5678`

### Discussion Points

> [Quote reviewer comment if needs discussion]

[Your response or explanation]

### Not Addressed (if any)

- **[Item]**: [Reason - needs clarification / out of scope / disagree because X]

### Thread Status

| Thread | Status |
|--------|--------|
| [Comment summary] | Resolved / Addressed / Needs discussion |

### Verification

- [x] All quality checks pass
- [x] Self-reviewed fix commits
- [x] No new issues introduced
```

## Phase 10: Request Re-Review

After addressing all feedback and pushing, optionally request re-review.

Invoke the **suggest-users** skill using the **Skill tool** with re-review context. The skill will:
1. Gather CODEOWNERS, collaborators, file commit history, and review load
2. Apply re-review scoring adjustments (previous reviewer: +30, comment count: +5 per comment, original requester: +20)
3. Return ranked suggestions with reasoning

After the skill returns, present suggestions using the **AskUserQuestion tool**:
- **Option 1**: "@{original_reviewer}" (Recommended) - Previous reviewer
- **Option 2**: "@{other_reviewer}" - Additional reviewer
- **Option 3**: "Don't request re-review"

**Graceful fallback**: If the Skill tool invocation fails, discover reviewers inline:

```bash
gh pr view $PR_NUM --json reviews --jq '.reviews[].author.login' | sort | uniq
```

Present previous reviewers as options using the **AskUserQuestion tool**.

After reviewer selection:
```bash
gh pr edit $PR_NUM --add-reviewer {reviewer-username}
```

## Arguments

- `$ARGUMENTS`: PR number or PR URL (required). Examples: `42`, `https://github.com/owner/repo/pull/42`

## Rules

- Address ALL comments (either fix or explain why not)
- Each fix should be a separate, focused commit
- Push all changes BEFORE posting the summary comment
- Be professional and appreciative of feedback
- **Always get repository info dynamically** — never hardcode owner/repo
- **ALWAYS display findings BEFORE asking questions** — users must see what changes were made and the response preview before being asked to approve
- **Run quality & review gate** before pushing — verify fixes don't introduce new issues
- **Use parallel operations** when possible (API calls, quality checks)
- **Use the AskUserQuestion tool** at decision points:
  - Clarifying ambiguous feedback
  - Deciding whether to implement or push back on suggestions
  - Getting approval before pushing and posting response

## Related Commands

- **`/gh-pr`**: Create PR with full review and reviewer suggestions
- **`/gh-review`**: Review a pull request
- **`/gh-start`**: Start work on an issue
- **`/gh-commit`**: Context-aware commits with change classification
