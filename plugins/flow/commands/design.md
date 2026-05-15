---
description: "Design or review architecture for a feature or system. Analyzes existing patterns, evaluates coupling, and produces design decisions."
argument-hint: [feature-description-or-issue-number]
allowed-tools: Bash, Read, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Design: $ARGUMENTS

Architecture discussion and design validation. Follows Explore > Plan > Review > Decide loop.

## Required Skills

This command operates with these domain skills loaded:
- `architecture-patterns` — C4 design, coupling analysis, decision framework
- `capability-discovery` — detect available agents and tech stack
- `specification-capture` — read existing specification from journal or capture missing elements (Phase 1)

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure for any Proactive-Autonomy escalation surfaced during design

## Phase 1: EXPLORE

Map existing architecture before proposing anything. Execute in parallel:

```!
# 1. Project structure
ls -la src/ app/ lib/ packages/ 2>/dev/null || ls -la

# 2. If issue number given, load issue context. Take the first whitespace-
# separated token; accept only if it is *all* digits. Inputs like
# "foo42 strategy" (where greedy digit-extraction would otherwise pluck
# `42` and fire `gh issue view 42` on an unrelated issue) are rejected to
# empty ISSUE_NUM. Supports usage like /flow:design 42 (decoupled auth
# service architecture).
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac
echo "ISSUE_NUM=$ISSUE_NUM"
[ -n "$ISSUE_NUM" ] && gh issue view "$ISSUE_NUM" --json title,body,labels 2>/dev/null

# 3. Current branch context
git branch --show-current
git log --oneline -5

true
```

**Parallel Agent + Skill calls:**

```
Agent(Explore):
  "Analyze the architecture of this project. Find:
   1. Entry points (main files, route definitions, controllers)
   2. Dependency structure (imports between modules)
   3. Existing design patterns (MVC, service layers, event-driven, etc.)
   4. Code related to: $ARGUMENTS
   Report: module map, dependency direction, patterns found."
```

```
Skill(capability-discovery):
  Discover tech stack, available agents, and project conventions.
```

**Map user flows** (from architecture-patterns skill):
- What user actions relate to this feature?
- What system flows are affected?
- What existing components are involved?

**Read or capture specification** (when an issue is in scope):

Architecture decisions need a fence — the same `## Specification` (non-goals, failure modes, interface contracts) that `commands/start.md` captures. Before proposing the design, invoke the `specification-capture` skill to read existing specification from the journal or capture missing elements. The skill is idempotent: if `commands/start.md` already captured the spec for this issue, the skill returns it verbatim; otherwise it captures non-goals + interface contracts (failure modes are optional during design but recommended).

```
Skill(specification-capture):
  Inputs:
  - Issue context: {pre-fetched issue title, body, comments, labels}
  - Journal path: .decisions/issue-$ISSUE_NUM.md
  - Invocation reason: design
```

If `$ISSUE_NUM` is empty (design is exploratory, not tied to an issue), skip this step — there is no journal to write to. The design discussion proceeds without a frozen fence; the user is responsible for capturing the spec when the design lands in an issue.

After the skill returns, surface the non-goals and interface contracts in the design discussion explicitly: every architecture decision must be reasoned against these constraints. A design that violates a captured non-goal is a scope mismatch, not a candidate.

## Phase 2: PLAN

Create tasks to track each design activity:

```
TaskCreate("Map existing architecture", "Identify entry points, dependency structure, existing patterns relevant to $ARGUMENTS")
TaskCreate("Identify abstraction level", "Determine C4 level: Context, Containers, Components, or Code")
TaskCreate("Propose design", "Map components, dependencies, data flow, integration points, API surface")
TaskCreate("Coupling and convention review", "Check circular deps, god objects, dependency direction, convention alignment")
TaskCreate("Design decision", "Present trade-offs, get user approval, log to decision journal")
```

TaskUpdate("Map existing architecture", status: "in_progress")

Apply C4 model thinking at the appropriate level:

1. **Identify the right abstraction level** — Context, Containers, Components, or Code
2. **Map what exists** vs **what's new** for this feature
3. **Propose design** with:
   - Components and their responsibilities
   - Dependencies and data flow
   - Integration points with existing code
   - API surface (if applicable)

TaskUpdate("Map existing architecture", status: "completed")
TaskUpdate("Identify abstraction level", status: "completed")
TaskUpdate("Propose design", status: "in_progress")

Present the design proposal to the user. Use the decision framework from architecture-patterns:

| Field | Content |
|-------|---------|
| **Context** | {situation and forces} |
| **Options** | {2-4 approaches} |
| **Trade-offs** | {per-option analysis} |
| **Recommendation** | {preferred option and why} |

TaskUpdate("Propose design", status: "completed")

## Phase 3: REVIEW

TaskUpdate("Coupling and convention review", status: "in_progress")

Validate the design with evidence:

**Coupling check:**

```
Agent(Explore):
  "Check coupling and dependency health for this project:
   1. Find circular dependencies
   2. Identify god objects (files imported by many others)
   3. Check dependency direction (does domain depend on infrastructure?)
   4. Flag hidden coupling (shared mutable state, globals)
   Report: coupling findings with file:line citations."
```

**Convention alignment:**
- Does the proposed design follow existing project patterns?
- Are naming conventions consistent?
- Does the dependency direction align with the existing architecture?

**Present trade-offs** to the user:
- What does this design make easy?
- What does it make hard?
- What constraints does it introduce?

TaskUpdate("Coupling and convention review", status: "completed")

## Phase 4: DECIDE

TaskUpdate("Design decision", status: "in_progress")

Use the AskUserQuestion tool with contextual options to ask: "Recommended design: {approach}. {rationale}. Approve?"
2. **Log decision** to decision journal if on a feature branch:

```bash
BRANCH=$(git branch --show-current)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
JOURNAL_DIR=".decisions"
[ -n "$ISSUE_NUM" ] && [ -d "$JOURNAL_DIR" ] && cat >> "$JOURNAL_DIR/issue-$ISSUE_NUM.md" << 'ENTRY'
## Design Decision: {title}
**Date**: {YYYY-MM-DD} | **Category**: architecture
**Decision**: {what was decided}
**Rationale**: {why this approach}
**Consequences**: {what changes, new constraints}
ENTRY
```

   **Manifest emit** — append the design-decision artifact to the journal manifest alongside the freeform `## Design Decision` section:

   ```bash
   if [ -n "$ISSUE_NUM" ]; then
     "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
       --issue $ISSUE_NUM \
       --type design-decision \
       --metadata decision="$DECISION_TITLE" \
       --metadata category=architecture
   fi
   ```

3. TaskUpdate("Design decision", status: "completed")
4. **TaskList** — confirm all design tasks show status: completed
5. **Display summary**: Decision made, next steps available

## Completion

Present next steps:

- `/flow:start <issue>` — begin implementation
- `/flow:brainstorm` — explore more options before deciding
- Continue designing — refine the architecture further

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read codebase / architecture | 1 | Autonomous, read-only |
| Read existing specification from journal | 1 | Autonomous, read-only |
| Invoke `Skill(specification-capture)` if missing elements | 1 | Autonomous (writes journal) |
| `AskUserQuestion` (design decision) | n/a | User-driven decision point |
| Write to decision journal | 1 | Autonomous, file edit |
