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

A 90-min walkthrough of the `/flow` plugin — for engineers, PMs, and designers.

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

> Source: `plugins/flow/README.md`, "Excellence Principles".

---

## Principle 2 — Spec-as-Eval-Suite

[QUOTE] `plugins/flow/skills/criterion-verification-map/SKILL.md` line 13:

> Iron law: **every acceptance criterion is an eval source: at plan time it must produce a runnable verification command, or planning is blocked.**

**Failure mode**: tests pass, criteria are never actually verified, the PR ships and breaks production.

---

## Principle 3 — Proactive Autonomy

The six-field escalation template (`plugins/flow/references/escalation-format.md`), delivered via `AskUserQuestion`:

| Field | Purpose |
|-------|---------|
| **Situation** | What specific state requires a decision — concrete facts, readable cold |
| **What I tried** | What was already attempted, and why each path did not resolve it |
| **Options** | 2–3 concrete paths forward, each with a one-line trade-off |
| **Recommendation** | The preferred option, with one sentence of reasoning |
| **Blocking?** | Yes / Soft / No — no calendar-time language |
| **Risk** | What breaks if the choice is wrong or deferred, and who bears the cost |

"What should I do?" is blocked. Always. And deciding what to do with a review finding is not a reason to escalate — the finding is fixed.

---

## Principle 4 — Quality > Speed

Strict defaults (source: `plugins/flow/settings.json`):

| Setting | Default | Why |
|---------|---------|-----|
| `testing.tddMode` | `"enforce"` | Catches test-first violations at write-time, which is cheaper than catching them at review-time. RED-GREEN-REFACTOR is observed before a task can complete. |
| `verdict.requireAllPass` | `true` | The judge must return PASS for every acceptance criterion or the verdict is FAIL. Partial coverage is a FAIL, not a "mostly done." |

**Every finding, P3 included, is fixed in this PR.** A P3 is not a polite note you can ignore, and it is not something to escalate.

**Failure mode**: "tests pass" treated as proof of correctness when only the happy path was tested.

---

## Principle 5 — No Lazy Verification

Every criterion's evidence MUST include `Does NOT promise`, `Visual analysis` (`none — …` for non-UI criteria), and five completeness subsections:

- **What was NOT tested** — explicit list of related behaviors not covered.
- **Known limitations of this evidence** — how it could be misleading even though it looks positive.
- **Negative/adversarial cases covered** — specific failure modes the system rejects.
- **Test inputs and expected values** — from the test source, with where each expected value came from. Never the implementation's own output.
- **Risk map coverage** — the test that tells the right implementation from the plausible wrong one.

Source: `plugins/flow/references/evidence-bundle-format.md`; `criterion-verification-map/SKILL.md`, "Evidence collection protocol".

The verdict-judge FAILs any criterion missing these subsections. Don't omit them. Write "none" if there's nothing — never blank.

---

## Principle 6 — No Incomplete Shipments

Three rules hold the line (source: `plugins/flow/README.md`, "No Incomplete Shipments"; `skills/llm-operator-principles/SKILL.md`):

- Pre-existing findings in touched files keep their natural priority — they are not capped at P3 just because they were already there.
- The merge gate blocks when `FLOW_RESOLUTION_CYCLE` markers contain unresolved or escalated items.
- The lifecycle uses **ESCALATED** (not "deferred"). Every finding is fixed in this PR; escalation is kept for a product decision only the user can make, or a file or dependency flow does not own. Silent deferral is not an option.

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
/flow:pr ────── parallel review (T1) ─── push (T2) ─── PR create (T2)
/flow:address ─ commits (T1) ─── push (T2) ─── re-request review (T2)
/flow:merge ─── PREREQUISITE CHECK ─── ASK USER (T3) ─── merge
/flow:release ─ CHANGELOG ─── ASK USER (T3) ─── tag + release
```

**Important**: merge/release confirmation is in the **command** files via `AskUserQuestion`. There is no `gate-merge` or `gate-release` hook script — Tier 3 confirmation is a structural prompt at command time, not a hook. Hooks block force-push, destructive ops, merges with unfinished or red checks, and inline secrets at the Bash layer (`three-tier-safety.md`, "Hook Enforcement"; `hooks/hooks.json`).

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

## What each phase leaves behind

| Phase | Artifact you can open afterwards |
|-------|----------------------------------|
| **EXPLORE** | `.decisions/issue-N.md` with `## Specification` (non-goals, failure modes, contracts) + Spec Validation Gate mapping each AC to a verification command |
| **PLAN** | Atomic TaskList (impl + test + verify cmd + expected evidence per task) + feature branch + Stranger Test result in the journal |
| **CODE** | Per-task commits (impl + test + captured evidence) + `<!-- auto-log: ... -->` entries in the local, gitignored trail + Per-Task Gate satisfied per task |
| **VERIFY** | Evidence bundle (per-AC: `Does NOT promise` + `Visual analysis` + 5 completeness subsections) + holdout output + verdict-judge PASS/FAIL/NEEDS-HUMAN-REVIEW |

