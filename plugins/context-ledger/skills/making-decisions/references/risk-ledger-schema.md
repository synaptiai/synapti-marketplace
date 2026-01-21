# Risk Ledger Schema

The canonical YAML schema for `05-risks/RISKS.yaml`.

## Full Schema

```yaml
# RISKS.yaml
# All identified risks with triggers and mitigations

risks:
  - id: RISK-<area>-<risk>[-n]  # Semantic ID
    title: string               # Short risk title
    description: string         # Detailed risk description
    severity: low | medium | high
    likelihood: low | medium | high

    # What would trigger this risk materializing
    triggers:
      - string
      - string

    # How to mitigate or monitor this risk
    mitigations:
      - string
      - string

    # Evidence supporting this risk (optional)
    evidence:
      - EV-*

    # Decisions that created this risk
    linked_decisions:
      - DEC-*

    # Status tracking
    status: active | mitigated | accepted | obsolete
    created_at: YYYY-MM-DD
    updated_at: YYYY-MM-DD

    # Notes (optional)
    notes: string
```

## Field Definitions

### id (required)
Unique semantic identifier: `RISK-<area>-<risk>[-n]`

**Areas:**
- `market` - Market and competitive risks
- `users` - User adoption and retention risks
- `tech` - Technical and infrastructure risks
- `legal` - Legal and compliance risks
- `ops` - Operational risks
- `economics` - Financial and business model risks
- `team` - Team and organizational risks
- `execution` - Delivery and timeline risks

**Examples:**
```yaml
RISK-market-competitor-response
RISK-users-power-user-churn
RISK-tech-llm-cost-overrun
RISK-legal-gdpr-violation
RISK-economics-unit-economics-negative
```

### title (required)
Short, descriptive title (5-10 words).

```yaml
title: "Power users churn due to insufficient depth"
title: "LLM API costs exceed projections"
title: "GDPR processing basis challenged"
```

### description (required)
Detailed description of the risk (2-4 sentences).

```yaml
description: "By targeting power users first, we risk building features that are too basic for their needs, leading to churn. Power users have high expectations and may leave for competitors that offer more advanced functionality."
```

### severity (required)
Impact if the risk materializes:

| Severity | Impact |
|----------|--------|
| `low` | Minor setback, easily recovered |
| `medium` | Significant impact, requires effort to address |
| `high` | Major impact, could threaten project success |

### likelihood (required)
Probability the risk will materialize:

| Likelihood | Probability |
|------------|-------------|
| `low` | Unlikely (<25%) |
| `medium` | Possible (25-60%) |
| `high` | Likely (>60%) |

### Risk Matrix

| | Low Severity | Medium Severity | High Severity |
|---|---|---|---|
| **High Likelihood** | Medium priority | High priority | Critical |
| **Medium Likelihood** | Low priority | Medium priority | High priority |
| **Low Likelihood** | Accept | Low priority | Medium priority |

### triggers (required)
What conditions would indicate this risk is materializing?

**At least 1 trigger required.**

```yaml
triggers:
  - "Power user retention drops below 60% at 30 days"
  - "Feature requests from power users exceed capacity"
  - "Competitor launches advanced features"
```

### mitigations (required)
Actions to reduce likelihood or impact.

**At least 1 mitigation required.**

```yaml
mitigations:
  - "Build advanced feature roadmap based on power user feedback"
  - "Establish power user advisory board for early feedback"
  - "Monitor competitor feature releases weekly"
  - "Plan 'expert mode' feature flag for rapid response"
```

### evidence (optional)
Evidence IDs that support this risk identification.

```yaml
evidence:
  - EV-users-power-user-expectations
  - EV-competitors-feature-depth
```

### linked_decisions (required)
Decision IDs that created or relate to this risk.

**Every risk must link to at least 1 decision.**

```yaml
linked_decisions:
  - DEC-scope-power-users-first
```

### status (required)
Current status of the risk:

