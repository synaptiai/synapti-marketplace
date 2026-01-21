# Pillar Definitions

The Context Ledger uses 8 research pillars to ensure comprehensive evidence collection.

## The 8 Pillars

### 1. Market (`market`)

**Scope:** Market size, dynamics, trends, and positioning opportunities.

**Research questions:**
- What is the total addressable market (TAM)?
- What are the market growth trends?
- What pricing models exist in this space?
- What is the willingness-to-pay by segment?
- What market gaps or underserved needs exist?

**Evidence types:**
- Market research reports
- Industry analyst data
- Pricing surveys
- Market sizing calculations

**Example IDs:**
- `EV-market-tam-b2b-saas`
- `EV-market-pricing-smb-wtp`
- `EV-market-growth-remote-tools`

---

### 2. Users (`users`)

**Scope:** User needs, behaviors, pain points, and personas.

**Research questions:**
- Who are the target users?
- What are their current workflows?
- What pain points do they experience?
- What jobs-to-be-done are we addressing?
- What are their adoption barriers?

**Evidence types:**
- User interviews
- Survey results
- Usage analytics
- Support ticket analysis
- Behavioral research

**Example IDs:**
- `EV-users-pain-points-manual-tracking`
- `EV-users-workflow-current-state`
- `EV-users-adoption-barriers-learning-curve`

---

### 3. Tech (`tech`)

**Scope:** Technical feasibility, constraints, architecture options.

**Research questions:**
- What technical approaches are viable?
- What are the scalability requirements?
- What dependencies exist?
- What are the performance constraints?
- What technical debt risks exist?

**Evidence types:**
- Technical documentation
- Benchmarks
- Architecture reviews
- Dependency analysis
- Performance studies

**Example IDs:**
- `EV-tech-llm-cost-per-request`
- `EV-tech-latency-requirements`
- `EV-tech-scalability-postgres-limits`

---

### 4. Competitors (`competitors`)

**Scope:** Competitive landscape, differentiation opportunities.

**Research questions:**
- Who are direct competitors?
- Who are indirect/adjacent competitors?
- What are their strengths and weaknesses?
- What is their pricing?
- What features do they offer/lack?

**Evidence types:**
- Competitor product analysis
- Feature comparisons
- Pricing research
- Review analysis
- Market share data

**Example IDs:**
- `EV-competitors-feature-matrix`
- `EV-competitors-pricing-comparison`
- `EV-competitors-weakness-enterprise`

---

### 5. Design (`design`)

**Scope:** UX patterns, design constraints, accessibility requirements.

**Research questions:**
- What UX patterns work in this domain?
- What accessibility requirements apply?
- What design systems to leverage?
- What are the key user flows?
- What are common UX mistakes in this space?

**Evidence types:**
- UX research
- Design audits
- Accessibility guidelines
- User flow analysis
- Usability studies

**Example IDs:**
- `EV-design-ux-patterns-dashboards`
- `EV-design-accessibility-wcag-reqs`
- `EV-design-flow-onboarding-best`

---

### 6. Legal (`legal`)

**Scope:** Compliance requirements, regulatory constraints, legal risks.

**Research questions:**
- What regulations apply (GDPR, CCPA, etc.)?
- What data handling requirements exist?
- What liability risks exist?
- What terms of service considerations?
- What intellectual property issues?

**Evidence types:**
- Regulatory documentation
- Legal opinions
- Compliance frameworks
- Industry standards
- Case law

**Example IDs:**
- `EV-legal-gdpr-data-processing`
- `EV-legal-hipaa-applicability`
- `EV-legal-tos-ai-generated-content`

---

### 7. Ops (`ops`)

**Scope:** Operational requirements, support model, infrastructure needs.

**Research questions:**
- What operational processes are needed?
- What support model is required?
- What infrastructure requirements?
- What monitoring/alerting needs?
- What disaster recovery requirements?

**Evidence types:**
- Operational playbooks
- SLA benchmarks
- Infrastructure studies
- Support ticket analysis
- Incident reports

**Example IDs:**
- `EV-ops-sla-requirements-enterprise`
- `EV-ops-support-volume-estimates`
- `EV-ops-infrastructure-cost-model`

---

### 8. Economics (`economics`)

**Scope:** Unit economics, business model, financial viability.

**Research questions:**
- What is the cost structure?
- What are the unit economics?
- What is the path to profitability?
- What funding requirements exist?
- What are the key financial metrics?

**Evidence types:**
- Financial models
- Cost analysis
- Revenue projections
- Benchmark data
- Industry financials

**Example IDs:**
- `EV-economics-cac-ltv-ratio`
- `EV-economics-gross-margin-target`
- `EV-economics-runway-requirements`

---

## Pillar Interactions

Pillars are not independent. Key interactions:

| Pillar A | Pillar B | Interaction |
|----------|----------|-------------|
| Market | Economics | Market size validates revenue projections |
| Users | Design | User needs drive UX requirements |
| Tech | Ops | Technical choices affect operational burden |
| Competitors | Market | Competitor analysis informs positioning |
| Legal | Tech | Compliance requirements constrain architecture |
| Economics | Ops | Unit economics drive support model |

## Evidence Gates

Before synthesis, each active pillar requires **minimum 5 Evidence Objects**.

| Pillar | Minimum Evidence |
|--------|------------------|
| Market | 5 EV-market-* |
| Users | 5 EV-users-* |
| Tech | 5 EV-tech-* |
| Competitors | 5 EV-competitors-* |
| Design | 5 EV-design-* |
| Legal | 5 EV-legal-* |
| Ops | 5 EV-ops-* |
| Economics | 5 EV-economics-* |

## Deactivating Pillars

Some projects may not need all pillars. To deactivate:

1. Mark as `inactive` in `PILLARS.md`
2. Document reason for deactivation
3. No evidence collection for inactive pillars
4. Synthesis will note "pillar not researched"

**Common deactivations:**
- Legal: Early-stage projects without compliance concerns
- Ops: MVP/prototype phase
- Economics: Research projects without revenue goals
