# Release Gate Conditions

Reference document. The nineteen conditions that decide whether a documentation package may be released, how each is checked, and the contract that stops the gate from becoming theater.

The gate is **binary and conjunctive**: nineteen of nineteen, or the package is not `release-ready`. A high score is one condition, not a substitute for the other eighteen. A package can score 96/100 and be unreleasable on a single unsupported public claim, and that is the correct outcome — the score measures quality, and the other conditions measure whether the package is safe to rely on.

## The mechanical / judgment split

Every condition carries exactly one tag, and the tag determines who is allowed to decide it.

| Tag | Definition |
|---|---|
| **`mechanical`** | `bin/dossier-gate.sh` can decide it true or false from repository state alone — files, headings, register rows, greps, link resolution, exit codes. No verdict file, no model judgment. |
| **`judgment`** | Cannot be decided from repository state. Requires the `dossier-scorer` verdict file, which is a model-produced artifact. The script's job is to **require and parse** that verdict, never to substitute for it. |

Twelve conditions are mechanical; seven are judgment.

Some mechanical conditions have a judgment shadow — a script can prove every registered claim has approved evidence, but not that every public *sentence* was registered in the first place. Where that applies, the condition below names its **mechanical precondition** and says which judgment condition covers the rest. The split is drawn so that the shadow always lands on a judgment-tagged condition rather than falling through the gate.

## The script contract

This section is normative for `bin/dossier-gate.sh`.

**Failing is decidable from a subset. Passing is not.**

That asymmetry is the whole design. Twelve mechanical conditions are enough to prove a package is *not* releasable — one broken link is sufficient. They are never enough to prove it *is*, because the seven judgment conditions include both scorecard conditions and three of the four "must never appear" rules. A script that passed on mechanics alone would emit `PASS` for a package whose planned features are documented as shipped, whose targets are printed as measurements, and whose policies are described as controls, having checked none of it. That package would look audited and would be wrong in exactly the ways the system exists to catch.

So the script **structurally refuses to emit `PASS` without a scorer verdict file**:

| Requirement on the verdict file | Why |
|---|---|
| Exists at `.dossier/runs/<run-id>/scorer-verdict.md` | A verdict that was produced but not written is not a verdict |
| Names the same `project.versionOrCommit` the package is pinned to | A verdict against a different revision is neither true nor false |
| Names the same audit round as the run being gated | A round-1 verdict does not cover a round-3 package |
| Carries an explicit `PASS` or `FAIL` line for **every** judgment-tagged condition, by ID (`G01`, `G02`, `G04`, `G07`, `G13`, `G14`, `G15`) | A verdict silent on a condition has not evaluated it, and silence must not read as assent |
| Carries the per-dimension score table with anchors, points, and cited finding IDs | G01 and G02 are computed from it, and an uncited score is an impression |

When the file is absent, stale, mismatched, or silent on any judgment condition, the result is **`INCONCLUSIVE`** — never `PASS`. `INCONCLUSIVE` maps to package status `not ready`, never to `conditionally ready`: "we did not check" is an absence of assurance, not a condition to attach.

Exit codes:

| Code | Meaning |
|---:|---|
| 0 | `PASS` — all nineteen conditions satisfied, judgment set covered by a valid verdict file |
| 1 | `FAIL` — at least one condition failed. Emitted from mechanics alone when a mechanical condition fails, with or without a verdict file |
| 2 | Usage error — missing or invalid arguments |
| 3 | `INCONCLUSIVE` — no mechanical condition failed, but the judgment set is not covered |

`--strict` maps exit 3 to exit 1, so CI treats an uncovered judgment set as a failure rather than as a state to interpret. `--json` emits one object per condition with `id`, `tag`, `result`, `evidence`, and `source` (`script` or `verdict`), so a reader can always tell which conditions were machine-decided and which were asserted by the scorer.

## The nineteen conditions

