## Summary

{2-3 sentence description of what changed and why}

Closes #{issue_number}

## Changes

{Bullet list of key changes, grouped by area:}

### {Area 1}
- {Change description}

### {Area 2}
- {Change description}

## Comprehension Report

**Tier**: {Minimal|Full} ({N} lines changed, {M} areas)

{Plain-language description of what was built and why, written for someone who hasn't seen the code}

### Key Decisions

{From decision journal — public entries only:}

- **{Category}: {Title}** — {Decision}. {Rationale}. Risk: {level}.

{For internal entries:}
- **{Category}: [Internal decision]** — See decision journal for details.

### Requirements Adherence

| # | Acceptance Criterion | Status | Evidence |
|---|---------------------|--------|----------|
| 1 | {criterion} | Met | {file:line} |
| 2 | {criterion} | Met | {file:line} |

## Review Findings

| Priority | Count | Details |
|----------|-------|---------|
| P1 | {X} | {All resolved before PR creation} |
| P2 | {Y} | {Summary} |
| P3 | {Z} | {Summary} |

### Review Cycle History
<!-- Updated by /flow:address -->
_No review cycles completed yet._

## Verification

- [ ] Quality checks pass (lint, test, typecheck)
- [ ] Self-review completed
- [ ] Runtime verification (if applicable)
- [ ] All tasks completed

## Verification Verdict

{If verdict.enabled and acceptance criteria exist:}

{If all PASS:}
All {N} acceptance criteria verified independently by verdict-judge. No human review required.

{If any FAIL or NEEDS-HUMAN-REVIEW:}
### Requires Attention ({X} of {N} criteria)

| # | Criterion | Verdict | Evidence | Action Needed |
|---|-----------|---------|----------|--------------|
{Only FAIL and NEEDS-HUMAN-REVIEW rows}

### Passed ({Y} of {N} criteria)
<details>
<summary>Click to expand passing criteria</summary>

| # | Criterion | Evidence Summary |
|---|-----------|-----------------|
{PASS rows — collapsed by default so humans review only failures}
</details>

{If spec-free task:}
Spec-free task — no acceptance criteria to verify.

## Files Changed

{Grouped by top-level directory with counts:}

| Area | Files | Additions | Deletions |
|------|-------|-----------|-----------|
| {dir} | {N} | +{lines} | -{lines} |
