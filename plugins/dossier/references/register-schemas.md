# Register Schemas

Reference document. Table shapes and identifier grammars for the four registers other than the evidence ledger: assumptions and open questions (`AQ-####`), contradictions (`CT-####`), claim and disclosure (`CL-####`), terminology and entities (`TM-####`). The evidence ledger has its own reference at `references/evidence-ledger-schema.md`; claim states and authority levels are defined in `references/source-authority-and-claim-states.md`.

All five registers share these rules:

- **Identifier grammar** is `<PREFIX>-<4 digits>`, zero-padded, assigned in strictly increasing creation order, never reused, never renumbered. Beyond `9999`, widen to five digits rather than restarting.
- **Append-only in identity.** Rows are closed, not deleted. A row that turns out to be wrong is closed with a reason.
- **Every register lives in one file.** `AQ-` and `CT-` share `00-control/assumptions-questions-and-contradictions.md` as two tables under separate headings; `CL-` owns `00-control/claim-and-disclosure-register.md`; `TM-` owns `00-control/terminology-and-ownership.md`.
- **Cross-register references use the bare ID** (`AQ-0007`, `CT-0002`) so a single grep finds every mention across all 23 documents.

## `AQ-####` — assumptions and open questions

One register, two row kinds, distinguished by the `Kind` column. They share an identifier space because an assumption and the question that would settle it are the same item at different confidence levels, and splitting them means renumbering when one becomes the other.

| # | Column | Type | Required content |
|---:|---|---|---|
| 1 | `ID` | `AQ-####` | Stable identifier. |
| 2 | `Kind` | enum | `assumption` — a working position being relied on. `question` — something that must be answered. |
| 3 | `Statement` | string | The assumption or the question, one sentence, answerable or falsifiable. |
| 4 | `Why it matters` | string | The decision or task that changes depending on the answer. Not "for completeness". If nothing changes, the row does not belong in the register. |
| 5 | `Working position` | string | What the package currently assumes and writes as if true, or `none — treated as unknown`. |
| 6 | `Evidence needed` | string | The smallest specific artifact, check, or statement that would settle it. "More information" is not evidence needed; "the output of the last restore rehearsal" is. |
| 7 | `Proposed owner` | string | A named person or team, or `unassigned`. Proposed, because the package cannot assign work. |
| 8 | `Blocking` | enum | `blocking` — documentation would materially mislead without resolution. `material` — can proceed with a visible qualification. `minor` — refinement only. |
| 9 | `Affected docs` | list | Package-relative paths. |
| 10 | `Due` | ISO date | The date by which the answer stops being useful, or `—`. Usually driven by a decision deadline, not by preference. |
| 11 | `Status` | enum | `open` \| `answered` \| `accepted` \| `closed-moot` |
| 12 | `Resolution` | string | On close: the answer, the `EV-####` row it produced, and the date. `—` while open. |

Status rules:

- `answered` — evidence arrived; the row names the `EV-####` it produced and the documents updated.
- `accepted` — the organisation chose to proceed without the evidence. Requires a named accepting owner in `Resolution`; an agent cannot accept a risk on the project's behalf.
- `closed-moot` — the decision it fed went away. Names what changed.
- A `blocking` row at `open` status is a release-gate failure. That is the entire purpose of the `blocking` value: it is not a priority label, it is a gate.

Rows are ordered by decision impact, not by ID, when rendered in the "recommended evidence requests" section — that section is a reading order for a busy owner, and creation order is not decision order.

```markdown
| ID | Kind | Statement | Why it matters | Working position | Evidence needed | Proposed owner | Blocking | Affected docs | Due | Status | Resolution |
|---|---|---|---|---|---|---|---|---|---|---|---|
| AQ-0007 | question | When was the database restore procedure last executed end to end? | Recovery claims in the infrastructure and operations documents currently rest on a stakeholder recollection dated 2025-11-04 [EV-0005]. A diligence reader will treat an untested restore as an unbounded liability. | none — treated as unknown | The runbook output or ticket from the most recent rehearsal, with date and environment. | unassigned | blocking | 02-architecture/infrastructure-and-deployment.md, 04-operating/operations-and-incident-response.md, 05-due-diligence/technical-due-diligence-report.md | — | open | — |
| AQ-0011 | assumption | No third-party service in the request path performs model inference. | Determines whether the AI sections are genuinely N/A and whether a subprocessor disclosure is required. | Assumed true for the codebase; not established for vendor services [EV-0007]. | The current subprocessor list, or vendor terms for the three services in the request path. | unassigned | material | 02-architecture/data-and-ai.md, 03-assurance/security-privacy-and-compliance.md | — | open | — |
```

## `CT-####` — contradictions

One row per disagreement between sources. A contradiction is not a finding about the documentation; it is a fact about the project's evidence, and it survives after the documents are corrected.

