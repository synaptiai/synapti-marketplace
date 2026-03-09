## Flow Workflow

This project uses the [flow](https://github.com/synaptiai/synapti-marketplace/tree/main/plugins/flow) plugin for skill-driven GitHub development.

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

- Commit format: `<type>(<scope>): <subject>`
- Branch naming: `feature/issue-{N}-{description}`
- Decision journal: `.decisions/` directory
