---
dossier-header: internal-v1
title: Documentation Index
purpose: Routes a reader to the one document that answers their question, and states up front how much the package is worth.
audience: Reviewer, Maintainer, Contributor, Installing operator
confidentiality: Public
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: Any document is added, removed, or re-verified; the gate verdict changes
related: []
---
# Documentation Index
<!-- contract: references/package-contract-00-control.md#documentation-index -->

## Package version and verification

| Field | Value |
|---|---|
| Package version | 1.1.0 |
| Project version or commit | `7ee4923` on `docs/dossier-refresh` — the last commit that changed the project rather than the documentation |
| Evidence cutoff date | 2026-09-10 |
| Delivery mode | full |
| Last full verification | 2026-09-10, round 4 |
| Last gate verdict | **Not yet issued for this package.** Round 4's three passes returned 58.0, 64.4 and 62.9 against a floor of 95, and none met the per-dimension minimum. No pass issued a verdict and `/dossier:audit` does not compute one. See `07-verification/documentation-verification-report.md` |

Round 4 is the first round audited against this refresh rather than against the July package. Its three passes produced 52 raw findings, 31 after deduplication, six of them Critical. Two were reported independently by all three passes.

The first is this file. It was re-stamped to a current date and `status: verified` in commit `c9b2a24` while its body still described the July package — 56 evidence rows against 193, 35 approved claims against 33, a 17-condition gate against 19, and a canonical table in which 75 of 115 cells disagreed with the headers they claimed to summarise. The body below is now derived from the headers, the ledger and the register rather than maintained by hand, which is the only form that does not drift again.

