# PRD Template

Template for `06-prd/PRD.md` - Product Requirements Document constrained by decisions.

---

# Product Requirements Document

**Product:** {name}
**Version:** {version}
**Generated:** {date}
**Decisions Referenced:** {count}

---

## Document Constraint

> **Every section in this document cites the decisions that justify it.**
> Requirements without decision references are not valid.

---

## 1. Executive Summary (DEC-scope-*, DEC-pricing-*)

{2-3 paragraph summary of what we're building and why}

**Key Decisions Driving This Product:**
- {DEC-id}: {decision summary}
- {DEC-id}: {decision summary}
- {DEC-id}: {decision summary}

---

## 2. Target Users (DEC-scope-*)

### 2.1 Primary Users
{Who the product is for, constrained by scope decisions}
(DEC-scope-*)

### 2.2 User Personas

#### Persona: {Name} (DEC-scope-*)
- **Role:** {role}
- **Goals:** {goals}
- **Pain Points:** {pain points from evidence}
- **Success Criteria:** {how they measure success}

(Supported by: EV-users-*)

#### Persona: {Name} (DEC-scope-*)
{Continue pattern}

### 2.3 Non-Users
{Explicitly who this is NOT for}
(DEC-scope-*)

---

## 3. Product Goals (DEC-scope-*, DEC-pricing-*, DEC-gtm-*)

### 3.1 Primary Goals

| Goal | Metric | Target | Decision |
|------|--------|--------|----------|
| {goal} | {metric} | {target} | DEC-* |
| {goal} | {metric} | {target} | DEC-* |
| {goal} | {metric} | {target} | DEC-* |

### 3.2 Success Criteria

{What success looks like, tied to decisions}
(DEC-*)

---

## 4. Scope (DEC-scope-*)

### 4.1 In Scope (MVP)

| Feature Area | Description | Decision |
|--------------|-------------|----------|
| {area} | {what's included} | DEC-scope-* |
| {area} | {what's included} | DEC-scope-* |

### 4.2 Out of Scope

| Exclusion | Rationale | Decision |
|-----------|-----------|----------|
| {exclusion} | {why excluded} | DEC-scope-* |
| {exclusion} | {why excluded} | DEC-scope-* |

### 4.3 Future Scope

{What might come later, but explicitly not now}
(DEC-scope-*)

---

## 5. Functional Requirements (DEC-*)

### 5.1 Core Functionality

#### 5.1.1 {Feature Name} (DEC-*)

**Description:** {what it does}

**User Story:**
As a {persona}, I want to {action} so that {outcome}.

**Requirements:**
- REQ-001: {requirement} (DEC-*)
- REQ-002: {requirement} (DEC-*)
- REQ-003: {requirement} (DEC-*)

**Acceptance Criteria:**
- [ ] {criteria}
- [ ] {criteria}

**Risk Note:** {if relevant RISK-* applies}

#### 5.1.2 {Feature Name} (DEC-*)
{Continue pattern for each feature}

### 5.2 Secondary Functionality

{Lower priority features, still constrained}

---

## 6. Non-Functional Requirements (DEC-tech-*, DEC-ops-*)

### 6.1 Performance (DEC-tech-*)

| Metric | Requirement | Decision |
|--------|-------------|----------|
| Page load | <2 seconds | DEC-tech-* |
| API response | <500ms p95 | DEC-tech-* |

### 6.2 Scalability (DEC-tech-*)

{Scalability requirements tied to technical decisions}

### 6.3 Security (DEC-tech-*, DEC-legal-*)

{Security requirements tied to decisions}

### 6.4 Availability (DEC-ops-*)

{Uptime and reliability requirements}

---

## 7. UX Requirements (DEC-ux-*, DEC-design-*)

### 7.1 Design Principles (DEC-ux-*)

{Core UX principles driven by decisions}

### 7.2 Key User Flows

#### Flow: {Name} (DEC-ux-*)
{Description of flow tied to UX decisions}

### 7.3 Accessibility (DEC-design-*)

{Accessibility requirements}

---

## 8. Pricing and Packaging (DEC-pricing-*)

### 8.1 Pricing Model (DEC-pricing-*)

{Pricing structure tied to pricing decisions}

### 8.2 Tiers

| Tier | Price | Features | Decision |
|------|-------|----------|----------|
| {tier} | {price} | {features} | DEC-pricing-* |

---

## 9. Dependencies and Constraints (DEC-tech-*, DEC-legal-*)

### 9.1 Technical Dependencies

| Dependency | Reason | Decision |
|------------|--------|----------|
| {dependency} | {why needed} | DEC-tech-* |

### 9.2 External Constraints

{Constraints from legal, compliance, etc.}
(DEC-legal-*)

---

## 10. Risks (RISK-*)

### 10.1 Product Risks

| Risk | Severity | Mitigation | Reference |
|------|----------|------------|-----------|
| {risk} | {level} | {mitigation} | RISK-* |

### 10.2 Risk Dependencies

{How risks affect requirements}

---

## 11. Open Questions

{Questions that need resolution - should eventually become decisions}

| Question | Blocking | Related Decision |
|----------|----------|------------------|
| {question} | {what it blocks} | DEC-* (potential) |

---

## Appendix A: Decision Reference

All decisions referenced in this document:

| ID | Decision | Status |
|----|----------|--------|
| DEC-* | {decision} | {status} |

---

## Appendix B: Evidence Reference

Key evidence supporting requirements:

| ID | Claim | Confidence |
|----|-------|------------|
| EV-* | {claim} | {confidence} |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | {date} | Initial generation | Context Ledger |
