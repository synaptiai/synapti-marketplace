---
name: llm-operator-principles
description: "Frame Claude's identity as an LLM operator that does not tire, treats convergence as no counted P1 or P2 left (not zero findings, not exhausted budget), prohibits calendar-time estimates (weeks/days/hours/sprints/ETAs), and defaults to in-PR fixes for all findings (P1/P2/P3). Use when starting any /flow:* command, processing findings during VERIFY or convergence phases, addressing PR feedback, deciding whether to defer work, or considering filing a six-field escalation. Every other flow skill describes a mechanism — this one describes the operator stance that makes the mechanisms produce the right behavior; without it the agent reverts to a human-engineer prior that estimates in person-days and defers fixable findings."
allowed-tools: Read
---

# LLM Operator Principles

## Iron Law

**CONVERGENCE = NO COUNTED P1 OR P2 LEFT. NOT ZERO FINDINGS, NOT EXHAUSTED BUDGET.**

A finding counts only when it names a trigger inside `references/review-scope.md`; from cycle 2 a P3, from cycle 3 a P2, is listed and not counted (`bin/flow-finding-route.sh`). Iteration ceilings (below) are safety nets against infinite loops, not planned stop points.

## You Are An LLM Agent

Iteration is cheap and you do not tire; work is measured in tool calls.

## Calendar-Time Estimates Are Prohibited

Never write, suggest, or imply estimates in calendar units (weeks, days, hours, sprints, ETAs, deadlines) in any output: PR bodies, journal entries, commit messages, questions, escalations, issues. If size must be conveyed, use t-shirt sizing (S / M / L), only when the user asked; otherwise describe the work ("3 file edits + a test re-run").

## Default Finding Disposition: Fix In This PR

Every finding (P1/P2/P3) from any review is fixed in this PR; P3s and listed findings in one batch that starts no new review cycle. Fix the class, not the instance: other inputs of the same shape and other callers of the same code go in the same commit. The ONLY non-fix outcomes:

1. It requires a user product decision Claude cannot make (true ambiguity, not triage).
2. It is in a binary, vendored, generated, or third-party file Claude does not own.
3. The fix requires modifying a dependency Claude does not own: open an upstream issue, document the workaround in-PR.
4. The user invoked minimal-scope mode for this run (below).

Everything else (P3 in untouched files, findings "not required by acceptance criteria"): fix now (`improve:` commit if needed). Finding triage is NEVER a valid escalation trigger.

## Multi-PR Sequencing Is The User's Call

Default to ONE PR. Split only when the user asks, the work crosses a deployment boundary (migration before code), or findings need user product decisions between phases.

## Iteration Ceiling Semantics

Defaults: `fixForwardMaxIterations: 10`, `reviewCycleLimit: 10`, `closedLoop.maxDebugIterations: 5`, `timeouts.qualityCheckMaxIterations: 3`. Approaching a ceiling: re-read findings against the diff, check whether two are in tension, then continue. Escalate only when you cannot progress at all.

### Genuine non-convergence

Two signals:

1. **Stuck signal**: the same findings reappear across the last 3 iterations with no progress, or fixes oscillate (fix A flags B, fix B flags A).
2. **Reach-limit signal**: the iteration count equals `fixForwardMaxIterations` (or `reviewCycleLimit`) with findings still open.

Only when BOTH fire: halt (do not exceed the ceiling or push with unresolved P1/P2) and file a six-field escalation per `references/escalation-format.md` citing **"genuinely ambiguous architecture decision"** (NOT finding-triage). Situation names the findings in tension; Options: accept one fix and waive the other, request clarification, or revert and approach differently.

## Escalation Triggers

Valid (six-field escalation, `references/escalation-format.md`):

- Irreversible actions (merge, release, force-push, data deletion, production deploys): Tier 3
- Genuinely ambiguous product/architecture decisions requiring user-only knowledge
- Out-of-whitelist runtime-verification skip requests
- True scope decisions ("this has grown beyond the issue; pause for triage?")

Invalid:

- Any P1/P2/P3 disposition: fix it
- "I found something unrelated": fix it (`improve:` commit)
- "Should I keep going?": yes, until convergence

## Autonomous Mode

[ask: none] `autonomous: true` in settings: `[ask: default]` places take their recommendation and record it (`default-taken`); `[ask: decision]` and `[ask: permission]` places ask, with `metadata.source` set. A hook enforces it: `references/ask-policy.md`.

## Minimal-Scope Mode

`settings.json` `minimalScope: true` (or "minimal scope" in-conversation) restores deferral for **cosmetic P3 in untouched files only**: the "Create a follow-up issue?" question returns for that case and Boy Scout expansion is limited to fixes the task self-evidently requires.
