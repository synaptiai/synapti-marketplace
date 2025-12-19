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
