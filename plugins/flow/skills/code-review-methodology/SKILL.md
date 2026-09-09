---
name: code-review-methodology
description: "Conduct two-stage code review: Stage 1 verifies spec compliance (criterion-to-code mapping), Stage 2 evaluates security, correctness, performance, and maintainability across 6 parallel facets with P1/P2/P3 synthesis and deduplication by file:line. For the Tests facet the reviewer derives expected behavior from the spec before reading the tests. Use when reviewing code changes or pull requests. This skill MUST be consulted because reviewing quality on broken logic is wasted effort, and unmet acceptance criteria must block merge."
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
---

# Code Review Methodology

## Contract

Iron law: first verify it works, then verify it is good; never review quality on code that does not meet the acceptance criteria. Loaded as a Required Skill by `/flow:review` (all phases) and `/flow:pr` (self-review and fan-out), and by the `code-reviewer` and `security-reviewer` agents. Returns a synthesized P1/P2/P3 finding set per `references/finding-schema.md`, a requirements-compliance map, and a decision (APPROVE, COMMENT, REQUEST_CHANGES). Permitted skips: Stage 2 is skipped when Stage 1 finds more than 3 unmet criteria (REQUEST_CHANGES immediately); on the 3rd+ review cycle only new P1s are raised.

## Two-stage review

**Stage 1, spec compliance.** Map each acceptance criterion to implementation evidence with one status: **Met** (implemented and testable), **Interpreted** (criterion ambiguous; one reading implemented), **Partially Met**, or **Not Addressed**. If Stage 1 fails, stop.

**Stage 2, code quality**, in priority order: security, correctness, performance, maintainability. Do not flag maintainability while security or correctness findings exist.

## 6-facet review

Stage 1 runs first on the main thread; facets fan out in parallel:

| Facet | Focus | Agent / Skill |
|---|---|---|
| **Security** | OWASP top 10, secrets, auth/authz, input validation | security-reviewer |
| **Quality** | Logic correctness, edge cases | code-reviewer |
| **Conventions** | Commit format, branch naming, PR structure | convention-checker |
| **Tests** | Coverage, quality commands pass, test adequacy | test-runner |
| **Error handling** | Unhandled errors, silent failures, error-path edge cases | error-handler-inspector |
| **Claim verification** | Self-review claims vs actual file state | holdout-validation (skill) |

**Tests facet rule:** derive the expected behavior from the issue/spec BEFORE reading the tests, then check each test's expected value and input against that derivation. Treating the tests as the spec is the failure mode: an expectation copied from the implementation's output confirms nothing. Checklist: `references/test-review-checklist.md`.

## Synthesis

1. Deduplicate by `file:line`: same location, keep highest priority
2. Order P1, P2, P3
3. Group by file
4. Count per priority; counts must match table rows

## Finding format

Emit the two-column `Finding | Suggested Fix` tables per priority defined in `references/finding-schema.md`.

## Confidence and signal

High (verified by running code/test, or LSP diagnostic / find-references): always include. Medium (verified by reading the code path): include for P1/P2. Low (pattern match only): include only as P1 marked "needs investigation". Style preferences are P3 at most. Only High-confidence P1s block merge. A finding with no `file:line` and no concrete harm scenario is noise; drop it.

## Boy Scout recognition

APPROVE `improve:` commits that pass the proximity test (file already modified, self-evidently correct, <10 lines, no API change); P2 "scope creep" only when it fails.

## Review cycle awareness

Count prior `FLOW_REVIEW_CYCLE` markers for the cycle number; review only the delta, verify each claimed resolution against `git diff`, and on the 3rd+ cycle raise only new P1s. Parsing commands and the Previous Feedback Status table: `references/review-cycle-parsing.md`.

## Stop conditions

- Stage 1 finds >3 unmet acceptance criteria: REQUEST_CHANGES immediately, skip Stage 2
- PR modifies files unrelated to the issue: flag as out-of-context, ask for a split (`improve:` commits in already-modified files are in context)
- Diff >500 lines with no test changes: P1 "untested large change"

## Review decision

| Findings | Decision |
|---|---|
| Any P1 | REQUEST_CHANGES |
| Any P2 | REQUEST_CHANGES |
| P3 only | COMMENT; author fixes every P3 in-PR, not "approve with nits" |
| None | APPROVE |

Finding triage is never an escalation trigger (`skills/llm-operator-principles/SKILL.md`, `references/escalation-format.md`).

## Adversarial protocol

With agent teams enabled, apply `skills/team-coordination/SKILL.md`: independent reviewers, mutual challenge, disputed findings escalate to a human.
