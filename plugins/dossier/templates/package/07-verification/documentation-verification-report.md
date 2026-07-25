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
# Documentation Verification Report
<!-- contract: references/package-contract-07-verification.md#documentation-verification-report -->

This report says what was verified, what remains uncertain, and whether the package passes its gates. It does not claim the package is perfect and does not report a check as passing when it did not run.

## Scope

| Field | Value |
|---|---|
| Package version verified | {fill} |
| Project version or commit | {fill} |
| Evidence cutoff | {fill} |
| Verification date | {fill} |
| Documents in scope | {fill} |
| Documents out of scope and why | {fill} |
| Round | {fill} |

## Independence method

How correlated review error was limited, stated honestly. A plugin cannot guarantee a different model; what it can guarantee is separate context, and which was used is recorded here.

| Field | Value |
|---|---|
| Passes run | {fill — A, B, C} |
| Execution mode | {fill — separate agent contexts \| external independent model \| single context with reset frames} |
| Model per pass | {fill} |
| Did any pass read another pass's findings before producing its own | {fill — no \| yes, with explanation} |
| External audit performed | {fill — yes, by {fill} \| no} |
| Residual correlation risk | {fill} |

## Checks performed

| Check | Method | Scope | Result | Evidence |
|---|---|---|---|---|
| Canonical file presence | {fill} | 23 files | {fill} | {fill} |
| Header completeness | {fill} | {fill} | {fill} | {fill} |
| Contract pointer resolution | {fill} | {fill} | {fill} | {fill} |
| Internal link resolution | {fill} | {fill} | {fill} | {fill} |
| Diagram syntax | {fill} | {fill} | {fill} | {fill} |
| Diagram versus inventory agreement | {fill} | {fill} | {fill} | {fill} |
| Evidence citation coverage | {fill} | {fill} | {fill} | {fill} |
| Ledger locator resolution | {fill} | {fill} | {fill} | {fill} |
| Public claim mapping | {fill} | {fill} | {fill} | {fill} |
| Secret and sensitive-material scan | {fill} | {fill} | {fill} | {fill} |
| Command and example execution | {fill} | {fill} | {fill} | {fill} |
| Terminology consistency | {fill} | {fill} | {fill} | {fill} |
| Cross-document fact agreement | {fill} | {fill} | {fill} | {fill} |

| Check not executed | Why | What it would have established |
|---|---|---|
| {fill} | {fill} | {fill} |

## Claim sample

| Field | Value |
|---|---|
| Claim categories audited at 100% | {fill} |
| Sampling method for remaining claims | {fill} |
| Sample size | {fill} |
| Population size | {fill} |
| Defect rate found in the sample | {fill} |
| What the sample can and cannot detect | {fill} |

## Scorecard

| Dimension | Weight | Score | Percent of available | Deductions cite |
|---|---:|---:|---:|---|
| Evidence grounding and freshness | 18 | {fill} | {fill} | {fill} |
| Coverage and completeness | 12 | {fill} | {fill} | {fill} |
| Technical correctness | 15 | {fill} | {fill} | {fill} |
| Cross-document consistency | 10 | {fill} | {fill} | {fill} |
| Due-diligence decision value | 10 | {fill} | {fill} | {fill} |
| Onboarding and operability | 10 | {fill} | {fill} | {fill} |
| Security, privacy, and disclosure safety | 10 | {fill} | {fill} | {fill} |
| Reliability and verification depth | 5 | {fill} | {fill} | {fill} |
| Public usefulness and claim integrity | 5 | {fill} | {fill} | {fill} |
| Clarity and maintainability | 5 | {fill} | {fill} | {fill} |
| **Total** | **100** | {fill} | | |

Every deduction cites at least one finding ID.

| Field | Value |
|---|---|
| Score before corrections | {fill} |
| Score after corrections | {fill} |

## Release gate

| Condition | Result | Evidence |
|---|---|---|
| Total score at least the configured minimum | {fill} | {fill} |
| Every dimension at or above its minimum percent | {fill} | {fill} |
| No unresolved critical or high finding | {fill} | {fill} |
| No unsupported or unapproved public claim | {fill} | {fill} |
| Every required human approval recorded | {fill} | {fill} |
| No secret, credential, personal data, or prohibited disclosure present | {fill} | {fill} |
| No contradiction that could materially mislead a decision | {fill} | {fill} |
| Canonical document and section coverage complete, including justified `N/A` | {fill} | {fill} |
| Every material internal claim has a state and a locator | {fill} | {fill} |
| Every public claim maps to approved `V` or `C` evidence | {fill} | {fill} |
| Internal links, paths, and diagram syntax validate | {fill} | {fill} |
| Commands and examples executed or marked not executed | {fill} | {fill} |
| Planned behaviour not presented as implemented | {fill} | {fill} |
| Targets not presented as measured results | {fill} | {fill} |
| Policies not presented as implemented controls | {fill} | {fill} |
| Unresolved uncertainty and source limitations visible | {fill} | {fill} |

The gate is conjunctive. A high score does not carry a failed condition.

## Findings

| Finding ID | Severity | Pass | Audience affected | File and section | Problem | Evidence | Why it matters | Required correction | Evidence still needed | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill — critical \| high \| medium \| low} | {fill — A \| B \| C \| multiple} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill — open \| corrected \| accepted risk \| blocked} |

| Severity | Found | Corrected | Open | Accepted | Blocked |
|---|---:|---:|---:|---:|---:|
| Critical | {fill} | {fill} | {fill} | {fill} | {fill} |
| High | {fill} | {fill} | {fill} | {fill} | {fill} |
| Medium | {fill} | {fill} | {fill} | {fill} | {fill} |
| Low | {fill} | {fill} | {fill} | {fill} | {fill} |

## Corrections applied

| Finding ID | Document | Change made | Re-checked | Result |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Unresolved findings

| Finding ID | Severity | Why it remains open | What would close it | Owner |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Cross-document consistency

| Subject checked | Documents compared | Agreed | Discrepancy | Resolution |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Disclosure and secret safety

| Check | Scope | Result | Detail |
|---|---|---|---|
| Secret patterns in the package | {fill} | {fill} | {fill} |
| Internal identifiers in `06-public/**` | {fill} | {fill} | {fill} |
| Internal paths or names in `06-public/**` | {fill} | {fill} | {fill} |
| Unapproved claims in `06-public/**` | {fill} | {fill} | {fill} |
| Prohibited words used without scope | {fill} | {fill} | {fill} |
| Vulnerability or exploit detail | {fill} | {fill} | {fill} |

Findings name the file and the nature of the problem. They never reproduce the matched value.

## Mechanics validation

| Item | Checked | Passed | Failed | Detail |
|---|---:|---:|---:|---|
| Internal links | {fill} | {fill} | {fill} | {fill} |
| Contract pointers | {fill} | {fill} | {fill} | {fill} |
| Commands | {fill} | {fill} | {fill} | {fill} |
| Examples | {fill} | {fill} | {fill} | {fill} |
| Diagrams | {fill} | {fill} | {fill} | {fill} |

## Residual uncertainty

| Uncertainty | Affects | Why it could not be resolved | Consequence of relying on the package anyway |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Package status

| Field | Value |
|---|---|
| Status | {fill — release-ready \| conditionally ready \| not ready} |
| Blockers, if any | {fill} |

## Next actions

| Rank | Action | Owner | Evidence required | Unblocks |
|---:|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |
