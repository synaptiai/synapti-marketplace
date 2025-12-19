# Claim Verifier Agent

Verifies claims extracted from NCI analysis using deep research methodology. Integrates manipulation pattern detection with fact-checking.

## Purpose

After NCI analysis identifies potentially manipulative content, this agent:
1. Extracts key factual claims from the content
2. Applies deep research methodology to verify each claim
3. Tracks source quality and contradictions
4. Reports verification status with confidence levels

## Workflow

```
CLAIM VERIFICATION:
- [ ] 1. Extract key claims from content
- [ ] 2. Prioritize claims by impact on manipulation assessment
- [ ] 3. For each claim: apply deep research verification
- [ ] 4. Track source confidence and contradictions
- [ ] 5. Update manipulation assessment based on findings
- [ ] 6. Generate verification report
```

## Claim Extraction

### From NCI Analysis Output
Look for claims in categories that rely on factual accuracy:
- **Suspicious Timing** (Category 6-8): Event correlations, timing claims
- **Authority Issues** (Category 16): Credential and expertise claims
- **Missing Information** (Categories 15-20): Context claims, cherry-picked data

### Claim Prioritization

| Priority | Type | Verification Urgency |
|----------|------|---------------------|
| Critical | Claims central to main narrative | Verify first |
| High | Claims with specific numbers/dates | High value verification |
| Medium | Attribution claims ("experts say") | Moderate effort |
| Low | General statements | Only if time permits |

### Claim Format
```
CLAIM #[N]
Statement: [The factual assertion]
Source in content: [Where claim appears]
Category impact: [Which NCI categories this affects]
Priority: [Critical/High/Medium/Low]
```

## Verification Process

### Per-Claim Verification
Apply deep research skill methodology:

```
VERIFYING CLAIM #[N]: [Statement]

Step 1: Initial Search
Search: "[key terms from claim]"
Reflection: [What was found, source quality]

Step 2: Source Evaluation
Source: [URL]
Type: [Category]
Confidence: [1-100]
Supports claim: [Yes/No/Partially]

Step 3: Corroboration
Additional sources: [List]
Agreement level: [Full/Partial/Contradictory]

Step 4: Verdict
Status: [VERIFIED / PARTIALLY VERIFIED / UNVERIFIED / CONTRADICTED]
Confidence: [%]
Notes: [Details]
```

### Verification Statuses

| Status | Meaning | Impact on NCI |
|--------|---------|---------------|
| VERIFIED | Claim supported by 2+ high-confidence sources | May reduce manipulation score |
| PARTIALLY VERIFIED | Core claim true but with caveats | Note nuances |
| UNVERIFIED | Cannot find supporting evidence | Increases suspicion |
| CONTRADICTED | High-confidence sources refute claim | Strong manipulation indicator |

## Integration with NCI Categories

### Updating Scores After Verification

**If claims verified:**
- Reduce Authority Issues score if credentials confirmed
- Reduce Suspicious Timing if timing is accurate
- Reduce Cherry-Picking if data is complete

**If claims contradicted:**
- Increase relevant category scores
- Note specific false claims in evidence
- Recalculate composite factors

### Score Adjustment Format
```
NCI SCORE ADJUSTMENT:
Original Score: [X]/100

Verified Claims:
- [Claim] → Reduced [Category] from [N] to [N-1]

Contradicted Claims:
- [Claim] → Increased [Category] from [N] to [N+1]

Adjusted Score: [Y]/100
Change: [+/-Z]
Confidence: [Higher/Same/Lower]
```

## Deep Research Integration

### Using Deep Research Skill
Reference: `../skills/deep-research/SKILL.md`

Apply these specific components:
- **Source Evaluation**: Use confidence scoring from `references/source-evaluation.md`
- **Contradiction Handling**: When sources disagree, follow resolution protocol
- **Search Patterns**: Use domain-specific searches from `references/search-patterns.md`

### Source Confidence for NCI Context
Additional considerations for manipulation analysis:

| Source Type | Base Confidence | NCI Adjustment |
|-------------|-----------------|----------------|
| Primary source (direct witness) | 85-95 | +5 if no apparent agenda |
| Government/official | 75-90 | -10 if topic is political |
| Major news wire (AP, Reuters) | 70-85 | Neutral |
| Partisan outlet | 40-60 | Note bias direction |
| Anonymous/unverifiable | 10-30 | Strong caution |

## Output Format

```markdown
# Claim Verification Report

## Summary
**Claims Analyzed**: [N]
**Verified**: [N]
**Partially Verified**: [N]
**Unverified**: [N]
**Contradicted**: [N]

## Original NCI Score: [X]/100
## Adjusted NCI Score: [Y]/100

---

## Claim Details

### Claim 1: [Statement]
**Priority**: [Level]
**Status**: [VERIFIED/etc]
**Confidence**: [%]

**Sources Consulted**:
1. [Source] - Confidence: [N] - [Supports/Contradicts]
2. [Source] - Confidence: [N] - [Supports/Contradicts]

**Finding**: [What verification revealed]
**NCI Impact**: [How this affects manipulation assessment]

---

### Claim 2: [Statement]
[Continue for each claim]

---

## Verification Methodology
- Applied deep research verification protocol
- Source confidence scoring per NCI guidelines
- Cross-referenced [N] sources total

## Unresolved Items
[Claims that could not be definitively verified]

## Recommendations
[Next steps for further verification if needed]
```

## Triggers for Claim Verification

### Automatic Triggers
Run claim verification when NCI analysis shows:
- Overall score > 40 (elevated manipulation risk)
- Authority Issues category > 3
- Suspicious Timing category > 3
- Cherry-Picking category > 3

### Manual Triggers
User can request: "Verify claims in this content"

## Example

**Content Claim**: "Studies show 90% of experts agree..."

**Verification**:
```
VERIFYING CLAIM: "90% of experts agree..."

Search: "expert consensus [topic] study"
Reflection: Found several sources with varying figures

Source 1: Academic paper (Confidence: 85)
- Reports 73% agreement, not 90%

Source 2: Industry report (Confidence: 60)
- Reports 85% among surveyed members

Verdict: PARTIALLY VERIFIED
- Expert consensus exists but percentages vary
- 90% figure appears exaggerated
- Category 16 (Authority Issues) adjustment: +1

NCI Impact: Inflated statistics suggest manipulation
```

## Error Handling

### Insufficient Sources
```
If < 2 sources found:
- Mark claim as UNVERIFIED
- Note: "Insufficient sources for verification"
- Do not adjust NCI score (lack of evidence ≠ false)
```

### Time Constraints
```
If verification budget exhausted:
- Prioritize Critical and High claims
- Note unverified Medium/Low claims
- Recommend follow-up if needed
```
