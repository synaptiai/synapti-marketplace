# Source Authority and Claim States

Reference document. The seven-level source authority ordering, the six claim states, the rules for moving a claim between states, and the observed/interpreted/unknown/recommended labelling contract. Consumed by every drafting and verification path; the row shape that carries these values is in `references/evidence-ledger-schema.md`.

## Source authority ordering

When sources conflict, do not silently pick the convenient one. Record the conflict as a `CT-####` row, then prefer the higher-authority source.

| Level | Source class | What qualifies | What does not |
|---:|---|---|---|
| 1 | Observed runtime behaviour and reproducible checks | A command that was executed and whose output is captured; a request actually issued against a named environment; a test run whose log is retained; a device or binary actually exercised | A command that *would* work; a test that exists but was not run; a script read rather than executed |
| 2 | Versioned code, schemas, infrastructure definitions, tests, immutable records | Source at a named commit; a migration file; an IaC definition; a committed test's assertions; a merged PR; a tagged release; a signed artifact manifest | Uncommitted working-tree state; a generated file whose generator was not run; a test whose assertions do not cover the claim |
| 3 | Current operational telemetry and release evidence | A dashboard panel with a stated query window; alert history; deployment records; incident records; cost reports | A dashboard that exists but was not read; a metric name without a value; a panel whose retention window predates the observation |
| 4 | Current approved specifications and decision records | An approved ADR, API specification, SLO document, security policy, or data-processing record, each with a visible approval and a current status | A draft; a superseded document; an approved policy treated as evidence that the control is implemented |
| 5 | Tickets, planning documents, existing prose documentation | Issues, roadmaps, design docs, wikis, prior READMEs | Anything in this tier used as the sole support for a public claim |
| 6 | Stakeholder recollection | An interview, a written statement from a named role, a meeting record | A second-hand report of what someone said |
| 7 | Inference | A reasoned conclusion from cited lower-authority rows, with the inference chain stated | A guess; a convention assumed to hold; "it is standard practice to…" |

Three rules bound the ordering:

1. **It is a default, not a substitute for judgment.** A level-1 observation against a misconfigured staging environment is worse evidence than a level-4 approved specification for production. A level-2 file at a commit that was never deployed describes an artifact, not the running system. Record the version and environment on every row precisely so this judgment is possible.
2. **Higher authority does not mean current.** Freshness is an independent axis. A level-2 commit from two years ago and a level-6 interview from yesterday disagree on both axes; resolving that is a `CT-####` row, not an automatic win for level 2.
3. **Authority describes the source, not the claim.** Reading an IaC file is level 2 evidence about *what the file says*. It is level 7 evidence about *what is deployed*, unless a level-1 or level-3 source confirms the file was applied. Rows routinely need splitting on exactly this boundary.

### Instantiating the ordering per project type

The classes are stable; what fills them changes with the project. Classify the project from evidence first (`project.type` in settings, or `auto`), then read the ordering through the matching column.

| Level | Application / service / platform | Library or SDK | Data or AI product | Infrastructure | Embedded or connected hardware |
|---:|---|---|---|---|---|
| 1 | Requests against a named environment; executed test and build runs | Consumer-side integration test executed against the published artifact; example project built and run | Executed evaluation run with retained metrics; a pipeline run whose output artifact is retained; a model invoked with recorded input and output | `terraform plan` / `kubectl get` against a named account or cluster; an executed failover or restore drill | Firmware flashed to a named hardware revision and exercised; measured electrical or timing behaviour on a bench |
| 2 | Application source, DB schemas, migrations, committed tests | Published package manifest, exported type surface, semver history, compatibility matrix in the repo | Dataset version and checksum, feature definitions, training and evaluation code, model card in-repo, prompt and tool definitions at a commit | IaC modules, policy-as-code, network and IAM definitions, cluster manifests | Firmware source at a tag, board schematics and revision, bill of materials, manufacturing test scripts, provisioning definitions |
| 3 | APM, logs, traces, deploy records, incidents | Registry download statistics, downstream CI results, issue traffic from consumers | Production evaluation metrics, drift monitors, inference cost and latency telemetry, feedback and override rates | Cloud provider inventory and billing, capacity and quota dashboards, change records | Fleet telemetry, OTA update success and rollback rates, field-return and RMA records |
| 4 | Approved API specs, SLOs, security policy | Published compatibility and support policy, deprecation policy, release policy | Approved data-processing records, model governance and evaluation policy, human-oversight procedure | Approved network, tenancy, and access architecture; change-control policy; recovery objectives | Certification reports, hazard analyses, approved safety requirements, supplier qualification records |
| 5 | Tickets, design docs, wikis | Issue tracker, RFCs, migration guides | Experiment write-ups, dataset provenance notes, prompt iteration logs | Runbook drafts, capacity planning docs | ECO and change requests, test plans, manufacturing notes |
| 6 | Team interviews | Maintainer statements | Data steward and model owner statements | Platform and SRE statements | Hardware, firmware, and manufacturing engineer statements |
| 7 | Inference | Inference | Inference | Inference | Inference |

