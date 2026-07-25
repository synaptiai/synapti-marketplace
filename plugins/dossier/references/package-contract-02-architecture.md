# Package Contract — `02-architecture/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the five architecture documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

These five documents are the technical model of the project. Every other technical document is a view over them, so a contradiction between them and anything else is resolved here or recorded as a contradiction — never smoothed over downstream.

Diagrams throughout this directory follow one rule: every node and every connection is supported by evidence, and connections that are inferred rather than observed are labelled inferred in both the diagram and its accompanying table. A decorative diagram is worse than no diagram, because it is read as a claim.

---

## system-architecture

| Field | Value |
|---|---|
| Path | `02-architecture/system-architecture.md` |
| Template | `templates/package/02-architecture/system-architecture.md` |
| Audience | Engineers, architects, security reviewers, diligence readers, operators |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `00-control/evidence-ledger.md`, `00-control/terminology-and-ownership.md`, `01-project/product-and-domain.md`.

### Required content

- Architectural goals, constraints, and quality attributes, each traced to what drives it.
- System context and external actors, with what crosses the boundary.
- Container or subsystem view — the deployable and runnable units, what each owns, and its criticality.
- Major runtime flows and control flows, including at least one flow traced end to end.
- Trust boundaries, and the authentication and authorization governing each crossing.
- Synchronous and asynchronous communication, with delivery guarantees, ordering, and idempotency.
- State ownership and consistency model.
- Tenancy, identity, authorization, and isolation model — including what each does *not* isolate.
- Principal failure modes and degradation behaviour.
- Architecture patterns actually used, not patterns aspired to.
- Material tradeoffs and rejected alternatives, only where evidence of the decision exists.
- Current architecture versus target architecture.
- Scalability boundaries and known bottlenecks, with how each limit was established.
- Cross-links to interfaces, data, infrastructure, reliability, and security.

### Hard rules

- Every diagram node and edge is evidence-backed. Inferred edges are labelled as inferred in the internal document.
- A flow description that shows only the happy path is incomplete. Timeouts, retries, queues, caches, and failure branches belong in the flow, because they are what a reader is actually trying to find.
- A retry path with no idempotency mechanism is recorded explicitly. It is one of the specific things a falsification pass traces.
- The isolation model states what it does not isolate. An isolation description written only in terms of what it covers reads as stronger than it is.
- Target architecture is labelled as target. A target drawn in the same diagram as current state, unlabelled, is the most common way an architecture document misleads.
- Historical rationale is recorded only where a decision record, commit, or discussion evidences it. Absent that, the rationale is unknown and is recorded as unknown.

### Project-type adaptation

- **Library or SDK:** the "container view" is the package boundary and its dependency surface. Trust boundaries are the boundary between library code and calling code, including what the library assumes about its caller. Failure modes are the library's behaviour on bad input and on downstream failure.
- **Data or AI product:** flows include the training and evaluation paths, not only inference. Trust boundaries include the boundary between untrusted input and the model, and between model output and any system that acts on it. State ownership covers datasets and model artifacts.
- **Infrastructure:** tenancy, failure domains, and change control lead. The container view is control plane versus data plane. Blast radius per failure domain is required, not optional.
- **Embedded or connected hardware:** the context diagram includes the physical environment and the device's connectivity states. Trust boundaries include the device boundary, the provisioning boundary, and the update path, with secure boot and update authentication as first-class elements. Degradation behaviour includes offline operation.
- **Safety-critical:** hazard-relevant flows are traced separately, and the human fallback path is documented as a flow with the same rigour as the automated one.

### Decision-usefulness test

A security architect must decide whether a proposed change crosses a trust boundary. It passes if:

1. They can find every boundary the change touches, and what enforces each crossing, from this document alone.
2. They can tell which edges are observed and which are inferred, so they know where to verify before relying.
3. Tracing the primary flow surfaces at least one thing they did not expect — because a flow description that surprises no one has almost certainly omitted the failure branches.

---

## components-and-codebase

| Field | Value |
|---|---|
| Path | `02-architecture/components-and-codebase.md` |
| Template | `templates/package/02-architecture/components-and-codebase.md` |
| Audience | Engineers, engineering leaders, diligence readers assessing maintainability |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/system-architecture.md`, `00-control/terminology-and-ownership.md`.

### Required content

- Repository and module map.
- Component or service catalog with purpose, owner, language and runtime, entry point, interfaces, dependencies, state owned, deployment unit, and criticality.
- Important directory and package conventions — only those a reader must know to place a change correctly.
- Request, job, event, or device lifecycle traced through the code, citing files and symbols.
- Extension points and common change paths.
- Generated code and vendored code, with regeneration commands and whether any has been hand-edited.
- Configuration model and precedence.
- Feature flags and rollout controls, each with a removal condition.
- Build system and artifact production.
- Legacy, deprecated, experimental, or orphaned areas.
- Code ownership and bus-factor gaps.
- "Where to make this change" examples for the changes this project actually receives.

### Hard rules

- Do not reproduce a large file tree. It is stale on the next commit and carries no decision value. Explain structure and decision-relevant hotspots instead.
- Hand-edited generated code is a finding: the next regeneration discards the edit silently.
- A feature flag with no removal condition is technical debt and is cross-referenced into the debt register.
- Contributor counts are evidence about the inspected history window, not about who understands the code today. State the window.
- "Unknown whether still executed" is a legitimate value for a legacy area and is better than a guess.
- No secret values in the configuration table — setting names, purposes, and read-from locations only.

### Project-type adaptation

- **Library or SDK:** the catalog is the module and export surface. Public versus internal symbols is the most important column. Compatibility-relevant code paths and the semver policy's enforcement point belong here.
- **Data or AI product:** pipelines, feature code, training code, and evaluation code are components with owners and criticality, on equal footing with services. Notebook-origin code that reached production is flagged.
- **Infrastructure:** modules, their blast radius, and which environments consume which module version. Drift between module version and deployed state is a required determination.
- **Embedded or connected hardware:** firmware layers, bootloader, board support, and hardware abstraction are components. The build must state which toolchain and which hardware revision an artifact targets. Reproducibility of a firmware build is a required field.
- **Safety-critical:** components carrying safety functions are identified as such, with the verification evidence for each.

### Decision-usefulness test

A new engineer is handed a small change on their second day. It passes if:

1. The "where to make this change" table names their task or a close relative, and following it produces a correct change.
2. They can trace the lifecycle from entry point to persisted result without opening the code first.
3. They can tell which parts of the codebase are safe to touch and which are legacy or orphaned, before they touch anything.

---

## data-and-ai

| Field | Value |
|---|---|
| Path | `02-architecture/data-and-ai.md` |
| Template | `templates/package/02-architecture/data-and-ai.md` |
| Audience | Engineers, data and AI practitioners, privacy and security reviewers, diligence readers |
| Default confidentiality | Internal — frequently `Restricted` where it describes regulated data |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/system-architecture.md`, `00-control/terminology-and-ownership.md`, `03-assurance/security-privacy-and-compliance.md` for the control side of data handling.

### Required content

- Conceptual and logical data model.
- Stores, schemas, ownership, residency, classification, and lifecycle.
- Sources, sinks, lineage, transformations, and synchronization.
- Consistency, transactional boundaries, caching, indexing, and search.
- Migrations, backup, restore, archival, deletion, and retention.
- Analytics and reporting pipelines.
- Sensitive and regulated data.
- Data quality controls and known gaps.
- Model, agent, prompt, tool, retrieval, memory, and evaluation architecture for AI functionality.
- Model and dataset provenance.
- Training, fine-tuning, inference, evaluation, monitoring, feedback, and rollback.
- Prompt injection, data leakage, unsafe output, autonomy, model drift, and human-oversight controls.
- Model limitations, cost, latency, fallback, and vendor dependency.
- Reproducibility and versioning.

### Hard rules

