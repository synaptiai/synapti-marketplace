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
# Testing, Quality, and Delivery
<!-- contract: references/package-contract-03-assurance.md#testing-quality-and-delivery -->

Coverage percentages state what was measured and are not treated as evidence of behavioural quality. A command that was not executed during documentation verification is recorded as `not executed`, never as passing.

## Quality strategy

Dimensions that do not apply to this project are marked `N/A` with a reason.

| Dimension | Strategy | Owner | Evidence |
|---|---|---|---|
| Software | {fill} | {fill} | {fill} |
| Product | {fill} | {fill} | {fill} |
| Data | {fill} | {fill} | {fill} |
| AI / model | {fill} | {fill} | {fill} |
| Hardware | {fill} | {fill} | {fill} |
| Security | {fill} | {fill} | {fill} |
| Accessibility | {fill} | {fill} | {fill} |
| Operational | {fill} | {fill} | {fill} |

## Test levels and ownership

| Level | What it covers | Owner | Runs where | Runtime | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Test inventory and coverage gaps

| Area | Tests present | Coverage measure | What the measure counts | Gap | Consequence of the gap | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — lines \| branches \| functions \| scenarios} | {fill} | {fill} | {fill} |

Critical paths with no test are listed explicitly rather than implied by a coverage number.

| Critical path | Tested | Test | Evidence |
|---|---|---|---|
| {fill} | {fill — yes \| partial \| no} | {fill} | {fill} |

## Quality gates

| Stage | Gate | Blocking | Bypassable | Bypass requires | Evidence |
|---|---|---|---|---|---|
| Local development | {fill} | {fill} | {fill} | {fill} | {fill} |
| Pull request / CI | {fill} | {fill} | {fill} | {fill} | {fill} |
| Release | {fill} | {fill} | {fill} | {fill} | {fill} |
| Production | {fill} | {fill} | {fill} | {fill} | {fill} |

## Static and supply-chain checks

The `Dependency scanning` row's `Tool`, `Last result`, and `Evidence` cells come from `bin/dossier-vuln-evidence.sh`'s ingestion of an existing scan artifact — dossier does not execute a scanner. When no scan artifact was found, `Last result` says so explicitly (no vulnerability-scan output located); it is never left blank, and it is never written as though the absence of a scan were a clean result.

| Check | Tool | Scope | Runs where | Blocking | Last result | Evidence |
|---|---|---|---|---|---|---|
| Static analysis | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Formatting | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Linting | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Type checking | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Dependency scanning | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| Artifact verification | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Test data and environments

| Concern | Approach | Contains production data | Refresh | Evidence |
|---|---|---|---|---|
| Test data | {fill} | {fill — yes \| no \| unknown} | {fill} | {fill} |
| Test environments | {fill} | {fill} | {fill} | {fill} |
| Fixtures and seeds | {fill} | {fill} | {fill} | {fill} |

Production data in a test environment is a privacy finding, not a convenience note.

## Flaky tests, quarantines, and manual gates

| Item | Kind | Where | Since | Owner | Impact | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill — flaky \| quarantined \| skipped \| bypassed \| manual gate} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Delivery pipeline

| Aspect | Current practice | Enforced by | Evidence |
|---|---|---|---|
| CI workflows | {fill} | {fill} | {fill} |
| Branch policy | {fill} | {fill} | {fill} |
| Review policy | {fill} | {fill} | {fill} |
| Artifact provenance | {fill} | {fill} | {fill} |
| Signing | {fill} | {fill} | {fill} |
| Promotion between environments | {fill} | {fill} | {fill} |

## Release process

| Aspect | Current practice | Evidence |
|---|---|---|
| Cadence | {fill} | {fill} |
| Approval | {fill} | {fill} |
| Rollback | {fill} | {fill} |
| Hotfix path | {fill} | {fill} |

## Delivery metrics

Verified figures only, each with its measurement window.

| Metric | Value | Window | Source | State | Evidence |
|---|---|---|---|---|---|
| Change failure rate | {fill} | {fill} | {fill} | {fill} | {fill} |
| Defect escape rate | {fill} | {fill} | {fill} | {fill} | {fill} |
| Incident rate | {fill} | {fill} | {fill} | {fill} | {fill} |
| Lead time to production | {fill} | {fill} | {fill} | {fill} | {fill} |
| Deployment frequency | {fill} | {fill} | {fill} | {fill} | {fill} |

## Commands executed during documentation verification

Every command run while producing this package, with its result. This table is the source for the `cmd:` locators in the evidence ledger.

| Command | Purpose | Environment | Date | Result | Output artifact |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill — passed \| failed \| not executed} | {fill} |

| Command not executed | Why | What it would have established |
|---|---|---|
| {fill} | {fill} | {fill} |
