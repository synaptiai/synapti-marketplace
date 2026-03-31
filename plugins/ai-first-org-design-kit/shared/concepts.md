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

**Target AI-first allocation (human time only — agent work is separate):**

| Activity | % of Human Time | What It Means |
|----------|----------------|---------------|
| Specification | 40-50% | Defining what should exist and what "good" looks like |
| Coordination design | 15-20% | Designing the infrastructure that replaces meetings/approvals |
| Execution oversight | 10-15% | Monitoring agent output, handling edge cases |
| System evolution | 15-20% | Updating genome, governance, and specs as the org learns |

These ranges overlap intentionally — allocation varies by org maturity. Early AI-first orgs skew toward specification; mature ones shift toward evolution. The `evolution-auditor` skill operationalizes this "system evolution" time allocation. Recommended cadence: monthly.

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

## AI Adoption Maturity Model

Four levels of AI adoption, measured by observable behavior (not self-report):

| Level | Name | Behavioral Test | Identity Frame |
|-------|------|-----------------|----------------|
| 0 | Not Engaged | No AI-assisted work tasks in the past 30 days | "I do my job without AI" |
| 1 | Capable | Uses AI for 3+ distinct tasks/week, reviews all output, follows usage policy | "AI is a useful tool" |
| 2 | Adoptive | Has designed at least 1 reusable AI workflow, delegates execution to AI by default | "I specify, AI executes" |
| 3 | Transformative | Has built or extended an AI tool/skill/workflow that others now use | "I create new capabilities" |

**Key design principle:** Level 3 is "invents new tools" not "uses AI the most." The identity shifts from "I don't need AI" to "I'm the one who creates new capabilities." This is an upgrade, not a replacement.

The `maturity-ladder` skill produces per-role customizations of this model with organization-specific behaviors per cell. The `adoption-sprint-designer` designs structured experiences that move people between levels. The `evolution-auditor` tracks level changes over time.

## The Five Resistance Archetypes

| Archetype | Power Source | Reframe To |
|-----------|-------------|------------|
| Approval Gate Holder | Sign-off authority | **Quality Architect** — designs what "good" looks like for automated gates |
| Information Broker | Sole knowledge holder | **Knowledge Encoder** — defines what gets encoded into org data set |
| Execution Expert | Best at doing X | **Specification Authority** — defines the quality bar agents must meet |
| Empire Builder | Headcount/budget | **Leverage Maximizer** — measured by output-per-person × scope |
| Process Owner | Built current system | **Workflow Designer** — translates process knowledge into agent-native specs |

## Governance Health Metrics

Track these to assess whether the governance system is healthy. The `evolution-auditor` skill computes these during each audit cycle.

| Metric | Healthy Range | Too Low Means | Too High Means |
|--------|-------------|---------------|----------------|
| Escalation rate | 5-15% of decisions | Agents may be overstepping authority | Governance too restrictive |
| First-pass gate approval | >80% | Agents not self-reviewing effectively | Gates may be too lenient |
| Policy generation rate | Decreasing over time | System stabilized (good) OR agents avoiding novel situations (bad) | Governance has gaps |
| Novel situation frequency | Decreasing over time | Coverage expanding (good) | Agents encountering unfamiliar territory |

## Organizational Genome Structure

The foundational identity specification. Built in two phases:

**Phase 1 — Created by `org-genome-builder`:**
```
genome/
├── 00-identity/
│   ├── MISSION.md           — Why we exist (operational, not marketing)
│   ├── VALUES.md            — Values as decision rules
│   └── VOICE.md             — Communication norms with examples
├── 01-decision-architecture/
│   ├── AUTHORITY-MATRIX.md  — What gets decided by whom/what
│   └── TRADEOFF-RULES.md    — When values conflict, which wins
└── 02-quality-standards/
    ├── BY-OUTPUT-TYPE.md    — What "good" looks like per output type
    └── ANTI-PATTERNS.md     — Explicit examples of what's not acceptable
```

**Phase 2 — Created by `governance-architect`:**
```
governance/
├── AUTHORITY-MATRIX.md       — Extended decision authority (4-tier)
├── HARD-BOUNDARIES.md        — What agents must never do autonomously
├── ESCALATION-PROTOCOLS.md   — When and how to escalate
├── POLICY-GENERATION.md      — How new policies get proposed and approved
├── DECISION-LEDGER-SPEC.md   — How decisions are recorded
└── LEARNING-LOOP.md          — How governance evolves from failures
```

The genome (Phase 1) encodes identity. Governance (Phase 2) encodes operational boundaries. Together they form the complete organizational specification.

## Artifact Handoff Convention

All skills save outputs to `$HOME/.ai-first-kit/projects/{slug}/` for downstream skill discovery. Each skill checks for upstream artifacts before starting and **reads their content** to maintain consistency.

