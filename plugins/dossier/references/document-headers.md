# Document Headers

Reference document. The canonical header block that opens every file in the dossier package, in two variants: `internal-v1` for the 21 internal documents and `public-v1` for the 2 documents under `06-public/`. `bin/dossier-package-check.sh` parses these headers; `templates/header-internal.md` and `templates/header-public.md` are the literal blocks a drafter copies.

## Form: YAML frontmatter

Headers are **YAML frontmatter** — a `---` fence, `key: value` lines, a closing `---` fence, as the first bytes of the file. There is exactly one representation of every field. No parallel rendered table, no HTML comment twin.

Why frontmatter and not a rendered table plus a machine-readable comment:

| Consideration | Outcome |
|---|---|
| Drift | A rendered table duplicating a comment block means every header edit is two edits. Cross-document duplication that invites drift is one of the failure modes the verification passes hunt for; the package should not seed it in its own headers. |
| House precedent | Skills, agents, and the flow decision journal already carry YAML frontmatter in Markdown. A reader of this repo knows the shape. |
| Rendering | GitHub renders frontmatter in `.md` files as a table, so the internal header is visible to a human reader without a second copy. |
| Parsing | One `---`-fenced block with flat scalar values parses with `python3 -c 'import yaml'`, with `awk`, or with a five-line shell loop. `dossier-package-check.sh` uses the shell path so the check runs with no Python dependency. |

Constraints that make the shell path safe:

- All values are flat scalars except `related`, which is a flow-style YAML sequence written on one line (`related: [a, b]`) or as a block list.
- No nested mappings, no anchors, no multi-line scalars. A value that needs a colon-space or a leading `[`, `{`, `#`, `*`, `&`, `>`, `|`, `%`, `@`, `` ` `` must be double-quoted.
- Keys appear in the order given below. Order is not required for parsing but is required for review — a header that reorders fields makes header diffs unreadable.

## Body layout

```text
---
<frontmatter>
---
# <Document Title>
<!-- contract: references/package-contract-<dir>.md#<doc-slug> -->

