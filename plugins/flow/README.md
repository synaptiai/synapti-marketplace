# Flow: Skill-Driven Workflow Plugin

A Claude Code plugin that replaces command-driven GitHub workflow automation with a skill-driven, agent-team-powered approach. Skills encode reusable team knowledge — policy, philosophy, and rationale — as reference documents that compound across sessions; commands carry the executable bash that runs at workflow time.

## Flow Runtime Layer

Flow keeps a **runtime layer** at `.flow/` on top of the skill + command framework. Its primitives give the plugin durable goals, inspectable workflows, declarative triggers, and resumable execution:

- **FlowGoal** — `.flow/goals/<id>.goal.yaml`, durable completion contracts (`/flow:goal status | create | inspect | evaluate | pause | resume | clear`).
- **FlowWorkflow** — `plugins/flow/workflows/*.workflow.yaml`, machine-readable process contracts for every `/flow:*` command (`/flow:workflow list | inspect | validate | graph`).
- **FlowTrigger** — `.flow/triggers/<id>.trigger.yaml`, wake-up intent contracts (`/flow:trigger`, `/flow:watch`, `/flow:run`). Supported types are `manual | hook | loop_prompt`.
- **FlowRun + FlowActivity** — `.flow/runs/<ISO-id>/`, durable execution ledger (`/flow:resume`).
- **FlowEvidence** — `.evidence.yaml` sidecars proving acceptance criteria.

Flow does NOT invoke native Claude Code `/goal` or `/loop` — those are session-only built-ins and not exposed to plugins. Flow implements its own file-backed goal layer and uses Stop hooks for post-turn enforcement. The `/flow:watch` command generates a `/loop` prompt file the user invokes manually.

**Trust ledger.** The Stop hook executes a goal's `verification_command` strings only when the goal is *trusted*: `bin/flow-goal-record.sh --create` records every goal flow creates in `goal-trust.jsonl` in the per-user state directory (`~/.claude/flow-state`, or `FLOW_STATE_DIR` when you set it; see [Per-user locations](#per-user-locations)) (repo, goal id, sha256 of AC ids + commands). A goal that arrived with a checkout is untrusted and its ACs are reported `not_executed` until you run `bin/flow-goal-trust.sh record --goal-file .flow/goals/<id>.goal.yaml`, which is also required after editing a `verification_command` by hand; `flow-goal-trust.sh list` shows the ledger. `flow.goals.executeVerificationCommands: true` still forces execution for every goal. `stopHookEnforcement: warn` (the default) never blocks and says so in its reason and on stderr; `block` keeps the agent working on missing evidence and is capped at `failAfterStuckTurns` consecutive blocks per session and goal. `evaluator-loop` runs a judge each turn and keeps the agent working until the goal is achieved, with two bounds: a goal that makes no progress for `failAfterStuckTurns` consecutive turns (default 3) is moved to `failed`, and a goal that has used up its contract's `continuation.max_iterations` (default 20) is moved to `failed` with reason `budget_exhausted`. A turn that lets the stop through spends none of that budget, so a goal whose checks all pass is never failed on it.

**Goals are invisible-by-default**: `flow.goals.goalCreation` defaults to `auto`, so `/flow:start` records a FlowGoal whenever the issue has ≥1 acceptance criterion carrying a `verification_command`, with no consent prompt. Issues with zero verifiable ACs (e.g. spec-free `documentation`/`chore`) create no goal, silently. Set `goalCreation: off` to suppress auto-creation, or `flow.goals.enabled: false` to disable the feature. The deprecated `requireGoalForStart` is migrated read-only (`true`→`always`, `false`→`off`). See `references/migration-v2-to-v3.md`.

### Get started with the runtime layer

- [`references/flow-goals-quickstart.md`](references/flow-goals-quickstart.md) — 5-minute Hello-FlowGoal walkthrough (synthetic issue → goal → evaluate → verdict)
- [`references/migration-v2-to-v3.md`](references/migration-v2-to-v3.md) — moving a v2 project over, and tuning goals, Stop-hook enforcement, workflows and triggers one setting at a time

Other runtime references:
- [`references/flow-goals.md`](references/flow-goals.md) — FlowGoal model
- [`references/flow-runtime-state.md`](references/flow-runtime-state.md) — `.flow/` directory layout
- [`references/flow-workflows.md`](references/flow-workflows.md) — FlowWorkflow contracts
- [`references/flow-triggers.md`](references/flow-triggers.md) — FlowTrigger model
- [`references/stop-hook-goal-enforcement.md`](references/stop-hook-goal-enforcement.md) — Stop hook architecture

## Excellence Principles

Flow enforces seven guiding principles that set the quality bar at "provably correct" rather than "good enough." They come from observed failure patterns in agent-driven development and are structural defaults.

### 1. Stranger Test

Every plan must be executable by someone with zero prior context. If an instruction requires unstated assumptions, implicit knowledge, or "you know what I mean" reasoning, it fails the Stranger Test and the PLAN phase blocks until rewritten.

### 2. Spec-as-Eval-Suite

Acceptance criteria are not documentation -- they are the eval suite. Each criterion must have a concrete, automated verification command defined before the PLAN phase begins. Vague criteria like "works correctly" are rejected by the Spec Validation Gate.

### 3. Proactive Autonomy

Agents resolve ambiguity themselves first. When escalation is unavoidable, it follows a structured six-field format (Situation, What I tried, Options, Recommendation, Blocking?, Risk), delivered through `AskUserQuestion` -- never open-ended questions. Anti-patterns like "what should I do?" are blocked.

### 4. Quality > Speed

TDD mode defaults to `enforce`, meaning tests must exist and pass before task completion. The verdict judge requires all acceptance criteria to pass (`verdict.requireAllPass: true`). P3 findings are not deferrable -- they are fixed in the PR or escalated with a Proactive Autonomy structure.

### 5. No Lazy Verification