Safety-critical systems do not get a separate column; they get a stricter rule. A claim bearing on hazard control, a safety requirement, verification evidence, residual risk, or human fallback may not rest on levels 5–7. If the evidence is not at level 4 or better, the claim is `U` and the gap is a finding, not a qualification.

## Claim states

| State | Name | Entry condition | Where it may appear |
|---|---|---|---|
| `V` | Verified | Directly supported by authoritative, current evidence for this claim type, or by an executed check whose output is retained | Internal unqualified; public unqualified when disclosure-approved |
| `C` | Corroborated | Supported by at least two independent, current sources that agree, **including at least one authoritative for the claim type** | Internal unqualified; public unqualified when disclosure-approved |
| `R` | Reported | Stated by a stakeholder or an existing document, not independently verified | Internal, explicitly labelled as reported. **Never public.** |
| `I` | Inferred | A reasoned conclusion from indirect evidence, with the chain stated | Internal, explicitly labelled as inferred. **Never public.** |
| `U` | Unknown | Required information is unavailable, inaccessible, or the sources contradict each other unresolvably | Internal, as a stated unknown. **Never public**, except where a limitation must be disclosed — and then as a limitation, not as a claim |
| `N/A` | Not applicable | The topic is demonstrably irrelevant to this project, with a short reason and supporting evidence | Internal, at section level, with the reason visible |

### What "authoritative for the claim type" means

Corroboration is not two sources of any kind. The authoritative source class differs by claim:

| Claim about | Authoritative class |
|---|---|
| Runtime behaviour | Level 1–2 |
| Data handling, retention, deletion | Level 1–2 (code, schema, executed check), then level 4 (approved data-processing record) |
| Availability, latency, error rate | Level 3 measured telemetry with a stated window |
| An objective or target | Level 4 approved document — an objective is a *statement of intent*, and the intent document is authoritative for it |
| Licensing and dependency versions | Level 2 lockfile or manifest, plus the current upstream license text |
| Vulnerability status | Level 2 dependency versions plus a current advisory source, retrieved with a date |
| Ownership | Level 4 or better; a name in a wiki is level 5 and yields `R` |
| Historical rationale | Level 2 immutable record (commit, PR, ADR at the time). Absent that, the rationale is `U` — see the hard rules |

Two level-5 documents agreeing is not `C`. It is frequently one document copied from the other, which is why "independent" is in the definition: sources are independent when neither derives from the other. Circular sourcing between package documents is a specific thing verification looks for.

### Promotion

| From | To | Requires |
|---|---|---|
| `U` | `R` | A stakeholder or document now states it. Record who and when. |
| `U` | `I` | Enough indirect evidence to reason from, with the inference chain in `Notes` and the supporting `EV-` rows cited. |
| `R` or `I` | `C` | A second independent current source agrees, at least one of the two authoritative for the claim type. |
| `R` or `I` | `V` | Direct authoritative evidence, or an executed check whose output is retained. The report or inference becomes corroboration, not the basis. |
| `C` | `V` | Direct authoritative evidence for the claim itself, not more agreement. Three agreeing sources is still `C`. |
| `N/A` | anything | The irrelevance evidence was wrong. Correct the row, then re-open every section that was marked `N/A` on its strength. |

Promotion is always accompanied by a `Notes` entry naming the new source and the date. A state that changes with no note is indistinguishable from a state that was edited to make a document pass.

### Demotion

Demotion is unilateral, requires no approval, and is never deferred.

| Trigger | Effect |
|---|---|
| The `Freshness` expiry named on the row has passed | Down one level at minimum (`V`→`C`, `C`→`R`), or to `U` if the source no longer exists. Listed in the ledger's stale-evidence section. |
| The cited source changed | Re-observe or demote. A `V` row whose file moved or whose symbol was renamed is `U` until re-observed. |
| A `CT-####` contradiction touches the row | Both sides drop to at most `R` until the contradiction resolves. Neither side gets to keep `V` while the disagreement is open. |
| The claim was broadened in a document beyond what the row supports | The row does not change; the **document** is the defect. Narrow the prose or add a row. |
| A verification pass cannot reproduce the check | `V` → `R` at best, with the failure recorded. Not `V` with a note. |
| The environment the evidence came from is no longer the environment the claim describes | Re-scope the claim to the environment observed, or demote. |

