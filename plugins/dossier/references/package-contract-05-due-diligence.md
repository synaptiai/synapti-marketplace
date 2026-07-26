# Package Contract — `05-due-diligence/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the two due-diligence documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

These two are drafted **last among the internal documents**, so they assess a completed evidence set rather than shaping the evidence to fit a conclusion. Everything they say is derived from the rest of the package; a fact appearing here for the first time is a fact that skipped verification.

---

## technical-due-diligence-report

| Field | Value |
|---|---|
| Path | `05-due-diligence/technical-due-diligence-report.md` |
| Template | `templates/package/05-due-diligence/technical-due-diligence-report.md` |
| Audience | Decision maker — investor, acquirer, procurement lead, partner, board, incoming leader |
| Default confidentiality | Internal — frequently `Restricted` |
| Header style | `internal-v1` |

**Depends on:** every internal document, and all five registers. Drafted after all of them.

### Required content

- Executive verdict and confidence level.
- Decision context, materiality thresholds, risk appetite, and time horizon, when provided.
- Diligence scope, date, project version, sources inspected, sources unavailable, and limitations.
- Product and technology fit.
- Current lifecycle and maturity.
- Architecture and codebase assessment.
- Data and AI assessment.
- Infrastructure, deployment, reliability, and operational assessment.
- Security, privacy, and compliance assessment.
- Engineering organization, ownership, bus factor, and delivery capability.
- Product delivery and evidence of product behaviour.
- Scalability, performance, unit-cost, and vendor-lock-in considerations.
- Intellectual property, licensing, provenance, and third-party exposure.
- Maintainability and changeability.
- Material strengths and defensible assets.
- Material weaknesses and hidden liabilities.
- Verified facts, reported assertions, inferences, and unknowns, in visibly separate groupings.
- Red flags and potential deal-breakers.
- Risk register ranked by decision impact.
- Remediation estimate ranges with stated assumptions, not false precision.
- Questions and evidence requests for management.
- 30/60/90-day stabilization or improvement priorities.
- An explicit recommendation — proceed, proceed with conditions, pause pending evidence, or do not proceed — when the assignment calls for such a decision.

### Hard rules

- **Do not advocate for the project. Do not attack it. Assess it.** The report's value is entirely in the reader's ability to trust that it is not arguing a side.
- Remediation estimates are ranges with the assumptions they rest on. A single number where the evidence supports a range is false precision, and false precision in a diligence report is worse than a wide range honestly stated.
- Estimates carry no calendar dates. Horizons are ordering; they are not commitments the package has authority to make.
- Where decision context was not supplied, this is a general technical and product readiness assessment. Transaction-specific acceptance criteria are not invented to fill the gap.
- An empty red-flag table states that none were found in the sources inspected. It never states that none exist.
- The four evidence groupings stay visibly separate. Summarizing is where they collapse, and this document is the most summarized in the package.
- No legal conclusions. Licensing and IP findings are flagged for qualified review; the report describes what was found, not what it means legally.
- Named individuals appear only where the terminology register already records the information. Bus-factor analysis is about roles and knowledge concentration, not about performance.
- Scope and limitations come before the assessments, not after. A reader who reaches the verdict without knowing what was inaccessible has been misled by ordering alone.

### Project-type adaptation

- **Library or SDK:** adoption evidence, downstream consumer exposure, breaking-change history, and maintainer concentration carry more weight than infrastructure maturity. The defensible asset is frequently the consumer base and the API design, not the code.
- **Data or AI product:** dataset and model provenance, licensing and permitted use of training data, evaluation rigour and its limits, cost per unit of work at projected scale, vendor dependency on model providers, and human-oversight maturity. Provenance ambiguity in training data is a material liability, not a documentation gap.
- **Infrastructure:** tenancy isolation evidence, failure-domain design, recovery evidence, capacity headroom, and unit economics at scale. An untested recovery path is a headline finding, not a medium one.
- **Embedded or connected hardware:** bill-of-materials risk, component availability and single-source parts, manufacturing dependency, certification status and its transferability, field-fleet update capability, warranty and field-failure exposure, and end-of-life obligations. Hardware liabilities do not remediate on a software timescale, and estimates say so.
- **Safety-critical:** hazard analysis completeness, verification evidence per safety requirement, residual risk acceptance and who holds it, certification status, and the human fallback path. A gap here is decisive rather than material.

