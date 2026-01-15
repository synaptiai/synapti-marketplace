---
description: Quick NCI manipulation score (0-100) with severity indicator and top findings - use for rapid content triage
---

# Quick NCI Score

Get a rapid manipulation assessment score without full analysis.

## Usage

```
/decipon:score <URL or text content>
```

## Purpose

Get a rapid manipulation assessment when you need:
- Quick triage of content
- Score only, not full analysis
- Fast check before deeper analysis

## Workflow

1. **Process Input**
   - Detect if URL, file, or text
   - Fetch/read content as needed

2. **Quick Category Assessment**
   - Score all 20 categories (brief evidence)
   - Focus on most salient indicators

3. **Calculate Score**
   - Compute composite factors
   - Generate overall 0-100 score

4. **Output Quick Summary**
   - Score with severity indicator
   - Top 3 findings only
   - Recommendation for action

## Output Format

```
═══════════════════════════════════════════════════
  NCI QUICK SCORE
═══════════════════════════════════════════════════

  SCORE: 72/100 [!!]

  Severity: HIGH
  Confidence: 78%

  TOP FINDINGS:
  1. Strong emotional manipulation (urgency, fear)
  2. Clear us-vs-them framing
  3. Missing alternative perspectives

  RECOMMENDATION: Cross-reference with independent sources

  Run /decipon:analyze for full report
═══════════════════════════════════════════════════
```

## Severity Scale

| Score | Indicator | Level | Quick Guidance |
|-------|-----------|-------|----------------|
| 0-25 | `[·]` | LOW | Normal consumption |
| 26-50 | `[!]` | MODERATE | Verify key claims |
| 51-75 | `[!!]` | HIGH | Cross-reference sources, strong skepticism |
| 76-100 | `[!!!]` | SEVERE | Likely manipulation |

## Example Invocations

**Quick score of URL:**
```
/decipon:score https://example.com/article
```

**Quick score of text:**
```
/decipon:score Everyone agrees this is the most important issue ever!
```

## When to Use Full Analysis

After quick score, run `/decipon:analyze` when:
- Score > 40 (upper Moderate or higher)
- Need evidence for the score
- Want dual perspectives
- Need to share/document findings
- Score is borderline (40-55 range)

## Difference from /decipon:analyze

| Aspect | /decipon:score | /decipon:analyze |
|--------|----------------|------------------|
| Speed | Fast | Thorough |
| Output | Score + 3 findings | Full report |
| Evidence | Minimal | Detailed |
| Perspectives | None | Both provided |
| Use case | Triage | Documentation |

## User Interaction

Use the **AskUserQuestion tool** when:
- No content is provided with the command
- Score falls in borderline range (35-55) requiring next-step guidance
- Multiple pieces of content need prioritized triage

### Example Invocations

**Missing content:**
```
User: /score
→ Use AskUserQuestion tool:
  Question: "What content would you like me to score?"
  Options:
  - "Provide a URL"
  - "Paste text directly"
  - "Score multiple items (batch triage)"
```

**Borderline score with next steps:**
```
Score: 42/100 [!] (Moderate)
→ Use AskUserQuestion tool:
  Question: "Score is 42 (Moderate) - in the borderline range. What next?"
  Options:
  - "Run full analysis for detailed breakdown" (Recommended)
  - "Verify key claims with fact-checking"
  - "Score is sufficient, no further action"
```

**Batch triage scenario:**
```
User: /score [multiple URLs or texts]
→ After scoring all items, use AskUserQuestion tool:
  Question: "Triage complete. Which items need deeper analysis?"
  Options:
  - "Analyze all High/Severe items (score > 50)"
  - "Analyze the highest-scoring item only"
  - "Show me the scores, I'll decide"
```
