---
description: Synthesize evidence into insights through per-pillar and cross-pillar analysis
argument-hint: "[--pillar <name>] [--cross-only]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion
---

# Synthesize Evidence

Process evidence objects into structured insights through layered synthesis.

> **Two-Phase Synthesis**: First, `pillar-synthesizer` agents process each pillar independently. Then, `cross-synthesizer` identifies connections and conflicts across pillars.

## Arguments

`$ARGUMENTS`: Optional synthesis focus or pillar filter.

**Optional flags:**
- `--pillars <list>` - Only synthesize specific pillars
- `--skip-cross` - Skip cross-pillar synthesis
- `--focus <topic>` - Prioritize insights on specific topic

## Prerequisites

- Evidence collection complete (`/ledger-research`)
- Evidence gates passed (≥5 objects per active pillar)
- Evidence objects in `02-evidence/<pillar>/`

## Workflow

### Phase 1: Per-Pillar Synthesis

1. **Spawn Pillar Synthesizers**
   - One `pillar-synthesizer` per active pillar
   - Agents run in parallel

2. **Each Agent:**
   - Loads all `EV-<pillar>-*` evidence
   - Clusters by theme
   - Identifies patterns
   - Handles contradictions
   - Extracts key insights
   - Generates `SYN-<pillar>.md`

3. **Output:** 8 synthesis documents in `03-synthesis/`

### Phase 2: Cross-Pillar Synthesis

1. **Spawn Cross-Synthesizer**
   - Single agent after all pillar syntheses complete

2. **Agent:**
   - Loads all `SYN-*.md` documents
   - Maps cross-pillar connections
   - Identifies cross-pillar conflicts
   - Extracts emergent insights
   - Generates decision candidates
   - Identifies risk candidates
   - Generates `CROSS-SYNTHESIS.md`

3. **Output:** `03-synthesis/CROSS-SYNTHESIS.md`

## Example Usage

### Full synthesis
```
/ledger-synthesize
```

### Specific pillars only
```
/ledger-synthesize --pillars market,users,economics
```

### Skip cross-synthesis
```
/ledger-synthesize --skip-cross
```

### Focus on specific topic
```
/ledger-synthesize --focus pricing
```

## Output

```markdown
## Synthesis Complete

**Pillars Synthesized:** 8
**Total Insights:** 42
**Cross-Pillar Connections:** 12
**Conflicts Identified:** 5

### Per-Pillar Summary
| Pillar | Insights | Contradictions | Decisions Needed |
|--------|----------|----------------|------------------|
| market | 6 | 1 resolved | 2 |
| users | 7 | 2 (1 pending) | 3 |
| tech | 5 | 0 | 1 |
| competitors | 5 | 1 resolved | 2 |
| design | 4 | 0 | 1 |
| legal | 4 | 0 | 2 |
| ops | 5 | 1 resolved | 1 |
| economics | 6 | 1 pending | 3 |

### Cross-Pillar Highlights

**Key Connections:**
1. Market pricing ceiling ($30) constrains Economics margin targets
2. User power-user preference aligns with Tech capability focus
3. Competitor gap in enterprise aligns with Market enterprise TAM

**Key Conflicts:**
1. Target segment: Market (enterprise) vs Users (SMB) vs Economics (SMB)
2. Pricing model: Competitors (freemium) vs Economics (paid)

### Decision Candidates
1. DEC-scope-target-segment
2. DEC-pricing-model
3. DEC-ux-complexity-level
4. DEC-tech-architecture-choice
5. DEC-legal-gdpr-approach

### Risk Candidates
1. RISK-market-price-competition
2. RISK-tech-llm-cost-overrun
3. RISK-retention-expert-churn

### Next Step
Run `/ledger-decide` to make explicit decisions with trade-offs.
```

## Synthesis Documents

### Per-Pillar (`SYN-<pillar>.md`)
- Executive summary
- Key insights with evidence citations
- Contradictions and resolutions
- Gaps and uncertainties
- Recommended decisions

### Cross-Pillar (`CROSS-SYNTHESIS.md`)
- Cross-pillar connections
- Cross-pillar conflicts
- Emergent insights
- Decision candidates
- Risk candidates

## User Interaction

Use the **AskUserQuestion tool** when:

### Contradiction resolution
```
After pillar synthesis:
→ If unresolved contradiction:
  Question: "[Pillar] has unresolved contradiction on [topic]. How to handle?"
  Options:
  - "Defer to decision phase" (Recommended)
  - "Research more to resolve"
  - "Accept higher-confidence source"
```

### Cross-pillar conflict prioritization
```
After cross-synthesis:
→ Multiple conflicts found:
  Question: "Multiple cross-pillar conflicts. Which is most critical?"
  Options:
  - "[Conflict A] - core product scope"
  - "[Conflict B] - go-to-market strategy"
  - "[Conflict C] - technical architecture"
  - "All equally important"
```

### Insight validation
```
During synthesis:
→ Emergent insight unclear:
  Question: "Cross-pillar analysis suggests [insight]. Is this correct?"
  Options:
  - "Yes, that interpretation is correct"
  - "No, the relationship is different"
  - "Need more context"
```

## After Synthesis

The typical workflow continues:

1. `/ledger-init` - Initialize (completed)
2. `/ledger-research` - Collect evidence (completed)
3. `/ledger-synthesize` - Synthesize findings (you are here)
4. `/ledger-decide` - Make explicit decisions
5. `/ledger-spec` - Generate constrained PRD + architecture
6. `/ledger-plan` - Generate implementation plan
