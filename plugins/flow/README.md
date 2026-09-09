# Flow: Skill-Driven Workflow Plugin

A Claude Code plugin that replaces command-driven GitHub workflow automation with a skill-driven, agent-team-powered approach. Skills encode reusable team knowledge — policy, philosophy, and rationale — as reference documents that compound across sessions; commands carry the executable bash that runs at workflow time.

## Flow v3 Runtime Layer (new in 3.0.0)

Flow v3 introduces a **runtime layer** at `.flow/` on top of the existing skill + command framework. Six new primitives give the plugin durable goals, inspectable workflows, declarative triggers, and resumable execution:

- **FlowGoal** — `.flow/goals/<id>.goal.yaml`, durable completion contracts (`/flow:goal status | create | inspect | evaluate | pause | resume | clear`).
- **FlowWorkflow** — `plugins/flow/workflows/*.workflow.yaml`, machine-readable process contracts for every `/flow:*` command (`/flow:workflow list | inspect | validate | graph`).
- **FlowTrigger** — `.flow/triggers/<id>.trigger.yaml`, wake-up intent contracts (`/flow:trigger`, `/flow:watch`, `/flow:run`). v3.0 supports `manual | hook | loop_prompt`.
- **FlowRun + FlowActivity** — `.flow/runs/<ISO-id>/`, durable execution ledger (`/flow:resume`).
- **FlowEvidence** — `.evidence.yaml` sidecars proving acceptance criteria.

Flow does NOT invoke native Claude Code `/goal` or `/loop` — those are session-only built-ins and not exposed to plugins. Flow implements its own file-backed goal layer and uses Stop hooks for post-turn enforcement. The `/flow:watch` command generates a `/loop` prompt file the user invokes manually.

**Goals are invisible-by-default**: `flow.goals.goalCreation` defaults to `auto`, so `/flow:start` records a FlowGoal whenever the issue has ≥1 acceptance criterion carrying a `verification_command` — no consent prompt (the v3.0 onboarding `AskUserQuestion` was retired in v3.1). Issues with zero verifiable ACs (e.g. spec-free `documentation`/`chore`) create no goal, silently. Set `goalCreation: off` to suppress auto-creation, or `flow.goals.enabled: false` to disable the feature. The deprecated `requireGoalForStart` is migrated read-only (`true`→`always`, `false`→`off`). See `references/migration-v2-to-v3.md`.

### Get started with v3

- [`references/flow-goals-quickstart.md`](references/flow-goals-quickstart.md) — 5-minute Hello-FlowGoal walkthrough (synthetic issue → goal → evaluate → verdict)
- [`references/migration-v2-to-v3.md`](references/migration-v2-to-v3.md) — step-by-step v2 → v3 opt-in (four independent flags)

Other v3 references:
- [`references/flow-goals.md`](references/flow-goals.md) — FlowGoal model
- [`references/flow-runtime-state.md`](references/flow-runtime-state.md) — `.flow/` directory layout
- [`references/flow-workflows.md`](references/flow-workflows.md) — FlowWorkflow contracts
- [`references/flow-triggers.md`](references/flow-triggers.md) — FlowTrigger model
- [`references/stop-hook-goal-enforcement.md`](references/stop-hook-goal-enforcement.md) — Stop hook architecture

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

### 7. Rules in the Room, Checked by Machine (3.3.0)

Two findings shaped 3.3.0. An audit of 43 sessions showed flow's rules were written but not in context when they were broken, and the hooks that could enforce them warned or exited 0. Dan Luu's "Agentic testing" study showed that naming a testing technique produces its surface, not its value: TDD instructions doubled test count and lowered correctness because agents fed identical or palindromic inputs and pasted the implementation's own output in as the expected value. The response is structural:

- Every command inlines its Required Skills at invocation (`bin/flow-load-skills.sh`); skill bodies are capped at 600 words so the load is affordable.
- The TaskCompleted hook blocks while edits postdate the last passing quality run; `gh issue create` asks during an active goal; the Stop hook says plainly when a stop was allowed.
- Specifications carry a risk map (where the logic is most likely to be subtly wrong, what the plausible wrong version does, and a check that tells them apart). Expected values must state their source; degenerate inputs do not count as coverage. The verdict judge sees test inputs and expected values, never the implementation.
- `/flow:learn` reads session transcripts, where corrections actually live.
- A headless correctness eval (`references/correctness-eval.md`) measures the TDD and risk-map settings on seeded-bug tasks with hidden tests instead of assuming.

### Strict Defaults

