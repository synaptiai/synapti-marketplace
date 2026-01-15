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

## User Interaction

Use the **AskUserQuestion tool** when:
- Target content is not specified
- Critique focus area needs clarification
- Severity threshold for reporting should be confirmed
- Multiple critical issues require prioritization guidance

### Example Invocations

**Missing target:**
```
User: /critique
→ Use AskUserQuestion tool:
  Question: "What would you like me to critique?"
  Options:
  - "Provide a file path"
  - "Paste text or claim directly"
  - "Critique output from previous analysis"
```

**Focus area clarification:**
```
User: /critique research-report.md
→ Use AskUserQuestion tool:
  Question: "What aspects should the critique focus on?"
  Options:
  - "All categories (Logic, Evidence, Coverage, Accuracy)" (Recommended)
  - "Focus on evidence quality and sourcing"
  - "Focus on logical reasoning and arguments"
  - "Focus on coverage gaps and missing perspectives"
```

**Severity threshold:**
```
User: /critique [document]
→ Use AskUserQuestion tool:
  Question: "What severity level should I report?"
  Options:
  - "All issues (1-10)"
  - "Significant and above (5-10)" (Recommended)
  - "Critical only (9-10)"
```

**Prioritization with many issues:**
```
Critique found 12 issues across all categories
→ Use AskUserQuestion tool:
  Question: "Found 12 issues. How should I present them?"
  Options:
  - "Top 5 highest severity with action items" (Recommended)
  - "All issues grouped by category"
  - "All issues sorted by severity"
```

Begin critique now.
