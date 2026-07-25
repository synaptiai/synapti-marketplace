# Package Contract — `07-verification/`

Reference document. Required content, audience, confidentiality, dependencies, and decision-usefulness test for the verification document. One section; the anchor matches the `<!-- contract: -->` pointer on body line 2 of the corresponding template.

---

## documentation-verification-report

| Field | Value |
|---|---|
| Path | `07-verification/documentation-verification-report.md` |
| Template | `templates/package/07-verification/documentation-verification-report.md` |
| Audience | Anyone deciding whether to rely on the package — decision makers, package owners, subsequent verifiers |
| Default confidentiality | Internal |
| Header style | `internal-v1` |

**Depends on:** every document and every register in the package. It is the last document written and the first a skeptical reader should open.

### Required content

- Verification scope and project version.
- Reviewer-pass independence method.
- Checks performed and evidence used.
- Scorecard and release-gate result.
- Findings by severity.
- Corrections applied.
- Unresolved findings and why they remain.
- Cross-document consistency result.
- Public disclosure and secret-safety result.
- Command, example, link, and diagram validation result.
- Residual uncertainty.
- Final package status: `release-ready`, `conditionally ready`, or `not ready`.
- Exact next actions, owners, and evidence required.

### Hard rules

- **Never report a check as passing when it did not run.** Every check row is `passed`, `failed`, or `not executed` with a reason, and the not-executed list states what each would have established.
- **Findings are published before repair.** The findings table records what each pass found, not what survived correction. A report showing only corrected findings hides the package's actual defect rate, which is the number a subsequent reader most needs.
- **Do not claim perfection.** State what was verified, what remains uncertain, and whether the gates pass.
- **The independence method is reported honestly, including its limits.** A plugin can guarantee separate context; it cannot guarantee a different model. Which mechanism was used — separate agent contexts, an external independent model, or reset frames within one context — is recorded, along with whether any pass saw another's findings before producing its own. Claiming independence the execution did not have is a `Critical` finding against this document itself.
- **The gate is conjunctive.** A high score never carries a failed condition. Where a gate cannot pass, the package is issued as conditionally ready or not ready, with exact blockers and evidence requests — not adjusted until it passes.
- **Every scorecard deduction cites at least one finding identifier.** An unexplained deduction is unarguable, and an unarguable score is not a measurement.
- **Do not inflate to match an author's self-assessment.** Where an independent audit and a self-assessment differ, both numbers are reported and the difference is explained by findings.
- **Disclosure findings name the file and the nature of the problem, never the matched value.** A verification report that reproduces a leaked secret in order to report it has leaked it twice.
- Severity vocabulary is fixed: `Critical` could cause a fundamentally wrong transaction, security, safety, legal, operational, or public decision; `High` could materially mislead diligence, onboarding, integration, deployment, incident response, or customer trust; `Medium` creates meaningful ambiguity, friction, inconsistency, or maintainability risk; `Low` is a localized clarity, formatting, or completeness issue with limited decision impact.
- Findings are merged across passes without losing evidence. Reviewer disagreement is resolved by evidence, never by majority vote, and a finding one pass raised is not dismissed by another pass's silence.
- Where a correction materially changes architecture, product behaviour, data handling, security, reliability, or a public claim, the affected passes re-run and the report says so.
- A refresh advances `last-verified` only on the documents it re-verified. A package-wide date stamp applied after a partial verification is indistinguishable from a package-wide false claim.

### Project-type adaptation

The verification report's structure does not vary by project type; what varies is which claims are audited at 100%. In addition to the always-100% categories — public capabilities and limitations; security, privacy, compliance, safety, and data-handling claims; reliability, performance, availability, recovery, support, and compatibility claims; current-versus-planned distinctions; material due-diligence conclusions and remediation estimates; setup, build, test, deploy, rollback, backup, restore, and incident instructions; asset ownership, IP provenance, dependency, end-of-life, and licensing claims; architecture trust boundaries and sensitive data flows — add:

- **Library or SDK:** every compatibility, supported-version, and deprecation-timeline claim, and every published example, since consumers execute them verbatim.
- **Data or AI product:** every accuracy, evaluation, provenance, and training-data claim, and every statement about whether customer data is used for training.
- **Infrastructure:** every isolation, tenancy, capacity, and recovery claim, since each is a promise other teams build on.
- **Embedded or connected hardware:** every certification, physical-safety, environmental-limit, update-capability, and end-of-support claim.
- **Safety-critical:** every claim bearing on hazard control, safety requirements, verification evidence, residual risk, and human fallback — and none of these may rest on evidence below authority level 4.

For lower-impact internal claims, the sampling method and size are stated. A sample without a stated method cannot be reasoned about.

### Decision-usefulness test

A reader who does not trust the package opens this report first. It passes if:

1. They can tell what was actually checked and what was not, without inferring it from the absence of a finding.
2. They can tell whether the three passes were genuinely independent, and how independent, in one paragraph.
3. If the verdict is `release-ready`, they can see the gate conditions and satisfy themselves that each was met — and if it is not, they can see exactly what would change it and who must supply it.
