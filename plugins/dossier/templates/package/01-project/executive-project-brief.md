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
# Executive Project Brief
<!-- contract: references/package-contract-01-project.md#executive-project-brief -->

This is a decision document, not marketing copy. A technical executive, investor, acquirer, or incoming leader should be able to understand the project from this file alone and know precisely how much of it is verified.

## Problem, users, and intended outcome

**Problem:** {fill}

**Users and buyers:** {fill}

**Value proposition:** {fill}

**Intended outcomes:** {fill}

## Lifecycle stage and actual scope

| Field | Value | Evidence |
|---|---|---|
| Lifecycle stage | {fill — concept \| prototype \| pre-production \| production \| maintenance \| sunset} | {fill} |
| In production since | {fill} | {fill} |
| Actual deployed scope | {fill} | {fill} |
| Users or tenants served | {fill} | {fill} |

## Capabilities: implemented versus planned

| Capability | State | Evidence | Note |
|---|---|---|---|
| {fill} | {fill — implemented \| partial \| planned \| deprecated \| absent} | {fill} | {fill} |

Planned capabilities appear here as planned. Nothing in this table is written in the present indicative unless it is implemented and evidenced.

## Architecture and operating model

{fill — three to six sentences: the shape of the system, who runs it, and how change reaches production. Detail belongs in `02-architecture/system-architecture.md`; this is the orientation a reader needs before the rest of the brief makes sense.}

| Aspect | Summary | Canonical source |
|---|---|---|
| System shape | {fill} | `02-architecture/system-architecture.md` |
| Deployment and environments | {fill} | `02-architecture/infrastructure-and-deployment.md` |
| Delivery model | {fill} | `03-assurance/testing-quality-and-delivery.md` |
| Operating model | {fill} | `04-operating/operations-and-incident-response.md` |

## Metrics

Only verified figures appear here. Every row carries its measurement window, environment, and evidence. A metric that could not be verified is listed in the unknowns section rather than estimated.

| Metric | Value | Window | Environment | State | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Principal dependencies and constraints

| Dependency or constraint | Type | Why it matters | Replaceability | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Strengths

| Strength | Why it is material | Evidence |
|---|---|---|
| {fill} | {fill} | {fill} |

## Top risks, unknowns, and near-term decisions

| Item | Kind | Impact | Owner | Evidence or register ID |
|---|---|---|---|---|
| {fill} | {fill — risk \| unknown \| decision} | {fill} | {fill} | {fill} |

## Documentation confidence

What a reader may rely on, and what they may not.

| Grouping | Content |
|---|---|
| Verified facts | {fill} |
| Reported assertions, not independently verified | {fill} |
| Inferences | {fill} |
| Unknowns | {fill} |

| Measure | Value |
|---|---|
| Overall confidence | {fill — high \| moderate \| low} |
| Basis for that rating | {fill} |
| Largest source of residual uncertainty | {fill} |
| Package status | {fill} |