| ID | Condition | Tag |
|---|---|---|
| G01 | Total score is at least `gate.minScore` | judgment |
| G02 | Each scorecard dimension reaches at least `gate.minDimensionPercent` of its available points | judgment |
| G03 | No unresolved critical or high-severity documentation finding exists | mechanical |
| G04 | No unsupported or unapproved public claim exists | judgment |
| G05 | Every human approval required by policy has been recorded | mechanical |
| G06 | No secret, credential, personal data, private customer information, or prohibited disclosure is present | mechanical |
| G07 | No known contradiction can materially mislead a decision | judgment |
| G08 | Canonical document and section coverage is 100%, including justified `N/A` entries | mechanical |
| G09 | All material internal claims have an evidence state and locator | mechanical |
| G10 | All public claims map to verified or corroborated, disclosure-approved evidence | mechanical |
| G11 | Internal links, document paths, and diagram syntax validate | mechanical |
| G12 | Commands and examples are executed successfully or visibly marked as not executed | mechanical |
| G13 | Planned behaviour is not presented as implemented | judgment |
| G14 | Targets are not presented as measured results | judgment |
| G15 | Policies are not presented as implemented controls | judgment |
| G16 | Unresolved uncertainty and source limitations are visible | mechanical |
| G17 | The reviewer-pass independence method is disclosed, including model diversity | mechanical |
| G18 | No hard-category prose-clarity violation exists in the package | mechanical |
| G19 | No unresolved Critical or High dependency vulnerability lacks a recorded disposition | mechanical |

### G01 — Total score is at least `gate.minScore`

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | Read the total from the scorer verdict file and compare against `gate.minScore` (default 95). The arithmetic is trivial; the number is not, and the script may not produce it. |
| Evidence that satisfies it | A verdict file whose per-dimension table sums to the stated total, where every deduction cites at least one finding ID, per `references/scorecard-rubric.md`. |
| Fails when | The total is below the threshold; the verdict file has no total; the per-dimension points do not sum to the stated total; or any deduction is uncited. |

### G02 — Each dimension reaches at least `gate.minDimensionPercent` of its available points

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | For every dimension, `points_d / weight_d >= gate.minDimensionPercent / 100`. With the default 80, this is `anchor_d >= 8.0`. All ten dimensions are checked; a missing dimension row fails the condition rather than being skipped. |
| Evidence that satisfies it | Ten dimension rows in the verdict file, each with an anchor, points, and the findings governing its deductions. |
| Fails when | Any dimension is below its floor, or the verdict file scores fewer than ten dimensions. A single unresolved `High` finding caps its dimension at 7.0 and fails this condition through the rubric's severity caps. |

### G03 — No unresolved critical or high-severity documentation finding exists

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Parse the reconciled ledger at `.dossier/runs/<run-id>/findings.md` per `references/finding-schema.md`. Fail if any row has `severity` in `gate.failOn` (default `["Critical", "High"]`) and `status` in `{Open, Blocked}`. Also fail if any `Accepted risk` row at those severities lacks a named accepting owner and date — acceptance without an accepter is not acceptance. |
| Evidence that satisfies it | A reconciled ledger in which every `Critical` and `High` row is `Corrected` with its verifying check re-run, or `Accepted risk` with a named individual owner and a date. |
| Fails when | Any `Critical` or `High` row is `Open` or `Blocked`; an `Accepted risk` row names a role instead of a person; or the ledger is absent, which is not a pass. An accepted `Critical` still fails and is reported as a deliberate override under `tiers.overrideGateCondition`. |

### G04 — No unsupported or unapproved public claim exists

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | Every assertion in `06-public/**` maps to a `CL-####` row with status `approved`. Deciding which sentences *are* assertions is the judgment part — a script cannot distinguish a claim from a transition. The scorer performs the sentence-by-sentence walk and records unmapped assertions by location. |
| Mechanical precondition | The script verifies the register side: every `CL-` row destined for a public document has status `approved` and at least one `EV-` reference. Necessary, not sufficient — it says nothing about sentences nobody registered. |
| Evidence that satisfies it | A claim-by-claim comparison recorded in the verdict file, naming the count of public assertions walked and listing zero unmapped ones, plus a clean register-side precondition. |
| Fails when | Any public assertion has no `CL-` row; any mapped row is `pending`, `rejected`, or `withdrawn`; or the scorer did not perform the walk, which is `INCONCLUSIVE` rather than pass. |

