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
# Documentation Index
<!-- contract: references/package-contract-00-control.md#documentation-index -->

## Scope

**Project scope:** {fill — what this package documents}

**Documentation scope:** {fill — which repositories, services, environments, and evidence classes were inspected}

**Out of scope:** {fill — what was deliberately not inspected, and why}

## Package version and verification

| Field | Value |
|---|---|
| Package version | {fill} |
| Project version or commit | {fill} |
| Evidence cutoff date | {fill — YYYY-MM-DD} |
| Delivery mode | {fill — full \| targeted \| verification-only} |
| Last full verification | {fill — YYYY-MM-DD, or `never`} |
| Last gate verdict | {fill — RELEASABLE \| CONDITIONALLY-RELEASABLE \| NOT-RELEASABLE \| not run} |

## Reader routes

Each route is an ordered reading list. A reader following a route should reach a decision without opening documents outside it.

| Reader | Route | First question answered |
|---|---|---|
| Technical due diligence | {fill} | {fill} |
| Engineering onboarding | {fill} | {fill} |
| Product onboarding | {fill} | {fill} |
| Design | {fill} | {fill} |
| Data / AI | {fill} | {fill} |
| Operators | {fill} | {fill} |
| Security and privacy reviewers | {fill} | {fill} |
| Technical partners | {fill} | {fill} |
| Customers | {fill} | {fill} |

## Canonical documents

Values in this table are copies of each document's header. When they disagree, the header wins and this row is the defect.

| Path | Purpose | Owner | Audience | Confidentiality | Status | Last verified |
|---|---|---|---|---|---|---|
| `00-control/documentation-index.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `00-control/evidence-ledger.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `00-control/assumptions-questions-and-contradictions.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `00-control/claim-and-disclosure-register.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `00-control/terminology-and-ownership.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `01-project/executive-project-brief.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `01-project/product-and-domain.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `02-architecture/system-architecture.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `02-architecture/components-and-codebase.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `02-architecture/data-and-ai.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `02-architecture/interfaces-and-integrations.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `02-architecture/infrastructure-and-deployment.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `03-assurance/security-privacy-and-compliance.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `03-assurance/reliability-performance-and-observability.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `03-assurance/testing-quality-and-delivery.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `04-operating/onboarding-and-local-development.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `04-operating/operations-and-incident-response.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `04-operating/decisions-technical-debt-and-risks.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `05-due-diligence/technical-due-diligence-report.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `05-due-diligence/assets-dependencies-and-licenses.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |
| `06-public/technical-partner-guide.md` | {fill} | {fill} | Public | {fill} | {fill} | {fill} |
| `06-public/customer-product-and-trust-guide.md` | {fill} | {fill} | Public | {fill} | {fill} | {fill} |
| `07-verification/documentation-verification-report.md` | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Evidence coverage

| Measure | Value |
|---|---|
| Evidence rows | {fill} |
| `V` / `C` / `R` / `I` / `U` / `N/A` | {fill} |
| Material claims with no evidence row | {fill} |
| Rows past their freshness expiry | {fill} |
| Source classes inspected | {fill} |
| Source classes unavailable | {fill} |

**Coverage by document** — which canonical documents rest on thin evidence, so a reader knows where to discount:

| Document | Rows cited | Weakest state carrying decision weight | Note |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Unresolved critical items

Blocking questions and unresolved contradictions that a reader must know about before relying on any document.

| ID | Item | Impact if wrong | Owner | Affected documents |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Document dependencies and sources of truth

Each fact has exactly one canonical home. Other documents cross-link rather than restate.

| Subject | Source of truth | Documents that link to it |
|---|---|---|
| {fill} | {fill} | {fill} |

## Maintenance

| Policy | Value |
|---|---|
| Review cadence | {fill} |
| Freshness threshold | {fill — days after which `last-verified` is considered stale} |
| Refresh triggers | {fill — the change events that invalidate documents; see the per-document `review-trigger`} |
| Archival rule | {fill — what happens to a superseded package version} |
| Refresh mechanism | {fill — manual, post-merge automation, scheduled sweep} |

## Change summary

Changes since the previous documentation version. `—` when this is the first package.

| Date | Package version | Documents changed | Reason |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Supplemental documents

Non-canonical documents this project genuinely needs. Each entry states why it exists and which canonical document it extends rather than duplicates. Empty is the normal state.

| Path | Why it exists | Extends | Owner |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |
