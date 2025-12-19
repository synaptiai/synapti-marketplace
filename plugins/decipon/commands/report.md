---
description: Generate formal NCI analysis report in JSON or Markdown format for sharing and archiving
---

# Generate NCI Report

Generate formal NCI analysis report in JSON or Markdown format.

## Usage

```
/decipon:report <URL or text> [--format json|markdown] [--output filename]
```

## Arguments

- `$ARGUMENTS`: Content to analyze plus optional flags
  - Content: URL, file path, or text
  - `--format`: Output format (default: markdown)
  - `--output`: Save to file (optional)

## Purpose

Generate a formal, shareable NCI analysis report:
- Complete 20-category breakdown
- Dual perspectives with confidence
- Structured format for sharing/archiving
- Machine-readable (JSON) or human-readable (Markdown)

## Workflow

1. **Parse Arguments**
   - Extract content from flags
   - Determine output format
   - Identify output file if specified

2. **Perform Full Analysis**
   - Invoke NCI skill
   - Score all 20 categories with evidence
   - Calculate all metrics

3. **Generate Perspectives**
   - Manipulative interpretation
   - Legitimate interpretation
   - Confidence levels for both

4. **Format Report**
   - Apply requested format (JSON or Markdown)
   - Include all metadata

5. **Output/Save**
   - Display to user
   - Save to file if `--output` specified

## Markdown Report Format

```markdown
# NCI Analysis Report

**Generated**: [ISO timestamp]
**Protocol Version**: 1.0
**Content Source**: [URL or "Direct input"]

---

## Executive Summary

**Overall Score**: 72/100 [!!!]
**Confidence**: 82%
**Risk Level**: HIGH

**Key Finding**: This content exhibits strong manipulation patterns,
particularly in emotional manipulation and missing information dimensions.

---

## Composite Factor Scores

### Emotional Manipulation: 4.2/5
Confidence: 85%

| Category | Score | Evidence |
|----------|-------|----------|
| Base Emotional | 4 | [Evidence] |
| Urgent Action | 5 | [Evidence] |
| Novelty | 4 | [Evidence] |
| Repetition | 4 | [Evidence] |
| Manufactured Outrage | 4 | [Evidence] |

### Suspicious Timing: 4.7/5
[Continue for each composite...]

---

## Perspectives

### Manipulative Interpretation
**Confidence**: 80%

[Full manipulative interpretation...]

### Legitimate Interpretation
**Confidence**: 55%

[Full legitimate interpretation...]

---

## Detailed Category Analysis

[All 20 categories with full evidence...]

---

## Methodology

This analysis follows NCI Protocol v1.0:
- Pattern-based detection (not truth-based)
- 20 manipulation indicators across 5 dimensions
- Weighted scoring with confidence metrics
- Dual perspective generation

---

## Appendix: Raw Scores

[JSON-formatted raw data for programmatic use]
```

## JSON Report Format

```json
{
  "nci_report": {
    "version": "1.0",
    "generated_at": "2025-01-15T10:30:00Z",
    "content_metadata": {
      "source": "https://example.com/article",
      "type": "url",
      "word_count": 1250,
      "fetch_date": "2025-01-15T10:29:55Z"
    },
    "score": {
      "overall": 72,
      "confidence": 0.82,
      "severity": "HIGH",
      "severity_indicator": "[!!!]"
    },
    "composite_factors": {
      "emotional_manipulation": {
        "value": 4.2,
        "confidence": 0.85,
        "categories": {
          "emotional_manipulation_base": {
            "score": 4,
            "evidence": "Fear vocabulary: 'devastating', 'threat'",
            "confidence": "HIGH"
          }
        }
      }
    },
    "perspectives": {
      "manipulative": {
        "summary": "...",
        "confidence": 0.80,
        "key_techniques": ["...", "...", "..."],
        "likely_intent": "...",
        "beneficiaries": ["..."]
      },
      "legitimate": {
        "summary": "...",
        "confidence": 0.55,
        "supporting_factors": ["...", "...", "..."],
        "genuine_concerns": "...",
        "explanatory_context": "..."
      }
    },
    "methodology": {
      "protocol": "NCI Protocol",
      "version": "1.0",
      "approach": "Pattern-based manipulation detection",
      "categories_scored": 20,
      "composite_factors": 5
    }
  }
}
```

## Example Invocations

**Markdown report to console:**
```
/decipon:report https://example.com/article
```

**JSON report to console:**
```
/decipon:report https://example.com/article --format json
```

**Save markdown report to file:**
```
/decipon:report https://example.com/article --output nci-analysis.md
```

**Save JSON report to file:**
```
/decipon:report https://example.com/article --format json --output analysis.json
```

## Integration with Deep Research

When generating formal reports, consider:
- Use `/deep-research` first for claims verification
- Include source evaluation scores
- Note any cross-referenced information
- Document verification attempts

## Use Cases

| Scenario | Recommended Format |
|----------|-------------------|
| Sharing with colleagues | Markdown |
| Archiving for records | JSON |
| Integration with tools | JSON |
| Presentation/documentation | Markdown |
| Comparative analysis | JSON |

## Comparison with Other Commands

| Command | Output | Use Case |
|---------|--------|----------|
| `/decipon:score` | Quick score only | Triage |
| `/decipon:analyze` | Console report | Investigation |
| `/decipon:report` | Formal document | Sharing/archiving |
