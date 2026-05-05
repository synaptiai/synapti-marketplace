# Decision Journal — Issue #82

**Title**: fix(skills): code-review-methodology says 6-facet to match actual fan-out
**Branch**: feature/issue-82-code-review-6-facet
**Started**: 2026-05-05

## Specification

### Non-goals
- Don't change the agent dispatch in `commands/pr.md` or `commands/review.md` (the 6-facet fan-out is already correct).
- Don't rename any agents.
- Don't reorder facets in priority (Security > Correctness > Performance > Maintainability stays).
- Don't alter the Two-Stage Review structure (Stage 1 = Spec Compliance, Stage 2 = Code Quality).
- Don't change the holdout-validation skill itself.

### Failure modes
- Markdown content change — no runtime failure modes apply (no timeouts, no partial failures, no invalid input).
- Forward-compat: if a 7th facet is added later, this model extends with one row; structure is preserved.

### Interface contracts
- `SKILL.md` frontmatter `description` field — string.
- Facet table — markdown with columns Facet | Focus | Agent.
- Anti-pattern row — markdown table cell containing the literal "facets" count.
- Internal: `Required Skills` lists in commands continue to reference the skill by name `code-review-methodology` (unchanged).

## Spec Validation Gate

| # | Acceptance Criterion | Verification Command | Gate Status |
|---|---|---|---|
| 1 | SKILL.md description (line 3) says "6-facet" and enumerates 6 facets | `grep -E "6-facet" plugins/flow/skills/code-review-methodology/SKILL.md` returns ≥1 + visual inspection of description for the 6 facets | PASS |
| 2 | Facets section (~line 33) lists exactly 6 facets, with the agent that owns each | Count rows in facet table = 6; each row has an agent name | PASS |
| 3 | "I don't have time" anti-pattern row (line 180) updates "5 facets" to "6 facets" | `grep "I don't have time" plugins/flow/skills/code-review-methodology/SKILL.md` shows "6 facets" | PASS |
| 4 | `git grep -n "5-facet\|five-facet" plugins/flow` returns zero matches | Run command, expect empty output | PASS |
| 5 | The 6 facets in the skill match the 6 agents dispatched in `commands/pr.md` and `commands/review.md` | Compare facet table rows against `grep "^Agent(\|^Skill(holdout" commands/pr.md` (excluding post-fan-out integration-verifier) = 6 | PASS |

All ACs PASS — proceeding to PLAN.

## Stranger Test

A zero-context agent could execute the plan ("update SKILL.md to 6-facet at lines 3, 33, 180; cross-check against pr.md fan-out; verify via grep") given the file paths and verification commands. **PASS**.

## Mapped facet table (6 facets, post-update)

The new facet table maps each facet to a fan-out agent or skill:

| Facet | Focus | Agent / Skill |
|-------|-------|---------------|
| Security | OWASP top 10, secrets, auth/authz, input validation | security-reviewer |
| Quality | Logic correctness, edge cases | code-reviewer |
| Conventions | Commit format, branch naming, PR structure | convention-checker |
| Tests | Coverage, lint/test/typecheck pass | test-runner |
| Error handling | Unhandled errors, silent failures, missing edge cases | error-handler-inspector |
| Claim verification | Self-review claims cross-referenced against file state | holdout-validation (skill) |

This drops the old "Requirements (main thread)" row — Requirements compliance moves to Stage 1 of Two-Stage Review (already at SKILL.md line 21), where it has always belonged.

## Boy Scout extension

The grep also finds 5-facet references in `commands/pr.md:20`, `commands/review.md:18`, `references/skill-manifests.md:44`, and `docs/flow-team-session/HANDBOOK.md:433`. AC4 scopes the requirement to `plugins/flow`, so HANDBOOK.md is in-scope-by-Boy-Scout, the others are required.

<!-- auto-log: 2026-05-05 23:09 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-82.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/code-review-methodology/SKILL.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/code-review-methodology/SKILL.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/code-review-methodology/SKILL.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/skill-manifests.md -->

<!-- auto-log: 2026-05-05 23:10 Edit /Users/danielbentes/synapti-marketplace/docs/flow-team-session/HANDBOOK.md -->

<!-- auto-log: 2026-05-05 23:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/code-review-methodology/SKILL.md -->

<!-- auto-log: 2026-05-05 23:34 commit "fix-forward: replace brittle (line 21) with content-addressable ref" -->
