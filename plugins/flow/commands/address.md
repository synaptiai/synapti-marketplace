---
description: "Address PR review feedback systematically. Categorizes feedback, implements surgical fixes, verifies changes, and re-requests review."
argument-hint: <pr-number> [free-form context]
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute independent operations simultaneously.
-->

# Address Review Feedback for PR #$ARGUMENTS

Systematic feedback resolution. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `llm-operator-principles` — foundational operator stance: convergence = zero findings, in-PR fixes by default, no calendar-time estimates, narrow escalation triggers. MUST be consulted before any other phase
- `feedback-resolution` — surgical changes, context recovery, pushback criteria
- `change-classification` — verify no out-of-context changes
- `capability-discovery` — quality commands for verification
- `tdd-patterns` — test-first for fixes, test quality standards
- `holdout-validation` — cross-reference self-review claims against file state (Phase 4)

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 3's out-of-scope-finding escalation, Phase 4's review-cycle-limit escalation, and any Proactive-Autonomy escalation surfaced during feedback resolution
- [`references/finding-schema.md`](../references/finding-schema.md) — canonical row shape every reviewer agent dispatched in the Phase 4 re-review fan-out emits

## Phase 1: EXPLORE

`gh pr checkout` stays inline (mutating); read-only context-gathering is in the `!` block below.

```!
# Take the first whitespace-separated token; accept only if it is all digits.
# A non-numeric token (e.g., "foo42" or "evil;rm") is rejected with empty
# PR_NUM so it never reaches the prompt context or any downstream shell.
#
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`. STATE=blocked on bad input.
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac

echo "### PR Reference"
if [ -z "$PR_NUM" ]; then
  echo "STATE=blocked"
  echo "ERROR=PR number required (all-digit). Usage: /flow:address <pr-number>"
