# Disclosure Policy Levels

Governs everything under `06-public/`. Read this before writing a single externally-visible sentence.

A public document is an unretractable commitment. A wrong internal document is corrected in the next revision; a wrong public claim has already been read, quoted, screenshotted, and relied upon. Every default here is therefore the conservative one.

## The five policy values

Set at `dossier.disclosure.policy`. The value classifies material that is not otherwise classified — it is the floor, not a ceiling.

| Policy | Who may read the output | What may appear in `06-public/` | Default `confidentialityDefault` |
|---|---|---|---|
| `public` | Anyone, including search engines and competitors | Only `V`/`C` claims with recorded approval. No unannounced roadmap, no version-specific vulnerability status, no named customers without written consent | `Public` |
| `partner-nda` | Named integration partners under agreement | The above, plus interface detail, rate limits, sandbox mechanics, and support commitments that are contractually real | `Partner-Confidential` |
| `customer-nda` | Existing customers under agreement | The above, plus deployment-model and data-handling detail at the level the contract already commits to | `Partner-Confidential` |
| `internal-only` | The organization only | Public documents are still **drafted** — completely — but released to nobody. Every claim's approval state stays `pending` | `Internal` |
| `regulated` | Constrained by an external regime named in `engagement.regulatory` | Only what the applicable regime permits, with the regime's own review recorded. Applicability is itself a claim requiring evidence | `Restricted` |

**`internal-only` is the default.** When the disclosure boundary is unknown, the correct behaviour is to draft the public documents in full and release none of them — not to guess what is safe to say. A package that omits `06-public/` because the policy was unclear has failed its own structural contract; a package that publishes on a guess has done something worse.

## The approval boundary

`dossier.disclosure.publicClaimApproval` defaults to `required`.

The run may **apply** a disclosure policy. The run may **never appoint itself** the business, legal, security, privacy, or communications approver. Where human approval is required and has not been recorded, the claim's state is `pending`, and a `pending` claim in a public document blocks the release gate.

This is not a formality. "Encrypted at rest", "SOC 2 compliant", "no customer data leaves the region", and "99.9% availability" are each simultaneously a technical claim, a contractual claim, and a marketing claim. Verifying the first does not settle the other two, and only a human with the authority to bind the organization can settle them.

| Situation | Correct handling |
|---|---|
| Claim is technically verified, no approver recorded | State `pending`. Draft the sentence. Do not release the document. |
| Claim appears in existing marketing copy | Existing publication is **neither** disclosure approval **nor** technical proof. Re-verify and re-approve, or withdraw. |
| Claim is obviously true and trivially checkable | Still needs a `CL-####` row. The register's value is completeness, and an exception process is how completeness dies. |
| Approver rejected the claim | Record it in the rejected section with the reason. Remove the sentence, and check whether any other sentence implies it indirectly. |

## Confidentiality classifications

Stamped in every internal document header. These classify the *document*; individual evidence rows carry their own classification, and a document is at least as restricted as its most restricted consumed row.

| Classification | Meaning | May be quoted in `06-public/`? |
|---|---|---|
| `Public` | Already released, or approved for release | Yes |
| `Partner-Confidential` | Shareable under a partner or customer agreement | Only when the policy is `partner-nda` or `customer-nda` |
| `Internal` | Organization only | No — may be *generalized* into a public statement that remains true |
| `Restricted` | Need-to-know: security findings, credentials metadata, personal data, customer identities, legal exposure | Never. Not even generalized, when generalization would still point at the finding |

## What must never cross the boundary

Enforced by `bin/dossier-claim-scan.sh` and the `block-unregistered-claim` hook, and audited by verification pass C.

- Credentials, tokens, keys, connection strings — in any form, including "example" values that are real
- Personal data and customer identities, including in sample payloads. Use synthetic data that is visibly synthetic
- Internal repository paths, file names, evidence IDs, register IDs, and ticket references
- Vulnerability details, unpatched version ranges, and anything that shortens an attacker's path
- Internal hostnames, IP ranges, account identifiers, and topology
- Internal ownership: team names, individual names, escalation chains
- Unannounced roadmap, pricing changes, and customer or partner names not already public
- Internal reliability objectives presented as customer guarantees
- Any claim whose `CL-####` row is `pending` or `rejected`

## What simplification may not do

Public documents are a **projection** of verified internal truth, not a rewrite. Detail may be omitted or generalized. The result may not become false.

| Internal truth | Acceptable public form | Unacceptable public form | Why |
|---|---|---|---|
| AES-256 at rest in the primary store; the analytics replica is unencrypted | "Customer records are encrypted at rest. Derived analytics data is not." | "All data is encrypted at rest." | Simplification inverted a material fact |
| 99.5% measured over the last quarter; no contractual SLA | "Measured availability over the last quarter was 99.5%. No availability level is contractually committed." | "99.9% uptime SLA." | A target, and a measurement, both misrepresented as a guarantee |
| Region-pinned storage; backups replicate cross-region | "Primary storage is region-pinned. Backups replicate to a second region within the same jurisdiction." | "Your data never leaves your region." | An absolute claim the backup path falsifies |
| No known breach | *say nothing about breach history* | "Our platform has never been compromised." | Absence of a known incident is not evidence of security |
| Model output is reviewed by a human before sending | "A person reviews every message before it is sent." | "Fully automated and always accurate." | Removes the oversight control that makes the system safe |

## Prohibited vocabulary without scope and evidence

Each of these is a claim, not an adjective. Using one requires a definition of scope and a `V` or `C` evidence row.

`secure` · `compliant` · `encrypted` · `anonymous` · `private` · `real time` · `unlimited` · `always` · `never` · `guaranteed` · `fully automated` · `zero downtime` · `bank-grade` · `military-grade` · `enterprise-ready`

Prefer the specific replacement: not "encrypted" but "encrypted at rest with AES-256 in the primary store"; not "real time" but "typically under 400 ms, not guaranteed"; not "anonymous" but "pseudonymized — we retain a reversible identifier".

## Derivation procedure

`/dossier:baseline` Phase 5 and `disclosure-gating` follow exactly this order.

1. Start from the **approved** rows of `00-control/claim-and-disclosure-register.md`. Not from internal documents, and never from existing marketing copy.
2. For each approved row, write the public sentence at the partner or customer abstraction level.
3. Strip evidence locators, internal identifiers, confidential detail, security-sensitive implementation detail, and unannounced plans.
4. Preserve every limitation and condition needed to keep the sentence true after stripping.
5. Verify examples against supported behaviour using visibly synthetic data.
6. Run a claim-by-claim comparison of the rendered document against the register. Any sentence in the document without a matching approved row is a release-gate failure — not a warning.

Zero unsupported public claims is a gate condition, not an aspiration.

## When there is no external surface

Some projects have no partners, no customers, or no external interface. The canonical files stay; the sections are marked `N/A` with the evidence for that conclusion, and `technical-partner-guide.md` explains the supported partnership model instead. Deleting the file is not an option — a missing canonical file is indistinguishable from an incomplete run.
