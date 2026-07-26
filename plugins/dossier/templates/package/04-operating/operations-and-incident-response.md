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
# Operations and Incident Response
<!-- contract: references/package-contract-04-operating.md#operations-and-incident-response -->

Any command below that can cause data loss, downtime, security exposure, or an irreversible effect carries its preconditions, blast radius, required authorization, rollback, and post-execution verification. A destructive command documented without those five is a defect in this document.

## Operational scope and responsibility

| Function | Responsible | Accountable | Hours | Escalation | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Service and dependency inventory

| Service or dependency | Criticality | Owner | Failure impact | Recovery path | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — tier 1 \| tier 2 \| tier 3} | {fill} | {fill} | {fill} | {fill} |

## Standard procedures

| Procedure | Command or runbook | Preconditions | Blast radius | Authorization | Rollback | Verification | Last executed |
|---|---|---|---|---|---|---|---|
| Deploy | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Rollback | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Restart | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Failover | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Backup | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Restore | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Scale | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Maintenance | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Alert triage

| Alert | First check | Second check | Escalate when | Runbook |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

### Diagnostic entry points

| Question | Where to look | Command or query | Access required |
|---|---|---|---|
| Is it up? | {fill} | {fill} | {fill} |
| Is it slow? | {fill} | {fill} | {fill} |
| Is it erroring? | {fill} | {fill} | {fill} |
| Which change caused it? | {fill} | {fill} | {fill} |
| Is data affected? | {fill} | {fill} | {fill} |

## Runbook catalog

One entry per credible failure mode. A failure mode with no runbook is listed with an empty runbook cell rather than omitted.

| Failure mode | Runbook | Owner | Last exercised | Exercise result | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — or `never`} | {fill} | {fill} |

`never` is common and is more useful than a plausible date.

## Incident management

| Severity | Definition | Declaration authority | Response time | Communication cadence | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

| Phase | Actions | Roles | Artifacts produced |
|---|---|---|---|
| Detection | {fill} | {fill} | {fill} |
| Declaration | {fill} | {fill} | {fill} |
| Command | {fill} | {fill} | {fill} |
| Mitigation | {fill} | {fill} | {fill} |
| Recovery | {fill} | {fill} | {fill} |
| Closure | {fill} | {fill} | {fill} |

## Security and privacy incidents

| Aspect | Procedure | Differs from standard incident how | Owner | Evidence |
|---|---|---|---|---|
| Detection and triage | {fill} | {fill} | {fill} | {fill} |
| Containment | {fill} | {fill} | {fill} | {fill} |
| Evidence preservation | {fill} | {fill} | {fill} | {fill} |
| Notification decision | {fill} | {fill} | {fill} | {fill} |
| External reporting | {fill} | {fill} | {fill} | {fill} |

## Communication boundaries

| Audience | Who may communicate | What may be said | What must not be said | Approval |
|---|---|---|---|---|
| Customers | {fill} | {fill} | {fill} | {fill} |
| Partners | {fill} | {fill} | {fill} | {fill} |
| Regulators | {fill} | {fill} | {fill} | {fill} |
| Public | {fill} | {fill} | {fill} | {fill} |

## Notification obligations

| Obligation | Source | Trigger | Deadline | Owner | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — regulation \| contract \| policy} | {fill} | {fill} | {fill} | {fill} |

## Status, review, and learning

| Mechanism | Where | Owner | Cadence | Evidence |
|---|---|---|---|---|
| Status communication | {fill} | {fill} | {fill} | {fill} |
| Post-incident review | {fill} | {fill} | {fill} | {fill} |
| Action tracking | {fill} | {fill} | {fill} | {fill} |
| Recurrence check | {fill} | {fill} | {fill} | {fill} |

## Business continuity and disaster recovery

| Scenario | Continuity plan | Recovery objective | Last exercised | Result | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Manual operations and unsafe gaps

| Operation | Why it is manual | Who can do it | Risk if done wrong | Reversible | Proposed remedy |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
