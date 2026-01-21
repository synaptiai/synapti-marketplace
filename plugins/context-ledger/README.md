# Context Ledger - Evidence-Based Product Development

A Claude Code plugin for structured product development with traceable evidence, explicit decisions, and constrained spec generation.

---

## Why Context Ledger?

### The Problem with Traditional Product Planning

Most product development starts with vibes and ends with specs that nobody trusts:

- **Specs drift from reality** — PRDs reference decisions that were never formally made
- **Assumptions hide in prose** — Trade-offs buried in paragraph 47 of a 200-page doc
- **Evidence disappears** — "Studies show..." but which studies? From when?
- **Updates break everything** — New learnings require manual diff of every downstream doc

### What Context Ledger Does Differently

Context Ledger asks: **"Can you trace every spec requirement back to evidence and an explicit decision?"**

This constraint-based approach:
- **Forces explicit decisions** — No spec section without a `DEC-*` reference
- **Traces to evidence** — Every decision cites `EV-*` evidence objects
- **Surfaces trade-offs** — Decisions must list wins, loses, and created risks
- **Produces impact reports** — Updates show what downstream artifacts need regeneration

### Who Benefits

| Role | How Context Ledger Helps |
|------|--------------------------|
| **Product Managers** | Evidence-backed PRDs with explicit trade-off documentation |
| **Engineers** | Architecture decisions with clear reasoning and risk awareness |
| **Executives** | Decision audits showing how conclusions were reached |
| **Teams** | Shared understanding through structured artifacts, not tribal knowledge |

---

## Design Philosophy

### Auditability Over Convenience

Every claim traces back to its source. If you can't cite the evidence, it doesn't go in the spec.

### Explicit Decisions Over Implicit Assumptions

Most product failures stem from hidden assumptions. Context Ledger makes trade-offs visible:
- What alternatives were considered?
- What are we giving up?
- What risks does this create?

### Constrained Generation Over Free-Form Writing

Specs cannot be generated without meeting quality gates:
- Evidence gate: ≥5 evidence objects per pillar before synthesis
- Decision gate: DECISIONS.yaml must exist before spec generation
- Spec gate: Every PRD section must reference at least one `DEC-*`

### Impact-Aware Updates

Changes produce diffs, not silent rewrites. Every update includes an impact report showing what must be regenerated.

---

## The Pipeline

### Phase 1 — Context Build (PARALLEL)
Generate pillar map, collect evidence in parallel across 8 pillars.

**Output**: Evidence Objects in `02-evidence/...`

### Phase 2 — Synthesis (LAYERED)
Per-pillar synthesis → cross-pillar synthesis → decisions + risks.

**Output**:
- `03-synthesis/...`
- `04-decisions/DECISIONS.yaml`
- `05-risks/RISKS.yaml`

### Phase 3 — Build (CONSTRAINED)
Generate PRD, architecture, plan — only from decisions + evidence.

**Output**:
- `06-prd/PRD.md`
- `07-architecture/ARCHITECTURE.md`
- `08-plan/PLAN.md`

---

## Installation

```bash
# Add the marketplace (one-time setup)
claude plugin marketplace add synaptiai/synapti-marketplace

# Install the plugin
claude plugin install context-ledger
```

---

## Commands

### Full Pipeline (Recommended)

#### `/ledger-full <brief>`

Run the complete Context Ledger pipeline from brief to implementation plan in one command.

```bash
# Standard overnight run
/ledger-full "Build a task management app for remote teams" --mode optimizer

# With self-improvement loops
/ledger-full "Task management app" --mode optimizer --self-improve

# Maximum speed hackathon
/ledger-full "AI code review assistant" --mode tokenburner

# Fully autonomous (walk away overnight)
/ledger-full "Healthcare portal with HIPAA" --mode ralph --max-iterations 50

# Ralph + self-improve (maximum autonomy)
/ledger-full "Complex fintech app" --mode ralph --self-improve --max-iterations 100
```

**What's Good About /ledger-full:**
1. **Single command, complete output** — Goes from idea to implementation plan without manual phase transitions
2. **Mode flexibility** — Choose between sustainable (`optimizer`), fast (`tokenburner`), or autonomous (`ralph`) execution
3. **Self-improvement loops** — Optional `--self-improve` flag fills evidence gaps and resolves contradictions automatically
4. **Quality gate enforcement** — Cannot skip evidence, decision, or spec gates; ensures receipts at every stage
5. **Walk-away capable** — Ralph mode with stop hooks enables overnight autonomous execution
6. **Minimal interaction** — Only asks questions during decision phase; everything else runs autonomously

### Individual Commands

#### `/ledger-init <brief>`

Initialize a Context Ledger workspace with structured brief and pillar configuration.

```bash
/ledger-init Build a task management app for remote software teams with Slack integration
```

**What's Good About /ledger-init:**
1. **Structured brief parsing** — Extracts goals, constraints, and target users from free-form input
2. **Pillar prioritization** — Identifies which research areas matter most for your specific project
3. **Directory scaffold** — Creates the complete 10-folder workspace structure automatically
4. **Validation gates** — Won't proceed if brief lacks goals or constraints, ensuring quality from the start

