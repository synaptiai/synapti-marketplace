# NCI Protocol Enhancements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add comprehensive detection nuances from NCI Protocol to Decipon plugin with vocabulary lists, detection signals, quantitative formulas, first principles, and actionable guidance.

**Architecture:** Create 2 new reference files (vocabulary.md, guidance.md), then enhance 5 existing files with cross-references, detection signals, and formulas. All changes are markdown documentation within the Claude Code plugin structure.

**Tech Stack:** Markdown files, Claude Code plugin architecture (agents/, commands/, skills/)

**Design Document:** `docs/plans/2025-12-19-nci-protocol-enhancements-design.md`

---

## Task 1: Create vocabulary.md

**Files:**
- Create: `synapti-marketplace/plugins/decipon/skills/nci-analysis/references/vocabulary.md`

**Step 1: Create the vocabulary reference file**

Create file with comprehensive English vocabulary lists organized by detection function.

```markdown
# NCI Detection Vocabulary Reference

Canonical word lists for manipulation detection. Reference during NCI analysis.

---

## Emotional Manipulation Vocabulary

### FEAR_WORDS
threat, danger, crisis, catastrophe, disaster, deadly, fatal, terrifying, horrifying, devastating, alarming, dire, perilous, menacing, ominous, dreadful, harrowing, nightmarish, apocalyptic, existential

### ANGER_WORDS
outrage, infuriating, unacceptable, disgraceful, shameful, appalling, despicable, reprehensible, unconscionable, abhorrent, scandalous, atrocious, heinous, vile, contemptible, revolting, sickening, enraging, maddening, inexcusable

### GUILT_WORDS
shame, betrayal, abandonment, neglect, failure, complicit, blood on hands, how dare, responsible for, turned their back, let down, forsaken, culpable, blameworthy

### OUTRAGE_WORDS
scandal, corruption, disgusting, fraud, lies, deceit, treachery, treason, sellout, backstab, double-cross, manipulation, exploitation, abuse, violation

### URGENCY_WORDS
immediately, urgent, now, asap, emergency, critical, deadline, time-sensitive, act fast, don't wait, hurry, rush, instant, pressing, crucial, vital, imperative

### NOVELTY_WORDS
unprecedented, shocking, bombshell, breaking, exclusive, first-time, never-before, historic, groundbreaking, explosive, stunning, jaw-dropping, earth-shattering, game-changing, revolutionary, unbelievable, extraordinary

---

## Tribal Division Vocabulary

### DEHUMANIZING_WORDS
**CRITICAL: Weight 0.8 penalty each - single instance significantly elevates score**

animals, vermin, horde, savages, barbarians, filth, scum, disease, cancer, plague, infestation, cockroaches, rats, parasites, swarm, locusts, monsters, beasts, creatures, subhuman, inhuman, demons, devils, spawn

### HUMANIZING_WORDS
(For contrast detection - presence on one side, absence on other indicates asymmetric humanization)

families, children, names, stories, individuals, people, persons, neighbors, community, loved ones, parents, mothers, fathers, sons, daughters, victims, survivors, heroes

### OTHERING_WORDS
enemy, threat, invader, outsider, foreigner, alien, stranger, intruder, infiltrator, hostile, adversary, opponent, foe, rival, antagonist, aggressor

### GROUP_IDENTITY_PHRASES
"us vs them", "with us or against us", "one of us", "the elites", "sheeple", "truth seekers", "real patriots", "true believers", "the people", "ordinary citizens", "silent majority", "woke mob", "radical left", "extreme right", "deep state", "the establishment"

---

## Attribution Vocabulary

### CREDIBLE_ATTRIBUTION_VERBS
(Applied to favored sources - signals trust)

stated, confirmed, said, reported, announced, explained, noted, emphasized, clarified, disclosed, revealed, established, demonstrated, proved, verified, documented

### DISCREDITING_ATTRIBUTION_VERBS
(Applied to disfavored sources - signals doubt)

claimed, alleged, insisted, demanded, ranted, asserted, contended, maintained, purported, suggested, speculated, insinuated, accused, blamed, charged

### ONE_SIDED_SOURCE_PHRASES
"officials say", "sources say", "according to officials", "declined to comment", "could not be reached", "refused to respond", "did not return calls", "unavailable for comment"

---

## Framing Vocabulary

### EUPHEMISM_WORDS
collateral damage, neutralized, eliminated, pacified, enhanced interrogation, surgical strike, kinetic action, clashes, incident, altercation, confrontation, engagement, operation, intervention, police action, security measures, crowd control, population transfer, ethnic cleansing (sanitized), regime change

### PASSIVE_VOICE_INDICATORS
(Hiding agency - who did what to whom)

"was killed", "were destroyed", "were injured", "situation escalated", "violence erupted", "shots were fired", "mistakes were made", "casualties occurred", "conflict broke out", "tensions rose", "tragedy struck", "lives were lost"

### AGENCY_OMISSION_PHRASES
"the situation deteriorated", "tensions rose", "conflict broke out", "violence flared", "hostilities resumed", "unrest spread", "chaos ensued", "tragedy unfolded", "disaster struck"

---

## Logical Fallacy Vocabulary

### WHATABOUTISM_PHRASES
"but what about", "what about when", "you also", "they did it too", "look at what they did", "remember when", "why don't you mention", "where was the outrage when", "hypocritical because"

### FALSE_EQUIVALENCE_PHRASES
"both sides", "equally responsible", "mutual", "reciprocal", "bilateral", "shared blame", "all parties", "everyone is guilty", "six of one", "two sides of the same coin", "just as bad"

### DEFLECTION_PHRASES
"that's not the real issue", "let's focus on", "the real problem is", "what really matters", "the bigger picture", "more importantly", "the actual concern", "beside the point"

### SMEAR_PHRASES
(Without substantiation = manipulation)

"known ties to", "funded by", "connected to", "linked to", "associated with", "has connections to", "backed by", "in the pocket of", "working for", "serving the interests of"

---

## Conspiracy Vocabulary

### CONSPIRACY_WORDS
cover-up, agenda, narrative, mainstream, controlled, puppet, shill, plant, asset, handler, operative, deep state, shadow government, new world order, false flag, inside job, psy-op, controlled opposition

### CONSPIRACY_PHRASES
"what they don't want you to know", "the truth about", "wake up", "open your eyes", "do your own research", "follow the money", "connect the dots", "hidden agenda", "they're hiding", "mainstream won't tell you", "censored truth", "banned information"

---

## Suppression Vocabulary

### CRITIC_LABELS
(Used to dismiss without engaging arguments)

conspiracy theorist, denier, extremist, radical, fringe, crackpot, lunatic, shill, bot, troll, agent, operative, propagandist, disinformation spreader, misinformation peddler, anti-vaxxer, climate denier, truther, birther

### SILENCING_PHRASES
"dangerous misinformation", "harmful content", "must be stopped", "should be banned", "needs to be removed", "platform should", "shouldn't be allowed to", "no place for", "spreading lies"

---

## Quality Indicators (Positive)

These indicate LOWER manipulation - their presence suggests more balanced content.

### FACTUAL_INDICATORS
"according to", "data shows", "study found", "research indicates", "evidence suggests", "analysis reveals", "statistics show", "peer-reviewed", "published in", "methodology", "sample size", "margin of error"

### QUALIFIER_WORDS
however, although, nevertheless, conversely, alternatively, nonetheless, on the other hand, despite, while, yet, except, unless, arguably, potentially, possibly, perhaps, may, might, could, seemingly, apparently

### PERSPECTIVE_PHRASES
"critics argue", "supporters say", "some believe", "others contend", "proponents claim", "opponents counter", "one view holds", "another perspective", "different interpretations", "debate continues"

### CONTEXT_WORDS
historically, previously, in context, background, origins, development, evolution, timeline, chronology, precedent, prior to, subsequently, following, before this

---

## Usage Notes

1. **Vocabulary presence alone doesn't prove manipulation** - context matters
2. **Asymmetric application is key** - credible verbs for "us", discrediting for "them"
3. **Density matters** - isolated instances vs. pervasive patterns
4. **Dehumanizing words have heavy weight (0.8)** - single instance is significant
5. **Quality indicators reduce scores** - their presence suggests balanced content
6. **Cross-reference with categories.md** for scoring thresholds
```

