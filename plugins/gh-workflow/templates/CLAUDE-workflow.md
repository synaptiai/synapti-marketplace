# Git Workflow Section Template

Copy this section into your project's `.claude/CLAUDE.md` file and customize as needed.

---

## Git Workflow

### Branching Strategy

```
{DEFAULT_BRANCH} (production/releases)
  ↑
  └── Feature PR (feature/* → {DEFAULT_BRANCH})

feature/issue-{number}-{desc}
fix/issue-{number}-{desc}
docs/issue-{number}-{desc}
```

### Commit Conventions

Use semantic commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`

### Branch Naming

- `feature/issue-{number}-{short-description}` - New features
- `fix/issue-{number}-{short-description}` - Bug fixes
- `docs/issue-{number}-{short-description}` - Documentation

## GitHub Workflow Commands

This project uses the gh-workflow plugin. Available commands:

| Command | Purpose |
|---------|---------|
| `/gh-workflow:gh-issue` | Create a new GitHub issue |
| `/gh-workflow:gh-start <issue>` | Start work on an issue |
| `/gh-workflow:gh-review <pr>` | Review a pull request |
| `/gh-workflow:gh-address <pr>` | Address PR review comments |
| `/gh-workflow:gh-merge <pr>` | Merge an approved pull request |
| `/gh-workflow:gh-release <type>` | Create a release (patch/minor/major) |

## Labels

Available labels for this repository:
- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Documentation improvements

---

## Customization Notes

### Replace Placeholders
- `{DEFAULT_BRANCH}` - Your default branch (e.g., `main`, `master`, `develop`)

### Project-Specific Additions
Add any project-specific workflow notes below the standard sections:
- Code review requirements
- CI/CD pipeline information
- Deployment process
- Team conventions

### Local Command Overrides
If you need to customize commands beyond the plugin defaults:
1. Create `.claude/commands/` directory
2. Copy the command you want to customize
3. Modify as needed - local commands take precedence over plugin commands
