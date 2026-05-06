---
description: "Review a pull request with multi-faceted analysis. Supports both single-session parallel review and agent team adversarial review."
argument-hint: <pr-number>
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute independent operations simultaneously.
-->

# Review PR #$ARGUMENTS

Multi-faceted code review with parallel analysis. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `code-review-methodology` — 6-facet review, finding synthesis, adversarial protocol
- `holdout-validation` — cross-reference self-review claims against file state (Phase 3)

## Phase 1: EXPLORE

**Parallel operations:**

```bash
# 1. PR details
gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName,changedFiles,additions,deletions,labels,author,reviews

# 2. Linked issue
gh pr view $ARGUMENTS --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#'

# 3. Previous reviews (follow-up detection)
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | "\(.state) by \(.author.login)"'

# 4. Checkout PR branch
gh pr checkout $ARGUMENTS

# 5. Diff
gh pr diff $ARGUMENTS --name-only
```

**Agent(Explore)**: "Read the changed files in this PR and understand the context. What modules are affected? What patterns are being followed or changed?"

Check for previous reviews — if this is a follow-up review, focus on changes since last review.

**Parse structured findings from previous review/resolution cycles** (follow-up reviews only):

```bash
# Parse previous review findings (from review bodies)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api repos/$REPO/pulls/$ARGUMENTS/reviews --jq '
  [.[] | select(.body | test("FLOW_REVIEW_CYCLE")) | {
    cycle: (.body | capture("FLOW_REVIEW_CYCLE:(?<n>[0-9]+)") | .n),
    findings: (.body | capture("FINDINGS:\\[(?<f>[^\\]]+)\\]") | .f)
  }]'

# Parse previous resolution outcomes (from issue comments posted via gh pr comment)
gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '
  [.[] | select(.body | test("FLOW_RESOLUTION_CYCLE")) | {
    cycle: (.body | capture("FLOW_RESOLUTION_CYCLE:(?<n>[0-9]+)") | .n),
    resolved: (.body | capture("RESOLVED:\\[(?<r>[^\\]]*?)\\]") | .r),
    escalated: (.body | capture("ESCALATED:\\[(?<e>[^\\]]*?)\\]") | .e)
  }]'
```

If previous cycles exist, build a **Previous Feedback Status** table and cross-reference each finding's location against `git diff` to verify resolution.

## Phase 2: PLAN

```
TaskCreate("Security review", "Check for OWASP top 10, secrets, injection, auth/authz")
TaskCreate("Code quality review", "Logic correctness, edge cases, error handling")
TaskCreate("Convention review", "Commit format, branch naming, code patterns")
TaskCreate("Test review", "Run quality commands, assess test coverage")
TaskCreate("Requirements review", "Map acceptance criteria to implementation")
TaskCreate("Error handling review", "Check for unhandled exceptions, silent failures, missing edge cases")
TaskCreate("Holdout validation", "Cross-reference self-review claims against actual file state using holdout scenarios")
```

## Phase 3: CODE (Review Execution)

### Path A: Agent Teams (when `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is set)

Implements the paired-reviewer + challenge-round protocol frozen in `.decisions/issue-86.md`. Invoke `team-coordination` skill for the protocol contract.

**Gate check** (mandatory before paired dispatch):

```bash
# Read agentTeams from settings (cascade: project < user < plugin defaults).
# Note: agentTeams is NOT pinned to plugin tier — it's a feature flag, not a
# security key like markerTrust. Cascade is appropriate here.
AGENT_TEAMS=$(jq -r '.agentTeams // false' plugins/flow/settings.json 2>/dev/null)

if [ "$AGENT_TEAMS" != "true" ]; then
  echo "Path A skipped: agentTeams=false. Using Path B (single-session)."
  USE_PATH_A=0
elif [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  echo "WARN: agentTeams enabled but CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var unset; using single-reviewer fallback (Path B)" >&2
  USE_PATH_A=0
else
  USE_PATH_A=1
fi
```

If `USE_PATH_A=0`, skip the rest of Path A and dispatch Path B below.

#### A.1 — Independent Analysis (paired reviewers, parallel dispatch)

Dispatch **12 subagents** in a single parallel Agent block — 6 facets × {skeptic, verifier}. Each variant carries an orthogonal lens; both run with no awareness of each other.

