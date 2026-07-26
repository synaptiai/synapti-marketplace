---
dossier-header: internal-v1
title: Documentation Index
purpose: Routes a reader to the one document that answers their question, and states up front how much the package is worth.
audience: Reviewer, Maintainer, Contributor, Installing operator
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: fbeb1ee
last-verified: 2026-07-26
review-trigger: Any document is added, removed, or re-verified; the gate verdict changes
related: []
---
# Documentation Index
<!-- contract: references/package-contract-00-control.md#documentation-index -->

## Package version and verification

| Field | Value |
|---|---|
| Package version | 1.0.1 |
| Project version or commit | `fbeb1ee` on `feature/dossier-documentation-plugin` — **not `main`** |
| Evidence cutoff date | 2026-07-26 |
| Delivery mode | full |
| Last full verification | 2026-07-26 |
| Last gate verdict | **NOT-RELEASABLE** — 2 of 17 conditions fail after round 3, down from 4 in round 1; see `07-verification/documentation-verification-report.md` |

The verdict is the package working as intended. Round 1 failed four conditions; two were closed by fixing the underlying facts — the repository is now licensed under Apache-2.0, and every public sentence maps to an approved claim. The two that remain are both score conditions, and both trace to a single cause: this run's verification passes were not independent of one another. No edit to the package can close them; only a genuinely independent re-run can.

Round 3 lowered the score from 92 to 87 rather than raising it. It re-derived every headline figure from the commit under review instead of from the ledger and found five defects two earlier rounds had certified past — a pin naming a commit at which the licence did not exist, six stale counts, three contract-requested diagrams never drawn, a ledger contradicting itself, and a ranked table missing its first row. All are corrected. The score fell because the earlier number had been measuring how hard the reviewer looked.

## Reader routes

| Reader | Route | First question answered |
|---|---|---|
| Technical due diligence | `05-due-diligence/technical-due-diligence-report.md` → `04-operating/decisions-technical-debt-and-risks.md` → `05-due-diligence/assets-dependencies-and-licenses.md` | Is this fit to depend on, and what would it cost to make it so |
| Engineering onboarding | `04-operating/onboarding-and-local-development.md` → `02-architecture/components-and-codebase.md` | How do I make a verified change today |
| Product onboarding | `01-project/executive-project-brief.md` → `01-project/product-and-domain.md` | What is this, who is it for, and what does it promise that it does not deliver |
| Design | N/A — the project renders no interface. `01-project/product-and-domain.md` states why | — |
| Data / AI | `02-architecture/data-and-ai.md` | What data exists (none) and what AI behaviour this induces in someone else's session |
| Operators | `04-operating/operations-and-incident-response.md` → `02-architecture/infrastructure-and-deployment.md` | What breaks, and who would know |
| Security and privacy reviewers | `03-assurance/security-privacy-and-compliance.md` → `02-architecture/system-architecture.md` | Should I let this execute on my machine |
| Technical partners | `06-public/technical-partner-guide.md` | What can I build against, and what will not hold still |
| Customers | `06-public/customer-product-and-trust-guide.md` | What am I installing, and what does it do to my machine |

## Canonical documents

