---
name: specification-capture
description: "Capture the three specification elements (non-goals, failure modes, interface contracts) for an issue and persist them to the decision journal under a ## Specification heading. Use when starting work on an issue (Phase 1 of /flow:start), entering a design discussion (/flow:design), or starting a brainstorm (/flow:brainstorm). This skill MUST be consulted because acceptance criteria alone do not describe the full specification — without explicit non-goals, failure modes, and interface contracts, downstream phases (PLAN, CODE, VERIFY) cannot fence the implementation or know what behavior to test."
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
agent: general-purpose
---

# Specification Capture

You capture three specification elements that complement an issue's acceptance criteria, and you persist them to the decision journal so every downstream phase (PLAN, CODE, VERIFY) and every related command (`/flow:design`, `/flow:brainstorm`) can read from the same source of truth.

This skill owns the capture lifecycle and the journal contract — every consumer (`/flow:start`, `/flow:design`, `/flow:brainstorm`) invokes the skill instead of re-implementing it. Two failure modes the skill prevents:

1. **No persistence-side check** — without a single owner, a command can claim "captured all three" while writing only a partial set to the journal, and the gap silently flows into PLAN.
2. **No shared source of truth** — `commands/design.md` and `commands/brainstorm.md` would otherwise address overlapping elements (non-goals especially) without reading from or writing to the same `.decisions/` artifact, so a user running `/flow:design` first and `/flow:start` second would get duplicate or contradictory specifications.

## Iron Law

**EVERY ISSUE GETS THE THREE ELEMENTS BEFORE PLAN. Acceptance criteria scope WHAT the user-visible outcome is. The three elements scope what the implementation IS NOT, how it behaves under failure, and what schemas it must honor. PLAN cannot fence the implementation without all three.**

A captured specification is the contract between the issue and the per-task atomic units the `implementation-planner` agent produces. Without it, tasks lack failure-mode coverage and interface contracts — the `Stranger Test` (end-of-PLAN gate in `commands/start.md`) will fail.

## Inputs

The invoking command MUST pass these in the prompt:

1. **Issue context** — title, body, labels, comments. The skill parses these for any specification language already in the issue.
2. **Journal path** — typically `.decisions/issue-{N}.md` (where `{N}` is the issue number). The skill reads this path first to detect prior captures.
3. **Invocation reason** — one of `start`, `design`, `brainstorm`. Used to scope which elements the skill focuses on (see "Per-invoker scope" below).

If any required input is missing, halt with `SPEC_CAPTURE_BLOCK: missing input <name>`. Partial inputs are NOT acceptable for this skill — without them, the capture cannot be authored or verified.

## Process

### Step 1: Read the journal first

Before parsing the issue or prompting the user, check the journal for an existing `## Specification` heading:

```bash
JOURNAL="$1"  # path passed by invoker
if [ -f "$JOURNAL" ]; then
  awk '/^## Specification$/,/^## (Stranger Test|Decision|Implementation|Verification)$/{print}' "$JOURNAL"
fi
```

If the section exists, parse it for the three elements: `### Non-goals`, `### Failure modes`, `### Interface contracts`. Record which are present and which are missing.

