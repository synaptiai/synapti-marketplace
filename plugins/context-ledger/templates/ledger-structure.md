# Ledger Workspace Structure

This template defines the standard directory structure for a Context Ledger workspace.

## Directory Tree

```
ledger/
├── 00-brief/
│   └── BRIEF.md                    # 5-sentence brief + goals + constraints
├── 01-pillars/
│   └── PILLARS.md                  # pillar map, scope, priorities
├── 02-evidence/
│   ├── market/                     # Market research evidence
│   │   └── EV-market-*.yaml
│   ├── users/                      # User research evidence
│   │   └── EV-users-*.yaml
│   ├── tech/                       # Technical research evidence
│   │   └── EV-tech-*.yaml
│   ├── competitors/                # Competitive analysis evidence
│   │   └── EV-competitors-*.yaml
│   ├── design/                     # Design research evidence
│   │   └── EV-design-*.yaml
│   ├── legal/                      # Legal/compliance evidence
│   │   └── EV-legal-*.yaml
│   ├── ops/                        # Operations research evidence
│   │   └── EV-ops-*.yaml
│   └── economics/                  # Economic/business model evidence
│       └── EV-economics-*.yaml
├── 03-synthesis/
│   ├── SYN-market.md               # Market pillar synthesis
│   ├── SYN-users.md                # Users pillar synthesis
│   ├── SYN-tech.md                 # Tech pillar synthesis
│   ├── SYN-competitors.md          # Competitors pillar synthesis
│   ├── SYN-design.md               # Design pillar synthesis
│   ├── SYN-legal.md                # Legal pillar synthesis
│   ├── SYN-ops.md                  # Ops pillar synthesis
│   ├── SYN-economics.md            # Economics pillar synthesis
│   └── CROSS-SYNTHESIS.md          # Cross-pillar synthesis
├── 04-decisions/
│   └── DECISIONS.yaml              # Decision ledger
├── 05-risks/
│   └── RISKS.yaml                  # Risk ledger
├── 06-prd/
│   └── PRD.md                      # Product Requirements Document
├── 07-architecture/
│   └── ARCHITECTURE.md             # Technical Architecture Document
├── 08-plan/
│   └── PLAN.md                     # Implementation plan + backlog
├── 09-brand/
│   ├── PERSONAS.md                 # User personas
│   ├── TONE.md                     # Brand voice and tone
│   ├── UI-REFS.md                  # UI reference materials
│   └── TOKENS.md                   # Design tokens
└── 10-gtm-ops/
    ├── PRICING.md                  # Pricing strategy
    ├── UNIT-ECONOMICS.md           # Unit economics analysis
    └── LAUNCH-CHECKLIST.md         # Launch readiness checklist
```

## Directory Purposes

### 00-brief
The starting point. Contains the project brief that scopes everything downstream.

**Must contain:**
- 5-sentence maximum project description
- Explicit goals (what success looks like)
- Explicit constraints (what's out of scope)

### 01-pillars
Defines which research pillars are active and their relative priorities.

**Must contain:**
- List of active pillars (default: all 8)
- Priority ranking (which pillars matter most)
- Any pillar-specific scope notes

### 02-evidence
Raw research artifacts. Each pillar gets its own subdirectory.

**File format:** YAML
**Naming:** `EV-<pillar>-<topic>-<descriptor>.yaml`

### 03-synthesis
Processed insights from evidence. One synthesis doc per pillar, plus cross-pillar.

**File format:** Markdown
**Naming:** `SYN-<pillar>.md` or `CROSS-SYNTHESIS.md`

### 04-decisions
The decision ledger. Single YAML file containing all explicit decisions.

**File format:** YAML
**Required:** Before any spec generation

### 05-risks
The risk ledger. Single YAML file containing all identified risks.

**File format:** YAML
**Linked to:** Decisions that create each risk

### 06-prd
Product Requirements Document, constrained by decisions.

**File format:** Markdown
**Constraint:** Every section must cite `DEC-*` references

### 07-architecture
Technical Architecture Document, constrained by decisions.

**File format:** Markdown
**Constraint:** Every section must cite `DEC-*` references

### 08-plan
Implementation plan including backlog, milestones, and test plan.

**File format:** Markdown
**Constraint:** Items trace to decisions and risks

### 09-brand
Brand and design assets. Optional but recommended.

**Contents:** Personas, tone guidelines, UI references, design tokens

### 10-gtm-ops
Go-to-market and operations artifacts. Optional but recommended.

**Contents:** Pricing, unit economics, launch checklist

## Creating the Structure

Use `/ledger-init` to create this structure automatically:

```bash
/ledger-init "Build a task management app for remote teams"
```

This creates all directories and initializes:
- `00-brief/BRIEF.md` with parsed brief
- `01-pillars/PILLARS.md` with default pillar configuration

## Overriding the Default Path

By default, the ledger is created at `./ledger/` in the current working directory.

To specify a different location:

```bash
/ledger-init --path ~/projects/my-app/ledger "Build a task management app"
```
