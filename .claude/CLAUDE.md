# Synapti Plugin Marketplace

Claude Code plugin marketplace with specialized agents for analytical and research tasks.

## Repository

- **GitHub**: https://github.com/synaptiai/synapti-marketplace
- **Tech Stack**: Claude Code plugins, Markdown-based agents/commands/skills
- **License**: MIT

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

> **Coexistence**: gh-workflow is also installed. Enable only one at a time to avoid hook conflicts. Flow commands use the `/flow:*` prefix; gh-workflow uses `/gh-*`.

### Commands

| Command | Purpose |
|---------|---------|
| `/flow:start <issue>` | Start work on a GitHub issue |
| `/flow:commit` | Classify changes and create atomic commits |
| `/flow:pr` | Create PR with full review pipeline |
| `/flow:review <pr>` | Multi-faceted PR review |
| `/flow:address <pr>` | Address review feedback surgically |
| `/flow:merge <pr>` | Merge approved PR (requires confirmation) |
| `/flow:release <type>` | Create release (requires confirmation) |
| `/flow:issue [topic]` | Create well-crafted GitHub issues |
| `/flow:status` | Workflow overview |
| `/flow:learn` | Analyze decision patterns |
| `/flow:setup` | Initialize flow for this repo |
| `/flow:explain` | Q&A about decisions |

### Safety Model

- **Tier 1** (Autonomous): commits, branches, file edits
- **Tier 2** (Journal): push, PR creation, issue assignment
- **Tier 3** (Confirm): merge, release

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
