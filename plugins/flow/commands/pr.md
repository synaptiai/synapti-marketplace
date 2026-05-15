---
description: "Create a pull request with full code review, quality gates, comprehension report, and reviewer suggestions. Runs parallel agent review before PR creation."
argument-hint: [title]
allowed-tools: Bash(git branch *) Bash(git status *) Bash(git rev-list *) Bash(git diff *) Bash(git push *) Bash(git log *) Bash(gh repo view *) Bash(gh issue view *) Bash(gh issue list *) Bash(gh pr list *) Bash(gh pr view *) Bash(gh pr create *) Bash(gh pr edit *) Bash(cat *) Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh:*) Bash(grep *) Bash(echo *) Bash(sed *) Read Write Edit Agent AskUserQuestion TaskCreate TaskList TaskUpdate Skill Grep Glob
---

<!--
EXECUTION MODEL:
Phase 1 EXPLORE bash is pre-executed via the `!` prefix at command load — no
Bash tool round-trip. Phase 2 `git diff` and Phase 4 actions (push, gh pr
create, journal-record emit) stay inline because the diff can be huge and the
actions depend on LLM-generated values + user confirmation.
-->

# Create Pull Request

Full PR creation workflow with multi-faceted review, quality gates, and structured PR body. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `pr-lifecycle` — pre-flight, PR body, reviewer suggestion
- `code-review-methodology` — 6-facet review synthesis
- `capability-discovery` — detect quality commands and agents
- `holdout-validation` — cross-reference self-review claims against file state (Phase 3)

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 4's visual-verification BLOCKED escalation and any other Proactive-Autonomy escalation surfaced during PR creation
- [`references/finding-schema.md`](../references/finding-schema.md) — canonical row shape every reviewer agent dispatched in Phase 3 emits

## Phase 1: EXPLORE

Pre-executed at command load (`!` prefix injects output before the LLM reads
the prompt — no Bash tool round-trip required).

```!
# 1. Pre-flight checks
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
[ "$BRANCH" = "$DEFAULT_BRANCH" ] && echo "ERROR: Cannot create PR from default branch" && exit 1
echo "BRANCH=$BRANCH DEFAULT=$DEFAULT_BRANCH"

# 2. Commits and changes
git rev-list --count "$DEFAULT_BRANCH"..HEAD
git status --porcelain
git diff --stat "$DEFAULT_BRANCH"...HEAD

# 3. Issue context (branch name is git-validated, but quote defensively)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
[ -n "$ISSUE_NUM" ] && gh issue view "$ISSUE_NUM" --json title,body,labels
echo "ISSUE_NUM=$ISSUE_NUM"

# 4. Existing PR check
gh pr list --head "$BRANCH" --state open --json number,url

# 5. Decision journal
JOURNAL_DIR=".decisions"
[ -n "$ISSUE_NUM" ] && [ -f "$JOURNAL_DIR/issue-$ISSUE_NUM.md" ] && cat "$JOURNAL_DIR/issue-$ISSUE_NUM.md"

true  # explicit success — block exit reflects block intent, not the trailing optional conditional
```

**If pre-flight emitted `ERROR: Cannot create PR from default branch`, halt
without proceeding to Phase 2.**

**Skill invocation:** `Skill(capability-discovery)` — detect quality commands.

If uncommitted changes exist, offer to run `/flow:commit` first.
If PR already exists, offer to update instead.

## Phase 2: PLAN

Create review tasks:

```
TaskCreate("Code quality and logic review", "Review diff for logic errors, edge cases, error handling")
TaskCreate("Security scan", "Check for OWASP top 10, secrets, auth issues")
TaskCreate("Convention check", "Validate commits, branch naming, patterns")
TaskCreate("Quality commands", "Run lint, test, typecheck")
TaskCreate("Requirements compliance", "Map acceptance criteria to implementation")
TaskCreate("Error handling review", "Check for unhandled exceptions, silent failures, missing edge cases")
TaskCreate("Holdout validation", "Cross-reference self-review claims against actual file state using holdout scenarios")
```

If the diff includes UI-relevant files (`.tsx`, `.jsx`, `.vue`, `.html`, `.css`, `.scss`):
```
TaskCreate("Visual verification", "Verify UI renders correctly with screenshot analysis")
```

Add runtime verification task:
```
TaskCreate("Runtime verification", "Build, start, and smoke test before PR creation")
```

Get the diff for review:

```bash
git diff "$DEFAULT_BRANCH"...HEAD
```

## Phase 3: CODE (Review Execution)

**Parallel Agent dispatch** — 5 agents and skill in a single message (parity with `/flow:review` Path B):

```
Agent(code-reviewer):
  "Review the branch diff against $DEFAULT_BRANCH for code quality,
   logic correctness, edge cases, and security. Return P1/P2/P3 findings
   with file:line citations."

Agent(convention-checker):
  "Validate commit messages, branch naming, and code conventions
   against project standards. Return findings."

Agent(test-runner):
  "Discover and run quality commands (lint, test, typecheck).
   Return structured results table."

Agent(security-reviewer):
  "Review the branch diff against $DEFAULT_BRANCH for OWASP Top 10,
   secrets, auth/authz, input validation, dependency vulnerabilities.
   Return P1/P2/P3 findings with file:line."

Agent(error-handler-inspector):
  "Inspect changed files for error handling gaps, silent failures,
   unhandled exceptions. Return P1/P2/P3 findings."

Skill(holdout-validation):
  Inputs:
  - Self-review findings: {P1/P2/P3 from code-reviewer}
  - Evidence bundle draft: {requirements compliance map}
  - File list: {all files changed since branch creation}
```