| Status | Meaning |
|--------|---------|
| `active` | Risk is current and being monitored |
| `mitigated` | Mitigations in place, reduced concern |
| `accepted` | Acknowledged, no action planned |
| `obsolete` | No longer relevant (decision changed, etc.) |

### notes (optional)
Additional context or commentary.

```yaml
notes: "This risk is elevated during the first 6 months. After establishing power user base, can reassess."
```

## Complete Example

```yaml
risks:
  - id: RISK-retention-expert-depth-churn
    title: "Power users churn due to insufficient feature depth"
    description: "By targeting power users first, we risk building features that are too basic for their needs. Power users have high expectations and may leave for competitors offering more advanced functionality if we don't meet their depth requirements."
    severity: high
    likelihood: medium

    triggers:
      - "Power user 30-day retention drops below 60%"
      - "Feature request volume from power users exceeds dev capacity"
      - "Direct competitor launches advanced features"
      - "Power user NPS drops below 30"

    mitigations:
      - "Establish power user advisory board for early feedback"
      - "Build advanced feature roadmap prioritizing power user needs"
      - "Plan 'expert mode' feature flag for rapid deployment"
      - "Weekly competitor feature monitoring"
      - "Bi-weekly power user interviews during MVP"

    evidence:
      - EV-users-power-user-expectations
      - EV-users-power-user-workflow-complexity
      - EV-competitors-notion-advanced-features

    linked_decisions:
      - DEC-scope-power-users-first

    status: active
    created_at: 2026-01-21

    notes: "Highest priority risk for first 6 months. Review monthly with retention data."

  - id: RISK-economics-free-tier-costs
    title: "Free tier infrastructure costs exceed projections"
    description: "Freemium model may attract users who consume resources without converting to paid. LLM API costs for free users could make unit economics unsustainable."
    severity: medium
    likelihood: medium

    triggers:
      - "Free tier cost per user exceeds $2/month"
      - "Free-to-paid conversion rate below 3%"
      - "LLM costs grow faster than paid revenue"

    mitigations:
      - "Implement usage caps on free tier"
      - "Use smaller/cheaper models for free tier"
      - "Track unit economics weekly from launch"
      - "Build kill switch for expensive free features"

    evidence:
      - EV-tech-llm-cost-per-request
      - EV-economics-freemium-conversion-benchmarks

    linked_decisions:
      - DEC-pricing-freemium-model

    status: active
    created_at: 2026-01-21

    notes: "Provisional decision - will revisit if conversion data doesn't support model."

  - id: RISK-legal-gdpr-processing-basis
    title: "GDPR processing basis for AI features challenged"
    description: "Using user content to train or improve AI models may face GDPR scrutiny. Processing basis (legitimate interest vs. consent) could be challenged by regulators or users."
    severity: high
    likelihood: low

    triggers:
      - "User complaint about data usage"
      - "Regulatory inquiry about AI training data"
      - "Competitor makes privacy a competitive advantage"

    mitigations:
      - "Clear consent mechanism for AI feature usage"
      - "Option to opt-out of model improvement"
      - "Data retention policy aligned with GDPR"
      - "Legal review of privacy policy quarterly"

    evidence:
      - EV-legal-gdpr-ai-processing
      - EV-legal-competitor-privacy-policies

    linked_decisions:
      - DEC-legal-gdpr-explicit-consent

    status: active
    created_at: 2026-01-21
```

## Quality Checklist

Before finalizing RISKS.yaml:

- [ ] Every risk has semantic ID
- [ ] Every risk has severity AND likelihood
- [ ] Every risk has ≥1 trigger
- [ ] Every risk has ≥1 mitigation
- [ ] Every risk links to ≥1 decision
- [ ] All referenced DEC-* IDs exist in DECISIONS.yaml
- [ ] All referenced EV-* IDs exist in evidence
- [ ] No duplicate risk IDs
- [ ] All high/high risks have multiple mitigations
