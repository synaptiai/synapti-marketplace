---
description: Run the complete Context Ledger pipeline from brief to plan in one command
argument-hint: "<brief>" --mode <optimizer|tokenburner|ralph> [--self-improve] [--max-iterations N] [--completion-promise TEXT]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, WebSearch, WebFetch, AskUserQuestion
---

# Full Pipeline Execution

Run the complete Context Ledger pipeline end-to-end with a single command.

## The 5-Sentence Superprompt

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

### Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--mode <mode>` | Execution mode: `optimizer`, `tokenburner`, or `ralph` | Required |
| `--self-improve` | Enable gap analysis loops within the pipeline | Off |
| `--max-iterations <n>` | Safety limit (required for `ralph` mode) | 50 |
| `--completion-promise <text>` | Completion signal for `ralph` mode | `LEDGER_COMPLETE` |
| `--path <path>` | Workspace location | `./ledger/` |
| `--pillars <list>` | Limit to specific pillars (comma-separated) | All 8 |

## Execution Modes

### `--mode optimizer`

**Sustainable execution.** Balances thoroughness with resource efficiency.

| Phase | Parallelism | Description |
|-------|-------------|-------------|
| Research | 3 agents per pillar | 24 parallel researchers total |
| Synthesis | 3 pillar synthesizers | Sequential cross-synthesis |
| Specs | 1 spec-architect | Constrained generation |

```bash
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

```bash
/ledger-full "Enterprise SaaS platform" --mode tokenburner
```

**Best for:** Hackathons, time-critical projects, exploration.

### `--mode ralph`

**Fully autonomous execution** using Ralph Loop's stop hook mechanism.

| Phase | Behavior | Description |
|-------|----------|-------------|
| All | Stop hook iteration | Same prompt re-fed on each exit |
| Completion | Promise-based | Output `<promise>LEDGER_COMPLETE</promise>` when done |
| Persistence | File-based | Previous work visible in files/git history |

```bash
/ledger-full "Healthcare patient portal with HIPAA compliance" --mode ralph --max-iterations 50
```

**Best for:** Walk-away overnight runs, complex autonomous projects.

## The `--self-improve` Flag

Can be combined with **any mode** to enable within-pipeline gap analysis loops:

- Analyzes research for missing evidence
- Checks synthesis for unresolved contradictions
- Validates spec constraint coverage
- Loops back to appropriate phase when gaps found

```bash
# Optimizer with self-improvement
/ledger-full "Task management app" --mode optimizer --self-improve

# Tokenburner with self-improvement
/ledger-full "AI assistant" --mode tokenburner --self-improve

# Ralph with self-improvement (maximum autonomy)
/ledger-full "Complex fintech app" --mode ralph --self-improve --max-iterations 100
```

## Ralph Mode Details

### How It Works

1. Creates state file at `.claude/ralph-loop.local.md`
2. Runs the full pipeline with the specified parallelism
3. On exit attempt, stop hook intercepts
4. Same prompt re-fed with incremented iteration counter
5. Claude sees previous work in modified files and git history
6. Loops until `<promise>LEDGER_COMPLETE</promise>` output or max iterations reached

### Completion Criteria

Output `<promise>LEDGER_COMPLETE</promise>` **ONLY** when:
- All evidence gates passed (≥5 per pillar)
- All decision gates passed (≥2 evidence per decision)
- All spec gates passed (all sections cite decisions)
- PLAN.md generated successfully

**CRITICAL:** Do not output the completion promise until the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

### Monitoring

```bash
# Check current iteration
grep '^iteration:' .claude/ralph-loop.local.md

# View full state
head -10 .claude/ralph-loop.local.md

# Cancel active loop
/cancel-ralph
```

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
→ If --self-improve: analyze gaps and loop if needed
```

### Phase 3: Synthesize (Layered)
```
→ Per-pillar synthesis: patterns, contradictions, insights
→ Cross-pillar synthesis: connections, conflicts, emergent insights
→ Output: SYN-*.md files + CROSS-SYNTHESIS.md
→ Generate decision candidates
→ If --self-improve: check for unresolved contradictions
```

### Phase 4: Decide
```
→ Present each decision with evidence and trade-offs
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
→ If --self-improve: validate all constraints met
```

### Phase 6: Plan
```
→ Extract work items from specs
→ Link to decisions and risks
→ Create milestones and test plan
→ Output: PLAN.md
```

### Ralph Mode Completion
```
→ Verify all gates passed
→ Output: <promise>LEDGER_COMPLETE</promise>
→ Stop hook allows exit
```

## User Interaction

Use the **AskUserQuestion tool** ONLY for:

### 1. Mode Selection (if not provided in arguments)
```
Question: "Which execution mode?"
Options:
- "optimizer - 3 agents/pillar, sustainable"
- "tokenburner - 30+ agents/pillar, maximum speed"
- "ralph - stop hook loops, fully autonomous"
```

### 2. Ralph Mode Settings (if ralph selected without flags)
```
Question: "Ralph mode settings:"
Options:
- "Default (max 50 iterations, promise: LEDGER_COMPLETE)"
- "Conservative (max 20 iterations)"
- "Aggressive (max 100 iterations)"
- "Let me specify custom settings"
```

### 3. Decision Phase Only
During the decide phase, present decisions with evidence for user choice.
This is the **only interactive part** of the pipeline execution.

**Do NOT use AskUserQuestion for:**
- "Ready to run?" confirmations
- Gate failure handling (auto-continue or flag-based)
- Self-improve loop continuations
- Progress updates

## Example Usage

```bash
# Standard overnight run
/ledger-full "Task management app for remote teams" --mode optimizer

# With self-improvement loops
/ledger-full "Task management app" --mode optimizer --self-improve

# Maximum speed hackathon
/ledger-full "AI code review assistant" --mode tokenburner

# Fully autonomous (walk away overnight)
/ledger-full "Healthcare portal with HIPAA" --mode ralph --max-iterations 50

# Ralph + self-improve (maximum autonomy)
/ledger-full "Complex fintech app" --mode ralph --self-improve --max-iterations 100

# Focused research (specific pillars only)
/ledger-full "Pricing strategy" --mode optimizer --pillars market,competitors,economics

# Custom completion promise
/ledger-full "Fintech app" --mode ralph --completion-promise "ALL_GATES_PASSED" --max-iterations 75
```

## Mode Selection Guide

| Scenario | Recommended |
|----------|-------------|
| Standard project | `--mode optimizer` |
| Hackathon / rapid prototyping | `--mode tokenburner` |
| Walk-away overnight run | `--mode ralph --max-iterations 50` |
| Complex regulated project | `--mode ralph --self-improve --max-iterations 100` |
| Quick idea validation | `--mode tokenburner` |
| High-stakes production planning | `--mode optimizer --self-improve` |

## Output

After pipeline completion:

```markdown
## Context Ledger Pipeline Complete

### Execution Summary
- **Mode:** optimizer
- **Self-improve:** enabled
- **Iterations:** 3 (ralph mode only)

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
```

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
