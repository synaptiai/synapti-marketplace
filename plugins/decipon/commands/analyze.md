---
description: Perform full NCI manipulation analysis on content (text or URL) with 20-category scoring and dual perspectives
---

# Analyze Content for Manipulation

Perform full NCI (Narrative Credibility Index) manipulation analysis on content.

## Arguments

`$ARGUMENTS`: The content to analyze - can be a URL, text, or file path.

## Workflow

1. **Detect Input Type**
   - If starts with `http://` or `https://` → Use WebFetch to retrieve content
   - If starts with `/` or `./` → Use Read tool to get file contents
   - Otherwise → Treat as direct text content

2. **Load NCI Methodology**
   - Read the `nci-analysis` skill from this plugin's `skills/` directory
   - Follow the complete 20-category analysis workflow

3. **Score All 20 Categories**
   Each category scored 1-5 with evidence:

   **Emotional Manipulation** (5 categories)
   - Base emotional triggers, urgency, novelty, repetition, manufactured outrage

   **Suspicious Timing** (3 categories)
   - Timing correlation, beneficiary analysis, historical parallels

   **Uniform Messaging** (3 categories)
   - Message uniformity, bandwagon effects, rapid shifts

   **Tribal Division** (3 categories)
   - Us-vs-them framing, simplistic narratives, false dilemmas

   **Missing Information** (6 categories)
   - Context gaps, authority issues, dissent suppression, cherry-picking, fallacies, framing

4. **Calculate Scores**
   - Compute 5 composite factors (weighted averages)
   - Calculate overall 0-100 score

5. **Generate Dual Perspectives**
   - Manipulative interpretation with confidence
   - Legitimate interpretation with confidence

6. **Output Full Report**
   Markdown format with:
   - Overall score and severity indicator
   - Composite factor breakdown
   - Top manipulation indicators with evidence
   - Both perspectives
   - Full 20-category details

## Example Usage

```
/analyze https://example.com/news/article
```

```
/analyze BREAKING: Shocking new report reveals what they don't want you to know!
```

## Severity Scale

| Score | Indicator | Risk |
|-------|-----------|------|
| 0-25 | [·] | Low - Normal consumption |
| 26-50 | [!] | Moderate - Verify claims |
| 51-75 | [!!] | High - Cross-reference, strong skepticism |
| 76-100 | [!!!] | Severe - Likely manipulation |

## User Interaction

Use the **AskUserQuestion tool** when:
- Input is ambiguous (e.g., "analyze this" without content)
- Content type is unclear (satire, opinion, news reporting)
- User's goal is uncertain (triage vs. deep analysis vs. documentation)
- Analysis reveals borderline scores requiring interpretation guidance

### Example Invocations

**Ambiguous input:**
```
User: /analyze this article
→ Use AskUserQuestion tool:
  Question: "What content would you like me to analyze?"
  Options:
  - "Provide a URL to fetch"
  - "Paste text directly"
  - "Specify a file path"
```

**Unclear analysis depth:**
```
User: /analyze https://example.com/article
→ After initial score (45 - borderline), use AskUserQuestion tool:
  Question: "This content scores 45/100 (Moderate). How would you like to proceed?"
  Options:
  - "Full 20-category breakdown with evidence" (Recommended)
  - "Quick summary with top 3 findings"
  - "Verify key claims with deep research"
  - "Generate formal report for sharing"
```

**Content type ambiguity:**
```
User: /analyze [satirical article]
→ Use AskUserQuestion tool:
  Question: "This appears to be satirical content. How should I analyze it?"
  Options:
  - "Analyze as satire (note manipulation techniques used for effect)"
  - "Analyze as if presented as news (ignore satirical intent)"
  - "Skip analysis (satire not suited for NCI scoring)"
```
