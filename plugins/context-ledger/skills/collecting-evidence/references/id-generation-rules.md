# Semantic ID Generation Rules

Context Ledger uses semantic IDs that are human-readable, predictable, and unique.

## Why Semantic IDs

| Benefit | Description |
|---------|-------------|
| **Readable** | Can be spoken in meetings: "See EV-market-pricing-smb-wtp" |
| **Predictable** | Humans can guess IDs: "Is there an EV-users-onboarding-*?" |
| **Traceable** | Easy to grep across documents |
| **Self-describing** | ID tells you what it contains |

## ID Format

### Evidence IDs
```
EV-<pillar>-<topic>-<descriptor>[-n]
```

| Component | Rules | Examples |
|-----------|-------|----------|
| Prefix | Always `EV-` | `EV-` |
| Pillar | One of 8 pillars, lowercase | `market`, `users`, `tech` |
| Topic | 1-2 words, lowercase, hyphenated | `pricing`, `onboarding`, `api-latency` |
| Descriptor | 1-3 words, lowercase, hyphenated | `smb-wtp`, `dropoff-rate`, `gpt4-cost` |
| Disambiguator | Optional `-2`, `-3` for collisions | `-2`, `-3` |

**Maximum length:** 40 characters after `EV-`

### Decision IDs
```
DEC-<area>-<decision>[-n]
```

| Component | Rules | Examples |
|-----------|-------|----------|
| Prefix | Always `DEC-` | `DEC-` |
| Area | Decision domain, lowercase | `scope`, `ux`, `pricing`, `tech` |
| Decision | 2-5 words describing choice | `power-users-first`, `single-summary-box` |
| Disambiguator | Optional `-2`, `-3` for collisions | `-2`, `-3` |

**Maximum length:** 40 characters after `DEC-`

### Risk IDs
```
RISK-<area>-<risk>[-n]
```

| Component | Rules | Examples |
|-----------|-------|----------|
| Prefix | Always `RISK-` | `RISK-` |
| Area | Risk domain, lowercase | `retention`, `legal`, `tech`, `market` |
| Risk | 2-5 words describing risk | `expert-depth-churn`, `gdpr-processing-basis` |
| Disambiguator | Optional `-2`, `-3` for collisions | `-2`, `-3` |

**Maximum length:** 40 characters after `RISK-`

## Auto-Suggestion Algorithm

When creating an ID, follow these steps:

### Step 1: Extract Keywords
From the claim/decision/risk text, extract the most distinctive words:

```
Claim: "SMB segment willingness-to-pay peaks at $29/mo."
Keywords: SMB, willingness-to-pay, $29, peaks
```

### Step 2: Form Topic
Choose 1-2 keywords that describe the general area:

```
Keywords: SMB, willingness-to-pay, $29, peaks
Topic: pricing (because this is about WTP/price)
```

### Step 3: Form Descriptor
Choose 1-3 keywords that make this specific:

```
Keywords: SMB, willingness-to-pay, $29, peaks
Descriptor: smb-wtp (SMB + willingness-to-pay abbreviated)
```

### Step 4: Combine and Normalize
```
Pillar: market
Topic: pricing
Descriptor: smb-wtp
Result: EV-market-pricing-smb-wtp
```

### Step 5: Check for Collision
If ID already exists:
1. Try adding more specific descriptor
2. If still collides, add `-2`, `-3`, etc.

## Normalization Rules

| Rule | Before | After |
|------|--------|-------|
| Lowercase | `SMB-WTP` | `smb-wtp` |
| Spaces to hyphens | `smb wtp` | `smb-wtp` |
| Remove special chars | `$29/mo` | `29mo` or omit |
| Abbreviate common terms | `willingness-to-pay` | `wtp` |
| Truncate if too long | `this-is-a-very-long-descriptor-name` | `long-descriptor` |

## Common Abbreviations

