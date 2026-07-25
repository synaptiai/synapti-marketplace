# Package Contract — `01-project/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the two project documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

These two documents answer "what is this and why does it exist" at two altitudes: one for a decision maker with ten minutes, one for anyone who needs to understand the product well enough to reason about it. Neither is marketing copy, and neither infers product intent from code when product evidence exists.

---

## executive-project-brief

| Field | Value |
|---|---|
| Path | `01-project/executive-project-brief.md` |
| Template | `templates/package/01-project/executive-project-brief.md` |
| Audience | Technical executive, investor, acquirer, incoming leader, board reader |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `00-control/evidence-ledger.md`, `00-control/terminology-and-ownership.md`, `01-project/product-and-domain.md`, `02-architecture/system-architecture.md`, `04-operating/decisions-technical-debt-and-risks.md`. Drafted after the architecture and risk documents exist, because a brief written first becomes the thing later documents are made to agree with.

### Required content

- Problem, users, value proposition, and intended outcomes.
- Current lifecycle stage and actual scope — what is genuinely deployed and serving, not what the repository could support.
- Implemented capabilities versus planned capabilities, in one table with an explicit state per capability.
- High-level architecture and operating model, with pointers to the canonical documents rather than a second architecture description.
- Important business and technical metrics, only when verified, each with its measurement window and environment.
- Principal dependencies and constraints, with replaceability.
- Key strengths, each with why it is material and what evidences it.
- Top risks, unknowns, and near-term decisions.
- Overall documentation confidence, with verified facts, reported assertions, inferences, and unknowns in visibly separate groupings.

### Hard rules

- This is not marketing copy. No superlatives, no unfalsifiable strengths, no framing chosen to flatter.
- A metric that could not be verified is listed as an unknown, not estimated. A single figure where the evidence supports a range is false precision.
- Planned capabilities appear as planned. Nothing in the capability table is written in the present indicative unless it is implemented and evidenced.
- Summarizing is where observed, interpreted, unknown, and recommended collapse into each other. The confidence section keeps them apart deliberately, and no interpretation from a body document is promoted to a fact here.
- Lifecycle stage is evidenced. "Production" means something is serving real users, established by evidence, not by the presence of a production configuration file.

### Project-type adaptation

- **Library or SDK:** actual scope means published versions and known downstream consumers, not repository contents. "Users" are integrating developers.
- **Data or AI product:** capability states must distinguish a model that exists from a model that is deployed and from a model that is deployed with oversight. Cost per unit of work belongs in the metrics table when verified.
- **Infrastructure:** actual scope means the workloads and tenants genuinely depending on it. Failure-domain breadth belongs in the risk table.
- **Embedded or connected hardware:** lifecycle stage covers hardware revision and manufacturing state alongside software maturity. Fielded unit counts are a metric, subject to the same verification bar.
- **Safety-critical:** the strengths section does not lead. Hazard coverage, verification evidence, and residual risk lead, because that is the material a decision maker is exposed to.

### Decision-usefulness test

A technical executive reads only this document before a meeting. It passes if:

1. They can state what the project is, what stage it is at, and its top three risks, without opening another file.
2. They can tell which of their beliefs after reading are verified and which are reported.
3. Nothing they would repeat in the meeting is unsupported — because the brief is the document most likely to be quoted out of context, and every sentence must survive that.

---

## product-and-domain

| Field | Value |
|---|---|
| Path | `01-project/product-and-domain.md` |
| Template | `templates/package/01-project/product-and-domain.md` |
| Audience | Product managers, designers, engineers, diligence readers assessing product behaviour |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `00-control/evidence-ledger.md`, `00-control/terminology-and-ownership.md`.

### Required content

- Product vision, mission, goals, and non-goals.
- Target users, buyers, administrators, operators, partners, and other actors.
- Jobs to be done, important user journeys, and success criteria, with at least one journey traced step by step through the components it crosses.
- Feature and capability map with implemented, partial, planned, deprecated, and absent states.
- Business model, plans, entitlements, and commercial-to-technical constraints, where applicable and verified.
- Product boundaries and explicitly out-of-scope behaviour.
- Domain model, business rules, invariants, and terminology.
- Permissions and role model at the product level, distinct from the technical authorization mechanism.
- Information architecture, interaction model, design-system source of truth, important UI states, and content conventions, where applicable.
- Product analytics, metric definitions, and instrumentation coverage.
- Accessibility, internationalization, and supported platforms, where applicable.
- Roadmap statements, clearly separated from current behaviour.
- Product assumptions, constraints, risks, and unresolved decisions.
- Divergence between intended and implemented behaviour, recorded rather than reconciled.

### Hard rules

- Do not infer product intent solely from code when product evidence is available. Code establishes what happens; it does not establish what was meant.
- Where intended and implemented behaviour diverge, record both and name the divergence. Silently documenting the implementation as if it were the intent erases the most useful signal in the document.
- An invariant recorded as `unenforced` is a finding, not a footnote — an invariant nothing enforces is a convention.
- A metric that is defined but not instrumented is recorded as `absent`. A definition is not a measurement.
- Roadmap items carry no date unless a committed date exists in evidence, and are never written in the present tense.
- The primary journey traced here uses the same component names as `02-architecture/system-architecture.md`, drawn from the terminology register.

### Project-type adaptation

- **Library or SDK:** "users" are integrating developers and "journeys" are integration paths — install, first call, upgrade, migration off a deprecated API. The capability map is the public API surface with its stability states. Downstream consumers are actors.
- **Data or AI product:** journeys include the human-review and override paths, not only the automated path. The capability map distinguishes what the model does from what the product promises. Evaluation criteria are success criteria and belong here, not only in the data document.
- **Infrastructure:** actors are tenants, platform operators, and the teams whose workloads depend on it. Product boundaries are the support contract between platform and consumer, and are frequently the least documented thing in an infrastructure project.
- **Embedded or connected hardware:** journeys include unboxing, provisioning, pairing, update, field service, and end-of-life. Supported platforms include hardware revisions. Physical safety constraints are product constraints.
- **Safety-critical:** non-goals carry the same weight as goals, because a system used outside its intended scope is the common precondition for harm. Intended operating conditions are stated explicitly.

### Decision-usefulness test

A new product manager must decide whether an observed behaviour is intended. It passes if:

1. They can find the relevant rule or journey and reach a defensible answer without asking an engineer.
2. When the answer is "unknown", the document says so rather than leaving them to infer intent from the implementation.
3. They can tell current behaviour from roadmap at a glance, in every section — not only in the roadmap section.
