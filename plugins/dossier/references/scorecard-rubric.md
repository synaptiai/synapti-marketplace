# Scorecard Rubric

Reference document. The ten weighted dimensions, the 0–10 anchors that fix what each score means, and the arithmetic that turns anchors into a total the release gate can compare against `gate.minScore`.

A score is not a gate. It is one of nineteen conditions, and it is the only one that compresses a package into a number — which is exactly why the anchors below are concrete and why every deduction must name a finding. An unanchored score drifts upward round over round; an anchored score with a citation trail does not.

## The ten dimensions

Weights sum to exactly 100. They are fixed by the source contract and are not project-configurable — a package whose weighting varies per engagement cannot be compared across engagements, which is most of the point of having a fixed package.

| # | Dimension | Weight | Test |
|---:|---|---:|---|
| 1 | Evidence grounding and freshness | 18 | Material claims are traceable, current, correctly classified, and scoped |
| 2 | Coverage and completeness | 12 | Canonical files and applicable sections are complete; `N/A` is justified |
| 3 | Technical correctness | 15 | Architecture, code, data, infrastructure, and interfaces match reality |
| 4 | Cross-document consistency | 10 | Terms, facts, diagrams, metrics, status, and boundaries agree |
| 5 | Due-diligence decision value | 10 | Strengths, liabilities, unknowns, risks, and evidence requests are candid and prioritized |
| 6 | Onboarding and operability | 10 | A teammate can understand, set up, change, test, deploy, and troubleshoot within their authorization |
| 7 | Security, privacy, and disclosure safety | 10 | Controls and gaps are accurate; secrets and unsafe disclosures are absent |
| 8 | Reliability and verification depth | 5 | Failure, recovery, observability, and executed checks are covered honestly |
| 9 | Public usefulness and claim integrity | 5 | Partner and customer content is usable, accurate, bounded, and approved |
| 10 | Clarity and maintainability | 5 | Information is navigable, concise, owned, versioned, and resistant to drift |
| | **Total** | **100** | |

Evidence grounding carries the largest weight because every other dimension inherits its failure: a correct architecture description sourced from nothing is indistinguishable from a plausible one.

## Arithmetic

Each dimension is scored on a 0–10 anchor scale, then converted to points:

```
points_d      = anchor_d x weight_d / 10          (one decimal)
total         = sum(points_d)                      (one decimal)
```

Because `points_d / weight_d = anchor_d / 10`, **the anchor score is the dimension's percentage of available points divided by ten**. With the shipped `gate.minDimensionPercent: 80`, the per-dimension floor is exactly `anchor >= 8.0` — the "8" anchor below is not a description of a good package, it is the gate line.

| # | Dimension | Weight | Floor at 80% | Anchor floor |
|---:|---|---:|---:|---:|
| 1 | Evidence grounding and freshness | 18 | 14.4 | 8.0 |
| 2 | Coverage and completeness | 12 | 9.6 | 8.0 |
| 3 | Technical correctness | 15 | 12.0 | 8.0 |
| 4 | Cross-document consistency | 10 | 8.0 | 8.0 |
| 5 | Due-diligence decision value | 10 | 8.0 | 8.0 |
| 6 | Onboarding and operability | 10 | 8.0 | 8.0 |
| 7 | Security, privacy, and disclosure safety | 10 | 8.0 | 8.0 |
| 8 | Reliability and verification depth | 5 | 4.0 | 8.0 |
| 9 | Public usefulness and claim integrity | 5 | 4.0 | 8.0 |
| 10 | Clarity and maintainability | 5 | 4.0 | 8.0 |
| | **Total at the floor** | **100** | **80.0** | |

**The two gate lines are independent and neither implies the other.** A package sitting exactly on every dimension floor scores 80.0 and fails `gate.minScore: 95`. A package scoring 96 can still fail on one dimension at 7.5. Reaching 95 requires a weighted mean anchor of 9.5 — the bar is demanding by design, because the package's purpose is to be relied on for consequential decisions.

## Deduction ledger

Every dimension's score is justified by a deduction table, and **every deduction cites at least one finding ID**. A deduction with no finding behind it is an impression, and an impression is what the anchors exist to replace.