Evidence bundles must include "What was NOT tested," "Known limitations," "Negative/adversarial cases," "Test inputs and expected values," and "Risk map coverage" for every criterion. The missing-criterion scan (verdict-judge Step 1) checks that every acceptance criterion has evidence before evaluation begins. Holdout validation cross-references self-review claims against actual file state.

### 6. No Incomplete Shipments

Pre-existing findings in touched files keep their natural priority; they are not capped at P3. The finding-ledger merge gate blocks merges when `FLOW_RESOLUTION_CYCLE` markers contain unresolved or escalated items. Items that cannot be fixed in the PR are marked "ESCALATED", never "DEFERRED", because deferral is not an option.

### 7. Rules in the Room, Checked by Machine

Two findings shape this principle. An audit of 43 sessions showed flow's rules were written but not in context when they were broken, and the hooks that could enforce them warned or exited 0. Dan Luu's "Agentic testing" study showed that naming a testing technique produces its surface, not its value: TDD instructions doubled test count and lowered correctness because agents fed identical or palindromic inputs and pasted the implementation's own output in as the expected value. The response is structural:

- Every command inlines its Required Skills at invocation (`bin/flow-load-skills.sh`); skill bodies are kept to about 600 words so the load is affordable.
- The TaskCompleted hook blocks while edits postdate the last passing quality run; `gh issue create` asks during an active goal; the Stop hook says plainly when a stop was allowed.
- Specifications carry a risk map (where the logic is most likely to be subtly wrong, what the plausible wrong version does, and a check that tells them apart). Expected values must state their source; degenerate inputs do not count as coverage. The verdict judge sees test inputs and expected values, never the implementation.
- `/flow:learn` reads session transcripts, where corrections actually live.
- A headless correctness eval (`references/correctness-eval.md`) measures the TDD and risk-map settings on seeded-bug tasks with hidden tests instead of assuming.

### Strict Defaults

| Setting | Default | Other values |
|---------|---------|--------------|
| `testing.tddMode` | `"enforce"` | `"suggest"` or `"off"` |
| `verdict.requireAllPass` | `true` | `false` |
| `fixForwardMaxIterations` | `10` | a lower number |
| `reviewCycleLimit` | `10` | a lower number |
| `autonomous` | `false` | `true` |
| `minimalScope` | `false` | `true` |
| `testing.taskCompletionGate` | `"block"` | `"warn"` or `"off"` |
| `specFirst.riskMap` | `true` | `false` |
| `learning.sources` | `["journal", "transcripts"]` | `["journal"]` |

### LLM Operator Principles

The `llm-operator-principles` foundational skill frames Claude as an LLM operator that does not tire. `/flow:start`, `/flow:commit`, `/flow:pr`, `/flow:review`, `/flow:address` and `/flow:merge` load it whole, and it sets default behavior in three ways:

1. **Convergence = zero findings, not exhausted budget.** Iteration ceilings (`fixForwardMaxIterations`, `reviewCycleLimit`) default to 10 because the ceiling is a safety net against true infinite loops, not a planned stop point. Approaching the ceiling without convergence is a signal to re-check understanding, not to escalate.
2. **In-PR fix by default for all findings.** P1/P2/P3 findings are fixed in the current PR. Finding triage is NEVER a valid escalation trigger — escalations are reserved for true product/architecture/irreversible-action decisions. Default mode does NOT create follow-up issues; cosmetic P3 in untouched files is fix-if-bounded or document inline.
3. **Calendar-time estimates prohibited.** PR bodies, decision-journal entries, escalations, and resolution comments MUST NOT include weeks/days/hours/sprints/ETAs. Escalations carry a "Blocking?" field with yes/soft/no values instead of a time-sensitivity field.

See [`skills/llm-operator-principles/SKILL.md`](skills/llm-operator-principles/SKILL.md) for the full operating frame.

### Modes

Two opt-in modes complement the LLM-operator defaults:

- `autonomous: true` — removes `AskUserQuestion` interruptions for any decision the agent can resolve under the operator principles. Reserves `AskUserQuestion` for Tier 3 confirmations (merge, release) and true product/architecture decisions. Recommended for sole-maintainer repositories.
- `minimalScope: true` — offers a follow-up issue, instead of an in-PR fix, for cosmetic P3 in untouched files only. Use when scope is deliberately constrained (e.g., a one-line hotfix that should not expand into a refactor). P1/P2 findings still fix in-PR even in this mode.

Both can be toggled in settings or in-conversation ("autonomous mode on", "minimal scope on").

### Opting Out

Teams not ready for the strict defaults can relax them:

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

See [gate-configuration.md](references/gate-configuration.md) for full gate details.

## Requirements

| Tool | Needed for | If it is missing |
|---|---|---|
| `bash` 3.2 or newer | every command, hook and script | flow does not run. On Windows this means Git Bash, which Git for Windows installs — see [docs/windows-support.md](../../docs/windows-support.md). Without a POSIX shell, Claude Code skips the hooks silently: no journal, no guards, and no error either |
| `git` | branch, commit and diff operations | flow does not run |
| `gh` (GitHub CLI, authenticated) | issues, pull requests, reviews, merges | any command that touches GitHub fails |
| `jq` | reading settings and GitHub JSON | commands fall back to a narrower path or stop |
| `python3` 3.12 to 3.14 with **PyYAML** | the decision journal, FlowRun state, FlowGoal contracts and evidence bundles | those writes are skipped; commands still run, but the history they would have left is lost |
| `python3` with `jsonschema` | strict validation of evidence and skill input against `schemas/` | validation falls back to a narrower structural check |
| `jscpd` (optional) | the duplication scan in review and in `/flow:start`'s per-task gate | the scan reports that it did not run and prints `npm install -g jscpd@5.3.1`; flow never installs it for you |
| `npm audit`, `pip-audit`, `bundle audit` (optional) | advisory lookups for new and bumped dependencies | the review says no advisory audit ran for that ecosystem |