| Setting | Old Default | New Default |
|---------|-------------|-------------|
| `testing.tddMode` | `"suggest"` | `"enforce"` |
| `verdict.requireAllPass` | `false` | `true` |
| `fixForwardMaxIterations` | `2` | `10` |
| `reviewCycleLimit` | `3` | `10` |
| `autonomous` | _(new)_ | `false` |
| `minimalScope` | _(new)_ | `false` |
| `testing.taskCompletionGate` | _(new, 3.3.0)_ | `"block"` |
| `specFirst.riskMap` | _(new, 3.3.0)_ | `true` |
| `learning.sources` | _(new, 3.3.0)_ | `["journal", "transcripts"]` |

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
SKILL LIBRARY (33 skills, every body <= 600 words)
  ├── Ambient (no context: fork / agent:) — inlined WHOLE into a command's prompt
  │   │                                    when the command lists them as Required
  │   ├── llm-operator-principles (operator stance — convergence, anti-deferral, anti-estimation)
  │   ├── evidence-based-development
  │   ├── autonomous-workflow
  │   └── code-quality-principles
  │
  └── Dispatched (context: fork / agent:) — their `## Contract` (<= 120 words) is
      │                                    inlined; the body runs via Skill(<name>)
      ├── issue-crafting
      ├── branch-and-task-management
      ├── change-classification
      ├── convention-enforcement
      ├── capability-discovery (+ LSP probing)
      ├── specification-capture (non-goals, failure modes, interface contracts, risk map)
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

COMMANDS (23)
  Work / intent (17) — the commands you drive:
  ├── flow (universal dispatcher)
  ├── start, commit, pr, issue
  ├── review, address
  ├── merge, release, resolve
  ├── status, learn
  ├── setup, explain
  └── brainstorm, debug, design
  Runtime / admin (6) — inspect & debug the layer Flow manages for you:
  └── goal, workflow, trigger, run, resume, watch

HOOKS (14 scripts)
  ├── Safety (PreToolUse): block-force-push, block-destructive, block-secrets,
  │                        ask-issue-create (asks before `gh issue create` during an active goal)
  ├── Ledger (PostToolUse): log-file-changes, log-commits, record-quality-run
  ├── Gates: verify-task-completion (TaskCompleted — blocks while edits postdate the last
  │          passing quality run), flow-goal-stop + flow-run-deterministic-checks +
  │          flow-goal-evaluator (Stop — FlowGoal evidence)
  └── Session: session-end-learn, session-end-state, nudge-idle-teammate

  Note: merge/release confirmation gates run at the COMMAND level via
  AskUserQuestion (see references/three-tier-safety.md), not as hooks.

BIN/ HELPER SCRIPTS
  ├── flow-load-skills.sh   — inlines a command's Required Skills (ambient bodies, dispatched contracts)
  ├── flow-quality-ledger.sh — per-session ledger of file edits and quality-command runs (task-completion gate)
  ├── flow-goal-trust.sh    — user-local trust ledger: which FlowGoals may auto-run verification commands
  ├── flow-mine-corrections.sh — mines user corrections from session transcripts for /flow:learn
  ├── flow-eval-run.sh      — headless correctness eval (seeded-bug tasks, hidden tests; references/correctness-eval.md)
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
| `PreToolUse` (Bash) | `block-force-push`, `block-destructive`, `block-secrets`, `ask-issue-create` | All current | Documented event. `ask-issue-create` returns `permissionDecision: ask` (documented JSON contract) only for `gh issue create` while a FlowGoal is active and `minimalScope` is false |
| `PostToolUse` (Edit\|Write) | `log-file-changes` | All current | Documented event; also appends a `file_change` entry to the session quality ledger |
| `PostToolUse` (Bash) | `log-commits`, `record-quality-run` | All current | Documented event; `record-quality-run` classifies test/lint/typecheck/build commands and records `tool_response.exit_code` |
| `Stop` | `flow-goal-stop` | All current | Documented event. Ships in `warn` mode: the reason says plainly that the stop was ALLOWED; `block` mode is opt-in and executes verification commands only for goals in the user-local trust ledger |
| `SessionEnd` | `session-end-learn`, `session-end-state` | All current | Documented event |
| `TaskCompleted` | `verify-task-completion` | **v2.1.33+** | Documented event (`task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name`). Exit 2 blocks completion while files changed after the last passing quality run; `testing.taskCompletionGate` selects `block\|warn\|off` |
| `TeammateIdle` | `nudge-idle-teammate` | **v2.1.33+** | Payload fields still treated as best-effort |

