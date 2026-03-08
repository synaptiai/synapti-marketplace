---
name: architecture-patterns
description: "[flow] Use when designing systems, evaluating structural changes, or reviewing architecture decisions. Guides design-from-functionality, coupling analysis, and C4 model thinking."
allowed-tools: Read, Bash, Grep, Glob, TaskCreate, TaskList, TaskUpdate
context: fork
agent: Explore
---

# Architecture Patterns

Domain skill for system design, structural evaluation, and architecture decisions.

## Iron Law

**DESIGN ARCHITECTURE FROM FUNCTIONALITY, NOT TO FUNCTIONALITY. If you can't trace a component to a user flow, delete it.**

Architecture serves user flows. Not the other way around.

## Prerequisite: Map Flows First

Before designing ANYTHING, enumerate flows. Track each design activity as a task:

```
TaskCreate("Map user/admin/system flows", "Enumerate all flows before designing components")
TaskCreate("Coupling analysis", "Check imports, circular deps, god objects, hidden coupling")
TaskCreate("Design proposal", "Components, responsibilities, dependencies, data flow")
TaskCreate("Decision documentation", "Context, options, trade-offs, decision, consequences")
```

1. **User flows** — what does the user do, step by step?
2. **Admin flows** — what does the operator/admin do?
3. **System flows** — what happens automatically (cron, webhooks, events)?

Each flow is a sequence: trigger → steps → outcome. Every component must serve at least one flow.

TaskUpdate("Map user/admin/system flows", status: "completed") after all flows enumerated.

## C4 Model Views

Navigate the right level of abstraction:

| Level | Shows | When to Use |
|-------|-------|-------------|
| **Context** | System + external actors | Starting a new project, explaining to stakeholders |
| **Containers** | Deployable units (services, DBs, queues) | Designing infrastructure, choosing tech stack |
| **Components** | Modules within a container | Designing internal structure, reviewing coupling |
| **Code** | Classes, functions, interfaces | Implementation decisions, code review |

**Rule**: Start at the highest relevant level. Zoom in only when needed. Most design discussions happen at Components level.

## Coupling Analysis

TaskUpdate("Coupling analysis", status: "in_progress")

Check actual dependencies, not assumed ones:

```bash
# Find imports and dependencies
grep -rn "import\|require\|from " --include="*.{ts,js,tsx,jsx,py,rb}" -l
# Check for circular dependencies
# Look for A imports B AND B imports A patterns
```

**Red flags:**
- **Circular dependencies** — A→B→C→A. Break the cycle with interfaces or events.
- **God objects** — One module imported by >50% of files. Split by responsibility.
- **Hidden coupling** — Shared mutable state, global variables, implicit ordering.
- **Shotgun surgery** — One feature change requires edits in 5+ unrelated files.

## Dependency Direction

Dependencies should flow ONE direction:

```
UI → Application → Domain → Infrastructure
        ↓
    External APIs
```

- **Domain** depends on nothing
- **Application** depends on domain
- **UI/Infrastructure** depends on application and domain
- Never: Domain → UI, Domain → Infrastructure

## API Design Principles

- Align endpoints with documented user flows, not internal structure
- One endpoint per user action (not per database table)
- Version APIs when breaking changes are unavoidable
- Validate at the boundary — trust internal code

TaskUpdate("Coupling analysis", status: "completed")

## Decision Framework

TaskUpdate("Decision documentation", status: "in_progress")

For each architectural decision, document:

| Field | Content |
|-------|---------|
| **Context** | What's the situation? What forces are at play? |
| **Options** | 2-4 distinct approaches (not just "do it" vs "don't") |
| **Trade-offs** | Pros and cons per option with evidence |
| **Decision** | Which option and why |
| **Consequences** | What changes? What new constraints? What risks accepted? |

TaskUpdate("Decision documentation", status: "completed")
Use TaskList to confirm all design activities resolved before proceeding to implementation.

## Existing Pattern Check

Before proposing new architecture, check what exists:

```bash
# What patterns does the codebase already use?
ls -la src/ app/ lib/
grep -r "class \|module \|interface " --include="*.{ts,js,py,rb}" | head -20
git log --oneline --all -- "src/*/index.*" | head -10
```

**Rule**: Follow existing patterns unless there's a documented reason to diverge. Consistency beats novelty.

## Anti-Patterns

| Anti-Pattern | Symptom | Fix |
|-------------|---------|-----|
| Design before mapping flows | Components that serve no user action | Map flows first, then design |
| Pattern from trends | Using microservices because "everyone does" | Choose patterns from requirements |
| Premature abstraction | Interfaces with one implementation | YAGNI. Concrete first, abstract when needed |
| Astronaut architecture | 5 layers for a CRUD app | Match complexity to actual requirements |
| Copy-paste architecture | Same structure regardless of problem | Each system is different. Design for THIS problem. |

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "We might need this later" | YAGNI. Build for now, extend when needed. The cost of removing is lower than maintaining unused code. |
| "This is best practice" | Best practice for WHOM? Show the requirement it serves. |
| "Let's add an abstraction layer" | For what? One implementation behind an interface is overhead, not architecture. |
| "We need to future-proof this" | You can't predict the future. Build for today, refactor when requirements change. |
| "Let's use microservices" | For a team of 3? Monolith first. Split when you have evidence of scaling needs. |