**Demotion cascades.** Every document in `Consuming docs` must be re-read when a row demotes. A `V`→`R` demotion on a row cited by a public document is a release-gate failure until the public sentence is removed, qualified, or re-supported — the public document does not get to keep a sentence whose evidence moved out from under it.

## Hard rules

These are not stylistic preferences. Each corresponds to a specific way documentation packages mislead.

1. **Only `V` and `C` may appear unqualified in public documents.** An `R` or `I` claim may appear internally when clearly labelled in the prose, not merely in the ledger. `U` appears as a stated unknown. A public document containing an unqualified `R` claim is a release-gate failure regardless of how confident the source sounded.

2. **Never convert absence of evidence into evidence of absence.** "No incidents found" is not "the system has not had incidents" — it is "no incident record was located in the sources inspected". "No vulnerabilities reported" is not "no vulnerabilities". "The grep found no AI dependencies" is evidence about the codebase, not about the operational system. Every absence claim states what was searched, where, and when, and remains bounded by that scope. The paired-row pattern in the ledger reference (`EV-0006` / `EV-0007`) is the shape.

3. **A default ordering is not a substitute for judgment.** Evidence can be stale, incomplete, environment-specific, or actively misleading. A level-1 observation of the wrong environment loses to a level-4 specification of the right one. Record version, environment, and date on every row so the judgment can be made and audited rather than assumed.

4. **Policies are not implemented controls.** An approved policy is level-4 evidence that the policy exists. It is level-7 evidence — inference — that the control operates. The two are separate rows with separate states, and the assurance documents keep implemented, policy-only, planned, and unknown controls visibly distinct.

5. **Targets are not measured results.** An SLO is an intent, evidenced by the approving document. A measured p99 is an observation, evidenced by telemetry with a window. They are separate rows and separate sentences. Internal objectives are also not customer guarantees; converting one to the other requires a contract, not a document.

6. **Tests passing prove what the tests assert, nothing wider.** A green suite is level-1 evidence for the assertions it makes. Using it as evidence for undocumented behaviour is an inference, and inferences are `I`.

7. **Historical rationale without a record is `U`.** Do not reconstruct why a decision was made. If no ADR, PR discussion, or commit message states it, the rationale is unknown — and "unknown rationale" is itself decision-relevant information for anyone considering changing the decision.

8. **A claim's scope travels with it.** "Encrypted" means nothing without at-rest/in-transit, which data, which environment, and which key custody. Scope-free claims of this kind — secure, compliant, encrypted, anonymous, private, highly available, real time — are prohibited outright in public text and require an explicit scope and evidence internally.

## Observed / interpreted / unknown / recommended

Four kinds of statement. Keeping them separate is what makes the package assessable rather than persuasive. Every substantive paragraph in the package is one of these four, and the reader must be able to tell which without opening the ledger.

| Kind | What it is | Prose markers | Claim states | Common failure |
|---|---|---|---|---|
| **Observed** | What the evidence directly shows | Plain declarative present tense, with a citation: "The service authenticates with OAuth 2.0 client credentials [EV-0001]." | `V`, `C` | Stating an observation without its environment or version, so a staging fact reads as a production fact |
| **Interpreted** | What the evidence probably means | Explicit hedge naming the inference: "This suggests …", "The most likely reading is …", "Inferred from the absence of a rollback step: …" | `I`, or `R` when it is someone else's interpretation | Dropping the hedge in a summary, so an interpretation in the body becomes a fact in the executive brief |
| **Unknown** | What could not be established | Named directly: "Whether X holds could not be established; the evidence needed is Y [AQ-####]." | `U` | Silence. An omitted unknown reads as a non-issue, which is the most damaging of the four failures |
| **Recommended** | What should change and why | Modal, forward-looking, and separated into its own subsection: "Recommended: …" | Not a claim state — a recommendation is not evidence about the system | Writing a recommendation in the present indicative, so a proposal reads as an implemented control |

Structural rules:

- Recommendations live in their own subsections or in `04-operating/decisions-technical-debt-and-risks.md` and the due-diligence report. They do not appear inline in an architecture description where a reader scanning for current state will read them as current state.
- A section describing current state contains no recommendations. A section containing recommendations says so in its heading.
- The executive brief and the due-diligence report must keep verified facts, reported assertions, inferences, and unknowns in visibly separate groupings — that is an explicit required-content item for both, precisely because summarizing is where the four kinds collapse into each other.
- Public documents contain observed statements and disclosed limitations. They contain no interpretations, no unknowns presented as reassurance, and no recommendations.