- A project with no AI component marks the AI sections `N/A` with the evidence that established it — and states what that evidence does not cover. A grep over dependencies is evidence about the codebase, not about vendor services in the request path.
- A project with no persistent data explains how state is handled. The document is not omitted and its sections are not left blank.
- A backup with no evidenced restore is a backup of unknown value and is recorded as such.
- Data-class examples name categories, never values. No sample records, no real identifiers.
- Whether sensitive data reaches logs, caches, search indexes, backups, and analytics pipelines is a required determination for every sensitive class. These are the stores that "encrypted at rest" claims routinely fail to cover.
- Control state for AI risk controls uses the same four-way distinction as the security document: implemented, policy-only, planned, unknown.

### Project-type adaptation

- **Library or SDK:** the data model is what the library persists or caches on the caller's behalf, and what it transmits. Frequently small, and frequently the thing consumers most need and least expect.
- **Data or AI product:** this document carries the project's weight. Lineage, evaluation methodology and its limits, provenance and licensing of datasets and models, drift detection, human oversight, cost per unit of work, and rollback are all first-class, and each needs its own evidence rather than a shared assertion.
- **Infrastructure:** the data of interest is state, configuration, and secrets — where they live, who can read them, and what a restore actually restores.
- **Embedded or connected hardware:** on-device storage, buffering during disconnection, telemetry upload, and what remains on a device after decommissioning. Data retention on physical hardware that has left the organization is a required determination.
- **Safety-critical:** data integrity controls and the failure behaviour of every input the system trusts are documented as safety-relevant, with their verification evidence.

### Decision-usefulness test

A privacy reviewer traces one sensitive data class from collection to deletion. It passes if:

1. They can name every store it reaches, including caches, logs, backups, and analytics, without asking an engineer.
2. They can determine whether a deletion request actually removes it from all of them, and where it does not.
3. Where the answer is unknown, the document says so — because a privacy answer that is confidently wrong is worse than one that is honestly incomplete.

---

## interfaces-and-integrations

| Field | Value |
|---|---|
| Path | `02-architecture/interfaces-and-integrations.md` |
| Template | `templates/package/02-architecture/interfaces-and-integrations.md` |
| Audience | Engineers, integration owners, partner-guide drafters, security reviewers |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/system-architecture.md`, `00-control/terminology-and-ownership.md`. Feeds `06-public/technical-partner-guide.md` through the claim register.

### Required content

- Inventory of APIs, events, webhooks, files, SDKs, CLIs, protocols, device interfaces, and human handoffs.
- Authoritative machine-readable contracts, and how they are generated, versioned, and validated.
- Producer, consumer, owner, transport, authentication, authorization, schema, version, and lifecycle for each interface.
- Request and response examples using safe synthetic data.
- Error model, retry behaviour, idempotency, ordering, rate limits, timeouts, pagination, and compatibility.
- Integration prerequisites and environment differences.
- Contract tests and verification coverage, including what each test does not cover.
- Third-party dependencies and their failure behaviour.
- Deprecation and versioning policy.
- Undocumented or unstable interfaces.
- Mapping to the public technical partner guide, with an explicit disclosure decision per interface.

### Hard rules

- Never publish an internal interface merely because it is discoverable in code. Every row carries an explicit disclosure decision, and only rows marked public reach the partner guide.
- Examples use synthetic data. No real identifiers, no real tokens, no customer data, in any environment's example.
- A contract hand-maintained alongside an implementation with no drift check is recorded as such. That gap is the mechanism by which API documentation becomes false.
- Undocumented interfaces that are reachable are listed. Their existence is a risk whether or not anyone is meant to use them, and omitting them is how they get consumed by accident.
- Contract-test rows state what the test does not cover. Coverage claimed without its boundary is read as complete.

### Project-type adaptation

- **Library or SDK:** the public API surface *is* the interface inventory. Semver policy, breaking-change definition, deprecation timeline, supported version window, and the compatibility matrix across runtimes and platforms carry the document. Downstream consumers and how they are notified are required content.
- **Data or AI product:** interfaces include dataset contracts, feature definitions, model input and output schemas, and evaluation result formats. Model output schema stability is a compatibility concern with the same weight as an API's.
- **Infrastructure:** interfaces are the platform's contract with its consumers — provisioning APIs, configuration schemas, and the guarantees attached to each. Deprecation of a platform interface has a wider blast radius than an application's.
- **Embedded or connected hardware:** physical connectors, pinouts, wire protocols, radio interfaces, and the device-to-cloud protocol are all interfaces. Backward compatibility with fielded devices that cannot be updated is a hard constraint and is documented as one.
- **Safety-critical:** interfaces carrying safety-relevant data are identified, with their failure behaviour and validation on both sides.

### Decision-usefulness test

A partner engineer builds an integration using only what this document approves for disclosure. It passes if:

1. They can implement the happy path and the error paths without asking a question.
2. They know what happens on retry, on timeout, and at the rate limit — before they hit them in production.
3. A reviewer can tell, from the mapping table alone, which interfaces are public and why each withheld one is withheld.

---

## infrastructure-and-deployment

| Field | Value |
|---|---|
| Path | `02-architecture/infrastructure-and-deployment.md` |
| Template | `templates/package/02-architecture/infrastructure-and-deployment.md` |
| Audience | Operators, platform engineers, security reviewers, diligence readers |
| Default confidentiality | Internal — `Restricted` where it describes access paths |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/system-architecture.md`, `00-control/terminology-and-ownership.md`.

