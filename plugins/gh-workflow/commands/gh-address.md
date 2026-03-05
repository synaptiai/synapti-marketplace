---
description: Use after receiving PR review feedback to systematically address comments, verify fixes, and re-request review
argument-hint: <pr-number>
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, TaskCreate, TaskList, TaskUpdate
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Address PR #$ARGUMENTS Comments

Systematically address review feedback on a pull request with task tracking and quality verification.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to clarify ambiguous feedback, and **TaskCreate/TaskUpdate** tools to track feedback resolution.

## Contract

**GOAL**: All review feedback items addressed with verification that fixes don't introduce new issues. Testable: each feedback item has a corresponding commit and response in the summary comment.

**CONSTRAINTS**:
- Address ALL comments (either fix or explain why not)
- Each fix should be a separate, focused commit
- Run post-address review gate before pushing
- Never push without explicit user approval

**FORMAT**: Summary comment posted on PR with feedback-to-action mapping table and verification checklist.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Any feedback item silently ignored (not addressed or explained)
- Changes pushed without running quality checks (tests, lint)
- Fix commit modifies files not related to the feedback without user approval
- Response posted before changes are pushed
- User not shown changes summary and response preview before approval

## Phase 1: Gather Feedback

**Execute in parallel** (single message, multiple tool calls):

1. **Get repository info for API calls**:
   ```bash
   # Get owner/repo dynamically - never hardcode
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   ```

2. **Fetch PR details and reviews**:
   ```bash
   gh pr view $ARGUMENTS --json title,headRefName,state,reviews
   ```

3. **Fetch review comments** (inline code comments):
   ```bash
   gh api repos/$REPO/pulls/$ARGUMENTS/comments
   ```

4. **Fetch PR conversation** (general discussion comments):
   ```bash
   gh api repos/$REPO/issues/$ARGUMENTS/comments
   ```

5. **Check for resolved/unresolved threads**:
   ```bash
   gh api repos/$REPO/pulls/$ARGUMENTS/comments --jq '[.[] | select(.in_reply_to_id == null)] | length'
   ```

6. **Checkout PR branch** (if not already on it):
   ```bash
   git fetch origin {headRefName}
   git checkout {headRefName}
   ```

## Phase 2: Create Feedback Tasks

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

Group related feedback into single tasks where appropriate.

## Phase 3: Work Through Feedback

### Surgical Change Principle

When addressing each feedback item:
- **Change ONLY what the feedback requires** - do not refactor adjacent code
- **If you notice other issues** while fixing, create a separate task rather than fixing inline
- **Verify scope** after each fix: `git diff --stat` should show only files directly related to the feedback
- **One commit per feedback item** - keeps changes traceable and reversible

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
   ```

8. **Mark task complete**: `TaskUpdate: taskId={id}, status=completed`

## Phase 4: Quality Verification

After addressing all feedback, verify changes don't introduce new issues:

### Step 4.1: Run Quality Checks

**Execute in parallel**:

```bash
# Based on detected tech stack
ruff check . 2>/dev/null
pytest 2>/dev/null

# Or for Node/TypeScript
npm run lint 2>/dev/null
npm test 2>/dev/null

