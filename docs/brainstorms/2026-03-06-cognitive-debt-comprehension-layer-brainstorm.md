# Brainstorm: Comprehension Layer for AI-Driven Workflows

**Date**: 2026-03-06
**Status**: Draft
**Related Issue**: #18

## What We're Building

A **Comprehension Layer** that keeps humans informed and in control throughout a fully AI-driven gh-workflow lifecycle. In this model, humans define intent (gh-issue) but AI handles implementation, commits, PRs, reviews, and merges. The comprehension layer ensures humans can understand what AI built, why it made the choices it did, and whether those choices align with the original intent.

### The Reframed Problem

Traditional "cognitive debt" assumes humans are writing or reviewing code. In a fully AI-driven workflow, the human's role is **director, not builder**. The cognitive debt becomes: "AI built a system on my behalf and I have no structured way to understand it."

The four failure modes this addresses:

1. **Intent drift** — AI builds something technically correct but subtly different from what was intended
2. **Architectural blind spots** — AI makes structural decisions humans can't evaluate or maintain
3. **Accumulated opacity** — Each AI change is fine individually, but the system becomes a black box over iterations
4. **Loss of veto power** — The workflow moves too fast for humans to intervene when it matters

### Current Workflow (Fully AI-Driven)

```
Human: gh-issue (defines intent)
  |
AI: gh-start -> implement -> gh-commit -> gh-pr -> gh-review -> gh-address -> gh-merge
  |
Human: gh-release (approves release... of something they may not fully understand)
```

### Target Workflow (With Comprehension Layer)

```
Human: gh-issue (defines intent)
  |
AI: gh-start
  |--- Decision Journal: logs requirements interpretation, scope decisions
  |--- Human Gate: pauses for architecture/design choices
  |
AI: implement -> gh-commit
  |--- Decision Journal: logs implementation choices, trade-offs, alternatives considered
  |--- Human Gate: pauses for risk-sensitive changes (security, data models, public APIs)
  |
AI: gh-pr
  |--- Architecture Narrative: what was built, how it connects, mental model
  |--- Decision Summary: condensed journal in PR body
  |
AI: gh-review -> gh-address -> gh-merge
  |--- Decision Journal: logs review findings and how they were addressed
  |
Human: gh-explain (anytime)
  |--- Interactive Q&A: ask anything about what was built, decisions, architecture, failure modes
  |
Human: gh-release (informed approval)
```

## Why This Approach

We evaluated three approaches:

1. **Decision Journal + Smart Gates** — Lightweight, just logging and pauses. Doesn't build understanding proactively.
2. **Comprehension Layer (selected)** — Full stack: decision journal + gates + architecture narrative + interactive Q&A. Addresses all four failure modes with layered artifacts.
3. **Observer Agent** — Autonomous monitor. Elegant but fights the markdown-based plugin architecture.

Approach 2 was selected because it provides comprehension at every layer:
- **During execution**: Decision journal captures choices in real-time
- **At critical moments**: Human gates pause for high-stakes decisions
- **At completion**: Architecture narrative provides holistic understanding
- **On demand**: Interactive Q&A gives comprehension when and where the human needs it

## Key Decisions

### 1. Decision Journal Storage: File + PR Summary

The decision journal lives in two places:
- **Detailed journal**: A markdown file in the branch (e.g., `.decisions/issue-18.md`) committed alongside code. Travels with the PR, reviewable in GitHub, part of the repo history.
- **Condensed summary**: In the PR body. Digestible overview for quick understanding.

**Why**: Full history in the repo for auditability; condensed summary in the PR for quick comprehension. The file is the source of truth; the PR summary is the human-friendly view.

### 2. Human Gate Behavior: AskUserQuestion Inline

When the workflow hits a high-stakes decision, it uses AskUserQuestion to present the decision with context, alternatives, and trade-offs. The workflow blocks until the human responds.

**Why**: Works within current command execution model. No need for async notification infrastructure. The human is already in the terminal watching the workflow — AskUserQuestion is the natural interaction pattern.

**Gate triggers** (all four categories):
- Architecture & design choices (new patterns, abstractions, dependencies)
- Requirements interpretation (ambiguous acceptance criteria, assumptions about intent)
- Scope & trade-off decisions (simplifications, reinterpretations, deferred work)
- Risk-based (security, data models, public APIs, high-blast-radius areas)

### 3. Decision Capture: Hybrid (Defined Points + Self-Report)

Each command has specific points where it invokes the decision-journal skill (predictable, consistent). Additionally, AI self-reports any other significant decisions it makes during execution.

**Why**: Defined trigger points ensure we capture the decisions we know matter. Self-reporting catches decisions we didn't anticipate. Categories filter noise (architecture, requirements, trade-off, implementation, risk).

### 4. gh-explain Scope: Full System Understanding

The interactive Q&A command can answer about:
- What was built and why (grounded in actual code + decision journal)
- How changes fit into broader system architecture
- Whether changes fulfill the original issue's acceptance criteria
- Failure modes, edge cases, operational implications
- What a human should test or verify manually

**Why**: Half-measures don't solve comprehension. If a human asks "what happens if the database is down?", the answer should be grounded in the actual error handling code, not a generic response.

## Components

### New Skill: `decision-journal`

**Purpose**: Captures, structures, and persists significant decisions made during AI-driven workflow execution.