```markdown
### D1 — Evidence grounding and freshness (weight 18)

| Deduction | Findings | Magnitude |
|---|---|---:|
| Two material claims carry `V` state on evidence that does not entail them | A1, A9 | −2.0 |
| Latency figure quoted as current from a nine-month-old undated source | A2 | −1.0 |
| `N/A` on the AI sections with no evidence locator | A3 | −0.5 |
| **Anchor** | | **6.5** |
| **Points** | | **11.7** |
```

Default magnitudes by severity. These are guide rails, not a formula:

| Severity | Default magnitude |
|---|---:|
| `Critical` | −4.0 |
| `High` | −2.0 |
| `Medium` | −1.0 |
| `Low` | −0.5 |

**Two independent constraints, take the lower.** The anchor describes the package the scorer is looking at; the arithmetic describes the findings against it. The score is `min(anchor_read, 10 − sum(deductions))`, floored at 0. Reading an anchor generously with no arithmetic check is how scores inflate; running arithmetic with no anchor read is how a package with forty trivial findings scores worse than one with two fatal ones. A departure from a default magnitude is allowed and is recorded with its reason in the deduction row.

### Severity caps

| Condition | Cap on that dimension |
|---|---:|
| One or more unresolved `Critical` findings assigned to the dimension | 4.0 |
| One or more unresolved `High` findings assigned to the dimension (and no unresolved `Critical`) | 7.0 |

The `High` cap is below the 8.0 floor, so a single unresolved `High` fails its dimension — and therefore the gate — regardless of the total. This is deliberate: it makes the scorecard and release-gate condition G03 agree rather than offering two routes to two different answers.

### Which statuses still deduct

| Status | Deducts at the post-repair score? |
|---|---|
| `Open` | Yes |
| `Blocked` | Yes — the defect is in the package, and the reason it cannot be fixed does not remove it |
| `Accepted risk` | Yes — acceptance is a decision about tolerance, not a change to the package. The accepting owner is named, and the deduction stands |
| `Corrected` | No, at the post-repair score. It deducted at the pre-repair score, and both scores are reported |

Reporting both the pre-repair and post-repair score is required. A package that went from 71 to 94 in one round and a package that started at 94 are different artifacts, and the difference is the audit's value.

## Anchors

Each anchor is cumulative: an 8 includes everything at 5, which includes everything at 3. Score the highest anchor the package fully satisfies, not the highest one it partly resembles.

### 1 — Evidence grounding and freshness (18)

*Material claims are traceable, current, correctly classified, and scoped.*

| Anchor | The package looks like |
|---:|---|
| 0 | No evidence ledger, or a ledger that material claims do not cite. Claim states absent or applied decoratively. Nothing traceable to a source. |
| 3 | A ledger covering some claims. Locators are file-level or missing; dates and versions largely absent; `V` used for anything the author believes. Sampling finds unsupported material claims above a 20% rate. |
| 5 | Every ledger row has a state and a locator, but locators are unstable (bare line numbers, no symbol or heading), a material fraction of rows carry no version or environment, and `V` appears where `R` or `I` is correct. Freshness concerns unrecorded. |
| **8** | Every material claim carries a state, a stable locator, an observed date, and a version or environment. The claim sample finds no unsupported claim at `High` or above; misclassification is confined to `R`-versus-`I` on non-material rows. Stale evidence is flagged with a named refresh action rather than silently carried forward. |
| 10 | All of 8, plus: every `V` is backed by an executed check or an authoritative artifact recorded with its command and date; every `C` names two independent current sources with at least one authoritative for the claim type; scope conditions — environment, version, percentile, tenant, region — travel with the claim into every consuming document; unavailable evidence is enumerated with its reason and the decision it blocks. |

### 2 — Coverage and completeness (12)

*Canonical files and applicable sections are complete; `N/A` is justified.*

| Anchor | The package looks like |
|---:|---|
| 0 | Canonical files missing. The package cannot be compared to any other package. |
| 3 | All 23 files exist, several as stubs — a header and a heading list with no content. `N/A` appears without a reason. |
| 5 | All files carry substantive content, but required sections are missing from several documents, and `N/A` carries a reason without an evidence locator. |
| **8** | All 23 files at their exact canonical paths; every section required by the applicable package contract present; every `N/A` carries a reason **and** an evidence locator; the independent inventory finds no omitted repository, service, module, interface, environment, pipeline, or dependency class. |
| 10 | All of 8, plus project-type adaptation is visible and justified — the emphasized sections match the recorded classification and its evidence — and any supplemental documents are linked from the index with a stated reason and do not duplicate a canonical source of truth. |

