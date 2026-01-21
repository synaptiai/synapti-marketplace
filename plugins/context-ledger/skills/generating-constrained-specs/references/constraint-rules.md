# Constraint Rules

Detailed rules for constrained spec generation in Context Ledger.

## Core Rule

> **No spec content without a DEC-* or EV-* reference.**

This is the fundamental rule. Every requirement, every architecture choice, every design decision must trace to explicit evidence or decisions.

## Citation Formats

### Section Headings

Every major section must cite relevant decisions:

```markdown
## 2. Target Users (DEC-scope-power-users-first)
```

Multiple decisions:
```markdown
## 5. Pricing (DEC-pricing-freemium, DEC-economics-margin-target)
```

### Paragraph Citations

Inline citations at end of relevant statement:

```markdown
Users will access via web browser only. (DEC-scope-web-only)
```

### Requirement Citations

Each requirement cites its justification:

```markdown
- REQ-001: System shall support offline mode (DEC-scope-power-users-first)
- REQ-002: Free tier limited to 100 requests/day (DEC-pricing-freemium)
```

### Evidence Citations

When evidence directly supports a claim:

```markdown
Based on user research showing 78% drop-off at team invitation
(EV-users-onboarding-dropoff), the invitation flow will be simplified.
(DEC-ux-simplified-onboarding)
```

## What Requires Citation

### PRD Citations Required

| Content Type | Citation Required | Format |
|--------------|-------------------|--------|
| Section heading | Yes | `## Section (DEC-*)` |
| User requirement | Yes | `REQ: ... (DEC-*)` |
| Feature description | Yes | `Feature ... (DEC-*)` |
| Scope inclusion | Yes | `Includes X (DEC-scope-*)` |
| Scope exclusion | Yes | `Excludes Y (DEC-scope-*)` |
| User persona | Yes | `Persona ... (DEC-scope-*)` |
| Pricing tier | Yes | `Tier ... (DEC-pricing-*)` |
| Success metric | Yes | `Metric ... (DEC-*)` |

### Architecture Citations Required

| Content Type | Citation Required | Format |
|--------------|-------------------|--------|
| Section heading | Yes | `## Section (DEC-*)` |
| Technology choice | Yes | `Using X (DEC-tech-*)` |
| Data model entity | Yes | `Entity ... (DEC-*)` |
| API endpoint | Yes | `Endpoint ... (DEC-*)` |
| Security measure | Yes | `Security ... (DEC-*)` |
| Performance target | Yes | `Target ... (DEC-*)` |
| Infrastructure choice | Yes | `Using X (DEC-tech-*)` |

## What Does NOT Require Citation

### Definitional Content

Standard definitions don't need citations:

```markdown
### 1.1 Document Purpose
This document describes the technical architecture for [Product].
```

### Meta Content

Document metadata doesn't need citations:

```markdown
**Version:** 1.0
**Date:** 2026-01-21
```

### Appendices

Reference lists are citations themselves:

```markdown
## Appendix A: Decision Reference
| ID | Decision |
| DEC-* | ... |
```

## Constraint Violations

### Types of Violations

| Violation | Description | Severity |
|-----------|-------------|----------|
| Missing section citation | Section heading lacks DEC-* | Blocking |
| Missing requirement citation | Requirement lacks DEC-* | Blocking |
| Orphaned feature | Feature not supported by any decision | Blocking |
| Conflicting citation | Content contradicts cited decision | Blocking |
| Stale citation | Cited DEC-* is rejected/obsolete | Warning |
| Weak citation | Only 1 decision for major section | Warning |

### Handling Violations

**Blocking violations:**
1. Cannot generate spec section
2. Must either:
   - Create new decision to support content
   - Remove content from spec
   - Link to existing decision

**Warning violations:**
1. Spec can generate but flagged
2. Review recommended
3. May indicate missing decisions

## Validation Rules

### PRD Validation

```
For each section:
  ✓ Has DEC-* in heading
  ✓ Each requirement cites DEC-*
  ✓ Cited decisions exist in DECISIONS.yaml
  ✓ Cited decisions are not rejected
  ✓ Content aligns with cited decision
```

### Architecture Validation

```
For each section:
  ✓ Has DEC-* in heading
  ✓ Each tech choice cites DEC-*
  ✓ Cited decisions exist in DECISIONS.yaml
  ✓ Technical details align with decision
```

## Examples

### Valid PRD Section

```markdown
## 4. MVP Scope (DEC-scope-power-users-first, DEC-scope-web-only)

The MVP will focus on power users within SMB organizations who manage
complex workflows. (DEC-scope-power-users-first)

### 4.1 Included Features

- Advanced workflow builder (DEC-scope-power-users-first)
- Real-time collaboration (DEC-scope-power-users-first)
- Web-based interface (DEC-scope-web-only)

### 4.2 Excluded Features

- Mobile application (DEC-scope-web-only)
- Enterprise SSO (DEC-scope-power-users-first - SMB focus)
- White-labeling (DEC-scope-mvp-minimal)
```

### Invalid PRD Section

```markdown
## 4. MVP Scope  ← VIOLATION: No DEC-* citation

The MVP will include the following features:

- Advanced workflow builder  ← VIOLATION: No citation
- Mobile app  ← VIOLATION: Contradicts DEC-scope-web-only
- AI-powered suggestions  ← VIOLATION: No decision supports this
```

### Valid Architecture Section

```markdown
## 3. Data Architecture (DEC-tech-postgres-primary)

### 3.1 Database Selection

PostgreSQL will serve as the primary database. (DEC-tech-postgres-primary)

This choice supports:
- Complex querying for workflow data (DEC-scope-power-users-first)
- ACID compliance for collaboration (DEC-tech-reliability)
- Full-text search capabilities (DEC-scope-power-users-first)
```

### Invalid Architecture Section

```markdown
## 3. Data Architecture  ← VIOLATION: No DEC-* citation

We'll use MongoDB because it's popular.  ← VIOLATION: No citation
                                         ← VIOLATION: Contradicts DEC-tech-postgres-primary
```

## Edge Cases

### Multiple Valid Decisions

When multiple decisions support content, cite all:

```markdown
## 5. Pricing (DEC-pricing-freemium, DEC-pricing-usage-based, DEC-economics-margin-target)
```

### Decision Chains

When a decision references another:

```markdown
Advanced features in paid tier (DEC-pricing-freemium, per DEC-scope-power-users-first)
```

### Provisional Decisions

Content based on provisional decisions should be flagged:

```markdown
## 6. Enterprise Features (DEC-scope-enterprise-later [provisional])

Note: This section is based on a provisional decision and may change.
```

## Quality Metrics

### Coverage Metrics

| Metric | Target |
|--------|--------|
| Sections with citations | 100% |
| Requirements with citations | 100% |
| Unique decisions referenced | ≥50% of accepted decisions |
| Average citations per section | ≥2 |

### Traceability Matrix

Generate traceability showing:
- Each decision → PRD sections that cite it
- Each decision → Architecture sections that cite it
- Decisions not cited (may be orphaned)
