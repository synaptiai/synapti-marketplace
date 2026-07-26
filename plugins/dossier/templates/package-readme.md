# Project documentation package

This directory holds an evidence-first documentation package. Every material
claim in it carries an evidence row naming the source, its authority, the
version observed, and the date. A statement with no such row is not a claim the
package makes.

**Start at [`00-control/documentation-index.md`](00-control/documentation-index.md).**
It routes you to the one document that answers your question, and states up
front how much the package is worth — including its release-gate verdict and
what the verification could not establish.

## What each directory holds

| Directory | Holds |
|---|---|
| `00-control/` | The registers — evidence, open questions and contradictions, public claims, terminology — and the index that routes you |
| `01-project/` | What the project is, who it serves, and what it deliberately does not do |
| `02-architecture/` | Structure, components, data and AI, interfaces, infrastructure |
| `03-assurance/` | Security and privacy, reliability and observability, testing and delivery |
| `04-operating/` | Onboarding, operations and incident response, decisions and risks |
| `05-due-diligence/` | The verdict and its conditions; what is owned, borrowed, and on what terms |
| `06-public/` | The two documents cleared for publication |
| `07-verification/` | How much this package's own claims are worth |

## How to read a claim

Internal documents cite evidence identifiers inline. Each resolves to a row in
`00-control/evidence-ledger.md`, and each row carries a claim state: verified,
corroborated, reported, inferred, unknown, or not applicable. Only verified and
corroborated claims appear as unqualified fact.

The public documents carry no identifiers by design — they would expose internal
structure and help no reader. Their traceability lives in
`00-control/claim-and-disclosure-register.md`, which maps every published
sentence to the evidence behind it and to the person who approved it.

A gate verdict of not-releasable is the package working, not failing. The
conditions it names are in `07-verification/documentation-verification-report.md`.

---

This file is a signpost. It asserts no fact about the project, so it cannot go
stale; everything that can is in the index.