| # | Column | Type | Required content |
|---:|---|---|---|
| 1 | `ID` | `CT-####` | Stable identifier. |
| 2 | `Claim A` | string | One side, stated as it appears, with its `EV-####` and authority level. |
| 3 | `Claim B` | string | The other side, same treatment. Additional sides go in `Notes`, not in extra columns. |
| 4 | `Likely cause` | string | Drift, environment difference, version skew, scope mismatch, stale document, genuine disagreement, or `unknown`. Naming the cause is what makes the resolution actionable. |
| 5 | `Decision impact` | string | What a reader would get wrong by believing the wrong side. |
| 6 | `Resolution` | enum | `unresolved` \| `resolved-A` \| `resolved-B` \| `resolved-other` \| `both-scoped` |
| 7 | `Resolution basis` | string | The evidence that settled it, or the scoping that made both true. `—` while unresolved. |
| 8 | `Owner` | string | Named person or team, or `unassigned`. |
| 9 | `Next verification` | string | The specific check that would settle it. Required while `unresolved`. |
| 10 | `Affected docs` | list | Package-relative paths. |

Rules:

- **Never resolve a contradiction by choosing.** Record both sides with their evidence and authority, name the impact, and either verify or escalate. A drafter that picks the convenient side and moves on has destroyed the most valuable signal in the package.
- **While `unresolved`, both underlying `EV-` rows drop to at most `R`.** Neither side keeps `V`.
- **`both-scoped` is a real resolution, not a compromise.** "The API rate-limits at 100 req/min" and "at 1000 req/min" are both true if one is the default tier and the other is enterprise. The resolution is to scope both claims, and both `EV-` rows are rewritten to carry their scope.
- **A contradiction that could materially mislead a diligence, onboarding, integration, operational, security, or customer decision blocks release** while `unresolved`, regardless of the score.

```markdown
| ID | Claim A | Claim B | Likely cause | Decision impact | Resolution | Resolution basis | Owner | Next verification | Affected docs |
|---|---|---|---|---|---|---|---|---|---|
| CT-0002 | The API enforces a 100 req/min limit per client [EV-0018, authority 4 — approved API spec]. | The gateway configuration sets no rate limit for the `partner` plan [EV-0019, authority 2 — IaC at 9f3c1ab]. | Scope mismatch — the spec may describe the default plan only. | A partner sizing an integration against the published 100 req/min figure would either over-engineer backoff or, if the limit is real on their plan and the spec is wrong, be throttled in production with no documented behaviour. | unresolved | — | unassigned | Issue 150 requests against staging on a `partner`-plan credential and record the response codes. | 02-architecture/interfaces-and-integrations.md, 06-public/technical-partner-guide.md |
```

## `CL-####` — claim and disclosure

Every public-facing claim, one row, before the sentence is written into a public document. The register is the source of truth for what may be published; the two files under `06-public/` are projections of its approved rows.

| # | Column | Type | Required content |
|---:|---|---|---|
| 1 | `ID` | `CL-####` | Stable identifier. |
| 2 | `Proposed wording` | string | The **exact sentence** intended for publication, verbatim. Not a summary of it. Approval attaches to wording, and a paraphrase is a different claim. |
| 3 | `Claim type` | enum | `capability` \| `metric` \| `reliability` \| `privacy` \| `security` \| `compliance` \| `compatibility` \| `roadmap` \| `support` |
| 4 | `Evidence` | list | `EV-####` rows supporting it. Every cited row must be `V` or `C`. |
| 5 | `Applicable version` | string | The product version and scope the claim holds for. A claim with no version is unbounded and cannot be approved. |
| 6 | `Scope` | string | Environments, plans, regions, platforms, or configurations the claim covers — and, where it matters, what it excludes. |
| 7 | `Limitations` | string | The conditions that must accompany the wording for it to stay true. If the limitation cannot be stated publicly, the claim cannot be published. |
| 8 | `Approver` | string | The named human with authority to approve this claim type, or `not-required` when `disclosure.publicClaimApproval` is `not-required`. |
| 9 | `Classification` | enum | `Public` \| `Partner-Confidential` \| `Customer-Confidential` \| `Internal` \| `Restricted` — the disclosure level of the claim itself. This enum carries one value the document-header and evidence-ledger enums do not: `Customer-Confidential`, for a claim whose sensitivity belongs to a customer rather than to this project. A document or evidence row never takes that value, because the document's own confidentiality is about who may read the file. |
| 10 | `Destination` | enum | `technical-partner-guide` \| `customer-product-and-trust-guide` \| `both` \| `none` |
| 11 | `Status` | enum | `pending` \| `approved` \| `rejected` \| `withdrawn` |
| 12 | `Decision basis` | string | On `approved`: approver and date. On `rejected` / `withdrawn`: the reason and the date. `—` while pending. |

Rules:

- **No public sentence without an `approved` row.** Every sentence in `06-public/**` that makes a claim maps to a `CL-` row whose `Proposed wording` it matches. `bin/dossier-claim-scan.sh` enforces this mechanically.
- **The package cannot approve its own claims.** A drafting or verifying agent may not set `Status: approved` and may not name itself in `Approver`. Where human approval is required and has not been recorded, the status is `pending` and the sentence does not ship. A user-provided disclosure policy may be applied; it does not make the agent the business, legal, security, privacy, or communications approver.
- **Rejected and withdrawn rows stay.** They are the record of what was considered and declined, which is exactly what a future drafter needs in order not to re-propose it.
- **Zero unsupported public claims is a release gate.** A `pending` row with a matching sentence already in a public document is a gate failure, not a warning.
- **Wording changes reset approval.** Editing an approved sentence returns it to `pending` unless the edit is a pure typographical fix recorded in `Decision basis`.
- **Roadmap claims are held to the same bar.** "Planned" wording must be unmistakably future-tense and must carry no date unless a committed date exists and is approved.

