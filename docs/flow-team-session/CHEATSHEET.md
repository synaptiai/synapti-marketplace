# Flow Cheatsheet

One page. Pin to the wall. Detail in `HANDBOOK.md`.

---

## Daily five

| Command | Use it for |
|---------|-----------|
| `/flow:start <issue>` | Begin work — preflight, EXPLORE, PLAN with verification commands, branch + tasks |
| `/flow:commit` | Atomic conventional commits with change classification |
| `/flow:pr` | Parallel agent review and fixes, then push and PR with comprehension report |
| `/flow:review <pr>` | Five review agents + holdout validation in parallel (or adversarial team if `agentTeams: true` and the env var is set) |
| `/flow:address <pr>` | Categorize comments, surgical fixes, re-request review |

## Tier 3 — always confirms

| Command | Notes |
|---------|-------|
| `/flow:merge <pr>` | Prerequisite check (finding ledger, FlowGoal achieved) + AskUserQuestion; `tier-gate` asks again when the merge runs. A hook refuses any merge whose checks are unfinished or red. |
| `/flow:release <type>` | Two runs. Run 1: release PR with the version bump and changelog from merged PRs. Run 2, after it is merged: AskUserQuestion, then tag + GitHub release (`tier-gate` asks again). |

## Read-only / learning

| Command | When |
|---------|------|
| `/flow:status` | Anywhere, anytime — five-line dashboard; `--full` for issues, PRs, goals, runs, findings |
| `/flow:explain` | "Why did we decide X?" — loads journal + diff |
| `/flow:learn` | Quarterly — turn journal and transcript patterns into skill and review-exception proposals |

## Shape work first

| Command | Before… |
|---------|---------|
| `/flow:issue` | …filing an issue (observable, solution-agnostic AC drafting + duplicate detection) |
| `/flow:brainstorm` | …choosing an approach |
| `/flow:debug` | …chasing a bug you can't reproduce |
| `/flow:design` | …a feature where architecture matters |

## Bootstrap

| Command | When |
|---------|------|
| `/flow:setup` | Once per repo (also offers GitHub rulesets for the default branch and tags) |
| `/flow:resolve` | Merge conflicts |
| `/flow:flow` | Universal dispatcher (`/flow <verb> <target>`) |

## Runtime / admin (rarely typed)

`/flow:goal` · `/flow:workflow` · `/flow:trigger` · `/flow:run` · `/flow:resume` · `/flow:watch` — inspect goals, workflows, triggers and runs. `/flow:start` creates the goal for you. `/flow:watch` modes: `pr <N>`, `ci`, `issue <N>`, `branch` (the branch watch merges the default branch in, fixes failures, commits and pushes).

---

## Three-tier safety

| Tier | Examples | Behavior |
|------|----------|----------|
| **1 — Autonomous** | edits, commits, branches, tests, agent dispatch | Execute without asking |
| **2 — Journal** | push, PR create, issue assign/create, PR comment, `--force-with-lease` | Execute + one breadcrumb in the local, gitignored `.decisions/auto-log/` trail |
| **3 — Confirm** | merge, release, tag push or tag delete | Always ask. Non-negotiable. |

Force-push and force-deleting an unmerged branch are not asked about: hooks block them (exit 2).

The `tier-gate` hook applies `tiers.*` to every Bash command. `push`, `prCreate`, `issueAssign`, `issueCreate`: `autonomous`, `journal` or `confirm`. `merge` and `release`: always `confirm` (a lower value is ignored with a warning).

## Hook layer (17 wired scripts)

