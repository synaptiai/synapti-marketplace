# Package Contract — `03-assurance/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the three assurance documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

Assurance documents make claims about properties rather than about structure — that something is protected, that it will hold under load, that it has been checked. Property claims are the easiest to overstate and the hardest to falsify by reading code, so this directory carries the package's strictest rules about scope, evidence, and the distinction between intent and result.

---

## security-privacy-and-compliance

| Field | Value |
|---|---|
| Path | `03-assurance/security-privacy-and-compliance.md` |
| Template | `templates/package/03-assurance/security-privacy-and-compliance.md` |
| Audience | Security reviewers, privacy reviewers, diligence readers, engineering leaders |
| Default confidentiality | Internal — `Restricted` where it describes gaps or access paths |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/system-architecture.md`, `02-architecture/data-and-ai.md`, `02-architecture/infrastructure-and-deployment.md`, `00-control/terminology-and-ownership.md`.

### Required content

- Security and privacy scope, including what the assessment can and cannot establish.
- Assets, actors, trust boundaries, and threat model.
- Authentication, authorization, tenancy, isolation, session, and administrative controls.
- Secrets, keys, encryption, certificate, and rotation practices.
- Network, application, infrastructure, supply-chain, endpoint, and physical controls, as applicable.
- Secure development and vulnerability-management process.
- Logging, detection, auditability, incident response, and evidence preservation.
- Data inventory, classification, legal basis, consent, minimization, retention, deletion, residency, and data-subject handling, as applicable.
- Subprocessors and third-party risk.
- Applicable regulatory, contractual, and policy requirements.
- Control evidence and last test date.
- Security and privacy gaps with severity, likelihood, impact, and remediation.
- Explicit distinction between implemented controls, policy-only controls, planned controls, and unknown controls.
- Safe public claims and prohibited disclosures.

### Hard rules

- **Do not state that the project is "secure", "compliant", "encrypted", "anonymous", or "private" without defining scope and evidence.** Each of these words names a property that holds only within a boundary; without the boundary the word is unfalsifiable and will be read as absolute.
- **Never turn the absence of a known incident into proof of security.** "No breaches reported" is a statement about reporting, not about breaches. It does not appear as a control, a strength, or a public claim.
- Every encryption and control row states the scope it does *not* cover. "Encrypted at rest" covering the primary database but not backups, logs, or the search index is a materially different statement from "encrypted at rest", and the difference is exactly what a reviewer needs.
- A policy is evidence that a policy exists. It is level-7 evidence — inference — that the control operates. The four-way control-state distinction is required on every control, and a policy-only control is never counted as implemented.
- Applicability of a regulation is a claim requiring evidence, and so is compliance with it. Candidate requirements are listed as candidates. Neither applicability nor compliance is asserted from the industry the project is in.
- No credential value, secret name that reveals content, vulnerability identifier with affected versions, or exploitation condition appears anywhere in this document. Remediation stays at the level of what must change, not how the weakness is exploited.
- Whether sensitive data reaches logs is a required determination, not an assumption.
- This is a documentation assessment, not a penetration test or an audit, and the scope section says so.

### Project-type adaptation

- **Library or SDK:** the threat model covers what the library assumes about its caller and what a malicious caller can do; supply-chain controls on the published artifact — signing, provenance, and who can publish — are central. A compromised publishing credential is the highest-impact threat.
- **Data or AI product:** add prompt injection, training-data poisoning, model-output leakage, membership inference, and the boundary between untrusted input and any system that acts on model output. Human oversight is a control with an evidenced state, not a stated intention.
- **Infrastructure:** tenancy isolation, privileged access paths, and control-plane compromise dominate. What one tenant can observe or affect about another is a required determination with evidence, not an assumption from the design.
- **Embedded or connected hardware:** add physical attack surface, debug interfaces left enabled, secure boot, key provisioning and custody, firmware update authentication, and anti-rollback. Physical possession of a device is an assumed attacker capability.
- **Safety-critical:** security and safety interact — a security control that can fail closed into an unsafe state is a hazard, and the interaction is documented rather than treated as two separate assessments.

### Decision-usefulness test

A security reviewer must decide whether to approve a partner integration. It passes if:

1. They can determine what the partner will be able to reach, and what enforces that boundary, from this document and the architecture document.
2. They can tell which controls are implemented and evidenced from those that are policy-only or unknown, without inferring from tone.
3. Every gap they would care about is either listed with a severity, or the document states that the class of gap was not assessed.

---

## reliability-performance-and-observability

| Field | Value |
|---|---|
| Path | `03-assurance/reliability-performance-and-observability.md` |
| Template | `templates/package/03-assurance/reliability-performance-and-observability.md` |
| Audience | Operators, engineers, diligence readers, partner and customer claim drafters |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/system-architecture.md`, `02-architecture/infrastructure-and-deployment.md`, `01-project/product-and-domain.md` for the critical journeys.

### Required content

- Critical user journeys and service dependencies.
- Availability, latency, throughput, durability, freshness, and correctness objectives.
- Service-level indicators, objectives, agreements, and error budgets, with each distinguished from the others.
- Measured performance and load assumptions.
- Capacity model and tested limits.
- Timeout, retry, backpressure, circuit-breaker, queue, cache, and degradation behaviour.
- Observability architecture and coverage of logs, metrics, traces, events, synthetic tests, and business signals.
- Dashboards, alerts, thresholds, owners, and escalation.
- Dependency failure, regional failure, data corruption, and recovery scenarios.
- Chaos, load, soak, failover, backup, and recovery test evidence.
- Known blind spots and operational risks.

