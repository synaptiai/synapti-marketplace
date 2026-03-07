---
description: "[flow] Address PR review feedback systematically. Categorizes feedback, implements surgical fixes, verifies changes, and re-requests review."
argument-hint: <pr-number>
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute independent operations simultaneously.
-->

# Address Review Feedback for PR #$ARGUMENTS

Systematic feedback resolution. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `feedback-resolution` — surgical changes, context recovery, pushback criteria
- `change-classification` — verify no out-of-context changes
- `capability-discovery` — quality commands for verification

## Phase 1: EXPLORE

**Parallel operations:**

```bash
# 1. PR details and branch
gh pr view $ARGUMENTS --json headRefName,baseRefName,title,body
gh pr checkout $ARGUMENTS

# 2. Review comments (inline)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api repos/$REPO/pulls/$ARGUMENTS/comments --jq '.[] | {
  id: .id,
  path: .path,
  line: .line,
  body: .body,
  author: .user.login
}'

# 3. Review summaries
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | {
  state: .state,
  body: .body,
  author: .author.login
}'

# 4. Conversation threads
gh api repos/$REPO/pulls/$ARGUMENTS/comments --jq 'group_by(.path) | .[] | {file: .[0].path, comments: [.[] | {body: .body, author: .user.login}]}'
```

**Agent(Explore)**: "Pre-resolve check — for each review comment, verify the feedback still applies to the current code. Some comments may already be addressed by later commits."

**Skill(capability-discovery)**: Discover quality commands for verification.

## Phase 2: PLAN

Categorize feedback and create tasks:

```
For each feedback item:
  TaskCreate(
    subject: "Address: {feedback summary}",
    description: "Reviewer: @{author}\nFile: {path}:{line}\nFeedback: {body}\nPriority: {P1|P2|P3|Question}",
    activeForm: "Fixing {short description}"
  )
```

Group related feedback. Set dependencies for sequential fixes.

Display categorized feedback:
```markdown
| # | Category | File | Feedback | Priority |
|---|----------|------|----------|----------|
| 1 | Must fix | auth.rb:42 | SQL injection risk | P1 |
| 2 | Should fix | test.rb:10 | Missing edge case | P2 |
| 3 | Question | api.rb:5 | Why this approach? | Q |
```

## Phase 3: CODE

For each feedback task (in priority order):

```
1. TaskUpdate(taskId, status: "in_progress")
2. Read the review comment
3. Context recovery: find current code location (don't trust line numbers)
   - Search for quoted code snippets
   - Read the file at the mentioned path
4. Implement the minimal surgical fix
5. Verify the fix addresses the specific feedback
6. Commit: git commit -m "fix(scope): address review — {summary}"
7. TaskUpdate(taskId, status: "completed")
```

For **Question** items: prepare a response comment (no code change needed).

For **Pushback** items: explain reasoning in response comment.

## Phase 4: VERIFY

1. **Quality commands** (parallel): lint, test, typecheck
2. **Self-review** — Agent(code-reviewer): verify fixes are surgical, no regressions
3. **Change classification** — verify no out-of-context changes introduced
4. **TaskList**: Confirm all feedback tasks complete
5. **Push** (Tier 2: journal-and-proceed):
   ```bash
   git push
   ```
6. **Post resolution comments**:
   ```bash
   gh pr comment $ARGUMENTS --body "Addressed review feedback:
   - {P1 fix 1}
   - {P2 fix 2}
   - {Question response}"
   ```
7. **Re-request review**:
   ```bash
   gh pr edit $ARGUMENTS --add-reviewer @{reviewer}
   ```

Display summary: fixes applied, questions answered, pushback items.
