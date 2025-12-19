# Critique Framework Reference

## Contents
- [Red Team Mindset](#red-team-mindset)
- [Critique Categories](#critique-categories)
- [Severity Guidelines](#severity-guidelines)
- [Quality Scoring](#quality-scoring)
- [Iteration Tracking](#iteration-tracking)
- [Self-Correction Triggers](#self-correction-triggers)

## Red Team Mindset

Approach your draft as an adversary trying to find weaknesses:
- "How could this be wrong?"
- "What would a skeptic attack?"
- "What's missing that an expert would notice?"
- "Where am I least confident?"

### Adversarial Questions
For each major claim, ask:
1. Is this actually true, or does it just sound true?
2. What source says this? How reliable?
3. Could reasonable people disagree?
4. Am I oversimplifying?
5. What counterargument exists?

## Critique Categories

### 1. Logical Fallacies

| Fallacy | Sign | Severity | Fix |
|---------|------|----------|-----|
| Circular reasoning | Conclusion assumes itself | 8-10 | Find independent evidence |
| False dichotomy | "Either X or Y" | 6-8 | Acknowledge spectrum |
| Hasty generalization | Broad claim, limited evidence | 7-9 | Qualify scope or add evidence |
| Appeal to authority | Irrelevant expert | 5-7 | Find domain experts |
| Strawman | Weakened opposing view | 6-8 | Steelman arguments |
| Post hoc fallacy | Correlation → causation | 7-9 | Acknowledge limitation |

### 2. Evidence Gaps

| Gap | Severity | Fix |
|-----|----------|-----|
| Central claim unsourced | 9-10 | Research immediately |
| Supporting claim unsourced | 6-8 | Research or qualify |
| Single-source critical claim | 7-9 | Find corroboration |
| Outdated information | 5-8 | Search for updates |
| Secondary source only | 4-6 | Trace to primary |
| Low-confidence source | 5-7 | Find higher-quality source |

### 3. Coverage Gaps

| Gap | Severity | Fix |
|-----|----------|-----|
| Key question unaddressed | 9-10 | Research and add section |
| Missing major perspective | 7-9 | Research counterarguments |
| No concrete examples | 4-6 | Add cases/data |
| Missing context | 5-7 | Add background |
| Incomplete comparison | 6-8 | Research missing element |

### 4. Accuracy Issues

| Issue | Severity | Fix |
|-------|----------|-----|
| Factual error detected | 9-10 | Correct immediately |
| Contradiction with sources | 8-10 | Resolve or note dispute |
| Misrepresentation | 7-9 | Re-read source, correct |
| Overconfident claim | 5-7 | Add hedging language |
| Conflated concepts | 5-8 | Distinguish clearly |

## Severity Guidelines

### Critical (9-10)
- Factual errors in central claims
- Missing major perspectives
- Core logical fallacies
- Unresolved contradictions
- Key research question unanswered

**Action**: Must fix before proceeding

### Significant (7-8)
- Unsourced important claims
- Outdated core information
- Missing key context
- Single-source reliance for important facts

**Action**: Fix in current iteration

### Moderate (5-6)
- Weak examples
- Minor gaps
- Style issues affecting clarity
- Could use additional support

**Action**: Fix if time permits

### Minor (1-4)
- Polish suggestions
- Optional additions
- Stylistic preferences

**Action**: Note for final pass

## Quality Scoring

### Two Dimensions

**Comprehensiveness (1-10)**: Does it fully address the research brief?
- 9-10: All questions answered with depth and nuance
- 7-8: Most questions answered adequately
- 5-6: Significant gaps remain
- 1-4: Major areas unaddressed

**Accuracy (1-10)**: Are claims well-sourced and factually correct?
- 9-10: All claims sourced, multiple confirmations, high confidence
- 7-8: Most claims sourced, appropriate confidence levels
- 5-6: Many unsourced claims or low-confidence sources
- 1-4: Significant unsourced or contradicted claims

### Scoring Checklist

```
COMPREHENSIVENESS:
[ ] All key questions from brief addressed?
[ ] Sufficient depth on each question?
[ ] Multiple perspectives included?
[ ] Concrete examples/data provided?
[ ] Limitations acknowledged?
Score: ___/10

ACCURACY:
[ ] Major claims have citations?
[ ] Sources are high quality?
[ ] Confidence levels appropriate?
[ ] Contradictions resolved or noted?
[ ] No obvious factual errors?
Score: ___/10

AVERAGE: ___/10
```

## Iteration Tracking

### Quality Log Format
Track scores across iterations to ensure improvement:

```
QUALITY LOG
===========
Iteration 1:
  Comprehensiveness: 5/10
  Accuracy: 4/10
  Average: 4.5/10
  Main issues: Missing private sector analysis, unsourced timeline claims
  
Iteration 2:
  Comprehensiveness: 7/10 (+2)
  Accuracy: 6/10 (+2)
  Average: 6.5/10 (+2)
  Main issues: Timeline claims still weak, need more sources
  Improvement: Added private sector section
  
Iteration 3:
  Comprehensiveness: 8/10 (+1)
  Accuracy: 8/10 (+2)
  Average: 8.0/10 (+1.5) ✓ THRESHOLD MET
  Resolved: All major issues addressed
```

### Monitoring Patterns

**Healthy iteration**: Scores increase each round
```
4.5 → 6.5 → 8.0 ✓
```

**Stalling**: Scores plateau
```
4.5 → 5.0 → 5.5 → 5.5 ← Problem!
Action: Change approach, not just more research
```

**Regression**: Scores drop
```
6.0 → 7.5 → 6.5 ← Problem!
Action: Compare drafts, identify what broke
```

## Self-Correction Triggers

### Automatic Interventions

When average score < 7, force-inject priority:
```
QUALITY ALERT: Previous draft scored [X]/10
Priority actions for this iteration:
1. [Highest severity unaddressed critique]
2. [Second highest]
3. [Third highest]
```

### When Score Drops Between Iterations

Compare drafts to identify:
1. What content was removed?
2. What claims became less supported?
3. Was good material accidentally lost in revision?

Recovery:
- Restore lost high-value content
- Re-add citations that were dropped
- Merge best parts of both versions

### Stuck Pattern Detection

If after 2 iterations same critique persists:
1. The issue may be structural, not informational
2. Consider reorganizing, not just adding
3. May need different search angle entirely

### When to Accept "Good Enough"

After 3 iterations, if score is 6-6.9:
- Document remaining limitations clearly
- Note what would improve with more research
- Deliver with appropriate caveats

Don't iterate forever—diminishing returns apply.

## Critique Process

### Pass 1: Structure (5 min)
- Does organization serve the research brief?
- Are sections balanced appropriately?
- Is flow logical?

### Pass 2: Claims (10 min)
- For each major claim: source? confidence? could be wrong?
- Flag anything that "sounds right" but isn't verified

### Pass 3: Gaps (5 min)
- What would an expert immediately ask?
- What counterarguments aren't addressed?
- What context is assumed but not stated?

### Document Format
```
CRITIQUE #[N]
Location: [Section/paragraph]
Category: [Logic/Evidence/Coverage/Accuracy]
Severity: [1-10]
Issue: [Specific description]
Fix: [Required action]
```

### Prioritization
Address in order:
1. Severity 9-10 (blocking issues)
2. Issues affecting executive summary
3. Issues affecting multiple sections
4. Remaining high-severity
5. Moderate issues if iteration budget remains