```markdown
| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |
|---|---|---|---|---|---|---|---|---|---|---|---|
| CL-0004 | "The API authenticates using OAuth 2.0 client credentials; requests without a valid token receive a 401 response." | capability | EV-0001, EV-0002 | 2.4 | Public `/v1` endpoints, all plans | Does not describe the internal admin routes, which are not part of the public surface. | unassigned | Public | technical-partner-guide | pending | — |
| CL-0009 | "Typical response times are under 250 milliseconds." | metric | EV-0003, EV-0004 | 2.4 | — | Rejected: EV-0003 is a 7-day p99 on one endpoint in one environment; EV-0004 is an internal objective. The wording generalises both into a customer-facing expectation neither supports. | unassigned | Public | customer-product-and-trust-guide | rejected | Objective presented as measured result; internal objective presented as a customer expectation. 2026-07-24. |
```

`CL-0009` is the canonical rejection shape: the evidence exists and is good, and the claim is still not publishable, because the wording travels further than the evidence.

## `TM-####` — terminology, entities, and ownership

The canonical name for everything the package names. Every document draws its vocabulary from here; a term used in two documents with two meanings is a cross-document consistency failure that this register exists to prevent.

| # | Column | Type | Required content |
|---:|---|---|---|
| 1 | `ID` | `TM-####` | Stable identifier. |
| 2 | `Canonical name` | string | The one name used everywhere in the package, spelled and cased exactly as it should appear. |
| 3 | `Class` | enum | `product` \| `project` \| `component` \| `service` \| `module` \| `repository` \| `package` \| `role` \| `environment` \| `deployment-unit` \| `external-system` \| `partner` \| `data-class` \| `domain-entity` \| `interface` \| `event` \| `team` \| `term` |
| 4 | `Definition` | string | One or two sentences. For a component: what it does and what it owns. For a term: what it means here, which is often narrower than the industry meaning. |
| 5 | `Aliases` | list | Every other name the sources use — old names, internal nicknames, marketing names, spelling variants. `—` when none. This column is what makes a rename traceable. |
| 6 | `Owner` | string | Named person or team, or `unassigned`. |
| 7 | `Decision rights` | string | Who decides changes to this entity, and the escalation path when they disagree. `unassigned` where no evidence exists. |
| 8 | `Source of truth` | string | Where the authoritative definition or configuration lives — a file, a schema, a system, a document. |
| 9 | `Evidence` | list | `EV-####` rows supporting the name, the definition, and the ownership. Ownership in particular is a claim and needs a row. |
| 10 | `Status` | enum | `current` \| `deprecated` \| `proposed` — `proposed` only for names the package is introducing because no canonical name existed, which must be flagged rather than silently coined. |

Rules:

- **Never invent an owner.** `unassigned` is the correct value when no evidence establishes ownership, and the count of `unassigned` entries is itself a diligence signal. A plausible owner inferred from commit history is `I`-grade at best and must be recorded as such, not asserted.
- **Ownership gaps and bus-factor concerns are reported, not smoothed over.** An entity with one contributor, or with `unassigned` decision rights on a critical path, appears in the ownership-gaps section of `00-control/terminology-and-ownership.md`.
- **Aliases are mandatory when sources disagree.** If the code says `billing-svc`, the wiki says `Payments Service`, and the org chart says `Monetization`, all three go in `Aliases` under one canonical name. Dropping the aliases makes every future search miss two thirds of the evidence.
- **`deprecated` names keep their rows.** A reader encountering an old name in a ticket needs to find it here.
- **Public documents use public-safe names.** Where the canonical internal name is not disclosable, the row records the approved public name in `Aliases` and the `CL-` row governs its use. The internal name never appears in `06-public/**`.

```markdown
| ID | Canonical name | Class | Definition | Aliases | Owner | Decision rights | Source of truth | Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| TM-0003 | Accounts API | service | HTTP service exposing the public `/v1/accounts` surface; owns account records and their lifecycle. | accounts-svc, Account Service, `api` (in IaC) | unassigned | unassigned | `src/api/` at the pinned commit; deployment in `infra/services/accounts.tf` | EV-0002 | current |
| TM-0012 | tenant | term | A billing and isolation boundary. One tenant maps to one organisation and to one schema in the primary database. Not a synonym for "customer": one customer may hold several tenants. | org, workspace, account (in older tickets) | unassigned | unassigned | `migrations/0007_tenant_schema.sql` | EV-0021 | current |
```

`TM-0012` is why the register exists: three documents using "tenant", "org", and "workspace" for the same boundary, plus one using "account" for something else, is a package that cannot be read correctly no matter how well each document is written.
