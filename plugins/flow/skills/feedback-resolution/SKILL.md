---
name: feedback-resolution
description: "[flow] Use when addressing PR review feedback. Guides focused change principle with Boy Scout Rule, feedback context recovery, ambiguity handling, pushback criteria, and re-review request patterns."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
context: fork
agent: general-purpose
---

# Feedback Resolution

Domain skill for systematically addressing PR review comments.

## Iron Law

**EVERY FIX TRACES TO A SPECIFIC REVIEW COMMENT OR THE BOY SCOUT RULE. Untraceable changes that fail the proximity test are out-of-context changes.**

If you can't point to the review comment or the Boy Scout proximity test that motivated a change, the change doesn't belong in this round.

## Focused Change Principle

When addressing feedback, fix what the feedback requires — and apply the Boy Scout Rule to files you're already modifying:

- Each feedback fix should be traceable to a specific review comment
- Don't add features while addressing feedback
- Don't change formatting in files not mentioned in feedback
- Boy Scout cleanup in files being modified for feedback is allowed if it passes the proximity test (see `code-quality-principles`)
- Boy Scout fixes get separate `improve:` commits, never mixed with feedback fixes

## Feedback Collection

Fetch all review feedback:

```bash
PR_NUM=$ARGUMENTS
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# Review comments with file:line context
gh api repos/$REPO/pulls/$PR_NUM/comments --jq '.[] | {id: .id, path: .path, line: .line, body: .body, author: .user.login}'

# Review summaries and states
gh pr view $PR_NUM --json reviews --jq '.reviews[] | {state: .state, body: .body, author: .author.login}'

# Root conversation threads (for grouping replies)
gh api repos/$REPO/pulls/$PR_NUM/comments --jq '.[] | select(.in_reply_to_id == null) | .id'
```

## Feedback Categorization

Categorize each comment:

| Category | Action |
|----------|--------|
| **P1 — Must fix** | Code bug, security issue, logic error |
| **P2 — Should fix** | Convention violation, missing test, unclear code |
| **P3 — Consider** | Style preference, optimization suggestion |
| **Question** | Needs response, not necessarily a code change |
| **Resolved** | Already fixed or no longer relevant |

## Context Recovery

Don't trust line numbers from review comments — code may have changed since the review:

1. Search for the **quoted code** from the review comment
2. Search for the **file path** mentioned
3. Read the current state of the file
4. Match the feedback to the current code location

```bash
# Find current location of reviewed code
grep -n "quoted_code_snippet" $FILE_PATH
```

## Fix Workflow

For each feedback item (as TaskCreate):

1. **Read** the review comment carefully
2. **Find** the current code location (context recovery)
3. **Implement** the minimal fix
4. **Verify** the fix addresses the specific feedback
5. **Commit** with reference: `fix(scope): address review — {summary}`

## Ambiguity Handling

When feedback is unclear:

1. Check if follow-up comments clarify
2. Check if similar patterns exist in the codebase for guidance
3. If still unclear, resolve with the most conservative interpretation
4. Note the interpretation in the response comment

## Pushback Criteria

It's acceptable to push back on feedback when:

- The suggestion would break existing tests
- The suggested approach contradicts project conventions (cite CLAUDE.md)
- The feedback is based on a misunderstanding of the requirements
- The suggested change would introduce a regression

Always explain the reasoning when pushing back. Never ignore feedback silently.

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "While fixing this, I noticed something else to improve" | Does it pass the proximity test? If yes, fix it in a separate `improve:` commit. If no, create a follow-up issue with `/flow:issue`. |
| "The reviewer probably meant this broader change" | Don't guess. Address the literal comment. Clarify if unsure. |
| "I'll batch all fixes into one commit" | One commit per feedback item. Traceability requires it. |

## Re-Review Request

After all feedback is addressed:

```bash
# Post resolution summary as comment
gh pr comment $PR_NUM --body "Addressed review feedback: {summary}"

# Re-request review
gh pr edit $PR_NUM --add-reviewer @{reviewer}
```

## Verification

Before re-requesting review:

1. All quality commands pass
2. Each feedback item has a corresponding commit or response
3. No out-of-context changes introduced (use change-classification)
4. Push changes (Tier 2)
