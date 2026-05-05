# Flow Plugin Handbook

Long-form reference for the team. The slide deck (`slides.md`) is the room-facing view; this handbook is what you read when something doesn't make sense afterwards.

**Source of truth**: `plugins/flow/` in this repo. When this handbook and the source disagree, the source wins — file an issue.

## Table of contents

1. The 6 Excellence Principles
2. The two skeletons — three-tier safety + Explore-Plan-Code-Verify
3. Vocabulary — skills vs agents vs commands
4. Commands (17) — what each does
5. Agents (8) — what each is for
6. Skills (22 + `learned/`) — knowledge units
7. Hooks — what's actually wired
8. Decision journal — the audit trail
9. Holdout validation and the verdict-judge
10. Configuration cascade
11. Failure modes and where to look

Appendix A — Coming from `gh-workflow`?
Appendix B — File paths quick reference

---

## 1. The 6 Excellence Principles

Flow enforces six principles. They are the answer to "why does this plugin block me?". Source: `plugins/flow/README.md` lines 5–66.

### 1. Stranger Test

Every plan must be executable by someone with zero prior context. If an instruction requires unstated assumptions or "you know what I mean" reasoning, it fails the Stranger Test and the PLAN phase blocks until rewritten.

**Failure mode it prevents**: implementer joins the PR mid-cycle, can't tell what "fix the auth thing" means, makes the wrong fix.

### 2. Spec-as-Eval-Suite

Acceptance criteria are not documentation — they are the eval suite. Each criterion must have a concrete, automated verification command defined **before the PLAN phase begins**. Vague criteria like "works correctly" are rejected by the Spec Validation Gate.

**Failure mode it prevents**: tests pass, criteria are never actually verified, the PR ships and breaks production.

> **Iron Law** (`plugins/flow/skills/criterion-verification-map/SKILL.md` line 15):
> "EVERY ACCEPTANCE CRITERION IS AN EVAL SOURCE. At plan time, each criterion must produce a runnable verification command. No criterion is deferred to verify time with 'we'll figure out how to test this later.' No criterion passes by assumption. No criterion is 'too obvious to verify.'"

### 3. Proactive Autonomy

Agents resolve ambiguity themselves first. When escalation is unavoidable, it follows a structured **six-field format**. Anti-patterns like "what should I do?" are blocked.

The six fields (`autonomous-workflow/SKILL.md` lines 162–173):

| Field | Purpose |
|-------|---------|
| **Situation** | What happened — the specific state or finding that requires a decision |
| **What I tried** | What you attempted before escalating — research, alternatives considered, commands run |
| **Options** | 2-3 concrete paths forward, each with trade-offs. Label one "(Recommended)" |
| **My recommendation** | Which option you recommend and why — never leave this blank |
| **Time sensitivity** | Is this blocking? Urgent? Safe to defer? |
| **Risk if wrong** | What happens if the chosen option turns out to be the wrong call, and who is affected |

**Failure mode it prevents**: agent dumps an open-ended question into a PM's inbox at 11pm on a Friday with no recommendation.

### 4. Quality > Speed

TDD mode defaults to `enforce`. The verdict judge requires all acceptance criteria to pass. P3 findings are fix-or-escalate.

| Setting | Default | Why |
|---------|---------|-----|
| `testing.tddMode` | `"enforce"` | Catching test-first violations at write-time is cheaper than catching them at review-time. The Per-Task Verification Gate observes RED-GREEN-REFACTOR before letting a task complete. Teams that prefer test-after can flip to `"suggest"` (decision 1 in the conventions worksheet) and document the rationale. |
| `verdict.requireAllPass` | `true` | The verdict judge must return PASS for every acceptance criterion or the verdict is FAIL. Partial coverage is a FAIL, not "mostly done." Teams that allow a soft pass on `NEEDS-HUMAN-REVIEW` can set this to `false` and accept the trade-off. |

(`plugins/flow/settings.json`)

**Failure mode it prevents**: "tests pass" treated as proof of correctness when only the happy path was tested.

### 5. No Lazy Verification

Evidence bundles must include three completeness subsections per criterion (`criterion-verification-map/SKILL.md` lines 89–106):

