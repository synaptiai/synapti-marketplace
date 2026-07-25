---
dossier-header: public-v1
title: {fill}
audience: {fill}
product-version: {fill}
last-updated: {fill}
---
# Technical Partner Guide
<!-- contract: references/package-contract-06-public.md#technical-partner-guide -->

Every claim in this document maps to an approved row in the internal claim register. Nothing here describes internal topology, repository structure, secret handling, unannounced plans, vulnerable versions, customer identities, or internal risk findings.

## Overview

{fill — what the product does, and what integrating with it gets a partner. Two or three paragraphs.}

## Supported use cases

| Use case | What it enables | Supported | Not supported |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

The "not supported" column is not a disclaimer. It is what stops a partner building something the product will not sustain.

## Integration architecture

{fill — a conceptual picture at the partner's level of abstraction: what they call, what calls them back, where state lives on each side.}

```mermaid
%% {fill — conceptual integration diagram. Partner systems, the product's public surface,
%%  and the flows between them. No internal components.}
graph LR
  partner[{fill}] --> product[{fill}]
```

## Prerequisites and access

| Step | What it is | How to obtain | Typical lead time |
|---:|---|---|---|
| 1 | {fill} | {fill} | {fill} |

## Public interfaces

| Interface | Kind | Purpose | Stability | Since version |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — stable \| beta} | {fill} |

### {fill — interface name}

{fill — what it does and when to use it.}

**Request**

```{fill}
{fill}
```

**Response**

```{fill}
{fill}
```

All examples use synthetic data.

## Authentication and authorization

{fill — how a partner authenticates, what scopes or permissions exist, how credentials are issued and rotated. No detail about how credentials are stored or validated internally.}

| Scope or permission | Grants | Required for |
|---|---|---|
| {fill} | {fill} | {fill} |

## Versioning and compatibility

| Aspect | Policy |
|---|---|
| Versioning scheme | {fill} |
| What counts as a breaking change | {fill} |
| Supported versions | {fill} |
| Deprecation notice period | {fill} |
| How changes are announced | {fill} |

## Behaviour a partner must handle

| Behaviour | What happens | What your integration should do |
|---|---|---|
| Errors | {fill} | {fill} |
| Retries | {fill} | {fill} |
| Idempotency | {fill} | {fill} |
| Rate limits | {fill} | {fill} |
| Timeouts | {fill} | {fill} |
| Pagination | {fill} | {fill} |

### Error reference

| Code | Meaning | Retryable | What to do |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Testing your integration

| Facility | What it offers | Differences from production | How to get access |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Security and data responsibility

{fill — the division of responsibility between the product and the partner, at the disclosure level the claim register approves. What data crosses the boundary, in which direction, and what each side is responsible for protecting. No control implementation detail.}

| Responsibility | Product | Partner |
|---|---|---|
| {fill} | {fill} | {fill} |

## Operations and support

| Aspect | Detail |
|---|---|
| Support channel | {fill} |
| Response expectations | {fill} |
| Escalation path | {fill} |
| Status page | {fill} |
| Maintenance notification | {fill} |

## Commitments

Only commitments that are both contractually and technically verified appear here. Where none exist, this section says so plainly rather than implying one.

| Commitment | Applies to | Conditions | Where it is contractually defined |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Change communication

| Change type | Notice | Channel |
|---|---|---|
| {fill} | {fill} | {fill} |

## Known limitations

Stated so a partner can design around them. Detailed enough to be useful, bounded so as not to describe an exploitable path.

| Limitation | Effect on your integration | Workaround |
|---|---|---|
| {fill} | {fill} | {fill} |

## Partner checklist

Confirm each item before going live.

- [ ] {fill}
- [ ] {fill}
- [ ] {fill}

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| {fill} | {fill} | {fill} |