**Main thread** (while agents run in parallel if using background agents, or after if foreground):
- Requirements compliance check: map acceptance criteria → implementation evidence
- TaskUpdate for requirements task

After agents return, TaskUpdate each review task with findings.

## Phase 4: VERIFY

1. **Synthesize findings**: Deduplicate by file:line, prioritize P1 > P2 > P3
2. **Integration verification** — dispatch Agent(integration-verifier):
   ```
   Agent(integration-verifier):
     "Verify runtime behavior for this branch. Invoke Skill(runtime-verification)
      for build, dev-server, smoke, E2E, and LSP diagnostics. If UI files changed,
      ALSO invoke Skill(visual-verification) in parallel for the screenshot-
      analyze-verify loop and responsive checks. Validate acceptance criteria at
      runtime. Return the verification results table per `skills/runtime-
      verification/SKILL.md` plus the visual table per `skills/visual-
      verification/SKILL.md`. Emit any findings using the canonical schema in
      `references/finding-schema.md`."
   ```
   After agent returns:
   - If visual verification task was created in Phase 2: `TaskUpdate(visualVerificationTaskId, status: "completed", result: "{agent's visual verification findings}")`
   - Record screenshot paths from agent results as evidence
3. **TaskList**: Confirm all review tasks complete (including visual verification if created)
4. **Runtime verification**: If integration-verifier returns SKIP without justification, run runtime verification directly (build, start, smoke test). Runtime verification must pass before PR creation.
5. **Visual verification enforcement**: If `visualVerification.requireVisualVerification` is `true` and integration-verifier returned visual verification as BLOCKED:
   - Use `AskUserQuestion` with a Proactive-Autonomy escalation:
     > **Situation** — Visual verification is required (`requireVisualVerification: true`) but no browser tools are available. UI files changed: {list}.
     >
     > **What I tried** — Checked for Playwright MCP, headless browser tools, and gstack. None available.
     >
     > **Options**:
     > 1. Skip visual verification — noted in PR body (Recommended if changes are minor CSS/copy)
     > 2. I will verify visually myself — marked as MANUAL in PR body
     > 3. Help me install browser tools — I'll provide Playwright MCP installation guidance and retry
     >
     > **Recommendation** — Option {1|2|3} based on scope of UI changes.
     >
     > **Time sensitivity** — Blocks PR creation if `requireVisualVerification: true`.
     >
     > **Risk** — Skipping may miss visual regressions. Manual verification depends on user follow-through.
   - Based on response → `TaskUpdate` visual tasks to SKIP_USER_APPROVED or MANUAL, or provide installation guidance and retry
   - The PR body should note whether visual verification was PASS, MANUAL, SKIP_USER_APPROVED, or SKIP_WARN
6. **Display findings** (finding-first pattern):
   - P1 findings → must fix before PR
   - P2 findings → fix before PR (max 2 fix iterations; after 2, remaining P2 become "Known issues" in PR body)
   - P3 findings → note in PR body
7. **If P1 findings**: Fix them, re-run review
8. **Generate PR body** from template + findings + journal + comprehension report.
   If visual verification ran, include visual evidence section:
   ```markdown
   ## Visual Verification
   | Page | Viewport | Status | Screenshot |
   |------|----------|--------|------------|
   ```
   Note: screenshots are local files; for remote visibility, mention "verified locally"
9. **Push** (Tier 2: journal-and-proceed):
   ```bash
   git push -u origin $BRANCH
   ```
10. **Create PR** (Tier 2):
    ```bash
    gh pr create --title "$TITLE" --body "$BODY"
    ```
11. **Suggest reviewers** using pr-lifecycle skill algorithm
12. **Verify**: `gh pr view --json number,url`
13. **Manifest emit** — record the review-cycle artifact for the parallel-review pass that ran during PR creation. Same emit shape as `commands/review.md` Phase 4 step 7 — the PR-creation flow runs an inline review and is morally a cycle:

    ```bash
    PR_NUMBER=$(gh pr view --json number --jq '.number')
    ISSUE=$(gh issue list --state open --search "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [ -z "$ISSUE" ]; then
      ISSUE=$(echo "$BRANCH" | grep -oE 'issue-([0-9]+)' | head -1 | sed 's/issue-//')
    fi
    if [ -n "$ISSUE" ]; then
      "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
        --issue $ISSUE \
        --type review-cycle \
        --metadata cycle=1 \
        --metadata path=B \
        --metadata findings_count=$TOTAL_FINDINGS \
        --metadata pr=$PR_NUMBER
    fi
    ```

    The emit is best-effort — if the issue cannot be inferred from the branch name, skip rather than fail. PR-creation flow uses Path B (single-session 5-agent dispatch); subsequent `/flow:review` invocations may re-emit with `path=A` if paired-reviewer mode is enabled.

Display PR URL and next steps.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Pre-flight checks (branch, commits, PR existence) | 1 | Autonomous; blocks on failure |
| Multi-agent review fan-out (5 reviewers + holdout-validation) | 1 | Autonomous; Tasks tracked |
| `Skill(integration-verifier)` runtime + visual verification | 1 | Autonomous |
| File edits (fix-forward for P1/P2 findings) | 1 | Autonomous |
| Commits (`fix:` from fix-forward) | 1 | Autonomous, logged by hook |
| `git push -u origin <branch>` | 2 | Journal-and-proceed |
| `gh pr create` | 2 | Journal-and-proceed |
| Visual-verification BLOCKED escalation (when `requireVisualVerification: true`) | 2 | Asks via `AskUserQuestion`; outcome journaled |
