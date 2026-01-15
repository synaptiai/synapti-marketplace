# Review PR #$ARGUMENTS

Review a pull request with proper branch checkout and convention checks.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to confirm review decisions, clarify ambiguous findings, and get approval before submitting reviews.

## Process

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

4. **If previous reviews or comments exist**: This is a follow-up review. You MUST:
   - Read through ALL previous review comments
   - Track each piece of feedback that was given
   - Later verify each item was addressed (fixed or explained)
   - Note: You're still doing a FULL review - previous reviewers may have missed things

5. **Checkout the PR branch** (CRITICAL - never review from wrong branch):
   ```bash
   git fetch origin {headRefName}
   git checkout {headRefName}
   ```

6. **Get the full diff**:
   ```bash
   gh pr diff $ARGUMENTS
   ```

7. **Read all changed files** - use the Read tool on each modified file to understand the full context

8. **Check conventions** (see checklist below)

9. **If this is a follow-up review**: For each previous comment, verify:
   - Was the issue fixed in the content?
   - Or was there a valid explanation for not fixing it?
   - Did the fix introduce any new issues?

10. **Determine review decision using the AskUserQuestion tool**:

    After completing the review checklist, present findings and ask:
    - **Option 1**: "Approve - PR meets all requirements"
    - **Option 2**: "Request changes - Critical issues found"
    - **Option 3**: "Comment only - Questions/suggestions, no blockers"
    - **Option 4**: "Need more context before deciding"

    If option 4, **use the AskUserQuestion tool** to ask specific clarifying questions.

11. **Preview review and get approval using the AskUserQuestion tool**:

    Show the review comment that will be submitted, then ask:
    - **Option 1**: "Submit this review" (Recommended)
    - **Option 2**: "Edit review content first"
    - **Option 3**: "Cancel review submission"

    **Do not submit review without explicit approval.**

12. **Submit review**:
    ```bash
    # Approve
    gh pr review $ARGUMENTS --approve --body "REVIEW"

    # Request changes
    gh pr review $ARGUMENTS --request-changes --body "REVIEW"

    # Comment only
    gh pr review $ARGUMENTS --comment --body "REVIEW"
    ```

13. **Return to original branch**:
    ```bash
    git checkout {original-branch}
    ```

## Review Checklist

### Conventions
- [ ] Commits follow conventional format (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`)
- [ ] PR description follows template structure
- [ ] `closes #X` links issue correctly (if applicable)
- [ ] PR targets correct default branch

### Content Quality
- [ ] Code/content is correct and complete
- [ ] No obvious bugs or errors
- [ ] Formatting is correct and consistent
- [ ] Links are valid and not broken
- [ ] No typos or grammatical errors
- [ ] Content is clear and well-organized

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

### Critical Issues (if any)

**1. [Issue Title]** (`path/to/file:line`)

[Description of the problem]

[Suggested fix or question]

### Suggestions (non-blocking)

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

## Severity Levels

- **Critical**: Must fix before merge (broken functionality, security issues, blocking bugs)
- **Suggestion**: Nice to have, non-blocking (style, minor improvements)
- **Question**: Clarification needed, may or may not need changes

## Rules

- ALWAYS checkout the PR branch before reviewing content
- Read the actual files, don't just rely on the diff
- Be constructive and specific in feedback
- Distinguish critical issues from suggestions
- Return to original branch when done
- **Always get repository info dynamically** - never hardcode owner/repo
- **Use the AskUserQuestion tool** at decision points:
  - Review decision (approve/request changes/comment)
  - Clarifying questions when findings are ambiguous
  - Review submission approval