- **What was NOT tested** — explicit list of related behaviors not covered
- **Known limitations of this evidence** — how the evidence could be misleading even though it looks positive
- **Negative/adversarial cases covered** — specific failure modes the system rejects

The verdict-judge treats any criterion missing these subsections as having incomplete evidence and FAILs it.

**Failure mode it prevents**: "test added" claim that turns out to be testing a stub, not the real behavior.

### 6. No Incomplete Shipments

Pre-existing findings in touched files keep their natural priority — they are not capped at P3 just because they were already there when you opened the file. The finding-ledger merge gate blocks merges when `FLOW_RESOLUTION_CYCLE` markers contain unresolved or escalated items. The lifecycle uses **ESCALATED** as its terminal state for any finding the engineer chooses not to fix in-PR — and ESCALATED is auditable (six-field structure required, reviewer must accept). The vocabulary is the policy: there is no silent deferral.

**Failure mode it prevents**: P3 backlog that grows forever and nothing ever gets fixed.

---

## 2. The two skeletons

Two structures hold the plugin together. Learn these and the rest follows.

### 2a. Three-tier safety

Source: `plugins/flow/references/three-tier-safety.md`.

| Tier | What | Behavior | Examples |
|------|------|----------|----------|
| **1 — Autonomous** | Local, reversible | Execute without asking | File edits, commits, branch creation, staging, running tests, agent dispatch |
| **2 — Journal** | Team-visible, recoverable | Execute and log to decision journal | Push, PR creation, issue assignment, issue creation, PR comment |
| **3 — Confirm** | Hard to reverse, high-impact | Always require human confirmation | PR merge, release creation, force push, branch force-deletion |

**Promotion rule**: actions can be promoted (autonomous → journal → confirm) but never demoted. Safety is never accidentally reduced.

**Hook enforcement at the Bash layer**:

| Hook | Action | Behavior |
|------|--------|----------|
| `block-force-push.sh` | `git push --force` | Exit 2 (block) |
| `block-destructive.sh` | `rm -rf`, `git reset --hard` | Exit 2 (block) |
| `block-secrets.sh` | Inline credentials | Exit 2 (block) |

**Important**: merge and release confirmation is handled at the **command level** via AskUserQuestion (see `/flow:merge` and `/flow:release`), not by a `gate-merge` or `gate-release` hook script (`three-tier-safety.md` line 80). The eight wired hook scripts are listed in §7.

### 2b. Explore-Plan-Code-Verify (EPCV)

Source: `plugins/flow/skills/autonomous-workflow/SKILL.md`.

> **Iron Law** (line 13): "NO SKIPPING PHASES. Explore before Plan, Plan before Code, Code before Verify. Every phase produces an artifact."

| Phase | What | Output |
|-------|------|--------|
| **EXPLORE** | Gather context. Parallel reads, agent dispatch, capability discovery, LSP tracing. | Context inventory |
| **PLAN** | Decompose work. TaskCreate per deliverable. Verification command attached to each criterion. Stranger Test gate. | Task list with criteria |
| **CODE** | Execute tasks. TaskUpdate(in_progress) → implement → commit → TaskUpdate(completed) only after Per-Task Verification Gate. | Working code, journal entries |
| **VERIFY** | Four mandatory layers (below). | Evidence bundle, verdict |

**What each phase leaves behind** (concrete artifacts a reader can open):

- **EXPLORE → Artifact**: a populated `.decisions/issue-N.md` with a `## Specification` heading (non-goals, failure modes, interface contracts) and the Spec Validation Gate result mapping each AC to its runnable verification command. Source: `commands/start.md` lines 122–126, 229.
- **PLAN → Artifact**: an atomic TaskList where each task bundles implementation + test + verification command + expected evidence shape; a feature branch off the default branch; the Stranger Test result recorded in the journal under `## Stranger Test` as PASS or BLOCK. Source: `commands/start.md` lines 232–269; `criterion-verification-map/SKILL.md` lines 43–55.
- **CODE → Artifact**: per-task commits, each containing implementation + test + the verification evidence captured at task-completion time (not deferred); `<!-- auto-log: ... -->` entries in the journal for every Edit/Write and commit; the Per-Task Verification Gate satisfied for each task. Source: `autonomous-workflow/SKILL.md` lines 23, 44–59.
- **VERIFY → Artifact**: an evidence bundle (one block per AC with `Does NOT promise` + the three completeness subsections), the holdout-validation output, and the verdict-judge agent's PASS/FAIL/NEEDS-HUMAN-REVIEW per criterion — fed only the evidence bundle + ACs + holdout output. Source: `criterion-verification-map/SKILL.md` lines 68–106, 137–139; `autonomous-workflow/SKILL.md` lines 24–28.

