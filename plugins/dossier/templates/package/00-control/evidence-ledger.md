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
# Evidence Ledger
<!-- contract: references/package-contract-00-control.md#evidence-ledger -->

## Method

Every material claim in this package traces to one row below. Column definitions, the `EV-####` grammar, append-only rules, and the `[EV-####]` citation syntax are specified in the plugin reference `references/evidence-ledger-schema.md`.

**Claim states**

| State | Meaning |
|---|---|
| `V` | Verified — directly supported by authoritative, current evidence, or by an executed check whose output is retained |
| `C` | Corroborated — two independent current sources agree, at least one authoritative for the claim type |
| `R` | Reported — stated by a stakeholder or existing document, not independently verified |
| `I` | Inferred — reasoned from indirect evidence, chain stated |
| `U` | Unknown — required information unavailable, inaccessible, or contradictory |
| `N/A` | Not applicable — demonstrably irrelevant, with a reason |

Only `V` and `C` may appear unqualified in public documents. Absence of evidence is never recorded as evidence of absence.

**Authority levels**

| Level | Source class | Instantiated here as |
|---:|---|---|
| 1 | Observed runtime behaviour and reproducible checks | {fill} |
| 2 | Versioned code, schemas, infrastructure, tests, immutable records | {fill} |
| 3 | Current operational telemetry and release evidence | {fill} |
| 4 | Current approved specifications and decision records | {fill} |
| 5 | Tickets, planning documents, existing prose documentation | {fill} |
| 6 | Stakeholder recollection | {fill} |
| 7 | Inference | {fill} |

## Evidence table

| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Source inventory and inspection coverage

What was made available, what was inspected, and how completely.

| Source | Class | Made available | Inspected | Coverage | Note |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill — full \| sampled \| partial \| none} | {fill} |

## Executed checks

Every `cmd:` locator in the evidence table appears here. A check that could not run is recorded as `not executed` with the reason — never as passed.

| Check | Command | Scope | Environment | Date | Result | Output artifact |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — passed \| failed \| not executed} | {fill} |

## Unavailable evidence

Sources that were sought and could not be reached, and what each would have settled. This section is what keeps `U` rows from reading as omissions.

| Source sought | Why it matters | Why unavailable | Would settle | Open question |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill — AQ-####} |

## Stale evidence

Rows whose freshness expiry has passed. Listing here precedes demotion; the calendar does not silently change a claim state.

| Evidence ID | Expiry basis | Expired on | Current state | Required refresh action | Owner |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Secrets and sensitive material encountered

Type and location category only. No values, no excerpts, no exploitable detail. `none` is a valid and common entry.

| Type | Location category | Severity | Confidentiality | Remediation need | Reported through |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
