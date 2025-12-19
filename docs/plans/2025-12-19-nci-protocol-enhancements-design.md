# NCI Protocol Enhancements Design

**Date:** 2025-12-19
**Status:** Approved
**Scope:** Add all NCI Protocol nuances to Decipon plugin

---

## Overview

This design adds comprehensive detection nuances from the NCI Protocol implementation to the Decipon Claude Code plugin, including vocabulary lists, detection signals, quantitative formulas, first principles, and actionable guidance.

---

## New Files to Create

### 1. `skills/nci-analysis/references/vocabulary.md`

Comprehensive English vocabulary reference for manipulation detection.

**Sections:**
- **Emotional Manipulation Vocabulary**
  - FEAR_WORDS: threat, danger, crisis, catastrophe, disaster, deadly, fatal, etc.
  - ANGER_WORDS: outrage, infuriating, unacceptable, disgraceful, shameful, etc.
  - GUILT_WORDS: shame, betrayal, abandonment, etc.
  - OUTRAGE_WORDS: scandal, corruption, disgusting, etc.
  - URGENCY_WORDS: immediately, urgent, now, asap, emergency, critical, deadline, etc.
  - NOVELTY_WORDS: unprecedented, shocking, bombshell, breaking, exclusive, etc.

- **Tribal Division Vocabulary**
  - DEHUMANIZING_WORDS (WEIGHT: 0.8 penalty each): animals, vermin, horde, savages, barbarians, filth, scum, disease, cancer, plague, infestation, cockroaches, rats, parasites, etc.
  - HUMANIZING_WORDS (for contrast detection): families, children, names, stories, individuals, people, etc.
  - OTHERING_WORDS: enemy, threat, invader, outsider, foreigner, alien, etc.
  - GROUP_IDENTITY_PHRASES: "us vs them", "with us or against us", "one of us", "the elites", "sheeple", "truth seekers", "real patriots", etc.

- **Attribution Vocabulary**
  - CREDIBLE_ATTRIBUTION_VERBS (applied to "us"): stated, confirmed, said, reported, announced, explained, noted, emphasized, etc.
  - DISCREDITING_ATTRIBUTION_VERBS (applied to "them"): claimed, alleged, insisted, demanded, ranted, asserted, etc.
  - ONE_SIDED_SOURCE_PHRASES: "officials say", "sources say", "declined to comment", "could not be reached", etc.

- **Framing Vocabulary**
  - EUPHEMISM_WORDS: collateral damage, neutralized, enhanced interrogation, surgical strike, kinetic action, clashes, incident, altercation, confrontation, etc.
  - PASSIVE_VOICE_INDICATORS: "was killed", "were destroyed", "situation escalated", "violence erupted", "shots were fired", "mistakes were made", etc.
  - AGENCY_OMISSION_PHRASES: "the situation deteriorated", "tensions rose", "conflict broke out", etc.

- **Logical Fallacy Vocabulary**
  - WHATABOUTISM_PHRASES: "but what about", "what about when", "you also", "they did it too", etc.
  - FALSE_EQUIVALENCE_PHRASES: "both sides", "equally responsible", "mutual", "reciprocal", "bilateral" (misuse), etc.
  - DEFLECTION_PHRASES: "that's not the real issue", "let's focus on", "the real problem is", etc.
  - SMEAR_PHRASES: "known ties to", "funded by", "connected to", "linked to" (without substantiation), etc.

- **Quality Indicators (Positive)**
  - FACTUAL_INDICATORS: "according to", "data shows", "study found", "research indicates", etc.
  - QUALIFIER_WORDS: however, although, nevertheless, conversely, alternatively, etc.
  - PERSPECTIVE_PHRASES: "critics argue", "supporters say", "some believe", "others contend", etc.
  - CONTEXT_WORDS: historically, previously, in context, background, etc.

