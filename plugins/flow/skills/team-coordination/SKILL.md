---
name: team-coordination
description: "[flow] Use when coordinating agent teams for adversarial review or parallel implementation. Guides when to spawn teams, task sizing, adversarial review protocol, and teammate health monitoring. Only loaded when agentTeams is enabled."
allowed-tools: Bash, Read, TaskCreate, TaskList, TaskUpdate
context: fork
disable-model-invocation: true
---

# Team Coordination

Domain skill for orchestrating agent teams. Only relevant when `agentTeams: true` in settings.

Requires: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable.

## When to Spawn Teams

| Scenario | Recommendation | Rationale |
|----------|---------------|-----------|
| Review with 3+ facets | Spawn team | Independent analysis enables adversarial protocol |
| Large feature (>5 acceptance criteria, independent modules) | Suggest team | Parallel implementation across modules |
| Debugging with competing hypotheses | Spawn team | Each teammate tests a different hypothesis |
| Small feature (<3 criteria) | Single session | Team overhead exceeds benefit |
| Sequential dependencies | Single session | Can't parallelize sequential work |

## Task Sizing

- **5-6 tasks per teammate** — enough work to stay busy, not so much they lose focus
- Each task should be completable without coordination
- Tasks must have clear acceptance criteria
- Overlapping file sets → same teammate (avoid merge conflicts)

## Adversarial Review Protocol

When spawning a review team:

### Phase 1: Independent Analysis

Each reviewer works in isolation:

```
Teammate(security-reviewer):
  "Review PR diff for security issues independently. Do not share findings until asked.
   Return P1/P2/P3 findings with file:line citations."

Teammate(code-reviewer):
  "Review PR diff for logic, quality, edge cases independently. Do not share findings.
   Return P1/P2/P3 findings with file:line citations."

Teammate(convention-checker):
  "Validate conventions independently. Return findings."
```

### Phase 2: Share Findings

Collect all findings from teammates.

### Phase 3: Challenge

Each reviewer challenges others' findings:

- "security-reviewer found no auth issues in auth.rb:42 — code-reviewer, do you agree?"
- "code-reviewer flagged a race condition — security-reviewer, is this exploitable?"

### Phase 4: Synthesize

Lead synthesizes results:
- **Consensus findings**: Both reviewers agree → highest confidence
- **Disputed findings**: Reviewers disagree → flag for human review
- **Unique findings**: Only one reviewer found it → include with lower confidence

## Teammate Health Protocol

### Timeout Handling

From settings: `timeouts.teammateTimeout` (default: 300 seconds)

If a teammate exceeds timeout:
1. Check if they have partial results
2. If yes, collect partial results and note as "incomplete review"
3. If no, mark the facet as "not reviewed" and proceed

### Failure Handling

If a teammate crashes or returns an error:
1. Log the failure
2. Fall back to single-session review for that facet
3. Note in the review summary: "Facet X reviewed in single-session fallback"

### Idle Handling

The `nudge-idle-teammate.sh` hook handles idle teammates:
- After 60s idle: "Check task list for unclaimed tasks"
- The hook sends feedback via exit code 2

## Implementation Team Protocol

When spawning an implementation team:

1. **Lead creates task list** with dependencies
2. **Lead assigns task groups** to teammates (non-overlapping file sets)
3. **Each teammate**:
   - Claims tasks from their group
   - Implements and commits
   - Marks tasks complete
4. **Lead monitors** via TaskList
5. **Lead runs final verification** after all teammates complete

## Single-Session Fallback

When teams are disabled or spawn fails, all team patterns fall back to:
- Sequential Agent dispatch (parallel where independent)
- Main thread handles coordination
- No adversarial protocol (single perspective)

The calling command handles the fallback — this skill only provides team-specific knowledge.
