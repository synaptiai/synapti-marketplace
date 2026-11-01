## Flow Workflow

This project uses the [flow](https://github.com/synaptiai/synapti-marketplace/tree/main/plugins/flow) plugin for skill-driven GitHub development.

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

- Commit format: `<type>(<scope>): <subject>`
- Branch naming: `feature/issue-{N}-{description}`
- Decision journal: `.decisions/` directory