---

#### `/ledger-research`

Parallel evidence collection across 8 research pillars (market, users, tech, competitors, design, legal, ops, economics).

```bash
/ledger-research
/ledger-research --pillars market,users,competitors
```

**What's Good About /ledger-research:**
1. **True parallelism** — 8 agents research simultaneously, dramatically faster than sequential research
2. **Atomic evidence objects** — Each finding is structured YAML with confidence scores and assumptions
3. **Semantic IDs** — Evidence gets readable IDs like `EV-market-pricing-smb-wtp` that humans can reference
4. **Quality gates** — Enforces minimum 5 evidence objects per pillar before proceeding
5. **Source traceability** — Every claim links to its source with retrieval date

---

#### `/ledger-synthesize`

Transform raw evidence into pillar syntheses, then cross-synthesize to identify conflicts and emergent insights.

```bash
/ledger-synthesize
```

**What's Good About /ledger-synthesize:**
1. **Two-layer synthesis** — Per-pillar patterns first, then cross-pillar connections and conflicts
2. **Contradiction surfacing** — Explicitly identifies where evidence disagrees, forcing resolution
3. **Decision candidates** — Generates preliminary decisions from synthesis, not from vibes
4. **Pattern recognition** — Identifies themes across evidence that individual pieces don't reveal

---

#### `/ledger-decide`

Make explicit decisions with documented alternatives, trade-offs, and risk implications.

```bash
/ledger-decide
```

**What's Good About /ledger-decide:**
1. **Forced alternatives** — Every decision must document what options were considered and rejected
2. **Trade-off documentation** — Explicit wins and loses, not just the happy path
3. **Risk linkage** — Decisions automatically create risk entries when they create new vulnerabilities
4. **Evidence requirements** — Each decision must cite minimum 2 evidence IDs, preventing gut-feel choices
5. **Interactive workflow** — Presents decisions with evidence for user approval, not autonomous guessing

---

#### `/ledger-spec`

Generate constrained PRD and architecture documents where every section cites decisions.

```bash
/ledger-spec
```

**What's Good About /ledger-spec:**
1. **Constraint enforcement** — PRD sections cannot exist without DEC-* references; no vibes allowed
2. **Automatic validation** — Spec gate checks that all sections cite decisions before completing
3. **Risk cross-referencing** — Architecture sections reference relevant RISK-* entries
4. **Coverage tracking** — Reports which decisions are covered and which need spec sections
5. **No drift** — Specs stay anchored to decisions, which stay anchored to evidence

---

#### `/ledger-plan`

Generate implementation plan with backlog, milestones, and test plan linked to decisions and risks.

```bash
/ledger-plan
```

**What's Good About /ledger-plan:**
1. **Decision-linked items** — Every backlog item traces to the decisions that require it
2. **Risk-aware sequencing** — High-risk items get earlier attention and explicit mitigations
3. **Test plan generation** — Acceptance criteria derived from decisions, not invented
4. **Milestone structure** — Logical groupings based on decision dependencies

---

#### `/ledger-update <new-evidence>`

Apply new learnings and generate impact report showing what needs regeneration.

```bash
/ledger-update "User interviews revealed onboarding completion rate of 23%"
```

**What's Good About /ledger-update:**
1. **Impact analysis** — Shows exactly which decisions, specs, and plans are affected by new evidence
2. **Diff generation** — Documents what changed, not silent rewrites
3. **Regeneration guidance** — Identifies which artifacts need updates vs. which remain valid
4. **Audit trail** — Maintains history of how understanding evolved over time

---

## Execution Modes

The `/ledger-full` command supports three modes + one flag:

### `--mode optimizer`

**Sustainable execution.** 3 agents per pillar (24 total), balanced throughput.

Best for: Standard projects, overnight runs, production use.

### `--mode tokenburner`

**Maximum parallelism.** 30+ agents per pillar (240+ total), burns through tokens fast.

Best for: Hackathons, time-critical projects, rapid exploration.

### `--mode ralph`

**Fully autonomous execution** using Ralph Loop's stop hook mechanism. Same prompt re-fed on each exit until `<promise>LEDGER_COMPLETE</promise>` is output.

Best for: Walk-away overnight runs, complex autonomous projects.

### `--self-improve` (Flag)

**Can combine with any mode.** Enables within-pipeline gap analysis loops:
- Analyzes research for missing evidence
- Checks synthesis for unresolved contradictions
- Loops back when gaps found

| Scenario | Recommended |
|----------|-------------|
| Standard project | `--mode optimizer` |
| Hackathon / rapid prototyping | `--mode tokenburner` |
| Walk-away overnight run | `--mode ralph --max-iterations 50` |
| Complex regulated project | `--mode ralph --self-improve --max-iterations 100` |
| High-stakes production planning | `--mode optimizer --self-improve` |

---

## Semantic ID Scheme

All artifacts use self-describing semantic IDs with optional `-2`, `-3` disambiguators.