| Full Term | Abbreviation |
|-----------|--------------|
| willingness-to-pay | wtp |
| total addressable market | tam |
| serviceable addressable market | sam |
| customer acquisition cost | cac |
| lifetime value | ltv |
| application programming interface | api |
| user interface | ui |
| user experience | ux |
| business-to-business | b2b |
| business-to-consumer | b2c |
| small-medium business | smb |

## Examples by Type

### Evidence IDs
```
EV-market-pricing-smb-wtp           # SMB willingness-to-pay research
EV-market-tam-b2b-saas              # B2B SaaS market size
EV-users-onboarding-dropoff         # Onboarding abandonment data
EV-users-workflow-current-state     # Current user workflow documentation
EV-tech-latency-requirements        # Performance requirements research
EV-tech-llm-cost-per-request        # LLM API cost analysis
EV-competitors-notion-pricing       # Notion pricing research
EV-competitors-feature-matrix       # Feature comparison matrix
EV-design-accessibility-wcag        # WCAG accessibility requirements
EV-legal-gdpr-data-processing       # GDPR requirements research
EV-ops-sla-enterprise-reqs          # Enterprise SLA requirements
EV-economics-cac-ltv-benchmarks     # CAC/LTV benchmark research
```

### Decision IDs
```
DEC-scope-power-users-first         # Target power users before SMB
DEC-scope-web-only-mvp              # Web-only for MVP, no mobile
DEC-ux-single-summary-box           # Use single summary box UI pattern
DEC-pricing-freemium-model          # Use freemium pricing model
DEC-tech-postgres-over-mongo        # Choose PostgreSQL over MongoDB
DEC-tech-serverless-architecture    # Use serverless architecture
DEC-legal-gdpr-consent-explicit     # Require explicit GDPR consent
```

### Risk IDs
```
RISK-retention-expert-depth-churn   # Power users churn due to lack of depth
RISK-tech-llm-cost-overrun          # LLM costs exceed projections
RISK-market-competitor-response     # Competitor launches similar feature
RISK-legal-gdpr-processing-basis    # GDPR processing basis challenged
RISK-ops-support-volume-spike       # Support volume exceeds capacity
```

## Collision Handling

When an ID collision occurs:

### Option 1: Make More Specific
```
# Existing
EV-market-pricing-smb-wtp

# New evidence about enterprise pricing
# Instead of: EV-market-pricing-smb-wtp (collision!)
# Use: EV-market-pricing-enterprise-wtp
```

### Option 2: Add Disambiguator
```
# When specificity doesn't help
EV-users-onboarding-dropoff      # Original
EV-users-onboarding-dropoff-2    # Second study on same topic
EV-users-onboarding-dropoff-3    # Third study
```

### When to Use Each
- **Make more specific** when evidence is about different aspects
- **Add disambiguator** when evidence is about the same aspect from different sources/times

## Validation Regex

```regex
# Evidence IDs
^EV-(market|users|tech|competitors|design|legal|ops|economics)-[a-z0-9]+(-[a-z0-9]+)*(-[0-9]+)?$

# Decision IDs
^DEC-[a-z0-9]+(-[a-z0-9]+)*(-[0-9]+)?$

# Risk IDs
^RISK-[a-z0-9]+(-[a-z0-9]+)*(-[0-9]+)?$
```

## Anti-Patterns

| Anti-Pattern | Problem | Better |
|--------------|---------|--------|
| `EV-market-1` | Not semantic | `EV-market-tam-estimate` |
| `EV-market-pricing-stuff` | Vague descriptor | `EV-market-pricing-smb-wtp` |
| `EV-market-pricing-smb-willingness-to-pay-survey-results-2026` | Too long | `EV-market-pricing-smb-wtp` |
| `EV-Market-Pricing-SMB` | Wrong case | `EV-market-pricing-smb` |
| `EV_market_pricing` | Wrong separator | `EV-market-pricing` |
