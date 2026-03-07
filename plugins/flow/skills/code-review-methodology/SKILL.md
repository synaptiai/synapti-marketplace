---
name: code-review-methodology
description: "[flow] Use when reviewing code changes for quality, security, conventions, tests, and requirements. Guides 5-facet review with P1/P2/P3 finding synthesis, deduplication by file:line, and requirements compliance mapping."
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
---

# Code Review Methodology

Domain skill for structured, multi-faceted code review.

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

## Review Decision

| Findings | Decision |
|----------|----------|
| P1 findings (any) | REQUEST_CHANGES |
| P2 findings only | COMMENT (suggest fixes) |
| P3 findings only | APPROVE with comments |
| No findings | APPROVE |

## Adversarial Protocol (Agent Teams)

When agent teams are enabled, the review uses adversarial synthesis:

1. Each reviewer works independently (no shared context)
2. Reviewers share findings
3. Each reviewer challenges others' findings
4. Disputed findings get escalated to human
5. Consensus findings get highest confidence