**Step 2: Verify file created**

Run: `ls -la synapti-marketplace/plugins/decipon/skills/nci-analysis/references/vocabulary.md`
Expected: File exists with content

**Step 3: Commit**

```bash
git add synapti-marketplace/plugins/decipon/skills/nci-analysis/references/vocabulary.md
git commit -m "feat(decipon): add vocabulary.md detection reference

Comprehensive English vocabulary lists for manipulation detection:
- Emotional manipulation vocabulary (fear, anger, guilt, urgency, novelty)
- Tribal division vocabulary (dehumanizing with 0.8 weight, humanizing, othering)
- Attribution vocabulary (credible vs discrediting verbs)
- Framing vocabulary (euphemisms, passive voice, agency omission)
- Logical fallacy vocabulary (whataboutism, false equivalence, smears)
- Conspiracy and suppression vocabulary
- Quality indicators (positive signals)"
```

---

## Task 2: Create guidance.md

**Files:**
- Create: `synapti-marketplace/plugins/decipon/skills/nci-analysis/references/guidance.md`

**Step 1: Create the guidance reference file**

```markdown
# NCI Actionable Guidance Reference

User-facing tips displayed when composite factors exceed thresholds. Helps users act on findings rather than just receiving scores.

---

## Display Thresholds

| Condition | Action |
|-----------|--------|
| Factor score > 2.5 (on 1-5 scale) | Show factor-specific tips |
| Overall score > 25 | Show summary guidance |
| Overall score > 50 | Show verification recommendations |
| Overall score > 75 | Show strong warning |

---

## Factor-Specific Tips

### Emotional Manipulation (when composite > 2.5)

Display these tips when Emotional Manipulation factor exceeds 2.5:

- "What facts support this emotional response?"
- "Is the emotional intensity proportional to the actual situation?"
- "Would this information be equally valid without the emotional language?"
- "Try mentally removing emotional adjectives - what claims remain?"

**Advanced detection tips:**
- Check trigger density (emotional words / total words)
- Note ALL CAPS usage and exclamation density
- Compare emotional vocabulary distribution (fear vs anger vs guilt)

---

### Suspicious Timing (when composite > 2.5)

Display these tips when Suspicious Timing factor exceeds 2.5:

- "Why is this emerging now? What recent events does it connect to?"
- "Who benefits if this narrative is believed?"
- "Who benefits if this narrative is dismissed?"
- "What was the news cycle like when this appeared?"

**Advanced detection tips:**
- Check publication date against political/economic calendar
- Identify all potential beneficiaries
- Research if similar narratives appeared before key events

---

### Uniform Messaging (when composite > 2.5)

Display these tips when Uniform Messaging factor exceeds 2.5:

- "Look for independent sources with different framing"
- "Are multiple outlets using identical phrases?"
- "Search for the same claim with different wording"
- "Check if 'experts' cited are the same across sources"

**Advanced detection tips:**
- Search key phrases in quotes to find identical usage
- Check publication timestamps for coordinated release
- Identify original source vs amplifiers

---

### Tribal Division (when composite > 2.5)

Display these tips when Tribal Division factor exceeds 2.5:

- "Consider the other side's perspective charitably"
- "Who is humanized with names/stories vs. reduced to statistics?"
- "Watch for dehumanizing language (animals, vermin, horde)"
- "Are there legitimate concerns on the 'other side' being ignored?"

**Advanced detection tips:**
- Calculate pronoun ratio: (we+us+our) / (they+them+their)
- Check for asymmetric humanization (names vs. numbers)
- Flag any dehumanizing vocabulary (0.8 weight each)

---

### Missing Information (when composite > 2.5)

Display these tips when Missing Information factor exceeds 2.5:

- "What questions aren't being answered?"
- "Notice attribution asymmetry: 'stated' vs 'claimed'"
- "Who is quoted and who is not? Who 'declined to comment'?"
- "Watch for passive voice hiding responsibility"
- "What context or history is omitted?"

**Advanced detection tips:**
- Check context completeness (qualifiers + perspectives per 100 words)
- Compare attribution verbs for different sources
- Identify what's conspicuously absent

---

## Advanced Detection Tips

### Framing Techniques

When framing manipulation is detected:

- "Notice who performs actions vs. who is acted upon"
- "Watch for euphemisms: 'clashes' vs 'attack', 'neutralized' vs 'killed'"
- "Passive voice often hides agency: 'mistakes were made' by whom?"
- "Compare how similar actions are described for different actors"

### Logical Fallacies

When logical fallacies are detected:

- "Watch for 'but what about...' deflections (whataboutism)"
- "'Both sides' framing may create false equivalence"
- "Smears without evidence: 'known ties to', 'funded by'"
- "Check if arguments address claims or attack people"

### Authority Issues

When authority problems are detected:

- "Verify expert credentials match the topic"
- "Check for undisclosed conflicts of interest"
- "Are 'experts' named or anonymous?"
- "Is the same expert cited across multiple 'independent' sources?"

---

## Summary Guidance by Score

Include this summary based on overall NCI score:

| Score Range | Indicator | Summary Guidance |
|-------------|-----------|------------------|
| 76-100 | [!!!] | "Significant manipulation indicators detected. Verify ALL claims independently before sharing. Exercise strong skepticism." |
| 51-75 | [!!] | "Notable manipulation patterns present. Cross-reference with independent sources before accepting claims." |
| 26-50 | [!] | "Some concerning indicators detected. Verify key claims before accepting or sharing." |
| 0-25 | [·] | No summary needed - content appears to use legitimate communication patterns. |

---

## Verification Recommendations

When overall score > 50, add these action items:

1. **Source verification**: Check original sources cited, not just the article
2. **Counter-search**: Search for opposing viewpoints on the same topic
3. **Timeline check**: Verify timing claims against independent records
4. **Expert verification**: Confirm expert credentials and potential conflicts
5. **Historical context**: Research background the article may have omitted

---

## Report Integration

When generating NCI reports, include guidance as follows:

```markdown
## Actionable Guidance

