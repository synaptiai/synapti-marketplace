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
# Reliability, Performance, and Observability
<!-- contract: references/package-contract-03-assurance.md#reliability-performance-and-observability -->

Objectives and measurements are kept in separate tables throughout this document. A target is never written as a result, and an internal objective is never written as a customer guarantee — the latter requires a contract, not a document.

## Critical user journeys

| Journey | Actor | Why it is critical | Components involved | Dependencies | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Objectives

Stated intent. Every row carries the document that approves it.

| Journey or service | Dimension | Objective | Window | Approved in | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — availability \| latency \| throughput \| durability \| freshness \| correctness} | {fill} | {fill} | {fill} | {fill} |

## Indicators, objectives, agreements, and error budgets

Four distinct things. Conflating them is the most common reliability documentation error.

| Service | SLI (what is measured, and how) | SLO (internal objective) | SLA (contractual commitment) | Error budget | Budget consumed | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — or `none`} | {fill} | {fill} | {fill} |

`none` in the SLA column is common and correct. An SLO reported to a customer as an SLA is a claim the project cannot honour.

## Measured performance

Observations. Every row carries its window and environment.

| Metric | Value | Window | Environment | Measurement source | Observed | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

### Load assumptions

| Assumption | Value | Basis | Verified | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill — measured \| projected \| assumed} | {fill} | {fill} |

## Capacity model and tested limits

| Dimension | Modelled limit | Tested limit | Test method | Test date | Headroom at current load | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill — or `not tested`} | {fill} | {fill} | {fill} | {fill} |

## Resilience mechanisms

| Mechanism | Where | Configuration | Behaviour on trip | Tested | Evidence |
|---|---|---|---|---|---|
| Timeouts | {fill} | {fill} | {fill} | {fill} | {fill} |
| Retries | {fill} | {fill} | {fill} | {fill} | {fill} |
| Backpressure | {fill} | {fill} | {fill} | {fill} | {fill} |
| Circuit breakers | {fill} | {fill} | {fill} | {fill} | {fill} |
| Queues | {fill} | {fill} | {fill} | {fill} | {fill} |
| Caches | {fill} | {fill} | {fill} | {fill} | {fill} |
| Graceful degradation | {fill} | {fill} | {fill} | {fill} | {fill} |

A retry configured without idempotency on the target operation is a correctness risk and is recorded as one.

## Observability

| Signal | Coverage | Where it lands | Retention | Gaps | Evidence |
|---|---|---|---|---|---|
| Logs | {fill} | {fill} | {fill} | {fill} | {fill} |
| Metrics | {fill} | {fill} | {fill} | {fill} | {fill} |
| Traces | {fill} | {fill} | {fill} | {fill} | {fill} |
| Events | {fill} | {fill} | {fill} | {fill} | {fill} |
| Synthetic checks | {fill} | {fill} | {fill} | {fill} | {fill} |
| Business signals | {fill} | {fill} | {fill} | {fill} | {fill} |

## Dashboards, alerts, and escalation

| Alert | Condition | Threshold basis | Fires to | Runbook | False-positive history | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill — measured \| guessed \| vendor default} | {fill} | {fill} | {fill} | {fill} |

| Dashboard | Answers | Owner | Evidence |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Failure and recovery scenarios

| Scenario | Expected behaviour | Detection | Recovery | Data loss window | Exercised | Evidence |
|---|---|---|---|---|---|---|
| Dependency failure | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Regional failure | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Data corruption | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Partial failure and retry storm | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Test evidence

| Test type | Last run | Scope | Environment | Result | Artifact | Evidence |
|---|---|---|---|---|---|---|
| Chaos | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Load | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Soak | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Failover | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Backup | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Recovery | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

`not executed` is a valid value in every cell and is the honest one when no evidence of a run exists.

## Blind spots and operational risks

| Blind spot | What would go undetected | How long | Consequence | Proposed remedy | Owner |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