```
PreToolUse   Bash   block-force-push   block-destructive   block-unchecked-merge
                    block-secrets      ask-issue-create    (asks during an active goal)
                    tier-gate          (applies tiers.*: confirm asks, journal logs)
PostToolUse  Edit   log-file-changes   (local auto-log trail + quality ledger)
PostToolUse  Bash   log-commits        (bounded by two commit guards, not a line check)
                    record-quality-run (also on PostToolUseFailure)
                    s1-screen-text     (off unless guard.planted-instructions is set)
SessionStart        tier-session-start (puts flow's git/gh wrappers on PATH)
TaskCompleted       verify-task-completion   (blocks while edits postdate the last passing check)
TeammateIdle        nudge-idle-teammate      (agent teams)
SessionEnd          session-end-learn   session-end-state
Stop                flow-goal-stop (warn by default)   reply-style-check (opt-in)
```

`gate-merge` / `gate-release` are NOT hook scripts — `/flow:merge` and `/flow:release` confirm via `AskUserQuestion`, and `tier-gate` asks again when the merge, tag push or release command runs (two prompts; the only prompt for one typed outside flow). `block-unchecked-merge` refuses a merge typed into Bash while its checks are queued, running or failed.

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

**Iron law**: "Explore, then Plan, then Code, then Verify, and every phase produces an artifact: a skipped phase comes back as rework." (`autonomous-workflow/SKILL.md` line 11)

**Fix-forward** (REVIEW layer): the agent fixes findings inline during self-review rather than reporting them as work-for-the-reviewer. Bounded by `fixForwardMaxIterations` to prevent loops.

---

## Verdict-judge — what it sees vs not

| Sees | Does NOT see |
|------|--------------|
| Acceptance criteria | The diff |
| Evidence bundle | Decision journal |
| Holdout-validation output | Planning notes / approach rationale |
| | Self-review findings |
| | Memory from prior sessions |
| | Test source files, screenshots (it has no file tools) |

If the evidence doesn't prove the AC → FAIL. Even if the code is "obviously correct."

## Per-criterion evidence — required subsections

Every AC's evidence MUST include `Does NOT promise`, `Visual analysis` (`none — …` for non-UI criteria), and:
1. **What was NOT tested** (never blank — write "none" if truly nothing)
2. **Known limitations of this evidence**
3. **Negative/adversarial cases covered**
4. **Test inputs and expected values** (with where each expected value came from — never the implementation's own output)
5. **Risk map coverage**

Missing any → criterion FAILs automatically.

---

## Six-field escalation

Used for a decision only a human can make, delivered via `AskUserQuestion`. Never "what should I do?" Never for what to do with a review finding — fix the finding.

`Situation / What I tried / Options / Recommendation / Blocking? (yes · soft · no) / Risk`

## P1 / P2 / P3

| Priority | Meaning | Action |
|----------|---------|--------|
| **P1** | Must fix — blocks merge, security, data loss, broken | Fix before proceeding |
| **P2** | Should fix — logic bug, edge case, test gap | Fix in this PR |
| **P3** | Consider — style, optimization | Fix in this PR |

P3 is **not** a free pass. Only `minimalScope: true` allows a follow-up issue, and only for a cosmetic P3 in a file the PR did not touch. A LOW-confidence finding goes to "Needs investigation" and does not decide the review.

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
- `verdict.requireAllPass = true` — every AC must PASS or the verdict is FAIL. Flip to `false` if rolling out gradually; a person can then approve a `NEEDS-HUMAN-REVIEW` criterion.

Opt-out template: `plugins/flow/README.md`, section "Opting Out".

---

## When something breaks

| Symptom | First place |
|---------|------------|
| Plan blocked | `.decisions/issue-N.md` — search "Stranger Test" |
| Verdict FAIL feels wrong | Check evidence-bundle completeness subsections |
| Hooks not firing | `~/.claude/logs/` |
| Force push blocked | Use `--force-with-lease` (allowed) |
| `gh pr merge` blocked | Checks still running or red — `gh pr checks <N> --watch`, then `/flow:merge` |
| Task won't complete | Files changed since the last passing check — re-run tests/lint |
| Auto-log loop | Update the plugin (`claude plugins update flow`). The breadcrumbs live in a local, gitignored trail (`.decisions/auto-log/`), so a journal commit cannot trigger one. |

When in doubt: `/flow:status` first.
