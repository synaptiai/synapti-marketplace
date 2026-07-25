# Package Contract — `06-public/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the two public documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

Public documentation is a projection of verified internal truth, not a rewrite of marketing material. It is derived from the approved rows of `00-control/claim-and-disclosure-register.md` and from nothing else. Both files use the `public-v1` header; the field rules and the list of what a public header must never contain are in `references/document-headers.md`.

**Rules that govern both files.** These apply to every sentence in this directory, in addition to the per-document rules below.

- **Every claim maps to an `approved` row in the claim register, matching its `Proposed wording` verbatim.** A sentence with no row does not ship, however obviously true it seems.
- **Only `V` and `C` evidence supports a public claim.** Reported and inferred claims do not appear, qualified or otherwise.
- **No internal identifiers.** No `EV-`, `AQ-`, `CT-`, `CL-`, or `TM-` strings; no repository paths, file names, module names, branch names, or internal component names; no commit SHAs.
- **No internal ownership.** No person names, team names, on-call identities, or escalation individuals. Roles and channels only.
- **No security-sensitive detail.** No vulnerability information, no affected versions, no control implementation detail, no secret-handling mechanics, no internal topology, no internal risk findings.
- **No customer identities or customer-confidential facts**, including named references, unless a specific approval covers them.
- **No unannounced roadmap.** Planned work is described as planned or not at all; it is never written in the present tense.
- **Avoid superlatives and absolute safety claims.** "Best", "fastest", "fully secure", "completely private", "never fails" are unfalsifiable and read as guarantees.
- **Avoid ambiguous words.** "Anonymous", "real time", "encrypted", "private", "unlimited", "instant" carry a meaning to the reader that is almost always stronger than the evidence. Either state the scope alongside the word, or use a plainer one.
- **Simplification must not create falsehood.** Internal detail may be omitted or generalized; a public description must remain true after the simplification. This is the specific failure that makes public documentation dangerous, because it is invisible to anyone who has not read the internal source.
- **Limitations stay visible.** Every condition needed to keep a claim true accompanies the claim, adjacent to it — not in a footnote, not on another page.
- **Examples use synthetic data**, verified against supported behaviour.
- Where the project has no external interface, the partner guide explains the supported partnership model and marks the interface sections `N/A`. The file is not omitted.

---

## technical-partner-guide

| Field | Value |
|---|---|
| Path | `06-public/technical-partner-guide.md` |
| Template | `templates/package/06-public/technical-partner-guide.md` |
| Audience | Integration partners and their engineers |
| Default confidentiality | Public — or `Partner-Confidential` where the disclosure policy scopes it that way |
| Header style | `public-v1` |

**Depends on:** `00-control/claim-and-disclosure-register.md` (the only permitted source), which draws from `02-architecture/interfaces-and-integrations.md`, `03-assurance/security-privacy-and-compliance.md`, and `03-assurance/reliability-performance-and-observability.md`.

### Required content

- Product and integration overview.
- Supported partner use cases and boundaries, including what is explicitly not supported.
- Conceptual integration architecture, at the partner's level of abstraction.
- Prerequisites and access process.
- Supported public APIs, events, webhooks, SDKs, files, protocols, or devices.
- Authentication and authorization.
- Versioning and compatibility.
- Safe synthetic examples.
- Error handling, retry, idempotency, rate limit, timeout, and pagination behaviour, where applicable.
- Sandbox or test process.
- Security and data-responsibility model, at the approved disclosure level.
- Operational expectations, support, escalation, and status channels.
- Published availability or support commitments, only when contractually and technically verified.
- Deprecation and change communication.
- Known limitations.
- Partner checklist and troubleshooting.

### Hard rules

- **Do not expose internal topology, repository paths, secret-handling details, unannounced roadmap, vulnerable versions, customer identities, internal risk findings, or unsupported guarantees.**
- The integration diagram shows partner systems and the public surface. It does not show internal components, however helpful that would be.
- Availability and support commitments appear only where both a contract and current technical evidence support them. An internal objective is not a commitment. Where no commitment exists, the section says so plainly rather than implying one through vagueness.
- The "not supported" column is required. It is not a disclaimer — it is what stops a partner building something the product will not sustain, and its absence is the most expensive omission in this document.
- Error behaviour, rate limits, and retry semantics are documented before a partner encounters them in production. Incomplete error documentation is the most common cause of partner incidents.
- Interfaces appear here only if `02-architecture/interfaces-and-integrations.md` records an explicit disclosure decision permitting it. Discoverability in code is never the reason.

### Project-type adaptation