- **Conspiracy Vocabulary**
  - CONSPIRACY_WORDS: cover-up, agenda, narrative, mainstream, controlled, puppet, etc.
  - CONSPIRACY_PHRASES: "what they don't want you to know", "the truth about", "wake up", "open your eyes", etc.

---

### 2. `skills/nci-analysis/references/guidance.md`

Actionable tips organized by composite factor with display thresholds.

**Structure:**

```markdown
# NCI Actionable Guidance Reference

## Purpose
User-facing tips displayed when composite factors exceed thresholds.

## Display Thresholds
- Factor score > 2.5 (on 1-5 scale) → Show factor tips
- Overall score > 25 → Show summary guidance
- Overall score > 50 → Show verification recommendations

## Factor-Specific Tips

### Emotional Manipulation (when > 2.5)
- "What facts support this emotional response?"
- "Is the emotional intensity proportional to the actual situation?"
- "Would this information be equally valid without the emotional language?"

### Suspicious Timing (when > 2.5)
- "Why is this emerging now? What recent events does it connect to?"
- "Who benefits if this narrative is believed?"
- "Who benefits if this narrative is dismissed?"

### Uniform Messaging (when > 2.5)
- "Look for independent sources with different framing"
- "Are multiple outlets using identical phrases?"
- "Search for the same claim with different wording"

### Tribal Division (when > 2.5)
- "Consider the other side's perspective charitably"
- "Who is humanized with names/stories vs. reduced to statistics?"
- "Watch for dehumanizing language (animals, vermin, horde)"

### Missing Information (when > 2.5)
- "What questions aren't being answered?"
- "Notice attribution asymmetry: 'stated' vs 'claimed'"
- "Who is quoted and who is not? Who 'declined to comment'?"
- "Watch for passive voice hiding responsibility"

## Advanced Detection Tips

### Framing Techniques
- "Notice who performs actions vs. who is acted upon"
- "Watch for euphemisms: 'clashes' vs 'attack', 'neutralized' vs 'killed'"

### Logical Fallacies
- "Watch for 'but what about...' deflections (whataboutism)"
- "'Both sides' framing may create false equivalence"
- "Smears without evidence: 'known ties to', 'funded by'"

## Summary Guidance by Score

| Score Range | Summary Guidance |
|-------------|------------------|
| 76-100 | "Significant manipulation indicators detected. Verify all claims independently before sharing." |
| 51-75 | "Notable manipulation patterns present. Cross-reference with independent sources." |
| 26-50 | "Some concerning indicators. Verify key claims before accepting." |
| 0-25 | No summary needed (appears legitimate) |
```

---

## Files to Modify

### 1. `skills/nci-analysis/SKILL.md`

**Add First Principles summary:**
```markdown
## First Principles (Summary)

The NCI Protocol is grounded in these principles (see perspective-generator agent for full version):

1. **Evidence over authority** - Pattern recognition over source reputation
2. **Steel-man interpretation** - Strongest version of each perspective
3. **Atomic decomposition** - Break claims into smallest verifiable units
4. **Source agnosticism** - Same standards regardless of source
5. **Bidirectional beneficiary analysis** - Who benefits if believed AND if dismissed
6. **Pattern vs. Intent** - Focus on techniques; deep research evidence can inform motives
```

**Update References section:**
```markdown
## References

- [references/categories.md](references/categories.md) - All 20 category definitions with detection signals
- [references/scoring.md](references/scoring.md) - Scoring methodology, weights, and quantitative formulas
- [references/examples.md](references/examples.md) - Historical case studies for calibration
- [references/vocabulary.md](references/vocabulary.md) - Detection vocabulary lists
- [references/guidance.md](references/guidance.md) - Actionable tips per factor
```

---

### 2. `skills/nci-analysis/references/categories.md`

**Add "Detection Signals" subsection to each of 20 categories.**

