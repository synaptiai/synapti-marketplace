---
name: team-coordination
description: "Coordinate agent teams for adversarial review or parallel implementation, including team spawning, task sizing, review protocol, and teammate health monitoring. Only loaded when agentTeams is enabled. Use when dispatching multi-agent work or adversarial review."
allowed-tools: Bash, Read, TaskCreate, TaskList, TaskUpdate
context: fork
agent: general-purpose
disable-model-invocation: true
---

# Team Coordination

Domain skill for orchestrating agent teams. Only relevant when `agentTeams: true` in settings.

Requires: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable.

## Iron Law

**INDEPENDENT ANALYSIS BEFORE SHARED CONCLUSIONS. Teammates who see each other's findings are contaminated reviewers.**

The value of a team is independent perspectives. Sharing findings before independent analysis destroys that value.

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

When spawning a review team, each facet runs as a **paired reviewer** (skeptic + verifier) with a **disposition-only challenge round** between them. The protocol is the contract frozen in `.decisions/issue-86.md` and emitted by `commands/review.md` Path A.

### Cost expectation

Per `/flow:review` run with default 6-facet fan-out:

| Phase | LLM calls |
|-------|-----------|
| Phase 1 — Independent Analysis (5 agent facets × 2 + 2 holdout-validation Skill calls) | 12 |
| Phase 2 — Share findings (lead-only orchestration; no LLM call) | 0 |
| Phase 3 — Challenge (each Agent reviewer challenges the other's findings, 5 × 2; holdout-validation excluded — see review.md A.1 note) | 10 |
| Phase 4 — Synthesize (main agent, 1 consolidation pass) | 1 |
| Phase 5 — Emit consolidated output (lead-only; no LLM call) | 0 |
| **Total** | **≈23 calls** (≈3.8× single-session baseline of 6) |

Wall-clock: ≈1.5–2× single-session via parallel dispatch within each phase. The cost is opt-in (`agentTeams: false` by default) and gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

### Phase 1: Independent Analysis (paired reviewers per facet)

For each facet, dispatch **two** subagents with orthogonal prompt lenses. Both run in parallel and never see each other's findings during this phase.

| Variant | System-prompt lens |
|---------|---------------------|
| **skeptic** | "Assume the diff is broken until proven otherwise. Flag every behavior you cannot prove correct from the code as written." |
| **verifier** | "Assume the diff is correct as a baseline. Look only for missed edge cases, undocumented contract assumptions, or invariants that aren't enforced." |

Default 6-facet topology (12 invocations in one parallel dispatch — 5 Agent pairs and 2 Skill calls):

```
Agent(security-reviewer-skeptic) | Agent(security-reviewer-verifier)
Agent(code-reviewer-skeptic) | Agent(code-reviewer-verifier)
Agent(convention-checker-skeptic) | Agent(convention-checker-verifier)
Agent(test-runner-skeptic) | Agent(test-runner-verifier)
Agent(error-handler-inspector-skeptic) | Agent(error-handler-inspector-verifier)
Skill(holdout-validation) [skeptic lens] | Skill(holdout-validation) [verifier lens]
```

The holdout-validation pair is dispatched as Skills (not Agents) because the project does not define a `holdout-validation` agent — the skill is the contract. As a consequence, the holdout-validation pair contributes findings to A.2 auto-consensus matching but is **excluded from the Phase 3 challenge round** (Skills do not accept the structured `[challenge mode]` invocation that Agents do). See `commands/review.md` A.1 note for the implementation rule.

Each returns P1/P2/P3 findings with `file:line` citations and a category. **No challenge information is included in this phase** — outputs are independent.

### Phase 2: Share Findings

Lead collects all 12 finding sets (10 Agent + 2 Skill). No LLM call. Indexes findings by facet for the per-facet challenge round. Holdout-validation findings are indexed for A.2 auto-consensus matching only and bypass Phase 3.

### Phase 3: Challenge (disposition-only, no diff re-read)

For each facet, dispatch each variant to challenge the OTHER variant's findings. **The challenger does NOT re-read the diff.** The challenger labels each of the other's findings with one of three dispositions:

| Disposition | Meaning |
|-------------|---------|
| `AGREE` | Challenger also flagged this OR confirms it as a real issue |
| `DISAGREE` | Challenger believes this is not a real issue (must give a one-line reason) |
| `REFINE` | Real issue, but priority/category differs (challenger states the corrected priority/category) |

Challenge prompt (issued per facet, both directions in parallel):

```
You are reviewer-{A|B} for facet {facet}. Reviewer-{B|A} raised the following
findings on the same diff you reviewed independently. For each finding, respond
with exactly one line:

  {finding-id} AGREE
  {finding-id} DISAGREE: {one-line reason}
  {finding-id} REFINE: priority={P1|P2|P3} category={text}

Do NOT re-read the diff. Decide based on your prior independent analysis only.

Findings to challenge:
{list of the OTHER reviewer's findings: ID, file:line, priority, category}
```

10 challenge prompts run in parallel (5 agent facets × 2 directions; the holdout-validation Skill pair is excluded — see A.1 note).

### Phase 4: Synthesize (consolidation rules)

Lead applies the consolidation table to each finding:

| Origin | Other reviewer's disposition | Consolidated confidence | Disposition vocab |
|--------|------------------------------|-------------------------|-------------------|
| Both raised independently (file ±2 lines, priority ±1) | n/a | **HIGH** | `consensus` |
| One raised, other AGREE | AGREE | **HIGH** | `validated` |
| One raised, other REFINE | REFINE | **MEDIUM** | `refined` (priority/category from REFINE) |
| One raised, other DISAGREE | DISAGREE | **LOW** | `kept` |
| One raised, other timed out / errored | none | **MEDIUM** | `unchallenged` |
| Both raised, both DISAGREE'd in challenge | n/a | **DROPPED** | excluded; logged in journal |

**Independence-match window** (hard-coded for v1): same facet AND same file AND lines within ±2 AND priority within ±1 (P1↔P2 counts; P1↔P3 does not).

The disposition vocabulary `consensus|validated|refined|kept|unchallenged` is the controlled set emitted into the `FLOW_REVIEW_CYCLE` marker — see `references/finding-ledger-parser.md` for the marker schema.

### Phase 5: Emit consolidated output

Lead writes the per-priority finding tables with two new columns:

```markdown
### P1 — Critical
| # | Category | Location | Issue | Fix | Confidence | Disposition |
|---|----------|----------|-------|-----|------------|-------------|
| F1 | security | src/auth.ts:42 | ... | ... | HIGH | consensus |
| F2 | correctness | src/api.ts:88 | ... | ... | LOW | kept (B disagreed: "off-by-one is intentional") |
```

And the extended `FLOW_REVIEW_CYCLE` marker (7 fields per row; example exercises three disposition values):

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[F1|P1|security|src/auth.ts:42|open|HIGH|validated,F2|P2|correctness|src/api.ts:88|open|MEDIUM|refined,F3|P1|race|src/job.ts:17|open|LOW|kept] -->
```

DROPPED findings do NOT appear in the marker; they are logged in the decision journal under `## Dropped after challenge` for traceability.

### Cognitive Bias Awareness

- **Anchoring**: A reviewer who reads another's findings before producing their own anchors on them. Phase 1 is strictly independent for this reason; the challenge round in Phase 3 explicitly forbids diff re-read so the reviewer cannot synthesize fresh "agreements" from re-reading.
- **Groupthink**: Confidence-HIGH-on-everything is a smell, not a goal. A healthy review surfaces some `kept` (challenged but disagreed) findings.
- **Central-judge bias**: The protocol intentionally has no third-agent challenger and no main-agent adjudicator. The lead consolidates mechanically via the table above; it does not opine on which finding is "really" correct.

## Fallback Semantics (per-facet graceful degradation)

A failure in the paired/challenge mechanism **never blocks `/flow:review`**. Per-facet matrix:

| Condition | Behavior |
|-----------|----------|
| `agentTeams: false` | Skip paired protocol entirely. Emit `Path A skipped: agentTeams=false. Using Path B (single-session).` to stdout and use single-reviewer dispatch (the `commands/review.md` Path B fallback). |
| `agentTeams: true` AND env var `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` unset | Single-line `WARN` to stderr: `agentTeams enabled but env var unset; using single-reviewer fallback`. Use Path B. |
| `agentTeams: true` AND env var set, but one variant (skeptic OR verifier) fails to spawn for one facet | That facet uses single-reviewer fallback (the responding variant). Other facets continue paired. Note in output: `facet {facet}: single-reviewer fallback (verifier failed to spawn)`. |
| Variant times out (`timeouts.teammateTimeout`) | Use the responding variant's findings only for that facet. Mark each finding as `unchallenged` (MEDIUM confidence). |
| BOTH variants fail for one facet | Re-dispatch with single-reviewer Path B for that facet. Note in output. |
| Challenge round itself fails (cannot dispatch challenger prompt) | Skip challenge step. Findings included as `unchallenged`. Do not block review. |

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
- The hook sends feedback via stderr output (exits 0; exit code 2 has no defined semantics for TeammateIdle)

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
