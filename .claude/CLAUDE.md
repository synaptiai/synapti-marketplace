# Synapti Plugin Marketplace

Claude Code plugin marketplace with specialized agents for analytical and research tasks.

Agent rules shared with other coding agents live in AGENTS.md:

@../AGENTS.md

## Repository

- **GitHub**: https://github.com/synaptiai/synapti-marketplace
- **Tech Stack**: Claude Code plugins, Markdown-based agents/commands/skills
- **License**: Apache-2.0

## Git Workflow

### Branching Strategy

```
main (production/releases)
  ↑
  └── Feature PR (feature/* → main)

feature/issue-{number}-{desc}
fix/issue-{number}-{desc}
docs/issue-{number}-{desc}
```

### Commit Conventions

Use semantic commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`

**Do NOT include Claude attribution in commits.** No `Co-Authored-By: Claude` lines.

### Branch Naming

- `feature/issue-{number}-{short-description}` - New features
- `fix/issue-{number}-{short-description}` - Bug fixes
- `docs/issue-{number}-{short-description}` - Documentation

## Claude Commands

Project-specific commands for GitHub workflow:

| Command | Purpose |
|---------|---------|
| `/gh-issue` | Create a new GitHub issue |
| `/gh-start <issue>` | Start work on an issue (ends with PR options) |
| `/gh-commit` | Context-aware commit with change classification |
| `/gh-pr` | Create PR with full review and reviewer suggestions |
| `/gh-review <pr>` | Review a pull request |
| `/gh-address <pr>` | Address PR review comments |
| `/gh-merge <pr>` | Merge an approved pull request |
| `/gh-release <type>` | Create a release (patch/minor/major) |
| `/gh-plugin [name]` | Validate plugin structure |
| `/gh-status` | Show workflow status overview |

## Project Structure

```
synapti-marketplace/
├── .claude/                          # Claude Code configuration
│   ├── CLAUDE.md                     # This file
│   ├── commands/                     # Custom commands
│   └── settings.local.json           # Permissions
├── AGENTS.md                         # Agent rules shared with other coding agents
├── .claude-plugin/
│   └── marketplace.json              # Marketplace metadata
├── plugins/
│   └── decipon/                      # Decipon plugin
│       ├── .claude-plugin/
│       │   └── plugin.json           # Plugin metadata
│       ├── README.md                 # Plugin documentation
│       ├── agents/                   # AI agent definitions
│       ├── commands/                 # User-facing commands
│       └── skills/                   # Skill implementations
└── README.md                         # Marketplace documentation
```

## Versioning

Version information is maintained in two files:

- **Marketplace version**: `.claude-plugin/marketplace.json` → `metadata.version`
- **Plugin versions**: `plugins/{name}/.claude-plugin/plugin.json` → `version`

When releasing:
1. Update plugin version in `plugin.json`
2. Update the same version in `marketplace.json` under the plugin entry
3. Optionally bump marketplace version for major changes

## Labels

Available GitHub labels:
- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Documentation improvements
- `security` - Security related issues
- `plugin` - Plugin-specific changes

<!-- ai-first-kit-operationalize: 2026-03-30-1750 -->
## Organizational Governance

This project follows an organizational genome and governance framework.
Agents operating in this repository must follow the rules below.

### Hard Boundaries (Non-Negotiable)
1. **No Ungrounded Claims** — Never make factual claims without verification against current sources. Never rely on training data for current state of APIs, models, libraries, or tools.
2. **No Irreversible Actions Without Approval** — Never delete data, force-push, or drop resources without explicit approval. Blanket authorization is never valid.
3. **No Unauthorized External Communication** — Never send messages or post content visible to others without explicit approval.
4. **No Incomplete Shipments** — Never ship work containing mocks, placeholders, TODOs, or unverified functionality. Done means done.
5. **No Assumption-Driven Decisions** — Never act on assumed state without verification. Research first, verify against current sources.

Priority: Safety > Reputation > Trust > Quality > Completeness.

### Values
- **Quality-First Completionism:** Nothing ships until tested, documented, verified, and worthy of putting your name on.
- **Observation-Driven Building:** Ground proposals in observable problems or connectable patterns, not best-practice lists.
- **Simplicity & Clarity:** Lead with the problem solved, simplest path to value, minimal jargon. If onboarding isn't intuitive, simplify.
- **Proactive Autonomy:** Try to resolve ambiguity yourself first. When escalating, present 2-3 options with reasoning — never open-ended questions.

### Full Operating Primer
For complete operating instructions including authority tiers, quality gates,
voice norms, escalation protocols, and anti-patterns, read:
`$HOME/.ai-first-kit/projects/synapti-marketplace/AGENT-PRIMER.md`

### Quality Gates
This project uses automated quality gates. Self-review against gate criteria
before presenting work. See `$HOME/.ai-first-kit/projects/synapti-marketplace/gates/INDEX.md`.
<!-- /ai-first-kit-operationalize -->

## Flow Workflow

This project uses the [flow](https://github.com/synaptiai/synapti-marketplace/tree/main/plugins/flow) plugin for skill-driven GitHub development.

> **Coexistence**: gh-workflow is also installed. The two plugins provide similar commands for the same steps under different prefixes (flow uses `/flow:*`, gh-workflow uses `/gh-*`), and both keep an issue's decision journal in `.decisions/issue-{N}.md` by default, so use one plugin's commands for a given issue.

### Commands

| Command | Purpose |
|---------|---------|
| `/flow <verb> <target>` | Entry point that routes a verb to the command below |
| `/flow:start <issue>` | Start work on an issue |
| `/flow:commit` | Classify and commit changes |
| `/flow:pr` | Create pull request |
| `/flow:review <pr>` | Review a pull request |
| `/flow:address <pr>` | Address review feedback |
| `/flow:merge <pr>` | Merge approved PR (requires confirmation) |
| `/flow:release <type>` | Create release (requires confirmation) |
| `/flow:resolve [pr-or-branch]` | Resolve merge conflicts |
| `/flow:status` | Workflow overview |
| `/flow:learn` | Analyze patterns |
| `/flow:setup` | Initialize flow for a repository |
| `/flow:explain` | Questions about decisions on this branch |
| `/flow:issue [topic]` | Create a GitHub issue |
| `/flow:brainstorm [topic]` | Explore approaches before implementation |
| `/flow:debug [error]` | Structured debugging |
| `/flow:design [feature]` | Architecture and design review |
| `/flow:goal` | Create, inspect and evaluate FlowGoals |
| `/flow:resume` | Propose the next safe action for an interrupted run |
| `/flow:workflow` | Inspect workflow definitions |
| `/flow:trigger` | Manage FlowTriggers |
| `/flow:run trigger <id>` | Run one FlowTrigger's target once |
| `/flow:watch` | Generate a `/loop` prompt for hands-off iteration |

### Safety Model

- **Tier 1** (Autonomous): commits, branches, file edits
- **Tier 2** (Journal): push, PR creation, issue creation, issue assignment. By default each runs and writes a breadcrumb to the git-ignored auto-log trail; each is a `tiers.*` setting (`push`, `prCreate`, `issueCreate`, `issueAssign`) that also takes `autonomous` or `confirm`
- **Tier 3** (Confirm): merge, release, pushing or deleting a tag. Always asks; `tiers.merge` and `tiers.release` cannot go below `confirm`

The `tier-gate.sh` hook applies these settings to every Bash command, and flow's `git` and `gh` wrappers check again when the program starts.

### LSP Code Intelligence

Flow leverages LSP servers when available for semantic code understanding:
- **EXPLORE**: `goToDefinition` and `findReferences` for code path tracing and impact analysis
- **CODE**: `hover` for type info and signatures
- **VERIFY**: LSP diagnostics as complementary quality signals (errors→P1, warnings→P2)
- **REVIEW**: `findReferences` and `incomingCalls` for caller verification

Run `/flow:setup` to detect and install LSP servers for your tech stack.

### Conventions

- Commit format: `<type>(<scope>): <subject>` (matches existing repo style)
- Branch naming: `feature/issue-{N}-{description}` (matches existing repo style)
- Decision journal: `.decisions/` directory
