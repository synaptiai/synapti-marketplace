---
marp: true
theme: default
paginate: true
header: 'Flow Plugin — Excellence Principles & Agent Architecture'
footer: 'docs/flow-team-session/slides-v2.md'
style: |
  section { font-size: 24px; }
  section.lead h1 { font-size: 56px; }
  section h1 { font-size: 36px; }
  section h2 { font-size: 28px; }
  pre { font-size: 18px; }
  table { font-size: 20px; }
  blockquote { border-left: 6px solid #888; padding-left: 12px; color: #444; }
  /* Dense slides — overrides for tables and code that need more vertical room */
  section.dense { font-size: 18px; }
  section.dense h1 { font-size: 28px; }
  section.dense table { font-size: 14px; }
  section.dense pre { font-size: 14px; }
  section.dense code { font-size: 14px; }
---

<!-- _class: lead -->
<!-- _paginate: false -->

# The Six Excellence Principles

### & Agent Architecture of `/flow`

A deep-dive reference on how Flow's principles, safety model, agents,
and commands combine to produce predictable, verifiable software delivery.

---

## What is Flow?

Flow is a **Claude Code plugin** that wraps your daily development workflow
in a structured pipeline. It doesn't replace your tools — it layers strict
defaults on top of them.

| You keep | Flow adds |
|----------|-----------|
| Your editor, language, test runner | EPCV phase discipline |
| GitHub Issues and PRs | Spec-as-Eval — every AC gets a verification command |
| `git` and `gh` CLI | Three-tier safety — autonomous → journal → confirm |
| Your team's conventions | Convention enforcement agents |
| Your review process | Independent verdict-judge + adversarial review |

**The promise**: the shape of "done" is always the same — evidence-backed
verdicts, auditable decisions, nothing silently deferred.

---

## Core concepts — for someone new to agent-driven workflows

**Agent**: A specialized AI subprocess dispatched with a narrow job and a
limited tool budget. Think "specialist you hire" — the verdict-judge only
judges, the security-reviewer only hunts vulnerabilities.

**Skill**: A reference document encoding policy, philosophy, and protocols.
Skills are the "why" and "how" — the agent reads them to know what rules to
follow. They carry no executable bash.

**Command**: The thing you type (`/flow:start`, `/flow:pr`). Commands own the
bash blocks that run at workflow time and orchestrate agents and skills.

**The loop**: Every piece of work flows through Explore → Plan → Code → Verify.
You can't skip phases. Every phase leaves an artifact you can open and inspect.

**Strict by default**: All quality gates are on. You opt out of strictness
by explicit team decision, never by accident.

---

<!-- _class: lead -->

# The Technical Loop

### Explore → Plan → Code → Verify

---

## EPCV — the full loop

```
EXPLORE                PLAN                  CODE                  VERIFY
parallel reads    →    TaskCreate × N    →   Per-Task Gate    →    4 layers:
Skill(                 verification          TDD red/green/        a. STATIC
  capability-          command per AC        refactor              b. RUNTIME
  discovery)           Stranger Test         commit incremental    c. REVIEW
LSP trace              gate                  journal auto-log      d. VERDICT
```

**Iron Law** (`autonomous-workflow/SKILL.md` line 13):

> NO SKIPPING PHASES. Explore before Plan, Plan before Code, Code before Verify.
> Every phase produces an artifact.

Jumping to code without exploration is the #1 cause of rework.
Jumping to "done" without verification is the #1 cause of bugs reaching review.

---

## What each phase leaves behind

| Phase | Artifact you can open afterwards |
|-------|----------------------------------|
| EXPLORE | `.decisions/issue-N.md` with `## Specification` (non-goals, failure modes, contracts) + Spec Validation Gate mapping each AC to a verification command |
| PLAN | Atomic TaskList (impl + test + verify cmd + expected evidence per task) + feature branch + Stranger Test result in the journal |
| CODE | Per-task commits (impl + test + captured evidence) + `<!-- auto-log: ... -->` journal entries + Per-Task Verification Gate satisfied per task |
| VERIFY | Evidence bundle (per-AC: `Does NOT promise` + 3 completeness subsections) + holdout output + verdict-judge PASS/FAIL/NEEDS-HUMAN-REVIEW |

Sources: `autonomous-workflow/SKILL.md`, `criterion-verification-map/SKILL.md`, `commands/start.md`.

---

## VERIFY — the four layers

```
a. STATIC      lint + test + typecheck (parallel) + LSP diagnostics
b. RUNTIME     build + start + smoke test (debug-fix-retest, bounded)
c. REVIEW      self-review with FIX-FORWARD (P1/P2 fixed, not just reported)
d. VERDICT     dispatch verdict-judge agent (INDEPENDENT)
                  ├── receives: ACs + evidence bundle + holdout output
                  └── does NOT receive: diff, journal, planning notes, self-review
```

**Fix-forward** (layer c): the agent fixes P1/P2 findings inline during
self-review rather than reporting them as work-for-the-reviewer.
Bounded by `fixForwardMaxIterations` to prevent loops.

**Per-Task Verification Gate**: a task may NOT be marked completed until
ALL of: tests pass, verification evidence captured, no out-of-context files,
TDD cycle observed (when `tddMode: enforce`).

---

## LSP intelligence — how it integrates with each phase

| Phase | LSP role |
|-------|----------|
| EXPLORE | `Skill(capability-discovery)` probes the LSP for available diagnostics, definitions, references — builds a tech-stack inventory before any code is written |
| PLAN | LSP trace informs task decomposition: knows which symbols exist, which files are affected, where interfaces are defined |
| CODE | LSP diagnostics run continuously during implementation — type errors and reference misses surface at write-time, not review-time |
| VERIFY (Static) | LSP diagnostics are re-run in parallel with lint + test + typecheck — the static layer catches what the compiler catches, plus what the LSP infers |

**Why it matters**: without LSP integration, EXPLORE is grep-and-guess.
With it, the agent knows the codebase's actual shape — symbols, call sites,
interface contracts — before it writes a single line.

---

<!-- _class: lead -->

# The Six Excellence Principles

These are the answer to "why does this plugin block me?"
Every gate, every required subsection, every "can't skip this phase"
traces back to one of these six.

---

## Principle 1 — Stranger Test

> Every plan must be executable by someone with **zero prior context**.

If a plan requires "you know what I mean" reasoning or unstated assumptions,
the PLAN phase **blocks** until rewritten.

**Failure mode it prevents**: an implementer joins the PR mid-cycle, can't tell
what "fix the auth thing" means, makes the wrong fix.

**Concrete example** — a plan that FAILS:

```
Task 2: Fix the auth issue we discussed in standup.
  - Update the middleware
  - Handle the edge case for tokens
```

This fails because: which middleware? Which edge case? What's the expected
behavior after the fix? A stranger reading this has zero information.

---

## Stranger Test — the same plan, rewritten to PASS

```
Task 2: Return 401 with JSON body when JWT is expired
  File: src/middleware/auth.ts (function `validateToken`, line 42-78)
  Change: In the `catch (err)` block (line 57), add a check:
    if (err.name === 'TokenExpiredError') →
      return res.status(401).json({ error: 'token_expired', message: err.message })
  Test: src/middleware/__tests__/auth.test.ts
    - New test: "returns 401 with token_expired when JWT is expired"
    - Verification: `npx jest -t "token_expired" --json`
  Expected evidence: test output showing 1 passing test + HTTP 401 + JSON body match
  Does NOT promise: doesn't handle refresh tokens, doesn't change non-expired error paths
```

Now a stranger can execute this without asking a single question.
The file path, function name, line numbers, expected behavior, and
verification command are all explicit.

> Source: `plugins/flow/README.md` line 11.

---

## Principle 2 — Spec-as-Eval-Suite

> EVERY ACCEPTANCE CRITERION IS AN EVAL SOURCE.

At plan time, each criterion must produce a **runnable verification command**.
No criterion is deferred to verify time with "we'll figure out how to test this later."
No criterion passes by assumption. No criterion is "too obvious to verify."

**The Spec Validation Gate** fires at the EXPLORE→PLAN boundary.
A criterion like "works correctly" is rejected. It must be rewritten.

**Failure mode**: tests pass, criteria are never actually verified,
the PR ships and breaks production.

> Source: `plugins/flow/skills/criterion-verification-map/SKILL.md` line 15.

---

## Spec-as-Eval — how it maps to daily commands

| Command | How Spec-as-Eval applies |
|---------|--------------------------|
| `/flow:issue` | Spec Validation Gate rejects vague ACs. Every AC gets classified (behavioral / API / UI / error / performance / configuration / data / contract) and a verification command is suggested. |
| `/flow:start` | EXPLORE phase runs `Skill(criterion-verification-map)` — produces a concrete verification command + expected evidence shape per AC before PLAN begins. |
| `/flow:pr` | PR body includes a comprehension report that maps each AC to its verification result. Reviewers see "AC1: PASS (evidence: test output)" not "looks good to me." |
| `/flow:merge` | Prerequisite check verifies all ACs have PASS verdicts. A missing verification command at issue-time blocks merge at PR-time. |

**Key insight**: the verification command is decided at **plan time**, not verify time.
This means the team commits to what "done" looks like before writing any code.

---

## Principle 3 — Proactive Autonomy

> "What should I do?" is blocked. Always.

Agents resolve ambiguity themselves first. When escalation is unavoidable,
it follows a structured **six-field format**.

**Failure mode it prevents**: agent dumps an open-ended question into a PM's
inbox at 11pm on a Friday with no recommendation.

**The six-field escalation template** (`autonomous-workflow/SKILL.md` lines 162–173):

| Field | Purpose |
|-------|---------|
| Situation | What happened — the specific state or finding that requires a decision |
| What I tried | What you attempted before escalating — research, alternatives considered, commands run |
| Options | 2–3 concrete paths forward, each with trade-offs. Label one "(Recommended)" |
| My recommendation | Which option you recommend and why — never leave this blank |
| Time sensitivity | Is this blocking? Urgent? Safe to defer? |
| Risk if wrong | What happens if the chosen option turns out to be wrong, and who is affected |

---

## Principle 4 — Quality > Speed

Strict defaults from `plugins/flow/settings.json`:

| Setting | Default | Why |
|---------|---------|-----|
| `testing.tddMode` | `"enforce"` | Catches test-first violations at write-time, cheaper than catching at review-time. RED-GREEN-REFACTOR observed before a task can complete. |
| `verdict.requireAllPass` | `true` | Judge must return PASS for every AC or verdict is FAIL. Partial coverage is a FAIL, not "mostly done." |

**P3 findings are fix-or-escalate** — fix in this PR or file a six-field
escalation. They are not a polite note you can ignore.

**Failure mode**: "tests pass" treated as proof of correctness when only
the happy path was tested.

**How it applies to daily commands**:

| Command | Quality gate |
|---------|--------------|
| `/flow:commit` | Change classification catches out-of-context files before commit |
| `/flow:pr` | Parallel review fan-out (6 facets) before PR creation |
| `/flow:start` | Per-Task Verification Gate blocks task completion without evidence |
| `/flow:merge` | Finding-ledger gate + verdict prerequisite check |

---

## Principle 5 — No Lazy Verification

Every criterion's evidence MUST include three completeness subsections
(`criterion-verification-map/SKILL.md` lines 89–106):

1. **What was NOT tested** — explicit list of related behaviors not covered
2. **Known limitations of this evidence** — how it could be misleading
   even though it looks positive
3. **Negative/adversarial cases covered** — specific failure modes the
   system rejects

The verdict-judge FAILs any criterion missing these subsections.
Don't omit them — write "none" if there's genuinely nothing. Never leave blank.

**Failure mode**: "test added" claim that turns out to be testing a stub,
not the real behavior.

**How it applies**: during `/flow:start` VERIFY phase, the evidence bundle
builder must populate all three subsections per AC. If it doesn't, the
verdict-judge rejects the bundle before even looking at the evidence.

---

## Principle 6 — No Incomplete Shipments

Three rules hold the line (`plugins/flow/README.md` lines 29–31):

- **Pre-existing findings keep their natural priority** — they are not
  capped at P3 just because they were already there when you opened the file.
- **Merge gate blocks** when `FLOW_RESOLUTION_CYCLE` markers contain
  unresolved or escalated items.
- **The vocabulary is the policy**: the lifecycle uses **ESCALATED**,
  not "deferred." A P3 either gets fixed in this PR or escalated through
  the six-field structure. Silent deferral is not an option.

**Failure mode**: P3 backlog grows forever and nothing ever gets fixed.

**How it applies to daily commands**:

| Command | Enforcement |
|---------|-------------|
| `/flow:pr` | Findings table includes pre-existing issues in touched files at natural priority |
| `/flow:address` | Resolution cycle tracks each finding as RESOLVED or ESCALATED |
| `/flow:merge` | Prerequisite check reads `FLOW_RESOLUTION_CYCLE` — blocks on unresolved items |

---

<!-- _class: lead -->

# Three-Tier Safety Model

How Flow prevents accidental or unauthorized command execution.

---

## The three tiers

```
Tier 1    AUTONOMOUS                       Local + reversible
          edits, commits, branches, tests  → Execute. Don't ask.

Tier 2    JOURNAL                          Team-visible + recoverable
          push, PR create, issue assign    → Execute, log, move on.

Tier 3    CONFIRM                          Hard to reverse + high blast
          merge, release, force-push       → Always ask. Non-negotiable.
```

**Promotion rule**: actions can be promoted (autonomous → journal → confirm),
never demoted. Safety can never accidentally be reduced.

> Source: `plugins/flow/references/three-tier-safety.md`.

---

## Tier 1 vs Tier 3 — the contrast

| Aspect | Tier 1 (Autonomous) | Tier 3 (Confirm) |
|--------|---------------------|-------------------|
| Reversibility | Fully reversible (`git reset`, checkout) | Hard to reverse (revert commit on main is permanent history) |
| Blast radius | Local workspace only | Entire team + default branch + potentially production |
| Human involvement | None needed | Required — `AskUserQuestion` prompt |
| Hook protection | Light (log-file-changes, log-commits) | Heavy (block-force-push, block-destructive, block-secrets) |
| Examples | File edits, `git commit`, `git branch`, `npm test` | `git push --force`, PR merge, release creation |
| Journal entry | Auto-log only | Structured entry + auto-log |

**The design philosophy**: Tier 1 trusts the agent to do routine work.
Tier 3 trusts nothing — the human must explicitly confirm.
There is no middle ground for destructive operations.

---

## Tier 3 in detail — how confirmation prevents unintended changes

`/flow:merge` and `/flow:release` are the two Tier 3 commands.
Neither can execute without human confirmation.

**The confirmation sequence for `/flow:merge <pr>`**:

1. **Prerequisite check runs automatically**:
   - All CI checks passed? ✓
   - All reviews approved? ✓
   - All conversations resolved? ✓
   - `FLOW_RESOLUTION_CYCLE` empty (no unresolved/ESCALATED items)? ✓
   - Verdict-judge returned PASS for all ACs? ✓
2. **If any prerequisite fails**: the command stops. Reports what's blocking.
3. **If all pass**: `AskUserQuestion` fires — a structured prompt with the
   merge details (branch, PR #, strategy, target). The agent cannot proceed
   until the human responds.
4. **Human confirms**: merge executes. Squash/rebase per `merge.strategy`.
5. **Human declines**: command exits cleanly. Nothing merged.

---

## Three-tier safety — by command

```
/flow:start  ─── creates branch (T1) ─── assigns issue (T2)
/flow:commit ── commit (T1)
/flow:pr ────── push (T2) ─── PR create (T2) ─── parallel review (T1)
/flow:address ─ commits (T1) ─── push (T2) ─── re-request review (T2)
/flow:merge ─── PREREQUISITE CHECK ─── ASK USER (T3) ─── merge
/flow:release ─ CHANGELOG ─── ASK USER (T3) ─── tag + release
```

**Note**: force-push is Tier 3 and hook-blocked at the Bash layer.
`--force-with-lease` is explicitly allowed as Tier 2 (journaled).

---

<!-- _class: lead -->

# Configuring Settings

### Overriding strict defaults

---

## Settings cascade — lowest to highest priority

```
plugins/flow/settings.json        ← plugin defaults (strict)
~/.claude/settings.flow.json      ← user global overrides
.claude/settings.flow.json        ← project shared (committed)
.claude/settings.flow.local.json  ← project local (gitignored)
```

Later files override earlier ones. The project shared file is committed —
your team's decisions live in version control. The local file is gitignored
for personal preferences that shouldn't be forced on the team.

---

<!-- _class: dense -->

## Key settings and how to override them

| Setting | Default | What it controls | To relax |
|---------|---------|------------------|----------|
| `testing.tddMode` | `"enforce"` | RED-GREEN-REFACTOR required per task | Set to `"suggest"` — recommended but not enforced |
| `verdict.requireAllPass` | `true` | All ACs must PASS or verdict is FAIL | Set to `false` — allows soft pass on `NEEDS-HUMAN-REVIEW` |
| `agentTeams` | `false` | Paired-reviewer + challenge protocol (see slide 35) | Set to `true` + env `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. ≈3.8× LLM cost. Plugin-tier-pinned. |
| `merge.strategy` | `"squash"` | How PRs merge | `"merge"` or `"rebase"` |
| `merge.deleteBranch` | `true` | Auto-delete branch after merge | Set to `false` |
| `journal.sensitivityDefault` | `"public"` | Journal entries included in PR body | Set to `"internal"` for redacted entries |

**Opt-out template**: `plugins/flow/README.md` lines 41–54.

---

## Example: relaxing TDD for a team that prefers test-after

In `.claude/settings.flow.json`:

```json
{
  "testing": {
    "tddMode": "suggest"
  }
}
```

This changes behavior:

- `enforce`: Per-Task Verification Gate blocks task completion if
  RED-GREEN-REFACTOR cycle wasn't observed. Tests must be written first.
- `suggest`: Agent still recommends test-first but won't block
  a task that was implemented before the test was written.

**Convention**: any non-default setting must be documented with rationale
in `CONVENTIONS-DECIDED.md`. The settings file alone isn't enough —
the team needs to know *why* the default was overridden.

---

<!-- _class: lead -->

# Commands

### The daily five and their supporting cast

---

<!-- _class: dense -->

## Daily five

| Command | When to use it | Tier mix |
|---------|----------------|----------|
| `/flow:start <issue>` | Begin work on an issue — preflight, EXPLORE, PLAN with verification commands, branch + tasks, implementation | T1 (branch, commits, tests) + T2 (issue assign) |
| `/flow:commit` | Classify changes, flag out-of-context files, create atomic conventional commits | T1 (commit) |
| `/flow:pr` | Push, 6-facet parallel agent review, PR body with comprehension report + findings table | T2 (push, PR create) + T1 (review agents) |
| `/flow:review <pr>` | Multi-faceted code review — Path B (single-session, default) or Path A (paired skeptic+verifier + challenge round, gated on `agentTeams: true` + env var) | T1 (review) |
| `/flow:address <pr>` | Categorize reviewer comments by P1/P2/P3, apply surgical fixes, re-request review | T1 (commits) + T2 (push, re-request) |

**Pattern**: the daily five keep you in Tier 1 territory 80% of the time.
Tier 2 fires at natural boundaries (push, PR creation).
Tier 3 is reserved for the two irreversible actions: merge and release.

---

## Supporting commands — when to reach for them

**Shape work before implementation**:

| Command | When |
|---------|------|
| `/flow:issue [topic]` | Before filing an issue — AC drafting with Spec Validation Gate, duplicate detection |
| `/flow:brainstorm [topic]` | Before choosing an approach — option generation, trade-off analysis |
| `/flow:debug [error]` | Before chasing a bug you can't reproduce — structured root-cause analysis |
| `/flow:design [feature]` | Before a feature where architecture matters — design validation, C4 diagrams |

**Read-only / learning**:

| Command | When |
|---------|------|
| `/flow:status` | Anywhere, anytime — view assigned issues, open PRs, journal health |
| `/flow:explain` | "Why did we decide X?" — loads journal + diff for current branch/issue |
| `/flow:learn` | Quarterly — analyze decision journal for patterns, generate skill proposals |

---

## Bootstrap and rare commands

| Command | When |
|---------|------|
| `/flow:setup` | Once per repo — detect tech stack, generate settings, configure LSP |
| `/flow:resolve` | Merge conflict on a branch or PR — classify + resolve + verify |
| `/flow:flow` | Universal dispatcher — `/flow <verb> <target>` |

**Tier 3 commands** (always confirm):

| Command | Notes |
|---------|-------|
| `/flow:merge <pr>` | Prerequisite check + `AskUserQuestion`. Hooks block force-push regardless. |
| `/flow:release <type>` | Changelog from merged PRs + `AskUserQuestion`. |

---

<!-- _class: lead -->

# Agents

### The eight specialists and how they interact

---

<!-- _class: dense -->

## The 8 agents — independent roles

| Agent | Role | Tool budget | Dispatched by |
|-------|------|-------------|---------------|
| **implementation-planner** | Parse ACs, decompose into atomic tasks, identify parallel work | `Read, Bash, TaskCreate, TaskList, TaskUpdate, Grep, Glob` | `/flow:start` (PLAN phase) |
| **test-runner** | Run lint/test/typecheck in parallel, return structured pass/fail | `Bash, Read, Glob, Grep` | `/flow:start` (VERIFY static), `/flow:pr` |
| **code-reviewer** | Quality + correctness, P1/P2/P3 findings with file:line citations | `Read, Bash, Grep, Glob, LSP` | `/flow:pr`, `/flow:review` |
| **convention-checker** | Git conventions — commit messages, branch names, PR format | `Bash, Read` | `/flow:pr`, `/flow:review` |
| **security-reviewer** | OWASP Top 10, secrets, auth, input validation, dependency audit | `Read, Bash, Grep, Glob` | `/flow:pr`, `/flow:review` |
| **error-handler-inspector** | Error propagation, panic recovery, error message quality | `Read, Bash, Grep, Glob, LSP` | `/flow:pr`, `/flow:review` |
| **integration-verifier** | E2E runtime verification — build, start, smoke test, visual checks | `Bash, Read, Glob, Grep, TaskCreate, TaskList, TaskUpdate` | `/flow:pr` (Phase 4 verify) |
| **verdict-judge** | Independent PASS/FAIL/NEEDS-HUMAN-REVIEW per AC | `Read` only | `/flow:start` (VERIFY verdict) |

**Note**: `holdout-validation` is a **Skill**, not an Agent — it loads into the orchestrator's context to cross-reference self-review claims against file state. Skills don't get their own subagent spawn.

---

## How the 8 agents interact to ensure code quality

```
/flow:pr — parallel fan-out (Phase 3)

      ┌──────────────────────────────┐
      │ PR diff +                    │
      │ AC list +                    │
      │ journal (public)             │
      └──────────────┬───────────────┘
                     │
       ┌─────────────┼──────────────┬───────────────┐
       ▼             ▼              ▼               ▼
  ┌─────────┐  ┌──────────┐  ┌───────────┐
  │ code-   │  │ convent- │  │ test-     │   ... ×6 parallel
  │ reviewer│  │ checker  │  │ runner    │
  │ P1/P2/P3│  │ branch/  │  │ pass/fail │
  │ file:line│ │ msg      │  │ structured│
  └────┬────┘  └────┬─────┘  └─────┬─────┘
       │            │              │
       └────────────┼──────────────┘
                    ▼
       ┌────────────────────────┐
       │ FINDINGS TABLE         │
       │ sorted P1→P3           │
       │ deduped by file:line   │
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐
       │ PR BODY                │
       │ comprehension report + │
       │ findings + verdict     │
       └────────────────────────┘
```

---

## The verdict-judge — specialized duties

The verdict-judge is **structurally independent**. It receives:

| Sees | Does NOT see |
|------|--------------|
| Acceptance criteria (from the issue) | The diff |
| Evidence bundle (per-AC, with 3 completeness subsections) | Decision journal |
| Holdout-validation output | Planning notes / approach rationale |
|  | Self-review findings |
|  | Memory from prior sessions |

**Why isolation is the feature**: the code-writing agent has goals, rationale,
and ego in the loop. The judge gets only "what was asked" and "what evidence
proves it." If you can't prove the AC against the evidence, it FAILs — even
if the code is "obviously correct."

**Three possible verdicts per AC**:

| Verdict | Meaning |
|---------|---------|
| PASS | Evidence conclusively proves the criterion is satisfied |
| FAIL | Evidence does not prove the criterion (missing, contradictory, or insufficient) |
| NEEDS-HUMAN-REVIEW | Evidence is ambiguous; human judgment required |

---

<!-- _class: dense -->

## Adversarial reviewers — when `agentTeams: true` AND env var set

When agent teams are enabled, the `/flow:pr` and `/flow:review` fan-out
changes from parallel-solo to adversarial paired-reviewer:

```
Normal mode:                    Adversarial mode (agentTeams: true):

code-reviewer ───→ findings     code-reviewer-skeptic    ─┐
                                code-reviewer-verifier   ─┤
convention-checker ─→           convention-checker-S     ─┤
                                convention-checker-V     ─┤
test-runner ──→ pass/fail       test-runner-S            ─┤
                                test-runner-V            ─┤   ├─→ A.2 auto-consensus
                                error-handler-S          ─┤   │   (file ±2 lines, priority ±1)
                                error-handler-V          ─┤   │
                                security-S               ─┤   │
                                security-V               ─┘   │
                                                              │
                            non-consensus findings ─→ A.3 challenge round
                                                       (AGREE/DISAGREE/REFINE,
                                                        no diff re-read)
                                                              │
                                                              ▼
                                                consolidated 7-field marker
                                                (Confidence + Disposition columns)
```

**The challenge phase** (disposition-only): each variant labels the OTHER's findings
as `AGREE` / `DISAGREE` / `REFINE`. No central judge — preserves independence.
Survives → `consensus` / `validated` (HIGH); challenged-but-kept → `kept` (LOW).

**Two gates**: `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
Either alone routes to single-session. **Cost**: ≈3.8× baseline (23 vs 6 calls).
Holdout-validation participates in A.2 only — Skills can't be challenged.

---

<!-- _class: lead -->

# Six-Field Escalation

### When agents hit an impasse

---

## The six-field escalation template

Used for **any human decision** where an agent can't proceed autonomously.
"What should I do?" is blocked — the agent must fill all six fields.

| Field | Purpose |
|-------|---------|
| Situation | What happened — the specific state or finding that requires a decision |
| What I tried | What you attempted before escalating — research, alternatives considered, commands run |
| Options | 2–3 concrete paths forward, each with trade-offs. Label one "(Recommended)" |
| My recommendation | Which option you recommend and why — never leave this blank |
| Time sensitivity | Is this blocking? Urgent? Safe to defer? |
| Risk if wrong | What happens if the chosen option turns out to be the wrong call, and who is affected |

> Source: `autonomous-workflow/SKILL.md` lines 162–173.

---

## Six-field escalation — concrete example

```
Situation:
  AC2 requires sync --json to return {status:"error", message} on auth failure.
  The stub server returns 401 with body {"code":"AUTH_EXPIRED"} — no "message" key.
  The API contract doesn't match the AC.

What I tried:
  1. Checked the API docs at docs/api.md — no "message" field documented.
  2. Checked whether the stub server can be modified — it can, but that changes
     behavior for other test suites.
  3. Checked whether the AC was written against a newer API version — it wasn't.

Options:
  A. Update AC2 to match actual API contract: {status:"error", code} instead of
     {status:"error", message}. Requires PM sign-off. (Recommended)
  B. Modify stub server to add "message" field — 15 min work, but makes stubs
     diverge from production behavior.
  C. Skip AC2 verification and flag as NEEDS-HUMAN-REVIEW — delays merge.

My recommendation:
  Option A. The AC should reflect reality. The PM can confirm whether "message"
  was intentional or an assumption. 5 min conversation vs. 15 min of tech debt.

Time sensitivity:
  Blocking — cannot proceed with AC2 implementation until resolved.

Risk if wrong:
  If "message" is actually required by downstream CI consumers and we drop it,
  their parsing breaks. PM + CI team affected.
```

---

<!-- _class: lead -->

# Step-by-Step Guides

### `/flow:setup` and `/flow:status`

---

<!-- _class: dense -->

## `/flow:setup` — step by step

Run once per repository. The command has **6 phases** in `commands/setup.md`:

| Phase | Action | What you see |
|-------|--------|--------------|
| 1. Detect Environment | Pre-flight (`gh` CLI, `git`, repo root) + tech stack (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`) + build/test/lint command detection | `PREFLIGHT: PASSED` + detected stack: Node.js 20 + TypeScript + Jest |
| 2. Generate Settings | Write `.claude/settings.flow.json` with detected build/test/lint commands and stack-specific defaults | File created with detected values |
| 3. LSP Server Setup | Probe available language servers, write LSP config to settings | `LSP: typescript-language-server detected` |
| 4. Coexistence Warning | If both `flow` and `gh-workflow` plugins are installed, emit a one-time advisory (commands overlap; pick one as primary) | Advisory printed (or skipped if only one plugin) |
| 5. CLAUDE.md Integration | `AskUserQuestion` — offer to append the flow workflow section from `templates/CLAUDE-flow.md` to your existing `CLAUDE.md` (no auto-create if missing) | Append confirmation, decline, or skip |
| 6. Summary | Print configured values, suggested next step (`/flow:status`) | Status dashboard invocation |

**If detection fails**: the fallback is manual. Populate `.claude/settings.flow.json`
with `build`, `test`, `lint` commands by hand and re-run. Journal directory
(`.decisions/`) is created lazily on first `/flow:start` — no separate init phase.

---

<!-- _class: dense -->

## `/flow:status` — step by step

Run anywhere, anytime. Read-only — no side effects.

What it displays:

```
## Flow Status — sync-cli

### Active Work
  Issue: #42 — Add --json flag to sync command
  Branch: feature/issue-42-sync-json-flag
  Phase: VERIFY (layer d — verdict-judge dispatched)
  Tasks: 4/4 completed

### Open PRs
  #17 — Add --json flag (review required, 2 findings unresolved)
  #15 — Fix rate-limit bug (approved, waiting on CI)

### Journal Health
  .decisions/issue-42.md — 12 entries (10 public, 2 internal)
  .decisions/issue-39.md — 8 entries (8 public)
  Last auto-log: 3 minutes ago

### Findings Ledger
  P1: 0    P2: 1 (in fix-forward)    P3: 1 (ESCALATED — awaiting reviewer accept)

### Tier Summary
  Tier 1 events: 47 (commits, branches, tests)
  Tier 2 events: 6 (pushes, PR creates)
  Tier 3 events: 0 (no merges or releases this session)
```

---

<!-- _class: lead -->

# Practical Guidance

### Migration, troubleshooting, and security

---

<!-- _class: dense -->

## Migration checklist — for teams coming from other workflow tools

| # | Step | Done? |
|---|------|-------|
| 1 | **Audit current workflow**: list all automation (CI hooks, PR templates, required checks). Flow may overlap — decide what to keep vs. replace. | ☐ |
| 2 | **Read the principles first**: the six excellence principles are the mental model. Without them, Flow reads as bureaucracy. | ☐ |
| 3 | **Run `/flow:setup` on a test repo first** — not your production repo. Let the team see the generated settings and journal structure. | ☐ |
| 4 | **Decide conventions as a team**: use the 10-decision conventions worksheet. Vote. Commit `CONVENTIONS-DECIDED.md`. | ☐ |
| 5 | **Configure `.claude/settings.flow.json`**: apply any non-default convention decisions. Commit the file. | ☐ |
| 6 | **Pick a pilot issue**: choose a small, well-scoped issue. Run `/flow:start`, `/flow:commit`, `/flow:pr`, `/flow:merge` end-to-end. | ☐ |
| 7 | **Train on `/flow:status`**: make it muscle memory. When confused, status first. | ☐ |
| 8 | **Review the hook scripts**: understand what `block-force-push`, `block-destructive`, and `block-secrets` catch. Don't disable them lightly. | ☐ |
| 9 | **Set a `/flow:learn` cadence**: monthly, rotating owner. The decision journal accumulates patterns — triage them. | ☐ |
| 10 | **Capture lessons in CONVENTIONS-DECIDED.md** as the team's evolving operating manual. | ☐ |

---

<!-- _class: dense -->

## Troubleshooting common issues

| Symptom | First place to look |
|---------|---------------------|
| `/flow:start` blocks at PLAN with "Stranger Test: BLOCK" | `.decisions/issue-N.md` — search for "Stranger Test." The plan has ambiguous instructions. Rewrite with file paths, line numbers, and expected behavior. |
| Verdict-judge returns FAIL but code "looks right" | Evidence bundle completeness subsections. Missing "What was NOT tested" or "Known limitations" → auto-FAIL regardless of evidence quality. |
| `/flow:setup` doesn't detect your build system | Manual fallback: populate `.claude/settings.flow.json` with `build`, `test`, `lint` commands. File an issue with your `package.json` / `pyproject.toml` so the heuristic improves. |
| Hooks not firing | `~/.claude/logs/` — hook execution is logged. Check hook file permissions (`chmod +x`). Verify `hooks.json` is valid. |
| Force push blocked | Use `--force-with-lease` instead — explicitly allowed, journaled at Tier 2. Plain `--force` is Tier 3 and hook-blocked. |
| Auto-log loop (journal grows unboundedly) | Restore `<!-- auto-log: ... -->` markers if they were stripped. Run `claude plugins update flow`. |
| Two engineers on the same issue | Don't. `/flow:start` assigns the issue. Branch creation will conflict. Split into two issues if parallel work is needed. |
| Merge gate keeps blocking | Open the PR. Find the `FLOW_RESOLUTION_CYCLE` marker. Every item must be RESOLVED or have a six-field escalation. ESCALATED is not "deferred." |

---

<!-- _class: dense -->

## Security roles of hooks — preventing destructive operations

Eight hook scripts are wired. Three are the security backstop:

| Hook | Trigger | What it blocks | Exit code |
|------|---------|----------------|-----------|
| `block-force-push` | `PreToolUse` on Bash | `git push --force` (any ref) | Exit 2 (block) |
| `block-destructive` | `PreToolUse` on Bash | `rm -rf`, `git reset --hard`, `git clean -fdx` | Exit 2 (block) |
| `block-secrets` | `PreToolUse` on Bash | Inline credentials, API keys, tokens in command text | Exit 2 (block) |

**Why hooks exist as a separate layer**: command-level guards (like Tier 3
confirmation) can contain bugs. The Bash-layer hooks are the structural
backstop — even if a command file has a logic error that would allow a
destructive action, the hook catches it at the Bash tool boundary.

**Important**: `gate-merge` and `gate-release` are NOT hook scripts.
Merge/release confirmation is at the command level via `AskUserQuestion`.
Hooks block the *underlying git operations*, not the workflow decisions.

---

<!-- _class: dense -->

## The other five wired hooks

Beyond the three security backstops, five more hooks handle observability and journaling — they don't block actions, they observe and annotate:

| Hook | Trigger | Behavior |
|------|---------|----------|
| `log-commits` | `PostToolUse` on Bash (commit) | Appends `<!-- auto-log -->` entry to the decision journal |
| `log-file-changes` | `PostToolUse` on Edit/Write | Appends `<!-- auto-log -->` entry to the decision journal |
| `nudge-idle-teammate` | `Stop` (idle 60s) | Reminds idle teammate to check task list |
| `validate-marker` | `PreToolUse` on PR comment posting | Checks `FLOW_REVIEW_CYCLE` schema before post |
| `journal-tier-tag` | `PostToolUse` on Bash | Tags journal entries with Tier 1/2/3 derived from tool name |

The auto-log markers (`<!-- auto-log: ... -->`) are what `/flow:learn` mines for skill proposals.

---

<!-- _class: dense -->

## Hook enforcement — the defense in depth

```
User types: /flow:merge 42
       │
       ▼
┌────────────────────────┐
│ COMMAND LAYER          │  ← Verifies ACs, CI, reviews, resolution cycle
│ Prerequisite check     │  ← Human must confirm
│ AskUserQuestion        │
└────────────┬───────────┘
       │ (if confirmed)
       ▼
┌────────────────────────┐
│ HOOK LAYER (Bash)      │  ← Even if command layer has a bug,
│ block-force-push       │     these catch the git operations
│ block-destructive      │     before they execute
│ block-secrets          │
└────────────┬───────────┘
       │ (if clean)
       ▼
┌────────────────────────┐
│ git merge (squash)     │  ← Actually executes
│ git branch -d          │
└────────────────────────┘
```

**Two layers, one goal**: no destructive action executes without human
confirmation (command layer) AND no destructive git operation slips
past the Bash filter (hook layer). If either fails, the other catches it.

---

<!-- _class: lead -->

# Summary

---

<!-- _class: dense -->

## What to remember

1. **Six Excellence Principles** — Stranger Test, Spec-as-Eval, Proactive Autonomy,
   Quality > Speed, No Lazy Verification, No Incomplete Shipments. Every gate
   in Flow traces to one of these.

2. **Three-Tier Safety** — Autonomous (T1, don't ask), Journal (T2, log it),
   Confirm (T3, always ask). Actions promote up, never demote down.

3. **EPCV** — Explore, Plan, Code, Verify. No skipping phases. Every phase
   leaves an artifact. Jumping to code without exploration is the #1 rework cause.

4. **Verdict-judge independence** — sees only ACs + evidence + holdout output.
   No diff, no journal, no planning rationale. If the evidence doesn't prove
   the AC, it FAILs. That's the feature.

5. **Strict by default** — all quality gates are on. Opt out by documented
   team decision, never by accident. P3 is fix-or-escalate, never a free pass.

6. **Daily five** — `/flow:start`, `/flow:commit`, `/flow:pr`, `/flow:review`,
   `/flow:address`. These carry you through every work cycle. Tier 3 only
   fires at merge and release.

---

## Questions?

→ `CHEATSHEET.md` — one page, pin to the wall
→ `HANDBOOK.md` — long-form reference, bookmark for later
→ `faq-and-glossary.md` — "what's ESCALATED again?"
→ `/flow:status` — always the first diagnostic
