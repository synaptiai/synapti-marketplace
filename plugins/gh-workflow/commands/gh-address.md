---
description: Address review comments on a pull request
argument-hint: <pr-number>
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# Address PR #$ARGUMENTS Comments

Systematically address review feedback on a pull request.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to clarify ambiguous feedback, confirm proposed fixes, and get approval before pushing changes.

## Process

1. **Get repository info for API calls**:
   ```bash
   # Get owner/repo dynamically - never hardcode
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   ```

2. **Fetch PR details and reviews**:
   ```bash
   gh pr view $ARGUMENTS --json title,headRefName,state,reviews
   ```

3. **Fetch review comments**:
   ```bash
   gh api repos/$REPO/pulls/$ARGUMENTS/comments
   ```

4. **Checkout PR branch** (if not already on it):
   ```bash
   git fetch origin {headRefName}
   git checkout {headRefName}
   ```

5. **Create checklist** of all feedback items to address

6. **For each comment**:
   - Read and understand the feedback
   - Read the relevant content context

   **If feedback is ambiguous, use the AskUserQuestion tool** to clarify:
   - Quote the unclear comment
   - Present your interpretation options:
     - **Option 1**: "I interpret this as [interpretation A]"
     - **Option 2**: "I interpret this as [interpretation B]"
     - **Option 3**: "I need more context to understand"

   **If you disagree with feedback, use the AskUserQuestion tool**:
   - **Option 1**: "Implement the suggested change anyway"
   - **Option 2**: "Push back with explanation"
   - **Option 3**: "Discuss further before deciding"

   - Make the necessary changes
   - Commit with a descriptive message

7. **Preview response and get approval using the AskUserQuestion tool**:

   Before pushing, show the summary of changes and response comment:
   - **Option 1**: "Push changes and post this response" (Recommended)
   - **Option 2**: "Edit response comment first"
   - **Option 3**: "Make additional changes before pushing"

   **Do not push without explicit approval.**

8. **Verify changes before pushing**:
   - Check formatting is correct
   - Verify links still work
   - Run any applicable tests

9. **Push changes**:
   ```bash
   git push
   ```

10. **Post summary comment**:
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

### Critical Issues
- Must be fixed
- Each fix should be a separate commit
- Explain what was done in the response

### Suggestions
- Consider carefully, implement if agreeable
- If not implementing, explain why in the response
- It's okay to respectfully disagree with reasoning

### Questions
- Answer in the response comment
- Make content changes if the answer reveals an issue
- Clarify any misunderstandings

## Rules

- Address ALL comments (either fix or explain why not)
- Each fix should be a separate, focused commit
- Verify content before pushing
- Push all changes BEFORE posting the summary comment
- Be professional and appreciative of feedback
- **Always get repository info dynamically** - never hardcode owner/repo
- **Use the AskUserQuestion tool** at decision points:
  - Clarifying ambiguous feedback
  - Deciding whether to implement or push back on suggestions
  - Getting approval before pushing and posting response
