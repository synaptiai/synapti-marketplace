# Decision Ledger Schema

The canonical YAML schema for `04-decisions/DECISIONS.yaml`.

## Full Schema

```yaml
# DECISIONS.yaml
# All project decisions with trade-offs and evidence

decisions:
  - id: DEC-<area>-<decision>[-n]  # Semantic ID
    decision: string               # The decision made (1-2 sentences)
    status: accepted | provisional | rejected
    owner: string                  # Who made/owns this decision
    created_at: YYYY-MM-DD
    updated_at: YYYY-MM-DD         # Optional, when last modified

    # Alternatives considered (required, at least 1)
    alternatives:
      - string  # Alternative option that was NOT chosen
      - string

    # Evidence supporting this decision (required, at least 2)
    evidence:
      - EV-*  # Evidence ID
      - EV-*

    # Trade-offs (required)
    tradeoffs:
      wins:
        - string  # What we gain from this decision
        - string
      loses:
        - string  # What we give up with this decision
        - string

    # Risks created by this decision (optional)
    risks:
      - RISK-*  # Risk ID

    # Implications (required, at least 1)
    implications:
      - string  # Downstream effect of this decision
      - string

    # Notes (optional)
    notes: string  # Additional context, rationale, caveats
```

## Field Definitions

### id (required)
Unique semantic identifier: `DEC-<area>-<decision>[-n]`

**Areas:**
- `scope` - What to build, what to exclude
- `ux` - User experience decisions
- `pricing` - Pricing and packaging
- `tech` - Technical architecture
- `legal` - Compliance and legal
- `ops` - Operations and support
- `gtm` - Go-to-market strategy
- `team` - Team and process

**Examples:**
```yaml
DEC-scope-power-users-first
DEC-pricing-freemium-model
DEC-tech-postgres-over-mongo
DEC-legal-gdpr-explicit-consent
```

### decision (required)
The actual decision made. Should be:
- Clear and unambiguous
- 1-2 sentences maximum
- Actionable (what we WILL do)

**Good:**
```yaml
decision: "Target power users before expanding to SMB segment"
decision: "Use freemium model with 14-day trial of premium features"
decision: "Require explicit opt-in consent for GDPR compliance"
```

**Bad:**
```yaml
decision: "Consider targeting users"  # Too vague
decision: "We might use freemium or maybe paid"  # Not a decision
decision: "Do the pricing thing"  # Incomprehensible
```

### status (required)
Current status of the decision:

| Status | Meaning | When to Use |
|--------|---------|-------------|
| `accepted` | Committed, will implement | Decision is final |
| `provisional` | Tentative, may revisit | Awaiting more evidence |
| `rejected` | Previously considered, not doing | Documenting why not |

### owner (required)
Who made or owns this decision. Usually "user" for user-made decisions.

### alternatives (required)
Other options that were considered but NOT chosen.

**Every decision must list at least 1 alternative.**

This documents that options were evaluated, not arbitrary.

```yaml
alternatives:
  - "Enterprise-first approach"
  - "Multi-segment simultaneous launch"
  - "Geographic segmentation instead"
```

### evidence (required)
Evidence IDs that informed this decision.

**Every decision must cite at least 2 evidence IDs.**

```yaml
evidence:
  - EV-market-tam-smb
  - EV-users-power-user-retention
  - EV-economics-smb-unit-economics
```

### tradeoffs (required)
What we gain and lose with this decision.

**Both `wins` and `loses` must have at least 1 entry.**

```yaml
tradeoffs:
  wins:
    - "Faster iteration cycles"
    - "Lower customer acquisition cost"
    - "Self-serve possible"
  loses:
    - "Lower initial contract values"
    - "May need enterprise pivot later"
    - "Limited negotiating leverage"
```

### risks (optional)
Risk IDs created by this decision. Links to `05-risks/RISKS.yaml`.

```yaml
risks:
  - RISK-retention-smb-churn
  - RISK-market-enterprise-blocked
```

### implications (required)
Downstream effects of this decision on other work.

**At least 1 implication required.**

```yaml
implications:
  - "MVP UX must optimize for self-serve onboarding"
  - "Pricing must fit SMB budget (<$50/mo)"
  - "Support model must scale without dedicated reps"
```

### notes (optional)
Additional context, rationale, or caveats.

```yaml
notes: "Revisit after 6 months of market data. If enterprise demand emerges, may need to reconsider."
```

## Complete Example

```yaml
decisions:
  - id: DEC-scope-power-users-first
    decision: "Target power users within SMB segment before broadening"
    status: accepted
    owner: user
    created_at: 2026-01-21

    alternatives:
      - "Enterprise-first approach"
      - "Broad SMB without power-user focus"
      - "Multi-segment simultaneous"

    evidence:
      - EV-users-power-user-retention
      - EV-users-power-user-advocacy
      - EV-market-tam-smb
      - EV-economics-smb-cac

    tradeoffs:
      wins:
        - "Power users provide better feedback"
        - "Higher retention reduces CAC payback"
        - "Advocacy drives organic growth"
        - "Smaller scope enables faster iteration"
      loses:
        - "Narrower initial market"
        - "Power user needs may differ from mainstream"
        - "May overbuild for average users"

    risks:
      - RISK-retention-expert-depth-churn
      - RISK-market-power-user-niche

    implications:
      - "MVP must include advanced features power users expect"
      - "Onboarding must handle complexity without losing users"
      - "Community/feedback channels prioritize power users"
      - "Marketing must target power user channels"

    notes: "Based on interviews showing power users have 3x retention and generate 80% of referrals. Revisit if power user acquisition proves difficult."

  - id: DEC-pricing-freemium-model
    decision: "Use freemium pricing with usage-based premium tier"
    status: provisional
    owner: user
    created_at: 2026-01-21

    alternatives:
      - "Paid-only with free trial"
      - "Flat-rate subscription"
      - "Enterprise-only sales"

    evidence:
      - EV-competitors-pricing-freemium
      - EV-market-pricing-smb-wtp
      - EV-economics-freemium-conversion

    tradeoffs:
      wins:
        - "Lower barrier to adoption"
        - "Viral potential from free users"
        - "Usage data before commitment"
      loses:
        - "Free tier support costs"
        - "Conversion rate uncertainty"
        - "Perceived value may be lower"

    risks:
      - RISK-economics-free-tier-costs

    implications:
      - "Must define clear free/paid boundary"
      - "Infrastructure must handle free-tier load"
      - "Conversion optimization critical"

    notes: "Marked provisional - need to validate conversion assumptions with early cohort data."
```

## Quality Checklist

Before finalizing DECISIONS.yaml:

- [ ] Every decision has semantic ID
- [ ] Every decision cites ≥2 evidence IDs
- [ ] Every decision lists ≥1 alternative
- [ ] Every decision has wins AND loses
- [ ] Every decision has ≥1 implication
- [ ] All referenced EV-* IDs exist
- [ ] All referenced RISK-* IDs exist in RISKS.yaml
- [ ] No duplicate decision IDs