The second is the public projection: sentences in `06-public/**` that map to no approved row in the claim register. That finding is open, not corrected — it needs approver action, and the control that should have caught it cannot see bullets or table cells (issue #176).

**Read the round-4 findings table before relying on any document here.** It is the honest statement of what this package is worth today.

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

Generated from each document's own header block. `document-headers.md` makes the header authoritative, so this table is a projection of the headers and never a second source for them.

| Path | Purpose | Owner | Audience | Confidentiality | Status | Last verified |
|---|---|---|---|---|---|---|
| `00-control/assumptions-questions-and-contradictions.md` | What rests on something unresolved | Daniel Bentes | Reviewer, Maintainer | Public | partially verified | 2026-09-10 |
| `00-control/claim-and-disclosure-register.md` | What may be said publicly, and on whose approval | Daniel Bentes | Maintainer, Reviewer | Public | partially verified | 2026-09-10 |
| `00-control/documentation-index.md` | This file — routing and package status | Daniel Bentes | Reviewer, Maintainer, Contributor, Installing operator | Public | partially verified | 2026-09-10 |
| `00-control/evidence-ledger.md` | Every material claim's grounding | Daniel Bentes | Reviewer, Maintainer, Installing operator | Public | verified | 2026-09-10 |
| `00-control/terminology-and-ownership.md` | One name per thing; who owns each part | Daniel Bentes | Reviewer, Maintainer, Contributor | Public | verified | 2026-09-10 |
| `01-project/executive-project-brief.md` | The whole shape in one read | Daniel Bentes | Reviewer, Maintainer, Prospective contributor | Internal | partially verified | 2026-09-10 |
| `01-project/product-and-domain.md` | Who it serves, and where stated meets implemented | Daniel Bentes | Maintainer, Reviewer, Prospective contributor | Internal | partially verified | 2026-09-10 |
| `02-architecture/components-and-codebase.md` | Where to place a change | Daniel Bentes | Contributor, Maintainer, Reviewer | Public | partially verified | 2026-09-10 |
| `02-architecture/data-and-ai.md` | What data exists, and what AI behaviour is induced | Daniel Bentes | Reviewer, Installing operator, Maintainer | Internal | partially verified | 2026-09-10 |
| `02-architecture/infrastructure-and-deployment.md` | What stands between a keystroke and every installer | Daniel Bentes | Reviewer, Maintainer | Internal | partially verified | 2026-09-10 |
| `02-architecture/interfaces-and-integrations.md` | The contracts, and which are stable | Daniel Bentes | Contributor, Installing operator, Reviewer | Internal | partially verified | 2026-09-10 |
| `02-architecture/system-architecture.md` | Trust boundaries and control flow | Daniel Bentes | Reviewer, Installing operator, Maintainer | Internal | partially verified | 2026-09-10 |
| `03-assurance/reliability-performance-and-observability.md` | What can fail, and who would notice | Daniel Bentes | Reviewer, Maintainer, Installing operator | Internal | partially verified | 2026-09-10 |
| `03-assurance/security-privacy-and-compliance.md` | Threat model, controls, and gaps | Daniel Bentes | Reviewer, Installing operator, Maintainer | Internal | partially verified | 2026-09-10 |
| `03-assurance/testing-quality-and-delivery.md` | What the passing numbers actually earn | Daniel Bentes | Reviewer, Contributor, Maintainer | Internal | partially verified | 2026-09-10 |
| `04-operating/decisions-technical-debt-and-risks.md` | Ranked risks, debt, and what was never decided | Daniel Bentes | Maintainer, Reviewer | Internal | partially verified | 2026-09-10 |
| `04-operating/onboarding-and-local-development.md` | Clone to verified change | Daniel Bentes | Contributor, Maintainer | Internal | partially verified | 2026-09-10 |
| `04-operating/operations-and-incident-response.md` | What happens when it breaks on someone else's machine | Daniel Bentes | Maintainer, Reviewer, Installing operator | Internal | partially verified | 2026-09-10 |
| `05-due-diligence/assets-dependencies-and-licenses.md` | What is owned, what is borrowed, on what terms | Daniel Bentes | Reviewer, Maintainer | Internal | partially verified | 2026-09-10 |
| `05-due-diligence/technical-due-diligence-report.md` | The verdict and its conditions | Daniel Bentes | Reviewer, Maintainer | Internal | partially verified | 2026-09-10 |
| `06-public/customer-product-and-trust-guide.md` | Decide whether to install | Daniel Bentes | Operators deciding whether to install | Public | derived | 2026-09-10 |
| `06-public/technical-partner-guide.md` | Build against it without reading the source | Daniel Bentes | Plugin authors, integrators, and operators evaluating the marketplace | Public | derived | 2026-09-10 |
| `07-verification/documentation-verification-report.md` | How much this package's own claims are worth | Daniel Bentes | Reviewer, Maintainer | Public | partially verified | 2026-07-26 |

## Evidence coverage

| Measure | Value |
|---|---|
| Evidence rows | 193 |
| Rows defined but cited nowhere outside the ledger | 27 |
| Dangling citations | 0 — every `EV-####` referenced in the package resolves to a row (`dossier-ledger-lint.sh`) |
| Rows in a refuted state | 4 — EV-0035, EV-0041, EV-0044 and their dependents, each retained with a successor named rather than deleted |
| Source classes inspected | Source trees, plugin and marketplace manifests, CI definitions, live GitHub settings, history and releases, existing documentation, the Claude Code client's own install state, both test suites executed locally |
| Source classes unavailable | Install telemetry (does not exist), any Windows environment, dependency-vulnerability scanning (never run) |

The 27 uncited rows are not a defect on their own — a ledger row records an observation, and not every observation earns a sentence. They are listed here because the previous version of this table claimed that "every row defined is cited", which was false, and because an uncited row is the first thing to check when pruning.

Per-document citation counts are deliberately **not** reproduced here. The previous version carried them and every one was wrong — the executive brief was recorded at 24 against 49, the security document at 27 against 76. A count that must be maintained by hand against 23 files drifts silently, and `grep -o 'EV-[0-9]\{4\}' <file> | sort -u | wc -l` answers the question on demand without a second copy to go stale.

## Unresolved critical items

| ID | Item | Impact if wrong | Owner | Affected documents |
|---|---|---|---|---|
| R4-02 | Claim-bearing sentences in both public guides map to no approved register row | The package's central structural claim, CL-0031, is false where it is printed | Daniel Bentes | `06-public/**`, `00-control/claim-and-disclosure-register.md` |
| R4-06 | CL-0046 is false at `v4.10.0`, the product version both guides advertise | An approved public claim describing a CI check that does not exist in the released tree | Daniel Bentes | `06-public/**` |
| R4-07 | The action ceiling was inert for this entire engagement — both hooks exit 0 without `.scope.json`, which is gitignored and absent | Every containment assurance in the package describes a control that was not running | Daniel Bentes | `03-assurance/security-privacy-and-compliance.md` |
| AQ-0002 | dossier's post-merge automation has never executed end to end | A published plugin's headline capability rests on unit tests of its parts | Daniel Bentes | `03-assurance`, `04-operating`, `05-due-diligence`, `06-public` |
| AQ-0032 | PyYAML and `jsonschema` are undeclared runtime requirements; a missing PyYAML silently opens the FlowGoal gate | An operator's enforcement gate approves everything and says nothing | Daniel Bentes | `02-architecture`, `03-assurance`, `04-operating`, `05-due-diligence` |
| F-05 | The verification passes share a model | Round 4 bought independent context, not independent judgment. `--external` was not run | Daniel Bentes | `07-verification/documentation-verification-report.md` |

AQ-0011 was carried here as unresolved through six rounds and is now closed: `LICENSE` reached `main` on 2026-07-26 and the GitHub API reports `Apache-2.0` [EV-0132].

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
| 2026-07-26 | 1.0.2 | all 23 | Round 4 of the July sequence: an external review found five containment defects in the plugin this package documents. Re-pinned to `06b1586` |
| 2026-07-26 | 1.0.3 | all 23 | Round 5: round 4's own action-ceiling fix still admitted `timeout N <command>` |
| 2026-07-26 | 1.0.4 | all 23 | Round 6: three findings attacked the gate's own integrity, including a verdict shape that let a judgment condition disappear from both counters |
| 2026-09-10 | 1.1.0 | 21 of 23 | Targeted refresh over `7e4a097..7ee4923`. The evidence ledger grew from 97 rows to 193; three repository defects were found and fixed in the tree rather than documented around it; ten superseded public claims were replaced, ten approved and two deliberately held. Both public guides re-derived. An independent three-pass audit then returned 31 reconciled findings, six Critical, and its pre-repair table is published in `07-verification/` before any of it was corrected |

## Supplemental documents

| Path | Why it exists | Extends | Owner |
|---|---|---|---|
| `README.md` at the package root | A reader browsing this directory lands on eight numbered folders and never reaches this index. The signpost points here. It states no fact about the project — no counts, dates, or verdict — so it cannot go stale | This file | Daniel Bentes |
| `.claude/settings.dossier.json` | The engagement configuration this package was produced under — scope, action ceiling, disclosure policy | The whole package | Daniel Bentes |
| `README.md` at the repository root | The storefront a prospective operator reads first | `06-public` | Daniel Bentes |
| `plugins/dossier/references/` | The package contract each document is written against | All 23 documents, via their contract pointers | Daniel Bentes |
