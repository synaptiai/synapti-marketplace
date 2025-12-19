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
| 0-20 | [✓] | Low - Normal consumption |
| 21-40 | [!] | Moderate - Verify claims |
| 41-60 | [!!] | Elevated - Cross-reference |
| 61-80 | [!!!] | High - Strong skepticism |
| 81-100 | [!!!!] | Severe - Likely manipulation |