Sources: `autonomous-workflow/SKILL.md`, `criterion-verification-map/SKILL.md`, `commands/start.md`.

---

## VERIFY — the four layers

```
[ASCII]  (source: plugins/flow/skills/autonomous-workflow/SKILL.md lines 18–22)

a. STATIC      lint + test + typecheck (parallel) + LSP diagnostics
b. RUNTIME     build + start + smoke test (debug-fix-retest, bounded)
c. REVIEW      self-review with FIX-FORWARD (findings fixed, not just reported)
d. VERDICT     dispatch verdict-judge agent
                  ├─ receives: ACs + evidence bundle + holdout output
                  └─ does NOT receive: diff, journal, planning notes, self-review
```

---

## The Iron Law

[QUOTE] `plugins/flow/skills/autonomous-workflow/SKILL.md` line 11:

> **NO SKIPPING PHASES. Explore, then Plan, then Code, then Verify. Every phase produces an artifact.**

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
         │  23 entry points     │    /flow:start  /flow:pr  ...
         │  carry executable    │    bash blocks live here, not in skills
         │  bash + workflow     │
         └──────┬───────────────┘
                │ dispatches
                ▼
         ┌────── AGENTS ────────┐    "specialists you hire"
         │  10 forked contexts  │    verdict-judge, security-reviewer
         │  narrow tool budgets │    (own context, memory: none)
         └──────┬───────────────┘
                │ load
                ▼
         ┌────── SKILLS ────────┐    "reference docs Claude reads"
         │  32 + learned/       │    autonomous-workflow,
         │  policy + philosophy │    criterion-verification-map, ...
         │  iron laws + rationale│
         └──────────────────────┘
```

**Design choice**: skills are reference documents — they encode policy, philosophy, and rationale that compounds across sessions. Commands carry the executable bash that runs at workflow time. Keeping these separate means a skill can be re-read by a new command without forking logic, and a command can change its bash without rewriting team knowledge (`plugins/flow/README.md` line 3).

---

## Skill library tree

```
[ASCII]  (source: plugins/flow/README.md, "Architecture")

AMBIENT (inlined whole into every command that lists them)
├── llm-operator-principles         ── converge on zero findings, fix in-PR, no time estimates
├── evidence-based-development      ── citations, P1/P2/P3, ASSERTION/EVIDENCE/VERIFIED
├── autonomous-workflow             ── EPCV, tiers, per-task gate
└── code-quality-principles         ── Boy Scout, no mocks/TODOs in prod