Based on the analysis, consider:

[Insert relevant factor-specific tips for factors > 2.5]

### Recommended Actions
[Insert verification recommendations if score > 50]

### Summary
[Insert summary guidance based on overall score]
```

---

## Cross-References

- See `vocabulary.md` for detection word lists
- See `categories.md` for full category definitions
- See `scoring.md` for quantitative formulas
- See `examples.md` for historical calibration
```

**Step 2: Verify file created**

Run: `ls -la synapti-marketplace/plugins/decipon/skills/nci-analysis/references/guidance.md`
Expected: File exists with content

**Step 3: Commit**

```bash
git add synapti-marketplace/plugins/decipon/skills/nci-analysis/references/guidance.md
git commit -m "feat(decipon): add guidance.md actionable tips reference

Actionable guidance for users based on NCI analysis:
- Display thresholds for when to show tips
- Factor-specific tips for all 5 composite factors
- Advanced detection tips for framing and fallacies
- Summary guidance by score range
- Verification recommendations for high scores
- Report integration template"
```

---

## Task 3: Update SKILL.md with First Principles and References

**Files:**
- Modify: `synapti-marketplace/plugins/decipon/skills/nci-analysis/SKILL.md`

**Step 1: Read current SKILL.md to identify insertion points**

Run: `head -50 synapti-marketplace/plugins/decipon/skills/nci-analysis/SKILL.md`

