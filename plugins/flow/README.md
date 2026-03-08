# Flow: Skill-Driven Workflow Plugin

A Claude Code plugin that replaces command-driven GitHub workflow automation with a skill-driven, agent-team-powered approach. Skills encode reusable team knowledge that compounds across sessions.

## Quick Start

```bash
# Install the plugin
claude plugins add ./plugins/flow

# Initialize for your repository
/flow setup

# Start working on an issue
/flow start 42
```

## Architecture

```
SKILL LIBRARY (18 skills)
  ├── Foundation (always loaded, <=100 lines each)
  │   ├── evidence-based-development
  │   ├── autonomous-workflow
  │   └── code-quality-principles
  │
  └── Domain (contextually invoked, max 3 concurrent)
      ├── issue-crafting
      ├── branch-and-task-management
      ├── change-classification
      ├── convention-enforcement
      ├── capability-discovery
      ├── code-review-methodology
      ├── pr-lifecycle
      ├── feedback-resolution
      ├── merge-and-release
      ├── runtime-verification
      ├── team-coordination
      ├── architecture-patterns
      ├── brainstorming
      ├── debugging-patterns
      ├── tdd-patterns
      └── learned/ (promoted from proposals)

AGENTS (7)
  ├── implementation-planner (task decomposition)
  ├── test-runner (quality commands)
  ├── code-reviewer (quality + security)
  ├── convention-checker (git conventions)
  ├── security-reviewer (OWASP, secrets, auth)
  ├── error-handler-inspector (error handling analysis)
  └── integration-verifier (integration validation)

COMMANDS (15)
  ├── flow (universal dispatcher)
  ├── start, commit, pr
  ├── review, address
  ├── merge, release
  ├── status, learn
  ├── setup, explain
  └── brainstorm, debug, design

HOOKS (10 scripts)
  ├── Safety: block-force-push, block-destructive, block-secrets
  ├── Gates: gate-merge, gate-release
  ├── Audit: log-file-changes, log-commits
  └── Experimental: verify-task-completion, nudge-idle-teammate, session-end-learn
```

## Commands

| Command | Purpose |
|---------|---------|
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

## Safety Model

Three-tier action classification:

| Tier | Actions | Behavior |
|------|---------|----------|
| **Tier 1** (Autonomous) | Commits, branches, edits | Execute without asking |
| **Tier 2** (Journal) | Push, PR creation | Execute and log |
| **Tier 3** (Confirm) | Merge, release | Always ask |

Hooks provide structural enforcement — they block dangerous operations even if command logic fails.

## Agent Teams (Opt-In)

Enable with `"agentTeams": true` in settings. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

When enabled, `/flow review` spawns an adversarial review team where independent reviewers challenge each other's findings. Falls back to single-session mode gracefully.

## Learning Loop

Flow captures development decisions in a journal (`.decisions/`) and analyzes them for patterns:

1. **During work**: PostToolUse hooks auto-log file changes and commits
2. **After work**: `/flow learn` identifies recurring patterns
3. **Proposals**: Generates skill proposals in `~/.claude/flow-proposals/`
4. **Promotion**: Human reviews and promotes proposals to active skills

## Configuration

Settings in `.claude/settings.flow.json`:

```json
{
  "agentTeams": false,
  "tiers": { "push": "journal", "merge": "confirm", "release": "confirm" },
  "conventions": { "commitTypes": ["feat", "fix", "docs", "..."] },
  "merge": { "strategy": "squash", "deleteBranch": true },
  "learning": { "enabled": true },
  "visualVerification": { "enabled": false, "screenshotOnVerify": true },
  "debugging": { "maxIterations": 5, "rootCauseFirst": true },
  "testing": { "tddMode": false, "parallelExecution": true }
}
```

See `schema.json` for full configuration reference.

## Comparison with gh-workflow

| Aspect | gh-workflow | flow |
|--------|------------|------|
| Paradigm | Command-driven | Skill-driven |
| Interaction | ~40 decision points | Autonomous with journal |
| Learning | None across sessions | Decision journal + skill proposals |
| Review | Sequential agents | Parallel + adversarial (team option) |
| Safety | Interactive gates | Hook-enforced tiers |
| Knowledge | Locked in commands | Composable, reusable skills |

## License

MIT
