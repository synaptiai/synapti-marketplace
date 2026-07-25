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
# Security, Privacy, and Compliance
<!-- contract: references/package-contract-03-assurance.md#security-privacy-and-compliance -->

The words secure, compliant, encrypted, anonymous, and private do not appear in this document without a defined scope and cited evidence. The absence of a known incident is not recorded as evidence of security. No credential value, secret name that reveals content, vulnerability detail, or exploitable path appears anywhere in this file.

## Scope

| Field | Value |
|---|---|
| Systems in scope | {fill} |
| Systems explicitly out of scope | {fill} |
| Evidence classes inspected | {fill} |
| Evidence classes unavailable | {fill} |
| Assessment date | {fill} |
| Assessed against project version | {fill} |

This is a documentation assessment, not a penetration test or an audit. What it can and cannot establish: {fill}

## Assets, actors, and trust boundaries

| Asset | Value to an attacker | Where it lives | Protected by | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

| Actor | Motivation | Access they start with | Capability assumed | Evidence |
|---|---|---|---|---|
| {fill} | {fill — external unauthenticated \| external authenticated \| partner \| insider \| supply chain \| compromised dependency} | {fill} | {fill} | {fill} |

## Threat model

| Threat | Asset | Actor | Path | Control | Control state | Residual risk | Evidence |
|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — implemented \| policy-only \| planned \| unknown} | {fill} | {fill} |

## Identity and access controls

| Control | Mechanism | Applies to | Enforcement point | State | Last verified | Evidence |
|---|---|---|---|---|---|---|
| Authentication | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Authorization | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Tenancy separation | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Isolation | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Session management | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Administrative access | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Secrets, keys, and encryption

| Aspect | Practice | Scope it covers | Scope it does not cover | State | Evidence |
|---|---|---|---|---|---|
| Secret storage | {fill} | {fill} | {fill} | {fill} | {fill} |
| Secret distribution | {fill} | {fill} | {fill} | {fill} | {fill} |
| Key management | {fill} | {fill} | {fill} | {fill} | {fill} |
| Encryption in transit | {fill} | {fill} | {fill} | {fill} | {fill} |
| Encryption at rest | {fill} | {fill} | {fill} | {fill} | {fill} |
| Certificate management | {fill} | {fill} | {fill} | {fill} | {fill} |
| Rotation | {fill} | {fill} | {fill} | {fill} | {fill} |

The "scope it does not cover" column is required on every row. "Encrypted at rest" that covers the primary database but not backups, logs, or the search index is a materially different statement from "encrypted at rest".

## Control layers

| Layer | Controls present | State | Gaps | Evidence |
|---|---|---|---|---|
| Network | {fill} | {fill} | {fill} | {fill} |
| Application | {fill} | {fill} | {fill} | {fill} |
| Infrastructure | {fill} | {fill} | {fill} | {fill} |
| Supply chain | {fill} | {fill} | {fill} | {fill} |
| Endpoint | {fill} | {fill} | {fill} | {fill} |
| Physical | {fill} | {fill} | {fill} | {fill} |

## Secure development and vulnerability management

| Practice | Current state | Enforced by | Coverage | Evidence |
|---|---|---|---|---|
| Threat modelling | {fill} | {fill} | {fill} | {fill} |
| Security review in code review | {fill} | {fill} | {fill} | {fill} |
| Dependency scanning | {fill} | {fill} | {fill} | {fill} |
| Static analysis | {fill} | {fill} | {fill} | {fill} |
| Secret scanning | {fill} | {fill} | {fill} | {fill} |
| Vulnerability triage and SLA | {fill} | {fill} | {fill} | {fill} |
| Patch cadence | {fill} | {fill} | {fill} | {fill} |
| Disclosure process | {fill} | {fill} | {fill} | {fill} |

## Logging, detection, and evidence preservation

| Capability | What is captured | Retention | Who can read it | Tamper resistance | Evidence |
|---|---|---|---|---|---|
| Application logging | {fill} | {fill} | {fill} | {fill} | {fill} |
| Audit logging | {fill} | {fill} | {fill} | {fill} | {fill} |
| Detection and alerting | {fill} | {fill} | {fill} | {fill} | {fill} |
| Evidence preservation | {fill} | {fill} | {fill} | {fill} | {fill} |

Whether sensitive data reaches logs is a required determination, not an assumption.

## Data protection and privacy

| Data class | Purpose | Legal basis | Consent mechanism | Minimization | Retention | Deletion path | Residency | Evidence |
|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

| Data-subject right | Supported | Mechanism | Time to fulfil | Verified | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — yes \| partial \| no \| N/A} | {fill} | {fill} | {fill} | {fill} |

## Subprocessors and third-party risk

| Party | Function | Data shared | Location | Contractual basis | Assessed | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — yes \| no \| unknown} | {fill} |

## Applicable requirements

Candidate requirements are listed as candidates. Applicability is never claimed without evidence, and neither is compliance.

| Requirement | Source | Applicability | Basis for the applicability determination | Compliance state | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — regulation \| contract \| certification \| internal policy} | {fill — applies \| does not apply \| candidate, unverified} | {fill} | {fill — evidenced \| self-asserted \| not assessed} | {fill} |

## Control evidence and test dates

| Control | Last tested | Tested by | Method | Result | Next due | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Gaps

| Gap | Severity | Likelihood | Impact | Affected assets | Remediation | Owner | Evidence |
|---|---|---|---|---|---|---|---|
| {fill} | {fill — critical \| high \| medium \| low} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

Remediation detail stays at the level of what must change, not at the level of how the weakness is exploited.

## Control state summary

| Control state | Count | Notes |
|---|---:|---|
| Implemented and evidenced | {fill} | {fill} |
| Policy-only — documented, implementation not evidenced | {fill} | {fill} |
| Planned | {fill} | {fill} |
| Unknown | {fill} | {fill} |

A policy is evidence that a policy exists. It is not evidence that a control operates.

## Public claims and prohibited disclosures

| Safe to state publicly | Scope it holds within | Claim ID |
|---|---|---|
| {fill} | {fill} | {fill} |

| Must not be disclosed | Why |
|---|---|
| {fill} | {fill} |