# Or for Go
go vet ./... 2>/dev/null
go test ./... 2>/dev/null
```

### Step 4.2: Code Review on New Changes

Review the diff since last push:

```bash
git diff HEAD~{n}..HEAD  # Where n = number of fix commits
```

**Check for**:
- Did fixes introduce new issues?
- Are fixes complete and correct?
- Any unintended side effects?

### Step 4.3: Verify All Tasks Complete

```
TaskList
```

All feedback tasks should be status=completed.

## Phase 5: Post-Address Review Gate

**MANDATORY before pushing**: Re-verify quality after all fixes.

### Step 5.1: Code Review (Self-Review on Fixes)

Review changes introduced by fix commits:

```bash
git log --oneline origin/{baseRef}..HEAD
git diff origin/{baseRef}..HEAD
```

**Check**:
- [ ] No new code duplication
- [ ] No debug code left
- [ ] Fix addresses the actual concern (not just surface symptom)
- [ ] No placeholder or incomplete code

### Step 5.2: Test Review (If Tests Changed)

If tests were added or modified:
- [ ] Tests cover the fixed behavior
- [ ] Assertions are meaningful
- [ ] No flaky test patterns

### Step 5.3: Re-run Quality Checks

```bash
# All quality commands should pass
ruff check . && pytest  # Python
npm run lint && npm test  # Node
go vet ./... && go test ./...  # Go
```

### Step 5.4: Final Verification

- [ ] All tasks from TaskList are completed
- [ ] All quality checks pass
- [ ] No new issues introduced by fixes
- [ ] Changes ready for re-review

**If any check fails**:
1. Create task for the failure
2. Fix the issue
3. Re-run this gate
4. Only proceed when all pass

## Phase 6: Prepare Response

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

   **IMPORTANT**: The user MUST see the complete summary of changes and the response preview BEFORE being asked to approve. Never ask for approval without first showing what will be pushed and posted.

   **Do not push without explicit approval.**

2. **Verify changes before pushing**:
   - Check formatting is correct
   - Verify links still work
   - Run any applicable tests

3. **Push changes**:
   ```bash
   git push
   ```

4. **Post summary comment**:
    ```bash
    gh pr comment $ARGUMENTS --body "RESPONSE"
    ```

## Response Format

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

### Verification

- [x] All quality checks pass
- [x] Self-reviewed fix commits
- [x] No new issues introduced
```

## Commit Message Guidelines

Use descriptive messages that reference the feedback:

```bash
# Good - specific and clear
git commit -m "fix: correct broken link per review feedback"
git commit -m "fix: update validation logic as suggested"
git commit -m "docs: clarify usage instructions per review"

# Bad - vague and unhelpful
git commit -m "address review comments"
git commit -m "fixes"
git commit -m "updates"
```

## Handling Different Feedback Types

### Critical Issues (P1)
- Must be fixed
- Each fix should be a separate commit
- Explain what was done in the response

### Important Issues (P2)
- Should be fixed
- Group related fixes if appropriate
- Explain approach taken

### Suggestions (P3)
- Consider carefully, implement if agreeable
- If not implementing, explain why in the response
- It's okay to respectfully disagree with reasoning

### Questions
- Answer in the response comment
- Make content changes if the answer reveals an issue
- Clarify any misunderstandings

## Request Re-Review (Optional)

After addressing all feedback, optionally request re-review.

### Reviewer Suggestion

Use the **suggest-users skill** to suggest reviewers for re-review:

**Scoring adjustments for re-review**:
- Previous reviewer on this PR: +30 points
- Comment count on this PR: +5 per comment
- Original requester: +20 points

```bash
# Get previous reviewers
gh pr view $ARGUMENTS --json reviews --jq '.reviews[].author.login' | sort | uniq
```

**Use the AskUserQuestion tool** with ranked suggestions:
- **Option 1**: "@{original_reviewer}" (Recommended) - Previous reviewer
- **Option 2**: "@{other_reviewer}" - Additional reviewer
- **Option 3**: "Just push changes, don't request re-review"

```bash
gh pr edit $ARGUMENTS --add-reviewer {reviewer-username}
```

## Thread Status Tracking

Include thread status in the response comment:

```markdown
### Thread Status

| Thread | Status |
|--------|--------|
| [Comment summary] | Resolved / Addressed / Needs discussion |
```

## Rules

- Address ALL comments (either fix or explain why not)
- Each fix should be a separate, focused commit
- Verify content before pushing
- Push all changes BEFORE posting the summary comment
- Be professional and appreciative of feedback
- **Always get repository info dynamically** - never hardcode owner/repo
- **ALWAYS display findings BEFORE asking questions** - users must see what changes were made and the response preview before being asked to approve
- **Run post-address review gate** before pushing - verify fixes don't introduce new issues
- **Use parallel operations** when possible (API calls, quality checks)
- **Use the AskUserQuestion tool** at decision points:
  - Clarifying ambiguous feedback
  - Deciding whether to implement or push back on suggestions
  - Getting approval before pushing and posting response