### Decision-usefulness test

A decision maker reads the report and acts. It passes if:

1. They can state the verdict, its confidence, and the two or three facts that most drive it, from the executive section alone.
2. Every fact they would repeat to a counterparty is traceable to a claim state and a locator.
3. If they disagree with the verdict, they can find the evidence to argue with — because a report that cannot be argued with has hidden its reasoning rather than shown it.

---

## assets-dependencies-and-licenses

| Field | Value |
|---|---|
| Path | `05-due-diligence/assets-dependencies-and-licenses.md` |
| Template | `templates/package/05-due-diligence/assets-dependencies-and-licenses.md` |
| Audience | Diligence readers, engineering leaders, counsel receiving flagged items |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/components-and-codebase.md`, `02-architecture/data-and-ai.md`, `02-architecture/infrastructure-and-deployment.md`, `00-control/evidence-ledger.md`.

### Required content

- Repository, service, package, artifact, schema, model, dataset, infrastructure, domain, certificate, account, and documentation asset inventory, as applicable.
- Ownership, provenance, criticality, maintenance status, and recovery path per asset.
- Direct and material transitive dependencies.
- Runtime, build, development, data, AI/model, device, and service dependencies.
- Version, license, support status, end-of-life status, known restrictions, and replacement difficulty.
- Open-source obligations and distribution implications.
- Commercial third-party terms that require human review.
- Generated, copied, vendored, or externally contributed code and content.
- Software bill of materials status.
- Vulnerability evidence and scan date.
- Abandoned or single-maintainer dependencies.
- External services, lock-in, exit strategy, and business continuity.
- Unknown provenance or ownership, treated as a material diligence risk.

### Hard rules

- **Never infer legal clearance from the presence of a license file.** A license file establishes what text is in the repository. It does not establish that the license applies, that its obligations are met, that the contributor had the right to grant it, or that the distribution mode in use is permitted.
- Flag issues for qualified legal review rather than giving legal conclusions. "This is permissive, so we are fine" is a legal conclusion.
- Transitive dependencies are included where material — restrictive license, known vulnerability, end-of-life date, single maintainer. An exhaustive transitive list with no decision value belongs in the SBOM, not in this document.
- License obligations are recorded against the project's actual distribution mode. An obligation that triggers on distribution is irrelevant to a service that does not distribute, and stating it anyway obscures the ones that do apply.
- No vulnerability identifiers with affected version details, and no exploitation conditions. Counts and severities only; detail lives with the security owner.
- A clean scan is evidence that the scanner found nothing in its scope, on its date, against its advisory data. It is not evidence that the system has no vulnerabilities, and it is not written as one.
- Unknown provenance and unknown ownership are material risks in their own right, summarized rather than left as blank cells in a long table.

### Project-type adaptation

- **Library or SDK:** license compatibility with downstream consumers is the central question, because the project's own license constrains everyone who depends on it. Contributor licensing and the provenance of external contributions matter more than in a closed service.
- **Data or AI product:** datasets and models are assets with licenses, permitted-use terms, and provenance chains — frequently the weakest-evidenced assets in the whole project. Training-data rights, model-output ownership terms, and restrictions on commercial or derivative use are required determinations, not optional ones.
- **Infrastructure:** accounts, domains, certificates, and reserved capacity are assets whose ownership is frequently held by an individual rather than the organization. Recovery path if the holder is unavailable is required content.
- **Embedded or connected hardware:** the bill of materials is an asset inventory with supply-chain exposure. Single-source components, minimum order quantities, lifecycle status of each part, firmware component licensing, and certification transferability all belong here. A part going end-of-life is a hardware risk with a long remediation horizon.
- **Safety-critical:** certification artifacts, qualification records, and supplier assessments are assets whose loss or non-transferability is material.

### Decision-usefulness test

An acquirer's counsel receives the flagged-items list. It passes if:

1. Each flagged item names a specific question they can answer, not a general area of concern.
2. Nothing in the document has already answered a legal question on their behalf.
3. The engineering reader can separately answer "what breaks if this dependency disappears tomorrow" for every critical dependency, from the same tables.
