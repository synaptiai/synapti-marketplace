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
| `/gh-start <issue>` | Start work on an issue |
| `/gh-review <pr>` | Review a pull request |
| `/gh-address <pr>` | Address PR review comments |
| `/gh-merge <pr>` | Merge an approved pull request |
| `/gh-release <type>` | Create a release (patch/minor/major) |
| `/gh-plugin [name]` | Validate plugin structure |

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