**Step 2: Add First Principles section after Quick Start**

Insert after "## Quick Start" section (around line 26):

```markdown
## First Principles (Summary)

The NCI Protocol is grounded in these principles (see `agents/perspective-generator.md` for full version):

1. **Evidence over authority** - Evaluate patterns in content, not source reputation
2. **Steel-man interpretation** - Present strongest version of each perspective
3. **Atomic decomposition** - Break claims into smallest verifiable units
4. **Source agnosticism** - Apply identical standards regardless of source alignment
5. **Bidirectional beneficiary analysis** - Ask who benefits if believed AND if dismissed
6. **Pattern vs. Intent** - Focus on techniques; deep research evidence can inform motives

These principles ensure fair, consistent analysis across all content regardless of political or ideological alignment.
```

**Step 3: Update References section at end of file**

Replace existing References section with:

```markdown
## References

- [references/categories.md](references/categories.md) - All 20 category definitions with detection signals
- [references/scoring.md](references/scoring.md) - Scoring methodology, weights, and quantitative formulas
- [references/examples.md](references/examples.md) - Historical case studies for calibration
- [references/vocabulary.md](references/vocabulary.md) - Detection vocabulary lists
- [references/guidance.md](references/guidance.md) - Actionable tips per factor
```

**Step 4: Commit**

```bash
git add synapti-marketplace/plugins/decipon/skills/nci-analysis/SKILL.md
git commit -m "feat(decipon): add First Principles and update references in SKILL.md

- Add First Principles summary section (6 core principles)
- Update References to include new vocabulary.md and guidance.md
- Cross-reference perspective-generator for full principles"
```

---

## Task 4: Update scoring.md with Quantitative Formulas

**Files:**
- Modify: `synapti-marketplace/plugins/decipon/skills/nci-analysis/references/scoring.md`