### Hard rules

- **Do not convert targets into measured results.** An objective is a statement of intent evidenced by the approving document; a measurement is an observation evidenced by telemetry with a window. They live in separate tables and separate sentences, and no summary merges them.
- **Do not convert internal objectives into customer guarantees.** An SLO becomes an SLA only through a contract. `none` in the SLA column is common and correct; an SLO reported to a customer as an commitment is a promise the project has not made.
- Indicators, objectives, agreements, and error budgets are four different things. Conflating them is the most common reliability-documentation error, and the table keeps them in four columns for that reason.
- Every measured figure carries its window, environment, and measurement source. A latency number without a window is not a measurement.
- Threshold basis is required on every alert. A vendor-default or guessed threshold behaves differently from a measured one, and an operator needs to know which they are trusting.
- A retry configured without idempotency on the target operation is a correctness risk and is recorded as one.
- `not executed` is a valid value in every test-evidence cell and is the honest one where no run is evidenced. A capacity limit that was calculated rather than tested says `calculated`.

### Project-type adaptation

- **Library or SDK:** reliability means behaviour under adverse conditions the caller controls — malformed input, resource exhaustion, concurrent use, downstream failure. Performance claims state the hardware, runtime version, and workload they were measured on, or they are not measurements.
- **Data or AI product:** freshness and correctness objectives matter as much as latency. Evaluation metrics are measurements with a dataset and a date; an evaluation score without its dataset is not a result. Drift detection is an observability signal.
- **Infrastructure:** objectives are per failure domain, and the capacity model must state what happens at the quota boundary, not only at the modelled limit. Noisy-neighbour behaviour is a reliability property.
- **Embedded or connected hardware:** availability includes connectivity assumptions and offline behaviour. Battery, thermal, and duty-cycle limits are capacity limits. Field failure rates are measurements with a fleet size and a window.
- **Safety-critical:** the distinction between a reliability objective and a safety requirement is explicit. A safety requirement is not an SLO and is not subject to an error budget.

### Decision-usefulness test

A customer-facing writer needs a sentence about performance. It passes if:

1. They can find a measured figure with a scope they could publish, or discover that none exists.
2. They cannot accidentally publish an objective as a result, because the two are never adjacent in the same table.
3. An operator reading the same document can find, for any alert, what it means and what to do — the two audiences are served by the same facts, differently arranged.

---

## testing-quality-and-delivery

| Field | Value |
|---|---|
| Path | `03-assurance/testing-quality-and-delivery.md` |
| Template | `templates/package/03-assurance/testing-quality-and-delivery.md` |
| Audience | Engineers, engineering leaders, diligence readers assessing delivery capability |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/components-and-codebase.md`, `02-architecture/infrastructure-and-deployment.md`, `00-control/evidence-ledger.md`.

### Required content

- Software, product, data, AI, hardware, security, accessibility, and operational quality strategy, as applicable.
- Test levels and ownership.
- Test inventory and important coverage gaps, including critical paths with no test listed explicitly.
- Quality gates in local development, CI, release, and production, with whether each is bypassable and what a bypass requires.
- Static analysis, formatting, linting, type checking, dependency scanning, and artifact verification.
- Test data and environment strategy.
- Flaky tests, quarantines, bypasses, and manual gates.
- CI/CD workflows, branch and review policy, artifact provenance, signing, and promotion.
- Release cadence, approval, rollback, and hotfix process.
- Change failure, defect, incident, and delivery metrics, when verified.
- The exact commands executed during documentation verification, with their results.

### Hard rules

- **Coverage percentages state what was measured** — lines, branches, functions, or scenarios — **and are not treated as proof of behavioural quality.** High line coverage over weak assertions is common and tells a reader nothing about correctness.
- Critical paths with no test are listed by name. A coverage number does not surface them, and a reader will assume the important paths are the covered ones.
- A command that was not executed during documentation verification is `not executed` with a reason. It is never recorded as passing.
- The executed-commands table is the source for the `cmd:` locators in the evidence ledger. Every such locator has a row here.
- Production data in a test environment is a privacy finding and is cross-referenced into the security document. It is not a convenience note.
- Quarantined, skipped, and bypassed tests are listed with the date they entered that state. A quarantine with no date is a permanent exclusion nobody decided on.

### Project-type adaptation

- **Library or SDK:** testing across the supported matrix — runtime versions, platforms, and dependency version ranges — is the coverage that matters, and a single-configuration test suite is a coverage gap regardless of its percentage. Consumer-side integration tests and published-artifact smoke tests are the strongest evidence.
- **Data or AI product:** evaluation suites are tests with owners, datasets, and thresholds. Data-quality checks are quality gates. A model promoted without an evaluation gate is documented as such. Non-determinism and how the suite handles it is required content.
- **Infrastructure:** policy-as-code checks, plan review, and drift detection are quality gates. Whether a change can reach production without a plan review is a required determination.
- **Embedded or connected hardware:** hardware-in-the-loop testing, manufacturing test coverage, environmental and compliance testing, and which firmware builds have been tested on which hardware revisions. A test that ran only in simulation is labelled.
- **Safety-critical:** verification evidence per safety requirement is required, and traceability from requirement to test to result is itself a quality gate.

### Decision-usefulness test

A diligence reader must judge whether this team can ship a change safely. It passes if:

1. They can tell what would stop a bad change from reaching production, and what would not.
2. They can identify every gate that is bypassable and what a bypass requires — because a gate everyone routes around is not a gate.
3. They can tell verified delivery metrics from asserted ones, and the document does not offer a metric it could not measure.
