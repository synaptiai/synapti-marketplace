# AI-First Org Design Kit

> **Version:** 1.4.0 | **License:** MIT | **Category:** Organizational Design

Thirteen opinionated skills that guide founders and leaders through designing, deploying, adopting, and evolving organizations where agents handle coordination and execution while humans own specification and judgment.

**This is not about adopting AI tools.** It's about re-engineering the operating model.

## The Thesis

Every organizational structure you work within is a fossil — a response to human constraints (scarce expertise, finite attention, expensive execution) that no longer exist. AI collapsed the cost of execution. The structures remain.

Organizations are specification machines that pretended to be execution machines. The value was always in defining *what should exist and what "good" looks like*. AI just proved it.

## Who This Is For

- **Founders** building AI-first from scratch (greenfield)
- **Leaders** transitioning existing organizations (brownfield)
- **CPOs/CTOs** designing agentic infrastructure with governance
- **Anyone** asking "if agents do the execution, what do humans do?"

## The Process

Skills run in sequence. Each feeds into the next.

```
Diagnose → Encode Identity → Specify → Design Gates → Architect Governance → Map Roles → Navigate Politics → Operationalize → Measure Adoption → Sprint → Deploy Agents → Evolve
```

### Greenfield Path (Founders)
```
org-genome-builder → specification-writer → governance-architect → quality-gate-designer → role-value-mapper → operationalize → [optional] maturity-ladder → adoption-sprint-designer → agent-builder → [ongoing] evolution-auditor
```

### Brownfield Path (Leaders)
```
coordination-audit → political-navigator → org-genome-builder → quality-gate-designer → specification-writer → role-value-mapper → governance-architect → operationalize → [optional] maturity-ladder → adoption-sprint-designer → usage-policy-writer → agent-builder → [ongoing] evolution-auditor
```

### Already Deployed Path
```
evolution-auditor → (revision skills based on findings) → operationalize → agent-builder
```

### Driving Adoption Path
```
maturity-ladder → adoption-sprint-designer → usage-policy-writer → [ongoing] evolution-auditor
```

### Quick Start
If building only two skills first: `coordination-audit` + `org-genome-builder`.

## The Skills

All skills live under `skills/` and follow the standard plugin SKILL.md format.

| Skill | Your Specialist | What They Do |
|-------|----------------|-------------|
| `skills/coordination-audit` | **Organizational Diagnostician** | Makes the invisible visible: where time actually goes, what's coordination vs. culture, highest-ROI encoding targets |
| `skills/org-genome-builder` | **Org Psychologist + Systems Architect** | Builds the organizational genome — values as decision rules, quality standards, communication norms, decision architecture |
| `skills/specification-writer` | **Specification Engineer** | Creates specs at any layer (task/workflow/governance/identity) precise enough for autonomous agent execution |
| `skills/quality-gate-designer` | **Validation Architect** | Converts approval chains into criteria-based quality gates with holdout-scenario validation |
| `skills/governance-architect` | **Governance Systems Designer** | Designs the full governance ecosystem — boundaries, escalation, policy generation, decision ledger, learning loops |
| `skills/role-value-mapper` | **Team Architect** | Designs roles from value flows and specification responsibility, not job titles |
| `skills/political-navigator` | **Power Dynamics Strategist** | Maps power structures, identifies resistance, creates reframes, sequences change |
| `skills/operationalize` | **Operational Bridge** | Distills all design artifacts into an agent-consumable primer (AGENT-PRIMER.md) and optionally merges governance into project CLAUDE.md |
| `skills/evolution-auditor` | **Organizational Fitness Auditor** | Runs the learning loop post-deployment: gate effectiveness, genome fitness, authority calibration, decision ledger |
| `skills/agent-builder` | **Agent Configuration Engineer** | Generates role-specific agent system prompts, tool permissions, and framework configs from organizational design artifacts |
| `skills/maturity-ladder` | **Adoption Diagnostician** | Builds per-role AI maturity matrix with observable behaviors, current assessment, and visibility infrastructure |
| `skills/adoption-sprint-designer` | **Sprint Architect** | Designs structured adoption sprints with objectives, buddy pairing, demo format, and activity-based measurement |
| `skills/usage-policy-writer` | **AI Policy Architect** | Generates human-facing AI usage policy with approved tools, data classification, risk model reasoning, and exceptions |

The router skill (`skills/ai-first-kit`) is the entry point — it diagnoses the user's situation and routes to the appropriate skill.

## Core Concepts

All skills share a foundational vocabulary (see `shared/concepts.md`):

- **Three-Variable Model** — Organizational time is specification + coordination + execution (not planning vs. execution)
- **Specification Stack** — Four layers: Task → Workflow → Governance → Identity
- **The Stranger Test** — "Could someone with zero context produce acceptable output from this spec?"
- **Dual-System Principle** — Every structure serves coordination AND culture. Encode one, invest in the other.
- **Five Resistance Archetypes** — Gate Holder, Information Broker, Execution Expert, Empire Builder, Process Owner

## Artifact Handoff

Skills save outputs to `$HOME/.ai-first-kit/projects/{slug}/` (chmod 700) and automatically discover upstream artifacts. The slug is derived from the git repo root name for cross-project isolation. The coordination audit feeds into four other skills. The genome is referenced by everything downstream.

## Installation

### Via Synapti Marketplace (recommended)
```bash
git clone https://github.com/synaptiai/synapti-marketplace.git
claude plugin install ./synapti-marketplace/plugins/ai-first-org-design-kit
```

### Project-level
```bash
cp -Rf path/to/synapti-marketplace/plugins/ai-first-org-design-kit .claude/plugins/ai-first-org-design-kit
```

## Post-Deployment

Once operational, two additional skills maintain and extend the design:

- **`evolution-auditor`** — Monthly health check that runs the governance learning loop. Measures gate effectiveness, checks genome fitness against real decisions, calibrates the authority matrix, maintains the decision ledger, and routes findings to existing skills for revision.
- **`agent-builder`** — Generates role-specific agent configurations from your organizational design artifacts. Produces system prompts, tool permissions, and self-review checklists. Supports Claude Code, OpenAI Agents SDK, Anthropic Agent SDK, CrewAI, and custom frameworks.

## Adoption

Three skills address the human side of AI adoption:

- **`maturity-ladder`** — Builds a per-role capability ladder with 4 levels (Not Engaged → Capable → Adoptive → Transformative). Measures actual behavior, not self-assessment. Creates visible progression paths that motivate through social proof.
- **`adoption-sprint-designer`** — Designs structured 2-3 day sprints (hackathons) that force hands-on AI usage. Includes buddy pairing, demo format, activity-based measurement, and leadership sequencing. One sprint converts more than months of presentations.
- **`usage-policy-writer`** — Generates a human-facing AI usage policy explaining what tools are approved, data classification, and the reasoning behind each decision. Addresses the "I don't know what I'm allowed to do" barrier that kills adoption.

## Claude Code Integration

The `operationalize` and `agent-builder` skills can generate Claude Code-native primitives:

- **CLAUDE.md @imports** — Import genome foundation (MISSION, VALUES, HARD-BOUNDARIES) directly into your project's CLAUDE.md. Always in context, auto-updates when source files change.
- **Governance skills** — Five `/org-*` commands generated in `.claude/skills/`: record decisions, handle novel situations, check voice, review gates, evaluate values.
- **Sub-agents** — Register configured agents as Claude Code sub-agents in `.claude/agents/`. Invokable via `@agent-name`. Preload governance skills for immediate availability.

Skills are dynamic (read source files at invocation — auto-update). Agents are static (inlined prompts — need regeneration via `agent-builder` when upstream changes). The `evolution-auditor` detects stale agents.

## What This Kit Does NOT Cover

- **Tool selection.** Which LLM, which agent framework. Tools are endpoints.
- **Technical architecture.** The kit bridges to agent consumption, not infrastructure.
- **Legal/compliance.** The governance skill helps design governance, not legal advice.
- **Culture building.** The kit identifies where culture needs design. What your culture should be is your job.

## License

MIT. Build something.