### Required content

- Environment inventory and purpose.
- Cloud, on-premises, edge, device, network, DNS, certificate, and region topology, as applicable.
- Infrastructure ownership and source of truth, with drift detection per resource class.
- Compute, storage, networking, queue, secret, and identity resources.
- Build, packaging, artifact storage, deployment, migration, promotion, rollback, and recovery flow.
- Environment configuration and drift controls.
- Access model and privileged operations.
- Capacity, quotas, scaling, and cost drivers.
- Backup, restore, disaster recovery, recovery objectives, and evidence of testing.
- Release strategy, change controls, and rollback limitations.
- Manual steps, single points of failure, and undocumented infrastructure.
- Local, test, staging, and production differences that change behaviour.

### Hard rules

- Do not claim high availability, recovery objectives, zero downtime, or geographic redundancy without current evidence. An objective with no test evidence is written as an objective, never as a capability, and never reaches a public or partner document as a commitment.
- Recovery point and recovery time entries state whether each is a stated objective or a measured result. These are different facts and are routinely conflated.
- Rollback limitations are required content. An irreversible migration, a cache that must be warmed, a client pinned to a version — each bounds what "rollback" means, and a rollback procedure documented without its limits will be attempted in an incident and fail.
- Resources managed by console or unmanaged are listed. They are the ones that will not survive a rebuild.
- No credential values, no secret names that reveal a secret's content, and no access paths that would materially help an attacker.
- Environment differences are documented where they change behaviour, not where they only change names.

### Project-type adaptation

- **Library or SDK:** infrastructure means the release and publication pipeline — how an artifact is built, signed, published, and yanked, and who can do each. Reproducibility of a published artifact is required content.
- **Data or AI product:** compute for training and inference, data storage tiers, and their cost behaviour at scale. Cost cliffs are an infrastructure fact here, not a footnote.
- **Infrastructure:** this document carries the project's weight. Tenancy, access, capacity, failure domains, recovery, and change control each need their own evidenced section, and blast radius per failure domain is required.
- **Embedded or connected hardware:** manufacturing and provisioning flows, firmware signing and key custody, the OTA update path with its rollback limits, and field-service procedures. "Deployment" for a fielded device is irreversible in a way a server deployment is not, and the document says so.
- **Safety-critical:** change control, verification before deployment, and the authorization required for each are documented as controls with their evidence, not as process description.

### Decision-usefulness test

An operator must recover the system after losing its primary datastore. It passes if:

1. They can find the restore procedure, its preconditions, and its expected duration without paging someone.
2. They can tell what data loss window to expect, and whether the procedure has ever been executed successfully.
3. Where it has never been tested, the document says `never` — because an operator who discovers that during an incident has been misled by every earlier sentence.
