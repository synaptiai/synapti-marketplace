# Flow: Skill-Driven Workflow Plugin

A Claude Code plugin that replaces command-driven GitHub workflow automation with a skill-driven, agent-team-powered approach. Skills encode reusable team knowledge — policy, philosophy, and rationale — as reference documents that compound across sessions; commands carry the executable bash that runs at workflow time.

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
| `fixForwardMaxIterations` | `2` | `10` |
| `reviewCycleLimit` | `3` | `10` |
| `autonomous` | _(new)_ | `false` |
| `minimalScope` | _(new)_ | `false` |

### LLM Operator Principles (v2.4)

Flow v2.4 introduces the `llm-operator-principles` foundational skill that frames Claude as an LLM operator that does not tire. This skill is consulted by every `/flow:*` command and shifts default behavior in three ways:

1. **Convergence = zero findings, not exhausted budget.** Iteration ceilings (`fixForwardMaxIterations`, `reviewCycleLimit`) defaulted to 10 because the ceiling is a safety net against true infinite loops, not a planned stop point. Approaching the ceiling without convergence is a signal to re-check understanding, not to escalate.
2. **In-PR fix by default for all findings.** P1/P2/P3 findings are fixed in the current PR. Finding triage is NEVER a valid escalation trigger — escalations are reserved for true product/architecture/irreversible-action decisions. Default mode does NOT create follow-up issues; cosmetic P3 in untouched files is fix-if-bounded or document inline.
3. **Calendar-time estimates prohibited.** PR bodies, decision-journal entries, escalations, and resolution comments MUST NOT include weeks/days/hours/sprints/ETAs. The old escalation "Time sensitivity" field is replaced by a "Blocking?" field with yes/soft/no values.

See [`skills/llm-operator-principles/SKILL.md`](skills/llm-operator-principles/SKILL.md) for the full operating frame.

### Modes

Two opt-in modes complement the LLM-operator defaults:

- `autonomous: true` — removes `AskUserQuestion` interruptions for any decision the agent can resolve under the operator principles. Reserves `AskUserQuestion` for Tier 3 confirmations (merge, release) and true product/architecture decisions. Recommended for sole-maintainer repositories.
- `minimalScope: true` — restores the original follow-up-issue workflow for cosmetic P3 in untouched files only. Use when scope is deliberately constrained (e.g., a one-line hotfix that should not expand into a refactor). P1/P2 findings still fix in-PR even in this mode.

Both can be toggled in settings or in-conversation ("autonomous mode on", "minimal scope on").

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
  },
  "fixForwardMaxIterations": 2,
  "reviewCycleLimit": 3,
  "minimalScope": true
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
- (v2.4) `llm-operator-principles` skill introduced; iteration ceilings raised to 10; follow-up-issue workflow now opt-in via `minimalScope`; calendar-time estimates prohibited; escalation "Time sensitivity" field renamed to "Blocking?"

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
SKILL LIBRARY (25 skills)
  ├── Foundation (always loaded, stable shape)
  │   ├── llm-operator-principles (operator stance — convergence, anti-deferral, anti-estimation)
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
      ├── specification-capture (non-goals, failure modes, interface contracts)
      ├── code-review-methodology
      ├── criterion-verification-map
      ├── pr-lifecycle
      ├── preflight-checks
      ├── feedback-resolution
      ├── holdout-validation
      ├── merge-and-release
      ├── merge-conflict-resolution
      ├── runtime-verification (build, dev server, smoke, E2E, LSP diagnostics)
      ├── visual-verification (screenshot-analyze-verify loop, responsive checks)
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

HOOKS (8 scripts)
  ├── Safety: block-force-push, block-destructive, block-secrets
  ├── Audit: log-file-changes, log-commits
  └── Experimental: verify-task-completion, nudge-idle-teammate, session-end-learn

  Note: merge/release confirmation gates run at the COMMAND level via
  AskUserQuestion (see references/three-tier-safety.md), not as hooks.

BIN/ HELPER SCRIPTS
  ├── flow-escalate.sh      — formats canonical six-field escalation prompts (CLI utility)
  ├── validate-skill-input.sh — validates skill inputs against JSON Schemas in plugins/flow/schemas/
  ├── journal-record.sh     — atomically updates the YAML manifest in .decisions/issue-{N}.md
  └── promote-proposal.sh   — promotes /flow:learn proposals to learned skills via draft PR

SCHEMAS/ (ship inside the plugin payload, available at runtime)
  └── schemas/<skill>/input-schema.json — JSON Schema Draft-07 input contract per skill