DISPATCHED (contract inlined; body runs via Skill())
├── issue-crafting                  ── solution-agnostic AC drafting
├── branch-and-task-management      ── start work, decompose ACs
├── change-classification           ── in-context vs out-of-context commits
├── convention-enforcement          ── git conventions per project
├── capability-discovery            ── tech stack + LSP probing
├── specification-capture           ── non-goals, failure modes, contracts, risk map
├── code-review-methodology         ── 2-stage review, confidence, dedup by file:line
├── criterion-verification-map      ── eval-as-spec, evidence bundle
├── pr-lifecycle                    ── push, PR body, comprehension narrative
├── preflight-checks                ── pure bash gates
├── feedback-resolution             ── address reviewer comments surgically
├── holdout-validation              ── hidden scenarios, claim verification
├── merge-and-release               ── Tier 3 prereq verification
├── merge-conflict-resolution       ── classify + resolve + verify
├── runtime-verification            ── build, run, smoke test
├── visual-verification             ── screenshots per viewport, drive the changed flow
├── team-coordination               ── adversarial review (opt-in, active)
├── architecture-patterns           ── design-from-functionality, C4
├── brainstorming                   ── option generation, trade-off analysis
├── debugging-patterns              ── on any verification failure (not bug-only)
├── tdd-patterns                    ── Red-Green-Refactor, runner discipline
├── goal-contract-capture, goal-evaluator, goal-evidence-ledger, goal-lifecycle
├── run-state-management, trigger-policy, workflow-validation   ── runtime layer
└── learned/                        ── promoted proposals from /flow:learn
```

---

## The 10 agents

| Agent | What it does |
|-------|-------------|
| **implementation-planner** | Parse ACs, decompose tasks, identify parallel work |
| **test-runner** | Run lint/test/typecheck, return structured pass/fail |
| **code-reviewer** | Quality + correctness, P1/P2/P3 with file:line |
| **convention-checker** | Git conventions — commits, branches, PR format |
| **security-reviewer** | OWASP, secrets, auth, input validation, deps |
| **error-handler-inspector** | Unhandled errors, missing edge cases, silent failures |
| **integration-verifier** | E2E — dev server, smoke tests, ACs at runtime |
| **finding-critic** | Tries to refute a review finding from the code (only when `review.groundingCritic: on`) |
| **verdict-judge** | **Independent** AC evaluation — sees only ACs + evidence + holdout |
| **goal-evaluator-judge** | Judges whether a FlowGoal is achieved (`/flow:goal evaluate`, Stop hook `evaluator-loop`) |

---

## Verdict-judge — information isolation

```
[ASCII]  (source: plugins/flow/skills/criterion-verification-map/SKILL.md, "Judge isolation")

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
                                            ├─ Memory from prior sessions
                                            │
                                            └─ Test source, screenshots
                                               (no file tools at all)
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
[ASCII]  (source: plugins/flow/hooks/hooks.json — 14 scripts)

PreToolUse   Bash   block-force-push.sh         exit 2 on git push --force
PreToolUse   Bash   block-destructive.sh        exit 2 on rm -rf, git reset --hard
PreToolUse   Bash   block-unchecked-merge.sh    exit 2 on gh pr merge with unfinished/red checks
PreToolUse   Bash   block-secrets.sh            exit 2 on inline credentials
PreToolUse   Bash   ask-issue-create.sh         asks before gh issue create (active goal)
PostToolUse  Edit   log-file-changes.sh         <!-- auto-log: ... --> (local trail)
PostToolUse  Bash   log-commits.sh              <!-- auto-log: commit ... --> (local trail)
PostToolUse  Bash   record-quality-run.sh       records test/lint runs (also on failure)
TaskCompleted (any) verify-task-completion.sh   blocks while edits postdate last passing check
TeammateIdle (any)  nudge-idle-teammate.sh      agent-teams
SessionEnd   (any)  session-end-learn.sh        marks /flow:learn pending
SessionEnd   (any)  session-end-state.sh        notes session end on active runs
Stop         (any)  flow-goal-stop.sh           FlowGoal evidence check (warn by default)
Stop         (any)  reply-style-check.sh        opt-in reply-style check, never blocks
```

**Note**: `gate-merge` / `gate-release` are not hook scripts. Merge and release confirmation runs at the **command** level via `AskUserQuestion` (`plugins/flow/references/three-tier-safety.md`, "Hook Enforcement"). The hook layer (Bash exit-2 blocks) catches the dangerous primitives — `git push --force`, `rm -rf`, an unchecked `gh pr merge`, inline credentials — that any recovery attempt would have to use.

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
2. **A vague criterion** ("works correctly") rejected, and each criterion mapped to a verification command at the Spec Validation Gate — the principle in action.
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

Every finding ends up **resolved**, **escalated** or **disputed**. All are auditable; none is silent. By default every finding is fixed in this PR; escalation is kept for a decision only the user can make, and a dispute needs evidence. The merge gate reads this marker — anything escalated, and anything not resolved, blocks merge.

---

## Pause beat 4 — structural confirmation (before merge)

[PAUSE 45s]

Tier 3. Merge is hard to reverse — once it's on the default branch, getting it off is a revert commit visible to everyone.

The plugin will not auto-merge. The hooks will not auto-merge. Even if a custom command tried, `block-force-push` and `block-destructive` catch the recovery attempt.

Confirmation here is structural. The user has to say yes.

---

<!-- _class: lead -->

# Section F — Command depth

23 commands, grouped. Daily five, Tier 3, supporting, entry-point variants, rare, runtime/admin.

---

## The daily five

```
[MOCKUP]

