# Flow Cheatsheet

One page. Pin to the wall. Detail in `HANDBOOK.md`.

---

## Daily five

| Command | Use it for |
|---------|-----------|
| `/flow:start <issue>` | Begin work — preflight, EXPLORE, PLAN with verification commands, branch + tasks |
| `/flow:commit` | Atomic conventional commits with change classification |
| `/flow:pr` | Push, parallel agent review, PR with comprehension report |
| `/flow:review <pr>` | 6-facet parallel review (or adversarial team if `agentTeams: true`) |
| `/flow:address <pr>` | Categorize comments, surgical fixes, re-request review |

## Tier 3 — always confirms

| Command | Notes |
|---------|-------|
| `/flow:merge <pr>` | Prerequisite check + AskUserQuestion. Hooks block force-push regardless. |
| `/flow:release <type>` | Changelog from merged PRs + AskUserQuestion. |

## Read-only / learning

| Command | When |
|---------|------|
| `/flow:status` | Anywhere, anytime — view assigned issues, open PRs, journal health |
| `/flow:explain` | "Why did we decide X?" — loads journal + diff |
| `/flow:learn` | Quarterly — turn journal patterns into skill proposals |

## Shape work first

| Command | Before… |
|---------|---------|
| `/flow:issue` | …filing an issue (AC drafting + Spec Validation Gate) |
| `/flow:brainstorm` | …choosing an approach |
| `/flow:debug` | …chasing a bug you can't reproduce |
| `/flow:design` | …a feature where architecture matters |

## Bootstrap

| Command | When |
|---------|------|
| `/flow:setup` | Once per repo |
| `/flow:resolve` | Merge conflicts |
| `/flow:flow` | Universal dispatcher (`/flow <verb> <target>`) |

---

## Three-tier safety

| Tier | Examples | Behavior |
|------|----------|----------|
| **1 — Autonomous** | edits, commits, branches, tests, agent dispatch | Execute without asking |
| **2 — Journal** | push, PR create, issue assign/create, PR comment | Execute + log to `.decisions/` |
| **3 — Confirm** | merge, release, force-push, force branch-delete | Always ask. Non-negotiable. |

Promote tiers (autonomous → journal → confirm). Never demote.

## Hook layer (8 wired scripts)

```
PreToolUse  Bash    block-force-push   block-destructive   block-secrets
PostToolUse Edit    log-file-changes
PostToolUse Bash    log-commits        (idempotent — skips lines already auto-logged)
TaskCompleted       verify-task-completion
TeammateIdle        nudge-idle-teammate           (experimental)
SessionEnd          session-end-learn             (experimental)
```

`gate-merge` / `gate-release` are NOT hook scripts — confirmation is in the command files via `AskUserQuestion`.

---

## EPCV — the loop

```
EXPLORE  →  PLAN  →  CODE  →  VERIFY
context     tasks +    Per-Task    a. STATIC    (lint+test+typecheck+LSP)
parallel    verif      Gate +      b. RUNTIME   (build, run, smoke test)
reads       cmd per    TDD +       c. REVIEW    (self-review, fix-forward)
+LSP        AC +       commits +   d. VERDICT   (verdict-judge — independent)
trace       Stranger   journal
            Test
```

**Iron law**: NO SKIPPING PHASES. (`autonomous-workflow/SKILL.md` line 13)

**Fix-forward** (REVIEW layer): the agent fixes P1/P2 findings inline during self-review rather than reporting them as work-for-the-reviewer. Bounded by `fixForwardMaxIterations` to prevent loops.

---

## Verdict-judge — what it sees vs not

| Sees | Does NOT see |
|------|--------------|
| Acceptance criteria | The diff |
| Evidence bundle | Decision journal |
| Holdout-validation output | Planning notes / approach rationale |
| | Self-review findings |
| | Memory from prior sessions |

If the evidence doesn't prove the AC → FAIL. Even if the code is "obviously correct."

## Per-criterion evidence — required subsections

Every AC's evidence MUST include:
1. **What was NOT tested** (never blank — write "none" if truly nothing)
2. **Known limitations of this evidence**
3. **Negative/adversarial cases covered**

Missing any → criterion FAILs automatically.

---

## Six-field escalation

Used for any human decision. Never "what should I do?"

`Situation / What I tried / Options (label one Recommended) / My recommendation / Time sensitivity / Risk if wrong`

## P1 / P2 / P3

| Priority | Meaning | Action |
|----------|---------|--------|
| **P1** | Must fix — blocks merge, security, data loss, broken | Fix before proceeding |
| **P2** | Should fix — logic bug, edge case, test gap | Fix in this PR |
| **P3** | Consider — style, optimization, future improvement | Fix in-PR or six-field escalate |

P3 is **not** a free pass.

---

## Settings cascade (lowest → highest priority)

```
plugins/flow/settings.json     ←  plugin defaults
~/.claude/settings.flow.json   ←  user global
.claude/settings.flow.json     ←  project shared (committed)
.claude/settings.flow.local.json ← project local (gitignored)
```

Strict defaults and why they're strict:
- `testing.tddMode = enforce` — RED-GREEN-REFACTOR is observed before a task can complete (catches test-first violations at write-time). Flip to `suggest` if your team prefers test-after.
- `verdict.requireAllPass = true` — every AC must PASS or the verdict is FAIL. Flip to `false` if rolling out gradually and willing to accept soft passes on `NEEDS-HUMAN-REVIEW`.

Opt-out template: `plugins/flow/README.md` lines 41–54.

---

## When something breaks

| Symptom | First place |
|---------|------------|
| Plan blocked | `.decisions/issue-N.md` — search "Stranger Test" |
| Verdict FAIL feels wrong | Check evidence-bundle completeness subsections |
| Hooks not firing | `~/.claude/logs/` |
| Force push blocked | Use `--force-with-lease` (allowed + journaled) |
| Auto-log loop | Restore `<!-- auto-log: ... -->` markers; `claude plugins update flow` |

When in doubt: `/flow:status` first.
