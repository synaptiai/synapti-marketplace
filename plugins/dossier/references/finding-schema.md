# Finding Schema (canonical verifier output)

Reference document. The row shape every verification pass emits, the marker that makes a pass file machine-readable, and the normalization rules that turn three independent pass files into one reconciled ledger.

A dossier finding is a defect **in the documentation package**, evidenced by something **outside** it. That asymmetry is the schema's organizing rule: `location` always points inside `project.outputRoot`; `verifier_evidence` always points at project source, a command result, or a register row the pass actually opened. A row that cannot fill both is not a finding — see [Rejection rules](#rejection-rules).

This schema is a sibling of `plugins/flow/references/finding-schema.md` and borrows its cell-packing discipline and its pipe-escaping rule, but the field set is different and the two are not interchangeable. Flow findings are `file:line` code defects prioritized `P1/P2/P3`; dossier findings are documentation defects scored `Critical/High/Medium/Low` against a weighted scorecard dimension.

## Required fields

Every row emitted by a verification pass MUST carry all ten fields.

| Field | Type | Description |
|---|---|---|
| `id` | string | Pass letter plus ordinal — `A1`, `B7`, `C3`. Ordinals start at 1 per pass per round and are never reused. See [ID grammar](#id-grammar). |
| `severity` | enum | `Critical` \| `High` \| `Medium` \| `Low`. See [Severity definitions](#severity-definitions). |
| `dimension` | integer 1–10 | The scorecard dimension the finding scores against, per `references/scorecard-rubric.md`. Rendered `D7`. Exactly one — a finding that plausibly touches three dimensions is assigned to the one whose deduction it will justify. |
| `location` | string | Where in the package the defect lives. Always relative to `project.outputRoot`. See [Location grammar](#location-grammar). |
| `claim` | string | The asserted text, **verbatim**, quoted from the document. For an omission, `— (omission)`; the expected assertion then belongs in `problem`. |
| `problem` | string | What is wrong with the claim, stated against the evidence. Not "unclear" — what a reader would wrongly conclude and why the evidence does not support it. |
| `required_repair` | string | The exact change. A repair a drafter cannot execute without asking a follow-up question is not a repair. |
| `evidence_still_needed` | string | What must be obtained before the repair can be verified, or `none` when the repair is complete on its own. `none` is a positive statement; blank is a missing field. |
| `verifier_evidence` | string | The source path, symbol, command, or register row **this pass actually checked**, with revision or execution date. See [Verifier evidence](#verifier-evidence). |
| `status` | enum | `Open` \| `Corrected` \| `Accepted risk` \| `Blocked`. A pass always emits `Open`; the other three values are written only by reconciliation. |

## Fields added by reconciliation

Never emitted by a pass. A pass that emits either of these has been contaminated — it saw another pass's output, which the independence contract in `references/independent-audit-protocol.md` forbids.

| Field | Type | Description |
|---|---|---|
| `corroboration` | string `N/M` | Distinct passes that independently produced a row with the same dedup key, over the number of passes that ran. Descriptive only. See [Corroboration semantics](#corroboration-semantics). |
| `contradiction` | string | `CT-####` register ID, present only on cross-pass disagreement findings. See [Disagreement is a finding](#disagreement-is-a-finding). |

## Severity definitions

Carried from the source contract without softening. Severity is a statement about the **decision the reader would get wrong**, not about how much text needs rewriting.

| Severity | Definition |
|---|---|
| `Critical` | Could cause a fundamentally wrong transaction, security, safety, legal, operational, or public decision. |
| `High` | Could materially mislead diligence, onboarding, integration, deployment, incident response, or customer trust. |
| `Medium` | Creates meaningful ambiguity, friction, inconsistency, or maintainability risk. |
| `Low` | Localized clarity, formatting, or completeness issue with limited decision impact. |

Two consequences bind elsewhere:

- `gate.failOn` defaults to `["Critical", "High"]`, so any row at those severities with status `Open` or `Blocked` fails release-gate condition G03.
- An unresolved `Critical` caps its dimension at 4.0 and an unresolved `High` caps it at 7.0, per `references/scorecard-rubric.md`. Because the per-dimension floor is 8.0, a single unresolved `High` fails the gate through the scorecard as well as through G03.

A pass may not downgrade a severity because the repair is cheap, because the document is internal-only, or because the same defect appears elsewhere. Cost, audience, and frequency are reconciliation's inputs to sequencing, not to severity.

## ID grammar

IDs match `^(A|B|C|EA|EB|EC|E|X)[0-9]+$`.

| Prefix | Issued by | Meaning |
|---|---|---|
| `A` | `dossier-pass-a-evidence` | Independent coverage, claim sample, evidence integrity |
| `B` | `dossier-pass-b-falsification` | End-to-end traces against the sources |
| `C` | `dossier-pass-c-audience` | Audience usability, mechanics, consistency, disclosure |
| `EA` / `EB` / `EC` | External audit that split by lens | Ingested via `/dossier:reconcile --findings <path>` |
| `E` | External audit that did not split by lens | Same ingest path |
| `X` | Reconciliation only | Cross-pass disagreement, always `Critical` |

Round-qualified form for cross-round references is `R<round>-<id>` — `R2-A7`. Use it in the verification report and in the contradiction register; use the bare form inside a single round's pass file.

IDs are never renumbered. When reconciliation merges two rows, the survivor keeps the ID of the highest-severity contributor and the merged IDs are listed in the survivor's `verifier_evidence`, so provenance survives the merge.

## Location grammar

`location` is always inside the package. Line numbers drift, so prefer stable anchors.

| Form | Example | Use for |
|---|---|---|
| `<file>:§<section>` | `05-due-diligence/technical-due-diligence-report.md:§3.2` | A claim inside a document section |
| `<file>:<register-id>` | `00-control/evidence-ledger.md:EV-0042` | A ledger, claim, contradiction, or question row |
| `<file>` | `02-architecture/data-and-ai.md` | A whole-file defect — missing header, wrong status, absent document |
| `<file>:§<section>:<n>` | `04-operating/onboarding-and-local-development.md:§Setup:3` | The nth command block or list item in a section, when the section alone is ambiguous |

A finding about a project defect rather than a documentation defect is out of scope for every pass. If the source is broken but the documentation describes it accurately, there is no finding — the package is correct. Record it, if it matters, as a risk row in `04-operating/decisions-technical-debt-and-risks.md`, which is a drafting action, not an audit finding.

## Verifier evidence

`verifier_evidence` is what separates an audited finding from an opinion. It records what **this pass** opened, at what revision, on what date.

Acceptable forms:

| Form | Example |
|---|---|
| Source path and symbol at a pinned revision | `infra/terraform/s3.tf` — no `server_side_encryption_configuration` block at `a1b2c3d` |
| Executed command with date | `npm run build` — exit 1, executed 2026-07-25 |
| Register row inspected | `00-control/claim-and-disclosure-register.md:CL-0017` — status `pending`, no `EV-` reference |
| Absence, stated as a search | `grep -rn "circuit.?breaker" src/ lib/` — 0 matches at `a1b2c3d` |
| Not executed, with the reason | `not executed` — `engagement.allowedActions.runTests` is false |

`not executed` is a legitimate value and does not weaken the finding when the finding is *about* the absence of a check. It is never acceptable as the sole evidence for a finding asserting that something is wrong: a pass that could not look may not conclude. When a pass wanted to check something and could not, the correct output is a finding whose `problem` is the unverifiable claim and whose `required_repair` downgrades the claim's state to `U`, not a finding asserting the claim is false.

Absence evidence must be stated as a search that was run, with its pattern and scope. "There is no evidence of X" without the query that failed to find it is unfalsifiable and is rejected at normalization.

## Rejection rules

Reconciliation drops these rows before deduplication and records the count in the verification report. A pass whose rejection rate exceeds 10% is itself a `Critical` finding against dimension 1 — a verifier that cannot follow its own output contract is not producing evidence.

| Rejected when | Why |
|---|---|
| `verifier_evidence` is empty or is prose without a locator | An opinion, not a finding |
| `location` points outside `project.outputRoot` | Not a documentation defect |
| `claim` is a paraphrase rather than the document's words | The repair cannot be applied unambiguously and the dedup hash is unstable |
| `required_repair` is "clarify", "improve", "review", or "consider" | Not executable by a drafter |
| `evidence_still_needed` is blank rather than `none` | Missing field, not an empty one |
| `id` collides with an earlier row in the same pass and round | Provenance is destroyed |
| The row asserts a defect the pass did not check | The definition of an ungrounded claim, produced by the agent whose job is to catch them |

## Marker format

Every pass file begins with exactly one marker on line 1. This is the machine record CI parses; the rendered tables below it are for humans.

```
<!-- DOSSIER_AUDIT round=2 pass=A model=claude-opus-5 started=2026-07-25T09:14:03Z findings=17 critical=2 high=5 -->
```

| Attribute | Required | Grammar | Meaning |
|---|---|---|---|
| `round` | yes | positive integer | Audit round. Increments on each `/dossier:audit`, resets never. |
| `pass` | yes | `A` \| `B` \| `C` \| `EA` \| `EB` \| `EC` \| `E` | Which lens produced the file. |
| `model` | yes | model identifier verbatim, or `unknown` | The honest record of which model ran the pass. `unknown` is permitted and is not a failure; a *wrong* value is. |
| `started` | yes | ISO-8601 UTC, `YYYY-MM-DDTHH:MM:SSZ` | When the pass began, not when the file was written. |
| `findings` | yes | non-negative integer | Total rows in the file. |
| `critical` | yes | non-negative integer | Rows at `Critical`. |
| `high` | yes | non-negative integer | Rows at `High`. |
| `medium` | no | non-negative integer | Recommended. |
| `low` | no | non-negative integer | Recommended. |
| `tier` | no | `in-plugin` \| `external` | Independence tier. Recommended; the verification report requires it regardless of whether the marker carries it. |

Grammar rules:

- Values are unquoted and contain no spaces. A model identifier with a space is written with the space removed, never quoted.
- The seven required attributes appear in the order listed, so a fixed-field parse works without a full attribute scan.
- Unknown attributes are a lint warning, not a parse error. Missing required attributes are a parse error.
- Exactly one marker per pass file. A second marker means two passes were concatenated, which destroys the independence record.

**Count invariant.** `findings` MUST equal the number of rendered rows in the file. When `medium` and `low` are both present, `critical + high + medium + low` MUST equal `findings`. A mismatch is a `Critical` finding against the pass itself: a verifier that miscounts its own output cannot be trusted on anything it counted.

Zero findings is a legitimate result and is written with `findings=0 critical=0 high=0` and an empty table under each severity heading, never by omitting the file. A missing pass file and a clean pass file must be distinguishable.

## Corroboration semantics

`corroboration` is `N/M` — `N` distinct passes produced a row with the same dedup key, `M` passes ran (`|verification.passes|`, plus one when an external audit was ingested).

**A 1/3 finding is never downgraded for being lonely.** This is a hard rule with a specific rationale: the three passes are constructed to have *different* priors — different lenses, different second skills, different dispatches, optionally different models. A defect only one lens can see is the expected product of that design, not a weak signal. Treating corroboration as confidence would convert a system built to decorrelate errors into a majority vote, which is the exact failure the three-pass split exists to prevent.

Concretely:

| Corroboration is | Corroboration is not |
|---|---|
| Recorded on every merged row | An input to `severity` |
| Reported in the verification report as a distribution | A threshold for repair |
| A signal about the **passes** — an all-3/3 finding set means the lenses collapsed and independence failed | A signal about the **finding** |
| Used to order repair when two findings are otherwise equal | Grounds for closing a 1/3 row as noise |

A round in which every finding is 3/3 is reported as an independence failure and re-run with `verification.passModels` differentiated, because three lenses that see identically are one lens dispatched three times.

## Disagreement is a finding

When two passes reach incompatible conclusions about the same claim — pass A records it `Verified`, pass B records it `Unknown`; or one pass passes a claim another pass fails — reconciliation does **not** pick a winner and does **not** average the two.

The disagreement is promoted to its own finding:

| Field | Value |
|---|---|
| `id` | Next `X` ordinal — `X1`, `X2` |
| `severity` | `Critical`, always. Two competent readings of the same evidence produced opposite answers; until that is resolved, every downstream document built on the claim is unsound. |
| `dimension` | The dimension of the underlying claim, or `1` when the claim's dimension is itself disputed |
| `location` | The claim's location, unchanged |
| `claim` | The disputed text, verbatim |
| `problem` | Both readings, both stated fairly, with the evidence each pass cited |
| `required_repair` | Return to primary evidence and produce a new `EV-` row that settles the state — never "accept the more confident pass" |
| `verifier_evidence` | Both contributing pass rows, e.g. `A7` (`infra/terraform/rds.tf:41`) vs `B12` (`grep -rn encryption infra/` — 0 matches outside `rds.tf`) |
| `contradiction` | The `CT-####` row it was routed into |

The row is simultaneously written into the contradiction register in `00-control/assumptions-questions-and-contradictions.md` per `references/register-schemas.md`, carrying the conflicting claims and sources, the likely cause, the decision impact, the owner, and the next verification action. The finding and the `CT-` row are the same fact in two places; closing one without the other is a defect.

`X` findings exist only in the reconciled ledger. A verification pass never sees one — it is produced after all passes have written their files, by a component the passes are firewalled from.

## Deduplication

Applied after rejection, before scoring.

**Dedup key:** `(location_normalized, claim_hash)`.

`location_normalized`:

1. Path made relative to `project.outputRoot`.
2. Lowercased.
3. Trailing `:<n>` ordinal suffix stripped, so `…:§Setup:3` and `…:§Setup:5` collide only if their claims match.
4. Section anchor retained verbatim after `§` — two findings in different sections of one file are different findings.

`claim_hash`:

1. Whitespace collapsed to single spaces, leading and trailing stripped.
2. Lowercased.
3. Trailing sentence punctuation stripped.
4. `sha256`, first 12 hex characters.

Merge rules for a collision:

| Field | Rule |
|---|---|
| `severity` | Keep the **highest**. Never average, never take the majority. |
| `id` | Keep the ID of the highest-severity contributor; ties break by pass order A, B, C, E. |
| `dimension` | Keep the surviving row's. When contributors disagree on dimension, record the alternates in `problem` — a disputed dimension changes which deduction the finding justifies and is worth a sentence. |
| `problem` | Concatenate, attributed by contributing ID, deduplicating identical sentences. Losing a contributor's wording loses the evidence for its severity. |
| `required_repair` | Union. If two repairs conflict rather than compose, the collision is a disagreement — promote it to an `X` finding instead of merging. |
| `evidence_still_needed` | Union. `none` unions to `none` only when every contributor said `none`. |
| `verifier_evidence` | Union, each locator attributed to its contributing ID. |
| `corroboration` | Count of distinct contributing passes over `M`. |
| `status` | `Open`. |

Rows that share `location_normalized` but not `claim_hash` are **not** duplicates. Three findings against three sentences of one section are three findings, and collapsing them would understate the section's defect density — which is exactly the signal dimension 1 scores on.

## Output format

### Pass rendering — three columns

A pass file's rows are always `Open` and a pass cannot know its own corroboration, so both fields are omitted from the rendering and implied by the file's identity.

```markdown
<!-- DOSSIER_AUDIT round=2 pass=A model=claude-opus-5 started=2026-07-25T09:14:03Z findings=4 critical=1 high=1 medium=1 low=1 -->

# Pass A — Evidence and Coverage

Sampling method: census stratum 86 rows (8 categories at 100%); sampled stratum n=30 of 128 remaining
(`max(minRows=30, ceil(0.10 x 128)=13)`), selected by `sha256(claim_id + "r2")` ascending. Defect rate in
sampled stratum: 2/30.

## Critical

| Finding | Problem and required repair | Verifier evidence |
|---|---|---|
| **A1 · D7 · `03-assurance/security-privacy-and-compliance.md:§4.2`**<br>Claim: "All customer data at rest is encrypted with AES-256." | Encryption is configured on the primary database only. The object store and the analytics replica carry no encryption setting in the infrastructure definitions, and no ledger row covers either. The unqualified sentence is repeated in the customer trust guide, where a reader would conclude all stored data is covered.<br>**Repair:** scope the claim to the primary database, or produce evidence for the other two stores. Withdraw `CL-0017` and the public sentence until the scope is settled.<br>**Evidence still needed:** object-store and analytics-replica encryption configuration at the pinned revision. | `infra/terraform/rds.tf:41` — `storage_encrypted = true` at `a1b2c3d`; `infra/terraform/s3.tf` — no `server_side_encryption_configuration` block at `a1b2c3d`; `grep -rn "encrypt" infra/` — 3 matches, all in `rds.tf`, executed 2026-07-25 |

## High

| Finding | Problem and required repair | Verifier evidence |
|---|---|---|
| **A2 · D1 · `00-control/evidence-ledger.md:EV-0042`**<br>Claim: "Median API latency is 120 ms." | State is `V` but the locator is a dashboard screenshot with no date, environment, or percentile definition, and the observed-date column reads `2025-11`. The figure is quoted in the executive brief and the partner guide as current.<br>**Repair:** downgrade `EV-0042` to `R`, add the freshness concern, and qualify both consuming documents with the observation window and environment, or re-observe.<br>**Evidence still needed:** a dated query against the current telemetry source, with environment and percentile stated. | `00-control/evidence-ledger.md:EV-0042` — Version/environment column reads `unknown`; consuming documents `01-project/executive-project-brief.md`, `06-public/technical-partner-guide.md` both quote it unqualified |

## Medium

| Finding | Problem and required repair | Verifier evidence |
|---|---|---|
| **A3 · D2 · `02-architecture/data-and-ai.md:§AI architecture`**<br>Claim: `— (omission)` | Section is marked `N/A — no AI component` with no evidence locator, but the dependency manifest pins an inference SDK and a prompt template directory exists. `N/A` without evidence is indistinguishable from an unexamined section.<br>**Repair:** replace the bare `N/A` with either the evidence that the SDK is unused, or the AI architecture sections the contract requires.<br>**Evidence still needed:** none — the manifest and template directory are sufficient to require the sections. | `package.json:31` — `"@vendor/inference-sdk": "^2.1"` at `a1b2c3d`; `prompts/` — 4 files, most recent commit `a1b2c3d` |

## Low

| Finding | Problem and required repair | Verifier evidence |
|---|---|---|
| **A4 · D10 · `00-control/documentation-index.md`**<br>Claim: "Last verified: 2026-07-19" | Index last-verified date precedes the last-verified dates of four documents it indexes, so the control plane is older than the material it controls.<br>**Repair:** stamp the index last, after the final document write, as the package contract requires.<br>**Evidence still needed:** none. | Header dates in `03-assurance/*.md` (3 files) and `05-due-diligence/technical-due-diligence-report.md` all read `2026-07-25` |
```

### Reconciled rendering — four columns

The reconciled ledger at `.dossier/runs/<run-id>/findings.md` adds `Status` as its own column and appends corroboration to the first cell.

```markdown
| Finding | Problem and required repair | Verifier evidence | Status |
|---|---|---|---|
| **A1 · D7 · 2/3 · `03-assurance/security-privacy-and-compliance.md:§4.2`**<br>Claim: "All customer data at rest is encrypted with AES-256." | … (merged from A1, C6) | … | Open |
| **X1 · D7 · `03-assurance/security-privacy-and-compliance.md:§4.2`**<br>Claim: "All customer data at rest is encrypted with AES-256." | Pass A records this `Verified` from the database configuration; pass B records it `Unknown` after finding two uncovered stores. Both readings are supported by what each pass opened.<br>**Repair:** re-derive the claim state from primary evidence covering every store and issue a replacement `EV-` row. Do not adopt either pass's state.<br>**Evidence still needed:** encryption configuration for all three stores at the pinned revision. | `A1` (`infra/terraform/rds.tf:41`) vs `B12` (`grep -rn encrypt infra/` — 0 matches outside `rds.tf`); routed to `CT-0004` | Open |
```

### Cell construction

- **Finding cell, line 1, bold:** `{id} · D{dimension} · {corroboration, reconciled only} · `{location}``. Severity is not repeated — the `##` section header carries it.
- **Finding cell, line 2** (after `<br>`): `Claim: "{claim verbatim}"`, or `Claim: — (omission)`.
- **Column 2:** `problem` prose, then `**Repair:** {required_repair}`, then `**Evidence still needed:** {evidence_still_needed}`, each separated by `<br>`.
- **Column 3:** `verifier_evidence`, semicolon-separated when there are several locators.
- **Column 4** (reconciled only): `status`.

**Pipe escaping (required):** any literal `|` inside a cell MUST be written `\|` or kept inside a code span. Verifier evidence routinely quotes shell pipes; an unescaped `|` silently splits the row into extra columns and the count invariant then fails against a table nobody can read.

Empty severity sections are retained with their header and the table header row, so "no findings at this severity" is distinguishable from "this section was forgotten".

## Status vocabulary

| Status | Written by | Meaning |
|---|---|---|
| `Open` | Pass, and reconciliation until repaired | Unresolved. Blocks G03 at `Critical` and `High`. |
| `Corrected` | Reconciliation, after the repair is applied **and** the affected check re-run | The repair landed and its verification passed. A repair applied without re-running the check that found it stays `Open`. |
| `Accepted risk` | Reconciliation, with a named accepting owner and date | The defect stands, knowingly. Requires an owner identity, not a role. An agent may never self-accept a `Critical` or `High` — that is a Tier 3 confirmation per `tiers.overrideGateCondition`. |
| `Blocked` | Reconciliation | The repair requires evidence that cannot currently be obtained. Requires a populated `evidence_still_needed` and an owner. Counts as unresolved for G03. |

`Corrected` is the only status that removes a row from the gate's unresolved set. `Accepted risk` on a `Critical` or `High` does not — an accepted `Critical` still fails G03 and is reported as a deliberate override with the accepting owner named.

## What this schema does not cover

- **Scoring.** How a finding becomes a deduction, the 0–10 anchors, and the severity-to-cap rules live in `references/scorecard-rubric.md`.
- **The gate.** Which conditions a finding set fails, and the mechanical-versus-judgment split, live in `references/release-gate-conditions.md`.
- **Evidence rows.** `EV-####` shape, the seven source-authority levels, and the `V/C/R/I/U/N-A` claim states live in `references/evidence-ledger-schema.md` and `references/source-authority-and-claim-states.md`.
- **Registers.** `CL-`, `CT-`, `AS-`, and `OQ-` row shapes live in `references/register-schemas.md`.
- **How passes are run and kept independent.** `references/independent-audit-protocol.md`. That document is normative for what a pass may receive; this one is normative only for what it emits.
