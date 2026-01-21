---
description: Generate implementation plan with backlog, milestones, and test plan constrained by decisions and risks
argument-hint: "[--format <md|yaml|json>] [--milestones <n>]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Generate Plan

Generate implementation plan including backlog, milestones, and test plan.

> **Risk-Aware Planning**: Plan items link to decisions and explicitly address identified risks with mitigations built into milestones.

## Arguments

`$ARGUMENTS`: Optional plan focus or format.

**Optional flags:**
- `--format <format>` - Output format (markdown, yaml, json)
- `--milestones <n>` - Number of milestones to generate
- `--include-tests` - Include detailed test plan

## Prerequisites

- Specs complete (`/ledger-spec`)
- `06-prd/PRD.md` exists
- `07-architecture/ARCHITECTURE.md` exists
- `04-decisions/DECISIONS.yaml` exists
- `05-risks/RISKS.yaml` exists

## Workflow

1. **Load All Artifacts**
   - Read PRD requirements
   - Read architecture components
   - Read decisions and risks

2. **Generate Backlog**
   - Extract work items from PRD/Architecture
   - Link items to decisions
   - Prioritize by decision status and risk

3. **Create Milestones**
   - Group items into logical milestones
   - Include risk mitigations in early milestones
   - Define acceptance criteria

4. **Generate Test Plan**
   - Map requirements to test cases
   - Include risk validation tests
   - Define test priorities

5. **Write PLAN.md**
   - Comprehensive implementation plan
   - Traceability to decisions/risks

## Example Usage

### Full plan generation
```
/ledger-plan
```

### With specific milestone count
```
/ledger-plan --milestones 4
```

### Include detailed tests
```
/ledger-plan --include-tests
```

### YAML format for tooling
```
/ledger-plan --format yaml
```

## Output

```markdown
## Plan Generation Complete

**Backlog Items:** 47
**Milestones:** 4
**Test Cases:** 32

### Plan Summary

#### Milestone 1: Foundation (Weeks 1-3)
- Items: 12
- Risk mitigations: RISK-tech-cold-start, RISK-tech-llm-cost
- Key decisions: DEC-tech-serverless, DEC-tech-postgres-primary

#### Milestone 2: Core Features (Weeks 4-7)
- Items: 18
- Risk mitigations: RISK-retention-expert-churn
- Key decisions: DEC-scope-power-users-first, DEC-ux-simplified-onboarding

#### Milestone 3: Monetization (Weeks 8-10)
- Items: 10
- Risk mitigations: RISK-economics-free-tier
- Key decisions: DEC-pricing-freemium

#### Milestone 4: Launch Prep (Weeks 11-12)
- Items: 7
- Risk mitigations: RISK-ops-support-volume
- Key decisions: DEC-ops-support-model

### Files Generated
- `08-plan/PLAN.md`

### Next Steps
- Begin implementation following milestone sequence
- Run `/ledger-update` when new learnings emerge
```

## Plan Structure

### Backlog Item Format

```yaml
- id: ITEM-001
  title: "Implement user authentication"
  type: feature | infrastructure | integration | documentation
  priority: P0 | P1 | P2

  # Traceability
  decisions:
    - DEC-tech-auth-jwt
    - DEC-legal-gdpr-consent
  requirements:
    - REQ-005
    - REQ-006
  risks_addressed:
    - RISK-legal-auth-compliance

  # Work breakdown
  tasks:
    - "Design auth flow"
    - "Implement JWT handling"
    - "Add session management"

  # Acceptance criteria
  acceptance:
    - "User can sign up with email"
    - "User can log in/out"
    - "Sessions expire after 24 hours"

  # Estimation
  estimate: S | M | L | XL
  milestone: 1
```

### Milestone Format

```markdown
## Milestone 1: Foundation

**Timeline:** Weeks 1-3
**Theme:** Technical foundation and infrastructure

### Goals
- Establish core infrastructure (DEC-tech-serverless)
- Set up data layer (DEC-tech-postgres-primary)
- Mitigate early technical risks

### Risk Mitigations Included
- RISK-tech-cold-start → Implement warming strategy
- RISK-tech-llm-cost → Add cost monitoring from day 1

### Items
| ID | Title | Priority | Estimate |
|----|-------|----------|----------|
| ITEM-001 | Infrastructure setup | P0 | L |
| ITEM-002 | Database schema | P0 | M |
| ... | ... | ... | ... |

### Acceptance Criteria
- [ ] Infrastructure deployed to staging
- [ ] Database schema implemented
- [ ] CI/CD pipeline operational
- [ ] Cost monitoring dashboard live
```

### Test Plan Format

```markdown
## Test Plan

### Test Strategy
- Unit tests for all business logic
- Integration tests for API endpoints
- E2E tests for critical user flows
- Performance tests for latency requirements

### Test Cases

#### TC-001: User Authentication (REQ-005, REQ-006)
**Decisions:** DEC-tech-auth-jwt
**Priority:** P0

**Cases:**
- [ ] Valid signup creates account
- [ ] Invalid email rejected
- [ ] Login returns valid JWT
- [ ] Expired JWT rejected
- [ ] Logout invalidates session

#### TC-002: Core Workflow (REQ-010)
**Decisions:** DEC-scope-power-users-first
**Priority:** P0
**Risk:** RISK-retention-expert-churn

**Cases:**
- [ ] Power user can complete workflow
- [ ] Workflow handles complexity
- [ ] Performance meets targets
```

## User Interaction

Use the **AskUserQuestion tool** when:

### Prioritization unclear
```
Question: "Multiple items could be P0. Which is most critical?"
Options:
- "Technical foundation first"
- "Core feature first"
- "Risk mitigation first"
- "Let me specify priorities"
```

### Milestone scope
```
Question: "How many milestones should the plan have?"
Options:
- "3 milestones (aggressive timeline)"
- "4 milestones (balanced)" (Recommended)
- "6 milestones (conservative)"
- "Let me specify"
```

### Risk mitigation timing
```
Question: "[RISK-X] is high severity. When to mitigate?"
Options:
- "Milestone 1 (earliest possible)"
- "Before feature that creates risk"
- "Defer mitigation (accept risk)"
```

## After Plan

With the plan complete, implementation can begin:

1. `/ledger-init` - Initialize (completed)
2. `/ledger-research` - Collect evidence (completed)
3. `/ledger-synthesize` - Synthesize findings (completed)
4. `/ledger-decide` - Make decisions (completed)
5. `/ledger-spec` - Generate specs (completed)
6. `/ledger-plan` - Generate plan (you are here)

**Implementation:** Follow milestone sequence
**Updates:** Run `/ledger-update` when new learnings emerge
