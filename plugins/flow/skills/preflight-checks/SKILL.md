---
name: preflight-checks
description: "Reference document describing six pre-flight checks (clean git state, not detached HEAD, gh auth, issue exists and OPEN, remote reachable, duplicate-branch warning) as pure bash exit codes with no LLM calls. Reference only (policy document; consumed by `/flow:start` Phase 0)."
allowed-tools: Read
context: fork
agent: general-purpose
disable-model-invocation: true
---

# Pre-flight Checks

Reference document for the pre-flight policy. The executable bash lives in `plugins/flow/commands/start.md` (Phase 0) — that is the single source of truth that runs at workflow start. This skill describes **what each check enforces and why**, so the policy can be reviewed, audited, and extended without untangling shell logic.

## Iron Law

**NO LLM CALLS IN PRE-FLIGHT.** Every check is a bash command with a pass/fail exit code. If pre-flight fails, the workflow stops before spending any tokens on planning.

## What Pre-flight Protects

Pre-flight is the cheapest possible filter. It runs before EXPLORE, before any agent dispatch, and before any token-spending reasoning. The goal is to fail fast on conditions that would invalidate everything downstream — saving both wall-clock time and LLM cost.

If pre-flight is honest about what it can and cannot prove, downstream phases can trust their preconditions and stop re-checking them.

## The Six Checks (and why each exists)

| # | Check | Failure mode it prevents |
|---|-------|--------------------------|
| 1 | Clean git state (no uncommitted changes) | Starting a feature branch on top of unrelated dirty state, then accidentally including those changes in the PR. |
| 2 | Not on detached HEAD | Creating commits that have no branch reference and silently disappear when the workflow checks out something else. |
| 3 | `gh` CLI authenticated | Spending tokens on planning, then failing at the first `gh issue view` call because auth was never established. |
| 4 | Issue exists and is OPEN | Working an issue that was already closed, deleted, or mistyped — produces a PR with nothing to close. |
| 5 | Remote `origin` reachable | Reaching the push step after hours of work and discovering the network is down or the remote is misconfigured. |
| 6 | Already on a feature branch for this issue (warning only) | Accidentally re-starting an issue that is already in progress on the current branch — recoverable, so warning not error. |

Checks 1–5 are **errors**: any one fails, the workflow halts. Check 6 is a **warning**: noted in output, workflow proceeds.

## Behavior Contract

- **ERRORS > 0**: halt the workflow. Do not proceed to EXPLORE. Do not spend tokens on planning.
- **WARNINGS only**: surface in output, proceed normally.
- **No LLM calls, no Agent dispatches, no Skill invocations** during pre-flight. Pre-flight is pure bash.
- **Total execution**: one Bash call, sub-second. If pre-flight is slow, it has scope creep.

## Where the Bash Lives

The runnable implementation is the bash block in `plugins/flow/commands/start.md` under "Phase 0: PRE-FLIGHT". `$ARGUMENTS` is substituted with the issue number from command arguments. That is the copy that actually runs.

This skill intentionally does **not** duplicate the bash. Two copies of the same checks drift silently — when a check is added to one and not the other, the gap is invisible until pre-flight either misses a real failure or fires on a condition that was already removed. Keeping the policy here and the implementation in the command means there is one place to read the shell, and one place to read the rationale.

## Extending Pre-flight

When adding a new check, the policy contract is:

1. **It must be representable as a single bash exit code** — no LLM judgment, no multi-step reasoning.
2. **It must be cheap** — sub-second, no network calls beyond `gh` and `git` that pre-flight already performs.
3. **It must protect against a concrete failure mode** — add a row to the table above explaining what goes wrong without it.
4. **It must classify cleanly as ERROR or WARNING** — errors halt, warnings surface. Anything in between belongs in EXPLORE, not pre-flight.

If a proposed check cannot meet all four, it does not belong in pre-flight. Push it to a later phase or to a domain skill.
