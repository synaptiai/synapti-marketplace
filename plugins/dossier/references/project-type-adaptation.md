# Project Type Adaptation

How the fixed 23-file package adapts to what the project actually is.

## The rule

**Content adapts. Structure never.**

Every project gets all 8 directories and all 23 files. A library still has `infrastructure-and-deployment.md`; a project with no AI still has `data-and-ai.md`. What changes is which sections carry substance and which carry a justified `N/A`.

This is not bureaucracy. A package whose shape varies per project cannot be diffed across revisions, compared across engagements, or audited against a checklist — and "we dropped that file because it did not apply" is indistinguishable from "we ran out of time" six months later. An `N/A` with evidence is a finding; a missing file is a hole.

## Classifying the project

`dossier.project.type` defaults to `auto`. Classification happens in Phase 1 from evidence, and the classification itself is recorded with its supporting evidence IDs — it drives what gets emphasized, so a wrong classification produces a subtly wrong package.

| Type | Evidence that classifies it |
|---|---|
| `application` | A user-facing entry point, UI assets, session or auth handling, an end-user deployment target |
| `service` | A network listener, an API contract, a deployment unit, callers it does not own |
| `platform` | Multiple services with a shared substrate, tenancy model, internal consumers with their own release cycles |
| `library` | A package manifest published to a registry, no deployment unit of its own, semver discipline, downstream consumers |
| `data-product` | Pipelines, schedules, warehouse or lake targets, lineage, freshness contracts |
| `ai-system` | Model invocation, prompts, retrieval, evaluation suites, model or dataset versioning |
| `infrastructure` | IaC as the primary artifact, tenancy and access as the primary concern, no application logic |
| `embedded` | Firmware sources, a bill of materials, board definitions, provisioning or flashing tooling |
| `mixed` | More than one of the above with genuinely different characteristics — the common real answer |

Choose `mixed` rather than forcing a bad fit, and record which component is which in the terminology register. Do not force web-service assumptions onto a library, a model, a device, or an offline tool.

## Emphasis by type

What to deepen. Everything not listed still gets its baseline treatment.

### Library / SDK

- Package boundary: what is public API, what is internal, and how that line is enforced rather than merely documented
- Compatibility matrix: language and runtime versions, peer dependencies, platform support, with the evidence for each cell
- Versioning discipline: semver policy, what constitutes a breaking change *for this package*, deprecation window
- Downstream consumers: who depends on this, discovered from evidence not assumed, and what breaks them
- Installation and first-use examples that were actually executed
- Build reproducibility, artifact signing, and registry provenance

`infrastructure-and-deployment.md` covers the release pipeline and registry rather than servers. `reliability-*.md` covers consumer-observed failure modes — a panic in a hot path is this project's outage.

### Data product

- Lineage end to end: source systems, transformations, sinks, and what breaks when an upstream schema changes
- Freshness and correctness contracts, and how violations are detected rather than noticed
- Backfill and reprocessing: how, at what cost, and what is not reprocessable
- Data quality controls, their coverage, and the gaps
- Schema evolution and consumer compatibility
- Retention, residency, deletion, and the regulated-data inventory

### AI system

Beyond the data-product items:

- Model, agent, prompt, tool, retrieval, and memory architecture — as an actual architecture, with boundaries
- Model and dataset **provenance**: origin, license, and whether training data permits the current use
- Evaluation: what suite, what it measures, what it does not measure, and the last time it ran
- Prompt injection, data leakage, unsafe output, excessive autonomy, and model drift — controls and gaps
- **Human oversight**: where a person is in the loop, what they see, and what happens when they are not there
- Cost and latency per operation, fallback behaviour, and vendor dependency
- Reproducibility: can a given output be reproduced, and if not, say so plainly

The prohibition on absolute claims is sharpest here. "Accurate", "always safe", and "fully automated" are each a claim requiring evidence and, in a public document, approval.

### Infrastructure / platform

- Tenancy and isolation: what separates tenants, and what would happen if it failed
- Access model, privileged operations, break-glass procedures, and their audit trail
- Configuration management, drift detection, and what is managed outside IaC
- Capacity, quotas, scaling boundaries, and cost drivers with their cliffs
- Failure domains, blast radius, and dependency graphs between them
- Change control, promotion path, and rollback limitations — including changes that cannot be rolled back
- Backup, restore, and recovery objectives **with the date each was last tested**

Never claim high availability, an RPO, an RTO, zero downtime, or geographic redundancy without current evidence that it was exercised, not merely configured.

### Embedded / connected hardware

Adds concerns the other types do not have:

- Electrical and mechanical interfaces, and the firmware/hardware boundary
- Bill of materials, component lifecycle, single-source parts, and lead times
- Manufacturing test, provisioning, and device identity issuance
- Secure boot, key storage, and the update mechanism — including what happens to a device that misses updates for a year
- Field service, diagnostics, and return handling
- Physical safety, certification status, and the evidence behind each certificate
- Supply chain and counterfeit exposure
- End-of-life: security support window, and what the device does after it

`infrastructure-and-deployment.md` covers fleet and update infrastructure. `operations-and-incident-response.md` covers field incidents, which cannot be rolled back the way a deployment can.

### Safety-critical

Adds, in `03-assurance/` with a supplemental safety case when the volume warrants it:

- Hazard analysis and the method used
- Safety requirements traced to verification evidence
- Residual risk with its acceptance authority
- Human fallback and degraded-mode behaviour

## Marking `N/A` correctly

An `N/A` is a claim: "this is demonstrably irrelevant to this project." It needs evidence like any other claim.

| Situation | Correct |
|---|---|
| No AI component | `N/A — no model invocation, inference dependency, or ML artifact found across `sources`. [EV-0031]` |
| No persistent data | Do **not** mark the document `N/A`. Explain how state is handled instead — statelessness is a design fact worth documenting |
| No external interface | Interface sections `N/A` with evidence; `technical-partner-guide.md` explains the supported partnership model |
| No customers yet | Product sections describe intended users and their evidence; do not invent adoption |
| Not inspected | **Never `N/A`.** This is `U — unknown` with an entry in the open-questions register. Conflating "does not apply" with "we did not look" is the single most common way a package misleads |

The last row is the one that matters. `N/A` and `Unknown` are opposite claims, and a verification pass that finds one used for the other raises it as a High finding.

## Section-level, not file-level

Adaptation happens *inside* files. A library's `infrastructure-and-deployment.md` is short and concrete — registry, build, signing, promotion — not absent. A stateless service's `data-and-ai.md` explains state handling and marks the AI sections `N/A` with evidence. The reader always knows where to look, and the absence of content is itself informative.