| Path | Purpose | Owner | Audience | Confidentiality | Status | Last verified |
|---|---|---|---|---|---|---|
| `00-control/documentation-index.md` | This file — routing and package status | Daniel Bentes | all | Public | verified | 2026-07-26 |
| `00-control/evidence-ledger.md` | Every material claim's grounding | Daniel Bentes | Reviewer, Maintainer | Public | verified | 2026-07-26 |
| `00-control/assumptions-questions-and-contradictions.md` | What rests on something unresolved | Daniel Bentes | Reviewer, Maintainer | Public | verified | 2026-07-26 |
| `00-control/claim-and-disclosure-register.md` | What may be said publicly, and on whose approval | Daniel Bentes | Maintainer, Reviewer | Public | verified | 2026-07-26 |
| `00-control/terminology-and-ownership.md` | One name per thing; who owns each part | Daniel Bentes | Reviewer, Maintainer, Contributor | Public | verified | 2026-07-26 |
| `01-project/executive-project-brief.md` | The whole shape in one read | Daniel Bentes | Reviewer, Maintainer | Public | verified | 2026-07-26 |
| `01-project/product-and-domain.md` | Who it serves, and where stated meets implemented | Daniel Bentes | Maintainer, Reviewer | Public | verified | 2026-07-26 |
| `02-architecture/system-architecture.md` | Trust boundaries and control flow | Daniel Bentes | Reviewer, Operator, Maintainer | Public | verified | 2026-07-26 |
| `02-architecture/components-and-codebase.md` | Where to place a change | Daniel Bentes | Contributor, Maintainer | Public | verified | 2026-07-26 |
| `02-architecture/data-and-ai.md` | What data exists, and what AI behaviour is induced | Daniel Bentes | Reviewer, Operator | Public | verified | 2026-07-26 |
| `02-architecture/interfaces-and-integrations.md` | The contracts, and which are stable | Daniel Bentes | Contributor, Operator | Public | verified | 2026-07-26 |
| `02-architecture/infrastructure-and-deployment.md` | What stands between a keystroke and every installer | Daniel Bentes | Reviewer, Maintainer | Public | verified | 2026-07-26 |
| `03-assurance/security-privacy-and-compliance.md` | Threat model, controls, and gaps | Daniel Bentes | Reviewer, Operator | Public | verified | 2026-07-26 |
| `03-assurance/reliability-performance-and-observability.md` | What can fail, and who would notice | Daniel Bentes | Reviewer, Maintainer | Public | verified | 2026-07-26 |
| `03-assurance/testing-quality-and-delivery.md` | What the passing numbers actually earn | Daniel Bentes | Reviewer, Contributor | Public | verified | 2026-07-26 |
| `04-operating/onboarding-and-local-development.md` | Clone to verified change | Daniel Bentes | Contributor | Public | verified | 2026-07-26 |
| `04-operating/operations-and-incident-response.md` | What happens when it breaks on someone else's machine | Daniel Bentes | Maintainer, Operator | Public | verified | 2026-07-26 |
| `04-operating/decisions-technical-debt-and-risks.md` | Ranked risks, debt, and what was never decided | Daniel Bentes | Maintainer, Reviewer | Public | verified | 2026-07-26 |
| `05-due-diligence/technical-due-diligence-report.md` | The verdict and its conditions | Daniel Bentes | Reviewer | Public | verified | 2026-07-26 |
| `05-due-diligence/assets-dependencies-and-licenses.md` | What is owned, what is borrowed, on what terms | Daniel Bentes | Reviewer | Public | verified | 2026-07-26 |
| `06-public/technical-partner-guide.md` | Build against it without reading the source | Daniel Bentes | Partners, integrators | Public | verified | 2026-07-26 |
| `06-public/customer-product-and-trust-guide.md` | Decide whether to install | Daniel Bentes | Operators | Public | verified | 2026-07-26 |
| `07-verification/documentation-verification-report.md` | How much this package's own claims are worth | Daniel Bentes | Reviewer, Maintainer | Public | verified | 2026-07-26 |

## Evidence coverage

| Measure | Value |
|---|---|
| Evidence rows | 56 |
| Material claims with no evidence row | 0 — every `EV-####` referenced resolves, and every row defined is cited |
| Rows past their freshness expiry | 0 — all observed 2026-07-26 |
| Source classes inspected | Source trees, plugin and marketplace manifests, CI definitions, live GitHub settings and history, existing documentation, the Claude Code client's own install state |
| Source classes unavailable | Install telemetry (does not exist), the `prompt-decorators` source, submodule history past the pin, any Windows environment |

| Document | Rows cited | Weakest state carrying decision weight | Note |
|---|---|---|---|
| `00-control/evidence-ledger.md` | 56 | `I` | One row, EV-0043, with its inference chain stated |
| `01-project/executive-project-brief.md` | 24 | `V` | Unknowns are named as unknowns rather than weighted |
| `01-project/product-and-domain.md` | 26 | `R` | The decipon capability row, attributed to its own description |
| `02-architecture/system-architecture.md` | 30 | `I` | EV-0043 in the tradeoffs table, labelled |
| `02-architecture/components-and-codebase.md` | 22 | `V` | — |
| `02-architecture/data-and-ai.md` | 21 | `V` | — |
| `02-architecture/interfaces-and-integrations.md` | 24 | `V` | — |
| `02-architecture/infrastructure-and-deployment.md` | 21 | `V` | — |
| `03-assurance/security-privacy-and-compliance.md` | 27 | `V` | — |
| `03-assurance/reliability-performance-and-observability.md` | 18 | `V` | Three unverified performance assumptions are labelled as assumptions, not cited as evidence |
| `03-assurance/testing-quality-and-delivery.md` | 20 | `V` | — |
| `04-operating/onboarding-and-local-development.md` | 17 | `V` | — |
| `04-operating/operations-and-incident-response.md` | 16 | `V` | — |
| `04-operating/decisions-technical-debt-and-risks.md` | 25 | `U` | Three decision rows record an unknown rationale rather than reconstructing one |
| `05-due-diligence/technical-due-diligence-report.md` | 28 | `I` | — |
| `05-due-diligence/assets-dependencies-and-licenses.md` | 19 | `V` | — |
| `06-public/**` | 0 direct | `V` only | Public documents cite no identifiers by design; every sentence traces through the claim register, and all 35 approved claims rest on `V` rows |
| `07-verification/documentation-verification-report.md` | 8 | `V` | — |

