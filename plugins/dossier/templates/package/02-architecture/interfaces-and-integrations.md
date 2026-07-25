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
# Interfaces and Integrations
<!-- contract: references/package-contract-02-architecture.md#interfaces-and-integrations -->

Discoverability in code is not a reason to publish an interface. Every row below carries an explicit disclosure decision, and only rows marked public reach `06-public/technical-partner-guide.md`.

## Interface inventory

| Interface | Kind | Producer | Consumers | Owner | Transport | Authentication | Authorization | Schema | Version | Lifecycle | Disclosure | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill — HTTP API \| event \| webhook \| file \| SDK \| CLI \| protocol \| device \| human handoff} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill — stable \| beta \| deprecated \| internal-only \| undocumented} | {fill — public \| partner \| internal \| restricted} | {fill} |

## Machine-readable contracts

| Contract | Format | Location | Generated from | Generation command | Versioned how | Validated where | Drift check | Evidence |
|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

A contract that is hand-maintained alongside an implementation, with no drift check, is recorded as such — that is the mechanism by which API documentation becomes false.

## Examples

Synthetic data only. No real identifiers, no real tokens, no customer data.

### {fill — interface name}

**Request**

```{fill}
{fill}
```

**Response**

```{fill}
{fill}
```

**Verified against:** {fill — the executed check, environment, and date, or `not executed` with the reason}

## Behaviour contract

| Interface | Error model | Retry guidance | Idempotency | Ordering | Rate limits | Timeouts | Pagination | Compatibility policy | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

### Error catalog

| Code | Meaning | Retryable | Caller action | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Integration prerequisites and environment differences

| Prerequisite | Applies to | How obtained | Lead time | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

| Behaviour | Local | Test | Staging | Production | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Contract tests and verification coverage

| Interface | Contract test | Runs where | Covers | Does not cover | Last run | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Third-party dependencies and failure behaviour

| Dependency | Used for | Criticality | Failure behaviour | Timeout | Fallback | Tested | Evidence |
|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill — yes \| no \| unknown} | {fill} |

## Deprecation and versioning policy

| Aspect | Policy | Enforced how | Evidence |
|---|---|---|---|
| Versioning scheme | {fill} | {fill} | {fill} |
| Breaking-change definition | {fill} | {fill} | {fill} |
| Deprecation notice period | {fill} | {fill} | {fill} |
| Sunset process | {fill} | {fill} | {fill} |

## Undocumented and unstable interfaces

Interfaces reachable by a consumer that carry no contract. Their existence is a risk whether or not anyone is meant to use them.

| Interface | Reachable by | Why undocumented | In use by anyone | Risk | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — yes \| no \| unknown} | {fill} | {fill} |

## Mapping to the partner guide

| Interface | Disclosure decision | Claim ID | Appears in partner guide | Rationale if withheld |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — yes \| no} | {fill} |
