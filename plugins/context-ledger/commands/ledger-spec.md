---
description: Generate constrained PRD and architecture documents where every section cites decisions
argument-hint: "[--prd-only] [--arch-only] [--focus <area>]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion
---

# Generate Specs

Generate PRD and architecture documents constrained by the decision ledger.

> **Constraint Enforcement**: Every section, requirement, and technical choice must cite DEC-* references. Content without decision support cannot be generated.

## Arguments

`$ARGUMENTS`: Optional spec type or focus area.

**Optional flags:**
- `--prd-only` - Generate only PRD
- `--arch-only` - Generate only architecture
- `--focus <area>` - Focus on specific area (scope, pricing, tech, etc.)

## Prerequisites

- Decisions complete (`/ledger-decide`)
- `04-decisions/DECISIONS.yaml` exists
- `05-risks/RISKS.yaml` exists

## Workflow

1. **Load Decision Ledger**
   - Read all decisions from `DECISIONS.yaml`
   - Read all risks from `RISKS.yaml`
   - Build decision index by area

2. **Generate PRD**
   - Map decisions to PRD sections
   - Write `06-prd/PRD.md` with citations
   - Validate constraint gate

3. **Generate Architecture**
   - Map technical decisions to architecture sections
   - Write `07-architecture/ARCHITECTURE.md` with citations
   - Validate constraint gate

4. **Cross-Reference**
   - Ensure decision coverage
   - Link risks to relevant sections
   - Generate traceability summary

## Example Usage

### Full spec generation
```
/ledger-spec
```

### PRD only
```
/ledger-spec --prd-only
```

### Architecture only
```
/ledger-spec --arch-only
```

### Focus on specific area
```
/ledger-spec --focus tech
```

## Output

```markdown
## Spec Generation Complete

**PRD:** 06-prd/PRD.md (14 sections)
**Architecture:** 07-architecture/ARCHITECTURE.md (11 sections)

### Constraint Gate Status
- PRD gate: ✓ All 14 sections cite decisions
- Architecture gate: ✓ All 11 sections cite decisions

### Decision Coverage

| Decision | Status | PRD Sections | Arch Sections |
|----------|--------|--------------|---------------|
| DEC-scope-power-users-first | accepted | 1, 2, 4, 5 | 2, 3 |
| DEC-pricing-freemium | provisional | 3, 8 | - |
| DEC-tech-postgres-primary | accepted | - | 3, 4, 5 |
| DEC-tech-serverless | accepted | - | 1, 5, 8 |
| DEC-legal-gdpr-consent | accepted | 7 | 6 |
| ... | ... | ... | ... |

### Orphaned Decisions (not referenced)
- DEC-gtm-launch-timing (may need GTM section)

### Risks Cross-Referenced
| Risk | PRD Sections | Arch Sections |
|------|--------------|---------------|
| RISK-retention-expert-churn | 2, 5 | - |
| RISK-tech-llm-cost | 5 | 5, 7 |
| RISK-economics-free-tier | 8 | 7 |

### Files Generated
- `06-prd/PRD.md`
- `07-architecture/ARCHITECTURE.md`

### Next Step
Run `/ledger-plan` to generate implementation backlog.
```

## Constraint Gate

### What Gets Checked

**PRD Gate:**
- Every section heading has DEC-* reference
- Every requirement cites a decision
- No content contradicts decisions
- All cited decisions exist and are not rejected

**Architecture Gate:**
- Every section heading has DEC-* reference
- Every technical choice cites a decision
- No content contradicts decisions
- All cited decisions exist and are not rejected

### Gate Failures

If constraint gate fails:

```markdown
### Constraint Gate FAILED

**Violations:**
1. PRD Section 5 lacks DEC-* citation
2. REQ-012 cites DEC-scope-mobile which is REJECTED
3. ARCH Section 4 contradicts DEC-tech-postgres-primary

**Resolution Required:**
- Add decision citation or remove content
- Update requirement to cite valid decision
- Resolve contradiction
```

## User Interaction

Use the **AskUserQuestion tool** when:

### Missing decision for content
```
Question: "PRD section '[X]' has no supporting decision. How to proceed?"
Options:
- "Skip this section (mark out of scope)"
- "Create a new decision to support this"
- "It relates to existing [DEC-Y] - explain how"
```

### Content contradicts decision
```
Question: "Requirement '[X]' contradicts [DEC-Y]. How to resolve?"
Options:
- "Revise requirement to align with decision"
- "The decision should be revisited"
- "Explain why they don't actually conflict"
```

### Decision not referenced
```
Question: "Decision [DEC-X] isn't referenced in any spec section. Handle?"
Options:
- "Add spec section for this decision"
- "Decision doesn't need spec coverage"
- "Combine with existing section [Y]"
```

## After Specs

The typical workflow continues:

1. `/ledger-init` - Initialize (completed)
2. `/ledger-research` - Collect evidence (completed)
3. `/ledger-synthesize` - Synthesize findings (completed)
4. `/ledger-decide` - Make decisions (completed)
5. `/ledger-spec` - Generate specs (you are here)
6. `/ledger-plan` - Generate implementation plan
