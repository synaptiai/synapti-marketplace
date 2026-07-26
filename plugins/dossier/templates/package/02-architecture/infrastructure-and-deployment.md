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
# Infrastructure and Deployment
<!-- contract: references/package-contract-02-architecture.md#infrastructure-and-deployment -->

High availability, recovery objectives, zero downtime, and geographic redundancy are claims about current behaviour. None of them appears in this document without current evidence, and a recovery objective without an evidenced test is recorded as an objective, not as a capability.

## Environments

| Environment | Purpose | Who can access | Data class held | Parity with production | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Topology

Cloud, on-premises, edge, device, network, DNS, certificate, and region layout as applicable. `N/A` with a reason for layers this project does not have.

| Layer | Configuration | Region or location | Owner | Source of truth | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

```mermaid
%% {fill — deployment topology: environments, network boundaries, and the path traffic takes
%%  from an external client to the workload.}
graph TD
  client[{fill}] --> edge[{fill}]
```

## Infrastructure ownership and source of truth

| Resource class | Managed by | Source of truth | Drift detection | Manual changes possible | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — IaC \| console \| script \| unmanaged} | {fill} | {fill} | {fill — yes \| no} | {fill} |

Resources marked `unmanaged` or `console` are the ones that will not survive a rebuild. They are listed here and cross-referenced as risks.

## Resources

| Resource | Type | Environment | Sizing | Cost driver | Owner | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill — compute \| storage \| network \| queue \| secret store \| identity} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Delivery flow

From commit to running system.

| Stage | Mechanism | Trigger | Approval | Duration | Reversible | Evidence |
|---|---|---|---|---|---|---|
| Build | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Package | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Artifact storage | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Deploy | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Migration | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Promotion | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Rollback | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Configuration and drift control

| Environment | Configuration source | Secret source | Drift detected how | Last drift check | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Access model and privileged operations

| Operation | Who can perform it | Authentication | Approval required | Audited | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill — yes \| no \| unknown} | {fill} |

No credential values, no secret names that reveal a secret's content, no access paths that would help an attacker.

## Capacity, quotas, scaling, and cost

| Dimension | Current | Limit | Limit source | Scaling mechanism | Cost behaviour at scale | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — measured \| provider quota \| configured \| unknown} | {fill} | {fill} | {fill} |

## Backup, restore, and disaster recovery

| Item | Value | Objective or measured | Evidence |
|---|---|---|---|
| Backup scope | {fill} | — | {fill} |
| Backup frequency | {fill} | — | {fill} |
| Backup retention | {fill} | — | {fill} |
| Recovery point objective | {fill} | {fill — stated objective \| measured} | {fill} |
| Recovery time objective | {fill} | {fill — stated objective \| measured} | {fill} |
| Last restore test | {fill} | — | {fill} |
| Last failover test | {fill} | — | {fill} |
| Scope of the last test | {fill} | — | {fill} |

An objective with no test evidence is written as an objective. It is never written as a capability, and it never reaches a public or partner document as a commitment.

## Release strategy and change control

| Aspect | Current practice | Enforced by | Limitation | Evidence |
|---|---|---|---|---|
| Release strategy | {fill} | {fill} | {fill} | {fill} |
| Change approval | {fill} | {fill} | {fill} | {fill} |
| Rollback limitations | {fill} | {fill} | {fill} | {fill} |

Rollback limitations are required content. A migration that cannot be reversed, a cache that must be warmed, a client that pins a version — each bounds what "rollback" actually means.

## Manual steps, single points of failure, and undocumented infrastructure

| Item | Kind | Impact if it fails or is forgotten | Who knows about it | Evidence |
|---|---|---|---|---|
| {fill} | {fill — manual step \| single point of failure \| undocumented resource} | {fill} | {fill} | {fill} |

## Environment differences

Differences that change behaviour, not differences that change only names.

| Behaviour | Local | Test | Staging | Production | Consequence | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
