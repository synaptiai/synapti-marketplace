---
description: Apply new learnings to the ledger and generate impact report showing what downstream artifacts need regeneration
argument-hint: "[--evidence <pillar>] [--decision <id>] [--regenerate]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion
---

# Update Ledger

Apply new evidence, decisions, or learnings to the ledger with impact analysis.

> **Impact-Aware Updates**: Changes are tracked and produce a diff showing what downstream artifacts are affected and may need regeneration.

## Arguments

`$ARGUMENTS`: What to update - evidence, decision, or general.

**Optional flags:**
- `--evidence <pillar>` - Add evidence to specific pillar
- `--decision <id>` - Update specific decision
- `--risk <id>` - Update specific risk
- `--regenerate` - Auto-regenerate affected artifacts

## Prerequisites

- Ledger initialized (any phase complete)
- Existing artifacts to update

## Workflow

1. **Identify Change Type**
   - New evidence
   - Updated evidence
   - Decision status change
   - Risk update
   - Synthesis revision

2. **Apply Change**
   - Add/modify artifact
   - Record change metadata

3. **Trace Impact**
   - Find all references to changed artifact
   - Identify affected downstream documents

4. **Generate Impact Report**
   - What changed
   - What's affected
   - Recommended actions

5. **Optionally Regenerate**
   - If `--regenerate`, update affected artifacts
   - Maintain traceability

## Example Usage

### Add new evidence
```
/ledger-update --evidence market
```

### Update decision status
```
/ledger-update --decision DEC-scope-power-users-first
```

### Update risk mitigation
```
/ledger-update --risk RISK-retention-expert-churn
```

### Auto-regenerate affected docs
```
/ledger-update --regenerate
```

### General update prompt
```
/ledger-update "We learned SMB WTP is actually $35 not $29"
```

## Output

```markdown
## Ledger Update Complete

### What Changed
| Artifact | Change Type | Details |
|----------|-------------|---------|
| EV-market-pricing-smb-wtp | updated | confidence: 0.75 → 0.85, claim revised |
| DEC-pricing-freemium | status change | provisional → accepted |

### Impact Analysis

#### Direct Impact (explicit references)
| Affected Artifact | References Changed | Impact |
|-------------------|-------------------|--------|
| SYN-market.md | EV-market-pricing-smb-wtp | Insight confidence may change |
| CROSS-SYNTHESIS.md | SYN-market.md | Cross-pillar connection affected |
| PRD Section 8 | DEC-pricing-freemium | Status now accepted |

#### Indirect Impact (downstream)
| Affected Artifact | Via | Impact |
|-------------------|-----|--------|
| DECISIONS.yaml | SYN-market.md | May affect decisions citing this evidence |
| PLAN.md | PRD Section 8 | Milestone may need update |

### Impact Report Generated
`IMPACT_REPORT.md`

### Recommended Actions
- [ ] Review SYN-market.md insight on pricing
- [ ] Verify CROSS-SYNTHESIS.md pricing connection
- [ ] PRD Section 8 status confirmed (no change needed)

### Next Steps
Run `/ledger-update --regenerate` to auto-update affected artifacts.
```

## Impact Report Format

Generated at ledger root as `IMPACT_REPORT.md`:

```markdown
# Impact Report

**Generated:** 2026-01-21
**Update Type:** evidence, decision

## What Changed

### Evidence Added/Updated
| ID | Change | Details |
|----|--------|---------|
| EV-market-pricing-smb-wtp | updated | Revised WTP from $29 to $35 |

### Decisions Updated
| ID | Change | Details |
|----|--------|---------|
| DEC-pricing-freemium | status | provisional → accepted |

## What Is Affected

### Synthesis Documents
| Document | Reason |
|----------|--------|
| SYN-market.md | EV-market-pricing-smb-wtp updated |
| CROSS-SYNTHESIS.md | Depends on SYN-market.md |

### PRD Sections
| Section | Referenced Decisions | Impact |
|---------|---------------------|--------|
| Section 8 (Pricing) | DEC-pricing-freemium | Status confirmed |

### Architecture Sections
(none affected)

### Plan Items
| Item | Impact |
|------|--------|
| Milestone 3 | Based on DEC-pricing-freemium |

## Dependency Graph

```
EV-market-pricing-smb-wtp (UPDATED)
  └── SYN-market.md
      └── CROSS-SYNTHESIS.md
          └── DEC-pricing-freemium (UPDATED)
              └── PRD Section 8
                  └── PLAN.md Milestone 3
```

## Recommended Actions

### Immediate
- [ ] Review pricing insight in SYN-market.md

### Review
- [ ] Verify CROSS-SYNTHESIS.md connections
- [ ] Check PLAN.md Milestone 3 assumptions

### Optional
- [ ] Consider regenerating synthesis
```

## Update Types

### Evidence Update

```
/ledger-update --evidence market "New research shows SMB WTP is $35"
```

Actions:
1. Create or update EV-* file
2. Trace references in synthesis
3. Note decisions that cite this evidence
4. Generate impact report

### Decision Update

```
/ledger-update --decision DEC-scope-power-users-first "Moving to accepted"
```

Actions:
1. Update DECISIONS.yaml status
2. Trace PRD sections citing this decision
3. Trace Architecture sections citing this decision
4. Note plan items affected
5. Generate impact report

### Risk Update

```
/ledger-update --risk RISK-retention-expert-churn "Adding new mitigation"
```

Actions:
1. Update RISKS.yaml
2. Note where risk is cross-referenced
3. Generate impact report

### General Update

```
/ledger-update "We've decided mobile is now in scope"
```

Actions:
1. Parse update intent
2. Identify affected decisions
3. Prompt for decision changes
4. Trace impacts
5. Generate impact report

## User Interaction

Use the **AskUserQuestion tool** when:

### Update type unclear
```
Question: "What type of update is this?"
Options:
- "New evidence for [pillar]"
- "Update existing evidence"
- "Change decision status"
- "Add/update risk"
- "General learning"
```

### Impact severity
```
Question: "This change affects [N] downstream artifacts. How to proceed?"
Options:
- "Generate impact report only"
- "Auto-regenerate affected synthesis"
- "Auto-regenerate all affected artifacts"
- "Let me review first"
```

### Conflict detected
```
Question: "This update conflicts with [DEC-X]. How to resolve?"
Options:
- "Update the decision too"
- "Keep decision, adjust this update"
- "Flag as contradiction for review"
```

## After Update

After applying updates:
- Review impact report
- Decide which artifacts to regenerate
- Re-run `/ledger-synthesize` if evidence changed significantly
- Re-run `/ledger-spec` if decisions changed
- Re-run `/ledger-plan` if specs changed
