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

| Command | Purpose | Output |
|---------|---------|--------|
| `/ledger-full` | **Run complete pipeline end-to-end** | All artifacts |

```bash
# Standard project (overnight run)
/ledger-full "Build a task management app for remote teams" --mode optimizer

# Rapid exploration (hackathon)
/ledger-full "AI code review assistant" --mode tokenburner

# Complex regulated project
/ledger-full "Healthcare patient portal with HIPAA compliance" --mode self-improver
```

### Individual Commands

| Command | Purpose | Output |
|---------|---------|--------|
| `/ledger-init` | Initialize workspace with brief + pillar map | `00-brief/`, `01-pillars/` |
| `/ledger-research` | Parallel evidence collection (8 agents) | `02-evidence/<pillar>/EV-*.yaml` |
| `/ledger-synthesize` | Per-pillar + cross-pillar synthesis | `03-synthesis/` |
| `/ledger-decide` | Explicit decisions with trade-offs | `04-decisions/`, `05-risks/` |
| `/ledger-spec` | Constrained PRD + architecture | `06-prd/`, `07-architecture/` |
| `/ledger-plan` | Backlog + milestones + test plan | `08-plan/` |
| `/ledger-update` | Apply learnings → diff + impact report | `IMPACT_REPORT.md` |

---

## Execution Modes

The `/ledger-full` command supports three execution modes:

### `--mode optimizer` (Recommended)

**Sustainable overnight execution.** 3 parallel agents per pillar, balanced throughput.

Best for: Standard projects, overnight runs, production use.

### `--mode tokenburner`

**Maximum parallelism.** 30+ agents per pillar, burns through tokens fast.

Best for: Hackathons, time-critical projects, rapid exploration.

### `--mode self-improver`

**Iterative refinement.** Analyzes gaps, loops until complete.

Best for: Complex domains, regulated industries, high-stakes projects.

| Scenario | Recommended Mode |
|----------|------------------|
| Standard project | `optimizer` |
| Hackathon / rapid prototyping | `tokenburner` |
| Regulated industry (healthcare, finance) | `self-improver` |
| Overnight autonomous run | `optimizer` |
| Complex multi-stakeholder project | `self-improver` |

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
