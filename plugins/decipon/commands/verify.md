---
description: Verify factual claims in content using deep research methodology - fact-checks key assertions and updates NCI scores
---

# Verify Claims

Verify factual claims in content using deep research methodology. Can be run standalone or after NCI analysis.

> **Context Isolation**: This command uses the `claim-verifier` agent which auto-loads both the `conducting-deep-research` and `nci-manipulation-analysis` skills. Verification happens in a forked context, allowing multiple claims to be researched without polluting the main conversation.

## Usage

```
/decipon:verify <URL or text content>
/decipon:verify --claims "claim1" "claim2" "claim3"
```

## Arguments

- `$ARGUMENTS`: Content to analyze OR specific claims to verify
  - Content: URL, file path, or text
  - `--claims`: Verify specific claims directly

## Purpose

Fact-check key claims using deep research:
- Extract factual assertions from content
- Research each claim using multiple sources
- Score source reliability (1-100 confidence)
- Track contradictions and agreements
- Report verification status with evidence

## Workflow

1. **Extract Claims** (if content provided)
   - Identify factual assertions
   - Prioritize by impact (Critical/High/Medium/Low)
   - Focus on verifiable claims (not opinions)

2. **Research Each Claim**
   - Apply deep research methodology
   - Search for supporting/contradicting evidence
   - Evaluate source quality
   - Track agreements and contradictions

3. **Evaluate Sources**
   - Score confidence (1-100)
   - Note source type and potential bias
   - Check for corroboration

4. **Generate Report**
   - Verification status per claim
   - Source citations with confidence
   - Overall credibility assessment

## Verification Statuses

| Status | Meaning |
|--------|---------|
| VERIFIED | 2+ high-confidence sources support claim |
| PARTIALLY VERIFIED | Core claim true but with caveats |
| UNVERIFIED | Cannot find supporting evidence |
| CONTRADICTED | High-confidence sources refute claim |

## Output Format

```
═══════════════════════════════════════════════════
  CLAIM VERIFICATION REPORT
═══════════════════════════════════════════════════

SUMMARY
───────
Claims Analyzed: [N]
✓ Verified:      [N]
~ Partial:       [N]
? Unverified:    [N]
✗ Contradicted:  [N]

DETAILED FINDINGS
─────────────────

CLAIM 1: "[Statement]"
Status: [STATUS]
Confidence: [%]

Sources:
  [1] example.com (Confidence: 85) - Supports
  [2] reuters.com (Confidence: 90) - Supports

Finding: [What research revealed]

───────────────────────────────────────────────────

CLAIM 2: "[Statement]"
[Continue for each claim...]

═══════════════════════════════════════════════════

METHODOLOGY
Applied deep research verification protocol
Consulted [N] sources total
Source confidence scoring: 1-100 scale

RECOMMENDATIONS
[Any suggested follow-up verification]

═══════════════════════════════════════════════════
```

## Integration with NCI Analysis

### After `/decipon:analyze`

If NCI analysis shows elevated manipulation risk (score > 40), verification is recommended:

```
/decipon:analyze https://example.com/article
# Returns NCI score of 55 with key claims identified

/decipon:verify https://example.com/article
# Verifies claims and may adjust manipulation assessment
```

### Automatic Triggers

Verification is automatically suggested when:
- NCI Score > 40
- Authority Issues category > 3
- Suspicious Timing category > 3
- Cherry-Picking category > 3

### Score Adjustment

After verification, NCI scores may be adjusted:
- **Verified claims**: May reduce manipulation scores
- **Contradicted claims**: Increase manipulation scores
- Report shows original vs adjusted scores

## Example Invocations

**Verify content from URL:**
```
/decipon:verify https://example.com/news-article
```

**Verify specific claims:**
```
/decipon:verify --claims "The study showed 90% improvement" "Experts unanimously agree"
```

**After NCI analysis:**
```
/decipon:analyze <content>
# If score elevated:
/decipon:verify <content>
```

## Deep Research Integration

Uses the deep research skill for:
- Source evaluation and confidence scoring
- Contradiction handling protocol
- Search patterns for different source types
- Quality iteration until confidence threshold met

See `skills/deep-research/SKILL.md` for full methodology.

## Source Confidence Guidelines

| Source Type | Confidence Range |
|-------------|------------------|
| Peer-reviewed research | 85-100 |
| Official documentation | 85-95 |
| Government/institutional | 75-90 |
| Major news (Reuters, AP) | 70-85 |
| Established newspapers | 60-80 |
| Industry publications | 50-75 |
| Blogs/forums | 20-50 |
| Anonymous/undated | 5-20 |

## Comparison with Other Commands

| Command | Focus | Depth |
|---------|-------|-------|
| `/decipon:score` | Quick manipulation score | Light |
| `/decipon:analyze` | Full pattern analysis | Thorough |
| `/decipon:verify` | Claim fact-checking | Deep research |
| `/decipon:report` | Formal documentation | Complete |

## Best Practice Workflow

1. **Quick triage**: `/decipon:score` - Get initial manipulation score
2. **Full analysis**: `/decipon:analyze` - If score > 20
3. **Fact-check**: `/decipon:verify` - If score > 40 or claims seem dubious
4. **Document**: `/decipon:report` - For formal records

## User Interaction

Use the **AskUserQuestion tool** when:
- No content or claims are provided
- Multiple claims exist and prioritization is needed
- Verification reveals contradictions requiring user judgment
- Resource constraints limit how many claims can be verified

### Example Invocations

**Missing content:**
```
User: /verify
→ Use AskUserQuestion tool:
  Question: "What would you like me to verify?"
  Options:
  - "Provide content (URL or text) to extract claims from"
  - "Specify claims directly with --claims flag"
  - "Verify claims from previous NCI analysis"
```

**Claim prioritization:**
```
User: /verify [content with 8 claims]
→ Use AskUserQuestion tool:
  Question: "Found 8 verifiable claims. How should I prioritize?"
  Options:
  - "Verify top 3-5 most impactful claims" (Recommended)
  - "Verify all claims (takes longer)"
  - "Let me select specific claims to verify"
```

**Contradictory sources:**
```
Verification found conflicting sources for: "90% of experts agree"
→ Use AskUserQuestion tool:
  Question: "Sources disagree on this claim (73% vs 90%). How to proceed?"
  Options:
  - "Mark as PARTIALLY VERIFIED with both figures noted"
  - "Search for additional tiebreaker sources"
  - "Present both perspectives without verdict"
```

**Unverifiable claims:**
```
After research, 3 claims remain UNVERIFIED
→ Use AskUserQuestion tool:
  Question: "3 claims could not be verified (no supporting sources). What next?"
  Options:
  - "Flag as UNVERIFIED and continue with report"
  - "Expand search with different queries"
  - "Note limitations and finalize"
```