### 3 — Technical correctness (15)

*Architecture, code, data, infrastructure, and interfaces match reality.*

| Anchor | The package looks like |
|---:|---|
| 0 | The described system is not the system in the sources: components that do not exist, or a topology the deployment definitions contradict. |
| 3 | Broad shape right, specifics wrong. Diagrams omit major components; the interface inventory misses whole surfaces; the data model contradicts the schema. |
| 5 | Descriptions match at the component level. Traces reveal edges, queues, caches, or manual steps absent from the documentation, and at least one trust boundary or state-ownership assumption is drawn wrongly. |
| **8** | Every mandatory trace completes against the sources without contradicting the documentation. Every diagram node and edge is evidenced. The interface inventory matches the implemented surface. Remaining defects are `Medium` or below and are localized rather than structural. |
| 10 | All of 8, plus every executed trace completes cleanly; failure modes and degradation behaviour appear in the diagrams rather than only in prose; inferred connections are labelled as inferred; current architecture and target architecture are separated, with evidence for both. |

### 4 — Cross-document consistency (10)

*Terms, facts, diagrams, metrics, status, and boundaries agree.*

| Anchor | The package looks like |
|---:|---|
| 0 | Documents describe mutually exclusive systems. The same component carries different names, owners, and behaviour in different files. |
| 3 | A terminology register exists and is not used. Numbers and dates disagree across documents with no indication which is authoritative. |
| 5 | Terminology mostly consistent. Duplicated facts have drifted — a metric, version, status, or owner differs between two documents — and neither names a source of truth. |
| **8** | Names, roles, permissions, owners, statuses, versions, and metrics agree across every document. Diagrams agree with prose and with the inventories. Every duplicated fact names its source of truth. |
| 10 | All of 8, plus duplication is structurally minimized — documents cross-link rather than restate — so a future change has exactly one place to land; source-material aliases are recorded in the terminology register rather than leaking into documents. |

### 5 — Due-diligence decision value (10)

*Strengths, liabilities, unknowns, risks, and evidence requests are candid and prioritized.*

| Anchor | The package looks like |
|---:|---|
| 0 | The report advocates for the project or attacks it. No verdict, or a verdict with no stated confidence and no evidence. |
| 3 | A verdict exists. Strengths listed, liabilities generic, unknowns absent, risks unranked, no evidence requests. |
| 5 | Strengths and weaknesses both specific, but unranked by decision impact; remediation stated with false precision or omitted; verified facts, reported assertions, inferences, and unknowns not visibly separated. |
| **8** | A verdict with a stated confidence level and the evidence it rests on. Risks ranked by decision impact, each with likelihood, impact, evidence, and owner. Verified / reported / inferred / unknown visibly separated. Remediation given as ranges with stated assumptions. Evidence requests specific and obtainable. |
| 10 | All of 8, plus red flags and potential deal-breakers named rather than implied; materiality assessed against the stated decision context rather than in the abstract; 30/60/90 priorities traceable to specific risk rows rather than a generic improvement list. |

### 6 — Onboarding and operability (10)

*A teammate can understand, set up, change, test, deploy, and troubleshoot within their authorization.*

| Anchor | The package looks like |
|---:|---|
| 0 | No setup path, or one that cannot work — missing prerequisites, wrong commands, no access process. |
| 3 | A setup section of untested prose. No verification stamps. No reading order. No first task. |
| 5 | Setup commands correct but incomplete — a prerequisite or access step is missing, so a clean environment stalls. Commands stamped, but several read `not executed` with no reason. Personas 2 and 4 stall mid-task. |
| **8** | A reader in a clean environment reaches a first meaningful contribution using only the package. Every command stamped `verified`, `partially verified`, or `not executed`, with environment and date. Runbooks exist for the credible failure modes, and anything destructive carries preconditions, impact, authorization, rollback, and verification. |
| 10 | All of 8, plus audience-specific routes for engineering, product, design, data/AI, operations, security, and leadership; a verified starter task or guided code trace; first-day, first-week, and first-month outcomes; troubleshooting for the failures a newcomer actually hits; ownership gaps stated rather than papered over; and no instruction anywhere to use production credentials or data for local development. |

### 7 — Security, privacy, and disclosure safety (10)

*Controls and gaps are accurate; secrets and unsafe disclosures are absent.*

| Anchor | The package looks like |
|---:|---|
| 0 | A secret, credential, personal datum, or customer-confidential item is present in the package, or exploitable detail appears in a public document. |
| 3 | No secrets, but implemented, policy-only, planned, and unknown controls are not distinguished. "Secure", "encrypted", "compliant", or "private" used with no scope and no evidence. |
| 5 | The four control classes are distinguished for most controls. Gaps lack severity, likelihood, impact, or remediation. At least one public document carries a security claim broader than the internal evidence supports. |
| **8** | Every stated control classified implemented / policy-only / planned / unknown, with evidence and a last-test date for implemented ones. Every gap carries severity, likelihood, impact, and remediation. No secret or prohibited disclosure anywhere in the package. Every security or privacy adjective carries a defined scope. |
| 10 | All of 8, plus a threat model with assets, actors, and trust boundaries; a data inventory with classification, legal basis, retention, deletion, and residency where applicable; subprocessor and third-party risk recorded; safe public claims and prohibited disclosures listed explicitly; and no absence of a known incident presented as evidence of safety. |

### 8 — Reliability and verification depth (5)

*Failure, recovery, observability, and executed checks are covered honestly.*

| Anchor | The package looks like |
|---:|---|
| 0 | Availability, recovery, or redundancy claimed with no evidence, or a check presented as passed that was not run. |
| 3 | Objectives stated; SLIs, SLOs, SLAs, and error budgets conflated; no measured performance; no recovery evidence. |
| 5 | Objectives and measurements distinguished in the assurance document, but no test evidence for backup, restore, failover, or degradation, and the target-versus-measurement distinction slips in at least one consuming document. |
| **8** | Targets and measurements never conflated anywhere in the package. Timeout, retry, backpressure, circuit-breaker, queue, cache, and degradation behaviour documented where present. Every recovery claim carries a last-exercise date or an explicit "untested" label. Every check states executed or `not executed` with its reason. |
| 10 | All of 8, plus dependency-failure, regional-failure, and data-corruption scenarios documented with their observability coverage; alert-to-owner-to-escalation paths complete with thresholds; known blind spots stated as blind spots rather than omitted. |

### 9 — Public usefulness and claim integrity (5)

*Partner and customer content is usable, accurate, bounded, and approved.*

| Anchor | The package looks like |
|---:|---|
| 0 | Public documents contain unregistered claims, or claims backed by `R`, `I`, or `U` evidence, or approvals the run recorded on its own authority. |
| 3 | Every public sentence maps to a register row, but many rows are `pending` and the documents read as released regardless. Limitations absent. |
| 5 | Claims registered and mostly approved, but conditions and limitations were lost in simplification, so at least one sentence is true internally and false as written. |
| **8** | Every public sentence maps to an approved `CL-` row backed by `V` or `C` evidence. Limitations and conditions survive simplification. No internal locators, topology, ownership detail, or unannounced plans in the rendered public text. Personas 6 and 7 complete their tasks from the public documents alone. |
| 10 | All of 8, plus public examples verified against the supported surface using synthetic data; error, retry, idempotency, rate-limit, timeout, and pagination behaviour documented where applicable; deprecation and change communication stated; and no superlative, absolute safety claim, or ambiguous term such as "anonymous" or "real time" left undefined. |

### 10 — Clarity and maintainability (5)

*Information is navigable, concise, owned, versioned, and resistant to drift.*

