# Package Contract — `00-control/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the five control documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

The control directory is the package's control plane. Everything else in the package is a view over these five files: the registers hold the facts and their provenance, and the index is the entry point that routes a reader to the right view. They are drafted **first**, before any narrative document, because a narrative document drafted before its evidence exists is a narrative that will be defended rather than corrected.

Shared register mechanics — column definitions, identifier grammars, append-only rules, citation syntax — are in `references/evidence-ledger-schema.md` and `references/register-schemas.md`. This file specifies what each document must *contain*, not how a row is shaped.

---

## documentation-index

| Field | Value |
|---|---|
| Path | `00-control/documentation-index.md` |
| Template | `templates/package/00-control/documentation-index.md` |
| Audience | Every reader — this is the entry point |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** every other document in the package. It is drafted first as a skeleton and finalized last, when the values it mirrors are stable.

### Required content

- Project and documentation scope — what the package covers, and what was deliberately not inspected.
- Package version and verification date, alongside the project version or commit the package describes.
- Reader routes for diligence, engineering onboarding, product onboarding, operators, security reviewers, technical partners, and customers. A route is an ordered reading list, not a link dump; a reader following it reaches a decision without opening documents outside it.
- A table of every canonical document with owner, audience, confidentiality, status, last verified date, and purpose.
- Evidence coverage summary — row counts by claim state, material claims with no row, rows past freshness, source classes inspected and unavailable, and coverage by document so a reader knows where to discount.
- Unresolved critical questions and contradictions, with the impact of each being wrong.
- Document dependencies and sources of truth — which document is canonical for which subject, and which documents link to it rather than restating it.
- Maintenance policy: review cadence, freshness threshold, review triggers, archival rules, and the refresh mechanism in use.
- Change summary since the previous documentation version, where a previous version is known.
- Supplemental document index — each entry states why the supplement exists and which canonical document it extends. An empty index is the normal state.

### Hard rules

- The canonical document table mirrors the headers. When a cell disagrees with the document's own header, the header wins and the index row is the defect.
- The index never becomes a second home for a fact. A fact that appears here and in a canonical document has one canonical home, and the index links to it.
- Reader routes are validated, not asserted: each route was walked, and the walk is what establishes that the entry point is findable.

### Decision-usefulness test

A reader arrives with a question and thirty seconds of patience. The index passes if:

1. Each of the seven reader types can identify their route without reading any other section.
2. A reader can tell, from the coverage summary alone, which documents are thin enough that they should not be relied on unaided.
3. A reader can tell from the unresolved-items table whether anything open would change their decision, before they invest time in the body of the package.

If a reader must open three documents to discover which document they needed, the index has failed regardless of how complete its tables are.

---

## evidence-ledger

| Field | Value |
|---|---|
| Path | `00-control/evidence-ledger.md` |
| Template | `templates/package/00-control/evidence-ledger.md` |
| Audience | Diligence readers, verification passes, document owners |
| Default confidentiality | Internal — `Restricted` when it cites restricted sources |
| Header style | `internal-v1` |

**Depends on:** nothing. It is the root of the package's dependency graph. Every other document depends on it.

### Required content

- Evidence method and claim-state definitions, stated in the document rather than only referenced, so the ledger is readable standalone.
- The authority ordering instantiated for this project — what "level 1" and "level 3" concretely mean here, not the generic class names.
- The complete material-claim evidence table.
- Source inventory and inspection coverage: what was made available, what was inspected, and how completely — full, sampled, partial, or none.
- Verification commands and checks executed, each with date, scope, environment, result, and output artifact.
- Unavailable or inaccessible evidence, with what each source would have settled and the open question it produced.
- Stale evidence and the refresh action required for each row past its expiry.
- Secrets and sensitive material encountered — type and location category only.

### Hard rules

- No secret value, credential, token, private key, personal data, customer-identifying data, or exploitable detail enters the ledger, in any column, ever. When such material is the evidence, the row records the type and the location category and nothing more.
- Every `cmd:` locator in the evidence table has a matching row in the executed-checks table. A `cmd:` locator with no execution record asserts that a check ran when nothing shows it did.
- A check that could not run is `not executed` with a reason. It is never recorded as passing and never omitted.
- Absence of evidence is never recorded as evidence of absence. An absence claim states what was searched, where, and when, and a companion row records what that search does not cover.
- The ledger is append-only in identity: rows are closed, never deleted; identifiers are never reused or renumbered.

### Decision-usefulness test

A verification pass must be able to take any material sentence in the package, find its row, and independently reach the same conclusion — or fail to, and say so. The ledger passes if:

1. Every `V` row can be re-verified by a second person from the `Source ref` alone, without asking the author anything.
2. Every `U` row makes clear what would resolve it, so an owner can act rather than merely acknowledge.
3. A reader can answer "what is this package weakest about?" by sorting on `State` and `Freshness`, without reading prose.

---

## assumptions-questions-and-contradictions

| Field | Value |
|---|---|
| Path | `00-control/assumptions-questions-and-contradictions.md` |
| Template | `templates/package/00-control/assumptions-questions-and-contradictions.md` |
| Audience | Document owners, project owners who must supply evidence, diligence readers |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `00-control/evidence-ledger.md`.

### Required content