else
  echo "STATE=ok"
  echo "PR_NUM=$PR_NUM"

  # Section: PR Details
  echo ""
  echo "### PR Details"
  gh pr view "$PR_NUM" --json headRefName,baseRefName,title,body --jq '
    "TITLE=\"\(.title)\"\nHEAD_BRANCH=\(.headRefName)\nBASE_BRANCH=\(.baseRefName)\nBODY_LENGTH=\(.body | length)"
  ' 2>/dev/null

  # Section: Inline Review Comments
  echo ""
  echo "### Inline Review Comments"
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  # Capture gh exit separately. gh failure ⇒ "" + non-zero exit; jq on empty
  # stdin produces no output + exit 0, so `|| echo "0"` doesn't fire and the
  # block silently emits a bare `INLINE_COUNT=` line. Distinguish unavailable
  # (gh failed) from empty (gh ok, no records).
  INLINE_JSON=$(gh api "repos/$REPO/pulls/$PR_NUM/comments" 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    echo "INLINE_COUNT=0"
    echo "STATE=unavailable"
    INLINE_JSON="[]"  # neutral fallback so the Conversation Threads section below also degrades gracefully
  else
    INLINE_COUNT=$(echo "$INLINE_JSON" | jq 'length' 2>/dev/null)
    [ -z "$INLINE_COUNT" ] && INLINE_COUNT=0
    echo "INLINE_COUNT=$INLINE_COUNT"
    if [ "$INLINE_COUNT" = "0" ]; then
      echo "STATE=empty"
    else
      # One record per comment; full body lives in the JSON cache for the agent
      # to fetch on demand. The summary line carries the routing fields.
      echo "$INLINE_JSON" | jq -r '.[] | "INLINE_COMMENT=id=\(.id) author=@\(.user.login) path=\(.path) line=\(.line // "?") length=\(.body | length)"' 2>/dev/null
    fi
  fi

  # Section: Review Summaries
  echo ""
  echo "### Review Summaries"
  REVIEWS_JSON=$(gh pr view "$PR_NUM" --json reviews --jq '.reviews' 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    echo "REVIEW_COUNT=0"
    echo "STATE=unavailable"
  else
    REVIEW_COUNT=$(echo "$REVIEWS_JSON" | jq 'length' 2>/dev/null)
    [ -z "$REVIEW_COUNT" ] && REVIEW_COUNT=0
    echo "REVIEW_COUNT=$REVIEW_COUNT"
    if [ "$REVIEW_COUNT" = "0" ]; then
      echo "STATE=empty"
    else
      echo "$REVIEWS_JSON" | jq -r '.[] | "REVIEW=state=\(.state) author=@\(.author.login) at=\(.submittedAt) length=\(.body | length)"' 2>/dev/null
    fi
  fi

  # Section: Conversation Threads (grouped by file path)
  echo ""
  echo "### Conversation Threads"
  THREADS=$(echo "$INLINE_JSON" | jq -r 'group_by(.path) | .[] | "THREAD=file=\(.[0].path) count=\(length)"' 2>/dev/null)
  if [ -z "$THREADS" ]; then
    echo "STATE=empty"
  else
    echo "$THREADS"
  fi
fi

true
```

Then check out the PR branch (mutating, runs inline):

```bash
gh pr checkout "$PR_NUM"
```

**Agent(Explore)**: "Pre-resolve check — for each review comment, verify the feedback still applies to the current code. Some comments may already be addressed by later commits."

**Skill(capability-discovery)**: Discover quality commands for verification.

### FlowRun (v3 runtime)

Addressing review feedback is a long-running workflow, so it gets a durable FlowRun. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_RUN_STATE=blocked"
  echo "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
if [ "$RUNTIME_ENABLED" != "true" ]; then
  echo "FLOW_RUN_STATE=skip"
  echo "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-address"
  echo "FLOW_RUN_STATE=create"
  echo "RUN_ID=$RUN_ID"
  echo "WORKFLOW=address-pr"
  echo "INITIAL_PHASE=preflight"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`address-pr`, goal=`null`), initial phase `preflight`. Phase order: `preflight → categorize → resolve → verify`. Address is **FlowRun-only — it creates NO FlowGoal**: the PR's own review-thread state (resolved comments, re-request status, cycle history) is the durable record of feedback resolution, so there is no separate acceptance-criteria contract to evaluate.

## Review Cycle Tracking

```!
# Digit-validate PR_NUM (matches Phase 1 block).
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac

echo "### Review Cycle"
if [ -z "$PR_NUM" ]; then
  echo "STATE=blocked"
  echo "ERROR=PR number required (all-digit)"
else
  echo "STATE=ok"
  CYCLE_COUNT=$(gh pr view "$PR_NUM" --json reviews --jq '[.reviews[] | select(.state == "CHANGES_REQUESTED")] | length' 2>/dev/null)
  echo "PR_NUM=$PR_NUM"
  echo "REVIEW_CYCLE=$CYCLE_COUNT"
fi

true
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

**FlowActivity writes** (when `FLOW_RUN_STATE=create`): invoke `Skill(run-state-management)` to record one FlowActivity per resolved finding as each fix lands, and invoke `Skill(goal-evidence-ledger)` to capture the verification-evidence sidecar (the test/quality output that proves the fix) attached to the FlowRun — not a goal, since address is FlowRun-only. Each activity write advances `state.current_phase` per the `preflight → categorize → resolve → verify` order.

For **Question** items: prepare a response comment (no code change needed).

For **Pushback** items: explain reasoning in response comment.

For **Out-of-scope** items — finding triage is NEVER a valid escalation trigger; the default action for every finding is fix in this PR:

A finding in a file the PR already modifies is NEVER out-of-scope — it must be fixed in this PR (Boy Scout Rule + ownership of known defects in touched files).

P1 or P2 findings in untouched files must be addressed in-PR (expand scope with an `improve:` commit if the fix is bounded). They MUST NOT be filed as a six-field Proactive-Autonomy escalation — finding triage is not a decision, it is work. See `skills/llm-operator-principles/SKILL.md`.

**Default mode (no `minimalScope` set):** cosmetic P3 findings in truly untouched files are fixed if bounded (<10 lines) or documented inline in the PR body under a `### Known cosmetic notes` section. Do NOT create follow-up issues, do NOT use AskUserQuestion to ask whether to defer.

**Minimal-scope mode (`settings.json` → `minimalScope: true`, or user said "minimal scope" in-conversation):** for cosmetic P3 findings in truly untouched files only, the original follow-up workflow is restored:

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

Even in minimal-scope mode, P1 and P2 findings in untouched files are always fixed in-PR.

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
4. **Convergence check** (bounded by `fixForwardMaxIterations`, default 10 — this is a safety net against true infinite loops, NOT a planned stop point; see `skills/llm-operator-principles/SKILL.md`):
   - Self-review finds P1 → fix NOW (don't re-request with known P1s)
   - Holdout-validation finds P1/P2 → fix NOW (same blocking treatment as self-review P1)
   - P2 in touched files → fix NOW
   - P3 in touched files → fix NOW (same disposition as P1/P2 — the proximity test is not a deferral mechanism)
   - P1/P2 in untouched files → fix in-PR (expand scope with `improve:` commits). Finding triage is NEVER a valid escalation trigger.
   - Cosmetic P3 in untouched files → fix if bounded (<10 lines) or document inline in PR body. Default mode does not create follow-up issues. (Only `minimalScope` mode restores the follow-up workflow for this case.)
   - After fixes: re-run quality commands, re-review changed files, re-run holdout-validation
   - Approaching the iteration ceiling without convergence is a signal to re-check your understanding (are two findings in tension? are you fixing the wrong thing?), not to escalate the remaining findings.
   - **Genuine non-convergence** (terminal case): iteration `fixForwardMaxIterations` is reached AND the same findings persist across the last 3 iterations with no progress (or fixes oscillate — fix A flags B, fix B flags A). Halt the loop, do not silently exceed the ceiling, do not push with known unresolved P1/P2. File a six-field Proactive-Autonomy escalation citing the **"genuinely ambiguous architecture decision"** trigger (NOT finding-triage), naming the specific finding(s) in irreconcilable tension. See `skills/llm-operator-principles/SKILL.md` § Genuine non-convergence and `references/escalation-format.md`.
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
   gh api "repos/$REPO/pulls/$PR_NUM/comments/{comment_id}/replies" \
     -f body="Addressed in \`{SHA}\`. {brief description of fix}"

   # For Question/Pushback items, reply with the response:
   gh api "repos/$REPO/pulls/$PR_NUM/comments/{comment_id}/replies" \
     -f body="{response text}"
   ```
9. **Post resolution comment** (MANDATORY) using the template structure from `templates/resolution-comment.md`:
   ```bash
   gh pr comment "$PR_NUM" --body "$BODY"
   ```
   - TaskUpdate(postCommentTaskId, status: "completed", result: "PASS — resolution comment posted to PR")
10. **Update PR body review cycle state** (if `### Review Cycle History` exists in the PR body):
   - Fetch current body: `gh pr view "$PR_NUM" --json body --jq '.body'`
   - If the body contains `### Review Cycle History`, replace content between that heading and the next `##` heading with the cycle metrics table (received/fixed/discussed/escalated)
   - If the heading does not exist, append a `### Review Cycle History` section under `## Review Findings`
   - Update: `gh pr edit "$PR_NUM" --body "$UPDATED_BODY"`
11. **TaskList**: Confirm ALL tasks complete including "Post resolution comment". Do NOT proceed until verified.
12. **Conditional re-request review**:

    ONLY after TaskList confirms "Post resolution comment" is completed:
    - If self-review found 0 findings → do NOT re-request (nothing changed that needs re-review beyond the feedback fixes)
    - If cycle < `reviewCycleLimit` (default 10) → re-request normally:
      ```bash
      gh pr edit "$PR_NUM" --add-reviewer @{reviewer}
      ```
    - If cycle >= `reviewCycleLimit` → this signals genuine review deadlock (not a finding-triage decision). Use the AskUserQuestion tool with the following Proactive-Autonomy escalation:

      **Situation**: Review cycle {N} reached the configured limit (`reviewCycleLimit`). {remaining_count} finding(s) remain unresolved across {N} review-and-address cycles — this is a deadlock between reviewer and author, not a finding-triage question.
      **Tried**: {N} cycles of review-and-address with the current reviewer.
      **Options**:
        1. Re-request the same reviewer for another cycle
        2. Request a fresh reviewer for an independent perspective
        3. Explicit override — accept risk of open findings (requires written justification that will be recorded in the PR)
      **Recommendation**: Option 2 (fresh reviewer) — breaks potential deadlock while maintaining quality gate integrity.
      **Blocking?**: Yes — PR cannot merge until findings are resolved or explicitly overridden with justification.
      **Risk**: Merging with unresolved findings violates the "no incomplete shipments" hard boundary. Open findings become production defects owned by the team.

      Present via AskUserQuestion: "Review cycle {N} has reached the limit with {remaining_count} unresolved finding(s). Choose a path forward:"
        - Option 1: "Re-request same reviewer"
        - Option 2: "Request fresh reviewer"
        - Option 3: "Override with written risk acceptance (will be recorded on PR)"

Display summary: fixes applied, Boy Scout improvements, questions answered, pushback items, cycle count.

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): once all findings are resolved and the resolution comment is posted, invoke `Skill(run-state-management)` to transition the FlowRun to `state.status: completed`. The `workflow-run` journal artifact is best-effort because address is PR-scoped: emit `bin/journal-record.sh --type workflow-run` only if a single issue can be inferred from the PR (e.g., the PR closes exactly one issue); otherwise the `run.yaml` is the durable record. If feedback resolution fails or is cancelled, transition to `state.status: cancelled` (with `blocked_reason`) instead so `/flow:resume` does not treat it as resumable.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read PR comments / inline reviews | 1 | Autonomous |
| File edits (fix per feedback item) | 1 | Autonomous |
| Commits (`fix:` and `improve:` Boy Scout) | 1 | Autonomous, logged by hook |
| Push | 2 | Journal-and-proceed |
| Post resolution comment | 2 | Journal-and-proceed |
| Inline replies to review comments | 2 | Journal-and-proceed |
| Re-request review | 2 | Journal-and-proceed |
| Follow-up issue creation (cosmetic P3 in untouched files only) | 2 | Journal-and-proceed |