### G05 — Every human approval required by policy has been recorded

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Enumerate the approvals required by `disclosure.publicClaimApproval`, `engagement.regulatory`, and any contractual or safety policy recorded in the registers. Each must carry an approver identity, a date, and the scope approved. The run may apply a policy; it may never appoint itself the business, legal, security, privacy, or communications approver. |
| Evidence that satisfies it | Approval rows in `00-control/claim-and-disclosure-register.md` with a named individual, an ISO date, and the exact scope. Where approval is required and absent, the row reads `pending`, which fails this condition honestly rather than passing it quietly. |
| Fails when | A required approval is absent, undated, unscoped, attributed to a role rather than a person, or recorded by the run itself. The script checks presence and shape; it cannot verify the approver had authority, and that limitation is stated in the verification report rather than assumed away. |

### G06 — No secret, credential, personal data, private customer information, or prohibited disclosure is present

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Scan the whole package for credential patterns (`sk-ant-`, `ghp_`, `gho_`, `github_pat_`, `AKIA`, `xox[baprs]-`, `-----BEGIN * PRIVATE KEY`, and the baseline patterns shared with the flow secret hook) plus every regex in `disclosure.redactionPatterns`. Any hit is a hard fail. The failure names the file and the pattern class; it never reproduces the matched value. |
| Evidence that satisfies it | A clean scan across all 23 files at the pinned revision, with the pattern set and scan date recorded, plus pass C's disclosure lens finding no prohibited detail in `06-public/**`. |
| Fails when | Any pattern matches, or the scan did not run. **Stated limitation:** regex scanning misses novel credential formats and most unstructured personal data. The judgment backstop is pass C, whose disclosure findings enter the gate through G03 as `Critical` or `High` rows — so a missed secret fails the gate on a different condition rather than passing unnoticed. |

### G07 — No known contradiction can materially mislead a decision

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | For every `CT-####` row in the contradiction register, decide whether an unresolved contradiction could materially mislead a diligence, onboarding, integration, operational, security, or customer decision. "Materially" is assessed against `engagement.dueDiligenceContext`, which is why this cannot be scripted. |
| Mechanical precondition | Every `CT-` row is either `resolved`, or carries a decision-impact assessment, an owner, and a next verification action. A `CT-` row with an empty impact field fails the precondition regardless of the judgment. |
| Evidence that satisfies it | A verdict entry naming each open `CT-` row and the decision it does **not** affect, with the reasoning. Every cross-pass disagreement promoted under the finding schema appears here, because those are `Critical` by construction. |
| Fails when | Any open contradiction bears on a material decision; any `CT-` row is unassessed; or the register is absent while the finding ledger contains an `X` row, which means a disagreement was found and never registered. |

### G08 — Canonical document and section coverage is 100%, including justified `N/A` entries

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | All 23 canonical files exist at their exact paths. Every section required by the applicable contract in `references/package-contract-*.md` is present as a heading. Every section marked `N/A` carries a non-empty reason **and** an evidence locator. |
| Evidence that satisfies it | A coverage report listing 23 of 23 files, every required heading present, and every `N/A` with its reason and `EV-####`. |
| Fails when | A file is missing or renamed; a required heading is absent; an `N/A` carries no reason or no evidence locator. Whether a justification is *good* is judgment and surfaces as a pass-A finding, entering the gate through G03 — this condition only requires that a justification exists at all. |

### G09 — All material internal claims have an evidence state and locator

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Ledger integrity in three directions: every `EV-####` row has a state in `{V, C, R, I, U, N/A}`, a non-empty locator, an observed date, and a consuming-documents list; every `[EV-####]` citation in the package resolves to an existing row; every row's listed consuming documents exist and actually cite it. |
| Evidence that satisfies it | A clean `bin/dossier-ledger-lint.sh` run at the pinned revision, with zero dangling citations, zero incomplete rows, and zero orphan rows. |
| Fails when | Any row is incomplete; any citation dangles; any row claims a consuming document that does not cite it. Whether the author put *every* material claim into the ledger is a coverage question scored under dimension 1 and raised as pass-A findings — it reaches the gate through G01, G02, and G03. |

### G10 — All public claims map to verified or corroborated, disclosure-approved evidence

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | For every `CL-####` row with a `06-public/**` destination: status is `approved`, it references at least one `EV-####`, and every referenced row has state `V` or `C`. `R`, `I`, and `U` may never back a public claim. |
| Evidence that satisfies it | A register report showing each public claim, its destination document, its evidence IDs, and their states — all `V` or `C`. |
| Fails when | Any public claim references `R`, `I`, or `U` evidence; references nothing; or is not `approved`. G10 and G04 are deliberately separate: **G10 asks whether registered public claims are adequately backed** (mechanical), **G04 asks whether every public sentence was registered at all** (judgment). Neither covers the other. |

