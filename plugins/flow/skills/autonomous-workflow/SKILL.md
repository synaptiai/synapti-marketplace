---
name: autonomous-workflow
description: "[flow] Autonomous development workflow principles. Defines Explore>Plan>Code>Verify loop, task-driven progress tracking with TaskCreate/TaskUpdate/TaskList, three-tier action classification, decision journaling, parallel execution, and bounded verification loops."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, TaskCreate, TaskList, TaskUpdate, TaskGet, AskUserQuestion
---

# Autonomous Workflow

Foundation skill governing how Claude executes development workflows autonomously.

## Iron Law

**NO SKIPPING PHASES. Explore before Plan, Plan before Code, Code before Verify. Every phase produces an artifact.**

Jumping to code without exploration is the #1 cause of rework. Jumping to "done" without verification is the #1 cause of bugs reaching review.

## Explore > Plan > Code > Verify

Every multi-step workflow follows this loop:

1. **EXPLORE**: Gather context. Use Agent(Explore) subagents for unfamiliar code. Parallel Bash for independent queries (git status, issue details, task list). Read referenced files. When LSP is available: use `goToDefinition` to trace code paths from issue keywords to implementation, and `findReferences` to assess the impact of planned changes — this enhances text-based grep searches with semantic understanding.
2. **PLAN**: Decompose work. TaskCreate for each deliverable. Set dependencies with addBlockedBy. Display the plan for visibility.
3. **CODE**: Execute tasks. TaskUpdate(in_progress) before starting. Implement. Commit incrementally (Tier 1). TaskUpdate(completed) after verification. When LSP is available: use `hover` to understand types and signatures of existing code before modifying it.
4. **VERIFY**: Prove it works. Four mandatory verification layers:
   a. **Static**: Run quality commands (lint, test, typecheck) in parallel. When LSP diagnostics are available (`lsp.diagnosticsAsQuality`), collect them as an additional quality signal — errors are P1, warnings are P2. LSP diagnostics complement, never replace, CLI-based checks.
   b. **Runtime**: Build the project, start it, verify at runtime. If anything fails, enter the debug-fix-retest loop (bounded by `closedLoop.maxDebugIterations`).
   c. **Review**: Self-review with fix-forward — fix P1/P2 findings immediately, don't just report them.
   d. **Verdict**: Independent judgment — dispatch verdict-judge agent (when `verdict.enabled`) with acceptance criteria + evidence bundle. The judge has no access to code-writing rationale, diff, or decision journal. It evaluates outcomes, not process. Each criterion receives PASS/FAIL/NEEDS-HUMAN-REVIEW. FAIL verdicts trigger fix loops; NEEDS-HUMAN-REVIEW escalates to user.

## Task-Driven Progress

Use Task tools as first-class workflow primitives:

| Tool | When |
|------|------|
| TaskCreate | Start of PLAN phase — one task per deliverable |
| TaskUpdate(in_progress) | Before starting work on a task |
| TaskUpdate(completed) | After task passes verification |
| TaskList | At checkpoints to confirm progress |
| TaskGet | Before working on a task to get full context |

Tasks have clear subjects (imperative form) and descriptions with acceptance criteria.

## Three-Tier Action Classification

| Tier | Actions | Behavior |
|------|---------|----------|
| **Tier 1** (Autonomous) | Commits, branch creation, file edits, staging | Execute without asking. Local and reversible. |
| **Tier 2** (Journal) | Push, PR creation, issue assignment | Execute and log to decision journal. Team-visible but recoverable. |
| **Tier 3** (Confirm) | Merge, release, force operations | Always require human confirmation. Non-negotiable. |

Tier configuration is in `settings.json` under `tiers`. Actions can be promoted (journal→confirm) but never demoted (confirm→journal).

## AskUserQuestion Tool Enforcement

When a command or skill says "use the AskUserQuestion tool", you MUST invoke the AskUserQuestion tool — do not substitute plain text output. The tool provides structured selectable options that plain text cannot replicate. Supply contextual options appropriate to the situation.

## Decision Journal Protocol

- **Init**: Create `{journal-dir}/issue-{N}.md` at branch creation
- **Log**: PostToolUse hooks auto-log file changes and commits
- **Structured entries**: Skills add timestamped entries with category, decision, rationale, risk
- **Summarize**: Condense journal for PR body (public entries only, internal redacted)

Journal dir defaults to `.decisions/`, configurable in settings.

## Parallel Execution

Dispatch independent operations in a single message:

- Multiple Bash calls for independent git queries
- Multiple Agent calls for independent review facets
- Never parallelize operations that depend on each other's output

## Bounded Verification

Quality check loops have max iterations from `settings.json`:

1. Run quality commands
2. If failures, fix and re-run
3. After `qualityCheckMaxIterations` (default 3), escalate to user
4. Never loop indefinitely

## Stop Conditions

| Trigger | Action |
|---------|--------|
| 3+ verification failures on the same issue | Stop fixing forward. Return to EXPLORE — the problem is architectural. |
| Plan has >10 tasks for a single issue | Decompose the issue first. One PR should not span 10 tasks. |
| EXPLORE phase yields contradictory signals | Stop. Ask the user for clarification before planning. |
| >5 files modified without staging or committing | Stop. What you have should be committable. If not, the tasks are too large. |

## Sensitivity Classification

- **public**: Safe for PR bodies, comments, logs
- **internal**: Security rationale, credential handling, vulnerability details
- Never include internal details in public-facing outputs

## Closed-Loop Mandate

The debug-fix-retest loop is mandatory — do NOT report failures and move on, DO fix them yourself.

**Minimum verification by project type:**
- **Web apps**: Build + start dev server + smoke test endpoints
- **CLI tools**: Build + run with --help + run with sample input
- **Libraries**: Build + run public API against sample data
- **Static sites**: Build + serve locally + verify pages load
- **Config/markdown-only**: Static checks only (explicit justification required)

The loop is bounded by `closedLoop.maxDebugIterations` (default 5). After max iterations, escalate to user — never silently skip.

## Graceful Degradation

| Missing | Fallback |
|---------|----------|
| No agent teams | Single-session sequential |
| No quality commands | Attempt to discover them first (`Skill(capability-discovery)`), then proceed with runtime verification only |
| No LSP server | Fall back to grep-based references and CLI-only diagnostics. No error — LSP is additive. |
| No gh CLI | Warn, continue with git-only |
| No decision journal | Proceed without logging, note in PR |

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "I already know what to do, skip EXPLORE" | Then exploring should take 10 seconds. Do it. |
| "The plan is obvious, no need to TaskCreate" | Untracked work is invisible work. Create the tasks. |
| "Just one more fix, then I'll verify" | Verify now. The loop exists because one-more-fix never ends. |
| "This is too simple for the full loop" | Simple tasks, same phases. Just faster. |
| "Runtime verification isn't possible" | It is, for any project that does something. Build it, run it, check it. |
| "Tests pass, so it works" | Tests verify what's tested. Runtime verifies what's real. |
| "I can't start the server" | Fix why. Server startup failure IS a bug. |
| "Self-review is enough" | Self-review checks code quality. The verdict checks requirements. Both are needed. |
| "I wrote the tests, so the criteria are met" | Tests prove the code does what you thought was wanted. The verdict proves it does what was actually wanted. |
