# Specification Journal Format (specification-capture output contract)

Reference document. The canonical shape of the `## Specification` section that the `specification-capture` skill writes to `.decisions/issue-{N}.md`, the return payload it hands back to the invoking command, and the manifest metadata the invoker emits. Producers (`skills/specification-capture/SKILL.md`) and consumers (`commands/start.md` Phase 1 gates and Phase 2 planner dispatch, `commands/design.md`, `commands/brainstorm.md`, `agents/implementation-planner.md`, the Phase 4 evidence-bundle producer, `skills/goal-contract-capture/SKILL.md`) cite this file so the four-element check runs against a published shape rather than an implicit convention.

## The four elements

| # | Subsection heading | What it scopes | Consumed by |
|---|---|---|---|
| 1 | `### Non-goals` | What the implementation IS NOT | task `Non-goals touched:`, bundle `### Does NOT promise` |
| 2 | `### Failure modes` | How it behaves under infrastructure failure | task `Failure modes covered:` |
| 3 | `### Interface contracts` | Schemas, signatures, shapes it must honor | task `Interface contract:` |
| 4 | `### Risk map` | Where the core logic is most likely to be subtly wrong, and the check that tells right from wrong | task `Risk areas:`, task `Test plan:`, bundle `### Risk map coverage` |

Elements 1-3 are lists. Element 4 is a table. Every element subsection MUST be present and non-empty; `none — {one-clause reason}` is the only permitted empty value for a failure-mode category, and `disabled — specFirst.riskMap=false` is the only permitted non-table value for the risk map.

## Section shape

```markdown
## Specification

_Captured by specification-capture skill on YYYY-MM-DD. Source: {extracted-from-issue | user-confirmed | mixed}._

### Non-goals

- {non-goal 1}
- {non-goal 2}

### Failure modes

- **Timeouts** — {behavior when an upstream call exceeds expected latency}
- **Partial failures** — {behavior when some operations succeed and others fail}
- **Invalid input** — {behavior when input violates the contract: error type, fallback, user-visible message, log signal}
- **Missing context** — {behavior when required config, env vars, or state are absent}

### Interface contracts

- {Contract 1: schema, signature, or shape}
- {Contract 2}

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| {place in the logic} | {what the plausible wrong implementation does} | {concrete input} → right: {outcome}; wrong: {outcome} |
```

The four failure-mode categories are the minimum coverage. A category that genuinely does not apply is written as `none — {reason}`; bare blank is not permitted.

## Risk map rules

- **2 to 6 rows.** Fewer than 2 means the author has not looked; more than 6 means the rows are not the *most likely* mistakes.
- **Area** names a place in the core logic of this change: a comparison, an ordering, a boundary, a rounding, a precedence, an empty case, a stream/byte order, a key choice. Timeouts, partial failures, invalid input, and missing context are NOT risk-map areas — they belong under `### Failure modes`.
- **Plausible wrong version** states what a wrong-but-plausible implementation would do: reversed order, transposed streams, off-by-one, `>=` for `>`, wrong rounding direction, wrong operator precedence, wrong empty-collection result, wrong key.
- **Discriminating check** is one concrete input plus the two outcomes. The right and wrong versions MUST produce different outcomes on that input. An input on which both versions agree (identical elements, symmetric or palindromic data, zero, a single repeated value, a trivially small case) is not a discriminating check and MUST be replaced.
- The agent drafts the rows itself from the issue and the codebase; the user confirms or edits. The default recommendation is to accept the draft.
- When `specFirst.riskMap` is `false`, the subsection body is exactly `disabled — specFirst.riskMap=false` (no table). Downstream: tasks carry `Risk areas: (disabled by specFirst.riskMap)` and the evidence bundle's `### Risk map coverage` is `none — risk map disabled (specFirst.riskMap=false)`, which is not an auto-FAIL.

Example (rate-limited login, issue #142):

```markdown
### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| threshold comparison | rejects the 5th failure instead of the 6th (`>=` where `>` is meant) | exactly 5 failures then a 6th from account A → right: attempts 1-5 return 401, 6th returns 429; wrong: 5th returns 429 |
| window boundary | counts an attempt at exactly t=60s as inside the window (inclusive compare) | 5 failures at t=0s, 6th attempt at t=60.000s → right: 401 and counter restarts; wrong: 429 |
| counter key | keys the counter by IP, so accounts behind one NAT share a limit | 3 failures from A and 3 from B, same source IP → right: both accounts' next attempt returns 401; wrong: one of them returns 429 |
```

## Return payload

The skill returns this shape to the invoking command. It MUST match the journal contents byte-for-byte under each subsection heading (the invoker's verification gate 3 compares them):

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

### Risk map
{table, or `disabled — specFirst.riskMap=false`}
```

## Manifest metadata

After the skill returns, the invoker records the artifact with `bin/journal-record.sh --type specification`. The `elements=` value lists the subsections the journal actually carries:

| `specFirst.riskMap` | Metadata |
|---|---|
| `true` (default) | `--metadata elements=non-goals,failure-modes,interface-contracts,risk-map` |
| `false` | `--metadata elements=non-goals,failure-modes,interface-contracts --metadata risk_map=disabled` |

## Staleness

The journal is the source of truth. A journal section is reused verbatim only when all four subsections are present AND the issue has not been updated since the journal was last written (`git log -1 --format=%cd .decisions/issue-{N}.md` versus the issue's `updatedAt` from `gh issue view --json updatedAt`). Otherwise the skill fills only the missing or stale elements — it never re-prompts for elements the journal already holds.

## Goal contract mapping

`skills/goal-contract-capture/SKILL.md` lifts these subsections into the FlowGoal YAML `specification` block: `non_goals`, `failure_modes`, `interface_contracts`, and `risk_map: [{area, plausible_wrong_version, discriminating_check}]` (one entry per table row; absent when the subsection is the disabled marker).