Install the Python packages with the pinned versions flow is tested against:

```bash
# From a clone of the marketplace repository:
python3 -m pip install --user --break-system-packages -r plugins/flow/requirements.txt

# From a marketplace install, where the plugin lives under ~/.claude/plugins:
python3 -m pip install --user --break-system-packages -r "${CLAUDE_PLUGIN_ROOT:?run this from a Claude Code session, or use the clone form above}/requirements.txt"

# Or without the manifest at all — these are the packages and their pins:
python3 -m pip install --user --break-system-packages 'pyyaml==6.0.2' 'jsonschema==4.23.0'
```

PyYAML is the one that is easy to miss, because nothing announces itself when it
is absent. `bin/_journal_atomic.py` is the atomic write path behind
`journal-record.sh`, `flow-record-activity.sh`, `flow-record-evidence.sh`,
`flow-record-verdict.sh` and `flow-goal-record.sh`, and behind the SessionEnd and
Stop hooks. Each of those checks for PyYAML before calling it and exits quietly
when it is not there, so the symptom is an empty `.decisions/` and `.flow/` tree
rather than an error. The symlink check itself (`bin/_repo_dir.py`, used by
`flow-mkdir.sh`) needs no PyYAML, so readers still tell a symlinked `.flow` from
a real one without it. Confirm it with:

```bash
python3 -c "import yaml; print(yaml.__version__)"
```

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
SKILL LIBRARY (32 skills, plus promoted skills under learned/)
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
      ├── goal-contract-capture, goal-evaluator, goal-evidence-ledger, goal-lifecycle (FlowGoal)
      ├── run-state-management (FlowRun)
      ├── trigger-policy (FlowTrigger)
      ├── workflow-validation (FlowWorkflow)
      └── learned/ (promoted from proposals)

AGENTS (10)
  ├── implementation-planner (task decomposition, risk areas per task)
  ├── test-runner (quality commands)
  ├── code-reviewer (quality + security + LSP references)
  ├── convention-checker (git conventions)
  ├── security-reviewer (OWASP, secrets, auth)
  ├── error-handler-inspector (error handling + LSP diagnostics)
  ├── finding-critic (grounding pass: refutes a consolidated finding from the code; read-only)
  ├── integration-verifier (integration validation)
  ├── verdict-judge (independent acceptance criteria evaluation; sees test inputs, never the diff)
  └── goal-evaluator-judge (loop-time verdict for FlowGoals)

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

HOOKS (16 scripts; 14 registered in hooks/hooks.json, the other two run from flow-goal-stop)
  ├── Safety (PreToolUse): block-force-push, block-destructive, block-secrets,
  │                        block-unchecked-merge (refuses `gh pr merge` while checks are
  │                        queued, running or failed), ask-issue-create (asks before
  │                        `gh issue create` during an active goal)
  ├── Ledger (PostToolUse / PostToolUseFailure): log-file-changes, log-commits, record-quality-run
  ├── Gates: verify-task-completion (TaskCompleted — blocks while edits postdate the last
  │          passing quality run), flow-goal-stop + flow-run-deterministic-checks +
  │          flow-goal-evaluator (Stop — FlowGoal evidence)
  ├── Reply style: reply-style-check (Stop — opt-in, warns only)
  └── Session: session-end-learn, session-end-state, nudge-idle-teammate

  Note: merge/release confirmation gates run at the COMMAND level via
  AskUserQuestion (see references/three-tier-safety.md), not as hooks.

BIN/ HELPER SCRIPTS (most print usage with --help)
  Settings and skills
  ├── cascade-resolve.sh    — reads one setting through the settings cascade (see Configuration)
  ├── flow-migrate-settings.sh — upgrades a settings file that still uses a deprecated key (dry-run unless --apply)
  ├── flow-load-skills.sh   — inlines a command's Required Skills (ambient bodies, dispatched contracts)
  └── validate-skill-input.sh — validates skill inputs against the JSON Schemas under schemas/
  Review
  ├── flow-finding-route.sh — routes consolidated findings by confidence and review mode, and builds the marker rows
  ├── flow-review-exceptions.sh — prints the team's review exceptions, read at the pull request's base commit
  ├── flow-contract-files.sh — names the changed files that are contracts (OpenAPI, GraphQL, protobuf, migrations, schemas, goals)
  ├── flow-dep-diff.sh      — lists dependencies added, bumped or removed between two commits, from the manifests, offline
  ├── flow-clone-scan.sh    — lists duplicated blocks a branch introduced, using jscpd against the merge base
  ├── flow-pr-linked-issue.sh — prints the issue GitHub lists as closed by a pull request
  └── flow-check-resolution-body.sh — refuses a resolution comment the merge finding-ledger gate would misread
  Goals, runs and the quality ledger
  ├── flow-active-goal.sh   — finds the FlowGoal for the current branch and prints its status, criteria or JSON
  ├── flow-goal-record.sh   — creates a FlowGoal, or updates its lifecycle (--merge, --increment-turns)
  ├── flow-goal-trust.sh    — user-local trust ledger: which FlowGoals may auto-run verification commands
  ├── flow-record-activity.sh, flow-record-evidence.sh, flow-record-verdict.sh — write FlowRun activities, evidence and the last verdict
  ├── flow-mkdir.sh         — creates a directory under .flow/ or the journal, refusing one reached through a symlink (exit 2), or says the check could not run (exit 3); needs python3 but not PyYAML
  └── flow-quality-ledger.sh — per-session ledger of file edits and quality-command runs (task-completion gate): append|path|status|digest|prune
  Decision journal
  ├── journal-dir.sh        — prints the journal directory: journal.dir, held inside the repository when the repository's settings set it
  ├── journal-record.sh     — atomically updates the YAML manifest in .decisions/issue-{N}.md
  ├── journal-append.sh     — appends to, or replaces a section of, a journal body under the same lock
  ├── journal-read-section.sh — prints one journal section, ignoring headings inside code fences
  └── flow-strip-auto-log.sh — removes auto-log lines older journals committed (dry-run unless --apply; /flow:setup offers it)
  Learning, escalation and evals
  ├── flow-mine-corrections.sh — mines user corrections from session transcripts for /flow:learn
  ├── promote-proposal.sh   — promotes a /flow:learn proposal: a skill via draft PR, or a review exception as a row in the project
  ├── flow-escalate.sh      — formats canonical six-field escalation prompts (CLI utility)
  └── flow-eval-run.sh      — headless evals: correctness (seeded-bug tasks, hidden tests) and review precision

SCHEMAS/ (ship inside the plugin payload, available at runtime)
  ├── schemas/v1/*.schema.json            — FlowGoal, FlowWorkflow, FlowTrigger, FlowRun, FlowActivity and FlowEvidence
  └── schemas/<skill>/input-schema.json   — JSON Schema Draft-07 input contract per skill

TESTS (not part of what a user runs)
  ├── plugins/flow/tests/run.sh  — the plugin suite. The e2e-*.test.sh scenarios run a shipped command
  │                                block or hook the way Claude Code does (arguments substituted, under
  │                                zsh and bash) in a scratch repository, and write one artifact file per
  │                                scenario; set FLOW_E2E_ARTIFACT_DIR to keep them
  └── tests/run-all.sh           — repository-level checks: agentteams-gate, markertrust-gate,
                                   hooks-symlink, journal-orchestration, command-fence-arguments
```

### Hook Compatibility

| Event | Wired Script | Min. Claude Code | Notes |
|-------|--------------|------------------|-------|
| `PreToolUse` (Bash) | `block-force-push`, `block-destructive`, `block-unchecked-merge`, `block-secrets`, `ask-issue-create` | All current | Documented event. `block-force-push`, `block-destructive` and `block-unchecked-merge` parse the command rather than match its text, so a command that only mentions `rm -rf` or `gh pr merge` in a string is not refused; each `block-*` guard blocks when a tool it needs (such as `jq`) is missing. `block-force-push` blocks unless it can show the command does not force-push; `--force-with-lease` is allowed. `block-unchecked-merge` refuses `gh pr merge` while any check is queued, running or failed, refuses `--auto` on a base branch with no required checks, and accepts a merge only in one literal shape: `gh pr merge <number> --repo owner/name --squash\|--merge\|--rebase [...]`, which `/flow:merge` writes. `ask-issue-create` returns `permissionDecision: ask` (documented JSON contract) only for `gh issue create` while a FlowGoal is active and `minimalScope` is false |
| `PostToolUse` (Edit\|Write\|NotebookEdit) | `log-file-changes` | All current | Documented event; also appends a `file_change` entry to the session quality ledger (`notebook_path` read for NotebookEdit) |
| `PostToolUse` (Bash) | `log-commits`, `record-quality-run` | All current | Documented event; `record-quality-run` classifies test/lint/typecheck/build commands at command position, records `tool_response.exit_code`, a `masked` flag (`\|\| true`), and a sha256 digest of the working-tree contents (HEAD excluded, so commits of tested edits stay clean) |
| `PostToolUseFailure` (Bash) | `record-quality-run` | All current | Documented event ("after a tool call fails"): records the failed run (`failed: true`, exit code from the `Exit code N` line of `error`) so a failing test run reaches the ledger; deduped with PostToolUse on `tool_use_id` |
| `Stop` | `flow-goal-stop`, `reply-style-check` | All current | Documented event. `flow-goal-stop` ships in `warn` mode: the reason says plainly that the stop was ALLOWED; `block` and `evaluator-loop` modes are opt-in and execute verification commands only for goals in the user-local trust ledger. `reply-style-check` runs only when `replyStyle.enabled` is true and never blocks |
| `SessionEnd` | `session-end-learn`, `session-end-state` | All current | Documented event |
| `TaskCompleted` | `verify-task-completion` | **v2.1.33+** | Documented event (`task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name`). Exit 2 blocks completion while files changed after the last passing quality run; `testing.taskCompletionGate` selects `block\|warn\|off` |
| `TeammateIdle` | `nudge-idle-teammate` | **v2.1.33+** | Payload fields treated as best-effort |

`TaskCompleted` and `TeammateIdle` were introduced alongside agent-team support in Claude Code v2.1.33. The TaskCompleted payload is documented (https://code.claude.com/docs/en/hooks) and `verify-task-completion.sh` reads the documented `task_subject` / `task_description` fields, falling back to the legacy `.task.subject` shape. `TeammateIdle` fields (`.teammate.id`, `.idle_seconds`) remain best-effort: the hook exits 0 silently when they are absent. The `v2.1.33+` floor only matters for installs running an older Claude Code build.

### Required Skills: loaded by the command, not by the agent

Claude Code commands cannot preload skills from frontmatter (only agents have `skills:`), so a `## Required Skills` section on its own is a reading list the agent might or might not open mid-run. An audit of 43 sessions found the skill carrying the most-broken rule loaded once in twenty-four chances. Every command with Required Skills therefore carries a `!` block right under the list that calls `bin/flow-load-skills.sh <names...>`; Claude Code pre-executes it and injects the output, so the rules are in context before Phase 0.

Two loading modes, decided from each skill's frontmatter:

- **Ambient** (no `context: fork`, no `agent:`) — the whole body is inlined. These are stance skills that apply throughout (`llm-operator-principles`, `evidence-based-development`, `autonomous-workflow`, `code-quality-principles`).
- **Dispatched** (`context: fork` or `agent:`) — only the skill's `## Contract` section is inlined (its first H2, at most 120 words: iron law, invoking phase, return shape, permitted skips). The body runs in full when the command invokes `Skill(<name>)`.

Rules. The plugin's test suite enforces rules 1 to 3; promotion refuses a learned skill whose body is over 600 words:

1. Every command either has `## Required Skills` bullets plus the loader block, or an explicit `_None — {reason}_` marker and no loader block.
2. The loader block's names equal the bullet list exactly.
3. Every dispatched skill has `## Contract` as its first H2, at most 120 words.
4. Every `Skill(X)` invocation in a command body names one of its Required Skills. Skill bodies are kept to about 600 words; long tables live under `references/` and are linked.
5. Read-only / dispatcher commands (`status`, `learn`, `explain`, `flow`) use the `_None_` marker.

`references/skill-manifests.md` lists what each command loads and how many words that costs.

## Canonical Reference Documents

The plugin ships five canonical reference documents (under `plugins/flow/references/`) that are the single source of truth for cross-cutting contracts. Every command and agent that touches these contracts cites the relevant document instead of duplicating it inline:

| Reference | What it canonicalizes | Primary consumers |
|---|---|---|
| [`finding-schema.md`](references/finding-schema.md) | Reviewer output: 7-field finding data model (id, priority, category, location, problem, suggested_fix, confidence — all required of the agents) rendered as a two-column table (`Finding` and `Suggested Fix` columns) for legibility in GitHub's narrow PR-comment column, plus the marker-only `status` and `disposition` fields. Both review paths write the 7-field `FLOW_REVIEW_CYCLE` marker. | All 4 reviewer agents (`code-reviewer`, `security-reviewer`, `error-handler-inspector`, `integration-verifier`); orchestrators (`commands/review.md`, `commands/pr.md`, `commands/address.md`) |
| [`escalation-format.md`](references/escalation-format.md) | Six-field Proactive-Autonomy escalation structure (Situation, What I tried, Options, Recommendation, Blocking?, Risk). Delivered via `AskUserQuestion`, never inline text. | All 6 escalating commands (`start`, `pr`, `merge`, `commit`, `address`, `resolve`); reviewer agents that surface NEEDS-HUMAN-REVIEW |
| [`specification-journal-format.md`](references/specification-journal-format.md) | The `## Specification` journal shape: non-goals, failure modes, interface contracts, and the risk map (2-6 rows of area / plausible wrong version / discriminating check), plus the `specFirst.riskMap` disabled marker and the goal-YAML `risk_map` mapping. | `specification-capture` skill (producer); `implementation-planner`, `goal-contract-capture`, Phase 4 bundle producer (consumers) |
| [`verdict-output-format.md`](references/verdict-output-format.md) | The verdict table the judge returns, with a fixed rationale vocabulary (`self-referential oracle`, `degenerate inputs`, `risk map uncovered`, ...). | `agents/verdict-judge.md`, `commands/start.md` Phase 4 step 6 |
| [`evidence-bundle-format.md`](references/evidence-bundle-format.md) | Markdown shape verdict-judge consumes: per-criterion sections with mandatory `### Does NOT promise`, `### Visual analysis` (per-viewport `Observed:` blocks on ui criteria, plus a `Step:` block per step, or a `Flows: none — {reason}` line, when the criterion describes a user action; the judge has no file tools and never opens the screenshot), plus five completeness subsections (including test inputs with their expected-value sources and risk-map coverage). `none` is a valid positive-statement answer; bare blank triggers auto-FAIL. | `commands/start.md` Phase 4 (producer), `agents/verdict-judge.md` Step 1 (consumer); `criterion-verification-map` skill (plan-time inputs) |

Plus the existing references documenting policy, parser rules, and configuration:

- [`finding-ledger-parser.md`](references/finding-ledger-parser.md) — `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE` marker grammar
- [`gate-configuration.md`](references/gate-configuration.md) — the eleven quality gates flow enforces
- [`decision-journal-schema.md`](references/decision-journal-schema.md) — `.decisions/` file format
- [`three-tier-safety.md`](references/three-tier-safety.md) — Tier 1/2/3 action classification
- [`skill-manifests.md`](references/skill-manifests.md) — command → required-skill mapping (kept in lockstep with command files)
- [`test-review-checklist.md`](references/test-review-checklist.md), [`code-review-checklist.md`](references/code-review-checklist.md) — runnable checklists for review facets
- [`classification-signals.md`](references/classification-signals.md) — `change-classification` skill heuristics
- [`review-cycle-parsing.md`](references/review-cycle-parsing.md), [`holdout-lens-dispositions.md`](references/holdout-lens-dispositions.md), [`paired-review-protocol.md`](references/paired-review-protocol.md) — cycle-marker parsing for reviewers; Path A lens stances, holdout marker dispositions, and the full paired-review protocol tables
- [`correctness-eval.md`](references/correctness-eval.md) — the headless correctness eval (seeded-bug tasks, hidden tests) that measures the TDD and risk-map settings
- [`review-precision-eval.md`](references/review-precision-eval.md) — the review-precision eval that decides the `review.groundingCritic` default
- [`system-one.md`](references/system-one.md) — the optional System One provider: configuration, what leaves the machine, modes, the client's contract

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
| `/flow <verb> <target>` | Universal entry point; dispatches to the commands below |
| `/flow:start <issue>` | Assign issue, create branch, decompose tasks, implement |
| `/flow:commit` | Classify changes, flag anomalies, create atomic commits |
| `/flow:pr` | Full review pipeline + PR creation |
| `/flow:review <pr>` | Multi-faceted code review (single or team) |
| `/flow:address <pr>` | Systematic feedback resolution |
| `/flow:merge <pr>` | Merge with prerequisite verification (Tier 3) |
| `/flow:release <type>` | Changelog + semantic version release (Tier 3) |
| `/flow:resolve [pr-or-branch]` | Resolve merge conflicts on the current branch or a pull request |
| `/flow:status` | Read-only workflow overview |
| `/flow:learn` | Analyze decision patterns, propose new skills |
| `/flow:setup` | Initialize flow for a repository |
| `/flow:explain` | Interactive Q&A about decisions |
| `/flow:issue [topic]` | Create well-crafted GitHub issues |
| `/flow:brainstorm [topic]` | Explore approaches before implementation |
| `/flow:debug [error]` | Structured debugging with root cause analysis |
| `/flow:design [feature]` | Architecture discussion and design validation |

### Advanced / runtime internals

These commands expose the runtime layer Flow normally manages for you. You rarely invoke them directly — the intent commands above create and advance goals, workflows, runs, and evidence automatically. Reach for these to inspect, debug, or hand-drive the runtime.

| Command | Purpose |
|---------|---------|
| `/flow:goal` | Inspect/evaluate FlowGoals. **`/flow:goal create` is the `--manual` path** — the normal way a goal is created is automatically by `/flow:start` (`goalCreation: auto`), not by hand. |
| `/flow:workflow` | Inspect workflow definitions and phase/activity state (`flow.workflows.enabled: false` turns it off) |
| `/flow:trigger` | Manage FlowTriggers (on by default; `flow.triggers.enabled: false` turns it and `/flow:watch` off) |
| `/flow:run trigger <id>` | Run one FlowTrigger's target once; schedules nothing |
| `/flow:resume` | Read an interrupted run and propose the next safe action (informational-only) |
| `/flow:watch` | Generate a `/loop` prompt file for hands-off iteration (user invokes the loop) |

## Safety Model

Three-tier action classification:

| Tier | Actions | Behavior |
|------|---------|----------|
| **Tier 1** (Autonomous) | Commits, branches, edits | Execute without asking |
| **Tier 2** (Journal) | Push, PR creation | Execute and log |
| **Tier 3** (Confirm) | Merge, release | Always ask |

Hooks provide structural enforcement — they block dangerous operations even if command logic fails. A `gh pr merge` typed outside `/flow:merge` is still checked: the merge guard refuses it while any check is unfinished or failed.

## LSP Code Intelligence

When LSP servers are available, Flow leverages language server capabilities across workflow phases:

| Phase | LSP Feature | Benefit |
|-------|------------|---------|
| **EXPLORE** | `goToDefinition`, `findReferences` | Semantic code path tracing and impact analysis |
| **CODE** | `hover` | Type info and signatures for existing code |
| **VERIFY** | Diagnostics | Errors→P1, warnings→P2 as complementary quality signals |
| **REVIEW** | `findReferences`, `incomingCalls` | Verify all callers of modified functions are handled |

LSP is additive — all phases fall back to grep/CLI-based analysis when no LSP server is configured. Configure via `lsp.enabled`, `lsp.timeout`, and `lsp.diagnosticsAsQuality` in settings.

## Review

`/flow:review`, `/flow:pr` (before the pull request is opened) and `/flow:address` (over the fix commits) dispatch the same reviewer agents. What the reviews do beyond reading the diff:

- **Finding confidence decides what a finding may demand.** Every finding carries HIGH, MEDIUM or LOW confidence; a missing or invalid value counts as MEDIUM. On someone else's pull request, a LOW finding goes under `Needs investigation` with what would confirm or refute it, and it does not count toward the review decision or the finding ledger the merge gate reads. On your own pull request each LOW finding is settled before anything posts: a test confirms it (fixed, recorded HIGH), refutes it (dropped, with the passing output as evidence), or, when neither is possible, it is escalated and recorded MEDIUM. Confidence never changes priority.
- **The goal is read at the pull request's head.** `/flow:review` reads the linked issue's FlowGoal over the GitHub API at the head commit and hands its criteria, non-goals, interface contracts and risk map to the reviewers as text; no `verification_command` from it is run. When the goal has no risk map, the rows are derived from the issue text and labelled as such. A pull request that removes its own goal is a P1 finding, and one that weakens a goal that already existed on the base is a P2 finding.
- **Contract changes list their blast radius.** When the diff touches an OpenAPI, GraphQL or protobuf file, a migration, a schema file or a goal file, the review body gets a `Blast radius` section listing the code that depends on it. Every consumer either appears in the diff or earns a `breaking-change` finding.
- **Someone else's pull request is read, not run.** `/flow:review` fetches it into a detached worktree outside this session's directory, with git hooks and the pull request's `.gitattributes` switched off. Its tests, build, dependency audit and duplication scan are not run, and the review lists them under `Checks not run`. Start the session with `FLOW_REVIEW_RUN_PR_COMMANDS=1` to run them anyway. Your own pull request is checked out normally, because self-review fixes forward onto its branch.
- **Review exceptions.** A team records a finding it has rejected on principle as a row in `.flow/review-exceptions.md` (rule, path glob, reason, source), by hand or by promoting a `/flow:learn` proposal. Reviewers are handed the rows and do not raise a matching finding inside the glob. The file is read at the pull request's base commit, or the default branch for `/flow:pr`, so a pull request cannot grant itself an exception, and a row takes effect once it is on the branch pull requests merge into. A security finding is never withheld because of an exception: the reviewer raises it labelled `exception-override` so a person decides. See the Learning Loop for how rows are proposed.
- **New and bumped dependencies.** `security-reviewer` reads the dependency changes from the manifests, compares them with the dependencies at the base commit, and raises `DEP-` findings: a critical or high advisory with a fix available (P1), a license the project cannot include (P1 with an escalation), install hooks, a name within edit distance 2 of an existing dependency, and a dependency redirected elsewhere. These enter the same finding ledger as every other finding.
- **Duplication, in two layers.** `code-reviewer` runs a clone scan (jscpd) against the merge base and raises a `DUP-` finding for each block the change copied from existing code (P2) or duplicated within itself (P3). It also looks for new functions that re-implement behaviour an existing symbol already provides (P2, MEDIUM). `/flow:start` runs the same scan after each task and does not mark the task complete while a copied block stands, and its plan names, for each new function, the existing code it reuses. Settings: `duplication.enabled`, `minLines`, `minTokens`, `excludePaths`. Without jscpd the scan says it did not run; it is never reported as clean.
- **Grounding critic (off by default).** With `review.groundingCritic: "on"`, each consolidated P1/P2 finding goes to the `finding-critic` agent, which tries to refute it from the code; the reviewer that raised a disputed finding must cite code or drop it. Security findings are never dropped by this pass. It applies to the single-session path only. The review-precision eval found it lowered precision on both models tested, so it stays off. `/flow:review` reads this setting only from your user settings file and the plugin default, never from the repository under review; `/flow:pr` reads the full cascade.

## Visual Verification

When a change touches UI files or its criteria mention UI, `/flow:start` and `/flow:pr` screenshot each page at every configured viewport and describe what they see. When a UI criterion describes something a user does (click, submit, type, select, toggle, open, navigate, drag), they also drive that flow: one to three scenarios of at most `visualVerification.maxFlowSteps` steps (default 8), taking element targets from the page snapshot and recording a screenshot and an observation after each step. Driving a flow needs an interactive browser tool (Playwright MCP or Chrome DevTools MCP); with a screenshot-only tool, or `visualVerification.flows: "off"`, the evidence says that no flow was run and why. Without any browser tool the result is `SKIP_WARN`, or `BLOCKED` when `requireVisualVerification` is true.

## Agent Teams (Opt-In)

Enable with `"agentTeams": true` in settings. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

When enabled, `/flow:review` spawns an adversarial review team where independent reviewers challenge each other's findings. Falls back to single-session mode gracefully.

**Model selection.** Because this Path A team dispatches ~20 agents per review, all of which would otherwise inherit the session model, the model is configurable via `agentTeamModel` (default `"sonnet"`; enum `haiku|sonnet|opus|fable|inherit`). It resolves through the same settings cascade as `agentTeams`. Set it to `"inherit"` to run the review agents on the session's model, or `"opus"` for a high-stakes review. This mirrors the `flow.goals.judge.model` pattern and applies to Path A only — Path B (single-session, the default) always inherits the session model.

## Evals

Flow's testing gates and review settings are measured, not assumed. `bin/flow-eval-run.sh` runs headless Claude Code sessions and has two modes.

**Correctness** (the default mode) runs four seeded-bug tasks under `evals/` across seven arms (`testing.tddMode` ∈ enforce/suggest/off × `specFirst.riskMap` on/off, plus a no-plugin baseline) and scores each run against a hidden unittest suite the agent never sees. Each run's own tests are also scored against the trap variants as a secondary signal, and results are grouped by model (`--models`); `--effort` pins the reasoning effort and every run records its token counts. `summary.md` states the verdict in plain sentences; the rule that flips the `tddMode` default is in [`references/correctness-eval.md`](references/correctness-eval.md). Verify the cases offline with `bin/flow-eval-run.sh --check-cases`. Two runs are recorded. The first (`evals/results-2026-09-09/`, 63 runs) had every arm at ceiling on correctness. The second (`evals/results-2026-09-09-round2/`, Sonnet 5 on four cases and Opus 5 on the one case Sonnet fails) again found no correctness difference between arms and a three-to-six-fold cost for the enforce arms. Both defaults stay by the rule.

**Review precision** (`--mode review`) puts the single-session review fan-out in front of a diff whose one defect is known, with `review.groundingCritic` off and on, and scores the P1/P2 findings: precision (the share of findings that hit the defect), recall (the share of runs that found it) and F1, where higher is better for all three. The critic becomes the default only if it raises F1 by more than the run-to-run spread on every model tested, with at least two models. The recorded run (`evals/results-2026-09-25-review/`, 272 runs on Opus 5.5 and Sonnet 5) lowered F1 with the critic on both models (0.440 to 0.335, and 0.510 to 0.471), so the setting stays off. See [`references/review-precision-eval.md`](references/review-precision-eval.md).

## Learning Loop

Flow captures development decisions in a journal (`.decisions/`) and also reads the session transcripts where user corrections actually live. The directory is `journal.dir`: set in the repository's own settings it must resolve inside the repository, or flow warns and uses your own `journal.dir`, or `.decisions/` when you set none; set in your own `~/.claude/settings.flow.json` it may point anywhere, and an absolute value there with no `..` component is written as configured, even through a symlink you made (see [`decision-journal-schema.md`](references/decision-journal-schema.md)).

1. **During work**: PostToolUse hooks auto-log file changes and commits to a local, gitignored trail under `{journal.dir}/auto-log/` — never to the tracked journal
2. **After work**: `/flow:learn` mines the journal and run events (what flow wrote) and, when `learning.sources` includes `transcripts`, the user turns in `<config>/projects/<project>/*.jsonl` (`<config>` being `$CLAUDE_CONFIG_DIR` or `~/.claude`) via `bin/flow-mine-corrections.sh` (read-only, local, recall-oriented filter; the judging happens in Phase 2). A pattern counts only with 3+ verified instances across 2+ sessions
3. **Proposals**: Generates skill proposals in `~/.claude/flow-proposals/`. When the rule already exists in a skill, the proposal is an `enforcement` proposal naming the hook or gate that should make it mechanical, not a new skill
4. **Review exceptions**: when `/flow:address` dismisses a review finding, it records the dismissal and its reason in the journal. `/flow:learn` clusters dismissals by category and reason; a cluster of two or more dismissals across two or more pull requests in one project becomes an `exception` proposal carrying one row for `.flow/review-exceptions.md`, scoped to the paths where the dismissals happened
5. **Promotion**: Human reviews and promotes proposals with `bin/promote-proposal.sh`. A skill or enforcement proposal becomes a learned skill in a draft PR; an exception proposal is appended as a row to the project's `.flow/review-exceptions.md`, which you then commit like any other change

## Configuration

Settings cascade in priority order; later layers override earlier ones:

1. `plugins/flow/settings.json` — plugin defaults
2. `~/.claude/settings.flow.json` — user defaults (or the file named by the `FLOW_USER_SETTINGS` environment variable; see [Per-user locations](#per-user-locations))
3. `.claude/settings.flow.json` — project settings (committed)
4. `.claude/settings.flow.local.json` — local overrides (gitignored, highest priority)

### Per-user locations

Two environment variables move what is yours alone: `FLOW_STATE_DIR` names the directory Flow keeps per-user state in (default `~/.claude/flow-state`: the goal trust ledger, stop and stuck counters, quality ledgers, System One records), and `FLOW_USER_SETTINGS` names your user settings file (default `~/.claude/settings.flow.json`), which holds settings only you may choose, such as the System One provider's address.

Set them yourself, in your shell or in `~/.claude/settings.json`'s `env` block. A repository cannot set them: Claude Code applies the `env` block of a repository's `.claude/settings.json` once you trust the folder, and a trusted goal's verification commands run at the end of every turn. So Flow uses a value only when it is an absolute path with no control character, outside the repository you are working in (its git top, and the project directory Claude Code names in `CLAUDE_PROJECT_DIR`, judged by where the path resolves, symlinks and `..` included), and is not the value the repository's own `.claude/settings.json` (or its `.claude/settings.local.json`) sets. Otherwise it prints one warning naming the variable and the reason, never the value or what it names, and uses the default. A value you set yourself that points inside the repository is ignored the same way, since nothing tells it apart from the repository's, so keep these locations outside any repository. `bin/cascade-resolve.sh --state-dir` and `--user-settings-path` print the directory and file Flow will use.

Flow finds every per-user file under your home: the two defaults above, the learn-pending flag, the proposal directory, the session transcripts `/flow:learn` reads, the goal evaluator's throttle and judge directories, and the markers that record a missing tool. A repository can set `HOME` the same way, so Flow uses `HOME` only when it is an absolute path with no control character that the settings of the repository, of `CLAUDE_PROJECT_DIR` or of the working directory did not set. Otherwise Flow uses the home your user account has, and `--state-dir`, `--user-settings-path` and `--user-home` print a warning saying so. Your home directory is not treated as a repository, even when it is kept in git, so `~/.claude/settings.json` stays yours. `bin/cascade-resolve.sh --user-home` prints the home Flow uses.

Example project settings in `.claude/settings.flow.json`:

```json
{
  "agentTeams": false,
  "agentTeamModel": "sonnet",
  "tiers": { "push": "journal", "merge": "confirm", "release": "confirm" },
  "conventions": { "commitTypes": ["feat", "fix", "docs", "..."] },
  "merge": { "strategy": "squash", "deleteBranch": true },
  "lsp": { "enabled": true, "timeout": 5000, "diagnosticsAsQuality": true },
  "visualVerification": { "enabled": true, "screenshotDir": ".screenshots", "maxIterations": 3, "flows": "on", "maxFlowSteps": 8 },
  "duplication": { "enabled": true, "minLines": 5, "minTokens": 20, "excludePaths": ["**/tests/**", "..."] },
  "debugging": { "maxHypotheses": 3 },
  "testing": { "tddMode": "enforce", "tddModeOptOut": false, "taskCompletionGate": "block", "qualityCommandPatterns": [] },
  "specFirst": { "riskMap": true },
  "learning": { "enabled": true, "sources": ["journal", "transcripts"] },
  "verdict": { "requireAllPass": true },
  "flow": { "goals": { "stopHookEnforcement": "warn", "failAfterStuckTurns": 3 }, "triggers": { "enabled": true } }
}
```

See `schema.json` for full configuration reference.

### Reply-style check (opt-in)

A project can state a house writing style once and have it checked when a reply
is written, rather than only when the session starts. The rule is in context at
session start; the violations happen deep into long sessions, after many tool
results have pushed it out.

```json
{
  "replyStyle": {
    "enabled": true,
    "constructions": ["issue-references", "repo-paths", "not-x-but-y"],
    "extraPatterns": [
      { "name": "house-tic", "pattern": "\\bsynergy\\b", "advice": "say what it does." }
    ]
  }
}
```

Off unless `enabled` is `true`. It matches a short list of literal constructions
— issue and PR numbers, bare repository paths, `not X but Y`, staged emphasis
(`the key thing is`), coined compounds, `surface` used as a noun for a component
— names where each appeared, and warns through `systemMessage`. It never blocks
and carries no `decision` field, so it cannot override another `Stop` hook.

Every pattern is deliberately narrow, because a check that fires on ordinary
sentences teaches the reader to ignore it. `the real problem is solved` and
`it is not clear, but we can check` are ordinary prose and are not flagged;
`attack surface`, `rate-gated` and a `load-bearing` wall are terms of art and
are not flagged either. A project regex runs under a watchdog, so one that
backtracks cannot hang the session.

It reads only the final assistant text. Tool calls, their output, fenced code
and inline code are not prose the reader reads, and a path the reader is being
told to open or run is an instruction rather than process noise. Omit
`constructions` for the full built-in set, or give `[]` to run only your own
`extraPatterns`.

It does not judge clarity, rewrite anything, or look at what was committed —
code and commit messages are a different check with different rules.

### System One (optional)

Flow can ask a System One model (TypeSafe's hosted Jev, or the open-weight
imajev running on your machine) typed yes/no, one-of-a-set and scale questions
at its decision points. With no provider, the default, nothing changes.

```json
{ "systemOne": { "provider": "imajev", "timeoutMs": 20000, "uses": { "review.dedup": "shadow" } } }
```

A model on your machine usually needs a longer `timeoutMs` than the 3-second
default; a request that runs past it gets no answer, and Flow keeps its
current behavior.

Set the provider in `~/.claude/settings.flow.json`. Flow ignores a provider,
address or key variable set in a repository's settings files, because those
come with the checkout. With `typesafe`, the text Flow sends (diffs, review
comments, transcript excerpts) goes to TypeSafe's servers. With `imajev` it
stays on the machine. No decision point uses it yet; see
[`references/system-one.md`](references/system-one.md).

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