/flow:start <issue>     ─── EXPLORE → PLAN → branch + tasks
/flow:commit            ─── classify → atomic conventional commit
/flow:pr                ─── parallel agent review → push → PR with body
/flow:review <pr>       ─── 6-facet parallel review (adversarial team: opt-in via agentTeams)
/flow:address <pr>      ─── categorize comments → surgical fix → re-request
```

Every other command exists to *not* interrupt the daily five. If you find yourself reaching for them often, the convention defaults need tuning, not the workflow.

---

## `/flow:start` — Phase 0 preflight

[QUOTE] `plugins/flow/commands/start.md` lines 82–117 (verbatim excerpt; `fail` and `warn` count and record each reason):

```bash
# 0. Issue number required (all-digit; non-digit input is rejected above)
[ -z "$ISSUE_NUM" ] && fail "Issue number required (all-digit)"

# 1. Clean git state
[ -n "$(git status --porcelain)" ] && fail "Uncommitted changes"

# 2. Not detached HEAD
git symbolic-ref HEAD >/dev/null 2>&1 || fail "Detached HEAD"

# 3. gh CLI authenticated
gh auth status >/dev/null 2>&1 || fail "gh CLI not authenticated"

# 4. Issue exists and is open
if [ -n "$ISSUE_NUM" ]; then
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null)
  [ "$ISSUE_STATE" != "OPEN" ] && fail "Issue #$ISSUE_NUM not found or not open (state: ${ISSUE_STATE:-not found})"
fi

# 5. Remote accessible
git ls-remote --exit-code origin >/dev/null 2>&1 || fail "Cannot reach remote 'origin'"

# 6. Already on feature branch (warning only)
# …
[ -n "$ISSUE_NUM" ] && git branch --show-current | grep -q "issue-$ISSUE_NUM" && warn "Already on branch for issue #$ISSUE_NUM"

printf '%s\n' "### Pre-Flight"
printf '%s\n' "ISSUE_NUM=$ISSUE_NUM"
printf '%s\n' "PREFLIGHT_ERRORS=$ERRORS"
printf '%s\n' "PREFLIGHT_WARNINGS=$WARNINGS"
if [ $ERRORS -gt 0 ]; then
  printf '%s\n' "PREFLIGHT_STATE=BLOCKED"
else
  printf '%s\n' "PREFLIGHT_STATE=PASSED"
fi
```

Pure bash. No LLM calls. Fails fast before spending tokens.

---

## `/flow:pr` — parallel review

```
[MOCKUP]

parallel agent fan-out (Phase 3):
   ├── code-reviewer         (quality + correctness, blast radius, duplication)
   ├── convention-checker    (commit format, branch, PR shape)
   ├── test-runner           (lint, test, typecheck)
   ├── security-reviewer     (OWASP, secrets, auth, dependencies)
   ├── error-handler-inspector  (unhandled, silent failures)
   └── holdout-validation    (skill — claim verification)
   ↓
findings deduplicated by file:line, sorted P1 → P3, fixed before push
   ↓
push (T2)
   ↓
PR body assembled (templates/pr-body.md)
   ↓
