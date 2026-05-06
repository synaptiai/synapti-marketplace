---
description: "Explore approaches before committing to implementation. Generates options, analyzes trade-offs, and helps select the best approach collaboratively."
argument-hint: [topic-or-issue-number]
allowed-tools: Bash, Read, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Brainstorm: $ARGUMENTS

Multi-option exploration before committing to an approach. Follows Explore > Generate > Compare > Decide loop.

## Required Skills

This command operates with these domain skills loaded:
- `brainstorming` — multi-option exploration, trade-off analysis
- `capability-discovery` — detect available agents and tech stack
- `specification-capture` — read existing specification from journal or capture non-goals (Phase 1)

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure for any Proactive-Autonomy escalation surfaced during brainstorming

## Phase 1: EXPLORE

Understand the goal before generating options. Execute in parallel:

**Parallel Bash calls:**

```bash
# 1. If issue number given, load context
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+')
[ -n "$ISSUE_NUM" ] && gh issue view $ISSUE_NUM --json title,body,labels

# 2. Current project state
git branch --show-current
git log --oneline -5
```

**Parallel searches:**

```
Agent(Explore):
  "Search the codebase for existing patterns related to: $ARGUMENTS.
   How does the project currently handle similar problems?
   Report: existing patterns, relevant files, conventions."
```

**Read or capture non-goals** (when an issue is in scope):

A brainstorm without explicit non-goals sprawls — every approach starts looking equally appealing because there is no scope fence to filter against. Before generating approaches, invoke the `specification-capture` skill to read existing non-goals from the journal or capture them now. The skill is idempotent: if `commands/start.md` or `commands/design.md` already captured non-goals for this issue, the skill returns them; otherwise it prompts for non-goals only (failure modes and interface contracts are not required at brainstorm time).

```
Skill(specification-capture):
  Inputs:
  - Issue context: {pre-fetched issue title, body, comments, labels}
  - Journal path: .decisions/issue-$ISSUE_NUM.md
  - Invocation reason: brainstorm
```

If `$ISSUE_NUM` is empty (the brainstorm is not tied to an issue — e.g., `/flow:brainstorm "what should our auth strategy be?"`), skip this step. The brainstorm proceeds without a journal-backed fence; the user can capture decisions later via `/flow:design` or `/flow:start`.

After the skill returns, treat the non-goals as a hard filter when generating approaches: an approach that violates a non-goal is out of scope and should not appear in the comparison table at all.

**Clarify the goal:**

If `$ARGUMENTS` is vague or ambiguous, use the AskUserQuestion tool with contextual options to get clarifications from the user with the question "The topic needs clarification. What outcome are you trying to achieve?"

## Phase 2: GENERATE

Create tasks to track the brainstorming process:

```
TaskCreate("Explore existing patterns", "Search codebase for how similar problems are currently handled")
TaskCreate("Generate approaches", "Produce 2-4 genuinely distinct approaches with pros, cons, effort, risk")
TaskCreate("Compare trade-offs", "Build comparison table across relevant dimensions, form recommendation")
TaskCreate("Select approach", "Present recommendation, get user decision, log to decision journal")
```

TaskUpdate("Explore existing patterns", status: "completed")
TaskUpdate("Generate approaches", status: "in_progress")

Produce 2-4 genuinely distinct approaches:

For each approach:

```markdown
### Approach {N}: {Name}

**Summary**: {one-line description}

**Pros**:
- {advantage 1}
- {advantage 2}

**Cons**:
- {disadvantage 1}
- {disadvantage 2}

**Effort**: Small / Medium / Large
**Risk**: Low / Medium / High
```

**Rules from brainstorming skill:**
- Minimum 2 approaches, maximum 4
- Approaches must be genuinely distinct (not minor variations)
- Include the "simplest possible" option when applicable
- Each approach must be implementable — no hand-waving
- Check existing codebase patterns first — consistency has value

TaskUpdate("Generate approaches", status: "completed")

## Phase 3: COMPARE

TaskUpdate("Compare trade-offs", status: "in_progress")

Build a comparison table:

```markdown
## Comparison

| Dimension | {Approach 1} | {Approach 2} | {Approach 3} |
|-----------|-------------|-------------|-------------|
| Simplicity | | | |
| Flexibility | | | |
| Consistency | | | |
| Effort | | | |
| Risk | | | |
```

Pick dimensions that matter for THIS decision (from brainstorming skill):
- Simplicity vs Flexibility
- Speed vs Correctness
- Consistency vs Innovation
- Build vs Buy
- Coupling vs Convenience

**Recommendation**: State the recommended approach with clear rationale. Highlight the most important trade-off.

TaskUpdate("Compare trade-offs", status: "completed")

## Phase 4: DECIDE

TaskUpdate("Select approach", status: "in_progress")

Use the AskUserQuestion tool with contextual options to ask: "I recommend Approach {N} because {rationale}. Which approach would you like to go with?"

2. **Log decision** to decision journal if on a feature branch:

```bash
BRANCH=$(git branch --show-current)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
JOURNAL_DIR=".decisions"
[ -n "$ISSUE_NUM" ] && [ -d "$JOURNAL_DIR" ] && cat >> "$JOURNAL_DIR/issue-$ISSUE_NUM.md" << 'ENTRY'
## Brainstorm Decision: {topic}
**Date**: {YYYY-MM-DD} | **Category**: approach-selection
**Options considered**: {list of approaches}
**Decision**: {chosen approach}
**Rationale**: {why this over alternatives}
ENTRY
```

3. TaskUpdate("Select approach", status: "completed")
4. **TaskList** — confirm all brainstorming tasks show status: completed
5. **Display summary**: Decision made, approaches considered, next steps.

## Completion

Present next steps:

- `/flow:start <issue>` — begin implementation with chosen approach
- `/flow:design` — dive deeper into architecture for the chosen approach
- Continue brainstorming — refine or explore sub-decisions
