---
marp: true
theme: default
paginate: true
header: 'Flow Plugin Team Workshop · 90 min'
footer: 'docs/flow-team-session/slides.md'
style: |
  section { font-size: 24px; }
  section.lead h1 { font-size: 56px; }
  section h1 { font-size: 36px; }
  section h2 { font-size: 28px; }
  pre { font-size: 18px; }
  table { font-size: 20px; }
  blockquote { border-left: 6px solid #888; padding-left: 12px; color: #444; }
---

<!-- _class: lead -->
<!-- _paginate: false -->

# Flow Plugin Team Workshop

A 90-min walkthrough of `/flow` v2.0.1 — for engineers, PMs, and designers.

By the end of this session: you'll share a mental model, you'll have voted on 10 conventions, and you'll have the plugin running.

---

## The one promise

By 1:30, every engineer has flow installed and the team has a checked-in `CONVENTIONS-DECIDED.md` that drives `.claude/settings.flow.json`.

That's it. If we don't deliver that, we wasted your morning.

---

## Before / after a flow PR

```
[MOCKUP]

BEFORE                              AFTER
─────                               ─────
Issue: "Add JSON output"            Issue: 4 ACs, each with verification command
PR: "Adds --json flag"              PR: comprehension report + 4 verdicts (PASS×4)
                                       review findings table sorted P1→P3
                                       FLOW_RESOLUTION_CYCLE: empty
                                       finding-ledger: clean
                                       merge: confirmed
```

The shape of "done" is the difference. Strict by default — opt out, don't opt in.

---

## Agenda — 90 min

| Time | Mins | What |
|------|------|------|
| 0:00–0:05 | 5 | Open + the one promise |
| 0:05–0:13 | 8 | 6 Excellence Principles |
| 0:13–0:21 | 8 | 3-tier safety + Explore-Plan-Code-Verify |
| 0:21–0:28 | 7 | Skills / Agents / Commands |
| 0:28–0:53 | 25 | **Pre-recorded walkthrough** (4 pause beats) |
| 0:53–1:03 | 10 | Command depth |
| 1:03–1:18 | 15 | **Conventions vote** (10 decisions, live worksheet) |
| 1:18–1:25 | 7 | **Hands-on** — `/flow:setup` + `/flow:status` |
| 1:25–1:30 | 5 | Q&A + Monday checklist |

---

<!-- _class: lead -->

# Section B — The 6 Excellence Principles

Mental model first. Without these, the rest of the plugin reads as bureaucracy.

---

## Principle 1 — Stranger Test

Every plan must be executable by someone with **zero prior context**. If it requires "you know what I mean" reasoning, the PLAN phase blocks until rewritten.

**Failure mode it prevents**: implementer joins the PR mid-cycle, can't tell what "fix the auth thing" means, makes the wrong fix.

> Source: `plugins/flow/README.md` line 11.

---

## Principle 2 — Spec-as-Eval-Suite

[QUOTE] `plugins/flow/skills/criterion-verification-map/SKILL.md` line 15:

> **EVERY ACCEPTANCE CRITERION IS AN EVAL SOURCE.** At plan time, each criterion must produce a runnable verification command. No criterion is deferred to verify time with "we'll figure out how to test this later." No criterion passes by assumption. No criterion is "too obvious to verify."

**Failure mode**: tests pass, criteria are never actually verified, the PR ships and breaks production.

---

## Principle 3 — Proactive Autonomy

The six-field escalation template (`plugins/flow/skills/autonomous-workflow/SKILL.md` lines 162–173):

| Field | Purpose |
|-------|---------|
| **Situation** | What happened — the specific state or finding that requires a decision |
| **What I tried** | What you attempted before escalating — research, alternatives, commands run |
| **Options** | 2–3 concrete paths forward, each with trade-offs. Label one "(Recommended)" |
| **My recommendation** | Which option you recommend and why — never blank |
| **Time sensitivity** | Blocking? Urgent? Safe to defer? |
| **Risk if wrong** | Consequence of wrong choice, and who is affected |

"What should I do?" is blocked. Always.

---

## Principle 4 — Quality > Speed

Strict defaults (`plugins/flow/README.md` lines 35–39):

| Setting | Old Default | New Default |
|---------|-------------|-------------|
| `testing.tddMode` | `"suggest"` | `"enforce"` |
| `verdict.requireAllPass` | `false` | `true` |

**P3 findings are no longer deferrable** — fix in-PR or file a six-field escalation.

**Failure mode**: "tests pass" treated as proof of correctness when only the happy path was tested.

---

## Principle 5 — No Lazy Verification

Every criterion's evidence MUST include three completeness subsections:

- **What was NOT tested** — explicit list of related behaviors not covered.
- **Known limitations of this evidence** — how it could be misleading even though it looks positive.
- **Negative/adversarial cases covered** — specific failure modes the system rejects.

Source: `plugins/flow/skills/criterion-verification-map/SKILL.md` lines 89–106.

The verdict-judge FAILs any criterion missing these subsections. Don't omit them. Write "none" if there's nothing — never blank.

---

## Principle 6 — No Incomplete Shipments

From `plugins/flow/CHANGELOG.md` v2.0.0:

- Pre-existing findings keep natural priority — no longer capped at P3.
- Merge gate blocks when `FLOW_RESOLUTION_CYCLE` markers contain unresolved or escalated items.
- **"DEFERRED" markers renamed to "ESCALATED"** to signal that deferral is not an option.

If a finding matters enough to mention, it matters enough to act on.

---

<!-- _class: lead -->

# Section C — The two skeletons

Three-tier safety + Explore-Plan-Code-Verify. Tiers are the *consequence* of the principles; EPCV is their *shape*.

---

## Three-tier safety — the table

```
[ASCII]  (source: plugins/flow/references/three-tier-safety.md)

┌──────────┬────────────────────────────────┬──────────────────────────────┐
│ Tier 1   │ AUTONOMOUS                     │ Local + reversible           │
│          │ edits, commits, branches, tests│ → Execute. Don't ask.        │
├──────────┼────────────────────────────────┼──────────────────────────────┤
│ Tier 2   │ JOURNAL                        │ Team-visible + recoverable   │
│          │ push, PR create, issue assign  │ → Execute, log, move on.     │
├──────────┼────────────────────────────────┼──────────────────────────────┤
│ Tier 3   │ CONFIRM                        │ Hard to reverse + high blast │
│          │ merge, release, force-push     │ → Always ask. Non-negotiable.│
└──────────┴────────────────────────────────┴──────────────────────────────┘
```

**Promotion rule**: actions can be promoted, never demoted. Safety can never accidentally be reduced.

---

## Three-tier safety — by command

```
[ASCII]

/flow:start ─── creates branch (T1) ─── assigns issue (T2)
/flow:commit ── commit (T1)
/flow:pr ────── push (T2) ─── PR create (T2) ─── parallel review (T1)
/flow:address ─ commits (T1) ─── push (T2) ─── re-request review (T2)
/flow:merge ─── PREREQUISITE CHECK ─── ASK USER (T3) ─── merge
/flow:release ─ CHANGELOG ─── ASK USER (T3) ─── tag + release
```

**Important**: merge/release confirmation is in the **command** files via `AskUserQuestion`. There is no `gate-merge` or `gate-release` hook script. Hooks block force-push, destructive ops, and inline secrets at the Bash layer (`three-tier-safety.md` line 80).

---

## Explore — Plan — Code — Verify

```
[ASCII]

┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│ EXPLORE           │  │ PLAN              │  │ CODE              │  │ VERIFY            │
│                   │  │                   │  │                   │  │                   │
│ parallel reads    │→ │ TaskCreate × N    │→ │ Per-Task Gate     │→ │ 4 layers below    │
│ Skill(            │  │ verification      │  │ TDD red/green/    │  │ verdict-judge     │
│ capability-       │  │ command per AC    │  │ refactor          │  │ INDEPENDENT       │
│ discovery)        │  │ Stranger Test     │  │ commit incremental│  │                   │
│ LSP trace         │  │ gate              │  │ journal auto-log  │  │                   │
└───────────────────┘  └───────────────────┘  └───────────────────┘  └───────────────────┘
```

---

## VERIFY — the four layers

```
[ASCII]  (source: plugins/flow/skills/autonomous-workflow/SKILL.md lines 24–28)

a. STATIC      lint + test + typecheck (parallel) + LSP diagnostics
b. RUNTIME     build + start + smoke test (debug-fix-retest, bounded)
c. REVIEW      self-review with FIX-FORWARD (P1/P2 fixed, not just reported)
d. VERDICT     dispatch verdict-judge agent
                  ├─ receives: ACs + evidence bundle + holdout output
                  └─ does NOT receive: diff, journal, planning notes, self-review
```

---

## The Iron Law

[QUOTE] `plugins/flow/skills/autonomous-workflow/SKILL.md` line 13:

> **NO SKIPPING PHASES. Explore before Plan, Plan before Code, Code before Verify. Every phase produces an artifact.**

Jumping to code without exploration is the #1 cause of rework. Jumping to "done" without verification is the #1 cause of bugs reaching review.

---

<!-- _class: lead -->

# Section D — Vocabulary

Skills, agents, commands. Different containers, different reuse profiles.

---

## Skills / Agents / Commands

```
[ASCII]

         ┌────── COMMANDS ──────┐    "things you type"
         │  17 entry points     │    /flow:start  /flow:pr  ...
         │  drive workflow phase│
         └──────┬───────────────┘
                │ dispatches
                ▼
         ┌────── AGENTS ────────┐    "specialists you hire"
         │  8 forked contexts   │    verdict-judge, security-reviewer
         │  narrow tool budgets │    (own context, own memory none)
         └──────┬───────────────┘
                │ load
                ▼
         ┌────── SKILLS ────────┐    "playbooks Claude reads"
         │  22 + learned/       │    autonomous-workflow,
         │  reusable knowledge  │    criterion-verification-map, ...
         │  iron laws + protocols│
         └──────────────────────┘
```

---

## Skill library tree

```
[ASCII]  (source: plugins/flow/README.md lines 86–112)

FOUNDATION (always loaded, stable shape)
├── evidence-based-development      ── citations, P1/P2/P3, ASSERTION/EVIDENCE/VERIFIED
├── autonomous-workflow             ── EPCV, tiers, six-field escalation
└── code-quality-principles         ── Boy Scout, no mocks/TODOs in prod

DOMAIN (contextually invoked, max 3 concurrent)
├── issue-crafting                  ── solution-agnostic AC drafting
├── branch-and-task-management      ── start work, decompose ACs
├── change-classification           ── in-context vs out-of-context commits
├── convention-enforcement          ── git conventions per project
├── capability-discovery            ── tech stack + LSP probing
├── code-review-methodology         ── 2-stage review, dedup by file:line
├── criterion-verification-map      ── eval-as-spec, evidence bundle
├── pr-lifecycle                    ── push, PR body, comprehension narrative
├── preflight-checks                ── pure bash gates
├── feedback-resolution             ── address reviewer comments surgically
├── holdout-validation              ── hidden scenarios, claim verification
├── merge-and-release               ── Tier 3 prereq verification
├── merge-conflict-resolution       ── classify + resolve + verify
├── runtime-verification            ── build, run, smoke test
├── team-coordination               ── adversarial review (opt-in)
├── architecture-patterns           ── design-from-functionality, C4
├── brainstorming                   ── option generation, trade-off analysis
├── debugging-patterns              ── on any verification failure (not bug-only)
├── tdd-patterns                    ── Red-Green-Refactor, runner discipline
└── learned/                        ── promoted proposals from /flow:learn
```

---

## The 8 agents

| Agent | What it does |
|-------|-------------|
| **implementation-planner** | Parse ACs, decompose tasks, identify parallel work |
| **test-runner** | Run lint/test/typecheck, return structured pass/fail |
| **code-reviewer** | Quality + correctness, P1/P2/P3 with file:line |
| **convention-checker** | Git conventions — commits, branches, PR format |
| **security-reviewer** | OWASP, secrets, auth, input validation, deps |
| **error-handler-inspector** | Unhandled errors, missing edge cases, silent failures |
| **integration-verifier** | E2E — dev server, smoke tests, ACs at runtime |
| **verdict-judge** | **Independent** AC evaluation — sees only ACs + evidence + holdout |

---

## Verdict-judge — information isolation

```
[ASCII]  (source: plugins/flow/skills/criterion-verification-map/SKILL.md lines 127–138)

         INPUTS                                  NOT INPUTS
         ──────                                  ──────────
    ┌─ Acceptance Criteria                  ┌─ The diff
    │  (from the issue)                     │  (no code changes)
    │                                       │
    ├─ Evidence Bundle                      ├─ Decision journal
    │  (verification commands + outputs +   │  (no rationale)
    │   completeness subsections)           │
    │                                       ├─ Planning notes
    └─ Holdout-validation output            │  (no approach choices)
                                            │
                                            ├─ Self-review findings
                                            │  (no "I think it works")
                                            │
                                            └─ Memory from prior sessions
```

This is the answer to "but how does the agent know if it's right?". By limiting what the judge sees, PASS becomes a function of evidence alone.

---

## Holdout validation in 30 seconds

The `holdout-validation` skill maintains hidden scenarios the executing agent never sees.

After self-review, it cross-references the agent's claims against actual file state.

> "I added a test for X" without a test that actually tests X is a P1.

Behavioral verifier — grep the files, read the test assertions, check the error handlers. Skeptical, secure, fair.

---

## Hooks — what's actually wired

```
[ASCII]  (source: plugins/flow/hooks/hooks.json — 8 scripts)

PreToolUse   Bash   block-force-push.sh         exit 2 on git push --force
PreToolUse   Bash   block-destructive.sh        exit 2 on rm -rf, git reset --hard
PreToolUse   Bash   block-secrets.sh            exit 2 on inline credentials
PostToolUse  Edit   log-file-changes.sh         <!-- auto-log: ... -->
PostToolUse  Bash   log-commits.sh              <!-- auto-log: commit ... -->
TaskCompleted (any) verify-task-completion.sh   per-task verification gate
TeammateIdle (any)  nudge-idle-teammate.sh      experimental, agent-teams
SessionEnd   (any)  session-end-learn.sh        feeds learning loop
```

**Note**: `gate-merge` / `gate-release` are not wired and don't exist as scripts. Merge/release confirmation is at the **command** level via `AskUserQuestion`. README's "10 hooks" is stale; the wired count is 8.

---

<!-- _class: lead -->

# Section E — The walkthrough

20 min recorded · 4 pause beats for narration · synthetic scenario.

---

## Demo scenario — `--json` flag for `/sync`

> **Issue**: Add `--json` flag to `/sync` command emitting structured output for CI.
>
> **Acceptance Criteria** (4 types in 4 lines):
> 1. AC1 — `sync --json` exits 0 + emits JSON `{ status, items, errors }` against healthy remote
> 2. AC2 — `sync --json` exits non-zero + emits `{ status: "error", message }` on auth failure
> 3. AC3 — `--help` lists `--json` with description
> 4. AC4 — non-JSON output unchanged when `--json` absent

Each AC has a runnable verification command, decided **at plan time**.

---

## What to watch for in the recording

1. **Phase 0 PRE-FLIGHT** runs as pure bash, fails fast before any LLM tokens.
2. **Spec Validation Gate** rejecting "works correctly" — the principle in action.
3. **Verdict-judge prompt** — see what it does NOT receive.
4. **FLOW_RESOLUTION_CYCLE** marker — the merge gate's substrate.

If only one of these lands: the verdict-judge prompt. That's where independence becomes operational.

---

## Pause beat 1 — eval-as-spec (after PLAN)

[PAUSE 75s]

We've just watched `criterion-verification-map` produce a verification command for each AC.

Look at AC1's row: the command was decided **right now, at plan time**. We are not going to write the test and then claim it covers the criterion. We're committing to a check before any code is written.

That's eval-as-spec.

---

## Pause beat 2 — independence (after VERIFY)

[PAUSE 75s]

Read what the judge sees: acceptance criteria, evidence bundle, holdout output. That's it.

No diff. No journal. No "here's why we chose this approach."

If your evidence doesn't prove the AC, the judge will say FAIL — and that's the point. The judge is independent because it can be.

---

## Pause beat 3 — fix or escalate (after /flow:address)

[PAUSE 60s]

`FLOW_RESOLUTION_CYCLE` marker — the finding-ledger.

DEFERRED is gone. ESCALATED is what's left. P3 used to be a polite note you could ignore. Now it's fix in this PR or file a six-field escalation. The merge gate enforces it.

---

## Pause beat 4 — structural confirmation (before merge)

[PAUSE 45s]

Tier 3. Merge is hard to reverse — once it's on the default branch, getting it off is a revert commit visible to everyone.

The plugin will not auto-merge. The hooks will not auto-merge. Even if a custom command tried, `block-force-push` and `block-destructive` catch the recovery attempt.

Confirmation here is structural. The user has to say yes.

---

<!-- _class: lead -->

# Section F — Command depth

17 commands, grouped. Daily five, Tier 3, supporting, entry-point variants, rare.

---

## The daily five

```
[MOCKUP]

/flow:start <issue>     ─── EXPLORE → PLAN → branch + tasks
/flow:commit            ─── classify → atomic conventional commit
/flow:pr                ─── push → parallel agent review → PR with body
/flow:review <pr>       ─── 5-facet review (or adversarial team)
/flow:address <pr>      ─── categorize comments → surgical fix → re-request
```

Every other command exists to *not* interrupt the daily five. If you find yourself reaching for them often, the convention defaults need tuning, not the workflow.

---

## `/flow:start` — Phase 0 preflight

[QUOTE] `plugins/flow/commands/start.md` lines 36–62 (verbatim):

```bash
ERRORS=0
WARNINGS=0

# 1. Clean git state
[ -n "$(git status --porcelain)" ] && echo "PREFLIGHT FAIL: Uncommitted changes" && ERRORS=$((ERRORS+1))

# 2. Not detached HEAD
git symbolic-ref HEAD >/dev/null 2>&1 || { echo "PREFLIGHT FAIL: Detached HEAD"; ERRORS=$((ERRORS+1)); }

# 3. gh CLI authenticated
gh auth status >/dev/null 2>&1 || { echo "PREFLIGHT FAIL: gh CLI not authenticated"; ERRORS=$((ERRORS+1)); }

# 4. Issue exists and is open
ISSUE_STATE=$(gh issue view $ARGUMENTS --json state --jq '.state' 2>/dev/null)
[ "$ISSUE_STATE" != "OPEN" ] && echo "PREFLIGHT FAIL: Issue #$ARGUMENTS not found or not open (state: ${ISSUE_STATE:-not found})" && ERRORS=$((ERRORS+1))

# 5. Remote accessible
git ls-remote --exit-code origin >/dev/null 2>&1 || { echo "PREFLIGHT FAIL: Cannot reach remote 'origin'"; ERRORS=$((ERRORS+1)); }

# 6. Already on feature branch (warning only)
git branch --show-current | grep -q "issue-$ARGUMENTS" && echo "PREFLIGHT WARN: Already on branch for issue #$ARGUMENTS" && WARNINGS=$((WARNINGS+1))

echo "PREFLIGHT: $ERRORS error(s), $WARNINGS warning(s)"
[ $ERRORS -gt 0 ] && echo "PREFLIGHT: BLOCKED" && exit 1
echo "PREFLIGHT: PASSED"
```

Pure bash. No LLM calls. Fails fast before spending tokens.

---

## `/flow:pr` — parallel review

```
[MOCKUP]

push (T2)
   ↓
parallel agent fan-out:
   ├── code-reviewer         (quality + correctness)
   ├── security-reviewer     (OWASP, secrets, auth)
   ├── convention-checker    (commit format, branch, PR shape)
   ├── error-handler-inspector  (unhandled, silent failures)
   ├── integration-verifier  (E2E smoke)
   └── holdout-validation    (claim verification)
   ↓
findings deduplicated by file:line, sorted P1 → P3
   ↓
PR body assembled (templates/pr-body.md)
   ↓
public journal entries → comprehension report
```

---

## Supporting three

| Command | Purpose | When to reach for it |
|---------|---------|---------------------|
| **`/flow:status`** | Read-only workflow overview — assigned issues, open PRs, branch state, journal health | Mondays. After lunch. Whenever you've context-switched. |
| **`/flow:explain`** | Q&A about decisions on the current branch/issue, loads journal + diff | "Why did we do it this way?" |
| **`/flow:learn`** | Analyze the journal for patterns, generate skill proposals | Quarterly. After a project ships. After 10+ issues with similar mistakes. |

---

## Entry-point variants

| Command | Use when |
|---------|---------|
| **`/flow:issue`** | Filing a new issue. Solution-agnostic AC drafting, duplicate detection, label discovery. Spec Validation Gate fires here. |
| **`/flow:brainstorm`** | Before committing to an approach. Multiple options + trade-off analysis. |
| **`/flow:debug`** | A bug report you can't reproduce yet. Structured root-cause analysis. |
| **`/flow:design`** | A feature where the architecture matters. C4 thinking, coupling analysis. |

These shape work *before* the daily five. They prevent the daily five from being applied to ill-formed inputs.

---

## Rare / bootstrap

| Command | When |
|---------|------|
| **`/flow:setup`** | Once per repo. Detect tech stack, generate `.claude/settings.flow.json`, configure LSP, optionally add CLAUDE.md sections, warn about plugin coexistence. |
| **`/flow:resolve`** | Merge conflicts on a branch or PR. Detect conflict type, classify, per-file strategy, post-resolution verification. |
| **`/flow:flow`** | Universal dispatcher — `/flow <verb> <target>`. Useful in scripts; humans should type the specific verb. |

---

<!-- _class: lead -->

# Section G — Conventions vote

10 decisions. 90 sec each. Worksheet on screen — we don't advance past a row until it has an answer.

---

## Why these are team decisions

Defaults in `plugins/flow/settings.json` are deliberately strict (Excellence Principle 4). But strict-by-default only works if the team has consciously chosen to live with strict.

Cascading override locations:

1. `plugins/flow/settings.json` — plugin defaults
2. `~/.claude/settings.flow.json` — user global
3. `.claude/settings.flow.json` — **project shared (committed)** ← we'll write to this
4. `.claude/settings.flow.local.json` — project local (gitignored)

If you vote anything non-default, that vote lands in #3 as part of the post-session PR.

---

## Decision 1 — TDD mode

**Default**: `enforce`

**Options**: `enforce` (test-first required, RED-GREEN-REFACTOR observed) | `suggest` (test-first encouraged, not gated)

**Lands in**: `settings.flow.json` → `testing.tddMode`

**Forcing question**: do we want the Per-Task Verification Gate to block merge on missing tests?

---

## Decision 2 — Verdict requires all pass

**Default**: `true`

**Options**: `true` (all ACs must PASS for verdict to be PASS) | `false` (PR can proceed with FAIL/NEEDS-HUMAN-REVIEW criteria)

**Lands in**: `settings.flow.json` → `verdict.requireAllPass`

**Forcing question**: do we trust the judge to fail us when we deserve it?

---

## Decision 3 — Agent teams (adversarial review)

**Default**: `false` (off)

**Options**: `false` | `true` (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var)

**Lands in**: `settings.flow.json` → `agentTeams` + env

**Forcing question**: do we want `/flow:review` to spawn an adversarial team where reviewers challenge each other's findings? Higher signal, higher cost.

---

## Decision 4 — Branch naming patterns

**Default**: `feature/issue-{N}-{desc}`, `fix/issue-{N}-{desc}`, `docs/issue-{N}-{desc}`

**Options**: keep defaults | adjust prefixes (e.g. `feat/`, `bugfix/`) | add new categories

**Lands in**: `settings.flow.json` → `conventions.branchPatterns`

---

## Decision 5 — Commit type vocabulary

**Default** (12 types from `plugins/flow/settings.json` line 18):

`feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert, improve`

**Options**: keep all 12 | drop ones we won't use | add team-specific types

**Lands in**: `settings.flow.json` → `conventions.commitTypes`

---

## Decision 6 — Journal sensitivity default

**Default**: `public` (entries go into PR bodies)

**Options**: `public` (transparent default) | `internal` (redacted by default, must opt-in to public)

**Lands in**: `settings.flow.json` → `journal.sensitivityDefault`

**Forcing question**: do we want PR bodies to expose decision rationale by default, or hide it by default?

---

## Decision 7 — Tier overrides

**Defaults**: push=journal, prCreate=journal, issueAssign=journal, issueCreate=journal, merge=confirm, release=confirm

**Options**: keep defaults | promote any to `confirm` (more friction, more safety)

**Reminder**: tiers can be promoted, never demoted. Once `merge: confirm` is set, you can't go back to autonomous.

**Lands in**: `settings.flow.json` → `tiers`

---

## Decision 8 — Spec-free label list

**Default**: `["documentation", "chore"]` — issues with these labels can skip the AC requirement

**Options**: keep defaults | add labels (e.g. `dependency-bump`) | remove (force AC for everything)

**Lands in**: `settings.flow.json` → `specFirst.allowSpecFreeLabels`

---

## Decision 9 — Reviewer routing (policy)

**Default**: n/a — this is policy, not config.

**Options**: round-robin | by area (frontend/backend/infra) | by author preference | least-recently-reviewed

**Lands in**: `CONVENTIONS-DECIDED.md` (policy section). The plugin doesn't enforce — humans do.

---

## Decision 10 — Learning-loop cadence (policy)

**Default**: n/a — this is policy.

**Options**: who runs `/flow:learn` and how often? who triages `~/.claude/flow-proposals/`? who promotes to `skills/learned/`?

**Lands in**: `CONVENTIONS-DECIDED.md` (policy section).

**Suggestion**: monthly cadence, rotating owner. A proposal that nobody triages is a missed pattern.

---

<!-- _class: lead -->

# Section H — Hands-on

Everyone runs `/flow:setup` and `/flow:status` now. Five minutes. We don't move on until everyone has a green status.

---

## `/flow:setup` — what to expect

```
[MOCKUP]  (matches commands/setup.md flow)

> /flow:setup
Phase 1 — detecting environment...
  • language: TypeScript (tsconfig.json found)
  • test/lint/typecheck: jest, eslint, tsc --noEmit
  • CLAUDE.md: present
  • gh-workflow plugin also installed (commands coexist; see HANDBOOK §12)

Phase 2 — generating .claude/settings.flow.json (merge with existing if present)

Phase 3 — LSP setup
  ⚠ INTERACTIVE: setup will ask:
    1. Which LSP servers to install for your stack? (all / pick / skip)
    2. Register the Piebald-AI/claude-code-lsps marketplace? (yes / skip)
    3. ENABLE_LSP_TOOL not set — add to ~/.claude/settings.json? (yes / no)

flow: setup complete. Try /flow:status next.
```

**Heads-up for hands-on**: the LSP phase is interactive — accept defaults to keep moving. Re-run is safe (won't overwrite settings without confirmation).

---

## `/flow:status` — what to expect

```
[MOCKUP]  (matches commands/status.md output structure)

> /flow:status

## Flow Status

### Current Branch
- Branch: feature/issue-142-sync-json-flag
- Commits ahead: 4 ahead of main
- Uncommitted changes: 0 files

### My Issues (Open)
| #   | Title                                   | Labels       |
|-----|-----------------------------------------|--------------|
| 142 | Add JSON output to /sync command        | enhancement  |
| 156 | Investigate flaky session test          | bug          |

### My PRs
| #  | Title                       | Status      | Checks |
|----|-----------------------------|-------------|--------|
| 43 | feat: rate-limit middleware | APPROVED    | passed |

### Awaiting My Review
| #  | Title                  | Author     |
|----|------------------------|------------|
| 44 | refactor session store | @teammate  |

### Decision Journal
- Journals: 1 active
- Learning: 3 proposals pending in ~/.claude/flow-proposals/

### Suggested Next Action
PR #43 is approved with passing checks → `/flow:merge 43`
```

Read-only. Safe to run anywhere, anytime. The "Suggested Next Action" line picks the most useful next command from the table in `commands/status.md`.

---

## Common gotchas

1. **`gh` CLI not authenticated** — preflight fails. Fix: `gh auth login`.
2. **Dirty worktree on `/flow:start`** — preflight fails. Fix: stash or commit before starting.
3. **No `CLAUDE.md`** — `/flow:setup` will offer to add a `CLAUDE-flow.md` section. Accept it or compose your own.
4. **`block-force-push` blocks a legitimate rebase push** — use `--force-with-lease`. Allowed and journaled (`three-tier-safety.md` line 41).
5. **Auto-log seems to duplicate commits** — make sure `plugin.json` shows `2.0.1`. The fix landed in v2.0.1.

---

## Where to look when broken

| Symptom | First place to look |
|---------|--------------------|
| Plan got blocked | `.decisions/issue-N.md` — search "Stranger Test" or "Spec Validation" |
| Verdict FAIL but code works | Evidence bundle — missing completeness subsection? |
| Hooks aren't firing | `~/.claude/logs/` for hook stderr |
| `/flow:learn` empty | `learning.enabled`? `journal.dir` populated? |
| Agent teams not spawning | Both `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var |
| Tier 3 prompt missing | `tiers.merge` / `tiers.release` in your settings cascade |

When in doubt, `/flow:status` first, then `~/.claude/logs/`.

---

<!-- _class: lead -->

# Section I — Close

Monday checklist · the docs · glossary · Q&A.

---

## Monday checklist

- [ ] Pull this branch — `docs/flow-team-session/` is now in the repo.
- [ ] Read `HANDBOOK.md` cover to cover (15 min). Bookmark it.
- [ ] Read `CHEATSHEET.md` (1 page). Print it if that helps.
- [ ] Confirm `/flow:status` works in your daily repo.
- [ ] Pick one in-flight issue and run `/flow:start` against it. Write down what surprises you.
- [ ] If you voted non-default conventions, the follow-up PR will land Wednesday. Review it.

---

## The eight docs

| File | Use it when |
|------|-------------|
| `README.md` (this folder) | Onboarding new teammates — start here |
| `slides.md` | This deck — re-skim sections you missed |
| `HANDBOOK.md` | Something doesn't make sense; deep reference |
| `CHEATSHEET.md` | Daily — pin to the wall |
| `CONVENTIONS-WORKSHEET.md` | The session — fillable template |
| `CONVENTIONS-DECIDED.md` | Source of truth for our `.claude/settings.flow.json` overrides |
| `walkthrough-script.md` | Re-recording the demo or running an offshoot session |
| `faq-and-glossary.md` | "What does ESCALATED mean again?" |

---

## File confusion → file an issue

Confusion is a finding. If something in the docs reads as bureaucracy, it's miscalibrated — file an issue with `documentation` label.

Specifically log:

- A slide that needed extra explanation we didn't anticipate.
- A convention we voted on that turns out to be wrong in practice.
- A skill that activates when it shouldn't (or doesn't when it should).
- A failure mode that wasn't in §11 of the handbook.

The plugin gets better when we tell it where it failed.

---

## Migrating from gh-workflow

Both plugins coexist at the marketplace level. `/flow:setup` warns when both are installed.

Verb mapping:

| gh-workflow | flow | Notes |
|-------------|------|-------|
| `/gh-start` | `/flow:start` | flow has Phase 0 preflight + Spec Validation Gate |
| `/gh-commit` | `/flow:commit` | same vocabulary, different autonomy |
| `/gh-pr` | `/flow:pr` | flow runs parallel agent review |
| `/gh-review` | `/flow:review` | flow supports adversarial teams (opt-in) |
| `/gh-merge` | `/flow:merge` | both Tier 3 |

If you preferred gh-workflow's interactive style: opt out of strict defaults (HANDBOOK §12). Don't fight the plugin — configure it.

---

## Glossary

- **P1 / P2 / P3** — finding priority. P1 blocks merge; P2 fix-in-PR; P3 fix-or-escalate.
- **ESCALATED** — was "DEFERRED" pre-v2.0. Means: a P3 escalated via the six-field structure, not silently dropped.
- **FLOW_RESOLUTION_CYCLE** — marker in PR comments capturing per-cycle resolved + escalated findings. The merge gate's substrate.
- **Holdout** — a hidden test scenario the executing agent never sees. Used by `holdout-validation` to verify self-review claims.
- **Stranger Test** — the gate at end of PLAN. Plan must be executable by someone with zero prior context.
- **Six-field escalation** — Situation / Tried / Options / Recommendation / Time sensitivity / Risk. Mandatory shape for every escalation.
- **Eval-as-spec** — acceptance criteria are eval sources. Each AC produces a runnable verification command at plan time.

---

## Q&A — seed questions

We expect at least one of these. If not, we'll seed it.

- "Can we keep using gh-workflow for legacy repos?" — yes, they coexist. See HANDBOOK §12.
- "What if `/flow:setup` doesn't detect our build?" — file an issue with the project's `package.json` / `pyproject.toml`. Setup is heuristic.
- "What if I disagree with a P3?" — rewrite it as a six-field escalation in the PR. Reviewer accepts/rejects.
- "Can we customize the verdict-judge?" — no. Independence is the feature, not a constraint.
- "What if the recording's demo repo isn't representative?" — that's deliberate (synthetic, not real). The lifecycle is the point, not the language.

---

<!-- _class: lead -->
<!-- _paginate: false -->

# Thanks

Plugin source: `plugins/flow/`
Workshop docs: `docs/flow-team-session/`
File confusion: GitHub issues, `documentation` label.

Now: open a terminal, run `/flow:setup`. Then `/flow:status`. Five minutes.