**Step 1: Add Quantitative Detection Formulas section**

Insert before "## Output Formats" section:

```markdown
---

## Quantitative Detection Formulas

These formulas improve scoring reproducibility. Use as guidelines alongside qualitative assessment.

### Emotional Trigger Density (Categories 1-5)

```
trigger_density = emotional_words / total_words
```

| Density | Score | Interpretation |
|---------|-------|----------------|
| < 0.02 | 1 | Minimal emotional language |
| 0.02-0.05 | 2 | Low emotional content |
| 0.05-0.10 | 3 | Moderate emotional content |
| 0.10-0.15 | 4 | High emotional content |
| > 0.15 | 5 | Overwhelming emotional language |

### Intensity Detection

```
caps_ratio = ALL_CAPS_words / total_words
exclamation_density = exclamation_marks / sentences
```

| Indicator | Threshold | Impact |
|-----------|-----------|--------|
| caps_ratio > 0.05 | Elevated | +0.5 to emotional scores |
| caps_ratio > 0.20 | Maximum | +1.0 to emotional scores |
| exclamation_density > 0.3 | Elevated | +0.5 to urgency score |
| exclamation_density > 0.5 | High | +1.0 to urgency score |
| Repeated punctuation (!!!, ???) | Present | Intensity marker |

### Pronoun Ratio (Category 12: Tribal Division)

```
tribal_ratio = (we + us + our) / (they + them + their + 1)
```

| Ratio | Score Guidance | Interpretation |
|-------|----------------|----------------|
| < 1.5 | 1-2 | Balanced, inclusive language |
| 1.5-3.0 | 2-3 | Mild tribal framing |
| 3.0-5.0 | 3-4 | Notable tribal division |
| > 5.0 | 4-5 | Strong us-vs-them dynamic |

### Repetition Thresholds (Category 4)

| Key Phrase Instances | Score |
|---------------------|-------|
| 0 | 1 |
| 1-2 | 2 |
| 3-5 | 3 |
| 6-10 | 4 |
| > 10 | 5 |

### Context Completeness (Category 15)

```
Expected per 100 words:
- 2 qualifier words (however, although, nevertheless, etc.)
- 1 perspective phrase (critics say, supporters argue, etc.)

completeness = (qualifiers + perspectives) / expected_count
```

| Completeness | Score | Interpretation |
|--------------|-------|----------------|
| > 80% | 1-2 | Comprehensive, balanced |
| 50-80% | 2-3 | Adequate context |
| 25-50% | 3-4 | Limited perspectives |
| < 25% | 4-5 | One-sided presentation |

### Dehumanization Penalty (Category 12)

**CRITICAL: Heavy weight for dehumanizing language**

```
Each dehumanizing word detected: +0.8 to tribal division score
```

Examples triggering penalty:
- animals, vermin, horde, savages, barbarians
- filth, scum, disease, cancer, plague
- cockroaches, rats, parasites, infestation

A single instance can elevate the tribal division score by nearly one full point.

### Attribution Asymmetry (Category 15, 20)

```
asymmetry_score = credible_verbs_for_us - credible_verbs_for_them
```

| Asymmetry | Impact |
|-----------|--------|
| Balanced (< 2 difference) | No penalty |
| Moderate (2-4 difference) | +0.5 to framing score |
| Strong (> 4 difference) | +1.0 to framing score |

See `vocabulary.md` for credible vs. discrediting verb lists.
```

**Step 2: Expand Confidence Calculation section**

Add after existing confidence section:

```markdown
### Word Count Confidence Adjustment

Longer content provides more evidence for reliable scoring:

```
base_confidence = 0.80
word_count_adjustment = min((word_count / 500) × 0.05, max_adjustment)
final_confidence = min(base_confidence + word_count_adjustment, 0.95)
```

| Analysis Type | Base | Max Adjustment | Max Final |
|---------------|------|----------------|-----------|
| Standard rule-based | 0.80 | +0.05 | 0.85 |
| NLP-enhanced | 0.80 | +0.05 | 0.85 |
| Text-only fallback | 0.70 | +0.05 | 0.75 |
| Context-dependent (with external data) | 0.80 | +0.10 | 0.90 |
| Context-dependent (no external data) | 0.45 | +0.10 | 0.55 |

**Word count examples:**

| Word Count | Adjustment | Typical Final Confidence |
|------------|------------|--------------------------|
| < 100 | +0.01 | 0.81 (show low confidence warning) |
| 250 | +0.025 | 0.825 |
| 500 | +0.05 | 0.85 |
| 1000+ | +0.05 (capped) | 0.85 |

**Short content warning:**

When word_count < 100, include in report:
> "⚠️ Limited content length (< 100 words) may reduce scoring reliability. Results should be interpreted with caution."

**Remember:** Maximum confidence is always capped at 0.95 per NCI Protocol - never claim 100% certainty.
```

