---
name: brainstorming
description: "Explore multiple approaches through structured option generation, trade-off analysis, and collaborative approach selection. Use when evaluating alternatives before committing to an implementation strategy."
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion, TaskCreate, TaskList, TaskUpdate
context: fork
agent: Explore
---

# Brainstorming

Domain skill for multi-option exploration and collaborative decision-making before implementation.

## Iron Law

**EXPLORE BEFORE COMMITTING. The cost of choosing wrong is 10x the cost of exploring options.**

Every hour spent exploring saves a day of rework from the wrong approach.

## When to Brainstorm

- Multiple valid approaches exist (and you know it)
- Requirements are unclear or ambiguous
- New territory — no existing patterns to follow
- User says "help me think through" or "what are our options"
- You catch yourself defaulting to the first idea

## Exploration Process

Track the brainstorming lifecycle with tasks:

```
TaskCreate("Clarify goal", "Confirm what, why, who before generating options")
TaskCreate("Check existing patterns", "Search codebase for how similar problems are solved")
TaskCreate("Generate approaches", "Produce 2-4 distinct approaches with pros, cons, effort, risk")
TaskCreate("Compare and recommend", "Build comparison table, highlight trade-offs, recommend")
TaskCreate("User decision", "Present recommendation, get user choice, log decision")
```

### 1. Clarify the Goal

TaskUpdate("Clarify goal", status: "in_progress")

Before generating options, confirm you understand:
- **What** needs to happen (outcome, not implementation)
- **Why** it needs to happen (motivation, constraints)
- **Who** is affected (users, systems, team)

Use `AskUserQuestion` if the goal is ambiguous. Don't guess.

TaskUpdate("Clarify goal", status: "completed")

### 2. Check Existing Patterns

TaskUpdate("Check existing patterns", status: "in_progress")

Before proposing new approaches, see what the codebase already does:

```bash
# How does the project handle similar problems?
grep -r "relevant_pattern" --include="*.{ts,js,py,rb}" -l
git log --oneline --all --grep="related keyword" | head -10
```

Existing patterns get priority — consistency has value.

TaskUpdate("Check existing patterns", status: "completed")

### 3. Generate 2-4 Approaches

TaskUpdate("Generate approaches", status: "in_progress")

For each approach, fill out:

| Field | Content |
|-------|---------|
| **Name** | Short, memorable label |
| **Summary** | One-line description |
| **Pros** | Bullet list of advantages |
| **Cons** | Bullet list of disadvantages |
| **Effort** | Small / Medium / Large |
| **Risk** | Low / Medium / High |

**Rules:**
- Minimum 2 approaches, maximum 4
- Approaches must be **genuinely distinct** (not minor variations)
- Include the "do nothing" or "simplest possible" option when applicable
- Each approach must be implementable — no hand-waving

TaskUpdate("Generate approaches", status: "completed")

### 4. Compare Trade-offs

TaskUpdate("Compare and recommend", status: "in_progress")

Build a comparison table across key dimensions:

| Dimension | Approach A | Approach B | Approach C |
|-----------|-----------|-----------|-----------|
| Simplicity | | | |
| Flexibility | | | |
| Performance | | | |
| Consistency | | | |
| Effort | | | |
| Risk | | | |

TaskUpdate("Compare and recommend", status: "completed")

### 5. Recommend and Decide

TaskUpdate("User decision", status: "in_progress")

- State your recommendation with rationale
- Highlight the most important trade-off
- Let the user choose — recommendation is not a decision
- Use `AskUserQuestion` for the final decision

TaskUpdate("User decision", status: "completed") after user selects an approach.
Use TaskList to confirm the full brainstorming lifecycle completed.

## Trade-Off Dimensions

Common dimensions to evaluate (pick the relevant ones):

| Dimension | Tension |
|-----------|---------|
| Simplicity vs Flexibility | Simple now vs adaptable later |
| Speed vs Correctness | Ship fast vs get it right |
| Consistency vs Innovation | Follow patterns vs better approach |
| Build vs Buy | Custom solution vs existing library |
| Coupling vs Convenience | Decoupled modules vs easy implementation |
| Explicit vs Implicit | Verbose but clear vs concise but magical |

## Anti-Patterns

| Anti-Pattern | Symptom | Fix |
|-------------|---------|-----|
| **Analysis paralysis** | >4 options, endless comparison | Cap at 4. Decide with available info. |
| **False dichotomy** | "We can only do A or B" | Challenge the constraint. Usually there's a C. |
| **Bikeshedding** | 30 min debating variable names | Is this decision reversible? If yes, just pick one. |
| **Anchoring** | First option dominates discussion | Present all options before discussing any. |
| **Groupthink** | Everyone agrees immediately | Play devil's advocate. What could go wrong? |

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "Let's just go with the obvious approach" | Obvious to whom? Explore first, then decide. |
| "We don't have time to brainstorm" | You don't have time to rewrite after choosing wrong. |
| "I've done this before, I know the best way" | Great. Then documenting why takes 2 minutes. Do it. |
| "All approaches are roughly the same" | Then pick the simplest. If they're truly equivalent, simplicity wins. |