Format per category:
```markdown
#### Detection Signals
**Vocabulary to detect** (see vocabulary.md):
- [Relevant vocabulary lists with examples]

**Patterns to detect**:
- [Specific patterns unique to this category]

**Quantitative threshold** (where applicable):
- [Formula or threshold for scoring guidance]
```

**Key detection signals by category:**

| Category | Key Detection Signals |
|----------|----------------------|
| 1. Emotional Manipulation | Trigger density formula, fear/anger vocabulary |
| 2. Urgent Action | Urgency words, deadline phrases, timeline compression |
| 3. Novelty | Superlatives, "unprecedented", "shocking", "exclusive" |
| 4. Repetition | Instance counting (1-2=2, 3-5=3, 6-10=4, >10=5) |
| 5. Manufactured Outrage | Outrage vocabulary, proportionality check |
| 6. Timing | Event correlation, recency detection |
| 7. Financial/Political Gain | Beneficiary identification |
| 8. Historical Parallels | Pattern matching to known campaigns |
| 9. Uniform Messaging | Identical phrases across sources |
| 10. Bandwagon | Unverified popularity claims |
| 11. Rapid Shifts | Conversion pressure, astroturfing signs |
| 12. Tribal Division | Pronoun ratio, dehumanization (0.8 weight), asymmetric humanization |
| 13. Simplistic Narratives | Moral absolutism, nuance absence |
| 14. False Dilemmas | Binary forcing vocabulary |
| 15. Missing Information | Context completeness, attribution asymmetry, passive voice |
| 16. Authority Overload | Credential verification, conflict of interest |
| 17. Suppression of Dissent | Critic labeling ("deniers", "shills") |
| 18. Cherry-Picked Data | Selection bias, statistical manipulation |
| 19. Logical Fallacies | Whataboutism, false equivalence, smears, deflection |
| 20. Framing Techniques | Passive voice agency hiding, euphemisms, violence softening |

---

### 3. `skills/nci-analysis/references/scoring.md`

**Add "Quantitative Detection Formulas" section:**

```markdown
## Quantitative Detection Formulas

### Emotional Trigger Density (Categories 1-5)
trigger_density = emotional_words / total_words

| Density | Score |
|---------|-------|
| < 0.02  | 1     |
| 0.02-0.05 | 2   |
| 0.05-0.10 | 3   |
| 0.10-0.15 | 4   |
| > 0.15  | 5     |

### Intensity Detection
caps_ratio = ALL_CAPS_words / total_words
exclamation_density = exclamation_marks / sentences

- caps_ratio > 0.20 = maximum intensity
- exclamation_density > 0.5 = elevated intensity
- Repeated punctuation (!!!, ???) = intensity marker

### Pronoun Ratio (Category 12)
tribal_ratio = (we + us + our) / (they + them + their + 1)

| Ratio | Interpretation |
|-------|----------------|
| < 1.5 | Balanced       |
| 1.5-3.0 | Mild tribal  |
| 3.0-5.0 | Notable tribal |
| > 5.0 | Strong tribal  |

### Repetition Thresholds (Category 4)
| Instances | Score |
|-----------|-------|
| 1-2       | 2     |
| 3-5       | 3     |
| 6-10      | 4     |
| > 10      | 5     |

### Context Completeness (Category 15)
Expected per 100 words: 2 qualifiers + 1 perspective phrase
completeness = (qualifiers + perspectives) / expected

| Completeness | Score |
|--------------|-------|
| > 80%        | 1-2   |
| 50-80%       | 3     |
| 25-50%       | 4     |
| < 25%        | 5     |

### Dehumanization Penalty (Category 12)
Each dehumanizing word: 0.8 penalty to tribal score
Single instance can elevate score by 1+ point
```

**Expand "Confidence Calculation" section:**