TESTS (repo-level, exercised by every PR series — not part of the plugin install)
  ├── tests/issue-86/                  — FLOW_REVIEW_CYCLE marker parser fixtures
  ├── tests/skills/*/                  — fixtures (valid-input.json, invalid-input.json) + test.sh per skill
  ├── tests/finding-schema/            — canonical finding row validator + fixtures
  ├── tests/status-parser/             — status.md ↔ merge.md ledger parser parity
  └── tests/journal-orchestration/     — full bin/journal-record.sh lifecycle (synthetic issue)
```

### Hook Compatibility

| Event | Wired Script | Min. Claude Code | Notes |
|-------|--------------|------------------|-------|
| `PreToolUse` (Bash) | `block-force-push`, `block-destructive`, `block-secrets` | All current | Documented event |
| `PostToolUse` (Edit\|Write) | `log-file-changes` | All current | Documented event |
| `PostToolUse` (Bash) | `log-commits` | All current | Documented event |
| `SessionEnd` | `session-end-learn` | All current | Documented event |
| `TaskCompleted` | `verify-task-completion` | **v2.1.33+** | See note below |
| `TeammateIdle` | `nudge-idle-teammate` | **v2.1.33+** | See note below |

`TaskCompleted` and `TeammateIdle` were introduced alongside agent-team support in Claude Code v2.1.33 and are not currently listed in the public hooks documentation. The events DO fire today; the JSON payload schema for both is undocumented, so the hooks treat their expected fields (`.task.subject`, `.task.description`, `.teammate.id`, `.idle_seconds`) as best-effort and exit 0 silently when those fields are absent rather than blocking on schema drift. The `v2.1.33+` floor only matters for installs running an older Claude Code build.

### Required Skills vs Skill() invocation convention

Commands declare their skill dependencies in two complementary ways:

- **`## Required Skills`** (declarative) — skills that inform the WHOLE command. Loaded as context at the start, applied throughout. Example: `code-review-methodology` for `/flow:review`.
- **`Skill(X)`** (imperative) — explicit forks at specific phase boundaries where the command hands off to a skill for a discrete sub-task. Example: `Skill(capability-discovery)` invoked once during Phase 1 detection.

Rules:

1. Every command either has a `## Required Skills` section, or an explicit `_None — {reason}_` marker so the absence is intentional.
2. Every `Skill(X)` invocation in a command body must resolve cleanly: `X` MUST also appear in that command's `## Required Skills` list. Invocation is a phase-specific call; the Required Skills list is the canonical dependency manifest, so all skill dependencies are visible in one place.
3. A skill listed as Required does NOT need an explicit `Skill()` invocation — the command operates with it loaded as ambient context.
4. Read-only / dispatcher commands (`status`, `learn`, `explain`, `flow`) typically have no domain skills and use the `_None_` marker.

When auditing: grep for `Skill(` in command bodies and confirm each name appears in Required Skills.

## Canonical Reference Documents

The plugin ships three canonical reference documents (under `plugins/flow/references/`) that are the single source of truth for cross-cutting contracts. Every command and agent that touches these contracts cites the relevant document instead of duplicating it inline:

| Reference | What it canonicalizes | Primary consumers |
|---|---|---|
| [`finding-schema.md`](references/finding-schema.md) | Reviewer output: 6-field row shape (ID, Category, Location, Problem, Suggested Fix, Confidence) plus the marker-only `status` and `disposition` fields. Compatible with the existing `FLOW_REVIEW_CYCLE` 7-field marker schema. | All 4 reviewer agents (`code-reviewer`, `security-reviewer`, `error-handler-inspector`, `integration-verifier`); orchestrators (`commands/review.md`, `commands/pr.md`, `commands/address.md`) |
| [`escalation-format.md`](references/escalation-format.md) | Six-field Proactive-Autonomy escalation structure (Situation, What I tried, Options, Recommendation, Blocking?, Risk). Delivered via `AskUserQuestion`, never inline text. | All 6 escalating commands (`start`, `pr`, `merge`, `commit`, `address`, `resolve`); reviewer agents that surface NEEDS-HUMAN-REVIEW |
| [`evidence-bundle-format.md`](references/evidence-bundle-format.md) | Markdown shape verdict-judge consumes: per-criterion sections with mandatory `### Does NOT promise` plus three completeness subsections. `none` is a valid positive-statement answer; bare blank triggers auto-FAIL. | `commands/start.md` Phase 4 (producer), `agents/verdict-judge.md` Step 1 (consumer); `criterion-verification-map` skill (plan-time inputs) |

Plus the existing references documenting policy, parser rules, and configuration:

- [`finding-ledger-parser.md`](references/finding-ledger-parser.md) — `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE` marker grammar
- [`gate-configuration.md`](references/gate-configuration.md) — the eight quality gates flow enforces
- [`decision-journal-schema.md`](references/decision-journal-schema.md) — `.decisions/` file format
- [`three-tier-safety.md`](references/three-tier-safety.md) — Tier 1/2/3 action classification
- [`skill-manifests.md`](references/skill-manifests.md) — command → required-skill mapping (kept in lockstep with command files)
- [`test-review-checklist.md`](references/test-review-checklist.md), [`code-review-checklist.md`](references/code-review-checklist.md) — runnable checklists for review facets
- [`classification-signals.md`](references/classification-signals.md) — `change-classification` skill heuristics

## Tier Classification (every command)

Every command in `plugins/flow/commands/` ships with a `## Tier Classification` section at the bottom listing the actions it takes and the tier (1 / 2 / 3) for each. The tier vocabulary:

| Tier | Behavior |
|---|---|
| 1 (Autonomous) | File edits, branches, commits — execute without asking |
| 2 (Journal) | Push, PR creation, posting reviews / resolution comments — execute and log |
| 3 (Confirm) | Merge, release — always ask via `AskUserQuestion` |

Per-command tier tables make the safety boundary explicit at the point of use. Reviewers can audit a command's behavior without reading the full prose; users can see what a command will do before invoking it. Verification: `grep -L "^## Tier Classification" plugins/flow/commands/*.md` returns nothing.

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

Settings cascade in priority order; later layers override earlier ones:

1. `plugins/flow/settings.json` — plugin defaults
2. `~/.claude/settings.flow.json` — user defaults
3. `.claude/settings.flow.json` — project settings (committed)
4. `.claude/settings.flow.local.json` — local overrides (gitignored, highest priority)

Example project settings in `.claude/settings.flow.json`:

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
