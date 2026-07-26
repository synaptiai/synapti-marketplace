# Package Contract — `04-operating/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the three operating documents. One section per document; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

These three documents are read under time pressure by someone who has to do something — join a team, recover a system, decide what to fix. Prose that reads well and cannot be executed fails here in a way it does not fail elsewhere in the package.

---

## onboarding-and-local-development

| Field | Value |
|---|---|
| Path | `04-operating/onboarding-and-local-development.md` |
| Template | `templates/package/04-operating/onboarding-and-local-development.md` |
| Audience | New engineers, product managers, designers, data and AI practitioners, operators, security staff, leaders |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/components-and-codebase.md`, `03-assurance/testing-quality-and-delivery.md`, `00-control/terminology-and-ownership.md`.

### Required content

- Audience-specific onboarding routes for engineering, product, design, data and AI, operations, security, and leadership.
- Prerequisites, supported versions, access requests, and expected setup time.
- Safe setup commands from a clean starting point.
- Configuration and secret acquisition, without secret values.
- Local dependencies and seed or synthetic data.
- Build, run, test, debug, reset, and cleanup procedures.
- Development workflow: branching, review, CI, release, and feature-flag flow.
- Architecture and domain reading order.
- First-day, first-week, and first-month outcomes.
- A small verified starter task, or a guided code trace.
- Common failure modes and troubleshooting.
- How to propose product, architecture, security, and documentation changes.
- Definitions of done for engineering and product work.
- Where to get help, and current ownership gaps.

### Hard rules

- **Never tell a new teammate to use production credentials or production data for local development.** No step in this document takes a production credential as input, and no seed-data instruction points at a production export. This is not a style preference — onboarding documentation is the most-followed documentation a project has, and it is where credential sprawl and data leakage start.
- **Mark every command `verified`, `partially verified`, or `not executed`, with the environment and date.** An unmarked command is an unverified command presented as a working one.
- Setup begins from a clean starting point. A procedure that only works on a machine that already has the previous developer's state is not a setup procedure.
- Every step states how the reader can tell it worked. A step with no success signal is a step a reader cannot debug.
- Configuration entries name settings, purposes, and where to obtain a development value. Never a value.
- Seed data is synthetic or anonymised at source, and a dataset described as anonymised names the technique and its known limits.
- Expected setup time is measured, with the machine and date it was measured on, or it is omitted. An optimistic estimate is worse than none.
- The starter task is real and was executed. A hypothetical starter task is the most common way this document fails its only test.
- Current ownership gaps are stated. A new teammate who spends a week looking for an owner who does not exist was misled by the omission.

### Project-type adaptation

- **Library or SDK:** the first meaningful contribution is usually a change plus a consumer-side test proving it. Onboarding covers building the artifact locally and consuming it from a scratch project, because that is the loop a library developer lives in.
- **Data or AI product:** local development needs a synthetic dataset and a way to run the evaluation suite without production data or production model credentials. Cost of running the loop locally is a prerequisite, and an undisclosed per-run cost is a real onboarding hazard.
- **Infrastructure:** the equivalent of "run it locally" is a sandbox account or a scoped environment. If none exists, the document says so plainly rather than describing a local flow that does not exist. Which operations a newcomer may perform, and where, is required content.
- **Embedded or connected hardware:** hardware prerequisites, which board revisions are supported, flashing and recovery procedures, and how to unbrick a device. A newcomer who bricks their only board on day one is blocked for a week.
- **Safety-critical:** what a newcomer may not do, and the authorization required for anything touching a safety function, comes before the setup instructions rather than after them.

### Decision-usefulness test

A new engineer follows this document on a clean machine with no help. It passes if:

1. They reach a running system and a passing test suite, and every step told them how to confirm it worked.
2. They complete the starter task and can explain what their change did.
3. Every command they ran carried a verification mark, so they knew in advance which steps were checked and which were not.

If any step required asking someone, that step is a finding — and the fastest way to find those findings is to execute the document in a clean environment.

---

## operations-and-incident-response

| Field | Value |
|---|---|
| Path | `04-operating/operations-and-incident-response.md` |
| Template | `templates/package/04-operating/operations-and-incident-response.md` |
| Audience | Operators, on-call engineers, incident commanders, security responders |
| Default confidentiality | Internal — `Restricted` where it describes privileged access |
| Header style | `internal-v1` |

**Depends on:** `02-architecture/infrastructure-and-deployment.md`, `03-assurance/reliability-performance-and-observability.md`, `03-assurance/security-privacy-and-compliance.md`, `00-control/terminology-and-ownership.md`.

### Required content

- Operational scope and responsibility model.
- Service and dependency inventory by criticality.
- Deployment, rollback, restart, failover, backup, restore, scaling, and maintenance procedures.
- Alert triage and diagnostic entry points.
- Runbook catalog for credible failure modes.
- Incident severity, declaration, command, communication, escalation, mitigation, recovery, and closure.
- Security and privacy incident handling, and how it differs from a standard incident.
- Customer and partner communication boundaries.
- Evidence preservation, and regulatory or contractual notification needs.
- Status communication, post-incident review, action tracking, and the learning loop.
- Business continuity and disaster recovery.
- Known manual operations and unsafe gaps.
- Last exercise or execution evidence for each critical runbook.

### Hard rules

- **Any command that can cause data loss, downtime, security exposure, or an irreversible effect carries five things: preconditions, blast radius, required authorization, rollback, and post-execution verification.** A destructive command documented without them is a defect, because it will be executed at 3am by someone who has never run it before.
- A runbook that has never been exercised says `never`. A plausible date is worse than no date, because an operator will calibrate their confidence on it.
- A failure mode with no runbook is listed with an empty runbook cell rather than omitted. The omission is what makes the gap invisible.
- Diagnostic entry points state the access required. A diagnostic step an on-call operator cannot perform at 3am is not an entry point.
- Communication boundaries state what must **not** be said, not only what may be. During an incident the constraint is the load-bearing half.
- Notification obligations name their source, trigger, and deadline. A regulatory deadline discovered after the fact is a compliance failure that documentation could have prevented.

### Project-type adaptation

- **Library or SDK:** the incidents are a bad release, a security advisory in a published artifact, and a compromised publishing credential. Procedures are yank, patch-release, and advisory publication, with the communication path to known downstream consumers.
- **Data or AI product:** add pipeline failure, data corruption and its downstream blast radius, model regression, harmful output, and the procedure for disabling a model or falling back to a previous version. Whether a bad model can be rolled back without a retrain is a required determination.
- **Infrastructure:** blast radius per failure domain, tenant-visible impact, and the procedures for the control plane being unavailable. A runbook that assumes the platform is working is not a runbook for the platform being down.
- **Embedded or connected hardware:** fleet-wide update failures, bricked-device recovery, RMA and field-service procedures, and what can be done for a device that cannot be reached remotely. Physical recall criteria and process belong here where they exist.
- **Safety-critical:** the hazard-response path, the human fallback procedure, and the authority to invoke each are documented ahead of the standard incident flow. Notification obligations frequently differ and are listed separately.

### Decision-usefulness test

An operator is paged at 3am for an alert they have never seen. It passes if:

1. The alert appears in triage with a first check they can execute with the access they have.
2. They reach either a resolution or a defensible escalation within the response time the severity table promises.
3. Every destructive step they might take told them the blast radius before they ran it.

---

## decisions-technical-debt-and-risks

| Field | Value |
|---|---|
| Path | `04-operating/decisions-technical-debt-and-risks.md` |
| Template | `templates/package/04-operating/decisions-technical-debt-and-risks.md` |
| Audience | Engineering leaders, architects, diligence readers, anyone about to reverse a decision |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** every architecture and assurance document. Drafted after them, because a risk register written first records anticipated risks rather than observed ones.

### Required content

- Decision log or index of architecture and product decisions.
- Known rationale and alternatives, only where evidenced.
- Unresolved decisions and decision deadlines.
- Technical debt register.
- Product, architecture, delivery, security, privacy, reliability, data, AI, dependency, cost, licensing, staffing, and operational risks.
- Likelihood, impact, detectability, urgency, evidence, mitigation, owner, and status for each risk.
- Dependencies between risks.
- Accepted risks and the acceptance authority.
- Remediation roadmap grouped into immediate, near-term, and strategic horizons.
- Distinction between risk reduction, capability investment, and optional improvement.

### Hard rules

- **Do not retroactively invent why a historical decision was made.** Where no decision record, commit message, or discussion evidences the rationale, it is `unknown` — and unknown rationale is itself decision-relevant for anyone considering a reversal, because they cannot tell what constraint they might be re-discovering.
- Every risk category listed above is represented or explicitly marked `N/A` with a reason. A register missing a whole category usually means the category was not examined, not that it holds no risk.
- Acceptance requires a named human with the authority to accept, plus a date and a basis. A risk marked accepted with no named accepter is an open risk. The package cannot accept a risk on the project's behalf.
- The remediation roadmap separates risk reduction, capability investment, and optional improvement. They compete for the same capacity and are routinely conflated; separating them is what lets a reader judge the roadmap rather than accept it.
- Effort figures are ranges with stated assumptions. Roadmap horizons are ordering, not calendar commitments.
- Technical debt rows state the interest currently being paid. Debt that costs nothing today ranks below debt that taxes every change, and a register without that column ranks by intuition.

### Project-type adaptation

- **Library or SDK:** decisions about the public API are the highest-consequence entries, because reversing one is a breaking change for every consumer. Debt in the public surface is qualitatively different from internal debt and is separated.
- **Data or AI product:** add model and dataset decisions, evaluation-methodology decisions, and the debt carried by unreproducible experiments or datasets of uncertain provenance. Cost risk is first-class.
- **Infrastructure:** add change-control, tenancy-model, and capacity decisions. Debt frequently takes the form of unmanaged resources and manual procedures, which are cross-referenced from the infrastructure document.
- **Embedded or connected hardware:** decisions with hardware consequences cannot be reversed in software, and are marked as such. Component-availability and supply-chain risks belong here. End-of-life and long-term support commitments are risks with a horizon measured in years.
- **Safety-critical:** residual risk after mitigation is documented per hazard, with who accepted it and on what basis. An unaccepted residual risk on a safety function blocks release.

### Decision-usefulness test

An engineering leader must choose what to fix next quarter. It passes if:

1. They can rank the register by decision impact using the columns present, without re-deriving the analysis.
2. For any item they choose to defer, they can see what it costs to keep deferring it.
3. Before reversing an existing decision, they can tell whether the original rationale is known — and if it is not, the document says so rather than offering a plausible reconstruction.
