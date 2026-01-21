---
description: Run the complete Context Ledger pipeline from brief to plan in one command
argument-hint: "<brief>" --mode <optimizer|tokenburner|self-improver> [--max-iterations N]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, WebSearch, WebFetch, AskUserQuestion
---

# Full Pipeline Execution

Run the complete Context Ledger pipeline end-to-end with a single command.

## The 5-Sentence Superprompt

This is what you're executing:

> **Build the Vault first.** Research every pillar this project depends on (market, users, tech, competitors, design, legal, ops, economics) in parallel, dumping evidence with confidence scores and assumptions into structured YAML files.
>
> **Synthesize before you spec.** Transform raw evidence into pillar syntheses, then cross-synthesize to resolve conflicts into a single coherent strategy with explicit decisions and documented trade-offs.
>
> **Constrain everything.** Generate PRD, architecture, and backlog where every section must cite a `DEC-*` decision — if you can't trace it to evidence, it doesn't go in.
>
> **Loop until done.** When you find gaps, research more. When evidence conflicts, decide explicitly. When specs drift from decisions, regenerate.
>
> **Ship with receipts.** Every claim traceable to evidence, every requirement traceable to a decision, every decision traceable to trade-offs considered.

## Arguments

`$ARGUMENTS`: The project brief — a text description of what you're building.

**Required:**
- `--mode <mode>` - Execution mode (see modes below)

**Optional:**
- `--max-iterations <n>` - Safety limit for self-improver mode (default: 10)
- `--path <path>` - Custom workspace location (default: `./ledger/`)
- `--pillars <list>` - Limit to specific pillars (comma-separated)

## Execution Modes

### `--mode optimizer` (Recommended for most use cases)

**Sustainable overnight execution.** Balances thoroughness with resource efficiency.

| Phase | Parallelism | Description |
|-------|-------------|-------------|
| Research | 3 agents per pillar | 24 parallel researchers total |
| Synthesis | 3 pillar synthesizers | Sequential cross-synthesis |
| Specs | 1 spec-architect | Constrained generation |

```
/ledger-full "Build a task management app for remote teams" --mode optimizer
```

**Best for:** Standard projects, overnight runs, production use.

### `--mode tokenburner`

**Maximum parallelism.** Burns through tokens fast for rapid iteration.

| Phase | Parallelism | Description |
|-------|-------------|-------------|
| Research | 30+ agents per pillar | 240+ parallel researchers |
| Synthesis | 8 pillar synthesizers | Parallel cross-synthesis |
| Specs | 3 spec-architects | Parallel PRD + Arch + Plan |

```
/ledger-full "Enterprise SaaS platform" --mode tokenburner
```

**Best for:** Hackathons, time-critical projects, exploration.

### `--mode self-improver`

**Iterative refinement.** Analyzes gaps and loops until complete.

| Phase | Behavior | Description |
|-------|----------|-------------|
| Research | Gap detection | Finds missing evidence, researches more |
| Synthesis | Conflict resolution | Iterates until contradictions resolved |
| Specs | Constraint validation | Loops until all sections cite decisions |

```
/ledger-full "Complex regulated fintech app" --mode self-improver --max-iterations 15
```

**Best for:** Complex domains, regulated industries, high-stakes projects.

## Workflow

### Phase 1: Initialize
```
→ Parse brief into structured components
→ Create ledger workspace structure
→ Generate BRIEF.md and PILLARS.md with priorities
```

### Phase 2: Research (Parallel)
```
→ Spawn pillar-researcher agents based on mode parallelism
→ Each researcher collects ≥5 evidence objects with:
  - Semantic IDs (EV-<pillar>-<topic>-<descriptor>)
  - Confidence scores (0.0-1.0)
  - Explicit assumptions
  - Source traceability
→ Check evidence gate (minimum 5 per pillar)
```

### Phase 3: Synthesize (Layered)
```
→ Per-pillar synthesis: patterns, contradictions, insights
→ Cross-pillar synthesis: connections, conflicts, emergent insights
→ Output: SYN-*.md files + CROSS-SYNTHESIS.md
→ Generate decision candidates
```

### Phase 4: Decide (Interactive)
```
→ Present each decision with evidence and trade-offs
→ Get user decision via AskUserQuestion
→ Record to DECISIONS.yaml with:
  - Alternatives considered
  - Wins and loses
  - Created risks
→ Generate RISKS.yaml with mitigations
```

### Phase 5: Spec (Constrained)
```
→ Generate PRD.md — every section cites DEC-*
→ Generate ARCHITECTURE.md — every choice cites DEC-*
→ Validate constraint gates
→ Cross-reference RISK-* entries
```

