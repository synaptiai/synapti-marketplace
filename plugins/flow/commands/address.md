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

## Review Cycle Tracking

Before planning, determine the current review cycle:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
CYCLE_COUNT=$(gh pr view $ARGUMENTS --json reviews --jq '[.reviews[] | select(.state == "CHANGES_REQUESTED")] | length')
echo "REVIEW_CYCLE=$CYCLE_COUNT"
```

**Escalating strategy by cycle:**
- **Cycle 1**: Targeted fixes + Boy Scout cleanup in modified files
- **Cycle 2**: Targeted fixes + whole-file scan of all modified files for P1/P2
- **Cycle 3+**: Comprehensive fix-all + full self-review before re-requesting

## Phase 2: PLAN

Categorize feedback and create tasks:

```
TaskCreate(
  subject: "Post resolution comment",
  description: "Post structured feedback resolution summary to PR via gh pr comment"
)

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
4. Implement the fix
5. Verify the fix addresses the specific feedback
6. Commit: git commit -m "fix(scope): address review — {summary}"
7. TaskUpdate(taskId, status: "completed")
```

**Boy Scout pass** — after all feedback fixes:
- Scan all modified files for lint/format/obvious issues that pass the proximity test
- If cycle >= 2, also scan the entire file for P1/P2 issues
- Fix any proximity-test-passing issues found
- Boy Scout fixes get separate `improve:` commits

For **Question** items: prepare a response comment (no code change needed).

For **Pushback** items: explain reasoning in response comment.

For **Out-of-scope** items — only items that FAIL the proximity test are out-of-scope:

A finding in a file the PR already modifies is NOT out-of-scope if it passes the proximity test — it should be fixed under the Boy Scout Rule.

If a finding truly fails the proximity test (untouched files, architecture changes, new tests required):

1. Use the AskUserQuestion tool with contextual options: "This finding is valid but out-of-scope (fails proximity test). Create a follow-up issue to track it?"
2. If yes, create a GitHub issue using issue-crafting skill knowledge:
   - Title: concise, solution-agnostic description
   - Body: Context, Current State (file:line), Objective, Acceptance Criteria
   - Labels: from repo label set
   - Issue creation is Tier 2 (journal-and-proceed)
   ```bash
   gh issue create --title "{title}" --body "{body}" --label "{labels}"
   ```
3. Reference the created issue in the resolution comment
4. TaskUpdate the feedback task as completed with result: "follow-up issue #{N}"

## Phase 4: VERIFY (Convergence Check)

1. **Quality commands** (parallel): lint, test, typecheck
2. **Comprehensive self-review** of ALL files touched on the branch:
   ```
   Agent(code-reviewer):
     "Review ALL files modified on this branch against $DEFAULT_BRANCH.
      Check for: logic errors, security issues, missing edge cases.
      Return P1/P2/P3 findings with file:line."
   ```
3. **Convergence check** (max 3 self-review-fix iterations):
   - Self-review finds P1 → fix NOW (don't re-request with known P1s)
   - P2 in touched files → fix NOW
   - P3 → note only
   - After fixes: re-run quality commands, re-review changed files
4. **Verify Boy Scout cleanup** passes proximity test (no scope creep)
5. **Change classification** — verify no out-of-context changes introduced
6. **TaskList**: Confirm all feedback tasks complete
7. **Push** (Tier 2: journal-and-proceed):
   ```bash
   git push
   ```
8. **Post resolution comment** using the template structure from `templates/resolution-comment.md`:
   ```bash
   gh pr comment $ARGUMENTS --body "$BODY"
   ```
   - TaskUpdate(postCommentTaskId, status: "completed", result: "PASS — resolution comment posted to PR")
9. **Conditional re-request review**:
   - If self-review found 0 findings → do NOT re-request (nothing changed that needs re-review beyond the feedback fixes)
   - If cycle < `reviewCycleLimit` (default 3) → re-request normally:
     ```bash
     gh pr edit $ARGUMENTS --add-reviewer @{reviewer}
     ```
   - If cycle >= `reviewCycleLimit` → use the AskUserQuestion tool: "Review cycle {N}. Options: re-request same reviewer, request fresh reviewer, or merge as-is?"

Display summary: fixes applied, Boy Scout improvements, questions answered, pushback items, cycle count.
