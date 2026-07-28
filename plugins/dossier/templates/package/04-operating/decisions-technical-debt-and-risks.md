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
# Decisions, Technical Debt, and Risks
<!-- contract: references/package-contract-04-operating.md#decisions-technical-debt-and-risks -->

Historical rationale is recorded only where evidence of it exists. Where no record exists, the rationale is `unknown` — which is itself information for anyone considering reversing the decision.

## Decision log

| ID | Decision | Date | Status | Record | Rationale state | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — active \| superseded \| reversed} | {fill} | {fill — recorded \| unknown} | {fill} |

### Recorded rationale and alternatives

Only decisions whose rationale is evidenced appear here.

| Decision | Chosen because | Alternatives considered | Why rejected | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

### Decisions with no recorded rationale

| Decision | What is visible | What is unknown | Risk of reversing blind |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Unresolved decisions

| ID | Decision needed | Options | Blocked by | Decides | Deadline | Consequence of not deciding |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Technical debt register

| ID | Debt | Location | Introduced | Why it exists | Interest paid | Remediation | Effort basis | Owner | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — what it costs per unit of work today} | {fill} | {fill} | {fill} | {fill} |

"Interest paid" is what makes a debt register actionable — debt that costs nothing today ranks below debt that taxes every change.

## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill — product \| architecture \| delivery \| security \| privacy \| reliability \| data \| AI \| dependency \| cost \| licensing \| staffing \| operational} | {fill} | {fill} | {fill — how soon it would be noticed} | {fill} | {fill} | {fill} | {fill} | {fill — open \| mitigating \| accepted \| closed} |

Every category above is represented or explicitly marked `N/A` with a reason. A register missing a whole category usually means the category was not examined, not that it holds no risk.

`bin/dossier-gate.sh`'s G19 condition reads this table mechanically for `dependency`/`security` rows citing a vulnerability finding (`[EV-####]` in `Evidence`). Cells here carry no raw `|` character — the same constraint `references/evidence-ledger-schema.md` and `dossier-ledger-lint.sh` already apply to the evidence ledger's own table.

## Risk dependencies

Risks that compound. This is where a set of individually-moderate risks becomes a material one.

| Risk | Depends on / amplified by | Combined effect |
|---|---|---|
| {fill} | {fill} | {fill} |

## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

Acceptance requires a named human with the authority to accept. A risk recorded as accepted with no named accepter is an open risk. `Risk ID` cites the finding this row disposes (`[EV-####]`); cells carry no raw `|` character, per the Risk register's note above.

## Remediation roadmap

| Horizon | Item | Addresses | Kind | Effort basis | Owner |
|---|---|---|---|---|---|
| Immediate | {fill} | {fill} | {fill — risk reduction \| capability investment \| optional improvement} | {fill} | {fill} |
| Near-term | {fill} | {fill} | {fill} | {fill} | {fill} |
| Strategic | {fill} | {fill} | {fill} | {fill} | {fill} |

The `Kind` column is required. Risk reduction, capability investment, and optional improvement compete for the same capacity and are routinely conflated; separating them is what lets a reader judge the roadmap rather than accept it.