**Slug derivation:** The project slug is derived from the git repository root directory name (via `git rev-parse --show-toplevel`), not the current working directory leaf. This prevents cross-repo collisions when different repos happen to share a directory name. Falls back to `${PWD##*/}` in non-git contexts.

**Security:** The `$HOME/.ai-first-kit/` directory is created with `chmod 700` on first use. Skills save sensitive organizational data (approval chains, political maps, stakeholder analysis) that should not be world-readable.

**Date format:** All date-stamped filenames use `YYYY-MM-DD-HHMM` (includes hours and minutes) to prevent same-day overwrites from multiple runs.

| Skill | Reads From | Writes To | Blocks Without |
|-------|-----------|----------|----------------|
| coordination-audit | (nothing) | `audit-{datetime}.md` | — |
| org-genome-builder | audit (optional) | `genome/` directory (3 subdirs) | — |
| specification-writer | genome VALUES.md, BY-OUTPUT-TYPE.md | `specs/{name}-{datetime}.md` | — |
| quality-gate-designer | audit, genome | `gates/{name}.md` + `gates/.holdouts/` | — |
| governance-architect | genome VALUES.md | `governance/` directory | genome (recommended) |
| role-value-mapper | audit, genome | `roles-{datetime}.md` | — |
| political-navigator | audit (optional) | `political-map-{datetime}.md` | — |
| operationalize | genome/ (required), governance/, gates/, specs/ | `AGENT-PRIMER.md`, `ORG-DESIGN-DUMP-{datetime}.md`, optionally `.claude/CLAUDE.md` | genome (required) |
| evolution-auditor | genome/ (req), governance/ (req), gates/ incl. .holdouts/ (for evaluation), specs/, roles-*.md, AGENT-PRIMER.md, previous evolution audits, evolution/decision-ledger.md | `evolution/audit-{datetime}.md`, `evolution/decision-ledger.md` (append-only) | genome + governance (both required) |
| agent-builder | roles-*.md (req), genome/ (req), governance/, gates/, specs/, AGENT-PRIMER.md | `agents/{role-slug}/` directory, `agents/INDEX.md` | roles + genome (both required) |
| maturity-ladder | roles-*.md (optional), genome (optional), audit-*.md (coordination audit, optional), previous maturity assessments | `adoption/maturity-ladder-{datetime}.md`, `adoption/maturity-visibility.md` | — |
| adoption-sprint-designer | adoption/maturity-ladder (optional), roles-*.md (optional), genome (optional), governance/HUMAN-USAGE-POLICY.md (optional), previous sprint plans | `adoption/sprint-{name}-{datetime}.md`, `adoption/sprint-measurement.md` | — |
| usage-policy-writer | governance/HARD-BOUNDARIES.md (optional), genome VALUES.md (optional), genome VOICE.md (optional), existing HUMAN-USAGE-POLICY.md (update detection) | `governance/HUMAN-USAGE-POLICY.md` | — |

**Note:** `adoption-sprint-designer` checks for `political-map-*.md` existence (count only via `find | wc -l`) but NEVER reads content. This is not a "read" dependency — it's an existence check that triggers a security note in pre-flight output.

## Skill Dependency Map

```
coordination-audit ──────────────────────┐
       │ (optional)                      │ (optional)
       ▼                                 ▼
org-genome-builder ─────────┬──── political-navigator
       │ (required by some) │
       ├────────────────────┤
       ▼                    ▼
specification-writer  governance-architect ──► usage-policy-writer
       │                    │                  (human-facing policy)
       ▼                    │                        │ (optional)
quality-gate-designer ◄─────┘                        │
       │                                             │
       ▼                                             │
role-value-mapper                                    │
       │                                             │
       ├──────────────────────────────┐              │
       ▼                              ▼              │
operationalize              maturity-ladder (optional)
       │                              │              │
       ├────────────────────┐         ▼              │
       ▼                    ▼   adoption-sprint-designer ◄───┘
evolution-auditor     agent-builder
(post-deployment)     (agent configs)
       │
       └──► routes to upstream skills for revision
```

Skills marked "optional" degrade gracefully without upstream artifacts. Skills marked "recommended" warn and offer alternatives if the dependency is missing. The map shows what's structurally possible; the Greenfield, Brownfield, and Adoption paths in the README show the recommended order.

The `operationalize` skill distills all produced artifacts into an agent-consumable primer (AGENT-PRIMER.md). It gracefully handles partial completion (only genome required).

Post-deployment, five additional skills extend the lifecycle: `evolution-auditor` runs the learning loop and decision ledger, `agent-builder` generates role-specific agent configurations, `maturity-ladder` assesses adoption levels per role, `adoption-sprint-designer` creates structured adoption experiences, and `usage-policy-writer` produces human-facing AI usage policies. The adoption skills have soft dependencies — they benefit from upstream artifacts but can run standalone. The `evolution-auditor` tracks adoption maturity trends when maturity data exists.