If the section exists AND all three elements are present AND the issue body has not been updated since the journal was last written (use `git log -1 --format=%cd .decisions/issue-{N}.md` for journal mtime, compare against issue's `updatedAt` field from `gh issue view`), return the existing specification verbatim. No re-prompting. The journal IS the source of truth.

If the journal section is partial (some elements missing) or stale (issue updated after journal write), proceed to Step 2 to fill the gaps.

### Step 2: Extract from the issue body

For each missing element, scan the issue body and comments for prior statements:

| Element | Issue-body cues |
|---|---|
| Non-goals | Sections like `## Non-goals`, `## Out of scope`, `Does NOT`, `Will not include`, bullet lists of "won't" statements |
| Failure modes | Sections like `## Failure modes`, `## Error cases`, `## Edge cases`, mentions of "timeout", "retry", "fallback", "graceful degradation" |
| Interface contracts | Sections like `## API`, `## Schema`, `## Contract`, code blocks with type definitions, JSON examples, OpenAPI snippets, function signatures |

If an element is found verbatim, capture it as-is and mark it `extracted-from-issue`. Do NOT prompt the user for elements that the issue already specifies — that wastes their time and creates friction.

### Step 3: Prompt for missing elements

For each element that is still missing after Steps 1 and 2, draft a 3-5 item proposal based on the issue's domain, then surface a Proactive-Autonomy escalation per [`references/escalation-format.md`](../../references/escalation-format.md) using `AskUserQuestion`. The six fields per element prompt:

- **Situation** — Issue #{N} is missing the {element-name} portion of its specification. Without it, downstream phases cannot {phase-specific consequence: PLAN cannot fence implementation / CODE cannot test failure paths / VERIFY cannot evaluate adversarial cases}.
- **What I tried** — Read issue body and {N} comments. Searched for cues ({list of cues from the table above}). No prior statement found.
- **Options** — (1) Accept the agent's proposal as written. (2) Accept with edits (the agent will prompt for changes). (3) Reject — the specification is incomplete and the issue should be updated first.
- **Recommendation** — Option {1|2} based on the proposal's specificity. Option 3 only when the agent cannot produce a credible proposal from the issue context.
- **Blocking?** — Yes. Blocks PLAN; the Spec Validation Gate cannot proceed until this resolves.
- **Risk** — Choosing Option 1 with a wrong proposal locks the implementation into the wrong fence; the agent will surface a Stranger Test failure later but the user will have wasted PLAN cycles. Choosing Option 3 means the issue must be updated before re-running the workflow.

Surface ONE escalation per missing element. Do not bundle (a compound prompt forces the user to make multiple decisions in one click; see `references/escalation-format.md` anti-patterns).

### Step 4: Write the journal

Write the captured specification to the journal under the canonical heading. Idempotent (rewrite the section if it exists; append it if it doesn't):

```markdown
## Specification

_Captured by specification-capture skill on YYYY-MM-DD. Source: {extracted-from-issue | user-confirmed | mixed}._

### Non-goals

- {non-goal 1}
- {non-goal 2}

### Failure modes

- **Timeouts** — {expected behavior when an upstream call exceeds expected latency}
- **Partial failures** — {expected behavior when some operations succeed and others fail}
- **Invalid input** — {expected behavior when input violates the contract: error type, fallback, user-visible message, log signal}
- **Missing context** — {expected behavior when required config, env vars, or state are absent}

### Interface contracts

- {Contract 1: schema, signature, or shape; format depends on what the change touches}
- {Contract 2}
```

The four failure-mode sub-bullets are the minimum coverage. The skill MUST NOT skip any of them — if a category genuinely doesn't apply, capture it as `none — {one-clause reason}` per the `none`-as-positive-statement discipline used in `references/evidence-bundle-format.md`. Bare blank is not permitted.

After writing, verify by re-reading: `awk '/^## Specification$/,/^## /{print}' "$JOURNAL"` should produce the section back. If it doesn't, halt with `SPEC_CAPTURE_BLOCK: journal write verification failed`.

### Step 5: Return the captured specification

Return the captured specification to the invoking command in this shape:

```markdown
## Captured Specification

**Issue**: #{N}
**Journal**: .decisions/issue-{N}.md
**Source**: {extracted-from-issue | user-confirmed | mixed}

### Non-goals
{...}

### Failure modes
{...}

### Interface contracts
{...}
```

Downstream consumers (`implementation-planner` agent, Stranger Test gate, Phase 4 evidence bundle producer) read these elements and reference them by name (`Non-goals touched`, `Failure modes covered`, `Interface contract`).

## Per-invoker scope

| Invoker | Required elements | Behavior on existing journal |
|---|---|---|
| `commands/start.md` Phase 1 | All three (non-goals, failure modes, interface contracts) | Required for PLAN to proceed. Treat partial capture as BLOCK; complete it via Step 3. |
| `commands/design.md` Phase 1 | Non-goals + interface contracts (failure modes optional but recommended) | If the journal already has the elements, surface them in the design discussion as the fence. If missing, capture during the design conversation. |
| `commands/brainstorm.md` Phase 1 | Non-goals only (the brainstorm is bounded by what's IN scope) | If non-goals exist in the journal, brainstorm only inside the fence. If missing, capture them BEFORE generating approaches — otherwise the brainstorm sprawls. |
| `commands/debug.md` Phase 3 (via `goal-contract-capture`) | Outcome (from the failure description) + acceptance criterion (the reproducing test) + root-cause constraints. The full three-element specification is skipped — a confirmed bug already carries its context. | Captured after hypothesis confirmation, not at entry. The reproducing test is the AC; no separate spec gate. |

The skill always writes the elements it captures to the journal regardless of invoker. A `/flow:brainstorm` call that captures non-goals first will pre-populate that element for a later `/flow:start` call on the same issue, eliminating duplicate prompting.

## Anti-patterns

| Excuse | Response |
|---|---|
| "The acceptance criteria are clear enough; specification capture is busywork" | The criteria scope WHAT. The three elements scope what the implementation IS NOT, how it FAILS, and what SCHEMAS it must honor. None of those are derivable from the criteria alone. |
| "I'll capture the elements during PLAN when I know more" | PLAN's fence is built FROM the specification. Capturing during PLAN is post-hoc rationalization. The Stranger Test gate at end-of-PLAN will fail. |
| "Failure modes are obvious; the implementation will handle them naturally" | The four mandatory categories (timeouts, partial failures, invalid input, missing context) require explicit positive statements. Implicit handling produces silent bugs. |
| "Interface contracts are internal; we don't need to write them down" | The contract is what makes the change consumable by callers. If the change is internal-only, capture the internal module-boundary contract. |
| "I'll skip the user prompt — I can guess the right answer" | The skill's default is to draft a proposal and surface it via AskUserQuestion (Option 1 = accept proposal). The user's confirmation is fast; silent guessing locks the implementation into the agent's interpretation, which the user may not have agreed to. |
| "The journal already has a Specification section, so I'll trust it without re-checking" | Step 1 verifies journal mtime against issue updatedAt. If the issue was updated after the journal write, the captured specification may be stale and must be reconciled. |

## Verification gates

The invoking command MUST verify after this skill returns:

1. The journal contains a `## Specification` heading
2. All three element subsections are present and non-empty (or `none — {reason}` for failure-mode categories that don't apply)
3. The skill's return payload matches the journal contents

If any check fails, the invoking command halts and re-invokes the skill with the failure noted. Silent acceptance of partial specs is forbidden.
