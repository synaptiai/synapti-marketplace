---
name: code-review-methodology
description: "[flow] Use when reviewing code changes for quality, security, conventions, tests, and requirements. Guides 5-facet review with P1/P2/P3 finding synthesis, deduplication by file:line, and requirements compliance mapping."
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

## 5-Facet Review

Every review evaluates these facets (parallelizable):

| Facet | Focus | Agent |
|-------|-------|-------|
| **Security** | OWASP top 10, secrets, auth/authz, input validation | security-reviewer |
| **Quality** | Logic correctness, edge cases, error handling | code-reviewer |
| **Conventions** | Commit format, branch naming, PR structure, patterns | convention-checker |
| **Tests** | Coverage, quality commands pass, test quality | test-runner |
| **Requirements** | Acceptance criteria compliance | main thread |

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
| Verified by reading code path | Medium | Always for P1/P2 |
| Pattern-match only (looks like a bug) | Low | Only if P1, flag as "needs investigation" |
| Style preference | N/A | Only as P3, never blocks merge |

**Noise filter**: If a finding cannot be explained with a file:line citation and a concrete scenario where it causes harm, it is noise. Drop it.

## Review Stop Conditions

- Stage 1 finds >3 unmet acceptance criteria — REQUEST_CHANGES immediately, skip Stage 2
- PR modifies files unrelated to the issue — flag as out-of-context, ask for split
- Diff is >500 lines with no test changes — flag as P1 "untested large change"

## Review Decision

| Findings | Decision |
|----------|----------|
| P1 findings (any) | REQUEST_CHANGES |
| P2 findings only | COMMENT (suggest fixes) |
| P3 findings only | APPROVE with comments |
| No findings | APPROVE |

## Adversarial Protocol (Agent Teams)

When agent teams are enabled, use adversarial synthesis from team-coordination skill (`skills/team-coordination/SKILL.md`). Reviewers work independently, share findings, challenge each other, and disputed findings escalate to human.

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "It looks correct to me" | Looking is not verifying. Trace the data flow. |
| "This is just a style issue" | Then it's P3 at most. Don't flag it as P2. |
| "I don't have time for all 5 facets" | Then prioritize: Security > Correctness > the rest. Never skip security. |
| "The tests pass so the logic is fine" | Tests prove what's tested. Review proves what's not. |
| "This is too small to review thoroughly" | Small changes, same process. Small bugs cause big outages. |