```
Agent(security-reviewer-skeptic):
  "You are reviewing PR #$ARGUMENTS as the SKEPTIC variant. Assume the diff is
   broken until proven otherwise. Flag every security behavior you cannot prove
   correct from the code as written: OWASP Top 10, secrets, auth/authz, input
   validation, dependency vulnerabilities. Return P1/P2/P3 findings with
   file:line citations and category. Do NOT include challenge information —
   another reviewer will challenge your findings later."

Agent(security-reviewer-verifier):
  "You are reviewing PR #$ARGUMENTS as the VERIFIER variant. Assume the diff is
   correct as a baseline. Look only for missed security edge cases, undocumented
   contract assumptions, or invariants that aren't enforced. Return P1/P2/P3
   findings with file:line citations and category."

Agent(code-reviewer-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Assume broken; flag logic/quality/edge-case
   issues you cannot prove correct. P1/P2/P3 + file:line + category."

Agent(code-reviewer-verifier):
  "PR #$ARGUMENTS as VERIFIER. Assume correct; look only for missed edge cases
   and unenforced invariants. P1/P2/P3 + file:line + category."

Agent(convention-checker-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Flag every convention violation (commits, branch
   naming, code patterns) you cannot prove conformant. P1/P2/P3 + file:line."

Agent(convention-checker-verifier):
  "PR #$ARGUMENTS as VERIFIER. Look for convention drift the skeptic might miss
   (e.g., subtle stylistic divergence). P1/P2/P3 + file:line."

Agent(test-runner-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Run quality commands (lint, test, typecheck) and
   flag every failure or warning. Return findings with command output."

Agent(test-runner-verifier):
  "PR #$ARGUMENTS as VERIFIER. Run quality commands and flag missing test
   coverage or weak assertions in passing tests. Return findings."

Agent(error-handler-inspector-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Flag every error-handling gap, silent failure,
   or unhandled exception you cannot prove handled. P1/P2/P3 + file:line."

Agent(error-handler-inspector-verifier):
  "PR #$ARGUMENTS as VERIFIER. Look for missed error contracts and unenforced
   exception invariants. P1/P2/P3 + file:line."

Skill(holdout-validation):
  Inputs (skeptic lens):
  - Self-review findings: {existing P1/P2/P3 findings}
  - Evidence bundle draft: {requirements compliance map}
  - File list: {all files changed in this PR}
  - Lens: SKEPTIC — assume claims are unsupported until proven

Skill(holdout-validation):
  Inputs (verifier lens):
  - Same inputs
  - Lens: VERIFIER — assume claims are supported; look for missed cross-references
```

Each returns a structured finding list. Index returned findings by facet for the challenge round: `findings[facet][variant] = [F1, F2, ...]`.

#### A.2 — Auto-consensus detection

Before dispatching the challenge round, detect findings that BOTH variants raised independently. The match window is hard-coded for v1: same facet AND same file AND lines within ±2 AND priority within ±1 (P1↔P2 counts; P1↔P3 does not).

```bash
# Pseudocode (apply per facet):
# for finding_a in findings[facet][skeptic]:
#   for finding_b in findings[facet][verifier]:
#     if same_file(finding_a, finding_b) AND
#        abs(line(finding_a) - line(finding_b)) <= 2 AND
#        priority_distance(finding_a.priority, finding_b.priority) <= 1:
#       mark both as auto-consensus -> confidence=HIGH, disposition=consensus
#       remove both from challenge candidates
```

Auto-consensus findings skip the challenge round (no need — both reviewers already agreed independently).

#### A.3 — Challenge Round (disposition-only, parallel)

For findings NOT in auto-consensus, dispatch each variant to challenge the OTHER variant's findings. **Variants do NOT re-read the diff.** Up to 12 challenge prompts run in parallel (6 facets × 2 directions).

```
Agent(security-reviewer-skeptic) [challenge mode]:
  "You are reviewer-A (skeptic) for facet 'security'. Reviewer-B (verifier)
   raised the following findings on the same diff you reviewed independently.
   For each finding, respond with exactly one line:

     {finding-id} AGREE
     {finding-id} DISAGREE: {one-line reason}
     {finding-id} REFINE: priority={P1|P2|P3} category={text}

   Do NOT re-read the diff. Decide based on your prior independent analysis only.

   Findings to challenge:
   {list of verifier's non-auto-consensus findings: ID, file:line, priority, category}"

Agent(security-reviewer-verifier) [challenge mode]:
  "Same instructions, reversed: challenge the skeptic's non-auto-consensus
   findings for facet 'security'."

[... repeat for the other 5 facets in parallel ...]
```

Each challenge call returns a list of `{finding-id, disposition, optional reason/refinement}`.

#### A.4 — Consolidation

Apply the consolidation table from `team-coordination/SKILL.md` Phase 4. For each finding, look up its origin and the other variant's disposition:

| Origin | Other variant's disposition | Confidence | Marker disposition vocab |
|--------|------------------------------|------------|--------------------------|
| Auto-consensus (A.2) | n/a | **HIGH** | `consensus` |
| One raised, other AGREE | AGREE | **HIGH** | `validated` |
| One raised, other REFINE | REFINE | **MEDIUM** | `refined` (use REFINE'd priority/category) |
| One raised, other DISAGREE | DISAGREE | **LOW** | `kept` (record reason) |
| One raised, other timed out / errored | none | **MEDIUM** | `unchallenged` |
| Both raised, both DISAGREE'd | n/a | **DROPPED** | excluded from output, logged below |

**DROPPED findings** are logged to `.decisions/issue-{N}.md` (where N = the issue this PR addresses) under a `## Dropped after challenge (PR #$ARGUMENTS, cycle {N})` heading with the finding details and both DISAGREE reasons. They never appear in the rendered tables or the FLOW_REVIEW_CYCLE marker.

#### A.5 — Per-facet fallback application

If any of A.1's variants failed (timeout, error, did-not-spawn), apply the fallback semantics from `team-coordination/SKILL.md` per facet — never block the review:

| Failure | Action |
|---------|--------|
| One variant failed for facet F | Use the responding variant's findings only; mark each as `unchallenged` (MEDIUM). Note in output: `facet F: single-reviewer fallback (skeptic failed)`. |
| Both variants failed for facet F | Re-dispatch single Agent for that facet using the Path B prompt. Note in output: `facet F: re-dispatched as single-reviewer (both variants failed)`. |
| Challenge round failed for a facet | Skip A.3 for that facet; keep A.1 findings as `unchallenged`. Note in output: `facet F: challenge skipped (challenge prompt failed)`. |

#### A.6 — Emit consolidated output

Use the synthesized findings (with confidence + disposition) for steps in Phase 4 below. The FLOW_REVIEW_CYCLE marker emitted in Phase 4.7 uses the 7-field form when paired-reviewer mode produced the findings:

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[F1|P1|security|src/auth.ts:42|open|HIGH|consensus,F2|P1|correctness|src/api.ts:88|open|LOW|kept] -->
```

The 5-field form is preserved for Path B (single-session) and for any per-facet fallback that produced findings without challenge data.

After A.6 completes, jump to Phase 4 with the consolidated finding set.

### Path B: Single Session (default)

**Parallel Agent dispatch** — 5 agents in single message:

```
Agent(code-reviewer):
  "Review PR #$ARGUMENTS diff for quality, logic, edge cases, security.
   Return P1/P2/P3 findings with file:line."

Agent(convention-checker):
  "Validate commits, branch naming, conventions for PR #$ARGUMENTS."

Agent(test-runner):
  "Run quality commands for PR #$ARGUMENTS branch."

Agent(error-handler-inspector):
  "Inspect changed files in PR #$ARGUMENTS for error handling gaps,
   silent failures, unhandled exceptions. Return P1/P2/P3 findings."

Agent(security-reviewer):
  "Review PR #$ARGUMENTS diff for OWASP Top 10, secrets, auth/authz,
   input validation, dependency vulnerabilities. Return P1/P2/P3 with file:line."

Skill(holdout-validation):
  Inputs:
  - Self-review findings: {P1/P2/P3 findings from code-reviewer agent}
  - Evidence bundle draft: {per-criterion evidence from requirements review}
  - File list: {all files changed in this PR}
```

**Main thread**: Requirements compliance — map acceptance criteria to implementation.

TaskUpdate each review task as agents complete.

## Phase 4: VERIFY

**CRITICAL: Posting review findings to the PR is MANDATORY. NEVER skip posting. The review is not complete until `gh pr review` has been executed and TaskUpdate confirms the post task is completed. Do not suggest next steps until posting is verified.**

1. **TaskList**: Confirm all review facets complete
2. **Synthesize findings**: Deduplicate by file:line, prioritize P1/P2/P3
3. **Display findings** (finding-first pattern):

```markdown
## Review Summary for PR #$ARGUMENTS

### Findings: P1: {X}, P2: {Y}, P3: {Z}

### P1 — Critical
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|

### Requirements Adherence
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
```

4. **Determine review mode** — compare PR author vs current user:

   ```bash
   PR_AUTHOR=$(gh pr view $ARGUMENTS --json author --jq '.author.login')
   CURRENT_USER=$(gh api user --jq '.login')
   ```

5. **Self-review (own PR — PR_AUTHOR == CURRENT_USER)**:

   Fix-forward approach (max `fixForwardMaxIterations`, default 2):
   - P1 findings → fix immediately
   - P2 findings → fix immediately
   - P3 findings → fix immediately (the proximity test is not a deferral mechanism — P3 in touched files gets the same disposition as P1/P2)
   - TaskCreate("Test coverage for fix-forward", "Write or update tests for each P1/P2/P3 fix applied during self-review")
   - For each fix: write or update a test that covers the fixed behavior
   - After fixes: run targeted re-review of only changed files
   - TaskUpdate(testCoverageTaskId, status: "completed", result: "Tests written/updated for {N} fixes")
   - No follow-up issue creation for fixable items — just fix them
   - If any P1/P2 finding cannot be fixed in-PR, file a six-field Proactive-Autonomy escalation (Situation / Tried / Options / Recommendation / Time sensitivity / Risk) rather than deferring silently
   - TaskCreate("Post self-review comment", "Post review findings summary to PR via gh pr review --comment")

6. **External review (someone else's PR — PR_AUTHOR != CURRENT_USER)**:

   - TaskCreate("Post review comment", "Post structured review findings to PR via gh pr review")
   - P1/P2/P3 in already-touched files → REQUEST_CHANGES (P1/P2) or COMMENT with fix-expected language (P3) — the author must fix or file an escalation
   - Cosmetic P3 in untouched files → follow-up issue workflow
   - P1/P2 in untouched files → REQUEST_CHANGES; author must address in-PR or file a six-field Proactive-Autonomy escalation

   Findings in files the PR already modifies are NEVER out-of-scope — the author owns the known defects in any file they touch. Do NOT flag them as informational; flag them as blocking.

   For cosmetic P3 findings in untouched files that warrant follow-up:
   Present the findings and use the AskUserQuestion tool with contextual options: "These cosmetic P3 findings are in untouched files. Which ones should become follow-up issues?"

   For each selected finding, create a GitHub issue using issue-crafting skill knowledge:
   - Title: concise, solution-agnostic description of the finding
   - Body: Context, Current State (file:line), Objective, Acceptance Criteria
   - Labels: select from repo labels based on finding category
   - Issue creation is Tier 2 (journal-and-proceed)

   ```bash
   gh issue create --title "{title}" --body "{body}" --label "{labels}"
   ```

   Include created issue numbers in the review comment body.

   **Note**: Reviewers should recognize `improve:` commits as legitimate Boy Scout cleanup — approve if they pass the proximity test.

7. **Post review findings** (MANDATORY — applies to both self-review and external review):

   For follow-up reviews, include the **Previous Feedback Status** table:
   ```markdown
   ### Previous Feedback Status
   | Cycle | Finding | Priority | Claimed Status | Verified |
   |-------|---------|----------|----------------|----------|
   ```
   Cross-reference each prior finding's location against `git diff` to verify resolution.

   Build `$BODY` using the appropriate template:
   - Self-review: `templates/self-review-comment.md`
   - External review: `templates/review-comment.md`

   **Marker form selection** (FLOW_REVIEW_CYCLE):
   - If Path A produced the findings (paired-reviewer mode), emit the **7-field** marker with Confidence + Disposition fields per finding. Render the Confidence + Disposition columns in the P1/P2/P3 tables.
   - If Path B produced the findings (single-session, fallback, or `agentTeams: false`), emit the legacy **5-field** marker. Omit the Confidence + Disposition columns.
   - When Path A had per-facet fallbacks, individual findings from fallback facets carry `unchallenged` disposition with MEDIUM confidence — emit them in the 7-field form alongside the rest. Mixed-form rows within a single marker are NOT permitted (parsers tolerate variable field count, but emitting both forms in one row list would be confusing); pad fallback findings to 7 fields with `MEDIUM|unchallenged`.

   Post the review:
   - Self-review → `gh pr review $ARGUMENTS --comment --body "$BODY"`
   - External + P1 findings → `gh pr review $ARGUMENTS --request-changes --body "$BODY"`
   - External + P2 findings (no P1) → `gh pr review $ARGUMENTS --request-changes --body "$BODY"`
   - External + P3 only → `gh pr review $ARGUMENTS --comment --body "$BODY"` (fix-expected, not approve-with-nits)
   - External + No findings → `gh pr review $ARGUMENTS --approve --body "$BODY"`

   TaskUpdate(postCommentTaskId, status: "completed", result: "PASS — review posted as {approve/request-changes/comment}")

8. **Verify posting**: TaskList — confirm "Post review comment" or "Post self-review comment" task is completed. Do NOT proceed to step 9 until this is verified.

9. **Post-review**: If self-review fixed everything, suggest `/flow:pr`. If external review, suggest `/flow:address $ARGUMENTS` for the PR author.