**The four VERIFY layers** (`autonomous-workflow/SKILL.md` lines 24–28):

| Layer | What | Tool |
|-------|------|------|
| **a. Static** | Lint, test, typecheck in parallel + LSP diagnostics if available | `Skill(test-runner)` agent + LSP |
| **b. Runtime** | Build the project, start it, verify at runtime. Debug-fix-retest loop bounded by `closedLoop.maxDebugIterations`. | `runtime-verification` skill |
| **c. Review** | Self-review with **fix-forward** — fix P1/P2 findings immediately, don't just report them | `code-review-methodology` skill |
| **d. Verdict** | Independent judgment. Acceptance criteria + evidence bundle → verdict-judge agent → PASS/FAIL/NEEDS-HUMAN-REVIEW. Judge has no access to diff or journal. | `verdict-judge` agent |

**Per-Task Verification Gate** (`autonomous-workflow/SKILL.md` lines 44–59): a task may NOT be marked completed until ALL of: tests pass, verification evidence captured, no out-of-context files, TDD cycle observed when `tddMode: enforce`. This is the primary quality enforcement point — VERIFY is independent confirmation, not first-pass verification.

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

### Required Skills vs `Skill()` invocation

Commands declare skill dependencies in two complementary ways (`plugins/flow/README.md` lines 142–156):

- **`## Required Skills`** (declarative) — skills that inform the WHOLE command. Loaded as ambient context at the start, applied throughout. Example: `code-review-methodology` for `/flow:review`.
- **`Skill(X)`** (imperative) — explicit forks at specific phase boundaries where the command hands off to a skill for a discrete sub-task. Example: `Skill(capability-discovery)` invoked once during EXPLORE.

Two rules govern usage. First: every command either has a `## Required Skills` section, or an explicit `_None — {reason}_` marker so absence is intentional. Second: every `Skill(X)` invocation in a command body must also appear in that command's `## Required Skills` list. The Required Skills list is the canonical dependency manifest; invocations are phase-specific calls.

Why both: a skill listed as Required is loaded as ambient context; an explicit `Skill()` call is useful when a phase needs the skill's full protocol re-anchored at a specific point. Read-only / dispatcher commands (`status`, `learn`, `explain`, `flow`) typically use the `_None_` marker.

A skill becoming popular enough across commands → it's the right shape. A command duplicating logic from another command → that logic should be a skill.

---

## 4. Commands (17)

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
| `/flow:status` | Read-only workflow overview |
| `/flow:explain` | Interactive Q&A about decisions on the current branch/issue |
| `/flow:learn` | Analyze the decision journal for patterns; generate skill proposals |

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
| `/flow:flow` | Universal dispatcher — `/flow <verb> <target>` |

**Command-level tier-3 prompts**: `/flow:merge` and `/flow:release` invoke `AskUserQuestion` for confirmation. There is no `gate-merge` or `gate-release` hook — the structural gate is in the command file itself plus the Bash hooks for the underlying dangerous operations.

### Parallel agent fan-out — which command, which agents

Three commands dispatch a parallel review fan-out. Knowing which agents run where is useful when reading PR-body findings tables and re-review comments.

