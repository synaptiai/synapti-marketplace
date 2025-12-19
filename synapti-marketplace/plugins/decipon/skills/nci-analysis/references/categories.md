# NCI Category Reference

All 20 manipulation detection categories with scoring criteria and detection signals.

## Contents
- [Emotional Manipulation (Categories 1-5)](#emotional-manipulation-categories-1-5)
- [Suspicious Timing (Categories 6-8)](#suspicious-timing-categories-6-8)
- [Uniform Messaging (Categories 9-11)](#uniform-messaging-categories-9-11)
- [Tribal Division (Categories 12-14)](#tribal-division-categories-12-14)
- [Missing Information (Categories 15-20)](#missing-information-categories-15-20)
- [Quick Reference Table](#quick-reference-table)

---

## Emotional Manipulation (Categories 1-5)

Techniques exploiting emotions to bypass rational analysis.

### Category 1: Emotional Manipulation (Base)
**Question**: Does it provoke fear, outrage, or guilt without solid evidence?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Fear vocabulary | danger, threat, crisis, terror, devastating, catastrophic |
| Anger vocabulary | outrage, betrayal, lies, fraud, treason, corrupt |
| Guilt triggers | shame on, how dare, blood on hands, complicit |
| Emotional density | High ratio of emotional words to total words |
| ALL CAPS emphasis | Multiple words in caps for emotional impact |
| Exclamation overuse | Multiple exclamation marks per paragraph |

**Scoring:**
```
1: Neutral tone, emotions proportional to facts
2: Slight emotional coloring, mostly balanced
3: Moderate emotional language, some unsupported claims
4: Strong emotional triggers, limited evidence
5: Overwhelming emotional manipulation, no substantiation
```

**Example Detection:**
```
Text: "This SHOCKING betrayal will DEVASTATE families!"
Signals: ALL CAPS (2), emotional vocabulary (shocking, betrayal, devastate)
Score: 4 - Strong emotional triggers without evidence
```

---

### Category 2: Call for Urgent Action
**Question**: Does it demand immediate decisions without reflection?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Urgency words | immediately, urgent, now, critical, emergency |
| Artificial deadlines | "before midnight", "last chance", "time is running out" |
| Pressure phrases | "act now or", "don't wait", "every second counts" |
| Exclusivity claims | "only you can", "you must be the one" |
| Countdown language | "hours left", "final warning" |

**Scoring:**
```
1: No urgency, reasonable timeline for consideration
2: Mild urgency, days to weeks given
3: Moderate urgency, "soon" but not immediate
4: Strong urgency, hours given, "act now" language
5: Extreme urgency, immediate action demanded, artificial crisis
```

---

### Category 3: Overuse of Novelty
**Question**: Is the event framed as shocking or unprecedented?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Novelty words | unprecedented, shocking, never-before, first-time, historic |
| Superlatives | most, biggest, worst, greatest, ever |
| Breaking claims | "breaking", "just in", "developing" |
| Exclusivity | "you won't believe", "what they don't want you to know" |
| Historical denial | Absence of comparable past events |

**Scoring:**
```
1: Event contextualized historically, proportionate framing
2: Some novelty language, proper historical context
3: Moderate novelty claims, limited context
4: Strong novelty emphasis, minimal historical perspective
5: Overwhelming "unprecedented" claims, no historical context
```

---

### Category 4: Emotional Repetition
**Question**: Are the same emotional triggers repeated excessively?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Phrase repetition | Same emotional phrase 3+ times |
| Image recycling | Same emotional imagery throughout |
| Hammer technique | Central emotional claim restated in every paragraph |
| Variation absence | No varied perspectives, single emotional note |

**Scoring:**
```
1: Varied emotional content, no excessive repetition
2: Some repetition (1-2 repeats of key phrase)
3: Moderate repetition (3-5 repeats)
4: High repetition (6-10 repeats)
5: Excessive repetition (>10 repeats, hammering technique)
```

---

### Category 5: Manufactured Outrage
**Question**: Does outrage seem sudden or disconnected from facts?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Disproportionate response | Outrage level exceeds factual basis |
| Sudden emergence | Issue appeared from nowhere with intense emotion |
| Coordinated timing | Multiple sources expressing identical outrage simultaneously |
| Missing backstory | No explanation of why now, why this intensity |
| Fact-emotion gap | Strong emotions with vague or missing facts |

**Scoring:**
```
1: Outrage proportional to facts, understandable reaction
2: Slight disproportionality, mostly appropriate
3: Moderate imbalance, emotion exceeds facts
4: Strong imbalance, outrage seems manufactured
5: Extreme imbalance, coordinated viral spread, no factual basis
```

---

## Suspicious Timing (Categories 6-8)

Strategic release patterns and beneficiary analysis.

### Category 6: Timing
**Question**: Does the timing feel suspicious or coincidental with other events?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Political correlation | Published near elections, votes, hearings |
| Distraction timing | Released during major breaking news |
| Anniversary manipulation | Timed with emotionally significant dates |
| Pre-emptive release | Published just before contradicting information expected |
| Friday news dump | Released to minimize coverage |

**Scoring:**
```
1: No notable timing correlation
2: Weak correlation, likely coincidental
3: Moderate correlation with one significant event
4: Strong correlation, timing clearly strategic
5: Perfect timing with multiple strategic events
```

---

### Category 7: Financial/Political Gain
**Question**: Do powerful groups benefit disproportionately?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Clear beneficiaries | Specific parties who gain from narrative |
| Follow the money | Financial incentives aligned with message |
| Power consolidation | Message supports concentration of power |
| Opponent harm | Narrative specifically damages opponents |
| Funding opacity | Source funding unclear or hidden |

**Scoring:**
```
1: No clear beneficiaries identifiable
2: Minor beneficiaries, small potential gains
3: Moderate beneficiaries, notable potential gains
4: Major beneficiaries, substantial gains clear
5: Massive beneficiaries, disproportionate gains obvious
```

---

### Category 8: Historical Parallels
**Question**: Does the story mirror manipulative past events?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Known playbook | Matches documented propaganda patterns |
| Atrocity propaganda | Unverifiable claims of extreme cruelty |
| Enemy dehumanization | Parallels historical dehumanization campaigns |
| False flag patterns | Structure similar to known false operations |
| Manufactured consent | Follows manufacturing consent blueprint |

**Scoring:**
```
1: No parallels to known manipulation campaigns
2: Weak similarities, likely coincidental
3: Moderate similarities in 1-2 dimensions
4: Strong similarities across 3-4 dimensions
5: Near-identical pattern to documented manipulation
```

---

## Uniform Messaging (Categories 9-11)

Indicators of coordinated messaging.

### Category 9: Uniform Messaging (Base)
**Question**: Are key phrases or ideas repeated across media?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Identical phrases | Same talking points across sources |
| Simultaneous release | Multiple outlets publish similar content together |
| Template language | Boilerplate phrasing suggests coordination |
| Lack of variation | No unique perspectives across sources |
| Attributed uniformity | "Experts agree", "everyone knows" |

**Scoring:**
```
1: High diversity, unique framing across sources
2: Low uniformity (10-20% phrase overlap)
3: Moderate uniformity (20-40% overlap)
4: High uniformity (40-60% overlap)
5: Extreme uniformity (>60% overlap), clear coordination
```

---

### Category 10: Bandwagon Effect
**Question**: Is there pressure to conform because "everyone is doing it"?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Consensus claims | "everyone agrees", "millions believe" |
| Majority pressure | "most people", "the public demands" |
| Isolation threats | "don't be left behind", "join the movement" |
| Unsubstantiated polls | Vague references to surveys/support |
| Social proof stacking | Multiple testimonials presented as trend |

**Scoring:**
```
1: No conformity pressure, individual reasoning encouraged
2: Mild social proof present
3: Moderate "everyone agrees" messaging
4: Strong bandwagon appeals, isolation implied
5: Overwhelming conformity pressure, dissent demonized
```

---

### Category 11: Rapid Behavior Shifts
**Question**: Are groups adopting symbols or actions without clear reasoning?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Viral adoption | Rapid spread of symbols/slogans |
| Organic disconnect | Spread faster than organic diffusion |
| Unclear origins | Hashtags/symbols appear from nowhere |
| Coordinated action | Multiple groups act simultaneously |
| Script-like behavior | Actions seem rehearsed or templated |

**Scoring:**
```
1: Organic, gradual adoption with clear reasoning
2: Slightly accelerated adoption
3: Rapid adoption with some coordination signs
4: Very rapid, clearly coordinated adoption
5: Instantaneous, highly coordinated, script-like behavior
```

---

## Tribal Division (Categories 12-14)

Us-vs-them dynamics and polarization.

### Category 12: Tribal Division (Base)
**Question**: Does it create an "us vs. them" dynamic?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Pronoun asymmetry | High we/us/our vs they/them/their ratio |
| In-group glorification | "real patriots", "true believers" |
| Out-group vilification | "enemies", "traitors", "threat to our way of life" |
| Boundary markers | Clear definitions of who is in/out |
| Unity demands | "stand together against" |

**Scoring:**
```
1: Inclusive language, no division
2: Slight group differentiation, mostly inclusive
3: Moderate us-vs-them framing
4: Strong tribal messaging, clear boundaries
5: Extreme polarization, dehumanizing language
```

---

### Category 13: Simplistic Narratives
**Question**: Is the story reduced to "good vs. evil" frameworks?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Moral absolutism | "pure evil", "complete corruption" |
| Nuance absence | No acknowledgment of complexity |
| Hero/villain casting | Clear good guys vs bad guys |
| Context stripping | Situational factors ignored |
| Motivation denial | Opponents have no legitimate concerns |

**Scoring:**
```
1: Highly nuanced, complexity acknowledged
2: Some simplification, context maintained
3: Moderate simplification, binary tendencies
4: Strong simplification, good vs evil framing
5: Extreme reductionism, cartoon-like characterization
```

---

### Category 14: False Dilemmas
**Question**: Are only two extreme options presented?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Binary framing | "either X or Y", "with us or against us" |
| Middle ground denial | No compromise options presented |
| Extreme endpoints | Both options are at far ends of spectrum |
| Nuance rejection | Alternatives dismissed without consideration |
| Forced choice | "you must choose", "there is no third way" |

**Scoring:**
```
1: Multiple options presented (>3), nuance encouraged
2: Few options but not strictly binary
3: Primarily binary, alternatives briefly mentioned
4: Strictly binary, alternatives dismissed
5: Absolute binary, "with us or against us" explicit
```

---

## Missing Information (Categories 15-20)

Omissions, suppression, and incomplete presentation.

### Category 15: Missing Information (Base)
**Question**: Are alternative views or critical details excluded?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| One-sided sourcing | Only supporting sources quoted |
| Counter-argument absence | No opposing views presented |
| Context gaps | Critical background omitted |
| Selective facts | Only favorable data included |
| Timeline manipulation | Key events omitted from chronology |

**Scoring:**
```
1: Comprehensive coverage, all sides presented
2: Minor omissions, mostly complete
3: Moderate omissions, key points missing
4: Major omissions, one-sided presentation
5: Extreme omissions, critical context absent
```

---

### Category 16: Authority Overload
**Question**: Are questionable "experts" driving the narrative?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Credential mismatch | Experts outside their field |
| Anonymous experts | "experts say" without naming |
| Credential inflation | Minor qualifications overstated |
| Echo chamber | Same experts across sources |
| Industry ties | Undisclosed conflicts of interest |

**Scoring:**
```
1: Qualified, diverse expert pool, credentials clear
2: Mostly qualified, minor issues
3: Mixed credentials, limited diversity
4: Predominantly unqualified or conflicted experts
5: Exclusively questionable "experts", clear agenda
```

---

### Category 17: Suppression of Dissent
**Question**: Are critics silenced or labeled negatively?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Ad hominem attacks | Critics attacked personally, not their arguments |
| Label dismissal | "conspiracy theorist", "denier", "extremist" |
| Platform removal | Calls to silence/deplatform critics |
| Motive questioning | "paid by", "working for" |
| Credibility destruction | Past mistakes weaponized |

**Scoring:**
```
1: Critics engaged substantively, arguments addressed
2: Some dismissiveness, mostly substantive
3: Moderate ad hominem, some engagement
4: Predominantly ad hominem, little engagement
5: Complete suppression, labeling, calls for silencing
```

---

### Category 18: Cherry-Picked Data
**Question**: Are statistics presented selectively or out of context?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Selective timeframes | Data chosen from favorable periods |
| Methodology hiding | How data gathered not explained |
| Contradicting data ignored | Inconvenient statistics omitted |
| Relative vs absolute | Using whichever looks more dramatic |
| Source obscuring | Vague attribution for numbers |

**Scoring:**
```
1: Comprehensive data, full context, methodology clear
2: Mostly complete, minor omissions
3: Moderate selectivity, some context
4: Highly selective, minimal context
5: Extreme cherry-picking, no context, misleading presentation
```

---

### Category 19: Logical Fallacies
**Question**: Are flawed arguments used to dismiss critics?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Whataboutism | "But what about X?" deflection |
| False equivalence | "Both sides equally responsible" when evidence asymmetric |
| Ad hominem | Attacking person, not argument |
| Straw man | Misrepresenting opponent's position |
| Appeal to authority | "Expert says" without reasoning |
| Slippery slope | Extreme consequences predicted without justification |

**Scoring:**
```
1: No significant fallacies, sound reasoning
2: 1-2 minor fallacies
3: 3-5 moderate fallacies
4: 6-10 significant fallacies
5: Pervasive fallacious reasoning throughout
```

---

### Category 20: Framing Techniques
**Question**: Is the story shaped to control how you perceive it?

**Detection Signals:**
| Signal | Pattern |
|--------|---------|
| Passive voice hiding | "Mistakes were made" hiding agency |
| Euphemistic language | "Collateral damage", "enhanced interrogation" |
| Attribution asymmetry | "Stated/confirmed" vs "claimed/alleged" |
| Selective emphasis | Burying key facts, highlighting preferred ones |
| Metaphor manipulation | Loaded metaphors shaping perception |

**Scoring:**
```
1: Neutral framing, multiple perspectives, clear agency
2: Slight bias, mostly balanced
3: Moderate framing bias visible
4: Strong framing, limited perspectives
5: Extreme framing control, single perspective enforced
```

---

## Quick Reference Table

| # | Category | Composite Factor | Weight |
|---|----------|-----------------|--------|
| 1 | Emotional Manipulation (Base) | Emotional Manipulation | 0.35 |
| 2 | Call for Urgent Action | Emotional Manipulation | 0.20 |
| 3 | Overuse of Novelty | Emotional Manipulation | 0.15 |
| 4 | Emotional Repetition | Emotional Manipulation | 0.15 |
| 5 | Manufactured Outrage | Emotional Manipulation | 0.15 |
| 6 | Timing | Suspicious Timing | 0.50 |
| 7 | Financial/Political Gain | Suspicious Timing | 0.35 |
| 8 | Historical Parallels | Suspicious Timing | 0.15 |
| 9 | Uniform Messaging (Base) | Uniform Messaging | 0.50 |
| 10 | Bandwagon Effect | Uniform Messaging | 0.25 |
| 11 | Rapid Behavior Shifts | Uniform Messaging | 0.25 |
| 12 | Tribal Division (Base) | Tribal Division | 0.40 |
| 13 | Simplistic Narratives | Tribal Division | 0.35 |
| 14 | False Dilemmas | Tribal Division | 0.25 |
| 15 | Missing Information (Base) | Missing Information | 0.25 |
| 16 | Authority Overload | Missing Information | 0.15 |
| 17 | Suppression of Dissent | Missing Information | 0.15 |
| 18 | Cherry-Picked Data | Missing Information | 0.20 |
| 19 | Logical Fallacies | Missing Information | 0.15 |
| 20 | Framing Techniques | Missing Information | 0.10 |
