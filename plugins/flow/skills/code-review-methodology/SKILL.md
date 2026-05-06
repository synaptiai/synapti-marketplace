---
name: code-review-methodology
description: "Conduct two-stage code review: Stage 1 verifies spec compliance (criterion-to-code mapping), Stage 2 evaluates security, correctness, performance, and maintainability across 6 parallel facets with P1/P2/P3 synthesis and deduplication by file:line. Use when reviewing code changes or pull requests. This skill MUST be consulted because reviewing quality on broken logic is wasted effort, and unmet acceptance criteria must block merge."
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
---

# Code Review Methodology

Domain skill for structured, multi-faceted code review.

## Iron Law

**FIRST VERIFY IT WORKS, THEN VERIFY IT'S GOOD. Never review code quality on code that doesn't function correctly.**

Spec compliance is Stage 1. Code quality is Stage 2. Reviewing style on broken logic is wasted effort.

## Two-Stage Review

**Stage 1 — Spec Compliance**: Does the code do what the issue/acceptance criteria require? Map each criterion to implementation evidence. If Stage 1 fails, stop — no point reviewing quality on code that doesn't meet requirements.

**Stage 2 — Code Quality** (in priority order):
1. **Security** — vulnerabilities, auth bypass, injection, secrets
2. **Correctness** — logic errors, race conditions, edge cases
3. **Performance** — O(n^2) in hot paths, unnecessary allocations, N+1 queries
4. **Maintainability** — readability, naming, structure (lowest priority)

Do NOT flag maintainability issues if security or correctness issues exist. Fix the important things first.

## 6-Facet Review

Every review evaluates these facets (parallelizable):

| Facet | Focus | Agent / Skill |
|-------|-------|---------------|
| **Security** | OWASP top 10, secrets, auth/authz, input validation | security-reviewer |
| **Quality** | Logic correctness, edge cases | code-reviewer |
| **Conventions** | Commit format, branch naming, PR structure, patterns | convention-checker |
| **Tests** | Coverage, quality commands pass, test quality | test-runner |
| **Error handling** | Unhandled errors, silent failures, missing edge cases in error paths | error-handler-inspector |
| **Claim verification** | Self-review claims cross-referenced against actual file state | holdout-validation (skill) |

Requirements compliance is Stage 1 (Spec Compliance) of the Two-Stage Review section above, not a parallel facet — it runs first on the main thread before the 6 facets fan out.

For the **Tests** facet specifically, see [`test-review-checklist.md`](../../references/test-review-checklist.md) for a runnable checklist of coverage, quality, and integration-test signals reviewers can flag with citations.

## Finding Synthesis

After all facets complete, synthesize:

1. **Deduplicate** by `file:line` — same location = same finding, keep highest priority
2. **Prioritize** P1 → P2 → P3
3. **Group** by file for readability
4. **Count** findings per priority level

## Requirements Compliance

Map each acceptance criterion to evidence:

| Status | Meaning |
|--------|---------|
| **Met** | Directly implemented and testable |
| **Interpreted** | Criterion was ambiguous, implementation reflects interpretation |
| **Partially Met** | Some aspects done, others pending |
| **Not Addressed** | Not implemented in this change |

## Finding Format

```markdown
### P1 - Critical
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|
| 1 | security | auth.rb:42 | SQL injection via string interpolation | Use parameterized query |

### P2 - Should Fix
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|

### P3 - Consider
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|
```

## Confidence Assessment

For each finding, assess confidence:

- **High**: Verified by reading code + running test
- **Medium**: Verified by reading code
- **Low**: Pattern match only — needs investigation

Only P1 findings with High confidence should block merge.

## Signal Quality Rules

| Signal Type | Confidence | Include In Review? |
|-------------|-----------|-------------------|
| Verified by running code/test | High | Always |
| LSP diagnostic (error/warning from language server) | High | Always — language server has full project context |
| LSP find-references (verified all callers handled) | High | Always for P1/P2 — semantic, not text-based |
| Verified by reading code path | Medium | Always for P1/P2 |
| Pattern-match only (looks like a bug) | Low | Only if P1, flag as "needs investigation" |
| Style preference | N/A | Only as P3, never blocks merge |