### G11 — Internal links, document paths, and diagram syntax validate

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Every relative link and cross-document reference in the package resolves to an existing file and, where anchored, an existing heading. Every fenced diagram parses. Diagram node and edge labels are compared against the component and interface inventories. |
| Evidence that satisfies it | Zero unresolved links, zero unparseable diagrams, and a diagram-to-inventory comparison with no unmatched node or edge. |
| Fails when | Any link or anchor is broken; any diagram fails to parse; any diagram names a component absent from the catalog. A diagram that renders while contradicting the inventory is worse than one that fails to render, because it is believed. |

### G12 — Commands and examples are executed successfully or visibly marked as not executed

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Every command block and example in the package carries a stamp of `verified`, `partially verified`, or `not executed`, with environment and date. Every `verified` stamp corresponds to a recorded execution in the evidence ledger's executed-checks section. |
| Evidence that satisfies it | A stamp on every block, and an execution record behind every `verified` one. A package built with `engagement.allowedActions.runTests: false` in which every block reads `not executed` with its reason **passes this condition** — honesty is the requirement, not green checks. |
| Fails when | Any block is unstamped, or any `verified` stamp has no execution record. This is the mechanical half of "unexecuted checks presented as passed"; see [What must never appear](#what-must-never-appear). |

### G13 — Planned behaviour is not presented as implemented

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | Read every capability, feature, control, and integration statement and decide whether it describes what exists now or what is intended. Roadmap language that reads as current behaviour is the failure. Tense and hedging are not reliable signals, which is why this cannot be scripted. |
| Evidence that satisfies it | A verdict entry confirming the implemented / partial / planned / deprecated / absent states in the capability map are each backed by evidence, that `01-project/product-and-domain.md` separates roadmap statements from current behaviour, and that no public document carries a planned capability as a present one. |
| Fails when | Any statement describes intended behaviour as present, in any document. In `06-public/**` this is at least `High` and usually `Critical`, because a customer cannot tell the difference and will act on it. |

### G14 — Targets are not presented as measured results

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | Every number in the package is classified as a target or a measurement. A measurement carries a window, an environment, and the query or source that produced it; a target carries none of those and must be labelled as an objective. SLIs, SLOs, SLAs, and error budgets must be distinguished from one another. |
| Evidence that satisfies it | A verdict entry confirming that each availability, latency, throughput, durability, freshness, coverage, and cost figure is labelled correctly, and that no internal objective is stated as a customer guarantee. |
| Fails when | An objective appears as an achieved result; a measurement appears without its window or environment; an SLO is quoted to a customer or partner as a commitment. |

### G15 — Policies are not presented as implemented controls

**Tag:** judgment

| Aspect | Content |
|---|---|
| Check | Every control statement is classified implemented / policy-only / planned / unknown. A written policy is evidence that a rule exists; a control needs a mechanism, an owner, and evidence it operates. The distinction is semantic and contextual, so it is judged, not grepped. |
| Evidence that satisfies it | A verdict entry confirming the four control classes are distinguished throughout `03-assurance/security-privacy-and-compliance.md`, that each implemented control carries evidence and a last-test date, and that no public document upgrades a policy into a control. |
| Fails when | A retention policy, access policy, encryption standard, or review requirement is described as an operating control without a mechanism and evidence of operation. |

### G16 — Unresolved uncertainty and source limitations are visible

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Structural presence: `00-control/documentation-index.md` carries an unresolved-critical-questions-and-contradictions section; every document with status `partially verified` names its missing evidence and next action; the evidence ledger carries an unavailable-or-inaccessible-evidence section and a stale-evidence section; `05-due-diligence/technical-due-diligence-report.md` states its scope limitations and unavailable sources; `07-verification/documentation-verification-report.md` states residual uncertainty. |
| Evidence that satisfies it | Each of those sections present and non-empty, or explicitly stating `none` as a positive assertion. `none` counts as present; blank does not. |
| Fails when | Any required disclosure section is absent or blank. Whether the disclosures are *complete* is a coverage judgment scored under dimensions 1 and 5 and raised as pass-A findings, reaching the gate through G01, G02, and G03. |

### G17 — The reviewer-pass independence method is disclosed, including model diversity

**Tag:** `mechanical`

**Check:** `07-verification/documentation-verification-report.md` contains a `## Reviewer-pass independence method` heading, a table row per pass that ran, and a line beginning `Model diversity:`.

**Satisfied by:** the table and the diversity line, written honestly — including when the honest answer is `none`, because all passes shared a model.

**Why it is a gate condition rather than a convention.** `references/independent-audit-protocol.md` calls this disclosure required, and the package's own evidence standard turns on it: three passes that shared one model decorrelate lenses but not model-level blind spots, and a reader who cannot see which tier ran has no way to weigh the audit. Without G17 a package could pass all eighteen other conditions while omitting the one sentence that tells the reader how much the verification is worth. That is the same defect class the format exists to catch elsewhere — a capability claim broader than what was actually done.

Mechanical rather than judgment: presence of the heading and the `Model diversity:` line is decidable from the file. Whether the disclosure is *accurate* is covered by G16's honesty requirement and by the scorer.

### G18 — No hard-category prose-clarity violation exists in the package

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | `bin/dossier-prose-lint.sh --output-root <path> --json` across all 23 canonical files. Hard categories only: banned marketing adjectives, banned phrasal verbs, banned filler/hedge phrases, Latinate long-form words, semicolons, over-length sentences, over-length paragraphs. A required epistemic-hedge marker (`Inferred:`, `Unknown:`, `Recommendation:`, or the phrasing in `references/source-authority-and-claim-states.md`) is exempt from the hedge-phrase and length rules, unconditionally — see `skills/prose-clarity/SKILL.md`. |
| Evidence that satisfies it | The linter's own JSON reporting `blocking_violations: 0`, with its exit code (`0`) agreeing. |
| Fails when | `blocking_violations` is nonzero; `dossier-prose-lint.sh` is missing or non-executable, which never reads as a pass; or the script's exit code and its own reported count disagree, which is a linter defect recorded as a failure rather than a result to pick favorably from — the same asymmetry G06 and G08 apply to a missing dependency. |

Advisory categories (passive voice, nominalization, em-dash count) are never checked here — they are grammar-heuristic and false-positive-prone, so they feed `dossier-pass-c-audience`'s Step 5 and Dimension 10 of `references/scorecard-rubric.md` as judgment context instead of a mechanical gate condition. This plugin's own reference documents use em-dashes constitutively, and an advisory category gating release would fail this plugin's own package on its first run.

### G19 — No unresolved Critical or High dependency vulnerability lacks a recorded disposition

**Tag:** mechanical

| Aspect | Content |
|---|---|
| Check | Read `00-control/evidence-ledger.md` for vulnerability-finding rows (`Notes` tagged `vuln-finding severity=<Critical\|High>`, written by the evidence-ledger skill from `bin/dossier-vuln-evidence.sh`'s normalized output — dossier never executes a scanner itself). For each Critical/High row, look for a disposition: a `04-operating/decisions-technical-debt-and-risks.md` Risk register row citing the same `EV-####`, with `Category` `dependency` or `security`, a named `Owner`, and `Status` other than `open`; or an Accepted risks row citing it with a named accepter, a calendar-valid acceptance date, a stated basis, and a calendar-valid review date. |
| Evidence that satisfies it | Every Critical/High `vuln-finding` row in the ledger has a qualifying Risk register or Accepted risks row citing it. A package with zero Critical/High findings (including zero vulnerability evidence recorded at all, and including scan output with only Medium/Low findings) satisfies this trivially **only when** a `vuln-scan-coverage status=parsed` row is also present — see "Fails when" for the no-evidence case, which is `INCONCLUSIVE`, not a vacuous pass. |
| Fails when | Any Critical/High `vuln-finding` row has no qualifying disposition — `FAIL`, naming the specific `EV-####`. Zero vulnerability evidence recorded in the ledger at all, or a `vuln-scan-coverage status=parse-error` row (the scan artifact could not be parsed) — `INCONCLUSIVE`, never `PASS`: an unevaluated condition must never read as assent, the same principle that governs an uncovered judgment set. This is a deliberate design choice: it means every existing dossier package moves to `not ready` on this condition the moment it exists, until vulnerability evidence is actually ingested — see `.decisions/issue-136.md`. |

Deliberately never reuses G03's `findings.md` ledger: `references/finding-schema.md` scopes `findings.md` to defects **in the documentation**, evidenced by something outside it. A dependency vulnerability is a defect in the project being documented, not in the documentation describing it — architecturally out of scope for G03, and recorded instead as a risk row per that same reference document's own guidance.

A Risk register or Accepted risks row citing the finding may appear anywhere in its table — the check does not stop at the first citing row — and a citation may name more than one `EV-####` in the same bracket, per `references/evidence-ledger-schema.md`'s inline citation grammar. Cells in both tables carry no raw `|` character, the same constraint the evidence ledger's own table already carries.

## Package status

The gate result maps to exactly one of three package statuses, which is what the completion response and `07-verification/documentation-verification-report.md` report.

| Status | Requires |
|---|---|
| `release-ready` | All nineteen conditions `PASS`, with the judgment set covered by a valid scorer verdict file. |
| `conditionally ready` | Every failing condition satisfies all four of: no unresolved `Critical` finding anywhere in the package; a named individual owner; an exact, obtainable evidence request; and disclosure of the condition in both the documentation index and the verification report. Internal audiences may use the package with the named conditions attached. `06-public/**` is **not** released. |
| `not ready` | Any unresolved `Critical` finding; any secret or prohibited disclosure present; any failing condition with no known resolution path; or an `INCONCLUSIVE` gate result. |

`INCONCLUSIVE` always maps to `not ready`. It never maps to `conditionally ready`, because a condition is something known and accepted, and an unevaluated condition is neither.

A package that cannot pass is issued with exact blockers and evidence requests. It is never issued as a pass with an asterisk, and the phrase "release-ready with minor caveats" does not exist in this vocabulary.

## Severity definitions

Carried from the source contract. Severity is a statement about the decision a reader would get wrong.

| Severity | Definition |
|---|---|
| `Critical` | Could cause a fundamentally wrong transaction, security, safety, legal, operational, or public decision. |
| `High` | Could materially mislead diligence, onboarding, integration, deployment, incident response, or customer trust. |
| `Medium` | Creates meaningful ambiguity, friction, inconsistency, or maintainability risk. |
| `Low` | Localized clarity, formatting, or completeness issue with limited decision impact. |

`gate.failOn` defaults to `["Critical", "High"]` and is what G03 reads. Lowering it is a local policy decision that the verification report records verbatim, alongside which findings it let through.

## What must never appear

Four statements are never permitted in a released package, at any severity discount, in any document, internal or public.

| # | Must never appear | Enforced by |
|---:|---|---|
| 1 | Planned behaviour presented as implemented | G13 (judgment) |
| 2 | Targets presented as measured results | G14 (judgment) |
| 3 | Policies presented as implemented controls | G15 (judgment) |
| 4 | Unexecuted checks presented as passed | G12 (mechanical stamp-and-record check) and G14 for the numbers such checks would have produced |

Three of the four are judgment-tagged. That is the concrete reason the script cannot pass a package alone: the failures that most reliably mislead a reader are semantic, and a grep cannot see any of them. A gate that skipped them would certify precisely the packages that most need to be caught.

The corresponding positive obligation, stated in `references/document-headers.md` and required of every document, is that a reader can always tell what is true now, what is planned but not implemented, what is unknown or unverified, what the important limits and conditions are, and where the canonical source of truth lives.

## Related references

| Reference | Covers |
|---|---|
| `references/finding-schema.md` | Finding row shape, marker format, corroboration, dedup, status vocabulary |
| `references/scorecard-rubric.md` | The ten dimensions, 0–10 anchors, deduction ledger, severity caps |
| `references/independent-audit-protocol.md` | How the passes run, what they may receive, how independence is recorded |
| `references/evidence-ledger-schema.md` | `EV-####` row shape, read by G09 |
| `references/register-schemas.md` | `CL-`, `CT-`, `AQ-`, `TM-` row shapes, read by G04, G05, G07, G10 |
| `references/package-contract-*.md` | Required sections per directory, read by G08 |
| `references/document-headers.md` | Header contract, read by G16 and scored under dimension 10 |
| `references/prose-style-and-vocabulary.md` | Word lists and the epistemic-hedge carve-out, read by G18 |
