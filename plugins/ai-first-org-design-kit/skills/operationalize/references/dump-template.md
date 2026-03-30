# Full Artifact Dump Template

The dump concatenates all organizational design artifacts into a single document.
Unlike the primer (which distills), the dump preserves full content.

This template is used as a fallback guide when the `dump-artifacts.sh` script
is not available. In normal operation, the script handles concatenation.

## Structure

```markdown
# Organizational Design — {Project Name}
<!-- Full artifact dump generated: {YYYY-MM-DD-HHMM} -->
<!-- Source: $HOME/.ai-first-kit/projects/{slug}/ -->
<!-- This is a reference document, not agent instructions. -->
<!-- For agent consumption, use AGENT-PRIMER.md instead. -->
<!-- Sections marked with CONFIDENTIAL contain sensitive data. -->
```

## Concatenation Order

Each section uses H2 headers. Each file within a section uses H3 with its source path.
Sections are skipped if no artifacts exist for that category.

| # | Section | Source | Confidential |
|---|---------|--------|-------------|
| 1 | Identity | `genome/00-identity/MISSION.md`, `VALUES.md`, `VOICE.md` | No |
| 2 | Decision Architecture | `genome/01-decision-architecture/AUTHORITY-MATRIX.md`, `TRADEOFF-RULES.md` | No |
| 3 | Quality Standards | `genome/02-quality-standards/BY-OUTPUT-TYPE.md`, `ANTI-PATTERNS.md` | No |
| 4 | Governance | `governance/AUTHORITY-MATRIX.md`, `HARD-BOUNDARIES.md`, `ESCALATION-PROTOCOLS.md`, `POLICY-GENERATION.md`, `DECISION-LEDGER-SPEC.md`, `LEARNING-LOOP.md` | No |
| 5 | Specifications | `specs/*.md` (all spec files) | No |
| 6 | Quality Gates | `gates/INDEX.md` + `gates/*.md` (excluding holdouts) | No |
| 7 | Quality Gate Holdouts | `gates/.holdouts/*.md` | **Yes — SKIP by default. Only include if user explicitly requests confidential sections.** |
| 8 | Roles | `roles-*.md` (most recent) | No |
| 9 | Political Map | `political-map-*.md` (most recent, if exists) | **Yes — SKIP by default. Only include if user explicitly requests confidential sections.** |
| 10 | Coordination Audit | `audit-*.md` (most recent, if exists) | No |
| 11 | Agent Primer | `AGENT-PRIMER.md` (if exists) | No |

## Confidential Section Format

Sensitive sections include a banner before each file:

```markdown
> **⚠️ CONFIDENTIAL** — This section contains sensitive organizational data.
> Do not share externally or expose to agents.
```

## File Separator

Each file is followed by a horizontal rule (`---`) for clear visual separation.