**Noise filter**: If a finding cannot be explained with a file:line citation and a concrete scenario where it causes harm, it is noise. Drop it.

## Boy Scout Recognition

When reviewing, recognize `improve:` commits as legitimate Boy Scout cleanup:
- **APPROVE** `improve:` commits that pass the proximity test (file already modified, self-evidently correct, <10 lines, no API change, no explanation needed)
- **Flag as P2 "scope creep"** only if the cleanup fails the proximity test (untouched files, architecture changes, new tests required, subjective style)

## Review Cycle Awareness

Check review history to understand cycle count:
- Count CHANGES_REQUESTED reviews to determine cycle number
- Focus on delta since last review — findings on unchanged code from prior cycles are noise
- On 3rd+ cycle: only flag NEW P1 findings, note persistent P2s, suggest synchronous discussion for unresolved items
- Note convergence signal if findings are shrinking each cycle — this is healthy progress

### Structured Cycle Parsing

Parse `FLOW_REVIEW_CYCLE` and `FLOW_RESOLUTION_CYCLE` markers from prior PR comments to build cycle context:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# Parse prior review findings (from review bodies)
gh api repos/$REPO/pulls/$PR_NUM/reviews --jq '
  [.[] | select(.body | test("FLOW_REVIEW_CYCLE")) | {
    cycle: (.body | capture("FLOW_REVIEW_CYCLE:(?<n>[0-9]+)") | .n),
    findings: (.body | capture("FINDINGS:\\[(?<f>[^\\]]+)\\]") | .f)
  }]'

# Parse prior resolution outcomes (from issue comments posted via gh pr comment)
gh api repos/$REPO/issues/$PR_NUM/comments --jq '
  [.[] | select(.body | test("FLOW_RESOLUTION_CYCLE")) | {
    cycle: (.body | capture("FLOW_RESOLUTION_CYCLE:(?<n>[0-9]+)") | .n),
    resolved: (.body | capture("RESOLVED:\\[(?<r>[^\\]]*?)\\]") | .r),
    escalated: (.body | capture("ESCALATED:\\[(?<e>[^\\]]*?)\\]") | .e)
  }]'
```

Cross-reference for each prior finding:
1. Was it marked as resolved in a resolution comment?
2. Has the code at that location changed in `git diff`?
3. Build a **Previous Feedback Status** table:

```markdown
### Previous Feedback Status
| Cycle | Finding | Priority | Claimed Status | Verified |
|-------|---------|----------|----------------|----------|
```

If a finding was claimed resolved but the code at that location is unchanged, flag it as "Not verified — code unchanged".

## Review Stop Conditions

- Stage 1 finds >3 unmet acceptance criteria — REQUEST_CHANGES immediately, skip Stage 2
- PR modifies files unrelated to the issue — flag as out-of-context, ask for split (but `improve:` commits in already-modified files are NOT out-of-context)
- Diff is >500 lines with no test changes — flag as P1 "untested large change"

## Review Decision

| Findings | Decision |
|----------|----------|
| P1 findings (any) | REQUEST_CHANGES |
| P2 findings (any) | REQUEST_CHANGES |
| P3 findings only | COMMENT (fix-expected — author must fix in-PR or file a six-field Proactive-Autonomy escalation; P3 is not a free pass) |
| No findings | APPROVE |

Note: P3 → COMMENT is NOT "approve with nits." The PR author is expected to fix every P3 in-PR unless they file an escalation justifying deferral. Reviewers should not approve PRs with unaddressed P3s.

## Adversarial Protocol (Agent Teams)

When agent teams are enabled, use adversarial synthesis from team-coordination skill (`skills/team-coordination/SKILL.md`). Reviewers work independently, share findings, challenge each other, and disputed findings escalate to human.

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "It looks correct to me" | Looking is not verifying. Trace the data flow. |
| "This is just a style issue" | Then it's P3 at most. Don't flag it as P2. |
| "I don't have time for all 6 facets" | Then prioritize: Security > Correctness > the rest. Never skip security. |
| "The tests pass so the logic is fine" | Tests prove what's tested. Review proves what's not. |
| "This is too small to review thoroughly" | Small changes, same process. Small bugs cause big outages. |
