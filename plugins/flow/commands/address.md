---
description: "Address PR review feedback systematically. Categorizes feedback, implements surgical fixes, verifies changes, and re-requests review."
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
- `tdd-patterns` — test-first for fixes, test quality standards
- `holdout-validation` — cross-reference self-review claims against file state (Phase 4)

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

TaskCreate(
  subject: "Test coverage for fixes",
  description: "Write or update tests for each feedback fix. At minimum one test per fix that would have caught the issue."
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
5. Write or update tests that verify the fix:
   - Follow existing test patterns (co-located files, same framework)
   - At minimum, write a test that would have caught the issue
   - Test the specific edge case, not just the happy path
   - Only modify the fix target and its test file
6. Verify the fix addresses the specific feedback and tests pass
7. Commit: git commit -m "fix(scope): address review — {summary}"
8. TaskUpdate(taskId, status: "completed")
```

**Boy Scout pass** — after all feedback fixes:
- Scan all modified files for lint/format/obvious issues that pass the proximity test
- If cycle >= 2, also scan the entire file for P1/P2 issues
- Fix any proximity-test-passing issues found
- Boy Scout fixes get separate `improve:` commits

TaskUpdate(testCoverageTaskId, status: "completed", result: "Tests written/updated for {N} fixes")

For **Question** items: prepare a response comment (no code change needed).

For **Pushback** items: explain reasoning in response comment.

For **Out-of-scope** items — the proximity test is NOT a deferral mechanism for P1/P2 findings:

A finding in a file the PR already modifies is NEVER out-of-scope — it must be fixed in this PR (Boy Scout Rule + ownership of known defects in touched files).

Only **cosmetic P3 findings in truly untouched files** may become follow-up issues by default. P1 or P2 findings in untouched files must either:

1. Be addressed in-PR (expand scope with an `improve:` commit if the fix is bounded), OR
2. Be filed as a six-field Proactive-Autonomy escalation:
   - **Situation**: what the finding is and where (file:line)
   - **Tried**: what you considered and why it didn't resolve in-PR
   - **Options**: 2–3 concrete paths forward with trade-offs
   - **Recommendation**: your recommended option with reasoning
   - **Time sensitivity**: is this blocking? urgent? safe to wait?
   - **Risk**: what happens if we defer, and to whom

For cosmetic P3 findings in untouched files that the team agrees to track separately:

1. Use the AskUserQuestion tool with contextual options: "This cosmetic P3 finding is in an untouched file. Create a follow-up issue to track it?"
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

**CRITICAL: The resolution comment and inline replies are MANDATORY. NEVER skip posting. Push without posting is incomplete — the reviewer cannot see what was addressed. Do not re-request review until the resolution comment is posted and TaskUpdate confirms completion.**

1. **Quality commands** (parallel): lint, test, typecheck
2. **Comprehensive self-review** of ALL files touched on the branch — parallel agent dispatch matching `/flow:pr` Phase 3 fan-out so fix commits don't slip convention/test/error-handling regressions past automated re-review:
   ```
   Agent(code-reviewer):
     "Review the fix commits since the last review against $DEFAULT_BRANCH.
      Check for: logic errors, security issues, missing edge cases.
      Return P1/P2/P3 findings with file:line."

   Agent(convention-checker):
     "Validate convention compliance for the fix commits since the last review.
      Check commit messages, branch naming, and code conventions against
      project standards. Return findings."

   Agent(test-runner):
     "Run quality commands (lint, test, typecheck); verify regressions
      haven't been introduced by the fix commits since the last review.
      Return structured results table."

   Agent(security-reviewer):
     "Review the fix commits since the last review against $DEFAULT_BRANCH
      for OWASP Top 10, secrets, auth/authz, input validation, and dependency
      vulnerabilities. Return P1/P2/P3 findings with file:line."

   Agent(error-handler-inspector):
     "Check error handling in the changed scope of the fix commits since
      the last review. Return P1/P2/P3 findings with file:line."
   ```

   This dispatch is the canonical re-review fan-out — exactly the same five
   reviewer agents `/flow:pr` Phase 3 dispatches. Keeping the agent list
   explicit here (rather than referencing pr.md by name) makes parity locally
   verifiable and prevents silent drift if either command's roster changes.
3. **Holdout validation** — after self-review, invoke `holdout-validation` to cross-reference claims against file state:
   ```
   Skill(holdout-validation):
     Inputs:
     - Self-review findings: {P1/P2/P3 findings from step 2}
     - Evidence bundle draft: {per-criterion evidence from feedback fixes}
     - File list: {all files modified on this branch}
   ```
   **Blocking treatment** (same as start.md):
   - P1/P2 holdout findings → fix immediately before proceeding
   - After fixes: re-run holdout-validation to confirm resolution
   - P3 findings → note, do not block
4. **Convergence check** (max 3 self-review-fix iterations):
   - Self-review finds P1 → fix NOW (don't re-request with known P1s)
   - Holdout-validation finds P1/P2 → fix NOW (same blocking treatment as self-review P1)
   - P2 in touched files → fix NOW
   - P3 in touched files → fix NOW (same disposition as P1/P2 — the proximity test is not a deferral mechanism)
   - Only truly cosmetic P3 findings in untouched files may become follow-up issues; P1/P2 in untouched files must be addressed in-PR or filed as a six-field Proactive-Autonomy escalation (Situation / Tried / Options / Recommendation / Time sensitivity / Risk)
   - After fixes: re-run quality commands, re-review changed files, re-run holdout-validation
5. **Verify Boy Scout cleanup** passes proximity test (no scope creep)
6. **Change classification** — verify no out-of-context changes introduced
7. **Push** (Tier 2: journal-and-proceed):
   ```bash
   git push
   ```
8. **Reply to individual review comments** inline:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   # For each fixed item, reply to the original review comment:
   gh api repos/$REPO/pulls/$ARGUMENTS/comments/{comment_id}/replies \
     -f body="Addressed in \`{SHA}\`. {brief description of fix}"

   # For Question/Pushback items, reply with the response:
   gh api repos/$REPO/pulls/$ARGUMENTS/comments/{comment_id}/replies \
     -f body="{response text}"
   ```
9. **Post resolution comment** (MANDATORY) using the template structure from `templates/resolution-comment.md`:
   ```bash
   gh pr comment $ARGUMENTS --body "$BODY"
   ```
   - TaskUpdate(postCommentTaskId, status: "completed", result: "PASS — resolution comment posted to PR")
10. **Update PR body review cycle state** (if `### Review Cycle History` exists in the PR body):
   - Fetch current body: `gh pr view $ARGUMENTS --json body --jq '.body'`
   - If the body contains `### Review Cycle History`, replace content between that heading and the next `##` heading with the cycle metrics table (received/fixed/discussed/escalated)
   - If the heading does not exist, append a `### Review Cycle History` section under `## Review Findings`
   - Update: `gh pr edit $ARGUMENTS --body "$UPDATED_BODY"`
11. **TaskList**: Confirm ALL tasks complete including "Post resolution comment". Do NOT proceed until verified.
12. **Conditional re-request review**:

    ONLY after TaskList confirms "Post resolution comment" is completed:
    - If self-review found 0 findings → do NOT re-request (nothing changed that needs re-review beyond the feedback fixes)
    - If cycle < `reviewCycleLimit` (default 3) → re-request normally:
      ```bash
      gh pr edit $ARGUMENTS --add-reviewer @{reviewer}
      ```
    - If cycle >= `reviewCycleLimit` → use the AskUserQuestion tool with the following Proactive-Autonomy escalation:

      **Situation**: Review cycle {N} reached the configured limit (`reviewCycleLimit`). {remaining_count} finding(s) remain unresolved.
      **Tried**: {N} cycles of review-and-address with the current reviewer.
      **Options**:
        1. Re-request the same reviewer for another cycle
        2. Request a fresh reviewer for an independent perspective
        3. Explicit override — accept risk of open findings (requires written justification that will be recorded in the PR)
      **Recommendation**: Option 2 (fresh reviewer) — breaks potential deadlock while maintaining quality gate integrity.
      **Time sensitivity**: Blocking — PR cannot merge until findings are resolved or explicitly overridden with justification.
      **Risk**: Merging with unresolved findings violates the "no incomplete shipments" hard boundary. Open findings become production defects owned by the team.

      Present via AskUserQuestion: "Review cycle {N} has reached the limit with {remaining_count} unresolved finding(s). Choose a path forward:"
        - Option 1: "Re-request same reviewer"
        - Option 2: "Request fresh reviewer"
        - Option 3: "Override with written risk acceptance (will be recorded on PR)"

Display summary: fixes applied, Boy Scout improvements, questions answered, pushback items, cycle count.
