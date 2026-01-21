# Architecture Template

Template for `07-architecture/ARCHITECTURE.md` - Technical Architecture Document constrained by decisions.

---

# Technical Architecture Document

**Product:** {name}
**Version:** {version}
**Generated:** {date}
**Decisions Referenced:** {count}

---

## Document Constraint

> **Every architectural choice in this document cites the decisions that justify it.**
> Technical decisions without DEC-* references are not valid.

---

## 1. Architecture Overview (DEC-tech-*, DEC-scope-*)

### 1.1 Executive Summary

{High-level architecture summary tied to key decisions}

**Key Technical Decisions:**
- {DEC-id}: {decision summary}
- {DEC-id}: {decision summary}
- {DEC-id}: {decision summary}

### 1.2 Architecture Diagram

```
{ASCII or description of architecture}
```

### 1.3 Design Principles (DEC-tech-*)

| Principle | Rationale | Decision |
|-----------|-----------|----------|
| {principle} | {why} | DEC-tech-* |
| {principle} | {why} | DEC-tech-* |

---

## 2. System Components (DEC-tech-*)

### 2.1 Component Overview

| Component | Purpose | Technology | Decision |
|-----------|---------|------------|----------|
| {component} | {purpose} | {tech} | DEC-tech-* |
| {component} | {purpose} | {tech} | DEC-tech-* |

### 2.2 Frontend (DEC-tech-*, DEC-ux-*)

**Technology:** {framework/stack}
(DEC-tech-frontend-*)

**Architecture:**
{Frontend architecture description}

**Key Decisions:**
- {DEC-id}: {impact on frontend}

### 2.3 Backend (DEC-tech-*)

**Technology:** {framework/stack}
(DEC-tech-backend-*)

**Architecture:**
{Backend architecture description}

**Key Decisions:**
- {DEC-id}: {impact on backend}

### 2.4 Infrastructure (DEC-tech-*, DEC-ops-*)

**Platform:** {cloud provider/setup}
(DEC-tech-infrastructure-*)

**Components:**
{Infrastructure component list}

---

## 3. Data Architecture (DEC-tech-*, DEC-scope-*)

### 3.1 Data Model Overview (DEC-tech-*)

{High-level data model tied to scope decisions}

### 3.2 Core Entities

#### Entity: {Name} (DEC-scope-*, DEC-tech-*)

```
{Entity schema or description}
```

**Rationale:** {Why this structure, tied to decisions}

### 3.3 Database Selection (DEC-tech-*)

**Primary Database:** {database}
(DEC-tech-database-*)

| Requirement | Solution | Decision |
|-------------|----------|----------|
| {requirement} | {how db meets it} | DEC-tech-* |

### 3.4 Data Flow

```
{Data flow diagram or description}
```

---

## 4. API Design (DEC-tech-*, DEC-scope-*)

### 4.1 API Overview (DEC-tech-*)

**Style:** {REST/GraphQL/gRPC}
(DEC-tech-api-*)

### 4.2 Core Endpoints

| Endpoint | Purpose | Decision |
|----------|---------|----------|
| {endpoint} | {purpose} | DEC-* |

### 4.3 Authentication (DEC-tech-*, DEC-legal-*)

**Method:** {auth method}
(DEC-tech-auth-*, DEC-legal-*)

---

## 5. Integration Architecture (DEC-tech-*, DEC-scope-*)

### 5.1 External Services

| Service | Purpose | Decision |
|---------|---------|----------|
| {service} | {why needed} | DEC-tech-* |

### 5.2 Third-Party APIs

{External API integrations tied to decisions}

### 5.3 AI/ML Components (DEC-tech-*)

**LLM Provider:** {provider}
(DEC-tech-llm-*)

**Usage:**
{How AI is used, costs, constraints}

**Cost Considerations:** (EV-tech-llm-cost-*)
{Cost model tied to evidence and decisions}

---

## 6. Security Architecture (DEC-tech-*, DEC-legal-*)

### 6.1 Security Model (DEC-tech-security-*)

{Security architecture tied to decisions}

### 6.2 Data Protection (DEC-legal-*)

**Encryption:**
- At rest: {method} (DEC-tech-*)
- In transit: {method} (DEC-tech-*)

**Access Control:**
{Access control model}

### 6.3 Compliance (DEC-legal-*)

| Requirement | Implementation | Decision |
|-------------|----------------|----------|
| GDPR | {how met} | DEC-legal-* |
| {other} | {how met} | DEC-legal-* |

---

## 7. Scalability and Performance (DEC-tech-*, DEC-ops-*)

### 7.1 Scaling Strategy (DEC-tech-*)

{How system scales, tied to technical decisions}

### 7.2 Performance Targets

| Metric | Target | Architecture Impact | Decision |
|--------|--------|---------------------|----------|
| {metric} | {target} | {how achieved} | DEC-tech-* |

### 7.3 Caching Strategy (DEC-tech-*)

{Caching approach tied to decisions}

---

## 8. Deployment Architecture (DEC-tech-*, DEC-ops-*)

### 8.1 Deployment Model (DEC-ops-*)

**Strategy:** {deployment strategy}
(DEC-ops-deployment-*)

### 8.2 Environments

| Environment | Purpose | Decision |
|-------------|---------|----------|
| Development | {purpose} | DEC-ops-* |
| Staging | {purpose} | DEC-ops-* |
| Production | {purpose} | DEC-ops-* |

### 8.3 CI/CD Pipeline

{Pipeline description tied to ops decisions}

---

## 9. Monitoring and Observability (DEC-ops-*)

### 9.1 Monitoring Strategy (DEC-ops-*)

{Monitoring approach tied to decisions}

### 9.2 Key Metrics

| Metric | Tool | Alert Threshold | Decision |
|--------|------|-----------------|----------|
| {metric} | {tool} | {threshold} | DEC-ops-* |

### 9.3 Logging

{Logging strategy tied to decisions}

---

## 10. Technical Risks (RISK-tech-*)

### 10.1 Identified Risks

| Risk | Impact | Mitigation | Reference |
|------|--------|------------|-----------|
| {risk} | {impact} | {mitigation} | RISK-tech-* |

### 10.2 Technical Debt Considerations

{Known debt and management strategy}

---

## 11. Architecture Decision Records

Key decisions documented in this architecture:

| ID | Decision | Rationale | Status |
|----|----------|-----------|--------|
| DEC-tech-* | {decision} | {why} | {status} |

---

## Appendix A: Technology Stack

| Layer | Technology | Version | Decision |
|-------|------------|---------|----------|
| Frontend | {tech} | {version} | DEC-tech-* |
| Backend | {tech} | {version} | DEC-tech-* |
| Database | {tech} | {version} | DEC-tech-* |
| Infrastructure | {tech} | {version} | DEC-tech-* |

---

## Appendix B: Evidence Reference

Technical evidence supporting architecture:

| ID | Claim | Confidence |
|----|-------|------------|
| EV-tech-* | {claim} | {confidence} |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | {date} | Initial generation | Context Ledger |