- Assumptions register — working positions the package relies on.
- Open-questions register — what must be answered, with the smallest sufficient artifact named.
- Contradiction register — disagreements between sources, both sides recorded with evidence and authority level.
- Blocking decisions — items where documentation would materially mislead until a human decides, naming the decision and the decider rather than only the gap.
- Recommended evidence requests, ordered by decision impact rather than by identifier.
- Owner and next action for every unresolved item.

### Hard rules

- Never resolve a contradiction by choosing the convenient side. Record both, name the decision impact, and either verify or escalate.
- While a contradiction is unresolved, both underlying evidence rows sit at `R` or lower. Neither side keeps `V`.
- An assumption the package writes as if true, without a row here, is an undocumented assumption — the failure mode this register exists to prevent.
- "Why it matters" names a decision or task that changes with the answer. An item where nothing changes does not belong in the register and dilutes the ones that do.
- Any open `blocking` item, and any unresolved contradiction that could materially mislead a diligence, onboarding, integration, operational, security, or customer decision, fails the release gate regardless of package score.
- The package may not mark a risk `accepted` on the project's behalf. Acceptance requires a named human with the authority to accept.

### Decision-usefulness test

The evidence-request list is handed to a busy project owner with fifteen minutes. It passes if:

1. Each request names an artifact that can be produced or refused in one action — not "clarify the architecture", but "the runbook output from the most recent restore rehearsal".
2. The owner can see, per request, exactly which document unblocks and which decision it serves.
3. Reading the top three requests answers "what is the fastest path to a releasable package?"

---

## claim-and-disclosure-register

| Field | Value |
|---|---|
| Path | `00-control/claim-and-disclosure-register.md` |
| Template | `templates/package/00-control/claim-and-disclosure-register.md` |
| Audience | Disclosure approvers, public-document drafters, verification pass C |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `00-control/evidence-ledger.md`, and every internal document that sources a public claim.

### Required content

- Public claim inventory — every capability, metric, reliability, privacy, security, compliance, compatibility, roadmap, and support claim intended for publication, with its exact proposed wording.
- Supporting evidence identifiers, applicable version, and scope for each claim.
- Approval state, and the approving owner where approval is required.
- Required qualifications — conditions that must accompany a claim's wording, and where they appear in the public document.
- Confidentiality and disclosure risks: what the package holds that must not reach a public document, and the specific leak path.
- Rejected and withdrawn claims with reasons, retained so a future drafter does not re-propose them.
- Mapping to both public documents, section by section.

### Hard rules

- The register exists before public drafting begins. A public sentence written before its row exists is a claim looking for evidence.
- No public sentence without an `approved` row whose `Proposed wording` it matches verbatim. Zero unsupported public claims is a release gate, not a warning.
- The package cannot approve its own claims. A drafting or verifying agent may apply a user-supplied disclosure policy; it may not appoint itself the business, legal, security, privacy, or communications approver. Where approval is required and absent, the status is `pending` and the sentence does not ship.
- Approval attaches to wording. Editing an approved sentence returns it to `pending` unless the change is purely typographical and recorded as such.
- Every claim carries an applicable version and scope. An unbounded claim cannot be approved because it cannot be re-verified.
- Rejected rows are never deleted.

### Decision-usefulness test

A disclosure approver reviews the register without reading the rest of the package. It passes if:

1. Each row can be approved or rejected on its own, from the wording, evidence, scope, and limitations in the row.
2. The approver never has to ask "what exactly are we saying?" — the exact sentence is present, not a summary of it.
3. Rejecting one row makes it obvious which public sentences must change, via the mapping section.

---

## terminology-and-ownership

| Field | Value |
|---|---|
| Path | `00-control/terminology-and-ownership.md` |
| Template | `templates/package/00-control/terminology-and-ownership.md` |
| Audience | Every drafter, every reader crossing document boundaries, diligence readers assessing bus factor |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `00-control/evidence-ledger.md`.

### Required content

- Glossary of domain, product, data, security, and engineering terms as used in this project, which is frequently narrower than the industry meaning.
- Canonical entity names and aliases for products, projects, components, services, modules, repositories, packages, user and customer roles, environments, deployment units, external systems, partners, data classes, domain entities, interfaces, events, owners, and teams.
- Component and capability ownership, with the evidence supporting each ownership claim.
- Decision ownership and escalation paths.
- Operational ownership.
- Documentation ownership.
- Explicit ownership gaps and bus-factor concerns, stated plainly.
- Public naming — where an internal canonical name is not disclosable, the approved public name and the claim row governing its use.

### Hard rules

- Never invent an owner. `unassigned` is the correct value where no evidence establishes ownership, and the count of `unassigned` entries on critical components is itself a diligence signal.
- Ownership is a claim and carries an evidence row. A name inferred from commit history is `I` at best and is labelled as such, never asserted.
- Aliases are mandatory where sources disagree. Dropping them makes every subsequent search miss the evidence recorded under the other names.
- Deprecated names keep their rows so a reader encountering an old name in a ticket can find the current one.
- Every other document draws its vocabulary from here. A term used with two meanings in two documents is a cross-document consistency failure that this register exists to prevent.

### Decision-usefulness test

Two readers — a new engineer and a diligence analyst — read different documents and then discuss the system. It passes if:

1. They use the same word for the same thing, and neither has to ask "is that the same as X?"
2. The analyst can answer "who would we need to retain?" from the ownership and bus-factor sections alone.
3. A reader encountering an unfamiliar name anywhere in the package finds it here, including names that appear only in older evidence.
