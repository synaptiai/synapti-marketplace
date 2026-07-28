# Evidence Ledger Schema

Reference document. The table shape, identifier grammar, citation syntax, and append rules for `00-control/evidence-ledger.md` — the register every material claim in the package traces back to. Claim states and the authority ordering are defined in `references/source-authority-and-claim-states.md`; this document defines the row.

A **material claim** is one that could change an investment, acquisition, partnership, procurement, or security decision; change how a teammate modifies, deploys, operates, or troubleshoots the system; change what a partner builds against; or change what a customer believes the product does, guarantees, stores, protects, or supports. Everything else is prose and needs no row.

## Columns

Thirteen columns. Twelve are the fields the method requires; `Retrievable` is added so the resolvability lint is mechanical rather than a judgement call about whether a locator "looks like" a path.

| # | Column | Type | Required content |
|---:|---|---|---|
| 1 | `Evidence ID` | `EV-####` | Stable identifier. Never reused, never renumbered. |
| 2 | `Claim` | string | One atomic, testable statement. See "Atomicity" below. |
| 3 | `State` | enum | `V` \| `C` \| `R` \| `I` \| `U` \| `N/A` |
| 4 | `Source ref` | string | Free text locating the source. File and stable symbol, command and its output artifact, dashboard name and panel, contract name and clause, interview participant role and date, record identifier. Not constrained to a file path. |
| 5 | `Retrievable` | `yes` \| `no` | Whether a reader with the stated access can reach `Source ref` and see the same thing. |
| 6 | `Authority` | 1–7 | Authority level of the source. See the ordering reference. |
| 7 | `Version/env` | string | Commit, tag, release, environment name, or `unknown`. |
| 8 | `Observed` | ISO date | `YYYY-MM-DD`. When the evidence was actually seen or the check actually ran. |
| 9 | `Freshness` | string | `none`, or a concrete explanation of why this may no longer hold. |
| 10 | `Confidentiality` | enum | `Public` \| `Partner-Confidential` \| `Internal` \| `Restricted` |
| 11 | `Public use` | enum | `yes` \| `no` \| `pending` |
| 12 | `Consuming docs` | list | Package-relative paths of the documents that rely on this row. |
| 13 | `Notes` | string | Contradictions, qualifications, scope limits, superseding rows. `—` when there is nothing to say. |

Thirteen columns is a wide table. It is a register read by tooling and by a reviewer doing a column-wise sweep ("show me every `Public use: yes` row whose `State` is not `V` or `C`"), not a table skimmed in a narrow column, so width is the right trade. Keep one row per line; do not wrap cells.

### Column rules

**`Claim` — atomicity.** One row asserts one thing. "The API requires OAuth and rate-limits at 100 req/min" is two claims, because the auth evidence and the rate-limit evidence are different sources with different freshness. Splitting them means one can be demoted without dragging the other down. A claim containing "and", "which also", or a comma-separated list of properties is almost always two rows.

A claim must be falsifiable by inspection. "The architecture is clean" cannot be checked. "`src/api/` has no imports from `src/internal/billing/`" can.

**`Source ref` — non-file sources.** Most projects' most important evidence is not a file. The column accepts any locator; what matters is that a second person with the same access could reach it. Conventions:

| Source class | `Source ref` form | `Retrievable` |
|---|---|---|
| Code | `path/to/file.ts::symbolName` or `path/to/file.ts#heading`. Prefer a stable symbol or heading to a line number — line numbers drift within a single commit's worth of edits and turn a valid row into a dangling one. | `yes` |
| Executed check | `cmd: <command>` plus the artifact path holding its output, e.g. `cmd: npm test → .dossier/runs/<id>/npm-test.log` | `yes` |
| Schema / IaC / config | Same as code. Include the environment when the file is per-environment. | `yes` |
| Immutable record | `git:<sha>`, `release:<tag>`, `pr:<number>`, `incident:<id>` | `yes` |
| Derived from other rows | `derived:<EV-#### expression>`, e.g. `derived: EV-0004..EV-0007, EV-0041`. Use when the row states something that follows from rows already in the ledger rather than from a source outside it — the cited rows carry the grounding, and each must exist | `yes` |
| Dashboard / telemetry | `dashboard:<system>/<dashboard name>/<panel>` plus the query window, e.g. `dashboard:grafana/api-slo/p99-latency (7d window, observed 2026-07-20)` | `yes` if the reader has the console; `no` if the panel is retention-limited and the window has since aged out |
| Contract / policy | `contract:<counterparty> <document title> §<clause>` — never the document text, never the counterparty's confidential terms | usually `no` |
| Interview / stakeholder | `interview:<role>, <YYYY-MM-DD>` — role, not name, unless the person's name is already public in the terminology register | `no` |
| Vendor lifecycle / CVE / license | `<source name> <identifier>, retrieved <YYYY-MM-DD>` | `yes` |
| Inference | `inference from EV-0012, EV-0031` | `yes` (the cited rows are retrievable) |

**`Retrievable` and the lint rule.** `bin/dossier-ledger-lint.sh` checks that a `Source ref` resolves — that the file exists, the symbol is present, the artifact is on disk — **only for rows at authority levels 1–3**. Those levels are runtime checks, versioned artifacts, and telemetry: things that exist inside the inspection boundary and can be mechanically confirmed. Levels 4–7 (approved documents, tickets and prose, stakeholder recollection, inference) routinely point at systems the linter cannot reach, and failing them would train everyone to ignore the linter.

`Retrievable: no` at authority 1–3 is therefore a contradiction and is itself a finding: either the source is not what the authority level claims, or the authority level is inflated. `Retrievable: no` at levels 4–7 is normal and carries one obligation — the `Notes` cell must say what a reader would need in order to check it ("requires access to the contracts drive", "participant left the company; re-confirm with current owner").

**`Observed`.** The date the evidence was seen, not the date the row was written and not the date of the thing observed. A commit dated 2024-03-01 read on 2026-07-25 has `Observed: 2026-07-25` and `Version/env: <sha>`.

**`Freshness`.** `none` means "nothing about this evidence has a known expiry". Anything else must name the expiry mechanism: "telemetry window is 30d; re-observe after 2026-08-19", "vendor EOL dates change; re-check quarterly", "staging config; production may differ". "Might be stale" is not a freshness concern, it is an absence of one.

**`Confidentiality`.** Set from the source, not from the claim. A benign-sounding claim derived from a restricted source is restricted, because confirming it discloses the source's existence. A document's header confidentiality is the maximum over the rows it cites.

**`Public use`.** `yes` only when a human with disclosure authority approved it, recorded in `00-control/claim-and-disclosure-register.md`. The drafter cannot set `yes` on its own behalf. When `disclosure.publicClaimApproval` is `required` and no approval is recorded, the value is `pending` — never `yes`, never blank. `pending` blocks the public documents and that is the intended behaviour.

**`Consuming docs`.** Maintained as documents are drafted, so the blast radius of a demoted row is answerable by grep. An empty cell on a `V` row is not an error; it means nothing consumes the claim yet, and it is the first thing to check when pruning.

## Identifier grammar

```
EV-<4 digits>          EV-0001 … EV-9999
```

- Zero-padded to four digits. `EV-1` and `EV-01` are invalid.
- Assigned in strictly increasing order of creation.
- Never reused. A withdrawn row keeps its ID and gains `State: U` with a `Notes` explanation; it is not deleted and the number does not return to the pool.
- Beyond `EV-9999`, widen to five digits (`EV-10000`) rather than restarting. Existing four-digit IDs are not repadded.
- The regex `EV-[0-9]{4,}` is what `bin/dossier-claim-scan.sh` and `dossier-ledger-lint.sh` match on. Nothing else in the package may use the `EV-` prefix.

## Append-only rules

The ledger is append-only in identity and mutable in state. Concretely:

| Operation | Allowed | How |
|---|---|---|
| Add a claim | yes | New row, next ID, appended at the end. |
| Delete a row | **no** | Set `State: U`, explain in `Notes`. A deleted row destroys the trail from every document that cited it. |
| Renumber rows | **no** | Citations across 22 other documents point at the old numbers. |
| Reorder rows | discouraged | Sorting by ID is fine because IDs are creation-ordered. Sorting by anything else makes diffs unreadable. |
| Change `State` | yes | Promotion and demotion rules are in the authority reference. Record the reason in `Notes` with the date. |
| Change `Claim` wording | only to narrow | Tightening scope ("in production" added) is a correction. Broadening scope is a new claim and needs a new row, because the old evidence no longer entails it. |
| Re-observe | yes | Update `Observed`, `Version/env`, and `Freshness` in place. This is the normal refresh operation. |
| Supersede | yes | New row with the new evidence; old row gets `Notes: superseded by EV-####` and keeps its state until the consuming documents have moved. |

The reason for append-only is not bookkeeping neatness. A verification pass compares the package against the ledger; if the ledger can be rewritten to match the package, the comparison proves nothing.

## Inline citation syntax

```
[EV-0042]
[EV-0042, EV-0043]
[EV-0042–EV-0045]
```

Rules:

1. **Placement.** Immediately after the sentence or table cell carrying the claim, inside the sentence's terminal punctuation is not required — `… uses OAuth 2.0 device flow [EV-0042].` A citation at the end of a paragraph covers only its own sentence.
2. **Tables.** Cite in the cell that carries the claim, not in a trailing "evidence" column. A table with a citation column invites one citation per row for rows whose cells came from different sources.
3. **Multiple.** Comma-separate. Use the en-dash range form only for genuinely contiguous runs.
4. **Never in public documents.** `06-public/**` contains no `EV-` strings. The mapping lives in the claim register.
5. **State-qualified prose.** A citation is not a substitute for labelling. A claim backed by an `R` row must say so in the prose — "the team reports that …  [EV-0087]" — because the reader will not open the ledger. See the observed/interpreted/unknown/recommended contract in the authority reference.
6. **Uncited material claims are findings.** A material sentence with no citation is a Medium finding at minimum, and High when it appears in the due-diligence report or feeds a public claim.

## Worked example rows

```markdown
| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EV-0001 | The HTTP API authenticates with OAuth 2.0 client credentials and rejects unauthenticated requests with 401. | V | `cmd: curl -s -o /dev/null -w '%{http_code}' https://api.example.internal/v1/accounts → .dossier/runs/2026-07-24T09-12Z/auth-probe.log` | yes | 1 | staging, 9f3c1ab | 2026-07-24 | none | Internal | pending | 02-architecture/interfaces-and-integrations.md, 06-public/technical-partner-guide.md | Probe run against staging only; production not exercised. |
| EV-0002 | `src/api/router.ts` registers exactly 14 public routes under `/v1`. | V | `src/api/router.ts::registerV1Routes` | yes | 2 | 9f3c1ab | 2026-07-24 | none | Internal | no | 02-architecture/interfaces-and-integrations.md, 02-architecture/components-and-codebase.md | Count excludes 3 routes behind the `internal_admin` flag. |
| EV-0003 | p99 latency on `GET /v1/accounts` was 210 ms over the 7 days ending 2026-07-20. | V | `dashboard:grafana/api-slo/p99-latency (7d window)` | yes | 3 | production | 2026-07-20 | Panel retention is 30d; the observed window ages out 2026-08-19. | Internal | pending | 03-assurance/reliability-performance-and-observability.md | Measured result, not an objective. The 250 ms figure elsewhere is the SLO — see EV-0004. |
| EV-0004 | The stated internal latency objective for `GET /v1/accounts` is p99 under 250 ms. | C | `docs/slo/api.md#accounts` and `interview:platform lead, 2026-07-18` | yes | 4 | main@2026-07-01 | 2026-07-18 | Objective document has no review date; confirm ownership. | Internal | no | 03-assurance/reliability-performance-and-observability.md | Objective, not a customer commitment. Must not appear in 06-public without a contractual basis. |
| EV-0005 | Nightly database backups run and the most recent restore rehearsal was 2025-11-04. | R | `interview:sre on-call, 2026-07-19` | no | 6 | unknown | 2026-07-19 | Restore rehearsal is 8 months old; recovery claims should not rely on it. | Internal | no | 02-architecture/infrastructure-and-deployment.md, 04-operating/operations-and-incident-response.md | No artifact located for the rehearsal. Open question AQ-0007 requests the runbook output. Reader needs access to the SRE drive to check. |
| EV-0006 | The project has no AI or machine-learning component. | V | `cmd: rg -l "openai\|anthropic\|torch\|sklearn\|transformers" --glob '!package-lock.json' → no matches; package.json dependencies reviewed` | yes | 2 | 9f3c1ab | 2026-07-24 | Re-check on any dependency change. | Internal | yes | 02-architecture/data-and-ai.md | Supports the N/A status of the AI sections. Absence of a dependency is evidence about the codebase, not proof no AI is used operationally — EV-0007 covers vendor tooling. |
| EV-0007 | Whether any third-party service in the request path performs model inference is unknown. | U | `inference from EV-0006; no subprocessor list located` | yes | 7 | 9f3c1ab | 2026-07-24 | none | Internal | no | 02-architecture/data-and-ai.md, 03-assurance/security-privacy-and-compliance.md | Recorded so the N/A on the AI sections is bounded rather than absolute. See AQ-0011. |
```

`EV-0006` and `EV-0007` together are the pattern for an honest `N/A`: a positive verified statement about what was checked, plus an explicit row for what the check does not cover. A single row saying "no AI" would be converting the absence of a grep hit into evidence of absence.

## Vulnerability-finding rows

`bin/dossier-vuln-evidence.sh` normalizes a project's existing vulnerability-scan output (SARIF, osv-scanner JSON, a Dependabot alerts export — dossier never executes a scanner itself) into rows following this grammar, so `bin/dossier-gate.sh`'s G19 condition can find them mechanically without a strict column-position parser — the same loose-grep convention G03 already uses.

- **State**: always `R` (Reported). Dossier reads the scan tool's output; it does not independently execute or re-verify the finding.
- **Authority**: `2` when the scan-artifact file itself is present and versioned in the project at the pinned revision (a "Code" class source, per the table above); `5` when it is an externally-exported alert list not versioned alongside the code (e.g., a downloaded Dependabot export).
- **`Source ref`**: the scan-artifact path wrapped in a code span, so `bin/dossier-ledger-lint.sh`'s locator-resolution check (authority 1–3) resolves it as a real file, followed by the tool name, finding identifier, and retrieval date — `` `<scan-artifact-path>` — <tool>, <identifier>, retrieved <YYYY-MM-DD> ``. This is `dossier-vuln-evidence.sh`'s own `findings[].source_ref` field, copied verbatim.
- **`Notes`** tag grammar — one row for what was scanned (the coverage row), one row per material (Critical/High) finding, one row for the aggregated Medium/Low count. Never collapse a Critical/High finding into the aggregate.

  | Row kind | Notes tag |
  |---|---|
  | Coverage (what was scanned) | `vuln-scan-coverage status=parsed`, `vuln-scan-coverage status=parse-error` (the whole scan failed to parse), or `vuln-scan-coverage status=partial` (the scan parsed, but one or more individual records inside it did not) |
  | Material finding (Critical or High) | `vuln-finding severity=<Critical\|High>` |
  | Aggregated Medium/Low count | `vuln-finding-aggregate severity=<Medium\|Low> count=<n>` |
  | Severity could not be determined, or the individual record could not be parsed | `vuln-finding-unresolved` |

- **Disposition**: a `vuln-finding` row's Critical/High status is resolved by a corresponding row in `04-operating/decisions-technical-debt-and-risks.md`'s existing Risk register or Accepted risks table, citing the `EV-####` row via that table's own `Evidence` column. The ledger row itself never carries owner/target-date/acceptance — that state lives in the risk register, not duplicated here.

A parse failure (malformed scan artifact, or an unrecognized shape) is recorded as a `vuln-scan-coverage status=parse-error` row with `State: U`, never silently omitted and never read as "zero findings, therefore clean." A finding whose severity could not be derived, or an individual record within an otherwise-valid scan that could not be normalized, is never fabricated as `Low` or otherwise silently dropped — it becomes its own `vuln-finding-unresolved` row with `State: U`, an honest disclosure that something was found whose materiality is unknown, per this ledger's own rule that absence of evidence is never recorded as evidence of absence. `bin/dossier-gate.sh`'s G19 does not itemize `vuln-finding-unresolved` rows into its FAIL/PASS decision — it acts only on confirmed `Critical`/`High` severities — but the row's presence is itself the honesty the format requires.

## Ledger sections

`00-control/evidence-ledger.md` carries more than the table. Its required sections are specified in `references/package-contract-00-control.md#evidence-ledger`; the parts that constrain rows are:

- **Executed checks.** Every `cmd:` in a `Source ref` must appear in the executed-checks table with its date, scope, environment, and result. A `cmd:` locator with no corresponding executed-check entry means the row asserts a check ran when there is no record that it did.
- **Unavailable evidence.** Sources that were sought and could not be reached, with what they would have settled. This is what keeps `U` rows from looking like laziness.
- **Stale evidence.** Rows whose `Freshness` names an expiry that has passed, with the refresh action. A row is not silently demoted by the calendar; it is listed here and demoted deliberately.

## What never enters the ledger

Secret values, credentials, tokens, private keys, personal data, customer-identifying data, and exploitable detail. When such material is the evidence, the row records the **type and location category** and nothing else — `Source ref: hardcoded credential in a deployment manifest under infra/`, `Confidentiality: Restricted`, and a `Notes` cell naming the remediation need. The value never appears, not in the ledger, not in a run artifact, not in a completion report.
