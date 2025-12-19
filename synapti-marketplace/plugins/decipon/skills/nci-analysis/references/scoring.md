# NCI Scoring Methodology

Complete scoring calculations for the NCI Protocol.

## Contents
- [Scoring Architecture](#scoring-architecture)
- [Category Scoring (1-5)](#category-scoring-1-5)
- [Composite Factor Calculation](#composite-factor-calculation)
- [Overall Score Calculation](#overall-score-calculation)
- [Confidence Calculation](#confidence-calculation)
- [Output Formats](#output-formats)

---

## Scoring Architecture

Three-level hierarchical scoring:

```
Level 1: 20 Individual Categories (1-5 scale)
    ↓ weighted averaging
Level 2: 5 Composite Factors (1-5 scale)
    ↓ weighted averaging + scaling
Level 3: Overall Score (0-100 scale)
```

---

## Category Scoring (1-5)

### Scale Definition

| Score | Label | Description |
|-------|-------|-------------|
| 1 | Not present | No signs of this manipulation technique |
| 2 | Minimally present | Slight indicators, possibly coincidental |
| 3 | Moderately present | Clear but not dominant |
| 4 | Strongly present | Prominent indicators |
| 5 | Overwhelmingly present | Clear, strong evidence |

### Evidence Requirements

Each category score MUST include:

```
CATEGORY: [Name]
Score: [1-5]
Evidence: [Specific quotes/patterns - minimum 1 per score point above 1]
Confidence: [LOW/MED/HIGH based on evidence clarity]
```

**Minimum evidence per score:**
- Score 1: Can be stated without specific evidence
- Score 2: 1 specific indicator
- Score 3: 2-3 specific indicators
- Score 4: 3-4 specific indicators
- Score 5: 4+ specific indicators with clear pattern

---

## Composite Factor Calculation

### Emotional Manipulation (25% of overall)

```
EM = (0.35 × Cat1) + (0.20 × Cat2) + (0.15 × Cat3) + (0.15 × Cat4) + (0.15 × Cat5)
```

| Category | Weight |
|----------|--------|
| 1. Emotional Manipulation (Base) | 0.35 |
| 2. Call for Urgent Action | 0.20 |
| 3. Overuse of Novelty | 0.15 |
| 4. Emotional Repetition | 0.15 |
| 5. Manufactured Outrage | 0.15 |

**Example:**
```
Cat1=4, Cat2=5, Cat3=4, Cat4=4, Cat5=4
EM = (0.35×4) + (0.20×5) + (0.15×4) + (0.15×4) + (0.15×4)
EM = 1.40 + 1.00 + 0.60 + 0.60 + 0.60 = 4.20
```

### Suspicious Timing (20% of overall)

```
ST = (0.50 × Cat6) + (0.35 × Cat7) + (0.15 × Cat8)
```

| Category | Weight |
|----------|--------|
| 6. Timing | 0.50 |
| 7. Financial/Political Gain | 0.35 |
| 8. Historical Parallels | 0.15 |

### Uniform Messaging (20% of overall)

```
UM = (0.50 × Cat9) + (0.25 × Cat10) + (0.25 × Cat11)
```

| Category | Weight |
|----------|--------|
| 9. Uniform Messaging (Base) | 0.50 |
| 10. Bandwagon Effect | 0.25 |
| 11. Rapid Behavior Shifts | 0.25 |

### Tribal Division (15% of overall)

```
TD = (0.40 × Cat12) + (0.35 × Cat13) + (0.25 × Cat14)
```

| Category | Weight |
|----------|--------|
| 12. Tribal Division (Base) | 0.40 |
| 13. Simplistic Narratives | 0.35 |
| 14. False Dilemmas | 0.25 |

### Missing Information (20% of overall)

```
MI = (0.25 × Cat15) + (0.15 × Cat16) + (0.15 × Cat17) + (0.20 × Cat18) + (0.15 × Cat19) + (0.10 × Cat20)
```

| Category | Weight |
|----------|--------|
| 15. Missing Information (Base) | 0.25 |
| 16. Authority Overload | 0.15 |
| 17. Suppression of Dissent | 0.15 |
| 18. Cherry-Picked Data | 0.20 |
| 19. Logical Fallacies | 0.15 |
| 20. Framing Techniques | 0.10 |

---

## Overall Score Calculation

### Step 1: Weight Composite Factors

```
Weighted_Sum = (0.25 × EM) + (0.20 × ST) + (0.20 × UM) + (0.15 × TD) + (0.20 × MI)
```

| Composite Factor | Weight |
|------------------|--------|
| Emotional Manipulation | 0.25 |
| Suspicious Timing | 0.20 |
| Uniform Messaging | 0.20 |
| Tribal Division | 0.15 |
| Missing Information | 0.20 |

### Step 2: Scale to 0-100

```
Overall_Score = (Weighted_Sum - 1) × 25
```

**Scale mapping:**
- Input 1.0 → Output 0
- Input 3.0 → Output 50
- Input 5.0 → Output 100

### Complete Example

```
Category Scores:
Cat1=4, Cat2=5, Cat3=4, Cat4=4, Cat5=4  → EM = 4.20
Cat6=5, Cat7=5, Cat8=3                  → ST = 4.70
Cat9=5, Cat10=4, Cat11=4                → UM = 4.50
Cat12=3, Cat13=4, Cat14=3               → TD = 3.35
Cat15=4, Cat16=4, Cat17=3, Cat18=4, Cat19=4, Cat20=4 → MI = 3.85

Weighted Sum:
= (0.25 × 4.20) + (0.20 × 4.70) + (0.20 × 4.50) + (0.15 × 3.35) + (0.20 × 3.85)
= 1.05 + 0.94 + 0.90 + 0.50 + 0.77
= 4.16

Overall Score:
= (4.16 - 1) × 25
= 79 [!!!]
```

---

## Confidence Calculation

### Factor Confidence

Each composite factor gets a confidence score based on:

```
Factor_Confidence = Evidence_Quality × Category_Agreement × Data_Completeness
```

Where:
- **Evidence_Quality**: Average clarity of evidence (0.5-1.0)
- **Category_Agreement**: How consistent scores are within factor (0.7-1.0)
- **Data_Completeness**: Whether all categories could be assessed (0.5-1.0)

### Overall Confidence

```
Overall_Confidence = min(
  Weighted_Average(Factor_Confidences),
  0.95  # CRITICAL: Never claim 100% certainty (NCI Protocol requirement)
)
```

**Maximum Confidence Cap: 0.95 (95%)**

The NCI Protocol explicitly requires that confidence never exceed 95%. This reflects:
- Inherent uncertainty in manipulation detection
- Possibility of sophisticated manipulation mimicking legitimacy
- Epistemic humility about intent assessment
- Recognition that even experts can be fooled

### Confidence Thresholds

| Confidence | Interpretation | Report Language |
|------------|----------------|-----------------|
| 0.85-0.95 | High | "Strong indicators suggest..." |
| 0.70-0.84 | Moderate | "Evidence indicates..." |
| 0.50-0.69 | Low | "Some signals suggest..." |
| Below 0.50 | Very Low | "Limited evidence, uncertain assessment..." |

---

## Output Formats

### JSON Format

```json
{
  "version": "1.0",
  "content_hash": "sha256:...",
  "score": {
    "overall": 79,
    "confidence": 0.82,
    "composite_factors": {
      "emotional_manipulation": {
        "composite_value": 4.20,
        "confidence": 0.85,
        "categories": {
          "emotional_manipulation_base": {
            "value": 4,
            "weight": 0.35,
            "evidence": "High density of fear triggers: 'devastating', 'threat', 'crisis'"
          },
          "call_for_urgent_action": {
            "value": 5,
            "weight": 0.20,
            "evidence": "'Act NOW', 'time is running out', artificial deadline"
          },
          "overuse_of_novelty": {
            "value": 4,
            "weight": 0.15,
            "evidence": "'Unprecedented', 'never before seen', 'shocking'"
          },
          "emotional_repetition": {
            "value": 4,
            "weight": 0.15,
            "evidence": "'Crisis' repeated 8 times across content"
          },
          "manufactured_outrage": {
            "value": 4,
            "weight": 0.15,
            "evidence": "Outrage disproportionate to stated facts"
          }
        }
      },
      "suspicious_timing": {
        "composite_value": 4.70,
        "confidence": 0.80,
        "categories": { ... }
      },
      "uniform_messaging": {
        "composite_value": 4.50,
        "confidence": 0.88,
        "categories": { ... }
      },
      "tribal_division": {
        "composite_value": 3.35,
        "confidence": 0.75,
        "categories": { ... }
      },
      "missing_information": {
        "composite_value": 3.85,
        "confidence": 0.82,
        "categories": { ... }
      }
    }
  },
  "perspectives": {
    "manipulative": {
      "summary": "Content appears designed to...",
      "confidence": 0.80
    },
    "legitimate": {
      "summary": "Content may reflect genuine...",
      "confidence": 0.55
    }
  },
  "metadata": {
    "analyzed_at": "2025-01-15T10:30:00Z",
    "content_type": "text",
    "word_count": 1024
  }
}
```

### Markdown Report Format

```markdown
# NCI Analysis Report

## Summary
**Overall Score: 79/100** [!!!]
**Confidence: 82%**

## Visual Score

┌──────────────────────────────────────┐
│    Information Nutrition Label       │
├──────────────────────────────────────┤
│ Manipulation Score: 79 [!!!]         │
│ Confidence: 82%                      │
├──────────────────────────────────────┤
│ COMPOSITE FACTORS                    │
│ Emotional Manipulation  ████▒ 4.2    │
│ Suspicious Timing       █████ 4.7    │
│ Uniform Messaging       █████ 4.5    │
│ Tribal Division         ███▒░ 3.4    │
│ Missing Information     ████░ 3.9    │
├──────────────────────────────────────┤
│        [See Perspectives]            │
└──────────────────────────────────────┘

## Composite Factor Details

### Emotional Manipulation: 4.2/5 (Confidence: 85%)
| Category | Score | Evidence |
|----------|-------|----------|
| Base Emotional | 4 | Fear vocabulary: "devastating", "threat" |
| Urgent Action | 5 | "Act NOW", artificial deadline |
| Overuse of Novelty | 4 | "Unprecedented", "never before" |
| Emotional Repetition | 4 | "Crisis" repeated 8x |
| Manufactured Outrage | 4 | Disproportionate to facts |

[Continue for each composite factor...]

## Perspectives

### If Manipulative (Confidence: 80%)
[Analysis of manipulation intent and techniques]

### If Legitimate (Confidence: 55%)
[Analysis of potential legitimate concerns]

## Methodology
NCI Protocol v1.0 - Pattern-based manipulation detection
```

### Severity Scale Reference

| Score Range | Indicator | Risk Level | Recommended Action |
|-------------|-----------|------------|-------------------|
| 0-25 | `[·]` | Low | Normal consumption |
| 26-50 | `[!]` | Moderate | Verify key claims |
| 51-75 | `[!!]` | High | Cross-reference sources, strong skepticism |
| 76-100 | `[!!!]` | Severe | Likely manipulative content |

---

## Calculation Worksheet

Use this template for manual calculation:

```
NCI SCORING WORKSHEET
=====================

CATEGORY SCORES:
[ ] 1. Emotional Manipulation (Base): ___
[ ] 2. Call for Urgent Action: ___
[ ] 3. Overuse of Novelty: ___
[ ] 4. Emotional Repetition: ___
[ ] 5. Manufactured Outrage: ___
[ ] 6. Timing: ___
[ ] 7. Financial/Political Gain: ___
[ ] 8. Historical Parallels: ___
[ ] 9. Uniform Messaging (Base): ___
[ ] 10. Bandwagon Effect: ___
[ ] 11. Rapid Behavior Shifts: ___
[ ] 12. Tribal Division (Base): ___
[ ] 13. Simplistic Narratives: ___
[ ] 14. False Dilemmas: ___
[ ] 15. Missing Information (Base): ___
[ ] 16. Authority Overload: ___
[ ] 17. Suppression of Dissent: ___
[ ] 18. Cherry-Picked Data: ___
[ ] 19. Logical Fallacies: ___
[ ] 20. Framing Techniques: ___

COMPOSITE FACTORS:
EM = (0.35×___) + (0.20×___) + (0.15×___) + (0.15×___) + (0.15×___) = ___
ST = (0.50×___) + (0.35×___) + (0.15×___) = ___
UM = (0.50×___) + (0.25×___) + (0.25×___) = ___
TD = (0.40×___) + (0.35×___) + (0.25×___) = ___
MI = (0.25×___) + (0.15×___) + (0.15×___) + (0.20×___) + (0.15×___) + (0.10×___) = ___

OVERALL:
Weighted = (0.25×___) + (0.20×___) + (0.20×___) + (0.15×___) + (0.20×___) = ___
Score = (Weighted - 1) × 25 = ___
```
