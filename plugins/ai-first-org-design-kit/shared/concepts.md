# AI-First Org Design Kit — Shared Concepts

All skills in this kit share these foundational models. Reference this file when you need definitions.

## The Three-Variable Model

Organizational time is NOT planning vs. execution. It's three variables:

| Variable | Definition | Traditional Allocation |
|----------|-----------|----------------------|
| **Specification** | Defining intent, success criteria, quality standards, judgment boundaries | ~10% |
| **Coordination** | Meetings, approvals, handoffs, alignment, status updates, reviews | ~55% |
| **Execution** | Actually producing artifacts | ~35% |

AI changes each differently: Execution → agents do it. Coordination → gets encoded into infrastructure. Specification → becomes the primary human activity.

**Target AI-first allocation (human time):** 40-50% specification, 15-20% coordination design, 10-15% execution oversight, 15-20% system evolution.

## The Specification Stack

Four layers, each requiring different skills:

| Layer | Question | Test |
|-------|----------|------|
| **L1: Task** | What should this specific output look like? | Can someone with zero context produce acceptable output from this spec? |
| **L2: Workflow** | How should this *class* of tasks be orchestrated? | Does this workflow improve with each iteration without human redesign? |
| **L3: Governance** | What are boundaries for autonomous operation? | Does the system produce a predictable response to novel situations? |
| **L4: Identity** | What makes this org *this* org? | Would two agents produce output that feels like the same organization? |

## The Stranger Test

"Could someone with zero context about this project read this spec and produce output you'd accept?" If no, the spec is insufficient. Apply at every layer.

## The Dual-System Principle

Every organizational structure serves both:
- **Coordination** (moving work forward)
- **Culture** (meaning, identity, belonging)

These have been fused for 150 years because humans required both simultaneously. AI pulls them apart. Encoding coordination without replacing the cultural function creates a vacuum.

**Rule:** Before encoding any structure, classify which function it serves. Encode coordination. Invest in culture. Never strip culture accidentally.

## Work Modes

Not career levels — modes you move between within a single day:

| Mode | Focus | Success Metric |
|------|-------|----------------|
| **Operator** | Producing artifacts | Am I doing work the right way? |
| **Designer** | Creating reusable workflows | Am I solving for a *class* of challenges? |
| **Architect** | Encoding intent and judgment | Am I optimizing for the right future? |

## The Five Resistance Archetypes

| Archetype | Power Source | Reframe To |
|-----------|-------------|------------|
| Approval Gate Holder | Sign-off authority | **Quality Architect** — designs what "good" looks like for automated gates |
| Information Broker | Sole knowledge holder | **Knowledge Encoder** — defines what gets encoded into org data set |
| Execution Expert | Best at doing X | **Specification Authority** — defines the quality bar agents must meet |
| Empire Builder | Headcount/budget | **Leverage Maximizer** — measured by output-per-person × scope |
| Process Owner | Built current system | **Workflow Designer** — translates process knowledge into agent-native specs |

## Organizational Genome Structure

The foundational identity specification. Structure:

```
organizational-genome/
├── 00-identity/
│   ├── MISSION.md           — Why we exist (operational, not marketing)
│   ├── VALUES.md            — Values as decision rules
│   └── VOICE.md             — Communication norms with examples
├── 01-decision-architecture/
│   ├── AUTHORITY-MATRIX.md  — What gets decided by whom/what
│   ├── TRADEOFF-RULES.md    — When values conflict, which wins
│   └── ESCALATION-PROTOCOLS.md — When and how to escalate
├── 02-quality-standards/
│   ├── BY-OUTPUT-TYPE.md    — What "good" looks like per output type
│   └── ANTI-PATTERNS.md     — Explicit examples of what's not acceptable
├── 03-governance/
│   ├── BOUNDARIES.md        — What agents must never do autonomously
│   ├── POLICY-GENERATION.md — How new policies get proposed and approved
│   └── DECISION-LEDGER.md   — How decisions are recorded
└── 04-evolution/
    ├── REVIEW-CYCLE.md      — When and how the genome gets updated
    └── CHANGE-LOG.md        — History of genome modifications
```

## Artifact Handoff Convention

All skills save outputs to `~/.ai-first-kit/projects/{slug}/` for downstream skill discovery. Each skill checks for upstream artifacts before starting.

| Skill | Reads From | Writes To |
|-------|-----------|----------|
| coordination-audit | (nothing) | `audit-{date}.md` |
| org-genome-builder | audit (optional) | `genome/` directory |
| specification-writer | genome (optional) | `specs/{name}.md` |
| quality-gate-designer | audit, genome | `gates/{name}.md` |
| governance-architect | genome | `governance/` directory |
| role-value-mapper | audit, genome | `roles-{date}.md` |
| political-navigator | audit (optional) | `political-map-{date}.md` |
