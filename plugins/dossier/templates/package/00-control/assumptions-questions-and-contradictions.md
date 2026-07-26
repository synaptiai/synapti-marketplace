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
# Assumptions, Open Questions, and Contradictions
<!-- contract: references/package-contract-00-control.md#assumptions-questions-and-contradictions -->

## Method

Two registers. `AQ-####` holds assumptions the package relies on and questions that must be answered; `CT-####` holds disagreements between sources. Column definitions and identifier grammar are in the plugin reference `references/register-schemas.md`.

A contradiction is never resolved by choosing the convenient side. Both sides are recorded with their evidence and authority level, the decision impact is named, and the row stays `unresolved` until evidence settles it or scoping makes both true. While a contradiction is open, both underlying evidence rows drop to at most `R`.

## Assumptions and open questions

| ID | Kind | Statement | Why it matters | Working position | Evidence needed | Proposed owner | Blocking | Affected docs | Due | Status | Resolution |
|---|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Contradictions

| ID | Claim A | Claim B | Likely cause | Decision impact | Resolution | Resolution basis | Owner | Next verification | Affected docs |
|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Blocking decisions

Items where documentation would materially mislead a reader until someone decides. Each names the decision, not just the gap.

| ID | Decision required | Who must decide | What is blocked | Consequence of proceeding without it | Deadline |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Recommended evidence requests

Ordered by decision impact, highest first — this is a reading order for the person who can produce the evidence, so it is deliberately not ordered by ID.

| Rank | Request | Smallest sufficient artifact | Resolves | Decision unblocked | Asked of |
|---:|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — AQ/CT IDs} | {fill} | {fill} |

## Open items summary

| Measure | Count |
|---|---|
| Open assumptions | {fill} |
| Open questions | {fill} |
| Open `blocking` items | {fill} |
| Unresolved contradictions | {fill} |
| Items with no proposed owner | {fill} |
| Items past due | {fill} |

Any open `blocking` item, and any unresolved contradiction that could materially mislead a diligence, onboarding, integration, operational, security, or customer decision, fails the release gate regardless of package score.
