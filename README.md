# Synapti Plugin Marketplace

> Agentic harnesses for Claude Code — specialized AI agents for complex analytical tasks

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://claude.com/claude-code)
[![Plugins](https://img.shields.io/badge/Plugins-6-green.svg)](#available-plugins)

## About the Marketplace

The **Synapti Plugin Marketplace** is a curated collection of Claude Code plugins designed for advanced analytical and research tasks. Each plugin provides specialized agents, skills, and commands that extend Claude Code's capabilities in specific domains.

### How to Use

1. Add the marketplace: `claude plugin marketplace add synaptiai/synapti-marketplace`
2. Browse the [Available Plugins](#available-plugins) below
3. Install using `claude plugin install <plugin-name>`
4. Use plugin commands with the `/plugin:command` syntax

---

## Available Plugins

| Plugin | Category | Description | Version |
|--------|----------|-------------|---------|
| [Agent Capability Standard ↗](https://github.com/synaptiai/agent-capability-standard) | Standards, Agent Development | Technical specification for AI agents with structural reliability. 36 atomic capabilities across 9 layers with reference workflows and safety-by-construction patterns. | 1.2.0 |
| [AI-First Org Design Kit](./plugins/ai-first-org-design-kit/) | Organizational Design | Fourteen opinionated skills for designing, deploying, adopting, and evolving AI-first organizations — diagnose coordination overhead, encode organizational identity, write specifications, convert approvals to quality gates, validate gates against hidden holdout scenarios, architect governance, redesign roles, navigate politics, operationalize, run evolution audits, generate agent configs, build maturity matrices, design adoption sprints, and write human-facing AI usage policies. | 1.5.0 |
| [Context Ledger](./plugins/context-ledger/) | Product Development | Evidence-based product development with traceable decisions, explicit trade-offs, and constrained spec generation. | 1.0.0 |
| [Decipon](./plugins/decipon/) | Content Analysis, Deep Research | Detects manipulation, propaganda, and disinformation patterns using the NCI Protocol. Analyzes content across 20 indicators with fact-checking capabilities. | 1.5.0 |
| [Flow](./plugins/flow/) | Workflow, Automation | Skill-driven workflow plugin for GitHub development with excellence-by-default quality gates. Composable skills, safety hooks, agent teams, LSP code intelligence, holdout validation, and learning loop. | 3.2.0 |
| [gh-workflow](./plugins/gh-workflow/) | Workflow, Automation | Generic GitHub workflow commands for issue management, PR creation, code review, and releases. Works with any repository by auto-detecting settings. | 1.9.0 |
| [Prompt Decorators ↗](https://github.com/synaptiai/prompt-decorators/tree/main/claude-code-plugin) | Prompt Engineering | Enhance prompts automatically with composable decorators (143 across 14 categories — reasoning, structure, tone, verification, and eight developer categories). Inline `::Name`/`+++Name` syntax, always-on config, and an opt-in Haiku-powered auto-selector that picks 0-3 decorators per prompt. | 0.1.0 |

### When to Use Each Plugin

| I want to... | Use |
|--------------|-----|
| Diagnose where organizational time goes (coordination vs. execution) | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Encode organizational identity for AI agents | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Convert approval chains into automated quality gates | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Design governance ecosystems for agentic operations | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Navigate political resistance to AI transformation | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Make org design artifacts work with actual agents | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Run post-deployment evolution audits on organizational design | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Generate agent system prompts from role definitions | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Measure AI adoption across teams with a maturity matrix | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Design adoption sprints or hackathons | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Write human-facing AI usage policies with risk reasoning | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Export organizational design as a single reference document | [AI-First Org Design Kit](#featured-ai-first-org-design-kit) |
| Design agents with formal capability contracts | [Agent Capability Standard](#featured-agent-capability-standard) |
| Validate agent workflows for completeness | [Agent Capability Standard](#featured-agent-capability-standard) |
| Ensure safety-by-construction patterns in agents | [Agent Capability Standard](#featured-agent-capability-standard) |
| Build a product with evidence-backed decisions | [Context Ledger](#featured-context-ledger) `/ledger-full` |
| Research all aspects of a product idea in parallel | [Context Ledger](#featured-context-ledger) `/ledger-research` |
| Make explicit decisions with documented trade-offs | [Context Ledger](#featured-context-ledger) `/ledger-decide` |
| Generate PRDs where every section traces to evidence | [Context Ledger](#featured-context-ledger) `/ledger-spec` |
| Analyze articles, social media posts, or news for manipulation | [Decipon](#featured-decipon) `/decipon:analyze` |
| Quickly triage content before deeper analysis | [Decipon](#featured-decipon) `/decipon:score` |
| Research a complex topic with verified sources | [Decipon](#featured-decipon) `/decipon:deep-research` |
| Fact-check claims in content | [Decipon](#featured-decipon) `/decipon:verify` |
| Start implementing a GitHub issue (autonomous, with learning) | [Flow](#featured-flow) `/flow start` |
| Create PRs with parallel review agents | [Flow](#featured-flow) `/flow pr` |
| Debug with structured root cause analysis | [Flow](#featured-flow) `/flow debug` |
| Brainstorm approaches before implementing | [Flow](#featured-flow) `/flow brainstorm` |
| Design architecture with C4 model thinking | [Flow](#featured-flow) `/flow design` |
| Check my workflow status (issues, PRs, reviews) | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-status` |
| Create well-structured GitHub issues | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-issue` |
| Start implementing a GitHub issue | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-start` |
| Commit changes with context-aware classification | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-commit` |
| Create a PR with full review and reviewer suggestions | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-pr` |
| Review a pull request systematically | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-review` |
| Create releases with changelogs | [gh-workflow](#featured-gh-workflow) `/gh-workflow:gh-release` |
| Enhance every prompt with reasoning or structure decorators automatically | [Prompt Decorators ↗](https://github.com/synaptiai/prompt-decorators/tree/main/claude-code-plugin) `/decorate always add <Name>` |
| Inline a one-off behavior tweak (`::Concise`, `::StepByStep`, `::TreeOfThought`) | [Prompt Decorators ↗](https://github.com/synaptiai/prompt-decorators/tree/main/claude-code-plugin) `::Name` sigil |
| Let a fast model pick the right decorators per prompt for me | [Prompt Decorators ↗](https://github.com/synaptiai/prompt-decorators/tree/main/claude-code-plugin) `/decorate auto on` |
| Browse or preview the 143-decorator catalogue | [Prompt Decorators ↗](https://github.com/synaptiai/prompt-decorators/tree/main/claude-code-plugin) `/decorate list` / `preview` |

---

## Claude Desktop Compatibility

Skills from this marketplace are also available for **Claude Desktop** users. Desktop-compatible skill packages are attached to each [GitHub Release](https://github.com/synaptiai/synapti-marketplace/releases).

### What's Different?

| Feature | Claude Code | Claude Desktop |
|---------|-------------|----------------|
| Installation | `claude plugin install` | Upload ZIP in Settings |
| Commands | Full `/plugin:command` syntax | Skills only |
| Agents | Supported | Not supported |
| Frontmatter | All fields | `name`, `description` only |

### How to Install Desktop Skills

1. Go to the [Releases page](https://github.com/synaptiai/synapti-marketplace/releases)
2. Download the `.zip` file for the skill you want (e.g., `deep-research.zip`)
3. Open Claude Desktop → Settings → Skills
4. Upload the ZIP file

### Available Desktop Skills

| Skill | Plugin | Description |
|-------|--------|-------------|
| `deep-research.zip` | Decipon | Comprehensive research using Time-Tested Diffusion methodology |
| `nci-analysis.zip` | Decipon | NCI Protocol for manipulation detection |
| `repo-config.zip` | gh-workflow | Dynamic repository configuration |
| `capability-discovery.zip` | gh-workflow | Environment and capability detection |
| `runtime-verification.zip` | gh-workflow | Runtime verification (dev server, E2E, smoke tests) |
| `suggest-users.zip` | gh-workflow | Reviewer and assignee suggestions based on expertise |

> **Note**: Desktop packages are automatically generated during releases. They contain the same skill content with Claude Code-specific frontmatter fields (`context`, `agent`, `hooks`, etc.) removed for compatibility.

---

## Featured: AI-First Org Design Kit

**AI-First Org Design Kit** provides fourteen opinionated skills that guide founders and leaders through designing, deploying, adopting, and evolving organizations where agents handle coordination and execution while humans own specification and judgment.

### Key Insight

> Every organizational structure is a fossil — a response to constraints (scarce expertise, finite attention, expensive execution) that AI has fundamentally altered. Organizations are specification machines that pretended to be execution machines. The value was always in defining *what should exist*. AI just proved it.

### What Makes It Different

| Feature | Benefit |
|---------|---------|
| **Opinionated Personas** | Each skill has a distinct specialist persona — not generic assistants but diagnosticians, architects, and strategists |
| **One Question at a Time** | Sequential questioning produces specification-grade depth; batch questions produce shallow answers |
| **Artifact Handoff** | Skills save outputs to `$HOME/.ai-first-kit/projects/{slug}/` and auto-discover upstream artifacts |
| **Four Pathways** | Greenfield (founders), brownfield (leaders), already-deployed (evolution), and driving-adoption (maturity + sprints) paths |
| **Political Realism** | The political navigator addresses why 70% of transformations fail — people, not technology |

### Skills

| Skill | Specialist | What It Does |
|-------|-----------|-------------|
| `coordination-audit` | Organizational Diagnostician | Diagnose where time goes — specification vs. coordination vs. execution |
| `org-genome-builder` | Org Psychologist + Systems Architect | Encode values as decision rules, quality standards, communication norms |
| `specification-writer` | Specification Engineer | Create specs precise enough for autonomous agent execution |
| `quality-gate-designer` | Validation Architect | Convert approval chains into criteria-based quality gates |
| `governance-architect` | Governance Systems Designer | Design boundaries, escalation, policy generation, decision ledger, learning loops |
| `role-value-mapper` | Team Architect | Design roles from value flows and specification responsibility |
| `political-navigator` | Power Dynamics Strategist | Map power structures, classify resistance, sequence change |
| `operationalize` | Operational Bridge | Distill all design artifacts into an agent primer (AGENT-PRIMER.md) and optionally merge governance into CLAUDE.md |
| `evolution-auditor` | Organizational Fitness Auditor | Run the learning loop post-deployment: gate effectiveness, genome fitness, authority calibration, decision ledger |
| `agent-builder` | Agent Configuration Engineer | Generate role-specific agent system prompts, tool permissions, and framework configs from organizational design artifacts |
| `maturity-ladder` | Adoption Diagnostician | Build per-role human AI maturity matrix using job titles or solo-founder operational modes, with barrier-informed progression paths and visibility infrastructure |
| `adoption-sprint-designer` | Sprint Architect | Design structured adoption sprints with barrier-informed objectives, buddy pairing, flexible scheduling, demo format, and activity-based measurement |
| `usage-policy-writer` | AI Policy Architect | Generate human-facing AI usage policy with approved tools, data classification, risk model reasoning, and exceptions |

### Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install ai-first-org-design-kit
```

### The Organizational Design Process

**Greenfield** (new orgs): `org-genome-builder → specification-writer → governance-architect → quality-gate-designer → role-value-mapper → operationalize → [optional] maturity-ladder → adoption-sprint-designer → agent-builder → [ongoing] evolution-auditor`

**Brownfield** (existing orgs): `coordination-audit → political-navigator → org-genome-builder → quality-gate-designer → specification-writer → role-value-mapper → governance-architect → operationalize → [optional] maturity-ladder → adoption-sprint-designer → usage-policy-writer → agent-builder → [ongoing] evolution-auditor`

**Already Deployed** (post-deployment): `evolution-auditor → (revision skills based on findings) → operationalize → agent-builder`

**Driving Adoption**: `maturity-ladder → adoption-sprint-designer → usage-policy-writer → [ongoing] evolution-auditor`

The brownfield path runs `political-navigator` early — before technical redesign, not after. 70% of transformations fail because of people, not technology.

**[Full AI-First Org Design Kit Documentation →](./plugins/ai-first-org-design-kit/README.md)**

---

## Featured: Context Ledger

**Context Ledger** provides evidence-based product development — from initial research through implementation planning — where every requirement traces back to explicit decisions and documented evidence.

### Why Context Ledger?

Traditional product development starts with vibes and ends with specs that nobody trusts:
- **Specs drift from reality** — PRDs reference decisions that were never formally made
- **Assumptions hide in prose** — Trade-offs buried in paragraph 47 of a 200-page doc
- **Evidence disappears** — "Studies show..." but which studies? From when?

### Key Insight

> If you can't trace every spec requirement back to evidence and an explicit decision, you're shipping guesswork. Context Ledger enforces traceability at every stage.

### What Makes It Different

| Feature | Benefit |
|---------|---------|
| **Evidence Objects** | Atomic, traceable research with confidence scores and assumptions |
| **Decision Ledger** | Every decision documents alternatives, wins, loses, and risks created |
| **Constrained Specs** | PRDs cannot exist without DEC-* references — no vibes allowed |
| **Quality Gates** | Pipeline won't proceed until evidence and decision minimums are met |
| **Impact Reports** | Updates show exactly what downstream artifacts need regeneration |

### Commands

| Command | What It Does |
|---------|-------------|
| `/ledger-full` | Run complete pipeline end-to-end with mode selection |
| `/ledger-init` | Initialize workspace with brief and pillar map |
| `/ledger-research` | Parallel evidence collection across 8 pillars |
| `/ledger-synthesize` | Per-pillar + cross-pillar synthesis |
| `/ledger-decide` | Make explicit decisions with trade-offs |
| `/ledger-spec` | Generate constrained PRD + architecture |
| `/ledger-plan` | Create implementation plan with milestones |
| `/ledger-update` | Apply learnings with impact report |

### Execution Modes

| Mode | Parallelism | Best For |
|------|-------------|----------|
| `--mode optimizer` | 3 agents/pillar | Standard projects, overnight runs |
| `--mode tokenburner` | 30+ agents/pillar | Hackathons, rapid exploration |
| `--mode ralph` | Stop hook autonomous | Walk-away overnight execution |

Add `--self-improve` to any mode for gap analysis loops.

### Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install context-ledger
```

### The Complete Pipeline

```
/ledger-init → /ledger-research → /ledger-synthesize → /ledger-decide → /ledger-spec → /ledger-plan
     │              │                    │                   │               │             │
     ▼              ▼                    ▼                   ▼               ▼             ▼
  Brief +       Evidence            Synthesis           Decisions        PRD +          Plan
  Pillars       Objects               Files              + Risks        Arch           + Tests
```

**[Full Context Ledger Documentation →](./plugins/context-ledger/README.md)**

---

## Featured: Decipon

**Decipon** implements the **NCI (Narrative Credibility Index) Protocol** — a pattern-based system for detecting manipulation, propaganda, and disinformation in content. Unlike fact-checkers, Decipon analyzes *how* content tries to influence people, not whether claims are true or false.

### Key Insight

> A factually accurate article can still use manipulation techniques. A false claim can be presented without manipulation. Decipon detects the **techniques**, not the truth value.

### Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install decipon
```

### Commands

| Command | Description |
|---------|-------------|
| `/decipon:score <content>` | Quick manipulation score (0-100) for rapid triage |
| `/decipon:analyze <content>` | Full 20-category NCI analysis with dual perspectives |
| `/decipon:verify <content>` | Fact-check claims using deep research methodology |
| `/decipon:report <content>` | Generate formal JSON/Markdown report for archiving |
| `/decipon:deep-research <topic>` | Comprehensive research using Time-Tested Diffusion |
| `/decipon:quick-research <question>` | Quick research with source verification |
| `/decipon:critique <content>` | Red team adversarial critique |

### Recommended Workflow

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  Score  │ ──▶ │ Analyze │ ──▶ │ Verify  │ ──▶ │ Report  │
│ (0-100) │     │(if >25) │     │(if >50) │     │(archive)│
└─────────┘     └─────────┘     └─────────┘     └─────────┘
```

### Severity Scale

| Score | Indicator | Recommended Action |
|-------|-----------|-------------------|
| 0-25 | Low [·] | Normal consumption |
| 26-50 | Moderate [!] | Verify key claims |
| 51-75 | High [!!] | Cross-reference sources, strong skepticism |
| 76-100 | Severe [!!!] | Likely manipulation |

### The NCI Framework

Analyzes 20 manipulation categories across 5 composite factors:

| Factor | Weight | What It Detects |
|--------|--------|-----------------|
| Emotional Manipulation | 25% | Fear, urgency, manufactured outrage |
| Suspicious Timing | 20% | Convenient emergence, beneficiary patterns |
| Uniform Messaging | 20% | Coordinated talking points, bandwagon effects |
| Tribal Division | 15% | Us-vs-them framing, false dilemmas |
| Missing Information | 20% | Context gaps, cherry-picking, logical fallacies |

**[Full Decipon Documentation →](./plugins/decipon/README.md)**

---

## Featured: gh-workflow

**gh-workflow** provides a complete GitHub development workflow — from issue creation through releases — that works with any repository without hardcoded configuration.

### Why gh-workflow?

Traditional approaches to GitHub automation often break when:
- Repository settings change (branch renamed, labels modified)
- Teams customize their workflow conventions
- Commands assume specific project structures

**gh-workflow solves this through dynamic detection** — every command discovers your repository's actual configuration at runtime.

### Key Insight

> Issues that specify implementation details ("add a component to src/views/") become obsolete when code is refactored. **Solution-agnostic issues** describe *what* should happen, not *how* — surviving any refactoring.

### What Makes It Different

| Feature | Benefit |
|---------|---------|
| **Dynamic Detection** | Auto-detects default branch, labels, and repo settings — no hardcoding |
| **Solution-Agnostic Issues** | Issues describe requirements, not implementation — survives refactoring |
| **Interactive Workflows** | Guided prompts at decision points prevent mistakes |
| **Complete Lifecycle** | Single plugin covers issues → implementation → review → merge → release |
| **Verification Loops** | Bounded fix-verify cycles (max 3 iterations) enforce "iterate until green" |
| **Parallel Agent Pipeline** | Dispatches code-reviewer, convention-checker, and test-runner simultaneously |
| **Runtime Verification** | Verifies implementation works when running (dev server, API, E2E tests) |
| **Evidence-Based Assertions** | Requires file:line citations for code behavior claims |

### Commands

| Command | What It Does |
|---------|-------------|
| `/gh-workflow:gh-status` | View workflow status (assigned issues, open PRs, review requests) |
| `/gh-workflow:gh-issue` | Create issues that focus on requirements, not implementation |
| `/gh-workflow:gh-start <N>` | Assign issue, create branch, implement with task tracking |
| `/gh-workflow:gh-commit` | Context-aware commits with change classification |
| `/gh-workflow:gh-pr` | Create PR with full review and reviewer suggestions |
| `/gh-workflow:gh-review <N>` | Systematic PR review with checklist and feedback |
| `/gh-workflow:gh-address <N>` | Address review comments on a PR |
| `/gh-workflow:gh-merge <N>` | Safely merge approved PRs |
| `/gh-workflow:gh-release` | Create releases with automatic changelog generation |
| `/gh-workflow:gh-setup` | Generate project-specific workflow configuration |

### Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install gh-workflow
```

### The Complete Development Cycle

```
/gh-status → /gh-issue → /gh-start → /gh-commit → /gh-pr → /gh-review → /gh-address → /gh-merge → /gh-release
     │            │            │            │          │          │            │            │            │
     ▼            ▼            ▼            ▼          ▼          ▼            ▼            ▼            ▼
  View        Create      Branch +    Context-   Full PR    Review      Address      Merge       Tag +
  status      issue      implement    aware      review       PR       comments       PR       changelog
                                     commits    + suggest
```

**[Full gh-workflow Documentation →](./plugins/gh-workflow/README.md)**

---

## Featured: Flow

**Flow** replaces command-driven GitHub workflow automation with a **skill-driven** approach. Instead of encoding logic in commands, Flow composes reusable skills that compound team knowledge across sessions.

### Key Insight

> Commands tell agents *what to do*. Skills teach agents *how to think*. When knowledge lives in composable skills instead of monolithic commands, it compounds — every session makes the next one better.

### What Makes It Different

| Feature | Benefit |
|---------|---------|
| **Composable Skills** | 22 reusable skills (3 foundation + 19 domain) — commands compose skills, not duplicate logic |
| **Three-Tier Safety** | Hook-enforced tiers: autonomous (commits), journal (push/PR), confirm (merge/release) |
| **Learning Loop** | Decision journal captures patterns; `/flow learn` proposes new skills from experience |
| **Agent Teams** | Parallel + adversarial review teams where reviewers challenge each other's findings |
| **LSP Code Intelligence** | Leverages language server go-to-definition, find-references, hover, and diagnostics across EXPLORE, CODE, VERIFY, and REVIEW phases |
| **Visual Verification** | Screenshot-based runtime verification for UI changes |

### Commands

| Command | What It Does |
|---------|-------------|
| `/flow start <issue>` | Assign issue, create branch, decompose tasks, implement |
| `/flow commit` | Classify changes, flag anomalies, create atomic commits |
| `/flow pr` | Full review pipeline + PR creation |
| `/flow review <pr>` | Multi-faceted code review (single or team) |
| `/flow address <pr>` | Systematic feedback resolution |
| `/flow merge <pr>` | Merge with prerequisite verification (Tier 3) |
| `/flow release <type>` | Changelog + semantic version release (Tier 3) |
| `/flow status` | Read-only workflow overview |
| `/flow learn` | Analyze decision patterns, propose new skills |
| `/flow setup` | Initialize flow for a repository |
| `/flow explain` | Interactive Q&A about decisions |
| `/flow brainstorm [topic]` | Explore approaches before implementation |
| `/flow debug [error]` | Structured debugging with root cause analysis |
| `/flow design [feature]` | Architecture discussion and design validation |

### Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install flow
```

### The Complete Development Cycle

```
/flow start → /flow commit → /flow pr → /flow review → /flow address → /flow merge → /flow release
     │             │             │            │              │              │              │
     ▼             ▼             ▼            ▼              ▼              ▼              ▼
  Branch +     Classify +    Review +     Quality       Resolve        Merge +        Tag +
  implement    atomic        agents       check         feedback       cleanup       changelog
               commits       + PR                                     (Tier 3)
```

**[Full Flow Documentation →](./plugins/flow/README.md)**

---

## Featured: Agent Capability Standard

**Agent Capability Standard** is a technical specification for building AI agents with structural reliability. It implements "Grounded Agency" — a framework ensuring agents operate with evidence-backed claims rather than hallucinations.

> **External Repository**: This plugin is maintained at [synaptiai/agent-capability-standard](https://github.com/synaptiai/agent-capability-standard) and included as a git submodule.

### Why Agent Capability Standard?

Most AI agents today operate with:
- **Hallucinated capabilities** — claiming skills they can't verify
- **Opaque decision-making** — no audit trail for actions taken
- **Brittle error handling** — mutations without rollback options
- **Implicit contracts** — undefined inputs/outputs between components

### Key Insight

> If an agent can't prove it has a capability, it shouldn't claim to have it. Agent Capability Standard enforces grounded capabilities with explicit contracts and audit trails.

### What Makes It Different

| Feature | Benefit |
|---------|---------|
| **36 Atomic Capabilities** | Minimal, composable building blocks across 9 cognitive layers |
| **Typed Contracts** | Explicit input/output schemas between capabilities |
| **Safety-by-Construction** | Mutations require checkpoints; rollback always possible |
| **Audit Trails** | Complete action lineage and provenance for every operation |
| **Reference Workflows** | Battle-tested patterns for common agent tasks |

### The 9 Capability Layers

| Layer | Count | Purpose |
|-------|-------|---------|
| Perceive | 4 | Retrieval, searching, observation, reception |
| Understand | 6 | Detection, classification, measurement, prediction |
| Reason | 4 | Planning, decomposition, critique, explanation |
| Model | 5 | State, transition, attribution, grounding, simulation |
| Synthesize | 3 | Generation, transformation, integration |
| Execute | 3 | Execution, mutation, sending |
| Verify | 5 | Verification, checkpointing, rollback, auditing |
| Remember | 2 | Persistence, recall |
| Coordinate | 4 | Delegation, synchronization, invocation, inquiry |

### Reference Workflows

| Workflow | Purpose |
|----------|---------|
| `debug_code_change` | Systematic debugging with evidence collection |
| `world_model_build` | Construct grounded world models |
| `capability_gap_analysis` | Identify missing capabilities |
| `digital_twin_bootstrap` | Initialize agent mirrors |
| `digital_twin_sync_loop` | Maintain synchronized state |

### Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install agent-capability-standard
```

**[Full Agent Capability Standard Documentation →](https://github.com/synaptiai/agent-capability-standard)**

---

## Repository Structure

```
synapti-marketplace/
├── README.md                          # This file
├── .claude-plugin/
│   └── marketplace.json               # Marketplace configuration
└── plugins/
    ├── agent-capability-standard/     # AI agent standards (submodule)
    │   ├── .claude-plugin/
    │   │   └── plugin.json            # Plugin metadata
    │   ├── README.md                  # Full specification
    │   ├── spec/                      # YAML specifications
    │   └── tools/                     # Validation scripts
    │
    ├── ai-first-org-design-kit/       # Organizational design for AI
    │   ├── .claude-plugin/
    │   │   └── plugin.json            # Plugin metadata
    │   ├── README.md                  # Full plugin documentation
    │   ├── shared/                    # Foundational concepts
    │   │   └── concepts.md            # Vocabulary all skills reference
    │   └── skills/                    # 13 organizational design skills + router
    │       ├── ai-first-kit/          # Router (entry point)
    │       ├── coordination-audit/    # Diagnose time allocation
    │       ├── org-genome-builder/    # Encode organizational identity
    │       ├── specification-writer/  # Create agent-ready specs
    │       ├── quality-gate-designer/ # Convert approvals to gates
    │       ├── governance-architect/  # Design governance ecosystem
    │       ├── role-value-mapper/     # Design specification-first roles
    │       ├── political-navigator/   # Navigate change resistance
    │       ├── operationalize/        # Bridge design to agent consumption
    │       ├── evolution-auditor/     # Post-deployment learning loop
    │       ├── agent-builder/         # Role-specific agent configs
    │       ├── maturity-ladder/       # Per-role AI adoption maturity matrix
    │       ├── adoption-sprint-designer/ # Structured adoption sprints
    │       └── usage-policy-writer/   # Human-facing AI usage policy
    │
    ├── context-ledger/                # Evidence-based product development
    │   ├── .claude-plugin/
    │   │   └── plugin.json            # Plugin metadata
    │   ├── README.md                  # Full plugin documentation
    │   ├── agents/                    # 5 specialized agents
    │   ├── commands/                  # 8 pipeline commands
    │   ├── skills/                    # 5 methodology skills
    │   └── templates/                 # Evidence/decision templates
    │
    ├── decipon/                       # Content analysis plugin
    │   ├── .claude-plugin/
    │   │   └── plugin.json            # Plugin metadata
    │   ├── README.md                  # Full plugin documentation
    │   ├── agents/                    # 5 specialized AI agents
    │   ├── commands/                  # 7 user-facing commands
    │   └── skills/                    # 2 methodology implementations
    │
    ├── flow/                          # Skill-driven workflow
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── README.md
    │   ├── agents/                   # 8 specialized agents
    │   ├── commands/                 # 23 workflow commands (17 work + 6 runtime/admin)
    │   ├── hooks/                    # Safety hook definitions
    │   ├── skills/                   # 22 composable skills (3 foundation + 19 domain)
    │   ├── templates/                # PR, issue, skill proposal templates
    │   └── references/               # Safety tiers, checklists, manifests
    │
    └── gh-workflow/                   # GitHub workflow plugin
        ├── .claude-plugin/
        │   └── plugin.json            # Plugin metadata
        ├── README.md                  # Full plugin documentation
        ├── agents/                    # 4 specialized agents
        │   ├── code-reviewer.md       # Code quality review
        │   ├── convention-checker.md  # Git convention validation
        │   ├── implementation-planner.md # Task breakdown
        │   └── test-runner.md         # Quality gate runner
        ├── commands/                  # 10 workflow commands
        │   ├── gh-status.md           # View workflow status
        │   ├── gh-issue.md            # Create issues
        │   ├── gh-start.md            # Start work on issue
        │   ├── gh-commit.md           # Context-aware commits
        │   ├── gh-pr.md               # Create PR with review
        │   ├── gh-review.md           # Review PRs
        │   ├── gh-address.md          # Address PR comments
        │   ├── gh-merge.md            # Merge approved PRs
        │   ├── gh-release.md          # Create releases
        │   └── gh-setup.md            # Setup workflow config
        ├── skills/                    # Dynamic configuration
        │   ├── repo-config/           # Repository settings
        │   ├── capability-discovery/  # Environment detection
        │   ├── runtime-verification/  # Runtime verification (dev server, E2E)
        │   └── suggest-users/         # Reviewer/assignee suggestions
        └── templates/                 # Issue/PR templates
```

---

## For Plugin Developers

Want to contribute a plugin to the marketplace?

### Plugin Structure Requirements

Each plugin must include:

```
your-plugin/
├── .claude-plugin/
│   └── plugin.json       # Required: name, version, description
├── README.md             # Documentation
├── agents/               # AI agent definitions (optional)
├── commands/             # User-facing commands (optional)
└── skills/               # Skill implementations (optional)
```

### plugin.json Format

```json
{
  "name": "your-plugin",
  "version": "1.0.0",
  "description": "Brief description of what your plugin does",
  "author": { "name": "Your Name" },
  "license": "MIT",
  "keywords": ["relevant", "keywords"]
}
```

### Submission Process

1. Fork this repository
2. Add your plugin to `plugins/`
3. Update `.claude-plugin/marketplace.json` with your plugin entry
4. Submit a pull request with documentation

---

## License

This project is licensed under the MIT License.

## Credits

**Author:** Daniel Bentes

**Organization:** [Synapti](https://synapti.ai)

**Repository:** [github.com/synaptiai/synapti-marketplace](https://github.com/synaptiai/synapti-marketplace)

---

<p align="center">
  <sub>Built for the Claude Code ecosystem</sub>
</p>