### Why Semantic IDs
- **Readable + speakable** in meetings and docs
- **Predictable structure** so humans can guess IDs
- **Still unique** with `-n` suffix when collisions happen
- **Max 40 chars** after prefix

### ID Formats

| Type | Format | Examples |
|------|--------|----------|
| Evidence | `EV-<pillar>-<topic>-<descriptor>[-n]` | `EV-market-pricing-smb-wtp`, `EV-users-onboarding-dropoff` |
| Decision | `DEC-<area>-<decision>[-n]` | `DEC-scope-power-users-first`, `DEC-ux-single-summary-box` |
| Risk | `RISK-<area>-<risk>[-n]` | `RISK-retention-expert-depth-churn`, `RISK-legal-gdpr-processing-basis` |

---

## Ledger Workspace Structure

Default: `~/project/ledger/` (overridable)

```
ledger/
├── 00-brief/           # 5-sentence brief + goals + constraints
├── 01-pillars/         # pillar map, scope, priorities
├── 02-evidence/        # Evidence Objects (per pillar)
│   ├── market/
│   ├── users/
│   ├── tech/
│   ├── competitors/
│   ├── design/
│   ├── legal/
│   ├── ops/
│   └── economics/
├── 03-synthesis/       # per-pillar syntheses + CROSS-SYNTHESIS.md
├── 04-decisions/       # DECISIONS.yaml
├── 05-risks/           # RISKS.yaml
├── 06-prd/             # PRD.md
├── 07-architecture/    # ARCHITECTURE.md
├── 08-plan/            # PLAN.md
├── 09-brand/           # personas, tone, UI refs, tokens
└── 10-gtm-ops/         # pricing, unit economics, launch checklist
```

---

## Evidence Objects

Evidence objects force atomic, traceable research output.

### Schema
```yaml
id: EV-market-pricing-smb-wtp
pillar: market
source:
  type: url | pdf | interview | internal-doc | experiment | dataset
  ref: "https://..."
  retrieved_at: 2026-01-21
claim: "SMB segment willingness-to-pay peaks at $29/mo."
quote: "<short excerpt or summary>"
confidence: 0.0-1.0
assumptions:
  - "Survey sample excludes enterprise accounts"
notes: "Why it matters, how it may fail, what to verify next."
tags:
  - pricing
  - smb
```

### Quality Rules
- Claims must be **falsifiable** (not vibes)
- **Confidence is mandatory** (even if subjective)
- **Assumptions must be listed**
- **ID auto-suggested** from claim text

---

## Decision Ledger

The heart of the system. Every decision must document:

### Schema
```yaml
- id: DEC-scope-power-users-first
  decision: "Target power users before SMB"
  status: accepted | provisional | rejected
  owner: "user"
  created_at: 2026-01-21
  alternatives:
    - "SMB-first"
    - "Enterprise-first"
  evidence:
    - EV-market-pricing-smb-wtp
    - EV-users-power-user-retention
  tradeoffs:
    wins:
      - "Faster iteration cycles"
      - "Lower sales friction"
    loses:
      - "Lower initial ARPA"
      - "Potentially higher churn"
  risks:
    - RISK-retention-expert-depth-churn
  implications:
    - "MVP UX must optimize for expert workflows"
```

---

## Quality Gates

| Gate | Requirement |
|------|-------------|
| **Evidence gate** | Each pillar needs ≥5 Evidence Objects before synthesis |
| **Decision gate** | No spec generation until DECISIONS.yaml exists with ≥2 evidence IDs per decision |
| **Spec gate** | No PRD/architecture sections without DEC-* references |

---

## Impact Reports

Updates produce structured impact analysis:

```markdown
# Impact Report

## What Changed
- Evidence added/updated:
  - EV-market-pricing-enterprise-wtp (new)
  - EV-users-onboarding-dropoff (updated confidence: 0.7 → 0.9)
- Decisions updated:
  - DEC-scope-power-users-first (status: provisional → accepted)

## What Is Affected
- PRD sections: 2, 4
- Architecture sections: Data model
- Plan items: Epic 1

## Recommended Actions
- [ ] Regenerate PRD section 2
- [ ] Review RISK-retention-expert-depth-churn mitigations
```

---

## Constraint Enforcement

### Citation Format

Specs must cite decisions using parseable references:

**Section headings:**
```markdown
## 2. MVP scope (DEC-scope-power-users-first, DEC-ux-single-summary-box)
```

**Inline:**
```markdown
We will prioritize workflow X because it reduces drop-off. (DEC-scope-power-users-first)
```

---

## What Makes This Different

Most "context" tooling is a dump of notes.

**Context Ledger is:**
- Structured evidence with confidence scores
- Explicit decisions with trade-offs and alternatives
- Explicit risks with triggers and mitigations
- Constrained generation (specs must cite decisions)
- Impact-aware updates (changes produce diffs)

**It's a lightweight system for building products with receipts.**

---

## License

MIT License - See LICENSE file for details.

## Author

Daniel Bentes

## Repository

https://github.com/synaptiai/synapti-marketplace