**Step 3: Commit**

```bash
git add synapti-marketplace/plugins/decipon/skills/nci-analysis/references/scoring.md
git commit -m "feat(decipon): add quantitative formulas and confidence calibration

Quantitative detection formulas:
- Emotional trigger density thresholds
- Intensity detection (caps, exclamation)
- Pronoun ratio for tribal division
- Repetition counting thresholds
- Context completeness calculation
- Dehumanization penalty (0.8 weight)
- Attribution asymmetry scoring

Confidence calibration:
- Word count adjustment formula
- Analysis type confidence table
- Short content warning threshold"
```

---

## Task 5: Update categories.md with Enhanced Detection Signals

**Files:**
- Modify: `synapti-marketplace/plugins/decipon/skills/nci-analysis/references/categories.md`

**Step 1: Enhance Category 12 (Tribal Division) with dehumanization**

Find Category 12 section and add after Detection Signals table:

```markdown
#### Enhanced Detection Signals

**Vocabulary references** (see vocabulary.md):
- DEHUMANIZING_WORDS: animals, vermin, horde, savages, barbarians, filth, scum, disease, cancer, plague, cockroaches, rats, parasites
- HUMANIZING_WORDS: families, children, names, stories, individuals
- OTHERING_WORDS: enemy, threat, invader, outsider, foreigner
- GROUP_IDENTITY_PHRASES: "us vs them", "with us or against us", "real patriots"

**Critical patterns:**
- **Dehumanization** (WEIGHT: 0.8 penalty each): Any word reducing humans to animals/disease/vermin
- **Asymmetric humanization**: One side gets names/stories, other side gets statistics/collectives
- **Pronoun imbalance**: High (we+us+our) / (they+them+their) ratio suggests tribal framing

**Quantitative thresholds:**
- Pronoun ratio > 3:1 suggests notable tribal framing
- Any dehumanizing word = automatic score increase (+0.8)
- Asymmetric humanization (names vs. statistics) = +1.0 to score
```

**Step 2: Enhance Category 15 (Missing Information) with attribution asymmetry**

Find Category 15 section and add:

```markdown
#### Enhanced Detection Signals

**Vocabulary references** (see vocabulary.md):
- CREDIBLE_ATTRIBUTION_VERBS: stated, confirmed, said, reported, announced, explained
- DISCREDITING_ATTRIBUTION_VERBS: claimed, alleged, insisted, demanded, ranted, asserted
- ONE_SIDED_SOURCE_PHRASES: "officials say", "sources say", "declined to comment"
- PASSIVE_VOICE_INDICATORS: "was killed", "were destroyed", "mistakes were made"

**Critical patterns:**
- **Attribution asymmetry**: Credible verbs for "us" (stated, confirmed), skeptical verbs for "them" (claimed, alleged)
- **One-sided sourcing**: Only certain perspectives quoted, others "declined to comment"
- **Passive voice agency hiding**: "Mistakes were made" without identifying who made them
- **Context stripping**: Key historical or situational context omitted

**Quantitative thresholds:**
- Context completeness: Expect 2 qualifiers + 1 perspective phrase per 100 words
- Attribution asymmetry > 4 instances = +1.0 to score
- "Declined to comment" without attempt to include perspective = +0.5
```

**Step 3: Enhance Category 19 (Logical Fallacies) with specific patterns**

Find Category 19 section and add:

```markdown
#### Enhanced Detection Signals

**Vocabulary references** (see vocabulary.md):
- WHATABOUTISM_PHRASES: "but what about", "what about when", "you also", "they did it too"
- FALSE_EQUIVALENCE_PHRASES: "both sides", "equally responsible", "mutual", "reciprocal"
- DEFLECTION_PHRASES: "that's not the real issue", "let's focus on", "the real problem is"
- SMEAR_PHRASES: "known ties to", "funded by", "connected to" (without substantiation)

**Critical patterns:**
- **Whataboutism**: Deflecting criticism by pointing to others' actions ("But what about X?")
- **Tu quoque**: Justifying behavior because others did it too
- **False equivalence**: Creating false "both sides" symmetry when evidence is asymmetric
- **Smears without evidence**: Association claims without substantiation ("known ties to")
- **Symmetry forcing**: Misusing "mutual", "reciprocal", "bilateral" to imply equal responsibility

**Detection guidance:**
- Count distinct fallacy types (not just instances)
- Smears require checking if substantiation is provided
- False equivalence requires comparing actual evidence for each "side"
```

**Step 4: Enhance Category 20 (Framing Techniques) with euphemism detection**

Find Category 20 section and add:

```markdown
#### Enhanced Detection Signals

**Vocabulary references** (see vocabulary.md):
- EUPHEMISM_WORDS: collateral damage, neutralized, enhanced interrogation, surgical strike, clashes, incident
- PASSIVE_VOICE_INDICATORS: "was killed", "were destroyed", "situation escalated", "violence erupted"
- AGENCY_OMISSION_PHRASES: "the situation deteriorated", "tensions rose", "conflict broke out"

**Critical patterns:**
- **Passive voice hiding agency**: "Workers were killed" vs "Company killed workers"
- **Agency omission**: "Situation escalated" vs "Forces escalated situation"
- **Euphemistic language**: "Collateral damage" vs "Civilian deaths", "Neutralized" vs "Killed"
- **Violence softening**: "Incident", "altercation", "confrontation" vs accurate descriptions
- **Comparative framing**: How similar actions are described for different actors

**Detection guidance:**
- Compare descriptions of similar actions by different parties
- Check if passive voice consistently hides specific actors
- Note euphemism patterns across the content
```

**Step 5: Commit**

```bash
git add synapti-marketplace/plugins/decipon/skills/nci-analysis/references/categories.md
git commit -m "feat(decipon): enhance detection signals for key categories

Enhanced detection signals with vocabulary references:
- Category 12: Dehumanization (0.8 weight), asymmetric humanization, pronoun ratio
- Category 15: Attribution asymmetry, passive voice agency hiding
- Category 19: Whataboutism, false equivalence, smears, deflection
- Category 20: Euphemisms, passive voice, agency omission

All enhancements reference vocabulary.md for word lists"
```

---

## Task 6: Update perspective-generator.md with First Principles

**Files:**
- Modify: `synapti-marketplace/plugins/decipon/agents/perspective-generator.md`

**Step 1: Add First Principles section at top (after Purpose)**

Insert after "## Purpose" section:

```markdown
## First Principles (NCI Protocol Foundation)

Before generating perspectives, internalize these principles:

### 1. Evidence Over Authority
Evaluate patterns in the content itself, not source reputation. A prestigious outlet can use manipulation techniques; an unknown source can present information fairly. Judge the content, not the masthead.

### 2. Steel-Man Interpretation
Present the STRONGEST version of each perspective. Don't strawman the legitimate interpretation or understate the manipulative one. Give each interpretation its most compelling formulation.

### 3. Atomic Decomposition
Break claims into smallest verifiable units. "Experts say X causes Y" contains multiple claims: Who are the experts? What's their evidence? Is causation established? Decompose before evaluating.

### 4. Source Agnosticism
Apply identical standards regardless of political/ideological alignment. Manipulation techniques are manipulation techniques, regardless of who uses them. Your analysis should be indistinguishable across the political spectrum.

### 5. Bidirectional Beneficiary Analysis
Ask BOTH questions:
- Who benefits if this narrative is **believed**?
- Who benefits if this narrative is **dismissed**?

Both directions reveal potential motivations for manipulation. One-sided beneficiary analysis is itself a form of bias.

### 6. Pattern vs. Intent
Focus primarily on detecting TECHNIQUES rather than assuming MOTIVES from patterns alone. We can identify manipulation patterns without claiming certainty about intent.

**However:** Evidence gathered through deep research (beneficiary analysis, timing correlations, documented coordination, financial trails) CAN inform assessments of likely intent. When such evidence exists, incorporate it into perspective generation with appropriate confidence levels.

- Pattern alone → Low confidence about intent
- Pattern + corroborating evidence → Higher confidence about intent
```

**Step 2: Add Execution Pattern section**

Insert before "## Output Format" section:

```markdown
## Execution Pattern

For optimal performance, perspectives should be generated with this structure:

```
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
```

**Execution notes:**
- Red Team and Blue Team can run simultaneously (no dependencies between them)
- Synthesis MUST wait for both to complete (it weighs and compares their outputs)
- If either perspective fails, Synthesis uses available data with reduced confidence
- Total confidence cannot exceed 0.95 even with strong evidence
```

**Step 3: Commit**

```bash
git add synapti-marketplace/plugins/decipon/agents/perspective-generator.md
git commit -m "feat(decipon): add First Principles and Execution Pattern

First Principles (6 core principles):
1. Evidence over authority
2. Steel-man interpretation
3. Atomic decomposition
4. Source agnosticism
5. Bidirectional beneficiary analysis
6. Pattern vs Intent (with deep research nuance)

Execution Pattern:
- Red Team / Blue Team parallel execution
- Synthesis sequential (depends on both)
- Failure handling with reduced confidence"
```

---

## Task 7: Update nci-analyzer.md with Detection References

**Files:**
- Modify: `synapti-marketplace/plugins/decipon/agents/nci-analyzer.md`

**Step 1: Add Detection Methodology section**

Insert after "## Integration Points" section:

```markdown
## Detection Methodology

For detailed detection signals and vocabulary during analysis, reference:

| Resource | Purpose |
|----------|---------|
| `skills/nci-analysis/references/categories.md` | Detection signals per category |
| `skills/nci-analysis/references/vocabulary.md` | Word lists for pattern matching |
| `skills/nci-analysis/references/scoring.md` | Quantitative formulas and thresholds |
| `skills/nci-analysis/references/guidance.md` | Actionable tips for users |

### Key Detection Patterns

During analysis, pay special attention to:

1. **Dehumanization** (Category 12): Any word reducing humans to animals/disease/vermin carries 0.8 weight penalty
2. **Attribution asymmetry** (Category 15, 20): Credible verbs for "us", skeptical verbs for "them"
3. **Passive voice agency hiding** (Category 20): "Mistakes were made" hiding who made them
4. **Whataboutism** (Category 19): "But what about X?" deflections
5. **Asymmetric humanization** (Category 12): Names/stories for one side, statistics for other

### Guidance Integration

When generating output, include actionable guidance based on thresholds:

- Factor score > 2.5 → Include factor-specific tips from `guidance.md`
- Overall score > 50 → Include verification recommendations
- Overall score > 75 → Include strong warning

See `skills/nci-analysis/references/guidance.md` for complete tip text.
```

**Step 2: Commit**

```bash
git add synapti-marketplace/plugins/decipon/agents/nci-analyzer.md
git commit -m "feat(decipon): add detection methodology and guidance references

- Reference all detection resources (vocabulary, categories, scoring, guidance)
- Highlight key detection patterns (dehumanization, attribution asymmetry, etc.)
- Add guidance integration thresholds for output generation"
```

---

## Task 8: Final Validation

**Step 1: Verify all files exist**

```bash
ls -la synapti-marketplace/plugins/decipon/skills/nci-analysis/references/
```

Expected output shows: categories.md, examples.md, guidance.md, scoring.md, vocabulary.md

**Step 2: Verify cross-references work**

Check that SKILL.md references all 5 reference files.

**Step 3: Run final commit for any remaining changes**

```bash
git status
# If any uncommitted changes:
git add -A
git commit -m "chore(decipon): final cleanup for NCI Protocol enhancements"
```

**Step 4: Create summary commit (optional)**

```bash
git log --oneline -10
```

---

## Validation Checklist

After implementation, verify:

- [ ] vocabulary.md exists with all vocabulary lists (English only)
- [ ] guidance.md exists with all factor tips and thresholds
- [ ] SKILL.md has First Principles summary
- [ ] SKILL.md References section includes vocabulary.md and guidance.md
- [ ] scoring.md has Quantitative Detection Formulas section
- [ ] scoring.md has Word Count Confidence Adjustment
- [ ] categories.md Category 12 has dehumanization (0.8 weight) documented
- [ ] categories.md Category 15 has attribution asymmetry documented
- [ ] categories.md Category 19 has whataboutism/false equivalence documented
- [ ] categories.md Category 20 has euphemism/passive voice documented
- [ ] perspective-generator.md has First Principles (full version)
- [ ] perspective-generator.md has Execution Pattern diagram
- [ ] nci-analyzer.md references detection resources
- [ ] All commits have descriptive messages