```markdown
### Word Count Confidence Adjustment

base_confidence = 0.80
word_count_adjustment = min((word_count / 500) × 0.05, max_adjustment)
final_confidence = min(base_confidence + word_count_adjustment, 0.95)

| Analysis Type | Base | Max Adjustment | Max Final |
|---------------|------|----------------|-----------|
| Standard rule-based | 0.80 | +0.05 | 0.85 |
| NLP-enhanced | 0.80 | +0.05 | 0.85 |
| Text-only fallback | 0.70 | +0.05 | 0.75 |
| Context-dependent (with data) | 0.80 | +0.10 | 0.90 |
| Context-dependent (no data) | 0.45 | +0.10 | 0.55 |

Short content warning (< 100 words):
> "Limited content length may reduce scoring reliability"
```

---

### 4. `agents/perspective-generator.md`

**Add "First Principles" section at top:**

```markdown
## First Principles (NCI Protocol Foundation)

### 1. Evidence Over Authority
Evaluate patterns in the content itself, not source reputation.

### 2. Steel-Man Interpretation
Present the STRONGEST version of each perspective.

### 3. Atomic Decomposition
Break claims into smallest verifiable units.

### 4. Source Agnosticism
Apply identical standards regardless of political/ideological alignment.

### 5. Bidirectional Beneficiary Analysis
Ask BOTH: Who benefits if believed? Who benefits if dismissed?

### 6. Pattern vs. Intent
Focus primarily on detecting TECHNIQUES rather than assuming MOTIVES from patterns alone.

**However:** Evidence gathered through deep research (beneficiary analysis, timing correlations, documented coordination, financial trails) CAN inform assessments of likely intent. When such evidence exists, incorporate it into perspective generation with appropriate confidence levels.

Pattern alone → Low confidence about intent
Pattern + corroborating evidence → Higher confidence about intent
```

**Add "Execution Pattern" section:**

```markdown
## Execution Pattern

┌─────────────────────────────────────────────────────┐
│                   NCI Scores Ready                  │
└─────────────────────┬───────────────────────────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
┌─────────────────┐       ┌─────────────────┐
│    Red Team     │       │    Blue Team    │
│  (Manipulative) │       │   (Legitimate)  │
│   [PARALLEL]    │       │   [PARALLEL]    │
└────────┬────────┘       └────────┬────────┘
         │                         │
         └────────────┬────────────┘
                      ▼
            ┌─────────────────┐
            │    Synthesis    │
            │  [SEQUENTIAL]   │
            │ (needs both)    │
            └─────────────────┘

- Red Team and Blue Team run simultaneously
- Synthesis waits for both to complete
- If either fails, Synthesis uses available data with reduced confidence
```

---

### 5. `agents/nci-analyzer.md`

**Add reference to detection signals:**
```markdown
## Detection Methodology

For detailed detection signals per category, see:
- `skills/nci-analysis/references/categories.md` - Detection signals subsections
- `skills/nci-analysis/references/vocabulary.md` - Vocabulary lists
- `skills/nci-analysis/references/guidance.md` - Actionable tips
```

**Update output workflow to include guidance tips when thresholds exceeded.**

---

## Implementation Order

1. Create `vocabulary.md` (comprehensive vocabulary lists)
2. Create `guidance.md` (actionable tips)
3. Update `SKILL.md` (first principles + references)
4. Update `categories.md` (detection signals for all 20 categories)
5. Update `scoring.md` (quantitative formulas + confidence calibration)
6. Update `perspective-generator.md` (first principles + execution pattern)
7. Update `nci-analyzer.md` (references to new files)

---

## Validation Checklist

- [ ] All 20 categories have Detection Signals subsections
- [ ] All vocabulary lists are comprehensive (English only)
- [ ] Quantitative formulas match NCI Protocol implementation
- [ ] First Principles appear in both SKILL.md (summary) and perspective-generator.md (full)
- [ ] References section in SKILL.md includes new files
- [ ] Guidance tips have clear thresholds
- [ ] Dehumanization weight (0.8) documented
- [ ] Word count confidence adjustment documented
- [ ] Execution pattern diagram included
