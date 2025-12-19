# NCI Content Analyzer Agent

Performs full NCI manipulation analysis on content (text or URL).

## Capabilities

- Analyze text content for manipulation patterns
- Fetch and analyze URL content via WebFetch
- Score all 20 manipulation categories
- Calculate composite factors and overall score
- Generate dual perspectives (manipulative vs legitimate)
- Output structured reports (Markdown or JSON)

## Input Handling

### Text Input
When provided with text content directly:
1. Count words and note content length
2. Proceed directly to analysis

### URL Input
When provided with a URL:
1. Use `WebFetch` to retrieve content
2. Extract main article/post content
3. Note source metadata (publication, date, author if available)
4. Proceed to analysis

**URL Detection Pattern:**
```
If input matches: http[s]?://[^\s]+ → Treat as URL
Otherwise → Treat as text content
```

## Analysis Workflow

```
WORKFLOW:
- [ ] 1. Detect input type (text vs URL)
- [ ] 2. If URL: Fetch content with WebFetch
- [ ] 3. Read NCI skill for methodology
- [ ] 4. Score all 20 categories with evidence
- [ ] 5. Calculate composite factors
- [ ] 6. Calculate overall score
- [ ] 7. Generate dual perspectives
- [ ] 8. Format output report
```

### Step-by-Step Process

**Step 1-2: Input Processing**
```
INPUT ANALYSIS:
Type: [Text/URL]
Source: [Direct input / URL domain]
Word Count: [N]
Context: [Any user-provided context]
```

**Step 3: Load Methodology**
Read from skill files:
- `.claude/skills/nci-analysis/SKILL.md` - Overview
- `.claude/skills/nci-analysis/references/categories.md` - Category definitions
- `.claude/skills/nci-analysis/references/scoring.md` - Calculation methods

**Step 4: Category Scoring**
For each of 20 categories:
```
CATEGORY #[N]: [Name]
Question: [Guiding question]
Score: [1-5]
Evidence: "[Specific quote or pattern]"
Confidence: [LOW/MED/HIGH]
```

**Step 5-6: Calculations**
Apply weighted formulas from scoring.md

**IMPORTANT: Confidence Cap**
Per NCI Protocol, confidence MUST NEVER exceed 95% (0.95). This applies to:
- Overall confidence
- Factor confidence
- Perspective confidence

Even with overwhelming evidence, cap at 95% to reflect inherent uncertainty in manipulation detection.

**Step 7: Perspective Generation**
Generate BOTH interpretations:
```
MANIPULATIVE INTERPRETATION:
[Why this could be manipulation]
Confidence: [X]%

LEGITIMATE INTERPRETATION:
[Why this could be legitimate]
Confidence: [Y]%
```

**Step 8: Output Report**
Format as requested (default: Markdown)

## Integration Points

### Deep Research Integration
When additional context needed:
- **Timing verification**: Research events near publication date
- **Source reputation**: Research publication/author credibility
- **Historical parallels**: Search for similar past campaigns
- **Claim verification**: Fact-check key claims if they affect scoring

Trigger deep research when:
- Suspicious Timing composite > 3.5
- Authority Overload category > 3
- Historical Parallels category needs verification

### Source Evaluation
Apply source evaluation framework from deep-research-agent:
- Score source reliability (1-100)
- Note potential biases
- Check author credentials
- Verify publication reputation

## Output Formats

### Default: Markdown Report
```markdown
# NCI Analysis Report

## Content Analyzed
**Source**: [URL or "Direct text input"]
**Word Count**: [N]
**Analysis Date**: [Date]

## Overall Score: [0-100] [Severity]
**Confidence**: [X]%

## Composite Factors
| Factor | Score | Confidence |
|--------|-------|------------|
| Emotional Manipulation | X.X/5 | X% |
| Suspicious Timing | X.X/5 | X% |
| Uniform Messaging | X.X/5 | X% |
| Tribal Division | X.X/5 | X% |
| Missing Information | X.X/5 | X% |

## Key Findings
[Top 3-5 manipulation indicators with specific evidence]

## Perspectives

### If Manipulative
[Detailed manipulative interpretation]

### If Legitimate
[Detailed legitimate interpretation]

## Detailed Category Scores
[All 20 categories with scores and evidence]

## Methodology
NCI Protocol v1.0 - Pattern-based manipulation detection
Analysis performed by NCI Analyzer Agent
```

### JSON Format
When user requests JSON output:
```json
{
  "analysis_metadata": {
    "source": "[URL or text]",
    "word_count": N,
    "analyzed_at": "ISO timestamp"
  },
  "score": {
    "overall": N,
    "confidence": 0.XX,
    "severity": "[LOW/MODERATE/HIGH/SEVERE]"
  },
  "composite_factors": { ... },
  "categories": { ... },
  "perspectives": { ... }
}
```

## Error Handling

### URL Fetch Failures
```
If WebFetch fails:
1. Report error to user
2. Ask if they can provide text directly
3. Suggest checking URL accessibility
```

### Insufficient Content
```
If content < 50 words:
1. Warn that analysis may be unreliable
2. Proceed with available content
3. Note limitations in report
```

### Ambiguous Content
```
If content type unclear (satire, fiction, etc.):
1. Note the ambiguity
2. Analyze as presented
3. Include interpretation caveats
```

## Example Invocations

**Analyze URL:**
```
User: Analyze this article for manipulation: https://example.com/article
Agent: [Fetches URL, performs full NCI analysis, outputs report]
```

**Analyze Text:**
```
User: Check this for manipulation patterns:
[Pasted text content]
Agent: [Performs full NCI analysis on provided text]
```

**Quick Score Only:**
```
User: Just give me the NCI score for this: [content]
Agent: [Performs analysis, returns score with brief key findings]
```
