---
description: Red team adversarial critique of a document or claim
argument-hint: <file path or claim text>
allowed-tools: Read, Grep, Glob
model: sonnet
---

# Red Team Critique

Target: $ARGUMENTS

Approach as an adversary finding weaknesses.

## Critique Format

For each issue:
```
CRITIQUE #[N]
Category: [Logic / Evidence / Coverage / Accuracy]
Severity: [1-10]
Location: [where]
Issue: [description]
Fix: [action]
```

## Categories

**Logic**: Circular reasoning, false dichotomies, hasty generalizations, strawman, post hoc fallacy

**Evidence**: Unsourced claims, single-source reliance, outdated info, secondary sources, low-credibility

**Coverage**: Unaddressed questions, missing perspectives, no examples, incomplete comparisons

**Accuracy**: Factual errors, misrepresentations, overconfident claims, conflated concepts

## Severity Guide

- **9-10 Critical**: Must fix (errors, core flaws, major gaps)
- **7-8 Significant**: Should fix (unsourced, outdated)
- **5-6 Moderate**: Consider fixing (weak examples)
- **1-4 Minor**: Polish items

## Output

```
## Summary
[2-3 sentences]

## Critical Issues (9-10)
[list]

## Significant Issues (7-8)
[list]

## Moderate Issues (5-6)
[list]

## Priority Actions
1. [first fix]
2. [second]
3. [third]
```

Begin critique now.