`/flow:pr` Phase 3 dispatches six review facets in parallel: `code-reviewer`, `convention-checker`, `test-runner`, `security-reviewer`, `error-handler-inspector`, and `holdout-validation`. The same six run in `/flow:review` Path B; `/flow:address` Phase 4 drops `security-reviewer` (re-review of fix commits doesn't re-test architectural threat surface), leaving five.

| Facet | One-line purpose |
|-------|------------------|
| `code-reviewer` | Quality + correctness review, P1/P2/P3 with file:line citations |
| `convention-checker` | Git convention compliance — commit messages, branch naming, PR shape |
| `test-runner` | Lint, test, typecheck — structured pass/fail report |
| `security-reviewer` | OWASP-style review — secrets, auth/authz, input validation, dep vulns. Not re-run by `/flow:address` |
| `error-handler-inspector` | Unhandled errors, missing edge cases, silent failures |
| `holdout-validation` | Cross-reference self-review claims against actual file state via hidden scenarios |

The fan-out runs all agents in a single dispatch — they do not see each other's findings, which keeps each agent's signal independent. The command consolidates afterwards, deduplicating findings by `file:line`. (The `code-review-methodology` skill describes a separate 5-pillar review frame in source — the workshop count above is the dispatch-side count, since that's what runs.)

---

## 5. Agents (8)

Each agent is a forked context with its own tool budget. Source: `plugins/flow/agents/*.md`.

| Agent | What it does |
|-------|-------------|
| **implementation-planner** | Parse acceptance criteria, decompose into tasks with dependencies, identify parallel work |
| **test-runner** | Discover and run lint/test/typecheck commands, return structured pass/fail |
| **code-reviewer** | Quality + correctness review, P1/P2/P3 findings with file:line citations |
| **convention-checker** | Git convention validation — commit messages, branch naming, PR format |
| **security-reviewer** | OWASP-style review — secrets, auth/authz, input validation, dependency vulnerabilities |
| **error-handler-inspector** | Unhandled errors, missing edge cases, silent failures, exception gaps |
| **integration-verifier** | End-to-end functionality — dev server startup, smoke tests, AC validation at runtime |
| **verdict-judge** | Independent acceptance-criteria evaluation. **Receives only ACs + evidence bundle + holdout output. No diff, no journal, no rationale.** |

The verdict-judge is structurally different: it's the only agent whose value depends on what it does NOT see. See §9.

---

## 6. Skills (22 + `learned/`)

22 named skills + a `learned/` directory (promotion area for proposals from `/flow:learn`). Source: `plugins/flow/skills/*/SKILL.md`.

### Foundation (always loaded; smaller and stable)

| Skill | What it enforces |
|-------|------------------|
| **evidence-based-development** | "Evidence before claims, always." File:line citations required. ASSERTION/EVIDENCE/VERIFIED pattern. P1/P2/P3 priority system. |
| **autonomous-workflow** | EPCV iron law, three-tier classification, six-field escalation template, per-task verification gate. |
| **code-quality-principles** | Boy Scout Rule, secret-free commits, anti-pattern detection, prohibition of mocks/stubs/TODOs in production code. |

### Domain (contextually invoked, max 3 concurrent)

| Skill | When it activates |
|-------|------------------|
| **issue-crafting** | Creating GitHub issues — solution-agnostic requirements, duplicate detection, verifiable AC |
| **branch-and-task-management** | Starting work — branch naming, issue context loading, AC decomposition |
| **change-classification** | Preparing commits — in-context vs out-of-context vs uncertain, first-touch flagging |
| **convention-enforcement** | Commits/PRs — detect project rules from CLAUDE.md and settings, validate compliance |
| **capability-discovery** | Start of any workflow — detect agents, quality commands, tech stack, LSP availability |
| **code-review-methodology** | Code review — 2-stage review (spec compliance, then quality), P1/P2/P3 synthesis, deduplication by file:line |
| **criterion-verification-map** | Plan time — classify each AC, produce verification command + evidence shape + does-NOT-promise. Verify time — assemble evidence bundle |
| **pr-lifecycle** | Creating PRs — pre-flight, body generation, reviewer suggestion, comprehension narrative |
| **preflight-checks** | Pure-bash validation — clean git, gh auth, issue exists, remote reachable. No LLM calls |
| **feedback-resolution** | Addressing review comments — categorize, surgical fixes, ambiguity handling, re-review request |
| **holdout-validation** | Cross-reference self-review claims against actual file state using hidden scenarios |
| **merge-and-release** | Tier 3 operations — prerequisite verification, semantic versioning, changelog generation |
| **merge-conflict-resolution** | Resolving conflicts — detection, classification, per-file strategy, post-resolution verification |
| **runtime-verification** | After static checks — dev server startup, API smoke tests, E2E, browser checks, LSP diagnostics |
| **team-coordination** | Adversarial review (when `agentTeams: true`) — independent analysis before shared conclusions |
| **architecture-patterns** | System design — design-from-functionality, coupling analysis, C4 thinking |
| **brainstorming** | Approach exploration — option generation, trade-off analysis, collaborative selection |
| **debugging-patterns** | Any verification failure — structured log analysis, hypothesis testing, fix validation. Activates on test/build/server failures, not just `bug` label |
| **tdd-patterns** | Implementation — Red-Green-Refactor cycle, test quality, runner discipline. Enforced when `tddMode: enforce` |
| **`learned/`** | Promotion area for `/flow:learn` proposals. Empty until a human reviews and promotes. |

---

## 7. Hooks — what's actually wired

Source of truth: `plugins/flow/hooks/hooks.json`.

| Trigger | Matcher | Script | What it does |
|---------|---------|--------|--------------|
| PreToolUse | Bash | `block-force-push.sh` | Exit 2 on `git push --force` (`--force-with-lease` allowed, journaled) |
| PreToolUse | Bash | `block-destructive.sh` | Exit 2 on `rm -rf`, `git reset --hard`, etc. |
| PreToolUse | Bash | `block-secrets.sh` | Exit 2 on inline credentials |
| PostToolUse | Edit\|Write | `log-file-changes.sh` | Append `<!-- auto-log: ... -->` entry to journal |
| PostToolUse | Bash | `log-commits.sh` | Append commit auto-log entry. The script is idempotent — it skips lines already carrying the `auto-log` marker, so a journal commit cannot trigger another append. |
| TaskCompleted | (any) | `verify-task-completion.sh` | Per-Task Verification Gate enforcement |
| TeammateIdle | (any) | `nudge-idle-teammate.sh` | Experimental — used with agent teams |
| SessionEnd | (any) | `session-end-learn.sh` | Experimental — feeds the learning loop |

That's eight scripts — matching `plugins/flow/README.md` lines 133–139. There is no `gate-merge` or `gate-release` hook script; merge/release confirmation is in the **command** files via AskUserQuestion.

---

## 8. Decision journal — the audit trail

Source: `plugins/flow/references/decision-journal-schema.md`.

**Default location**: `.decisions/` (configurable via `journal.dir`).

**Two entry kinds**:

1. **Auto-log entries** (HTML comments, written by hooks):
   ```
   <!-- auto-log: 2026-05-05 14:32 Edit /path/to/file -->
   <!-- auto-log: 2026-05-05 14:35 commit "feat: add --json flag to sync" -->
   ```
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

**Sensitivity**: `public` (default) goes into PR bodies; `internal` is redacted.

**Categories**: `Architecture`, `Implementation`, `Convention`, `Quality`, `Risk`.

The journal is the input to `/flow:learn` and to `/flow:explain`. If the journal disappears, those features lose their substrate.

---

## 9. Holdout validation and the verdict-judge

The two independence mechanisms.

### Holdout validation

The `holdout-validation` skill maintains hidden scenarios that the executing agent never sees. After self-review, it cross-references the agent's claims against actual file state. "I added a test for X" without a test that actually tests X is a P1.

### Verdict-judge

The verdict-judge agent receives **only**:

1. Acceptance criteria (from the issue).
2. Evidence bundle (verification commands + outputs + completeness subsections).
3. Holdout-validation output.

It does NOT see:

- The diff (no code changes)
- The decision journal (no rationale)
- Planning notes (no approach choices)
- Self-review findings from the code-writing agent
- Project memory from previous sessions

(Source: `plugins/flow/agents/verdict-judge.md`.)

This separation is the answer to "but how does the agent know if it's right?" — by deliberately limiting what the judge sees, FAIL/PASS becomes a function of evidence alone, not of self-told stories. If the evidence doesn't prove the criterion, FAIL — even if the code is "obviously correct."

**Step 1 (mandatory)**: missing-criterion scan. Before evaluating any criterion on its merits, the judge checks every AC has evidence. A bundle with three of four ACs covered fails fast — you can't pass on partial coverage.

---

## 10. Configuration cascade

Settings cascade in priority order (later overrides earlier):

1. `plugins/flow/settings.json` — plugin defaults
2. `~/.claude/settings.flow.json` — user global
3. `.claude/settings.flow.json` — project shared (committed)
4. `.claude/settings.flow.local.json` — project local (gitignored)

The full schema is in `plugins/flow/schema.json`. Defaults are in `plugins/flow/settings.json`. The 10 conventions decided in the workshop land here — see `CONVENTIONS-WORKSHEET.md` for the mapping.

---

## 11. Failure modes and where to look

| Symptom | Look here |
|---------|-----------|
| "Why did the plan get blocked?" | `.decisions/issue-N.md` for the most recent entry. Search for "Stranger Test" or "Spec Validation Gate." |
| "The verdict is FAIL but the code works" | `criterion-verification-map/SKILL.md` — check completeness subsections in the evidence bundle. Missing one = automatic FAIL. |
| "Hooks aren't firing" | `plugins/flow/hooks/hooks.json` — confirm matcher and trigger. Check `~/.claude/logs/` for hook stderr. |
| "Auto-log is duplicating commits" | The script is idempotent only when the marker is intact. If the journal file's `<!-- auto-log: ... -->` lines were edited out, append loops can resurface — restore the markers or run `claude plugins update flow` to refresh the script. |
| "/flow:learn isn't proposing skills" | `~/.claude/flow-proposals/` for proposals; ensure `learning.enabled: true` and `journal.dir` is populated. |
| "Agent teams not spawning" | Both `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var must be set. |
| "Tier 3 prompt isn't appearing" | Check `tiers.merge` and `tiers.release` in your settings cascade. Promoted to `confirm` is the default. |
| "Force push got blocked but I needed it" | Use `--force-with-lease` instead — explicitly allowed and journaled (`three-tier-safety.md` line 41). |

---

## Appendix A — Coming from `gh-workflow`?

If you've used the `gh-workflow` plugin, the verbs carry over; the autonomy doesn't. The two plugins coexist at the marketplace level — `/flow:setup` warns when both are installed.

| gh-workflow | flow equivalent | What's different |
|-------------|-----------------|------------------|
| `/gh-start` | `/flow:start` | Adds Phase 0 preflight + Spec Validation Gate |
| `/gh-commit` | `/flow:commit` | Same vocabulary; classification + journal auto-log |
| `/gh-pr` | `/flow:pr` | 6-facet parallel agent review before PR creation |
| `/gh-review` | `/flow:review` | Adversarial team option (`agentTeams: true`) |
| `/gh-address` | `/flow:address` | 5-facet re-review + `FLOW_RESOLUTION_CYCLE` ledger |
| `/gh-merge` | `/flow:merge` | Both Tier 3; flow's prereq check is structural |
| `/gh-release` | `/flow:release` | Both Tier 3; flow generates changelog from merged PRs |

Migration is a config decision, not a code change: commit-message vocabulary, branch patterns, and reviewer routing carry over. If your team prefers a more interactive style, set `tddMode: suggest`, `verdict.requireAllPass: false`, and promote more tiers to `confirm` — strict defaults are opt-out (`plugins/flow/README.md` lines 40–56). See also: `plugins/flow/references/comparison-with-gh-workflow.md`.

---

## Appendix B — file paths quick reference

```
plugins/flow/
├── README.md                                   ← Excellence Principles + skill tree
├── CHANGELOG.md                                ← release history (versioning reference)
├── settings.json                               ← all defaults
├── schema.json                                 ← full config schema
├── .claude-plugin/plugin.json                  ← version
├── agents/{8}.md                               ← one file per agent
├── commands/{17}.md                            ← one file per command
├── skills/{22}/SKILL.md + learned/             ← knowledge units
├── references/
│   ├── three-tier-safety.md
│   ├── decision-journal-schema.md
│   ├── classification-signals.md
│   ├── code-review-checklist.md
│   ├── gate-configuration.md
│   ├── skill-manifests.md
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
    └── scripts/{8}.sh
```