- **Library or SDK:** the "integration" is dependency adoption. The supported version matrix, the breaking-change policy, and the upgrade path are the core content, and the deprecation timeline is a commitment consumers plan against.
- **Data or AI product:** partners need model input and output contracts, evaluation and accuracy characteristics within a stated scope, cost and latency behaviour, and the limits of what they may rely on the model to do. Accuracy figures state their dataset and conditions or are omitted.
- **Infrastructure:** partners are tenants or integrating platforms. Isolation guarantees are disclosed only within the scope evidence supports, and quota, capacity, and change-notification behaviour matter more than API ergonomics.
- **Embedded or connected hardware:** partners need electrical and mechanical interface specifications, protocol documentation, certification implications of their integration, and the supported hardware revision matrix. Backward compatibility with fielded devices is a commitment with a long tail.
- **Safety-critical:** the partner's responsibilities within the safety case are stated explicitly, including what the product does not protect against and what the integrator must implement.

### Decision-usefulness test

A partner engineer implements an integration using only this document. It passes if:

1. They complete the happy path without asking a question.
2. They handle errors, retries, rate limits, and timeouts correctly the first time, because the behaviour was documented before they hit it.
3. Nothing they read leads them to build against a capability the product does not support — which is what the boundaries and limitations sections exist to prevent.

---

## customer-product-and-trust-guide

| Field | Value |
|---|---|
| Path | `06-public/customer-product-and-trust-guide.md` |
| Template | `templates/package/06-public/customer-product-and-trust-guide.md` |
| Audience | Customers, consumers, administrators, and evaluators |
| Default confidentiality | Public |
| Header style | `public-v1` |

**Depends on:** `00-control/claim-and-disclosure-register.md` (the only permitted source), which draws from `01-project/product-and-domain.md`, `02-architecture/data-and-ai.md`, and `03-assurance/security-privacy-and-compliance.md`.

### Required content

- What the product is, who it is for, and the problem it solves.
- How it works, at the level users need.
- Current capabilities and explicit limitations.
- Important user journeys.
- Account, permission, and control model, where relevant.
- What data is collected, why, how it is used, where choices exist, and how deletion and support work — using approved language.
- Security, privacy, reliability, accessibility, and responsible-AI explanations, limited to verified scope.
- AI involvement, meaningful limitations, human oversight, and user controls, where applicable.
- Supported platforms, regions, languages, compatibility, and prerequisites.
- Support, incident, status, and escalation paths.
- A concise FAQ.
- Last updated date and applicable product version.

### Hard rules

- **Avoid superlatives, absolute safety claims, and ambiguous words such as "anonymous" or "real time".** Where such a word is unavoidable, its scope appears in the same sentence.
- **Roadmap language must not sound like a current feature.** "We are working towards" and "the product supports" describe different worlds to a reader deciding whether to buy.
- **Make limitations understandable without unnecessarily exposing exploitable detail.** A customer needs to know a limit exists and how to work within it; they do not need the mechanism that makes it exploitable. Where the two conflict, the limitation is stated at a level the customer can act on and the mechanism is withheld.
- The limitations table is required and is not a disclaimer section. It is what lets a reader judge fit, and a product page without it will be judged by someone else's review instead.
- Data statements name what is collected, why, how long it is kept, who can access it, and how to delete it. "We take privacy seriously" is not a data statement.
- AI sections are `N/A` where no AI is present — stated plainly, not omitted. Absence is information a reader may specifically be looking for.
- Security, privacy, reliability, and accessibility statements each carry the scope they hold within, in the same table row. A scopeless trust claim is the exact failure this directory exists to prevent.
- Non-marketing register throughout: plain language, no persuasion, no framing chosen to flatter. A reader who feels sold to stops trusting the trust section.

### Project-type adaptation

- **Library or SDK:** the "customer" is a developer choosing a dependency. What they need is scope, maintenance status, supported versions, licensing, and honest limitations — not feature marketing.
- **Data or AI product:** AI involvement, what it decides and does not decide, its known failure modes in terms the reader can recognize, human oversight, user controls, and whether customer data is used for training. Accuracy claims state their conditions or are omitted entirely.
- **Infrastructure:** the audience is usually an evaluating engineer. Isolation, data location, and operational transparency matter more than capability breadth.
- **Embedded or connected hardware:** add physical safety information, environmental limits, what happens when connectivity is lost, update behaviour, warranty scope, and end-of-life and end-of-support commitments. A device that stops receiving updates on a stated date is a trust fact the buyer needs before purchase.
- **Safety-critical:** intended use and — with equal prominence — uses the product is not qualified for. Required operator training or supervision is stated as a requirement, not a recommendation.

### Decision-usefulness test

A customer evaluates the product before buying, and an existing customer checks what happens to their data. It passes if:

1. The evaluator can tell what the product does and does not do, and finds no surprise after purchase that the limitations section should have named.
2. The existing customer can answer "what is collected, how long is it kept, and how do I delete it" without contacting support.
3. A skeptical reader finds no sentence they could call misleading — which is the only durable test for a trust document, since one such sentence discredits the rest.
