---
description: Conduct deep research using Time-Tested Diffusion methodology
argument-hint: <research topic or question>
model: opus
---

# Deep Research: $ARGUMENTS

Conduct comprehensive research using Time-Tested Diffusion (TTD) methodology.

## Step 1: Research Brief

Create a structured brief:
```
RESEARCH BRIEF
Topic: [derived from request]
Key Questions:
1. [Primary]
2. [Secondary]
3. [Tertiary]
Constraints: [limits]
```

## Step 2: Initial Draft

Write from existing knowledge. Mark uncertainty:
- `[NEEDS VERIFICATION]` - unsure claims
- `[RESEARCH NEEDED]` - gaps
- `[CONFIDENCE: LOW/MED/HIGH]`

## Step 3: Red Team Critique

Attack your draft for:
- Logical fallacies (circular reasoning, false dichotomies)
- Evidence gaps (unsourced, single-source)
- Coverage gaps (missing perspectives)

Rate each issue 1-10 severity.

## Step 4: Research with Reflection

**CRITICAL: After EVERY search, reflect:**
```
REFLECTION:
- Key facts: [with confidence 1-100]
- Gaps remaining: [what's missing]
- Source agreement: [contradictions?]
- Decision: [search again / move on / done]
```

## Step 5: Source Tracking

Track every fact:
```
FACT: [Statement]
SOURCE: [URL]
CONFIDENCE: [1-100]
DISPUTED: [Yes/No]
```

## Step 6: Quality Evaluation

Score after each cycle:
- Comprehensiveness (1-10)
- Accuracy (1-10)

```
QUALITY LOG:
Iteration 1: Comp [X], Acc [Y], Avg [Z]
```

If average < 7: repeat critique → research → refine (max 3 cycles)

## Step 7: Final Report

```markdown
# [Title]

## Executive Summary
[2-3 paragraphs]

## Findings
[with inline citations]

## Methodology
[sources, confidence approach]

## Limitations
[gaps, disputes]

## Sources
[numbered with confidence]
```

## User Interaction

Use the **AskUserQuestion tool** when:
- Topic is ambiguous or has multiple interpretations
- Scope needs clarification (timeframe, geography, focus area)
- Quality threshold preferences should be confirmed
- Contradictions require user judgment to resolve

### Example Invocations

**Ambiguous topic:**
```
User: /deep-research AI
→ Use AskUserQuestion tool:
  Question: "AI research is broad. What aspect interests you?"
  Options:
  - "Current state of large language models"
  - "AI safety and alignment research"
  - "AI in a specific industry (healthcare, finance, etc.)"
  - "AI regulation and policy developments"
```

**Scope clarification:**
```
User: /deep-research fusion energy
→ Use AskUserQuestion tool:
  Question: "What scope for fusion energy research?"
  Options:
  - "Current technical progress and milestones" (Recommended)
  - "Commercial viability and timelines"
  - "Comparison of approaches (tokamak, stellarator, etc.)"
  - "Investment landscape and key players"
```

**Quality iteration decision:**
```
After iteration 2: Comprehensiveness 6, Accuracy 6, Avg 6.0
→ Use AskUserQuestion tool:
  Question: "Quality score is 6/10. Continue refining or finalize?"
  Options:
  - "Continue to iteration 3 for higher quality" (Recommended)
  - "Finalize with current quality (good enough)"
  - "Focus on specific gaps I'll identify"
```

**Source contradictions:**
```
Sources disagree on timeline: "2030 vs 2040 for commercial fusion"
→ Use AskUserQuestion tool:
  Question: "Expert sources disagree on fusion timeline. How to present?"
  Options:
  - "Present both estimates with source confidence"
  - "Focus on the more conservative estimate"
  - "Research additional sources to find consensus"
```

Begin now.
