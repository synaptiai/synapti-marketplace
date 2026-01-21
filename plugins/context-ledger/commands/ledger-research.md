---
description: Launch parallel evidence collection across all active research pillars
argument-hint: "[--pillar <name>] [--depth <quick|standard|deep>]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, WebSearch, WebFetch, AskUserQuestion
---

# Research Evidence

Launch parallel evidence collection agents for all active pillars.

> **Parallel Execution**: This command spawns up to 8 `pillar-researcher` agents in parallel, one for each active pillar. Evidence collection happens concurrently for maximum efficiency.

## Arguments

`$ARGUMENTS`: Optional pillar filter or research focus.

**Optional flags:**
- `--pillars <list>` - Only research specific pillars (comma-separated)
- `--focus <topic>` - Prioritize specific research topic across pillars
- `--min <n>` - Override minimum evidence per pillar (default: 5)

## Prerequisites

- Ledger workspace initialized (`/ledger-init` completed)
- `00-brief/BRIEF.md` exists
- `01-pillars/PILLARS.md` exists

## Workflow

1. **Read Configuration**
   - Load brief from `00-brief/BRIEF.md`
   - Load pillar priorities from `01-pillars/PILLARS.md`
   - Identify active pillars

2. **Spawn Research Agents**
   - Launch `pillar-researcher` agent for each active pillar
   - Pass pillar scope and project context
   - Agents run in parallel

3. **Monitor Progress**
   - Track evidence creation per pillar
   - Report gate status (minimum 5 per pillar)

4. **Aggregate Results**
   - Collect summary from each agent
   - Report total evidence objects
   - Identify gaps and contradictions

## Example Usage

### Research all pillars
```
/ledger-research
```

### Research specific pillars only
```
/ledger-research --pillars market,users,competitors
```

### Research with specific focus
```
/ledger-research --focus pricing
```

### Override minimum threshold
```
/ledger-research --min 3
```

## Output

```markdown
## Research Complete

**Total Evidence Objects:** 47
**Pillars Researched:** 8
**Gate Status:** ALL PASSED ✓

### Per-Pillar Summary
| Pillar | Objects | Gate | Key Finding |
|--------|---------|------|-------------|
| market | 7 | ✓ | TAM is $X billion |
| users | 6 | ✓ | 78% drop off at invitation |
| tech | 5 | ✓ | LLM costs $0.03/1K tokens |
| competitors | 6 | ✓ | 3 direct competitors |
| design | 5 | ✓ | WCAG 2.1 AA required |
| legal | 5 | ✓ | GDPR processing needed |
| ops | 5 | ✓ | 99.9% SLA expected |
| economics | 8 | ✓ | 70% gross margin target |

### Cross-Pillar Contradictions
- EV-market-pricing-smb-wtp (SMB WTP $29) vs EV-economics-pricing-premium ($49 target)

### Research Gaps
- User churn reasons need more depth
- Competitor roadmap intelligence limited

### Next Step
Run `/ledger-synthesize` to process evidence into insights.
```

## Pillar Research Agents

Each pillar gets a dedicated `pillar-researcher` agent with:

| Pillar | Research Focus |
|--------|----------------|
| market | Market size, pricing, trends |
| users | Personas, pain points, workflows |
| tech | Feasibility, constraints, options |
| competitors | Landscape, features, positioning |
| design | UX patterns, accessibility |
| legal | Compliance, regulations, risk |
| ops | Operations, support, infrastructure |
| economics | Unit economics, costs, revenue |

## User Interaction

Use the **AskUserQuestion tool** when:

### Pillar prioritization needed
```
User: /ledger-research
→ If brief doesn't clearly prioritize pillars:
  Question: "Which pillars should I research first?"
  Options:
  - "Market + Users (validate demand)" (Recommended)
  - "Tech + Competitors (validate feasibility)"
  - "All equally important"
  - "Let me specify"
```

### Research focus requested
```
User: /ledger-research --focus pricing
→ Confirm scope:
  Question: "Research pricing across which pillars?"
  Options:
  - "Market (WTP, benchmarks) + Economics (unit economics)"
  - "Market + Competitors (competitive pricing)"
  - "All pillars that touch pricing"
```

### Gate failure risk
```
After initial research:
→ If pillar has <3 evidence objects:
  Question: "[Pillar] only has [N] evidence. How to proceed?"
  Options:
  - "Continue researching this pillar"
  - "Accept partial evidence"
  - "Skip this pillar (mark inactive)"
```

### Contradictions discovered
```
After research completes:
→ If significant contradictions:
  Question: "Found contradictions between [EV-X] and [EV-Y]. How to handle?"
  Options:
  - "Note for synthesis to resolve"
  - "Research deeper to resolve now"
  - "Flag as critical uncertainty"
```

## Evidence Gates

Each pillar must meet minimum evidence threshold:

| Gate Status | Condition |
|-------------|-----------|
| ✓ PASSED | ≥5 evidence objects |
| ⚠ WARNING | 3-4 evidence objects |
| ✗ FAILED | <3 evidence objects |

Synthesis will proceed with warnings but note gaps. Failed gates require resolution.

## After Research

Once research completes, the typical workflow continues:

1. `/ledger-init` - Initialize (completed)
2. `/ledger-research` - Collect evidence (you are here)
3. `/ledger-synthesize` - Synthesize findings
4. `/ledger-decide` - Make explicit decisions
5. `/ledger-spec` - Generate constrained PRD + architecture
6. `/ledger-plan` - Generate implementation plan
