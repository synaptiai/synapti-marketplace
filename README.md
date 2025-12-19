# Synapti Plugin Marketplace

> Agentic harnesses for Claude Code — specialized AI agents for complex analytical tasks

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://claude.com/claude-code)
[![Plugins](https://img.shields.io/badge/Plugins-1-green.svg)](#available-plugins)

## About the Marketplace

The **Synapti Plugin Marketplace** is a curated collection of Claude Code plugins designed for advanced analytical and research tasks. Each plugin provides specialized agents, skills, and commands that extend Claude Code's capabilities in specific domains.

### How to Use

1. Browse the [Available Plugins](#available-plugins) below
2. Install using `claude plugin install <path-or-url>`
3. Use plugin commands with the `/plugin:command` syntax

---

## Available Plugins

| Plugin | Category | Description | Version |
|--------|----------|-------------|---------|
| [Decipon](./synapti-marketplace/plugins/decipon/) | Security | NCI manipulation detection with deep research fact-checking | 1.3.1 |

---

## Featured: Decipon

**Decipon** implements the **NCI (Narrative Credibility Index) Protocol** — a pattern-based system for detecting manipulation, propaganda, and disinformation in content. Unlike fact-checkers, Decipon analyzes *how* content tries to influence people, not whether claims are true or false.

### Key Insight

> A factually accurate article can still use manipulation techniques. A false claim can be presented without manipulation. Decipon detects the **techniques**, not the truth value.

### Installation

```bash
# From local path
claude plugin install ./synapti-marketplace/plugins/decipon

# From GitHub
claude plugin install github:synaptiai/decipon-plugin
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
│ (0-100) │     │(if >20) │     │(if >40) │     │(archive)│
└─────────┘     └─────────┘     └─────────┘     └─────────┘
```

### Severity Scale

| Score | Indicator | Recommended Action |
|-------|-----------|-------------------|
| 0-20 | Low | Normal consumption |
| 21-40 | Moderate | Verify key claims |
| 41-60 | Elevated | Cross-reference sources |
| 61-80 | High | Exercise strong skepticism |
| 81-100 | Severe | Likely manipulation |

### The NCI Framework

Analyzes 20 manipulation categories across 5 composite factors:

| Factor | Weight | What It Detects |
|--------|--------|-----------------|
| Emotional Manipulation | 25% | Fear, urgency, manufactured outrage |
| Suspicious Timing | 20% | Convenient emergence, beneficiary patterns |
| Uniform Messaging | 20% | Coordinated talking points, bandwagon effects |
| Tribal Division | 15% | Us-vs-them framing, false dilemmas |
| Missing Information | 20% | Context gaps, cherry-picking, logical fallacies |

**[Full Decipon Documentation →](./synapti-marketplace/plugins/decipon/README.md)**

---

## Repository Structure

```
agentic-harnesses/
├── README.md                          # This file
└── synapti-marketplace/
    ├── .claude-plugin/
    │   └── marketplace.json           # Marketplace configuration
    └── plugins/
        └── decipon/
            ├── .claude-plugin/
            │   └── plugin.json        # Plugin metadata
            ├── README.md              # Full plugin documentation
            ├── agents/                # 5 specialized AI agents
            │   ├── nci-analyzer.md
            │   ├── perspective-generator.md
            │   ├── claim-verifier.md
            │   ├── deep-researcher.md
            │   └── fact-checker.md
            ├── commands/              # 7 user-facing commands
            └── skills/                # 2 methodology implementations
                ├── nci-analysis/
                └── deep-research/
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
2. Add your plugin to `synapti-marketplace/plugins/`
3. Update `marketplace.json` with your plugin entry
4. Submit a pull request with documentation

---

## License

This project is licensed under the MIT License.

## Credits

**Author:** Daniel Bentes
**Organization:** [Synapti](https://synapti.ai)
**Repository:** [github.com/synaptiai/agentic-harnesses](https://github.com/synaptiai/agentic-harnesses)

---

<p align="center">
  <sub>Built for the Claude Code ecosystem</sub>
</p>