public journal entries → comprehension report
```

---

## Supporting three

| Command | Purpose | When to reach for it |
|---------|---------|---------------------|
| **`/flow:status`** | Read-only workflow overview — a five-line dashboard by default; `--full` adds issues, PRs, goals, runs, triggers, findings | Mondays. After lunch. Whenever you've context-switched. |
| **`/flow:explain`** | Q&A about decisions on the current branch/issue, loads journal + diff | "Why did we do it this way?" |
| **`/flow:learn`** | Analyze the journal and session transcripts for patterns, generate skill and review-exception proposals | Quarterly. After a project ships. After 10+ issues with similar mistakes. |

---

## Entry-point variants

| Command | Use when |
|---------|---------|
| **`/flow:issue`** | Filing a new issue. Solution-agnostic AC drafting, duplicate detection, label discovery. Vague criteria are rejected here; the Spec Validation Gate runs in `/flow:start`. |
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

**Runtime / admin** — `/flow:goal`, `/flow:workflow`, `/flow:trigger`, `/flow:run`, `/flow:resume`, `/flow:watch`. They inspect the goals, workflows, triggers and runs flow manages for you; `/flow:start` creates the goal on its own.

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

**Options**: `enforce` (test-first required, RED-GREEN-REFACTOR observed) | `suggest` (test-first encouraged, not gated) | `off`

**Lands in**: `settings.flow.json` → `testing.tddMode`

**Forcing question**: do we want the Per-Task Verification Gate to block task completion when the test was not written first?

---

## Decision 2 — Verdict requires all pass

**Default**: `true`

**Options**: `true` (all ACs must PASS for verdict to be PASS) | `false` (a person can approve a criterion the judge marked NEEDS-HUMAN-REVIEW)

**Lands in**: `settings.flow.json` → `verdict.requireAllPass`

**Forcing question**: do we trust the judge to fail us when we deserve it?

---

## Decision 3 — Agent teams (adversarial review)

**Default**: `false` (off)

**Options**: `false` | `true` (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var)

**Lands in**: `settings.flow.json` → `agentTeams` + env

**Forcing question**: do we want `/flow:review` to spawn an adversarial team where reviewers challenge each other's findings? Higher signal, higher cost.

**What `true` does**: when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is also set, `/flow:review` runs the paired-reviewer protocol: the 5 agent facets dispatch as skeptic + verifier pairs, with holdout validation in both lenses (12 invocations, plus up to 10 challenge prompts, instead of 5 agents + 1 skill), and the variants challenge each other's findings (AGREE/DISAGREE/REFINE). Agreement decides each finding's confidence. The agents run on `agentTeamModel` (default `sonnet`). `/flow:pr` and `/flow:address` are unaffected. Opt-in only.

---

## Decision 4 — Branch naming patterns

**Default**: `feature/issue-{N}-{desc}`, `fix/issue-{N}-{desc}`, `docs/issue-{N}-{desc}`

**Options**: keep defaults | adjust prefixes (e.g. `feat/`, `bugfix/`) | add new categories

**Lands in**: `settings.flow.json` → `conventions.branchPatterns`

---

## Decision 5 — Commit type vocabulary

**Default** (12 types from `plugins/flow/settings.json` line 19):

`feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert, improve`

**Options**: keep all 12 | drop ones we won't use | add team-specific types

**Lands in**: `settings.flow.json` → `conventions.commitTypes`

---

## Decision 6 — Journal sensitivity default

**Default**: `public` (entries go into PR bodies)

**Options**: `public` (transparent default) | `internal` (redacted by default, must opt-in to public)

**Lands in**: `CONVENTIONS-DECIDED.md` as a writing policy. Flow has no setting for this: each journal entry declares `Sensitivity:`, and an entry without the line is `public`.

**Forcing question**: do we want PR bodies to expose decision rationale by default, or hide it by default?

---

## Decision 7 — Tier overrides

**Defaults**: push=journal, prCreate=journal, issueAssign=journal, issueCreate=journal, merge=confirm, release=confirm

**Options**: keep defaults | promote any to `confirm` (more friction, more safety)

**Reminder**: tiers can be promoted, never demoted — that is the documented policy. No flow command or hook reads the `tiers` keys today: `/flow:merge` and `/flow:release` always ask, whatever the file says.

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
  • gh-workflow plugin also installed (enable only one at a time; see HANDBOOK Appendix A)

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

> /flow:status --full

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

### FlowGoal State
| Goal      | Lifecycle | ACs          |
|-----------|-----------|--------------|
| issue-142 | active    | 3/4 pass, 1 pending |

### Recent Runs
| Run ID                             | Verdict | Activities |
|------------------------------------|---------|------------|
| 2026-09-27T101500Z-start-issue-142 | -       | 5          |

### Active Triggers
No triggers registered.

### Findings Ledger
P1: 0    P2: 1 (in fix-forward)    P3: 1 (ESCALATED)

### Suggested Next Action
PR #43 is approved with passing checks → `/flow:merge 43`
```

Read-only. Safe to run anywhere, anytime. Plain `/flow:status` prints a five-line dashboard instead: active work, goal, workflow, evidence (the Findings Ledger line), and the next safe action. The "Suggested Next Action" line picks the most useful next command from the table in `commands/status.md`.

---

## Common gotchas

