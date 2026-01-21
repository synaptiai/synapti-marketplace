---
description: Make explicit decisions with trade-offs, alternatives, and evidence citations
argument-hint: "[--review] [--accept-all-provisional]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Make Decisions

Transform synthesis insights into explicit decisions with documented trade-offs.

> **Interactive Decision-Making**: This command walks through each decision candidate, presenting options with evidence and requiring explicit user choice.

## Arguments

`$ARGUMENTS`: Optional decision filter or focus area.

**Optional flags:**
- `--decisions <list>` - Only process specific decision topics
- `--status <status>` - Filter by decision status (accepted, provisional, rejected)
- `--risks-only` - Only process risk identification (skip decisions)

## Prerequisites

- Synthesis complete (`/ledger-synthesize`)
- `03-synthesis/CROSS-SYNTHESIS.md` exists with decision candidates
- Per-pillar syntheses in `03-synthesis/SYN-*.md`

## Workflow

1. **Load Decision Candidates**
   - Extract from `CROSS-SYNTHESIS.md`
   - Gather supporting evidence for each

2. **For Each Decision:**
   - Present options with evidence summary
   - Show trade-offs (wins/loses)
   - Request user decision via AskUserQuestion
   - Confirm trade-off acceptance
   - Record decision with semantic ID

3. **Identify Created Risks**
   - For each accepted decision
   - Identify risks the decision creates
   - Document triggers and mitigations

4. **Generate Ledger Files**
   - Write `04-decisions/DECISIONS.yaml`
   - Write `05-risks/RISKS.yaml`

5. **Validate Quality Gates**
   - Decision gate: ≥2 evidence per decision
   - Risk gate: ≥1 mitigation per risk

## Example Usage

### Full decision process
```
/ledger-decide
```

### Specific decisions only
```
/ledger-decide --decisions scope,pricing
```

### Update risk mitigations
```
/ledger-decide --risks-only
```

## Output

```markdown
## Decisions Complete

**Decisions Made:** 8
**Status:** 6 accepted, 2 provisional
**Risks Identified:** 12

### Decisions Made
| ID | Decision | Status | Trade-offs |
|----|----------|--------|------------|
| DEC-scope-power-users-first | Target power users | accepted | +3 wins, -2 loses |
| DEC-pricing-freemium | Use freemium model | provisional | +3 wins, -3 loses |
| DEC-tech-serverless | Serverless architecture | accepted | +4 wins, -2 loses |
| ... | ... | ... | ... |

### Risks Created
| ID | Risk | Severity | Likelihood |
|----|------|----------|------------|
| RISK-retention-expert-churn | Power user churn | high | medium |
| RISK-economics-free-tier | Free tier costs | medium | medium |
| RISK-tech-cold-start | Serverless cold start | medium | low |
| ... | ... | ... | ... |

### Quality Gates
- Decision gate: ✓ All decisions cite ≥2 evidence
- Risk gate: ✓ All risks have mitigations

### Files Generated
- `04-decisions/DECISIONS.yaml`
- `05-risks/RISKS.yaml`

### Next Step
Run `/ledger-spec` to generate constrained PRD and architecture.
```

## Decision Process

For each decision candidate:

### 1. Present Options
```
Decision: Target Segment Priority

Option A: Power Users First
- Evidence: EV-users-power-user-retention (0.80), EV-users-power-user-advocacy (0.75)
- Wins: Better feedback, higher retention, organic growth
- Loses: Narrower market, may overbuild

Option B: Broad SMB
- Evidence: EV-market-tam-smb (0.85), EV-economics-smb-volume (0.70)
- Wins: Larger market, simpler features
- Loses: Lower retention, commoditized

Option C: Enterprise First
- Evidence: EV-market-enterprise-tam (0.85), EV-competitors-enterprise-gap (0.70)
- Wins: Higher contract values, less competition
- Loses: Longer sales cycle, higher support cost
```

### 2. Get User Decision
```
Question: "Which target segment should we prioritize?"
Options:
- "Power Users First - higher retention path"
- "Broad SMB - larger market path"
- "Enterprise First - higher revenue path"
- "Need more information"
```

### 3. Confirm Trade-offs
```
Question: "Confirming: You chose 'Power Users First'. Accept these trade-offs?"
Options:
- "Yes, accept trade-offs"
- "Wait, let me reconsider"
- "Explain trade-offs more"
```

### 4. Set Status
```
Question: "Decision status?"
Options:
- "Accepted - committed to this"
- "Provisional - may revisit later"
```

### 5. Document Created Risks
```
Question: "This decision may create 'Power user churn risk'. Severity?"
Options:
- "High - critical to monitor"
- "Medium - important but manageable"
- "Low - acceptable risk"
```

## Quality Gates

### Decision Quality Gate
Every decision must have:
- ≥2 evidence IDs cited
- ≥1 alternative considered
- Both wins AND loses documented
- ≥1 implication listed

### Risk Quality Gate
Every risk must have:
- Link to creating decision
- Severity and likelihood
- ≥1 trigger condition
- ≥1 mitigation action

## After Decisions

The typical workflow continues:

1. `/ledger-init` - Initialize (completed)
2. `/ledger-research` - Collect evidence (completed)
3. `/ledger-synthesize` - Synthesize findings (completed)
4. `/ledger-decide` - Make decisions (you are here)
5. `/ledger-spec` - Generate constrained PRD + architecture
6. `/ledger-plan` - Generate implementation plan
