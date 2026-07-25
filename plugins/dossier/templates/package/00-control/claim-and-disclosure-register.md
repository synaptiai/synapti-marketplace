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
# Claim and Disclosure Register
<!-- contract: references/package-contract-00-control.md#claim-and-disclosure-register -->

## Method

Every sentence in `06-public/**` that makes a claim maps to one `approved` row below, matching its `Proposed wording` verbatim. Column definitions and identifier grammar are in the plugin reference `references/register-schemas.md`.

The package cannot approve its own claims. Where human approval is required by the disclosure policy and has not been recorded, `Status` is `pending` and the sentence does not ship. Zero unsupported public claims is a release gate.

**Disclosure policy in force:** {fill}

**Approval authority:** {fill — who may approve each claim type, or `not-required` where the policy says so}

## Public claim inventory

| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |
|---|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Required qualifications

Approved claims whose wording is only true with an accompanying condition. The condition must appear in the public document adjacent to the claim, not in a footnote a reader can miss.

| Claim ID | Qualification that must accompany it | Where it appears |
|---|---|---|
| {fill} | {fill} | {fill} |

## Rejected and withdrawn claims

Kept so a future drafter does not re-propose them.

| ID | Wording | Reason declined | Date | What would make it publishable |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Confidentiality and disclosure risks

Material the package holds that must not reach a public document, and the specific way it could leak.

| Risk | Material at risk | Leak path | Control | Owner |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Mapping to public documents

Both public documents, claim by claim. A sentence in either file with no row here is a gate failure.

### `06-public/technical-partner-guide.md`

| Section | Claim ID | Status |
|---|---|---|
| {fill} | {fill} | {fill} |

### `06-public/customer-product-and-trust-guide.md`

| Section | Claim ID | Status |
|---|---|---|
| {fill} | {fill} | {fill} |

## Register summary

| Measure | Count |
|---|---|
| Total claims | {fill} |
| Approved | {fill} |
| Pending | {fill} |
| Rejected or withdrawn | {fill} |
| Approved claims resting on a state other than `V` or `C` | {fill — must be 0} |
| Sentences in `06-public/**` with no matching row | {fill — must be 0} |
