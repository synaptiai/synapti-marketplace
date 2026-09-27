# Flow Plugin Handbook

Long-form reference for the team. The slide deck (`slides.md`) is the room-facing view; this handbook is what you read when something doesn't make sense afterwards.

**Source of truth**: `plugins/flow/` in this repo. When this handbook and the source disagree, the source wins — file an issue.

## Table of contents

1. The 6 Excellence Principles
2. The two skeletons — three-tier safety + Explore-Plan-Code-Verify
3. Vocabulary — skills vs agents vs commands
4. Commands (23) — what each does
5. Agents (10) — what each is for
6. Skills (32 + `learned/`) — knowledge units
7. Hooks — what's actually wired
8. Decision journal — the audit trail
9. Holdout validation and the verdict-judge
10. Configuration cascade
11. Failure modes and where to look
12. FlowGoals and the Stop hook

Appendix A — Coming from `gh-workflow`?
Appendix B — File paths quick reference

---

## 1. The 6 Excellence Principles

Flow enforces six principles. They are the answer to "why does this plugin block me?". Source: `plugins/flow/README.md`, section "Excellence Principles". The README also lists a seventh, "Rules in the Room, Checked by Machine": each command loads its required skills into its own prompt (§3), and hooks check what the rules say (§7).

### 1. Stranger Test

Every plan must be executable by someone with zero prior context. If an instruction requires unstated assumptions or "you know what I mean" reasoning, it fails the Stranger Test and the PLAN phase blocks until rewritten.

**Failure mode it prevents**: implementer joins the PR mid-cycle, can't tell what "fix the auth thing" means, makes the wrong fix.

### 2. Spec-as-Eval-Suite

Acceptance criteria are not documentation — they are the eval suite. Each criterion must have a concrete, automated verification command defined **before the PLAN phase begins**. Vague criteria like "works correctly" are rejected by the Spec Validation Gate in `/flow:start`.

**Failure mode it prevents**: tests pass, criteria are never actually verified, the PR ships and breaks production.

> **Iron Law** (`plugins/flow/skills/criterion-verification-map/SKILL.md` line 13):
> "every acceptance criterion is an eval source: at plan time it must produce a runnable verification command, or planning is blocked."

### 3. Proactive Autonomy

Agents resolve ambiguity themselves first. When escalation is unavoidable, it follows a structured **six-field format**, delivered through `AskUserQuestion` rather than as inline text. Anti-patterns like "what should I do?" are blocked.

The six fields (`plugins/flow/references/escalation-format.md`, section "The six fields"):

| Field | Purpose |
|-------|---------|
| **Situation** | What specific state requires a decision. Concrete facts, readable cold by a teammate |
| **What I tried** | What was already attempted, and why each path did not resolve it |
| **Options** | 2-3 concrete paths forward, each with a one-line trade-off |
| **Recommendation** | The preferred option, with one sentence of reasoning |
| **Blocking?** | Yes / Soft / No — whether the current command can proceed. No calendar-time language ("urgent", "by Friday") |
| **Risk** | What breaks if the choice is wrong or deferred, and who bears the cost |

Escalation is for irreversible actions, genuinely ambiguous product or architecture decisions, runtime-verification skips outside the whitelist, and genuine non-convergence. It is never for deciding what to do with a review finding — findings are fixed (see Principle 6).

**Failure mode it prevents**: agent dumps an open-ended question into a PM's inbox at 11pm on a Friday with no recommendation.

### 4. Quality > Speed

TDD mode defaults to `enforce`. The verdict judge requires all acceptance criteria to pass. Every review finding, P3 included, is fixed in the PR.

| Setting | Default | Why |
|---------|---------|-----|
| `testing.tddMode` | `"enforce"` | Catching test-first violations at write-time is cheaper than catching them at review-time. The Per-Task Verification Gate observes RED-GREEN-REFACTOR before letting a task complete. Teams that prefer test-after can set `"suggest"` (or `"off"`) — decision 1 in the conventions worksheet — and document the rationale. |
| `verdict.requireAllPass` | `true` | The verdict judge must return PASS for every acceptance criterion or the verdict is FAIL. Partial coverage is a FAIL, not "mostly done." With `false`, a person can approve a criterion the judge marked `NEEDS-HUMAN-REVIEW`. |

(`plugins/flow/settings.json`)

**Failure mode it prevents**: "tests pass" treated as proof of correctness when only the happy path was tested.

### 5. No Lazy Verification

Every criterion's section in the evidence bundle must carry `### Does NOT promise`, `### Visual analysis` (`none — …` on criteria with no UI), and five completeness subsections (`plugins/flow/references/evidence-bundle-format.md`; `criterion-verification-map/SKILL.md`, section "Evidence collection protocol"):

- **What was NOT tested** — explicit list of related behaviors not covered
- **Known limitations of this evidence** — how the evidence could be misleading even though it looks positive
- **Negative/adversarial cases covered** — specific failure modes the system rejects
- **Test inputs and expected values** — one row per test, taken from the test source, with the source of each expected value (spec, reference implementation, hand computation, fixture, standard). A value copied from the implementation's own output is FAILed.
- **Risk map coverage** — each risk-map row mapped to the test that tells the right implementation from the plausible wrong one

`none — {reason}` is a valid answer; a blank or missing subsection is an automatic FAIL.

**Failure mode it prevents**: "test added" claim that turns out to be testing a stub, or a test whose expected value was pasted from the code it tests.

### 6. No Incomplete Shipments

Pre-existing findings in touched files keep their natural priority — they are not capped at P3 just because they were already there when you opened the file. Every finding, P1 to P3, is fixed in this PR by default (`skills/llm-operator-principles/SKILL.md`, "Default Finding Disposition: Fix In This PR"). The only non-fix outcomes are a product decision only the user can make, a file flow does not own (binary, vendored, generated, third-party), a dependency flow does not own, and `minimalScope: true`, which allows a follow-up issue for a cosmetic P3 in a file the PR did not touch.

The finding-ledger merge gate blocks `/flow:merge` while the latest `FLOW_RESOLUTION_CYCLE` marker lists any ESCALATED item, or any finding in `FLOW_REVIEW_CYCLE` has no RESOLVED entry. The lifecycle word is **ESCALATED**, not "deferred": there is no silent deferral.

**Failure mode it prevents**: P3 backlog that grows forever and nothing ever gets fixed.

---

## 2. The two skeletons

Two structures hold the plugin together. Learn these and the rest follows.

### 2a. Three-tier safety

Source: `plugins/flow/references/three-tier-safety.md`.

| Tier | What | Behavior | Examples |
|------|------|----------|----------|
| **1 — Autonomous** | Local, reversible | Execute without asking | File edits, commits, branch creation, staging, running tests, agent dispatch |
| **2 — Journal** | Team-visible, recoverable | Execute and log to decision journal | Push, PR creation, issue assignment, issue creation, PR comment, `--force-with-lease` push |
| **3 — Confirm** | Hard to reverse, high-impact | Always require human confirmation | PR merge, release creation, force push, branch force-deletion |

**Promotion rule**: actions can be promoted (autonomous → journal → confirm) but never demoted. This is the documented policy for the `tiers` setting. No command or hook reads the `tiers` keys at present: `/flow:merge` and `/flow:release` ask for confirmation whatever the setting says, and every other command applies the tier listed in its own `## Tier Classification` section.

**Hook enforcement at the Bash layer**:

| Hook | Action | Behavior |
|------|--------|----------|
| `block-force-push.sh` | `git push --force`, `-f`, a `+refspec` | Exit 2 (block). `--force-with-lease` is allowed |
| `block-destructive.sh` | `rm -rf`, `git reset --hard`, `git clean -f`, discarding all changes, force-deleting an unmerged branch | Exit 2 (block) |
| `block-unchecked-merge.sh` | `gh pr merge` while a check is queued, running or failed; `--auto` where the base branch requires no checks | Exit 2 (block) |
| `block-secrets.sh` | Inline credentials | Exit 2 (block) |
| `ask-issue-create.sh` | `gh issue create` while a FlowGoal is active | Asks for permission |

**Important**: merge and release confirmation is handled at the **command level** via AskUserQuestion (see `/flow:merge` and `/flow:release`), not by a `gate-merge` or `gate-release` hook script (`three-tier-safety.md`, section "Hook Enforcement"). `block-unchecked-merge.sh` does not confirm anything; it refuses a merge whose checks have not finished green, including one typed straight into Bash. The fourteen wired hook scripts are listed in §7.

### 2b. Explore-Plan-Code-Verify (EPCV)

Source: `plugins/flow/skills/autonomous-workflow/SKILL.md`.

> **Iron Law** (line 11): "NO SKIPPING PHASES. Explore, then Plan, then Code, then Verify. Every phase produces an artifact."

| Phase | What | Output |
|-------|------|--------|
| **EXPLORE** | Gather context. Parallel reads, agent dispatch, capability discovery, LSP tracing. Capture the specification. | Context inventory, specification |
| **PLAN** | Decompose work. TaskCreate per deliverable. Verification command attached to each criterion. Stranger Test gate. | Task list with criteria |
| **CODE** | Execute tasks. TaskUpdate(in_progress) → implement → commit → TaskUpdate(completed) only after Per-Task Verification Gate. | Working code, journal entries |
| **VERIFY** | Four mandatory layers (below). | Evidence bundle, verdict |

**What each phase leaves behind** (concrete artifacts a reader can open):

- **EXPLORE → Artifact**: a populated `.decisions/issue-N.md` with a `## Specification` heading (non-goals, failure modes, interface contracts, risk map) and the Spec Validation Gate result mapping each AC to its runnable verification command. When at least one AC carries a verification command, a FlowGoal at `.flow/goals/issue-N.goal.yaml` (§12). Source: `commands/start.md`, Phase 1.
- **PLAN → Artifact**: an atomic TaskList where each task bundles implementation + test + verification command + expected evidence shape, plus a `Reuses:` line naming the existing code to call or what was searched before writing a new helper; a feature branch off the default branch; the Stranger Test result recorded in the journal under `## Stranger Test` as PASS or BLOCK. Source: `commands/start.md`, Phase 2; `agents/implementation-planner.md`.
- **CODE → Artifact**: per-task commits, each containing implementation + test + the verification evidence captured at task-completion time (not deferred); `<!-- auto-log: ... -->` entries in the local gitignored trail for every Edit/Write and commit; the Per-Task Verification Gate satisfied for each task. Source: `autonomous-workflow/SKILL.md`, "Per-Task Verification Gate"; `commands/start.md`, Phase 3.
- **VERIFY → Artifact**: an evidence bundle (one section per AC with `Does NOT promise`, `Visual analysis` and the five completeness subsections), the holdout-validation output, and the verdict-judge agent's PASS/FAIL/NEEDS-HUMAN-REVIEW per criterion — fed only the ACs + evidence bundle + holdout output. Source: `criterion-verification-map/SKILL.md`, "Evidence collection protocol" and "Judge isolation"; `commands/start.md`, Phase 4.

**The four VERIFY layers** (`autonomous-workflow/SKILL.md` lines 18–22):

| Layer | What | Tool |
|-------|------|------|
| **a. Static** | Lint, test, typecheck in parallel + LSP diagnostics if available | Parallel quality commands + LSP |
| **b. Runtime** | Build the project, start it, verify at runtime; for UI changes, screenshot each viewport and drive the changed user flow. Debug-fix-retest loop bounded by `closedLoop.maxDebugIterations`. | `runtime-verification` and `visual-verification` skills |
| **c. Review** | Self-review with **fix-forward** — fix findings immediately, don't just report them | `code-review-methodology` skill |
| **d. Verdict** | Independent judgment. Acceptance criteria + evidence bundle → verdict-judge agent → PASS/FAIL/NEEDS-HUMAN-REVIEW. Judge has no access to diff or journal. | `verdict-judge` agent |

**Per-Task Verification Gate** (`autonomous-workflow/SKILL.md` lines 28–35): a task may NOT be marked completed until ALL of: tests pass, verification evidence captured, no out-of-context files, TDD cycle observed when `tddMode: enforce`. `/flow:start` also runs a duplication scan per task: a block this change copied is treated like a failing test. The `TaskCompleted` hook backs this up: it refuses completion while files have changed since the last passing test, lint, typecheck or build run (§7). This is the primary quality enforcement point — VERIFY is independent confirmation, not first-pass verification.

---

## 3. Vocabulary — skills vs agents vs commands

If you only remember three definitions, remember these.

| Concept | What it is | Plural noun for | Example |
|---------|-----------|-----------------|---------|
| **Command** | An entry point — a `/flow:*` invocation that drives a workflow phase. Carries the executable bash. | "things you type" | `/flow:start 42` |
| **Agent** | A subagent dispatched by a command, with its own context and a narrow tool budget | "specialists you hire" | `verdict-judge` |
| **Skill** | A reference document — policy, philosophy, rationale — loaded into the active context | "reference docs Claude reads" | `criterion-verification-map` |

The same knowledge lives in different containers depending on how it's reused:

- A **command** runs once per workflow step and re-reads itself each session. It owns the bash blocks and the phase ordering.
- An **agent** runs in a forked context with isolated tools — useful for independent judgment (verdict-judge sees no diff) or parallel review.
- A **skill** is invoked from anywhere — commands, other skills, agents — and contributes its iron laws + protocols to whatever workflow needs them.

**Why skills carry no executable bash**: skills are policy and rationale that compounds across sessions. Bash that runs at workflow time belongs in commands, where it can be audited and version-controlled per phase. Splitting the responsibility this way means a skill can be re-read by a new command without forking logic, and a command can change its bash without rewriting team knowledge.

### Required Skills and the skill loader

Source: `plugins/flow/README.md`, section "Required Skills: loaded by the command, not by the agent".

Each command lists its skills under `## Required Skills`. A loader block right under the list (`bin/flow-load-skills.sh`) runs when the command is invoked and puts those skills into the prompt before Phase 0, so the rules are in context before any work starts. Skills load in one of two modes:

- **Ambient** — the whole skill body is inlined. These are the four stance skills that apply throughout: `llm-operator-principles`, `evidence-based-development`, `autonomous-workflow`, `code-quality-principles`.
- **Dispatched** — only the skill's `## Contract` section (at most 120 words: iron law, invoking phase, return shape, permitted skips) is inlined. The full body runs when the command invokes `Skill(<name>)` at a phase boundary. Example: `Skill(capability-discovery)` during EXPLORE.

Four rules govern usage:

1. Every command either has `## Required Skills` bullets plus the loader block, or an explicit `_None — {reason}_` marker and no loader block.
2. The loader block names exactly the bullet list, and every `Skill(X)` invocation in the body names a Required Skill.
3. Every dispatched skill has `## Contract` as its first section; every skill body is at most 600 words, with long tables moved to `references/`.
4. Read-only / dispatcher commands (`status`, `learn`, `explain`, `flow`) use the `_None_` marker.

A skill becoming popular enough across commands → it's the right shape. A command duplicating logic from another command → that logic should be a skill.

---

## 4. Commands (23)

Daily five (you'll use these every day):

| Command | Purpose |
|---------|---------|
| `/flow:start <issue>` | Assign issue, create branch, decompose tasks, implement |
| `/flow:commit` | Classify changes, flag anomalies, create atomic commits |
| `/flow:pr` | Full review pipeline + PR creation |
| `/flow:review <pr>` | Multi-faceted code review (single or team) |
| `/flow:address <pr>` | Systematic feedback resolution |

Tier 3 (confirmation required):

| Command | Purpose |
|---------|---------|
| `/flow:merge <pr>` | Merge with prerequisite verification — never autonomous |
| `/flow:release <type>` | Changelog + semantic version release — never autonomous |

Supporting three (read-only or learning):

| Command | Purpose |
|---------|---------|
| `/flow:status` | Read-only workflow overview. Default is a five-line dashboard; `--full`, `--json` and `--evidence` give longer views |
| `/flow:explain` | Interactive Q&A about decisions on the current branch/issue |
| `/flow:learn` | Analyze the decision journal and session transcripts for patterns; generate skill, enforcement and review-exception proposals |

Entry-point variants (shape work before implementation):

| Command | Purpose |
|---------|---------|
| `/flow:issue [topic]` | Create well-crafted GitHub issues with duplicate detection and verifiable acceptance criteria |
| `/flow:brainstorm [topic]` | Explore approaches, generate options, analyze trade-offs |
| `/flow:debug [error]` | Structured debugging with root cause analysis |
| `/flow:design [feature]` | Architecture discussion and design validation |

Rare / bootstrap:

| Command | Purpose |
|---------|---------|
| `/flow:setup` | Initialize flow for a repository — detect tech stack, generate settings, configure LSP |
| `/flow:resolve` | Resolve merge conflicts on a branch or PR |
| `/flow:flow` | Universal dispatcher — `/flow <verb> <target>` for the sixteen commands above |

Runtime / admin (inspect the layer flow manages for you; see §12):

| Command | Purpose |
|---------|---------|
| `/flow:goal` | Inspect, evaluate, pause, resume or clear FlowGoals. `/flow:start` creates goals automatically; `/flow:goal create` is the manual path |
| `/flow:workflow` | List, inspect, validate and graph the workflow definitions |
| `/flow:trigger` | Manage FlowTriggers — wake-up intent; they do not run anything in the background |
| `/flow:run` | Run a trigger's target once |
| `/flow:resume` | Read an interrupted run and propose the next safe action. It never runs the action itself |
| `/flow:watch` | Write a trigger and a `/loop` prompt file that you start yourself |

**Command-level tier-3 prompts**: `/flow:merge` and `/flow:release` invoke `AskUserQuestion` for confirmation. There is no `gate-merge` or `gate-release` hook — the structural gate is in the command file itself plus the Bash hooks for the underlying dangerous operations, including `block-unchecked-merge.sh`.

**What `/flow:merge` checks before it asks**: approval, CI checks (finished, and which are required on the base branch), mergeability, unresolved conversations and stale approval are shown in a Merge Assessment table. It stops on the finding-ledger gate (§1, Principle 6), on the FlowGoal gate (an active goal for the branch must be `achieved`; a branch with no goal is not blocked), and when a FlowRun linked to the branch is still active. It then asks for confirmation and runs the merge with `merge.strategy` (default `squash`) and `merge.deleteBranch` (default `true`).

### Parallel agent fan-out — which command, which agents

Three commands dispatch a parallel review fan-out. Knowing which agents run where is useful when reading PR-body findings tables and re-review comments.

`/flow:pr` Phase 3 dispatches five review agents in one message — `code-reviewer`, `convention-checker`, `test-runner`, `security-reviewer`, `error-handler-inspector` — alongside the `holdout-validation` skill. `/flow:review` Path B (the default, single-session) dispatches the same five plus `holdout-validation`. `/flow:address` Phase 4 re-reviews the fix commits with the same five agents, then runs `holdout-validation` as a separate step.

| Facet | One-line purpose |
|-------|------------------|
| `code-reviewer` | Quality + correctness review, P1/P2/P3 with file:line citations; also blast radius and duplication |
| `convention-checker` | Git convention compliance — commit messages, branch naming, PR shape |
| `test-runner` | Lint, test, typecheck — structured pass/fail report |
| `security-reviewer` | OWASP-style review — secrets, auth/authz, input validation; judges every added or bumped dependency |
| `error-handler-inspector` | Unhandled errors, missing edge cases, silent failures |
| `holdout-validation` (skill) | Cross-reference self-review claims against actual file state via hidden scenarios |

The fan-out runs all agents in a single dispatch — they do not see each other's findings, which keeps each agent's signal independent. The command consolidates afterwards, deduplicating findings by `file:line`. The `code-review-methodology` skill calls these six the "6-facet review".

**Path A (agent teams)** runs only in `/flow:review`, and only when `agentTeams: true` AND the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable is set; either alone falls back to Path B. Each of the five agents runs twice, as a skeptic and a verifier, plus `holdout-validation` in both lenses — twelve invocations, and up to ten more in the challenge round. Findings both reviewers raise are matched automatically; the rest go to a challenge round where each reviewer answers the other's findings with AGREE, REFINE or DISAGREE. The agents run on `agentTeamModel` (default `sonnet`). `/flow:pr` and `/flow:address` always use the single-session fan-out.

### What else a review does

- **Confidence decides what a finding can demand.** Every finding carries HIGH (the reviewer ran code, a test or LSP), MEDIUM (read the full code path) or LOW (pattern match). HIGH and MEDIUM findings count toward the review decision; LOW findings go to a "Needs investigation" list and never decide the review. Any HIGH or MEDIUM P1 or P2 → REQUEST_CHANGES; P3 only → COMMENT, and the author fixes every P3 in the PR. On your own PR, a LOW finding must be confirmed by a failing test, refuted, or escalated before the review posts. Source: `references/finding-schema.md`, `skills/code-review-methodology/SKILL.md`.
- **Review exceptions.** `.flow/review-exceptions.md` is a tracked team file of rules the team has already rejected a finding over, each scoped to a path glob. Every reviewer is handed the rows and told not to raise a matching finding; raising one anyway requires the label `exception-override`. The file is read at the PR's base commit, so a PR cannot grant itself an exception. Security findings are never withheld. Rows get there through `/flow:learn`: dismissals recorded by `/flow:address` are clustered into an exception proposal, and promoting the proposal appends the row.
- **The FlowGoal at the PR head.** `/flow:review` reads `.flow/goals/issue-N.goal.yaml` from the PR's head commit and uses its acceptance criteria, non-goals, interface contracts and risk map in the requirements check and reviewer prompts. Its verification commands are read, never run. A PR that removes items from its own goal gets a P2; one that deletes the goal gets a P1.
- **Blast radius.** When a change touches something other code depends on — an OpenAPI, GraphQL or protobuf file, a migration, a schema, an exported signature, a goal's interface contract — `code-reviewer` lists each consumer in a `Blast radius` table, and a consumer the PR does not update is a P1.
- **Dependency review.** `security-reviewer` checks every added, changed or redirected package for advisories, license, install hooks, names close to an existing dependency, and whether anything imports it. These are `DEP-` findings.
- **Duplication.** `bin/flow-clone-scan.sh` runs jscpd against the merge base and reports only duplication this branch added (`duplication.*` settings); `code-reviewer` also judges whether a new symbol reimplements an existing one. Without jscpd installed the scan reports `STATE=unavailable` with the install command, and the review says it did not cover duplication.
- **Grounding critic** — off by default (`review.groundingCritic: "off"`). When set to `"on"`, the single-session fan-out sends each P1/P2 finding to the `finding-critic` agent, and a finding the critic disputes must be backed by cited code or dropped. Security findings are never dropped by this pass. `/flow:pr` reads the setting through the normal cascade; `/flow:review` reads it only from your user settings file, so the PR under review cannot switch it on.

---

## 5. Agents (10)

Each agent is a forked context with its own tool budget. Source: `plugins/flow/agents/*.md`.

| Agent | What it does |
|-------|-------------|
| **implementation-planner** | Parse acceptance criteria, decompose into tasks with dependencies, identify parallel work, add one discriminating test per risk-map row |
| **test-runner** | Discover and run lint/test/typecheck commands, return structured pass/fail |
| **code-reviewer** | Quality + correctness review, P1/P2/P3 findings with file:line citations; blast radius and duplication |
| **convention-checker** | Git convention validation — commit messages, branch naming, PR format |
| **security-reviewer** | OWASP-style review — secrets, auth/authz, input validation, dependency review |
| **error-handler-inspector** | Unhandled errors, missing edge cases, silent failures, exception gaps |
| **integration-verifier** | End-to-end functionality — dev server startup, smoke tests, visual verification, AC validation at runtime. Dispatched by `/flow:pr` Phase 4 |
| **finding-critic** | Tries to refute a consolidated P1/P2 finding from the code. Runs only when `review.groundingCritic` is `on` |
| **verdict-judge** | Independent acceptance-criteria evaluation. **Receives only ACs + evidence bundle + holdout output. No diff, no journal, no rationale, and no file tools.** |
| **goal-evaluator-judge** | Loop-time verdict on a FlowGoal (`achieved`, `not_achieved`, `blocked`, `needs_human_review`) for `/flow:goal evaluate` and the Stop hook's `evaluator-loop` mode |

The verdict-judge is structurally different: it's the only agent whose value depends on what it does NOT see. See §9.

---

## 6. Skills (32 + `learned/`)

32 named skills + a `learned/` directory (promotion area for proposals from `/flow:learn`). Source: `plugins/flow/skills/*/SKILL.md`. Every skill body is at most 600 words; §3 explains how they load.

### Ambient (inlined whole into every command that lists them)

| Skill | What it enforces |
|-------|------------------|
| **llm-operator-principles** | Convergence means zero findings, not an exhausted budget. Every finding is fixed in the PR. No calendar-time estimates. Consulted by every command. |
| **evidence-based-development** | "Evidence before claims, always." File:line citations required. ASSERTION/EVIDENCE/VERIFIED pattern. P1/P2/P3 priority system. |
| **autonomous-workflow** | EPCV iron law, three-tier classification, per-task verification gate, bounded verification. |
| **code-quality-principles** | Boy Scout Rule, secret-free commits, prohibition of mocks/stubs/TODOs in production code. |

### Dispatched (contract inlined; body runs via `Skill()`)

| Skill | When it activates |
|-------|------------------|
| **issue-crafting** | Creating GitHub issues — solution-agnostic requirements, duplicate detection, verifiable AC |
| **branch-and-task-management** | Starting work — branch naming, issue context loading, AC decomposition |
| **change-classification** | Preparing commits — in-context vs out-of-context vs uncertain, first-touch flagging |
| **convention-enforcement** | Commits/PRs — detect project rules from CLAUDE.md and settings, validate compliance |
| **capability-discovery** | Start of any workflow — detect agents, quality commands, tech stack, LSP availability |
| **specification-capture** | Start of work — non-goals, failure modes, interface contracts and the risk map, written to the journal |
| **code-review-methodology** | Code review — 2-stage review (spec compliance, then quality), confidence levels, P1/P2/P3 synthesis, deduplication by file:line |
| **criterion-verification-map** | Plan time — classify each AC, produce verification command + evidence shape + does-NOT-promise + risk areas. Verify time — assemble evidence bundle |
| **pr-lifecycle** | Creating PRs — pre-flight, body generation, reviewer suggestion, comprehension narrative |
| **preflight-checks** | Pure-bash validation — clean git, gh auth, issue exists, remote reachable. No LLM calls |
| **feedback-resolution** | Addressing review comments — categorize, surgical fixes, ambiguity handling, pushback on evidence only, re-review request |
| **holdout-validation** | Cross-reference self-review claims against actual file state using hidden scenarios |
| **merge-and-release** | Tier 3 operations — prerequisite verification, semantic versioning, changelog generation |
| **merge-conflict-resolution** | Resolving conflicts — detection, classification, per-file strategy, post-resolution verification |
| **runtime-verification** | After static checks — build, dev server startup, API smoke tests, E2E, LSP diagnostics |
| **visual-verification** | UI changes — screenshot each configured viewport, and drive the changed user flow (click, type) when a criterion describes an interaction. Needs an interactive browser tool (Playwright MCP or Chrome DevTools MCP) |
| **team-coordination** | Adversarial review (when `agentTeams: true`) — independent analysis before shared conclusions |
| **architecture-patterns** | System design — design-from-functionality, coupling analysis, C4 thinking |
| **brainstorming** | Approach exploration — option generation, trade-off analysis, collaborative selection |
| **debugging-patterns** | Any verification failure — structured log analysis, hypothesis testing, fix validation. Activates on test/build/server failures, not just `bug` label |
| **tdd-patterns** | Implementation — Red-Green-Refactor cycle, test quality, runner discipline. Enforced when `tddMode: enforce` |
| **goal-contract-capture** | Writing a FlowGoal contract after the Spec Validation Gate |
| **goal-evaluator** | Evaluating a FlowGoal — deterministic checks first, the judge only for fuzzy criteria |
| **goal-evidence-ledger** | Recording the evidence that proves a criterion |
| **goal-lifecycle** | Every FlowGoal status change, with a journal record |
| **run-state-management** | FlowRun records at each phase boundary, so `/flow:resume` can pick up |
| **trigger-policy** | What a FlowTrigger may do — never a merge or release |
| **workflow-validation** | Checking workflow definitions |
| **`learned/`** | Promotion area for `/flow:learn` proposals. A proposal lands here only when a human promotes it. It holds one promoted skill today, `a-check-that-can-only-confirm`. |

---

## 7. Hooks — what's actually wired

Source of truth: `plugins/flow/hooks/hooks.json`.

| Trigger | Matcher | Script | What it does |
|---------|---------|--------|--------------|
| PreToolUse | Bash | `block-force-push.sh` | Exit 2 on `git push --force`, `-f` or a `+refspec`. `--force-with-lease` is allowed. A command it cannot read is blocked rather than allowed |
| PreToolUse | Bash | `block-destructive.sh` | Exit 2 on `rm -rf` (except build and cache directories), `git reset --hard`, `git clean -f`, `git checkout -- .` / `git restore .`, and force-deleting a branch that is not merged into the default branch |
| PreToolUse | Bash | `block-unchecked-merge.sh` | Exit 2 on `gh pr merge` while any check is queued, running or failed, on `--auto` where the base branch requires no checks, and on any merge not written as `gh pr merge <N> --repo owner/name` with `--squash`, `--merge` or `--rebase` |
| PreToolUse | Bash | `block-secrets.sh` | Exit 2 on inline credentials |
| PreToolUse | Bash | `ask-issue-create.sh` | Turns `gh issue create` into a permission prompt while a FlowGoal is active (the fix-it-here rule). Off when `minimalScope: true` |
| PostToolUse | Edit\|Write\|NotebookEdit | `log-file-changes.sh` | Append `<!-- auto-log: ... -->` entry to the local, gitignored trail (`{journal.dir}/auto-log/`) — not to the tracked journal — and record the edit in the session quality ledger |
| PostToolUse | Bash | `log-commits.sh` | Append a commit breadcrumb to the same local trail. Two guards bound the append loop: the commit subject starting with `chore(decisions):`, and a commit that touched only the tracked journal. |
| PostToolUse and PostToolUseFailure | Bash | `record-quality-run.sh` | Record each test, lint, typecheck or build run, its exit code and a digest of the working tree, in the session quality ledger. Never blocks |
| TaskCompleted | (any) | `verify-task-completion.sh` | Per-Task Verification Gate enforcement: exit 2 while files have changed since the last passing quality run. `testing.taskCompletionGate` = `block` (default), `warn` or `off` |
| TeammateIdle | (any) | `nudge-idle-teammate.sh` | Used with agent teams — nudges a teammate idle for 60 seconds or more |
| SessionEnd | (any) | `session-end-learn.sh` | Marks `/flow:learn` as pending when learning is enabled; it does not run the analysis |
| SessionEnd | (any) | `session-end-state.sh` | Notes the session end on any active FlowRun, so `/flow:resume` can pick it up; prunes old quality ledgers |
| Stop | (any) | `flow-goal-stop.sh` | Checks the active FlowGoal's evidence before the agent stops. Default `warn` never blocks (§12) |
| Stop | (any) | `reply-style-check.sh` | Checks the reply against a project's reply-style list and reports what it finds. Off unless the project sets `replyStyle.enabled: true`; never blocks |

That's fourteen scripts. There is no `gate-merge` or `gate-release` hook script; merge/release confirmation is in the **command** files via AskUserQuestion. Hooks cannot be switched off in settings (`references/gate-configuration.md`, "Hook Override"); the only way is to edit the scripts.

---

## 8. Decision journal — the audit trail

Source: `plugins/flow/references/decision-journal-schema.md`.

**Default location**: `.decisions/` (configurable via `journal.dir`).

**Two entry kinds**:

1. **Auto-log entries** (HTML comments, written by hooks) — these live in the local, gitignored trail at `{journal.dir}/auto-log/`, not in this journal, so a teammate never sees them:
   ```
   <!-- auto-log: 2026-05-05 14:32 Edit path/to/file -->
   <!-- auto-log: 2026-05-05 14:35 commit "feat: add --json flag to sync" -->
   ```
   An entry written inside a subagent ends with `agent=<type>`.
2. **Structured entries** (Markdown, written by skills):
   ```markdown
   ### [Implementation] Title

   **Timestamp**: 2026-05-05 14:40
   **Sensitivity**: public

   **Decision**: What was decided.
   **Reasoning**: Why this approach.
   **Alternatives considered**: …
   **Evidence**: links/output/files.
   ```

**Sensitivity**: set per entry. `public` (the default when an entry has no `Sensitivity:` line) goes into PR bodies; `internal` entries appear there only as "[Internal decision]". There is no setting that changes the default.

**Categories**: `Architecture`, `Implementation`, `Convention`, `Quality`, `Risk`.

The journal is the input to `/flow:learn` (together with session transcripts) and to `/flow:explain`. If the journal disappears, those features lose their substrate.

---

## 9. Holdout validation and the verdict-judge

The two independence mechanisms.

### Holdout validation

The `holdout-validation` skill maintains hidden scenarios that the executing agent never sees. After self-review, it cross-references the agent's claims against actual file state, including whether each expected value in the tests has the source the evidence bundle claims and whether every risk-map row has a test. "I added a test for X" without a test that actually tests X is a P1.

### Verdict-judge

The verdict-judge agent receives **only**:

1. Acceptance criteria (from the issue).
2. Evidence bundle (verification commands + outputs + the required subsections, including test inputs and expected values as rows).
3. Holdout-validation output.

It does NOT see:

- The diff (no code changes)
- The decision journal (no rationale)
- Planning notes (no approach choices)
- Self-review findings from the code-writing agent
- Project memory from previous sessions
- Test source files and screenshots — it has no file tools at all, so anything not in the bundle is a FAIL

(Source: `plugins/flow/agents/verdict-judge.md`.)

This separation is the answer to "but how does the agent know if it's right?" — by deliberately limiting what the judge sees, FAIL/PASS becomes a function of evidence alone, not of self-told stories. If the evidence doesn't prove the criterion, FAIL — even if the code is "obviously correct."

**Step 1 (mandatory)**: missing-criterion scan. Before evaluating any criterion on its merits, the judge checks every AC has evidence and every required subsection. A bundle with three of four ACs covered fails fast — you can't pass on partial coverage.

---

## 10. Configuration cascade

Settings resolve in priority order (later overrides earlier; for each key, the highest file that sets it wins):

1. `plugins/flow/settings.json` — plugin defaults
2. `~/.claude/settings.flow.json` — user global (or the file named by `FLOW_USER_SETTINGS`)
3. `.claude/settings.flow.json` — project shared (committed)
4. `.claude/settings.flow.local.json` — project local (gitignored)

The full schema is in `plugins/flow/schema.json`. Defaults are in `plugins/flow/settings.json`. The conventions decided in the workshop land here — see `CONVENTIONS-WORKSHEET.md` for the mapping.

---

## 11. Failure modes and where to look

| Symptom | Look here |
|---------|-----------|
| "Why did the plan get blocked?" | `.decisions/issue-N.md` for the most recent entry. Search for "Stranger Test" or "Spec Validation Gate." |
| "The verdict is FAIL but the code works" | The evidence bundle — a missing or blank required subsection, an expected value copied from the implementation, or evidence that is not in the bundle is an automatic FAIL. `references/evidence-bundle-format.md` lists the subsections. |
| "Hooks aren't firing" | `plugins/flow/hooks/hooks.json` — confirm matcher and trigger. Check `~/.claude/logs/` for hook stderr. |
| "Auto-log is duplicating commits" | Run `claude plugins update flow` to refresh the script. The two guards test the commit subject and the commit's file list; nothing depends on the journal's existing contents. |
| "/flow:learn isn't proposing skills" | `~/.claude/flow-proposals/` for proposals; ensure `learning.enabled: true`, and that `learning.sources` includes `journal` (with a populated `journal.dir`) or `transcripts`. |
| "Agent teams not spawning" | Both `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var must be set, and only `/flow:review` uses them. |
| "Tier 3 prompt isn't appearing" | `/flow:merge` and `/flow:release` always ask, whatever the `tiers` setting says. If no prompt appeared, the merge or release did not go through the command. |
| "Force push got blocked but I needed it" | Use `--force-with-lease` instead — explicitly allowed (`three-tier-safety.md`, Tier 3 table). |
| "`gh pr merge` got blocked" | A check is still queued, running or failed, or the command is not in the one shape the hook reads: `gh pr merge <N> --repo owner/name --squash`. Wait with `gh pr checks <N> --watch`, or use `/flow:merge`. |
| "Task won't complete" | The `TaskCompleted` gate: files changed after the last passing test, lint, typecheck or build run. Re-run the checks. |
| "`/flow:merge` blocks on the FlowGoal" | Run `/flow:goal evaluate <id>`; the goal must reach `achieved`. |

---

## 12. FlowGoals and the Stop hook

Source: `plugins/flow/references/flow-goals.md`, `references/stop-hook-goal-enforcement.md`.

A **FlowGoal** is the completion contract for a piece of work, stored at `.flow/goals/<id>.goal.yaml` and committed with the branch. You rarely create one by hand:

- `/flow:start` creates `.flow/goals/issue-N.goal.yaml` when the Spec Validation Gate passes with at least one acceptance criterion that has a verification command (`flow.goals.goalCreation: "auto"`). A spec-free issue creates no goal.
- `/flow:debug` creates one after the hypothesis is confirmed.
- Lifecycle: `draft → active → waiting_for_user / waiting_for_ci / blocked → achieved / failed / cancelled`.
- `/flow:merge` refuses to merge while the branch's active goal is not `achieved`.
- `/flow:status` shows the goal's state; `/flow:goal evaluate <id>` runs its checks and records a verdict.

The **Stop hook** (`flow-goal-stop.sh`) looks at the active goal whenever the agent is about to stop. `flow.goals.stopHookEnforcement` picks its behaviour:

| Mode | What happens |
|------|--------------|
| `warn` (default) | The stop is always allowed. If evidence is missing, the message says `FLOW_GOAL_INCOMPLETE — stop ALLOWED`. |
| `block` | The stop is blocked while a criterion fails or has no verification command, up to `failAfterStuckTurns` (default 3) consecutive blocks. Verification commands run only for goals flow created on your machine (the trust ledger), unless `executeVerificationCommands: true`. |
| `evaluator-loop` | Deterministic checks first; if fuzzy criteria remain, the `goal-evaluator-judge` agent (model `flow.goals.judge.model`, default `haiku`) decides whether the agent keeps working. |

In `evaluator-loop` mode two limits end a loop:

- **Turn budget** — the goal's `continuation.max_iterations` (default 20). Only a stop that blocks, and a non-final `/flow:goal evaluate`, spend a turn; a stop that is allowed spends nothing. When the budget is spent, a stop that would block marks the goal `failed` (`budget_exhausted`) instead.
- **Stuck detection** — when the judge reports no progress (`delta: unchanged`) for `failAfterStuckTurns` turns in a row, the goal is marked `failed` (`stuck_no_progress`). A failing required check counts as no progress. Any progress or regression resets the count.

Other runtime state lives beside the goals: FlowRuns in `.flow/runs/` (gitignored; read by `/flow:resume`), FlowTriggers in `.flow/triggers/` (they describe when to wake up; they never merge or release), and review exceptions in `.flow/review-exceptions.md` (§4).

---

## Appendix A — Coming from `gh-workflow`?

If you've used the `gh-workflow` plugin, the verbs carry over; the autonomy doesn't. The two plugins can both be installed, but `/flow:setup` warns when it detects gh-workflow and advises enabling only one at a time to avoid hook conflicts.

| gh-workflow | flow equivalent | What's different |
|-------------|-----------------|------------------|
| `/gh-start` | `/flow:start` | Adds Phase 0 preflight + Spec Validation Gate |
| `/gh-commit` | `/flow:commit` | Same vocabulary; classification + the local auto-log trail |
| `/gh-pr` | `/flow:pr` | Parallel agent review (five agents + holdout validation) before PR creation |
| `/gh-review` | `/flow:review` | Adversarial team option (`agentTeams: true`) |
| `/gh-address` | `/flow:address` | Re-review of the fix commits by the same five agents + `FLOW_RESOLUTION_CYCLE` ledger |
| `/gh-merge` | `/flow:merge` | Both Tier 3; flow's prereq check is structural |
| `/gh-release` | `/flow:release` | Both Tier 3; flow generates changelog from merged PRs |

Migration is a config decision, not a code change: commit-message vocabulary, branch patterns, and reviewer routing carry over. If your team prefers a more interactive style, set `tddMode: suggest` and `verdict.requireAllPass: false` — strict defaults are opt-out (`plugins/flow/README.md`, section "Opting Out").

---

## Appendix B — file paths quick reference

```
plugins/flow/
├── README.md                                   ← Excellence Principles + skill tree
├── CHANGELOG.md                                ← release history (versioning reference)
├── settings.json                               ← all defaults
├── schema.json                                 ← full config schema
├── .claude-plugin/plugin.json                  ← version
├── agents/{10}.md                              ← one file per agent
├── commands/{23}.md                            ← one file per command
├── skills/{32}/SKILL.md + learned/             ← knowledge units
├── bin/                                        ← helper scripts (settings cascade, skill loader, journal writers, scanners)
├── workflows/*.workflow.yaml                   ← workflow definitions
├── references/                                 ← canonical contracts, among them:
│   ├── three-tier-safety.md
│   ├── escalation-format.md
│   ├── finding-schema.md
│   ├── finding-ledger-parser.md
│   ├── evidence-bundle-format.md
│   ├── decision-journal-schema.md
│   ├── gate-configuration.md
│   ├── flow-goals.md
│   ├── stop-hook-goal-enforcement.md
│   ├── skill-manifests.md
│   ├── code-review-checklist.md
│   └── test-review-checklist.md
├── templates/
│   ├── issue-body.md
│   ├── pr-body.md
│   ├── self-review-comment.md
│   ├── review-comment.md
│   ├── resolution-comment.md
│   ├── skill-proposal.md
│   ├── CLAUDE-flow.md
│   └── holdout-scenarios/
└── hooks/
    ├── hooks.json
    └── scripts/*.sh                            ← 14 wired scripts + 2 the Stop hook calls

.decisions/                                     ← decision journal (tracked); auto-log/ inside it is local
.flow/                                          ← goals, triggers, review exceptions (tracked); runs/ (local)
```
