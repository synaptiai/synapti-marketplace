---
dossier-header: internal-v1
title: {fill}
purpose: {fill}
audience: {fill}
confidentiality: Internal
owner: {fill}
status: draft
project-version: {fill}
last-verified: {fill}
review-trigger: {fill}
related: []
---
# System Architecture
<!-- contract: references/package-contract-02-architecture.md#system-architecture -->

Every node and every connection in the diagrams below is supported by evidence. Connections that are inferred rather than observed are labelled as inferred in the diagram and in the accompanying table.

## Goals, constraints, and quality attributes

| Quality attribute | Target or constraint | Driven by | Evidence | State |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

| Architectural constraint | Origin | Consequence | Evidence |
|---|---|---|---|
| {fill} | {fill — regulatory \| contractual \| technical \| organizational \| cost} | {fill} | {fill} |

## System context

External actors and systems, and what crosses the boundary.

```mermaid
%% {fill — context diagram: the system as one node, external actors and systems around it,
%%  labelled edges naming what flows. Every edge must map to a row in the table below.}
graph LR
  actor[{fill}] --> system[{fill}]
```

| Edge | From | To | Carries | Protocol | Trust | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — trusted \| authenticated \| untrusted} | {fill} |

## Container view

Deployable and runnable units inside the boundary.

```mermaid
%% {fill — container diagram: one node per deployable unit and datastore,
%%  edges labelled with protocol and direction.}
graph TD
  a[{fill}] --> b[{fill}]
```

| Container | Responsibility | Runtime | Deployment unit | State it owns | Criticality | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Runtime and control flows

| Flow | Trigger | Path | Synchronous or asynchronous | Failure behaviour | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

### Primary flow walkthrough

{fill — the same primary journey traced in `01-project/product-and-domain.md`, followed through the containers: what handles each step, what it calls, where state is written, what happens on each failure. Timeouts, retries, queues, and caches appear here — a flow description that shows only the happy path is a finding.}

## Trust boundaries

```mermaid
%% {fill — trust boundary diagram: subgraphs per boundary, edges crossing them labelled
%%  with the authentication and authorization that governs the crossing.}
graph TD
  subgraph boundary[{fill}]
    x[{fill}]
  end
```

| Boundary | Separates | Crossing mechanism | Authentication | Authorization | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Communication

| Interaction | Kind | Transport | Delivery guarantee | Ordering | Idempotency | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill — synchronous \| asynchronous \| batch \| streaming} | {fill} | {fill — at-most-once \| at-least-once \| exactly-once \| unknown} | {fill} | {fill} | {fill} |

A retry path without an idempotency mechanism is recorded here explicitly, because it is one of the failure modes verification traces.

## State ownership and consistency

| State | Owning component | Store | Consistency model | Concurrent-write handling | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Tenancy, identity, authorization, and isolation

| Aspect | Model | Enforcement point | What it does not isolate | Evidence |
|---|---|---|---|---|
| Tenancy | {fill} | {fill} | {fill} | {fill} |
| Identity | {fill} | {fill} | {fill} | {fill} |
| Authorization | {fill} | {fill} | {fill} | {fill} |
| Isolation | {fill} | {fill} | {fill} | {fill} |

The "what it does not isolate" column is required. An isolation model documented only by what it covers reads as stronger than it is.

## Failure modes and degradation

| Failure | Blast radius | Detection | Degraded behaviour | Recovery | Tested | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — yes \| no \| unknown} | {fill} |

## Patterns actually used

Patterns present in the implementation, not patterns the team aspires to.

| Pattern | Where | Why it is there | Evidence |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Tradeoffs and rejected alternatives

Recorded only where evidence of the decision exists. Where no record exists, the rationale is unknown and is recorded as unknown rather than reconstructed.

| Decision | Chosen | Rejected alternative | Stated rationale | Evidence | State |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Current versus target architecture

| Aspect | Current | Target | Gap | Committed | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill — yes \| no \| aspiration} | {fill} |

## Scalability boundaries and bottlenecks

| Boundary | Current limit | How the limit was established | Symptom on breach | Headroom | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill — measured \| calculated \| vendor-stated \| unknown} | {fill} | {fill} | {fill} |

## Cross-links

| Subject | Canonical document |
|---|---|
| Interface contracts and integration behaviour | `02-architecture/interfaces-and-integrations.md` |
| Data model, stores, and AI architecture | `02-architecture/data-and-ai.md` |
| Environments, deployment, and recovery | `02-architecture/infrastructure-and-deployment.md` |
| Threat model and controls | `03-assurance/security-privacy-and-compliance.md` |
| Objectives, measurements, and observability | `03-assurance/reliability-performance-and-observability.md` |
| Component inventory and code paths | `02-architecture/components-and-codebase.md` |
