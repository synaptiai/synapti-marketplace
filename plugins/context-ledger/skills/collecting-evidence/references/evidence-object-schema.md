# Evidence Object Schema

The canonical YAML schema for Evidence Objects in Context Ledger.

## Full Schema

```yaml
# Required fields
id: EV-<pillar>-<topic>-<descriptor>[-n]  # Semantic ID (see id-generation-rules.md)
pillar: market | users | tech | competitors | design | legal | ops | economics
claim: string  # The falsifiable claim (1-2 sentences max)
confidence: 0.0-1.0  # Subjective confidence in claim accuracy

# Source information (required)
source:
  type: url | pdf | interview | internal-doc | experiment | dataset
  ref: string  # URL, file path, or identifier
  retrieved_at: YYYY-MM-DD  # When source was accessed

# Assumptions (required, at least 1)
assumptions:
  - string  # Assumption that must hold for claim to be valid

# Optional fields
quote: string  # Direct quote or excerpt supporting claim
notes: string  # Additional context, limitations, follow-up needed
tags:
  - string  # Searchable tags for cross-referencing

# Metadata (auto-generated)
created_at: YYYY-MM-DD  # When evidence object was created
updated_at: YYYY-MM-DD  # Last modification date
superseded_by: EV-*  # If deprecated, link to replacement
```

## Field Definitions

### id (required)
Unique semantic identifier following the pattern:
`EV-<pillar>-<topic>-<descriptor>[-n]`

- **pillar**: One of the 8 research pillars
- **topic**: 1-2 word topic (e.g., `pricing`, `onboarding`, `latency`)
- **descriptor**: 1-3 words describing specific claim (e.g., `smb-wtp`, `dropoff-rate`)
- **-n**: Optional disambiguator if ID collision (-2, -3, etc.)

See [id-generation-rules.md](id-generation-rules.md) for detailed rules.

### pillar (required)
Which research pillar this evidence belongs to:
- `market` - Market research
- `users` - User research
- `tech` - Technical research
- `competitors` - Competitive analysis
- `design` - Design research
- `legal` - Legal/compliance
- `ops` - Operations
- `economics` - Business/financial

### claim (required)
The core assertion this evidence supports.

**Requirements:**
- Must be falsifiable (can be proven wrong)
- Maximum 1-2 sentences
- Specific, not vague
- Avoid weasel words ("some", "many", "often")

**Good claims:**
```yaml
claim: "SMB segment willingness-to-pay peaks at $29/mo for productivity tools."
claim: "78% of users abandon onboarding at the team invitation step."
claim: "PostgreSQL full-text search handles up to 10M documents with <100ms latency."
```

**Bad claims:**
```yaml
claim: "Users like simple interfaces."  # Not falsifiable
claim: "The market is large and growing."  # Too vague
claim: "Many competitors exist in this space."  # Weasel words
```

### confidence (required)
Subjective probability that the claim is accurate. Scale: 0.0 to 1.0.

| Range | Interpretation | When to Use |
|-------|----------------|-------------|
| 0.9-1.0 | Near certain | Peer-reviewed, multiple corroborating sources |
| 0.7-0.9 | High confidence | Authoritative source, methodology clear |
| 0.5-0.7 | Moderate | Single source, reasonable methodology |
| 0.3-0.5 | Low confidence | Weak source, significant assumptions |
| 0.0-0.3 | Very uncertain | Speculation, unreliable source |

**Calibration guidance:**
- Don't inflate confidence to make evidence seem stronger
- Consider: "If I bet money on this claim, at what odds?"
- When in doubt, round down

### source (required)
Information about where this evidence came from.

**type** - One of:
- `url` - Web page, article, documentation
- `pdf` - PDF document (academic paper, whitepaper, report)
- `interview` - User interview, expert conversation
- `internal-doc` - Internal company document, prior research
- `experiment` - A/B test, prototype test, experiment
- `dataset` - Analytics data, survey results, datasets