## Unresolved critical items

| ID | Item | Impact if wrong | Owner | Affected documents |
|---|---|---|---|---|
| AQ-0011 | GitHub's derived licence field still reports `null` | Only the badge and automated scanners; the licence itself is in place | Daniel Bentes | `05-due-diligence/assets-dependencies-and-licenses.md`, `06-public/customer-product-and-trust-guide.md` |
| AQ-0002 | dossier's post-merge automation has never executed | A published plugin's headline capability rests on unit tests of its parts | Daniel Bentes | `03-assurance`, `04-operating`, `05-due-diligence`, `06-public` |
| F-05 | The three verification passes were not independent | Every judgment finding in this package is one reviewer's opinion, not three | Daniel Bentes | `07-verification/documentation-verification-report.md` |

## Document dependencies and sources of truth

| Subject | Source of truth | Documents that link to it |
|---|---|---|
| Every material claim's grounding | `00-control/evidence-ledger.md` | all 21 internal documents |
| Canonical names and ownership | `00-control/terminology-and-ownership.md` | `01-project`, `02-architecture`, `04-operating` |
| What may be said publicly | `00-control/claim-and-disclosure-register.md` | `06-public` |
| Open questions and contradictions | `00-control/assumptions-questions-and-contradictions.md` | `01-project`, `04-operating`, `05-due-diligence`, `07-verification` |
| Trust boundaries | `02-architecture/system-architecture.md` | `03-assurance/security-privacy-and-compliance.md`, `06-public` |
| Risks and remediation | `04-operating/decisions-technical-debt-and-risks.md` | `05-due-diligence/technical-due-diligence-report.md` |
| Verification result | `07-verification/documentation-verification-report.md` | this index, `05-due-diligence/technical-due-diligence-report.md` |

## Maintenance

| Policy | Value |
|---|---|
| Review cadence | On change. Each document's own `review-trigger` names the change event that invalidates it |
| Freshness threshold | 90 days, from `refresh.stalenessDays` |
| Refresh triggers | Any change under `plugins/`, `.claude-plugin/marketplace.json`, `.github/workflows/`, `scripts/`, or `README.md`; see each file's `review-trigger` for the document-specific event |
| Archival rule | A superseded package version is superseded in git history. No parallel copy is kept — the history is the archive |
| Refresh mechanism | **Manual today.** `dossier.ci.enabled` is `true` in configuration, but the post-merge workflow has not been scaffolded into this repository and has never executed anywhere (AQ-0002) |

## Change summary

| Date | Package version | Documents changed | Reason |
|---|---|---|---|
| 2026-07-26 | 1.0.0 | all 23 | Initial package, produced by running the dossier plugin against the repository that ships it |
| 2026-07-26 | 1.0.1 | all 23, plus the new `README.md` | Round 3: re-pinned to `fbeb1ee`, six figures re-derived, three requested diagrams drawn, the ledger's internal contradiction closed, the due-diligence ranked tables renumbered, and an entry point added at the package root |

## Supplemental documents

| Path | Why it exists | Extends | Owner |
|---|---|---|---|
| `README.md` at the package root | A reader browsing this directory lands on eight numbered folders and never reaches this index. The signpost points here. It states no fact about the project — no counts, dates, or verdict — so it cannot go stale | This file | Daniel Bentes |
| `.claude/settings.dossier.json` | The engagement configuration this package was produced under — scope, action ceiling, disclosure policy | The whole package | Daniel Bentes |
| `README.md` at the repository root | The storefront a prospective operator reads first | `06-public` | Daniel Bentes |
| `plugins/dossier/references/` | The package contract each document is written against | All 23 documents, via their contract pointers | Daniel Bentes |