| Anchor | The package looks like |
|---:|---|
| 0 | No index, no headers, no owners, no dates. The package cannot be maintained because nothing records what it describes. |
| 3 | An index that is a file list. Headers incomplete. Ownership largely `unassigned` without that being stated as a gap. |
| 5 | Headers complete and the index navigable, but prose is padded with generic explanation, and review triggers and cadence are absent — so the package will age without anyone noticing. |
| **8** | Every document carries the full header contract from `references/document-headers.md`. The index gives a reader route per audience. Maintenance policy, review cadence, and review triggers stated. Prose is concrete and free of filler. |
| 10 | All of 8, plus a change summary since the previous documentation version; document dependencies and sources of truth mapped so a change's blast radius is readable from the index; ownership gaps and bus-factor concerns stated explicitly rather than left as bare `unassigned` rows. |

"Prose is concrete and free of filler" at anchor 8 is a judgment call `bin/dossier-prose-lint.sh` cannot make alone — its hard categories are gated separately by `G18`, never here. Its advisory categories (passive voice, nominalization) are useful evidence for this dimension: a document whose G18 fix reads as genuine has few of them; one that shortened sentences into vague fragments to dodge the word cap tends to keep or worsen them.

## Worked example

A package after one repair round. Findings are drawn from the reconciled ledger; every deduction cites at least one.

| # | Dimension | Weight | Anchor | Points | Governing deductions |
|---:|---|---:|---:|---:|---|
| 1 | Evidence grounding and freshness | 18 | 9.0 | 16.2 | A2 (−1.0) latency figure undated |
| 2 | Coverage and completeness | 12 | 10.0 | 12.0 | none |
| 3 | Technical correctness | 15 | 9.0 | 13.5 | B4 (−1.0) cache absent from the data-flow diagram |
| 4 | Cross-document consistency | 10 | 8.0 | 8.0 | C2 (−1.0), C7 (−1.0) owner and version drift across two documents |
| 5 | Due-diligence decision value | 10 | 9.0 | 9.0 | A11 (−1.0) remediation ranges without stated assumptions |
| 6 | Onboarding and operability | 10 | 7.0 | 7.0 | C4 (−2.0) persona 2 stalls on a missing access prerequisite; C9 (−1.0) three commands `not executed` with no reason |
| 7 | Security, privacy, and disclosure safety | 10 | 10.0 | 10.0 | none |
| 8 | Reliability and verification depth | 5 | 8.0 | 4.0 | B8 (−2.0) restore procedure with no exercise date and no "untested" label |
| 9 | Public usefulness and claim integrity | 5 | 9.0 | 4.5 | C11 (−1.0) rate-limit behaviour undocumented in the partner guide |
| 10 | Clarity and maintainability | 5 | 9.0 | 4.5 | C13 (−1.0) index last-verified date precedes four indexed documents |
| | **Total** | **100** | | **88.7** | |

Gate result on the scorecard conditions:

| Condition | Result |
|---|---|
| G01 — total ≥ `gate.minScore` (95) | **FAIL** — 88.7 |
| G02 — every dimension ≥ `gate.minDimensionPercent` (80%, anchor 8.0) | **FAIL** — dimension 6 at 7.0 |

Repairing C4 and C9 lifts dimension 6 to 9.0 and the total to **90.7**. G02 now passes; G01 still fails. One more round closing C2, C7, B8, and A2 lifts dimensions 4, 8, and 1 to 10.0, 10.0, and 10.0 — total **95.5**, and both scorecard conditions pass.

The arithmetic is the point of the example: no single repair reaches the bar. 95/100 requires a weighted mean anchor of 9.5, which is only reachable by closing findings across several dimensions. A package that arrives at 88.7 and asks for one more fix has misread what the gate requires.

## Rules

| Rule | Rationale |
|---|---|
| Every deduction cites at least one finding ID | An uncited deduction cannot be verified, argued with, or closed |
| Do not inflate scores to match the author's self-score | Anchoring. Each pass scores before seeing any other score, per `references/independent-audit-protocol.md` |
| Each pass scores all ten dimensions, not only the ones its lens covers | Per-pass scores are only comparable when they cover the same set |
| `dossier-scorer` issues the single authoritative score | Per-pass scores are inputs. The scorer sees the final package and the adjudicated findings, never the drafting or repair rationale |
| Divergence above 2.0 on any dimension between passes is recorded as a confidence note | Large divergence is information about the rubric as much as about the package |
| The score never overrides a failed gate condition | A package can score 96 and be unreleasable on one unsupported public claim. See `references/release-gate-conditions.md` |