### Phase 6: Plan
```
→ Extract work items from specs
→ Link to decisions and risks
→ Create milestones and test plan
→ Output: PLAN.md
```

### Self-Improver Loop (if enabled)
```
→ Analyze evidence for gaps
→ Check synthesis for unresolved contradictions
→ Validate spec constraint coverage
→ If gaps found: loop back to appropriate phase
→ Continue until complete or max iterations reached
```

## Example Usage

### Standard project (overnight run)
```
/ledger-full "Build a documentation tool for developer teams. Target: small teams (5-50). Must ship MVP in 6 weeks. Web-only, no mobile. Key goal: reduce documentation time by 30%." --mode optimizer
```

### Rapid exploration (hackathon)
```
/ledger-full "AI-powered code review assistant for GitHub PRs" --mode tokenburner
```

### Complex regulated project
```
/ledger-full "Healthcare patient portal with HIPAA compliance, insurance integration, and telehealth scheduling" --mode self-improver --max-iterations 20
```

### Focused research (specific pillars only)
```
/ledger-full "Competitive pricing strategy for B2B SaaS" --mode optimizer --pillars market,competitors,economics
```

## Output

After full pipeline completion:

```markdown
## Context Ledger Pipeline Complete

### Execution Summary
- **Mode:** optimizer
- **Duration:** [time]
- **Iterations:** [n] (self-improver only)

### Artifacts Generated
| Directory | Files | Description |
|-----------|-------|-------------|
| 00-brief/ | 1 | BRIEF.md |
| 01-pillars/ | 1 | PILLARS.md |
| 02-evidence/ | 47 | EV-*.yaml across 8 pillars |
| 03-synthesis/ | 9 | SYN-*.md + CROSS-SYNTHESIS.md |
| 04-decisions/ | 1 | DECISIONS.yaml (12 decisions) |
| 05-risks/ | 1 | RISKS.yaml (8 risks) |
| 06-prd/ | 1 | PRD.md |
| 07-architecture/ | 1 | ARCHITECTURE.md |
| 08-plan/ | 1 | PLAN.md |

### Quality Gates
- Evidence gate: ✓ PASSED (all pillars ≥5)
- Decision gate: ✓ PASSED (all decisions ≥2 evidence)
- Spec gate: ✓ PASSED (all sections cite decisions)

### Traceability
All specs trace to decisions → all decisions trace to evidence.
Your product plan has receipts.

### Next Steps
1. Review DECISIONS.yaml for any provisional decisions
2. Check RISKS.yaml mitigations
3. Begin implementation from PLAN.md backlog
```

## User Interaction

Use the **AskUserQuestion tool** at key checkpoints:

### Before starting
```
Question: "Ready to run full Context Ledger pipeline in [mode] mode?"
Options:
- "Yes, run full pipeline" (Recommended)
- "Let me provide more context first"
- "Change execution mode"
```

### Gate failures
```
Question: "[Pillar] has only [N] evidence (need 5). How to proceed?"
Options:
- "Continue researching this pillar"
- "Accept partial and proceed"
- "Deactivate this pillar"
```

### Decision points
```
Question: "Decision needed: [topic]. Evidence suggests [options]."
Options:
- "[Option A] - supported by [evidence summary]"
- "[Option B] - supported by [evidence summary]"
- "Need more information"
```

### Self-improver loop
```
Question: "Iteration [N]: Found [gaps]. Continue refining?"
Options:
- "Yes, continue loop"
- "Accept current state"
- "Focus on specific gaps"
```

## Integration with Ralph Loop

For extended autonomous execution, combine with Ralph Loop:

```bash
# Run with Ralph-style iteration
/ralph-loop "/ledger-full 'Your project brief' --mode self-improver" --max-iterations 50 --completion-promise "LEDGER_COMPLETE"
```

The self-improver mode will iterate internally, while Ralph Loop provides session-level persistence for overnight runs.

## Mode Selection Guide

| Scenario | Recommended Mode |
|----------|------------------|
| Standard project | `optimizer` |
| Hackathon / rapid prototyping | `tokenburner` |
| Regulated industry (healthcare, finance) | `self-improver` |
| Overnight autonomous run | `optimizer` + Ralph Loop |
| Complex multi-stakeholder project | `self-improver` |
| Quick validation of idea | `tokenburner` |

## Quality Standards

**The pipeline enforces:**
- Every evidence object has a confidence score and assumptions
- Every decision documents alternatives and trade-offs
- Every spec section cites at least one decision
- Every risk has documented mitigations
- All artifacts use semantic IDs for traceability

**You cannot skip:**
- Evidence gates (minimum 5 per pillar)
- Decision gates (minimum 2 evidence per decision)
- Spec constraint gates (all sections cite decisions)