1. **`gh` CLI not authenticated** — preflight fails. Fix: `gh auth login`.
2. **Dirty worktree on `/flow:start`** — preflight fails. Fix: stash or commit before starting.
3. **`CLAUDE.md` integration depends on file existence** — `/flow:setup` Phase 5 asks via AskUserQuestion whether to add the flow section. If you say yes, it appends `templates/CLAUDE-flow.md` to your existing `CLAUDE.md`. If `CLAUDE.md` doesn't exist yet, create it first (or copy the template manually) before answering yes.
4. **`block-force-push` blocks a legitimate rebase push** — use `--force-with-lease`. Allowed (`three-tier-safety.md`, Tier 3 table).
5. **Auto-log seems to duplicate commits** — `log-commits.sh` skips commits whose subject starts with `chore(decisions):` and commits that touched only the journal, and it writes to the local trail in `.decisions/auto-log/`, not the tracked journal. If you see duplication, your plugin is out of date — `claude plugins update flow`.
6. **`gh pr merge` blocked** — a check is still queued, running or failed, or the command is not in the one shape the hook reads (`gh pr merge <N> --repo owner/name --squash`). Wait for checks, or use `/flow:merge`.

---

## Where to look when broken

| Symptom | First place to look |
|---------|--------------------|
| Plan got blocked | `.decisions/issue-N.md` — search "Stranger Test" or "Spec Validation" |
| Verdict FAIL but code works | Evidence bundle — missing completeness subsection? Expected value copied from the implementation? |
| Hooks aren't firing | `~/.claude/logs/` for hook stderr |
| `/flow:learn` empty | `learning.enabled`? `learning.sources`? `journal.dir` populated? |
| Agent teams not spawning | Both `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var; `/flow:review` only |
| Tier 3 prompt missing | `/flow:merge` and `/flow:release` always ask — the merge or release did not go through the command |
| Task won't complete | Files changed since the last passing test/lint run — re-run it |

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

Both plugins can be installed from the marketplace. `/flow:setup` warns when it finds gh-workflow: enable only one at a time, to avoid hook conflicts.

Verb mapping:

| gh-workflow | flow | Notes |
|-------------|------|-------|
| `/gh-start` | `/flow:start` | flow has Phase 0 preflight + Spec Validation Gate |
| `/gh-commit` | `/flow:commit` | same vocabulary, different autonomy |
| `/gh-pr` | `/flow:pr` | flow runs parallel agent review |
| `/gh-review` | `/flow:review` | flow ships parallel multi-facet review (adversarial teams opt-in) |
| `/gh-merge` | `/flow:merge` | both Tier 3 |

If you preferred gh-workflow's interactive style: opt out of strict defaults (HANDBOOK Appendix A). Don't fight the plugin — configure it.

---

## Glossary

- **P1 / P2 / P3** — finding priority. P1 blocks merge; P2 and P3 are fixed in the PR too.
- **ESCALATED** — a finding that could not be fixed in the PR for an allowed reason (a product decision only the user can make, a file or dependency flow does not own), escalated with the six fields into `FLOW_RESOLUTION_CYCLE`. Auditable; not silently dropped; blocks merge.
- **FLOW_RESOLUTION_CYCLE** — marker in PR comments capturing per-cycle resolved, escalated and disputed findings. The merge gate's substrate.
- **Holdout** — a hidden test scenario the executing agent never sees. Used by `holdout-validation` to verify self-review claims.
- **Stranger Test** — the gate at end of PLAN. Plan must be executable by someone with zero prior context.
- **Six-field escalation** — Situation / What I tried / Options / Recommendation / Blocking? / Risk. Mandatory shape for every escalation.
- **Eval-as-spec** — acceptance criteria are eval sources. Each AC produces a runnable verification command at plan time.

---

## Q&A — seed questions

We expect at least one of these. If not, we'll seed it.

- "Can we keep using gh-workflow for legacy repos?" — yes; enable one plugin per repo. See HANDBOOK Appendix A.
- "What if `/flow:setup` doesn't detect our build?" — file an issue with the project's `package.json` / `pyproject.toml`. Setup is heuristic.
- "What if I disagree with a P3?" — push back in `/flow:address` with evidence (a `file:line`, a named test, or a CLAUDE.md rule). It is recorded as DISPUTED and still blocks merge until resolved. Disagreeing with a finding is not a reason to escalate.
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