## <first section>
```

The **body** is everything after the closing `---`. Body line 1 is the H1. Body line 2 is the contract pointer. This is positional and mechanically checked: `dossier-package-check.sh` reads body line 2, extracts the reference path and anchor, and asserts the reference file exists and contains a heading whose GitHub anchor matches. There is no blank line between the closing fence and the H1.

The contract pointer is an HTML comment, so it does not render. It is the only HTML comment permitted in the header region — a second comment on body line 2 shifts the pointer and fails the check.

## Internal header — `internal-v1`

Used by all 21 documents outside `06-public/`.

```yaml
---
dossier-header: internal-v1
title: {fill}
purpose: {fill}
audience: {fill}
confidentiality: Internal
owner: {fill}
status: draft
project-version: {fill}
last-verified: {fill}
review-trigger: {fill}
related: []
---
```

| Key | Type | Rule |
|---|---|---|
| `dossier-header` | literal | Always `internal-v1`. The schema discriminator. A parser that does not recognize the value must fail loudly rather than guess. |
| `title` | string | Human title of the document. Must match the H1 on body line 1 exactly. Two titles that disagree is a Medium finding. |
| `purpose` | string | One sentence naming the decision or task the document supports. Not a restatement of the title. "Architecture documentation" is not a purpose; "lets a reviewer decide whether the trust boundaries hold before a partner integration" is. |
| `audience` | string | Comma-separated reader roles from the terminology register, most-important first. Not "everyone". A document whose audience is everyone has no audience. |
| `confidentiality` | enum | `Public` \| `Partner-Confidential` \| `Internal` \| `Restricted`. Defaults to `disclosure.confidentialityDefault` (plugin default `Internal`). Never lower than the most restrictive evidence the document cites — a document citing one `Restricted` row is `Restricted`. |
| `owner` | string | A named person or a named team from the terminology register, or the literal `unassigned`. Never invented. `unassigned` is a true statement about the project; a plausible-looking owner is a false one. |
| `status` | enum | `verified` \| `partially verified` \| `draft` \| `N/A`. See the status ladder below. |
| `project-version` | string | The commit, tag, or release the document describes, or `unknown`. Not the date. A document with no pinned version cannot be re-verified, because there is nothing to re-verify it against. |
| `last-verified` | date | ISO `YYYY-MM-DD`. The date the document's claims were last checked against evidence — **not** the date the file was last edited. A formatting fix does not advance it. |
| `review-trigger` | string | The change event that invalidates this document, stated concretely. "Quarterly" is a cadence, not a trigger; both may appear, but a trigger is required. |
| `related` | list | Package-relative paths of the canonical documents this one depends on or is depended on by, e.g. `[02-architecture/system-architecture.md, 00-control/evidence-ledger.md]`. Every entry must resolve; `dossier-package-check.sh` treats a dangling entry as a finding. May be `[]` only for `00-control/documentation-index.md`. |

### Status ladder

| `status` | Means | Entry condition |
|---|---|---|
| `verified` | Every material claim in the document is `V` or `C` in the evidence ledger, and every executable instruction was executed. | No `R`, `I`, or `U` claim carries decision weight in the document. |
| `partially verified` | The document is accurate but incomplete — some material claims are `R`, `I`, or `U`, and each is labelled in place. | Every unverified claim is visibly marked and appears in the assumptions or open-questions register. |
| `draft` | Structure and some content exist; grounding is not complete. | Default for a newly scaffolded document. |
| `N/A` | The topic is demonstrably irrelevant to this project. | A reason and a `[EV-####]` citation supporting the irrelevance are in the body. The file still exists — see the package contract for `00-control`. |

`status` never advances on the strength of the drafter's confidence. It advances when the ledger supports it. Downgrading is always permitted and never requires approval; a stale `verified` is worse than an honest `draft`.

## Public header — `public-v1`

Used by `06-public/technical-partner-guide.md` and `06-public/customer-product-and-trust-guide.md`.

```yaml
---
dossier-header: public-v1
title: {fill}
audience: {fill}
product-version: {fill}
last-updated: {fill}
---
```

| Key | Type | Rule |
|---|---|---|
| `dossier-header` | literal | Always `public-v1`. |
| `title` | string | Must match the H1 on body line 1. |
| `audience` | string | The external reader, in the reader's own vocabulary — "integration partners", "administrators evaluating the product". Not an internal role name. |
| `product-version` | string | The **product** version the document applies to, not the commit. A commit SHA in a public header is a repository detail leak. |
| `last-updated` | date | ISO `YYYY-MM-DD`. |

`package.headerStyle` in settings names the internal variant (`internal-v1`) because that is the variant that will version independently; `public-v1` is pinned to it. Both variants change together or the setting gains a new value.

### What the public header must never contain

The public header is rendered to external readers. These are prohibited, and `dossier-package-check.sh` plus the disclosure gate both check for them:

| Prohibited | Why |
|---|---|
| Internal repository paths, file names, module names, branch names | Reveals structure an attacker would otherwise have to guess, and creates a support burden when it changes. |
| `[EV-####]` citations, `AQ-`, `CT-`, `CL-`, `TM-` identifiers | Evidence identifiers are internal traceability. Their presence invites requests for evidence that is not disclosable. |
| Vulnerability detail, unpatched-version identifiers, exploit conditions | Directly exploitable. |
| Customer names, customer-confidential facts, private user data | Contractual and legal exposure, usually irreversible once published. |
| Internal ownership — person names, team names, on-call rotations, escalation identities | Social-engineering surface, and it is wrong the day someone changes role. |
| `confidentiality`, `owner`, `status`, `review-trigger`, `project-version` keys | Internal-only fields. Their presence in a public file means an internal header was copied without translation. |

Traceability is not lost by omitting these — it lives in `00-control/claim-and-disclosure-register.md`, where every public sentence maps to its `CL-####` row, its `[EV-####]` support, and its approval state. The public document is the projection; the register is the record.

The same prohibitions apply to the public **body**, not only the header. The header rules are stated here because they are mechanically checkable; the body rules live in `references/package-contract-06-public.md`.

## Header maintenance rules

1. **`last-verified` is a claim.** Advancing it asserts that someone re-checked the document against evidence on that date. Advancing it without re-checking is the single most damaging thing that can be done to this package, because it converts stale documentation into documentation that *looks* current.
2. **A refresh stamps only what it touched.** A targeted refresh advances `last-verified` on the documents it re-verified and leaves the rest alone. A package-wide date stamp is indistinguishable from a package-wide lie.
3. **`status` and `confidentiality` move independently.** A `draft` can be `Restricted`; a `verified` document can be `Public`.
4. **Header edits are ordinary edits.** They are not exempt from the evidence rule. Changing `owner` requires evidence of the ownership, recorded in the terminology register.
5. **The index mirrors the headers.** `00-control/documentation-index.md` carries a table of all 23 documents with owner, audience, confidentiality, status, and last-verified date. Those cells are copies of header values; when they disagree, the header wins and the index is the defect.

## Parsing contract

Consumers may rely on:

- The file begins with `---\n`. No byte, including a BOM or a blank line, precedes it.
- The closing fence is a line that is exactly `---`.
- Every line between the fences matches `^[a-z][a-z-]*: ` or is a continuation of a block list started by the preceding key.
- Every key listed above is present, and its value is non-empty after trimming. `{fill}` counts as **empty** for the check — an unfilled template placeholder is a missing field, not a value.
- `last-verified` / `last-updated` match `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`.
- `status` and `confidentiality` are drawn from their enums, case-sensitively.

Consumers may **not** rely on key order, on the absence of extra keys, or on `related` using inline rather than block list syntax. Extra keys are permitted for project-specific needs and are ignored by the check; they are not permitted in `public-v1`.
