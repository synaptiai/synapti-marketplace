# Agent Operating Primer Template

## AGENT-PRIMER.md Template

```markdown
# Agent Operating Primer — {Project Name}
<!-- Generated: {YYYY-MM-DD-HHMM} | Tier: {1-3} -->
<!-- Source: $HOME/.ai-first-kit/projects/{slug}/ -->
<!-- Regenerate: /ai-first-org-design-kit:operationalize -->

## Identity

### Mission
[From genome/00-identity/MISSION.md — operational mission + who we serve, 3-5 lines.
Include "What We Don't Do" if present — it prevents agent scope creep.]

### Values as Decision Rules
[For each value from genome/00-identity/VALUES.md:]

**{Value Name}:** {One-sentence decision rule from the "Definition" field}
- Agent instruction: {Content of the "Agent Instruction" field}

[Strip: Real Example, What We Sacrifice, Conflict Resolution details.
Keep only the operational encoding.]

### Value Priority (When Values Conflict)
[From genome/01-decision-architecture/TRADEOFF-RULES.md — "Priority Ordering" section only.
One numbered line per value in priority order. Strip all rule details and examples.]

## Authority

### Decision Tiers
[From genome/01-decision-architecture/AUTHORITY-MATRIX.md — the 4-tier table.
If governance/AUTHORITY-MATRIX.md adds agent-type-specific tiers, include those too.]

| Tier | Scope | Examples |
|------|-------|---------|
| Autonomous | [scope] | [examples] |
| Autonomous + Notify | [scope] | [examples] |
| Human-in-Loop | [scope] | [examples] |
| Human-Only | [scope] | [examples] |

### Failure Handling
[From genome/01-decision-architecture/AUTHORITY-MATRIX.md — the Failure Handling Protocol.
Include the numbered steps and the "Never:" line.]

### Escalation
[From governance/ESCALATION-PROTOCOLS.md — three sections:]

**Automatic triggers:** [list from "Automatic Escalation" section]

**Information package format:**
[The escalation template — Situation, What I tried, Options, Recommendation,
Time sensitivity, Risk if wrong]

### Time-Bound Defaults
[From governance/ESCALATION-PROTOCOLS.md — the time-bound defaults table]

| Risk Level | Timeframe | Default Action |
|-----------|-----------|----------------|

## Hard Boundaries (Non-Negotiable)
[FULL content from governance/HARD-BOUNDARIES.md. Do NOT distill this section.
Include every boundary with: what is prohibited, on violation response.
Include the boundary hierarchy at the end.
This is the most critical section of the primer.]

## Quality Standards

### By Output Type
[From genome/02-quality-standards/BY-OUTPUT-TYPE.md — for each output type:]

**{Output Type}:** Pass criteria:
1. [criterion 1]
2. [criterion 2]
...

[Strip: "What Good Looks Like" prose, examples of good/bad, anti-pattern details.
Keep only the numbered pass criteria.]

### Anti-Patterns
[From genome/02-quality-standards/ANTI-PATTERNS.md — bullet list:]
- **{Pattern Name}:** {One-line from "What it looks like" field}
[Strip: "Why it's wrong for us" and "What to do instead" — the name + description
is enough for pattern recognition.]

## Voice
[From genome/00-identity/VOICE.md:]

**Profile:** [One-line voice description from "Voice Profile" field]

**Words we use:** [comma-separated list]
**Words we never use:** [comma-separated list]

**Formality gradient:**
[Include the formality gradient table as-is]

[If agent communication standards exist, include them — these directly
instruct agent behavior.]

## Quality Gates
[From gates/INDEX.md + individual gate files. For each gate:]

| Gate | Type | Key Criteria |
|------|------|-------------|
| {Gate Name} | {Blocking/Advisory}, {Agent-Autonomous/Human-Gated} | {Top 3 pass criteria, comma-separated} |

[Strip: satisfaction metrics, escalation packages, on-fail details.
Keep: gate name, type, and the criteria agents check against.]

**Gate architecture:**
[Include the architecture diagram from INDEX.md if present — shows
which gates are parallel, sequential, and blocking.]

## Governance Operations

[From governance/POLICY-GENERATION.md, DECISION-LEDGER-SPEC.md, LEARNING-LOOP.md.
These are operational instructions — agents actively participate in governance growth.]

### Novel Situations
When you encounter a situation with no existing policy:
1. Recognize it as novel — "I don't have a policy for this"
2. Draft a candidate policy (read `governance/POLICY-GENERATION.md` for the template)
3. Include the draft in your escalation package alongside your regular options

### Decision Recording
For decisions at Autonomous+Notify tier or above, append an entry to
`$HOME/.ai-first-kit/projects/{slug}/evolution/decision-ledger.md`:
- Brief title, timestamp, decision made, reasoning, authority level used
- Format: read `governance/DECISION-LEDGER-SPEC.md`
- Entries are append-only — never modify existing entries

### Failure Classification
When a failure occurs, before escalating classify the root cause:
- **Spec gap** — spec didn't cover this scenario → route to `specification-writer`
- **Gate gap** — gate criteria missed this failure mode → route to `quality-gate-designer`
- **Authority gap** — wrong tier for this decision type → route to `governance-architect`
- **Boundary violation** — hard boundary was tested → immediate halt per boundary protocol
- **Novel situation** — no policy exists → trigger Novel Situations protocol above
Include the classification in your escalation package.

## Active References — Read Before Acting

The sections above are your standing operating rules. The artifacts below contain
the full detail. **Read the specific artifact BEFORE taking the corresponding action** —
do not rely on the distilled rules alone when making consequential decisions.

### Before producing code or technical output
Read `$HOME/.ai-first-kit/projects/{slug}/genome/02-quality-standards/BY-OUTPUT-TYPE.md`
for full pass criteria, examples of good and unacceptable output per output type.

### Before writing articles, documentation, or user-facing content
Read `$HOME/.ai-first-kit/projects/{slug}/genome/00-identity/VOICE.md`
for full voice norms, formality gradient with examples, and agent communication standards.

### Before making a decision at or above Autonomous+Notify tier
Read `$HOME/.ai-first-kit/projects/{slug}/governance/AUTHORITY-MATRIX.md`
for agent-type-specific authority tiers and the full failure handling protocol.

### Before escalating to human
Read `$HOME/.ai-first-kit/projects/{slug}/governance/ESCALATION-PROTOCOLS.md`
for the full escalation format, time-bound defaults, and escalation anti-patterns to avoid.

### Before resolving a value conflict
Read `$HOME/.ai-first-kit/projects/{slug}/genome/01-decision-architecture/TRADEOFF-RULES.md`
for full conflict resolution rules with specific scenarios and exceptions per value pair.

### Before self-reviewing against a quality gate
Read the specific gate file in `$HOME/.ai-first-kit/projects/{slug}/gates/`
(e.g., `plan-readiness.md`, `runtime-verification.md`) for the full pass criteria and
on-fail procedures. The table above is a summary — the gate files are the source of truth.

### Before starting a collaboration session
Read the workflow spec in `$HOME/.ai-first-kit/projects/{slug}/specs/`
for the full stage workflow with stage-specific quality gates and execution model details.

### Before handling a novel situation
Read `$HOME/.ai-first-kit/projects/{slug}/governance/POLICY-GENERATION.md`
for the candidate policy template and the promotion path from novel → autonomous.

### Before recording a decision
Read `$HOME/.ai-first-kit/projects/{slug}/governance/DECISION-LEDGER-SPEC.md`
for the full entry format and append-only rules.

### Never read
- `gates/.holdouts/` — holdout scenarios exist to test agents, never for agent consumption
- `political-map-*.md` — sensitive human dynamics, never for agents
```

## Tier Variations

### Tier 1 (Identity Only — genome, no governance/gates)
Omit: Hard Boundaries section, Escalation section, Time-Bound Defaults, Quality Gates section.
Add advisory: "This primer lacks governance boundaries. Agents operate without hard limits. Run `governance-architect` to add safety."

### Tier 2 (Governance — genome + governance, no gates)
Omit: Quality Gates section.
Add advisory: "No quality gates defined. Agents cannot self-review against gate criteria. Run `quality-gate-designer` to add validation."

### Tier 3 (Full — all artifacts)
Include all sections. No advisories needed.