**Invoked by**: gh-start, gh-commit, gh-pr, gh-review, gh-address

**Decision entry format**:
```markdown
### [TIMESTAMP] [CATEGORY] Decision Title

**Context**: What situation prompted this decision
**Choice**: What was decided
**Alternatives considered**: What else was evaluated
**Trade-offs**: What was gained and what was given up
**Risk level**: Low / Medium / High / Critical
**Gate triggered**: Yes/No (was human consulted?)
```

**Categories**: `architecture`, `requirements`, `trade-off`, `implementation`, `risk`, `scope`

**Storage**: Writes to `.decisions/issue-{N}.md` in the branch. Appends entries as the workflow progresses.

### New Skill: `human-gate`

**Purpose**: Detects high-stakes decisions during workflow execution and pauses for human input via AskUserQuestion.

**Invoked by**: gh-start (after task breakdown), gh-commit (after change analysis), any command when AI self-reports a significant decision.

**Detection heuristics**:
- New dependency or framework introduction
- New abstraction layer or design pattern not present in existing code
- Changes to security-related code, authentication, authorization
- Database schema changes or data model modifications
- Public API surface changes (endpoints, contracts, types)
- Deviation from acceptance criteria or scope changes
- Ambiguous requirements that require interpretation

**Gate interaction pattern**:
```
[AI presents decision context, alternatives, and recommendation]

AskUserQuestion:
- "Approve recommended approach" (AI's recommendation, with rationale)
- "Choose alternative: [Alternative A]" (with trade-off explanation)
- "Choose alternative: [Alternative B]" (with trade-off explanation)
- "I need more information before deciding"
```

**All gate decisions are logged to the decision journal.**

### New Skill: `comprehension-report`

**Purpose**: Generates an architecture narrative at PR time — a human-readable story of what was built, how it connects to existing systems, and the mental model needed to reason about it.

**Invoked by**: gh-pr (during PR content generation)

**Inputs**: Decision journal, git diff, issue acceptance criteria, existing codebase context

**Output structure**:
```markdown
## What Was Built

### Summary
[2-3 sentence plain-language description of what changed and why]

### Architecture Decisions
[Key structural choices and their rationale, extracted from decision journal]

### How It Connects
[How new code relates to existing system components]

### Mental Model
[The conceptual framework needed to reason about this change — "think of it as..."]

### Requirements Adherence
[Map each acceptance criterion to what was implemented, flag any gaps or interpretations]

### Failure Modes & Edge Cases
[What could go wrong, how errors are handled, what's not covered]

### What to Verify
[Specific things a human should check or test to build confidence]
```

### New Command: `gh-explain`

**Purpose**: Interactive Q&A about what AI built, grounded in actual code, decision journal, and system context.

**When to use**: Anytime after AI has started working on an issue. Especially useful before gh-release to build comprehension.

**How it works**:
1. Reads the decision journal for the current branch/issue
2. Reads the diff (what changed)
3. Reads relevant source files for context
4. Reads the original issue for intent
5. Enters an interactive loop where the human asks questions

**Example interactions**:
- "Why did you choose X over Y?" → Grounded in decision journal entry
- "What happens if the API is unavailable?" → Traces actual error handling code
- "Does this meet acceptance criterion 3?" → Maps implementation to criteria
- "What's the blast radius if this fails?" → Analyzes dependencies and failure propagation
- "What should I manually test?" → Suggests verification steps based on risk areas
- "Explain the architecture of the new module" → Walks through the code structure with rationale

**Exit**: Human types "done" or selects "I understand enough to proceed"

### Modifications to Existing Commands

**gh-start**: After task breakdown, invoke `decision-journal` to log requirements interpretation. Invoke `human-gate` if acceptance criteria are ambiguous or if proposed architecture involves significant new patterns.

**gh-commit**: After change analysis, invoke `decision-journal` to log implementation decisions. Invoke `human-gate` if changes touch risk-sensitive areas.

**gh-pr**: Invoke `comprehension-report` to generate architecture narrative. Include condensed decision summary in PR body. Include full comprehension report as a PR section.

**gh-review**: When reviewing, check PR for comprehension report. Flag if missing. Verify requirements adherence section against actual acceptance criteria.

**gh-merge**: Before merge, display comprehension report summary. If any acceptance criteria are flagged as "interpreted" or "partially met", trigger human gate.

**gh-status**: Show which open PRs have decision journals, comprehension reports, and any pending human gates.

### Template Additions

**PR template** gets new sections:
- Decision Summary (condensed from journal)
- Architecture Narrative (from comprehension-report skill)
- Requirements Adherence Map

## Resolved Questions

1. **Decision journal cleanup**: Keep `.decisions/` files permanently in the repo. Full audit trail — anyone can trace why decisions were made months later.

2. **Gate sensitivity tuning**: Configuration-based. Users configure gate sensitivity in their project CLAUDE.md or workflow config. Categories and thresholds are adjustable per project.

3. **gh-explain session persistence**: Optional save on exit. At the end of a Q&A session, ask the human if they want to save the exchange. Low friction, human chooses.

4. **Cross-issue comprehension**: Full cross-issue tracking. Track how changes across related issues interact. When decisions reference other issues, maintain a cross-issue comprehension model that surfaces interactions and dependencies.

## Next Steps

1. Create implementation plan (`/ce:plan`)
2. Update issue #18 with refined scope
