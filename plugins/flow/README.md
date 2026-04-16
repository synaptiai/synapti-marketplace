# Flow: Skill-Driven Workflow Plugin

A Claude Code plugin that replaces command-driven GitHub workflow automation with a skill-driven, agent-team-powered approach. Skills encode reusable team knowledge that compounds across sessions.

## Excellence Principles

Flow v2.0 enforces six guiding principles that shift the quality bar from "good enough" to "provably correct." These principles emerged from observed failure patterns in agent-driven development and are now structural defaults.

### 1. Stranger Test

Every plan must be executable by someone with zero prior context. If an instruction requires unstated assumptions, implicit knowledge, or "you know what I mean" reasoning, it fails the Stranger Test and the PLAN phase blocks until rewritten.

### 2. Spec-as-Eval-Suite

Acceptance criteria are not documentation -- they are the eval suite. Each criterion must have a concrete, automated verification command defined before the PLAN phase begins. Vague criteria like "works correctly" are rejected by the Spec Validation Gate.

### 3. Proactive Autonomy

Agents resolve ambiguity themselves first. When escalation is unavoidable, it follows a structured six-field format (context, options considered, tradeoffs, recommendation, risk of inaction, decision needed) -- never open-ended questions. Anti-patterns like "what should I do?" are blocked.

### 4. Quality > Speed

TDD mode defaults to `enforce`, meaning tests must exist and pass before task completion. The verdict judge requires all acceptance criteria to pass (`verdict.requireAllPass: true`). P3 findings are no longer deferrable -- they must be fixed in the PR or escalated with a Proactive Autonomy structure.

### 5. No Lazy Verification

Evidence bundles must include "What was NOT tested," "Known limitations," and "Negative/adversarial cases" for every criterion. The missing-criterion scan (verdict-judge Step 1) checks that every acceptance criterion has evidence before evaluation begins. Holdout validation cross-references self-review claims against actual file state.

### 6. No Incomplete Shipments

Pre-existing findings in touched files keep their natural priority (no longer capped at P3). The finding-ledger merge gate blocks merges when `FLOW_RESOLUTION_CYCLE` markers contain unresolved or escalated items. "DEFERRED" markers have been renamed to "ESCALATED" to signal that deferral is not an option.

### Strict Defaults

| Setting | Old Default | New Default |
|---------|-------------|-------------|
| `testing.tddMode` | `"suggest"` | `"enforce"` |
| `verdict.requireAllPass` | `false` | `true` |

### Opting Out

Teams not ready for strict defaults can restore previous behavior:

```json
{
  "testing": {
    "tddMode": "suggest",
    "tddModeOptOut": true
  },
  "verdict": {
    "requireAllPass": false
  }
}
```

Set these in `.claude/settings.flow.json` or `.claude/settings.flow.local.json`.

### What Changed (Summary)

- Pre-existing findings keep natural priority instead of being capped at P3
- P3 findings are fix-or-escalate, no longer deferrable
- Merge gate blocks on unresolved findings in `FLOW_RESOLUTION_CYCLE` markers
- Plans must pass the Stranger Test before exiting PLAN phase
- Evidence bundles require completeness subsections (not tested, limitations, adversarial cases)
- Holdout validation runs inline during VERIFY, review, and address phases
- Spec Validation Gate requires automated verification commands for every acceptance criterion

See [gate-configuration.md](references/gate-configuration.md) for full gate details.

## Quick Start

```bash
# Install the plugin
claude plugins add ./plugins/flow

# Initialize for your repository
/flow:setup

# Start working on an issue
/flow:start 42
```

## Architecture

```
SKILL LIBRARY (22 skills)
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
      ├── capability-discovery (+ LSP probing)
      ├── code-review-methodology
      ├── criterion-verification-map
      ├── pr-lifecycle
      ├── preflight-checks
      ├── feedback-resolution
      ├── holdout-validation
      ├── merge-and-release
      ├── merge-conflict-resolution
      ├── runtime-verification
      ├── team-coordination
      ├── architecture-patterns
      ├── brainstorming
      ├── debugging-patterns
      ├── tdd-patterns
      └── learned/ (promoted from proposals)

AGENTS (8)
  ├── implementation-planner (task decomposition)
  ├── test-runner (quality commands)
  ├── code-reviewer (quality + security + LSP references)
  ├── convention-checker (git conventions)
  ├── security-reviewer (OWASP, secrets, auth)
  ├── error-handler-inspector (error handling + LSP diagnostics)
  ├── integration-verifier (integration validation)
  └── verdict-judge (independent acceptance criteria evaluation)

COMMANDS (17)
  ├── flow (universal dispatcher)
  ├── start, commit, pr, issue
  ├── review, address
  ├── merge, release, resolve
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
| `/flow:start <issue>` | Assign issue, create branch, decompose tasks, implement |
| `/flow:commit` | Classify changes, flag anomalies, create atomic commits |
| `/flow:pr` | Full review pipeline + PR creation |
| `/flow:review <pr>` | Multi-faceted code review (single or team) |
| `/flow:address <pr>` | Systematic feedback resolution |
| `/flow:merge <pr>` | Merge with prerequisite verification (Tier 3) |
| `/flow:release <type>` | Changelog + semantic version release (Tier 3) |
| `/flow:status` | Read-only workflow overview |
| `/flow:learn` | Analyze decision patterns, propose new skills |
| `/flow:setup` | Initialize flow for a repository |
| `/flow:explain` | Interactive Q&A about decisions |
| `/flow:issue [topic]` | Create well-crafted GitHub issues |
| `/flow:brainstorm [topic]` | Explore approaches before implementation |
| `/flow:debug [error]` | Structured debugging with root cause analysis |
| `/flow:design [feature]` | Architecture discussion and design validation |

## Safety Model

Three-tier action classification:

| Tier | Actions | Behavior |
|------|---------|----------|
| **Tier 1** (Autonomous) | Commits, branches, edits | Execute without asking |
| **Tier 2** (Journal) | Push, PR creation | Execute and log |
| **Tier 3** (Confirm) | Merge, release | Always ask |

Hooks provide structural enforcement — they block dangerous operations even if command logic fails.

## LSP Code Intelligence

When LSP servers are available, Flow leverages language server capabilities across workflow phases:

| Phase | LSP Feature | Benefit |
|-------|------------|---------|
| **EXPLORE** | `goToDefinition`, `findReferences` | Semantic code path tracing and impact analysis |
| **CODE** | `hover` | Type info and signatures for existing code |
| **VERIFY** | Diagnostics | Errors→P1, warnings→P2 as complementary quality signals |
| **REVIEW** | `findReferences`, `incomingCalls` | Verify all callers of modified functions are handled |

LSP is additive — all phases fall back to grep/CLI-based analysis when no LSP server is configured. Configure via `lsp.enabled`, `lsp.timeout`, and `lsp.diagnosticsAsQuality` in settings.

## Agent Teams (Opt-In)

Enable with `"agentTeams": true` in settings. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

When enabled, `/flow:review` spawns an adversarial review team where independent reviewers challenge each other's findings. Falls back to single-session mode gracefully.

## Learning Loop

Flow captures development decisions in a journal (`.decisions/`) and analyzes them for patterns:

1. **During work**: PostToolUse hooks auto-log file changes and commits
2. **After work**: `/flow:learn` identifies recurring patterns
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
  "lsp": { "enabled": true, "timeout": 5000, "diagnosticsAsQuality": true },
  "visualVerification": { "enabled": true, "screenshotDir": ".screenshots", "maxIterations": 3 },
  "debugging": { "maxHypotheses": 3 },
  "testing": { "tddMode": "enforce", "tddModeOptOut": false },
  "verdict": { "requireAllPass": true }
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
