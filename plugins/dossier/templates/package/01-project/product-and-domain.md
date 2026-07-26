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
# Product and Domain
<!-- contract: references/package-contract-01-project.md#product-and-domain -->

Product intent is not inferred from code when product evidence exists. Where intended and implemented behaviour diverge, both are recorded and the divergence is named.

## Vision, mission, goals, and non-goals

**Vision:** {fill}

**Mission:** {fill}

| Goal | Measure of success | Evidence |
|---|---|---|
| {fill} | {fill} | {fill} |

| Non-goal | Why excluded | Evidence |
|---|---|---|
| {fill} | {fill} | {fill} |

## Actors

Users, buyers, administrators, operators, partners, and anyone else the product serves or is acted on by.

| Actor | Class | What they need from the product | Access path | Evidence |
|---|---|---|---|---|
| {fill} | {fill — end user \| buyer \| administrator \| operator \| partner \| regulator \| internal} | {fill} | {fill} | {fill} |

## Jobs to be done and user journeys

| Job | Actor | Journey | Success criterion | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

### Primary journey walkthrough

{fill — step-by-step trace of the most important journey, from entry to completion, naming the components it crosses. This is the journey the architecture and verification documents also trace, so the names must match `00-control/terminology-and-ownership.md`.}

## Feature and capability map

| Capability | State | Actor | Entry point | Evidence | Note |
|---|---|---|---|---|---|
| {fill} | {fill — implemented \| partial \| planned \| deprecated \| absent} | {fill} | {fill} | {fill} | {fill} |

## Business model and commercial constraints

Included only where evidenced and where commercial structure constrains technical behaviour. `N/A` with a reason where it does not.

| Plan or entitlement | What it grants | Technical enforcement point | Evidence |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Product boundaries

| Boundary | In scope | Explicitly out of scope | Evidence |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Domain model

| Entity | Definition | Owns | Lifecycle | Canonical name (`TM-####`) | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

### Business rules and invariants

| Rule or invariant | Enforced where | Enforcement kind | What breaks if violated | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill — code \| schema constraint \| process \| unenforced} | {fill} | {fill} |

An invariant recorded as `unenforced` is a finding, not a footnote.

## Permissions and role model

Product-level roles. The technical authorization mechanism lives in `02-architecture/system-architecture.md` and `03-assurance/security-privacy-and-compliance.md`.

| Role | Grants | Denies | Assignment path | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Experience and interaction

Where applicable. `N/A` with a reason for products with no user interface.

| Aspect | Current state | Source of truth | Evidence |
|---|---|---|---|
| Information architecture | {fill} | {fill} | {fill} |
| Interaction model | {fill} | {fill} | {fill} |
| Design system | {fill} | {fill} | {fill} |
| Important UI states (empty, loading, error, partial, offline) | {fill} | {fill} | {fill} |
| Content and voice conventions | {fill} | {fill} | {fill} |

## Product analytics

| Metric | Definition | Instrumented where | Coverage | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — full \| partial \| absent} | {fill} |

A metric defined but not instrumented is recorded as `absent`, not as a metric.

## Accessibility, internationalization, and platforms

| Aspect | Current state | Standard or target | Verified how | Evidence |
|---|---|---|---|---|
| Accessibility | {fill} | {fill} | {fill} | {fill} |
| Internationalization | {fill} | {fill} | {fill} | {fill} |
| Supported platforms | {fill} | {fill} | {fill} | {fill} |

## Roadmap

Planned only. Nothing here describes current behaviour, and nothing here carries a date unless a committed date exists in evidence.

| Planned item | Stage | Committed date | Evidence |
|---|---|---|---|
| {fill} | {fill — under consideration \| committed \| in progress} | {fill} | {fill} |

## Intended versus implemented behaviour

Divergences between what product evidence says the product should do and what the implementation does.

| Subject | Intended | Implemented | Divergence | Impact | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Product assumptions, constraints, risks, and open decisions

| Item | Kind | Impact | Owner | Register ID |
|---|---|---|---|---|
| {fill} | {fill — assumption \| constraint \| risk \| open decision} | {fill} | {fill} | {fill} |