**ref** - How to find the source:
- For `url`: Full URL
- For `pdf`: File path or URL
- For `interview`: Identifier (e.g., "User Interview #12")
- For `internal-doc`: Document name and location
- For `experiment`: Experiment name/ID
- For `dataset`: Dataset name and query/filter

**retrieved_at** - Date source was accessed (YYYY-MM-DD format)

### assumptions (required)
List of assumptions that must hold for the claim to be valid.

**Every evidence object must have at least 1 assumption.**

Common assumption types:
- Sample representativeness
- Methodology validity
- Time relevance (data not stale)
- Geographic applicability
- Segment applicability

```yaml
assumptions:
  - "Survey sample representative of target SMB market"
  - "WTP measured in 2024 still applicable in 2026"
  - "US pricing data applies to target geography"
```

### quote (optional)
Direct excerpt from source supporting the claim.

- Keep brief (1-3 sentences)
- Use for high-stakes claims
- Helps with auditing

```yaml
quote: "Our survey of 500 SMB decision-makers found median willingness-to-pay of $29/month for productivity SaaS, with significant variance by company size."
```

### notes (optional)
Additional context, limitations, or follow-up needed.

- Why this evidence matters
- How it might be wrong
- What to investigate next
- Relationship to other evidence

```yaml
notes: "Sample skewed toward US companies. May need regional validation for EU launch. Conflicts with EV-market-pricing-enterprise-wtp which shows higher WTP for larger companies."
```

### tags (optional)
Searchable labels for cross-referencing.

- Use lowercase
- Keep consistent across evidence objects
- Think about how you'll search later

```yaml
tags:
  - pricing
  - smb
  - willingness-to-pay
  - quantitative
```

## Examples

### Market Evidence
```yaml
id: EV-market-tam-b2b-saas
pillar: market
source:
  type: url
  ref: "https://www.gartner.com/en/research/methodologies/market-guide"
  retrieved_at: 2026-01-15
claim: "Global B2B SaaS market will reach $307B by 2028, growing at 12.5% CAGR."
quote: "The B2B SaaS market is projected to grow from $195B in 2024..."
confidence: 0.85
assumptions:
  - "Gartner methodology remains accurate"
  - "No major market disruption events"
  - "Growth rate continues historical trend"
notes: "High-level number. Need segment-specific sizing for our niche."
tags:
  - market-size
  - saas
  - growth
```

### User Evidence
```yaml
id: EV-users-onboarding-dropoff
pillar: users
source:
  type: experiment
  ref: "Onboarding Funnel Analysis Q4-2025"
  retrieved_at: 2026-01-10
claim: "78% of users who start onboarding abandon at the team invitation step."
confidence: 0.92
assumptions:
  - "Analytics tracking is accurate"
  - "Sample period representative of normal behavior"
notes: "Strong signal. Team invitation UX is critical path for retention."
tags:
  - onboarding
  - dropoff
  - funnel
  - quantitative
```

### Tech Evidence
```yaml
id: EV-tech-llm-cost-per-request
pillar: tech
source:
  type: url
  ref: "https://openai.com/pricing"
  retrieved_at: 2026-01-20
claim: "GPT-4 API costs $0.03 per 1K input tokens and $0.06 per 1K output tokens."
confidence: 0.95
assumptions:
  - "Pricing stable through development period"
  - "No volume discounts significantly change unit economics"
notes: "Pricing subject to change. Build flexibility into cost model."
tags:
  - llm
  - cost
  - api
  - infrastructure
```

## Validation Checklist

Before saving an Evidence Object:

- [ ] ID follows semantic scheme
- [ ] Pillar is valid
- [ ] Claim is falsifiable and specific
- [ ] Confidence is honest (not inflated)
- [ ] Source type and ref are accurate
- [ ] At least 1 assumption listed
- [ ] File saved to correct pillar directory