`TaskCompleted` and `TeammateIdle` were introduced alongside agent-team support in Claude Code v2.1.33. The TaskCompleted payload is now documented (https://code.claude.com/docs/en/hooks) and `verify-task-completion.sh` reads the documented `task_subject` / `task_description` fields, falling back to the legacy `.task.subject` shape. `TeammateIdle` fields (`.teammate.id`, `.idle_seconds`) remain best-effort: the hook exits 0 silently when they are absent. The `v2.1.33+` floor only matters for installs running an older Claude Code build.

### Required Skills: loaded by the command, not by the agent

Claude Code commands cannot preload skills from frontmatter (only agents have `skills:`), so until 3.3.0 a command's `## Required Skills` section was a reading list the agent might or might not open mid-run. An audit of 43 sessions found the skill carrying the most-broken rule loaded once in twenty-four chances. Every command with Required Skills now carries a `!` block right under the list that calls `bin/flow-load-skills.sh <names...>`; Claude Code pre-executes it and injects the output, so the rules are in context before Phase 0.

Two loading modes, decided from each skill's frontmatter:

- **Ambient** (no `context: fork`, no `agent:`) — the whole body is inlined. These are stance skills that apply throughout (`llm-operator-principles`, `evidence-based-development`, `autonomous-workflow`, `code-quality-principles`).
- **Dispatched** (`context: fork` or `agent:`) — only the skill's `## Contract` section is inlined (its first H2, at most 120 words: iron law, invoking phase, return shape, permitted skips). The body runs in full when the command invokes `Skill(<name>)`.

Rules, enforced by `tests/flow-load-skills.test.sh`:

1. Every command either has `## Required Skills` bullets plus the loader block, or an explicit `_None — {reason}_` marker and no loader block.
2. The loader block's names equal the bullet list exactly. Every `Skill(X)` invocation in the body must name a Required Skill.
3. Every dispatched skill has `## Contract` as its first H2, at most 120 words. Every skill body is at most 600 words; long tables live under `references/` and are linked.
4. Read-only / dispatcher commands (`status`, `learn`, `explain`, `flow`) use the `_None_` marker.

`references/skill-manifests.md` lists what each command loads and how many words that costs.

## Canonical Reference Documents

The plugin ships three canonical reference documents (under `plugins/flow/references/`) that are the single source of truth for cross-cutting contracts. Every command and agent that touches these contracts cites the relevant document instead of duplicating it inline:

| Reference | What it canonicalizes | Primary consumers |
|---|---|---|
| [`finding-schema.md`](references/finding-schema.md) | Reviewer output: 6-field finding data model (id, category, location, problem, suggested_fix, confidence) rendered as a two-column table (`Finding` and `Suggested Fix` columns) for legibility in GitHub's narrow PR-comment column, plus the marker-only `status` and `disposition` fields. Compatible with the existing `FLOW_REVIEW_CYCLE` 7-field marker schema. | All 4 reviewer agents (`code-reviewer`, `security-reviewer`, `error-handler-inspector`, `integration-verifier`); orchestrators (`commands/review.md`, `commands/pr.md`, `commands/address.md`) |
| [`escalation-format.md`](references/escalation-format.md) | Six-field Proactive-Autonomy escalation structure (Situation, What I tried, Options, Recommendation, Blocking?, Risk). Delivered via `AskUserQuestion`, never inline text. | All 6 escalating commands (`start`, `pr`, `merge`, `commit`, `address`, `resolve`); reviewer agents that surface NEEDS-HUMAN-REVIEW |
| [`evidence-bundle-format.md`](references/evidence-bundle-format.md) | Markdown shape verdict-judge consumes: per-criterion sections with mandatory `### Does NOT promise` plus three completeness subsections. `none` is a valid positive-statement answer; bare blank triggers auto-FAIL. | `commands/start.md` Phase 4 (producer), `agents/verdict-judge.md` Step 1 (consumer); `criterion-verification-map` skill (plan-time inputs) |

Plus the existing references documenting policy, parser rules, and configuration:

- [`finding-ledger-parser.md`](references/finding-ledger-parser.md) — `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE` marker grammar
- [`gate-configuration.md`](references/gate-configuration.md) — the ten quality gates flow enforces
- [`decision-journal-schema.md`](references/decision-journal-schema.md) — `.decisions/` file format
- [`three-tier-safety.md`](references/three-tier-safety.md) — Tier 1/2/3 action classification
- [`skill-manifests.md`](references/skill-manifests.md) — command → required-skill mapping (kept in lockstep with command files)
- [`test-review-checklist.md`](references/test-review-checklist.md), [`code-review-checklist.md`](references/code-review-checklist.md) — runnable checklists for review facets
- [`classification-signals.md`](references/classification-signals.md) — `change-classification` skill heuristics
- [`review-cycle-parsing.md`](references/review-cycle-parsing.md), [`holdout-lens-dispositions.md`](references/holdout-lens-dispositions.md), [`paired-review-protocol.md`](references/paired-review-protocol.md) — cycle-marker parsing for reviewers; Path A lens stances, holdout marker dispositions, and the full paired-review protocol tables
- [`correctness-eval.md`](references/correctness-eval.md) — the headless correctness eval (seeded-bug tasks, hidden tests) that measures the TDD and risk-map settings

## Tier Classification (every command)

Every command in `plugins/flow/commands/` ships with a `## Tier Classification` section at the bottom listing the actions it takes and the tier (1 / 2 / 3) for each. The tier vocabulary:

| Tier | Behavior |
|---|---|
| 1 (Autonomous) | File edits, branches, commits — execute without asking |
| 2 (Journal) | Push, PR creation, posting reviews / resolution comments — execute and log |
| 3 (Confirm) | Merge, release — always ask via `AskUserQuestion` |

Per-command tier tables make the safety boundary explicit at the point of use. Reviewers can audit a command's behavior without reading the full prose; users can see what a command will do before invoking it. Verification: `grep -L "^## Tier Classification" plugins/flow/commands/*.md` returns nothing.

## Commands

**You work in outcomes; Flow manages the runtime.** `/flow:start` creates a goal, selects a workflow, records evidence, and prevents premature completion — you inspect it with `/flow:status`, you don't manage it by hand. Reach for the intent commands below; the runtime primitives (`goal`, `workflow`, `trigger`, `run`, `resume`, `watch`) are admin/debug surface documented under [Advanced / runtime internals](#advanced--runtime-internals).

### Work (intent) commands

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

### Advanced / runtime internals

These commands expose the v3 runtime layer Flow normally manages for you. You rarely invoke them directly — the intent commands above create and advance goals, workflows, runs, and evidence automatically. Reach for these to inspect, debug, or hand-drive the runtime.

| Command | Purpose |
|---------|---------|
| `/flow:goal` | Inspect/evaluate FlowGoals. **`/flow:goal create` is the `--manual` path** — the normal way a goal is created is automatically by `/flow:start` (`goalCreation: auto`), not by hand. |
| `/flow:workflow` | Inspect workflow definitions and phase/activity state |
| `/flow:trigger` | Manage FlowTriggers (opt-in automation; `flow.triggers.enabled`) |
| `/flow:run` | Inspect FlowRun records and their event ledgers |
| `/flow:resume` | Read an interrupted run and propose the next safe action (informational-only) |
| `/flow:watch` | Generate a `/loop` prompt file for hands-off iteration (user invokes the loop) |

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

**Model selection.** Because this Path A team dispatches ~20 agents per review, all of which would otherwise inherit the session model, the model is configurable via `agentTeamModel` (default `"sonnet"`; enum `haiku|sonnet|opus|inherit`). It resolves through the same settings cascade as `agentTeams`. Set it to `"inherit"` to run the review agents on the session's model, or `"opus"` for a high-stakes review. This mirrors the `flow.goals.judge.model` pattern and applies to Path A only — Path B (single-session, the default) always inherits the session model.

## Learning Loop

Flow captures development decisions in a journal (`.decisions/`) and, since 3.3.0, also reads the session transcripts where user corrections actually live:

1. **During work**: PostToolUse hooks auto-log file changes and commits
2. **After work**: `/flow:learn` mines the journal and run events (what flow wrote) and, when `learning.sources` includes `transcripts`, the user turns in `~/.claude/projects/<project>/*.jsonl` via `bin/flow-mine-corrections.sh` (read-only, local, recall-oriented filter; the judging happens in Phase 2). A pattern counts only with 3+ verified instances across 2+ sessions
3. **Proposals**: Generates skill proposals in `~/.claude/flow-proposals/`. When the rule already exists in a skill, the proposal is an `enforcement` proposal naming the hook or gate that should make it mechanical, not a new skill
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
  "agentTeamModel": "sonnet",
  "tiers": { "push": "journal", "merge": "confirm", "release": "confirm" },
  "conventions": { "commitTypes": ["feat", "fix", "docs", "..."] },
  "merge": { "strategy": "squash", "deleteBranch": true },
  "learning": { "enabled": true },
  "lsp": { "enabled": true, "timeout": 5000, "diagnosticsAsQuality": true },
  "visualVerification": { "enabled": true, "screenshotDir": ".screenshots", "maxIterations": 3 },
  "debugging": { "maxHypotheses": 3 },
  "testing": { "tddMode": "enforce", "tddModeOptOut": false, "taskCompletionGate": "block", "qualityCommandPatterns": [] },
  "specFirst": { "riskMap": true },
  "learning": { "enabled": true, "sources": ["journal", "transcripts"] },
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

Apache-2.0
