# Architecture Decision Record

Supporting reference for `skills/architecture-patterns/SKILL.md`. The skill states the rules; this file holds the C4 level guide, the failure-mode questionnaire, and the full decision-record layout that `/flow:design` Phase 4 writes to the decision journal.

## C4 levels

| Level | Shows | When to use |
|-------|-------|-------------|
| **Context** | System + external actors | Starting a new project, explaining to stakeholders |
| **Containers** | Deployable units (services, DBs, queues) | Designing infrastructure, choosing a tech stack |
| **Components** | Modules within a container | Designing internal structure, reviewing coupling |
| **Code** | Classes, functions, interfaces | Implementation decisions, code review |

Start at the highest relevant level; zoom in only when needed. Most design discussions happen at Components.

## Dependency direction

```
UI → Application → Domain → Infrastructure
        ↓
    External APIs
```

Domain depends on nothing; Application depends on Domain; UI and Infrastructure depend on Application and Domain. Never Domain → UI or Domain → Infrastructure.

## Non-goals

Scope fences, written as declarative negations. Capture as a bulleted list:

- What the design does NOT cover (features, flows, actors out of scope)
- What it does NOT guarantee (consistency level, durability, isolation, ordering)
- What it does NOT replace (existing components that stay untouched)
- What it does NOT optimize for (latency, throughput, cost, developer ergonomics — name what is deprioritized)

"Does not support multi-region writes" is a non-goal. "May eventually support multi-region writes" is a hedge and is not useful.

## Failure modes

Every component in the design records its behavior for at least these modes:

| Failure mode | Design question | Record |
|--------------|-----------------|--------|
| **Timeouts** | What happens when a downstream call exceeds the deadline? | Error type, fallback, caller-visible outcome |
| **Partial failures** | What happens when some operations in a batch succeed and others fail? | Rollback / compensate / surface partial result / retry policy |
| **Invalid input** | What happens when input violates the contract (wrong type, missing field, out of range)? | Validation boundary, error shape, rejection vs. coercion |
| **Missing context** | What happens when required config, env vars, or upstream state is absent? | Fail-fast at startup / degrade gracefully / specific error |
| **Dependency outage** | What happens when a required external service is unreachable? | Circuit break / cache / queue / hard fail |
| **Resource exhaustion** | What happens under memory pressure, connection-pool exhaustion, or rate limits? | Backpressure / shed load / error shape |

A mode with no answer is a gap to close before proceeding, not a detail to defer to implementation. Modes captured at design time become test cases, verification commands, and explicit non-goals; modes discovered at implementation or verify time become rework.

## Decision record layout

| Field | Content |
|-------|---------|
| **Context** | What is the situation? What forces are at play? |
| **Options** | 2–4 distinct approaches (not just "do it" vs "don't") |
| **Trade-offs** | Pros and cons per option, with evidence |
| **Decision** | Which option and why |
| **Consequences** | What changes? What new constraints? What risks are accepted? |
| **Non-goals** | Bulleted negations (section above) |
| **Failure modes** | Table of mode → expected behavior for each component touched |

Non-goals and failure modes are not optional; a record missing them is incomplete and does not ship.

## Existing-pattern probes

```bash
ls -la src/ app/ lib/
grep -r "class \|module \|interface " --include="*.{ts,js,py,rb}" | head -20
git log --oneline --all -- "src/*/index.*" | head -10
```

Follow existing patterns unless there is a documented reason to diverge.
