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
