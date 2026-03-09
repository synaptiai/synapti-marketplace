# Synapti Plugin Marketplace

> Agentic harnesses for Claude Code — specialized AI agents for complex analytical tasks

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://claude.com/claude-code)
[![Plugins](https://img.shields.io/badge/Plugins-5-green.svg)](#available-plugins)

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
| [Context Ledger](./plugins/context-ledger/) | Product Development | Evidence-based product development with traceable decisions, explicit trade-offs, and constrained spec generation. | 1.0.0 |
| [Decipon](./plugins/decipon/) | Content Analysis, Deep Research | Detects manipulation, propaganda, and disinformation patterns using the NCI Protocol. Analyzes content across 20 indicators with fact-checking capabilities. | 1.5.0 |
| [Flow](./plugins/flow/) | Workflow, Automation | Skill-driven workflow plugin for GitHub development. Composable skills, safety hooks, agent teams, LSP code intelligence, and learning loop. | 1.1.0 |
| [gh-workflow](./plugins/gh-workflow/) | Workflow, Automation | Generic GitHub workflow commands for issue management, PR creation, code review, and releases. Works with any repository by auto-detecting settings. | 1.8.0 |

### When to Use Each Plugin

| I want to... | Use |
|--------------|-----|
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
| **Composable Skills** | 18 reusable skills (3 foundation + 15 domain) — commands compose skills, not duplicate logic |
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
    │   ├── agents/                   # 7 specialized agents
    │   ├── commands/                 # 16 workflow commands
    │   ├── hooks/                    # Safety hook definitions
    │   ├── skills/                   # 18 composable skills (3 foundation + 15 domain)
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
