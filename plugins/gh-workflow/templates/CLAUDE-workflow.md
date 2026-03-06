# Git Workflow Section Template

Copy this section into your project's `.claude/CLAUDE.md` file and customize as needed.

---

<!-- gh-workflow: 1.7.0 -->

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
| `/gh-workflow:gh-status` | View workflow status (issues, PRs, reviews) |
| `/gh-workflow:gh-issue` | Create a new GitHub issue |
| `/gh-workflow:gh-start <issue>` | Start work on an issue (branch, implement, track) |
| `/gh-workflow:gh-commit` | Context-aware commits with change classification |
| `/gh-workflow:gh-pr` | Create PR with full review and reviewer suggestions |
| `/gh-workflow:gh-review <pr>` | Review a pull request with prioritized findings |
| `/gh-workflow:gh-address <pr>` | Address PR review comments |
| `/gh-workflow:gh-merge <pr>` | Merge an approved pull request |
| `/gh-workflow:gh-release <type>` | Create a release (patch/minor/major) |
| `/gh-workflow:gh-explain <issue>` | Explore what AI built — interactive Q&A |
| `/gh-workflow:gh-security-review` | Security review of branch changes |
| `/gh-workflow:gh-setup` | Set up or update workflow configuration |

## Plugin Capabilities

### Agents
- **code-reviewer** - Code quality analysis with P1/P2/P3 prioritized findings
- **convention-checker** - Validates commit messages, branch naming, PR format
- **test-runner** - Discovers and runs project-specific lint/test/typecheck commands
- **implementation-planner** - Creates task breakdowns from issue acceptance criteria

### Skills
- **repo-config** - Auto-detects default branch, labels, and repository settings
- **capability-discovery** - Discovers available agents, skills, and quality commands
- **runtime-verification** - Verifies implementation works at runtime (dev server, API, E2E)
- **suggest-users** - Suggests reviewers/assignees based on CODEOWNERS and activity
- **decision-journal** - Captures decisions from diffs, detects human gate triggers
- **comprehension-report** - Generates architecture narratives for PR bodies

### Safety Hooks
Automatic safety guards: pre-push verification, pre-release checks, destructive operation warnings, repository target verification, post-edit test reminders, workflow completion checks, task completion verification.

## Labels

Available labels for this repository:
- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Documentation improvements

## Verification

### Quality Commands
- Lint: `{lint_cmd}`
- Test: `{test_cmd}`
- Type check: `{typecheck_cmd}`

### Runtime Verification
- Dev server: `{dev_server_cmd}` (app at http://localhost:{port})
- Health check: `curl http://localhost:{port}/health`
- E2E tests: `{e2e_cmd}`
- Smoke tests: `{smoke_cmd}` (or "N/A")

### For any feature work:
1. Add/extend unit tests first
2. Implement code
3. Run unit + lint + typecheck; fix until green
4. Start dev server and verify new behavior works
5. Run E2E tests if applicable
6. For UI changes, verify visually or via browser automation

## Comprehension Layer

### Gates
- gate-new-dependencies: on
- gate-security-changes: on
- gate-schema-changes: on
- gate-api-surface-changes: on
- gate-scope-deviations: on
- gate-ambiguous-requirements: on

### Decision Journal
- journal-dir: .decisions
- journal-sensitivity-default: public

### Report
- report-threshold-full: 100

### Explain
- explain-include-diff: true
- explain-session-save: ask

### Per-Command Toggles
- gh-start-familiarity-prompt: true
- gh-commit-first-touch: true
- gh-pr-comprehension-report: true
- gh-pr-decision-summary: true
- gh-review-comprehension-check: true
- gh-merge-knowledge-checkpoint: true

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

### Version Marker
The `<!-- gh-workflow: X.Y.Z -->` comment at the top of the workflow section tracks which version of gh-workflow generated this configuration. Do not remove it -- it enables `/gh-setup` to detect and upgrade existing installations.

### Local Command Overrides
If you need to customize commands beyond the plugin defaults:
1. Create `.claude/commands/` directory
2. Copy the command you want to customize
3. Modify as needed - local commands take precedence over plugin commands
