# Independent Audit Protocol

Reference document. The nine-step protocol every verification pass executes, the contract that keeps the passes independent, and the honest limits of what a plugin can enforce about independence.

An audit is not a second reading. A second reading inherits the first reading's frame and confirms it — that is correlated error, and correlated error is the specific failure this protocol exists to prevent. An audit begins from the project evidence, rebuilds what it needs, and compares the result to the package. Where they disagree, the package is wrong until the evidence says otherwise.

## Independence contract

This is a hard contract, not a preference. It is the dossier analogue of the Independence Protocol in `plugins/flow/agents/verdict-judge.md`, and it is enforced by construction, not by instruction.

### What a pass MUST NOT receive

| Denied input | Why |
|---|---|
| The drafting transcript | The reasoning that produced a claim is the most persuasive possible argument for it, and it is not evidence. A pass that reads the author's reasoning audits the reasoning, not the project. |
| The authored canonical project model | Pass B's job is to rebuild the model from sources and compare it to the published documents. Handing it the author's model makes it verify the model against itself, which always succeeds. The **published** documents under `project.outputRoot` are the audit target and must be read; the drafting-time model artifact and the narrative explaining how it was derived must not. |
| Any other pass's findings | Three lenses that see each other converge. Convergence is the outcome the design is built to avoid: a defect only one lens can see is the expected product of decorrelation, and it disappears the moment the lenses share a prior. |
| Prior-round findings | A pass that knows what round 1 found searches where round 1 searched. Rounds are re-audits, not follow-ups; the repair record belongs to reconciliation. |
| The reconciliation logic | A pass that can load the merge, dedup, and disagreement rules starts optimizing its output for the merge — pre-deduplicating, pre-softening, pre-agreeing. The `finding-reconciliation` skill is absent from every pass agent's `skills:` list, and a test asserts it stays absent. |
| The author's self-score | An anchor. A pass that has seen 96/100 will not independently produce 88. |

### What a pass MUST receive

| Input | Notes |
|---|---|
| `PROJECT_NAME`, `PROJECT_ROOT_OR_SOURCES`, `DOCUMENTATION_ROOT`, `PROJECT_VERSION_OR_COMMIT` | The same pinned revision the package describes. A pass auditing a different revision produces findings that are neither true nor false. |
| `DUE_DILIGENCE_CONTEXT`, `PUBLIC_DISCLOSURE_POLICY`, `REGULATORY_OR_CONTRACTUAL_CONTEXT` | Materiality without a decision context is guesswork. |
| `ALLOWED_ACTIONS` | Determines which checks can be executed and which must be recorded `not executed`. |
| Read access to the project sources | Non-negotiable. A pass with access only to the package cannot audit anything; it can only proofread. |
| Read access to the complete package, including all five registers | The audit target. |
| Its own lens assignment and the relevant sections of this document | Below. |

### How independence is enforced

Five mechanisms, none of which is a sentence in a prompt:

1. **Separate dispatches.** Each pass is a separate `Agent()` call with its own context. Nothing crosses.
2. **`memory: none`** on all three pass agents. No cross-session priors.
3. **Skill firewall.** No pass agent lists `finding-reconciliation`, and each loads a *different* second skill, so their priors differ by construction rather than by instruction. Pass A loads `evidence-ledger` and `doc-package-contract`; pass B loads `project-modeling`; pass C loads `disclosure-gating`.
4. **Single-message dispatch.** `/dossier:audit` spawns all passes in one message. Sequential dispatch would put pass A's output into the orchestrator's context before pass B is spawned, and an orchestrator that has read A cannot spawn a B that has not.
5. **Per-pass model.** `verification.passModels` allows a different model per pass.

### The two independence tiers

**A plugin cannot guarantee a different model.** Stating otherwise would be the exact failure this plugin exists to catch — a capability claim broader than the implementation. Two tiers ship, and which one ran is recorded.

| Tier | Mechanism | What it actually delivers | What it does not |
|---|---|---|---|
| `in-plugin` | Three subagent dispatches with `memory: none`, a skill firewall, and `verification.passModels` | Genuinely independent **context**, genuinely different **lenses**, and a different **model** when the operator configures one | Any guarantee about model diversity when `passModels` is left at `inherit` — in that case all three passes share weights and share whatever blind spots those weights have |
| `external` | `/dossier:audit --external` renders `templates/external-audit-prompt.md` as a self-contained prompt for a genuinely different model or a human reviewer; findings return via `/dossier:reconcile --findings <path>` | Cross-model independence, which is the only kind that decorrelates model-level blind spots | Automation — the operator runs it, and the plugin records what they report having run |

Both tiers are recorded in `07-verification/documentation-verification-report.md` under a required heading:

```markdown
## Reviewer-pass independence method

| Pass | Tier | Model | Context | Memory | Second skill |
|---|---|---|---|---|---|
| A | in-plugin | claude-opus-5 | isolated subagent | none | evidence-ledger |
| B | in-plugin | claude-opus-5 | isolated subagent | none | project-modeling |
| C | external | <vendor model id> | separate conversation, operator-run | n/a | n/a |

Model diversity: partial — passes A and B shared a model. Blind spots common to that model are not
covered by this round.
```

The last line is required and is written honestly. `Model diversity: none` is an acceptable result; concealing it is not.

## Lens split

Each pass owns a subset of the nine steps. No pass runs all nine, and no pass runs step 9.

| Pass | Lens | Owns steps | Reads the package as |
|---|---|---|---|
| **A — evidence and diligence** | Independent coverage, claim sampling, evidence integrity | 1, 2, and the pass-A half of 6, 7, 8 | A skeptical technical due-diligence analyst who does not believe the source inventory |
| **B — engineering and operational adversary** | Falsify the project model with end-to-end traces | 3, and the pass-B half of 6, 7, 8 | A principal engineer, production operator, security architect, privacy engineer, and hostile-but-fair acquirer |
| **C — audiences, consistency, and disclosure** | Reader usability, mechanics, cross-document consistency, disclosure safety | 4, 5, and the pass-C half of 6, 7, 8 | Six readers trying to complete real tasks, plus an editor and a disclosure reviewer |

**Step 9 is not a pass step.** Improvement and re-audit are executed by the reconciliation owner, after every pass file is written. A pass that repairs what it found has destroyed the evidence for its own finding and contaminated the next round. This split is why `verification-protocol` and `finding-reconciliation` are separate skills, and why no pass agent may list the latter.

## Audit constraints

Binding on every pass, every round, both tiers.

| Constraint | Meaning in practice |
|---|---|
| Remain read-only outside `DOCUMENTATION_ROOT` unless explicitly authorized | Enforced by `engagement.allowedActions`, not by good intentions. A pass never modifies project source. |
| Never reproduce secrets, credentials, personal data, private customer information, or exploitable detail | A finding about a leaked secret names the file and the secret's type; it never quotes the value. The finding is the evidence; the value is the harm. |
| Do not infer implementation from intentions, tickets, roadmaps, or prose | A ticket saying "add rate limiting" is evidence that someone wanted rate limiting. It is not evidence that rate limiting exists. |
| Do not treat passing tests as proof of undocumented behaviour beyond their scope | A green suite proves the assertions it makes. It proves nothing about the behaviour it does not assert, and test names are not assertions. |
| Do not treat missing incidents, vulnerabilities, or failures as proof of safety | Absence of a recorded incident is evidence about the recording, not about the system. Never convert absence of evidence into evidence of absence. |
| Do not treat policies as implemented controls | A written retention policy is a policy. A retention job with a schedule and an execution record is a control. The package must distinguish them and so must the audit. |
| Do not treat targets as measured outcomes | An SLO is a target. A measurement is a number with a window, an environment, and a query. |
| Do not treat an existing public statement as disclosure approval or technical proof | A sentence already on a website is evidence that someone published it. It is neither an approval record nor a verification. |
| Label facts, reports, inferences, unknowns, and not-applicable claims distinctly | Findings inherit the `V/C/R/I/U/N-A` vocabulary from `references/source-authority-and-claim-states.md`. |
| Provide evidence and concise reasoning, not hidden chain-of-thought | Every finding carries `verifier_evidence`. Conclusions without locators are rejected at normalization. |

## Step 1 — establish independent coverage

**Pass A.**

Inventory the project evidence **without reading the package's source inventory first**. Ordering matters: an inventory built after reading the index is an inventory of what the index mentions.

1. Enumerate repositories, services, modules, packages, interfaces, schemas, environments, pipelines, tests, deployments, dashboards, incident records, product artifacts, security evidence, dependencies, assets, and stakeholder sources from the sources directly.
2. Only then open `00-control/documentation-index.md`, `evidence-ledger.md`, `terminology-and-ownership.md`, `assumptions-questions-and-contradictions.md`, and `claim-and-disclosure-register.md`.
3. Diff the two inventories in both directions. Omissions from the package are findings against dimension 2. Entries in the package with no counterpart in the sources are findings against dimension 3 — they are either stale or invented, and both matter.
4. Confirm all 23 canonical files exist at their exact paths. A missing file is a `High` finding at minimum; a missing control file is `Critical`, because the registers are what make every other claim checkable.

The canonical file set is normative and is listed in the package contract references (`references/package-contract-*.md`). Verify against that list, not against memory of it.

Record the inventory method: what was enumerated, by what command or traversal, at what revision. An inventory whose method is unstated cannot be reproduced and is not evidence.

## Step 2 — build a claim sample

**Pass A.**

An unstated sample is not evidence. The report must carry the method, the strata, the sizes, the selection function, and the observed defect rate — enough that another auditor could draw the same sample.

### Stratum 1 — census, audited at 100%

Never sampled. One wrong row here changes a transaction, security, or legal decision.

| # | Category |
|---|---|
| 1 | Public capabilities and limitations |
| 2 | Security, privacy, compliance, safety, responsible-AI, and data-handling claims |
| 3 | Reliability, performance, availability, recovery, support, compatibility, and scale claims |
| 4 | Current-versus-planned behaviour |
| 5 | Material due-diligence conclusions, red flags, deal-breakers, and remediation estimates |
| 6 | Setup, build, test, deploy, rollback, backup, restore, and incident-response instructions |
| 7 | Asset ownership, IP provenance, dependency, end-of-life, and licensing claims |
| 8 | Architecture trust boundaries and sensitive data flows |

`verification.claimSample.auditAllCategories` extends this list per project; it never shortens it. The eight categories above are the floor.

### Stratum 2 — risk-based sample

Everything else. Let `N` be the total material claims in the ledger and `Nc` the census stratum. Then `Nr = N − Nc` and:

```
n = min( Nr, max( claimSample.minRows, ceil( claimSample.percent / 100 x Nr ) ) )
```

With the shipped defaults (`minRows: 30`, `percent: 10`):

| `N` | `Nc` | `Nr` | `ceil(0.10 x Nr)` | `n` | Total audited | Coverage |
|---:|---:|---:|---:|---:|---:|---:|
| 214 | 86 | 128 | 13 | 30 | 116 | 54% |
| 640 | 180 | 460 | 46 | 46 | 226 | 35% |
| 41 | 22 | 19 | 2 | 19 | 41 | 100% |

`minRows` is what stops a small package from being audited by a sample of two; the third row shows it collapsing the sample into a census, which is the correct outcome for a small ledger.

**Selection function.** Deterministic, reproducible, and not cherry-picked: sort candidate rows by `sha256(claim_id + round_seed)` ascending and take the first `n`, where `round_seed` is `"r" + round`. Record the seed. A sample the auditor chose by hand is a sample of what the auditor already suspected.

**Stratification.** Every canonical document with at least one non-census claim contributes at least one sampled row. Without this, the sample concentrates in the largest documents and a small document can carry a systematic defect through every round untouched.

**Escalation.** If the sampled stratum yields two or more findings at `High` or above, or a defect rate above 10%:

1. Draw a second sample of the same size from the unsampled remainder, same function, seed `"r" + round + "b"`.
2. If the combined defect rate still exceeds the threshold, escalate the stratum to a census and file a `Critical` finding against dimension 1 stating that the ledger has a systematic weakness rather than isolated errors.

A sample exists to detect systematic weakness. Detecting it and then not acting on it wastes the sample.

### Per-claim audit

For each audited claim, determine and record:

| Determination | Note |
|---|---|
| Exact wording and destination document | Verbatim. Paraphrase destroys the dedup hash and the repair. |
| Materiality | Against `DUE_DILIGENCE_CONTEXT`, not against how interesting it is. |
| Evidence locator | Does it resolve? A `[EV-####]` citation pointing at a row that does not exist is a `High` finding on its own. |
| Evidence authority, date, version, environment | Per `references/source-authority-and-claim-states.md`. |
| Whether the evidence **entails** the claim | The most common real defect: evidence consistent with the claim, presented as evidence for it. |
| Whether important conditions were lost | Scope, environment, percentile, version, tenant, region. |
| Correct claim state | `V`, `C`, `R`, `I`, `U`, or `N/A` — independently assigned, not read off the ledger. |
| Whether public disclosure is approved | Only for claims with a `06-public/**` destination. |
| Verdict | `pass` \| `qualify` \| `correct` \| `remove` \| `seek evidence` |

## Step 3 — attempt to falsify the project model

**Pass B.**

Rebuild the model from the sources and try to break it. Ten traces; `verification.traceCount` sets how many run, with a floor of 3.

| # | Trace | Mandatory |
|---:|---|---|
| 1 | A primary product or user journey | Yes |
| 2 | An identity, authorization, or trust decision | |
| 3 | Sensitive data from collection through deletion | |
| 4 | A code or product change through test, release, deployment, and rollback | Yes |
| 5 | An external integration through its normal **and** error paths | |
| 6 | A dependency outage or partial failure | One of 6, 8, 9, 10 |
| 7 | A capacity, rate, latency, or cost boundary | |
| 8 | A backup, restore, or disaster scenario | One of 6, 8, 9, 10 |
| 9 | An alert and incident from detection through recovery | One of 6, 8, 9, 10 |
| 10 | An AI, model, or agent failure or abuse path, where applicable | One of 6, 8, 9, 10 |

The three mandatory slots correspond to the model's three load-bearing axes: it works, it changes, it breaks. A model tested only on slot 1 is a happy-path diagram.

**When `traceCount` is below 10**, the report names which slots were dropped and why. Reducing trace coverage is a deliberate reduction in assurance, and the verification report records it as such rather than presenting a partial trace set as a complete one.

**When a trace is genuinely inapplicable** — a library with no deployment, an offline tool with no external integration — substitute; never silently drop. Record all four fields:

| Field | Content |
|---|---|
| Slot | The trace number being substituted |
| Why inapplicable | With an evidence locator, not an assertion. "No deployment" needs the absence of deployment definitions demonstrated, not asserted. |
| Substitute | The trace actually run |
| Why comparable | Which boundary the substitute exercises in place of the original. A substitution that exercises no boundary is a dropped trace with extra words. |

For each trace, compare observed reality against every affected document and diagram, then run the falsification checklist.

### Falsification checklist

| # | Look for | What "found" looks like |
|---:|---|---|
| 1 | Missing components or edges | A service, queue, cron, or third party in the sources that appears in no diagram and no catalog |
| 2 | Inconsistent names, roles, permissions, or ownership | The same component under two names, or a role with different permissions in two documents |
| 3 | Undocumented coupling and manual steps | A deploy that requires a human to run one command that appears in no runbook |
| 4 | Wrong state ownership or consistency assumptions | Two services writing the same record; a document claiming a single writer |
| 5 | Retries without idempotency | A retry policy in code with no idempotency key, documented as safe |
| 6 | Timeouts, queues, caches, or failure modes omitted from happy-path diagrams | A cache in the code path absent from the data-flow diagram, so a reader mis-reasons about staleness |
| 7 | Unsafe or untested recovery | A restore procedure with no recorded execution, documented without that qualification |
| 8 | False isolation or tenancy assumptions | A shared resource crossing a boundary the architecture document draws as isolated |
| 9 | Weak observability | A critical journey with no alert, no dashboard, and no owner, described as monitored |
| 10 | Cost and scaling cliffs | A per-request external call with no cap, in a document claiming linear cost |
| 11 | Stale or unsupported dependencies | A pinned version past end-of-life, or a single-maintainer package on a critical path |
| 12 | Licensing or provenance ambiguity | Vendored or copied code with no origin recorded |
| 13 | Secrets or sensitive disclosure | A credential, key, internal hostname, or customer identifier reachable in the package |
| 14 | AI autonomy, injection, leakage, evaluation, drift, or fallback gaps | An agent with tool access and no documented authorization boundary; an evaluation suite with no drift monitoring |
| 15 | Customer and partner promises broader than implementation | A support, availability, or compatibility commitment the implementation does not deliver |

Items 1–12 are documentation defects even when the underlying system is fine — the defect is that a reader would reason wrongly. Items 13–15 are additionally disclosure and commitment risks and are rarely below `High`.

## Step 4 — test audience usability

**Pass C**, for six of the seven personas.

The source lists seven readers. All seven are carried; six are simulated by pass C. Persona 1 belongs to pass A because its questions are grounding questions, not navigation questions — a technical executive is asking whether the conclusions are supported, which is pass A's lens.

| # | Persona | Pass | Task it must complete using the package alone |
|---:|---|---|---|
| 1 | Technical executive making a diligence decision | **A** | Reach a proceed / proceed-with-conditions / pause / do-not-proceed position, and name the evidence it rests on |
| 2 | New engineer making a first safe contribution | **C** | Set up, locate the change site, make a bounded change, test it, and know what "done" means |
| 3 | New product manager deciding whether behaviour is intended | **C** | Determine whether an observed behaviour is implemented-as-designed, a known gap, or a defect |
| 4 | Operator responding to a credible incident | **C** | Go from alert to diagnosis to mitigation to communication, without guessing at an owner |
| 5 | Security or privacy reviewer tracing a sensitive flow | **C** | Follow one class of sensitive data from collection to deletion and identify every control on the path |
| 6 | Technical partner building an integration | **C** | Authenticate, call the supported surface, handle its errors, and know the compatibility and deprecation policy |
| 7 | Customer evaluating capability and trust claims | **C** | Determine what the product does, what it does not, what it stores, and what recourse exists |

Persona 5's *trace* is pass B's work. Persona 5 in pass C judges only whether a reviewer could follow that flow from the package alone — pass C does not re-run the trace and does not read pass B's output.

For each persona, record:

| Field | Note |
|---|---|
| Entry point obvious? | Yes/no, from `00-control/documentation-index.md` |
| Navigation hops to critical information | The mechanical proxy for the source's "under two minutes" test: **at most 3 hops from the index**. Hops are counted, not estimated. |
| Tasks that cannot be completed | With the specific step where the reader stalls |
| Decisions that remain ambiguous | With the two readings the package permits |
| Misleading simplifications | Statements that are true internally and false as written for this audience |
| Missing prerequisites, owners, examples, limitations, or escalation paths | Named individually, not as "incomplete" |

A persona that cannot complete its task is at least a `High` finding against dimension 6 or 9, depending on whether the reader is internal or public.

## Step 5 — validate mechanics

**Pass C**, when safe and authorized.

| Check | Records |
|---|---|
| Internal links and canonical paths resolve | Every broken link, individually |
| Diagram syntax parses; diagram nodes and edges match the inventories | A diagram that renders but contradicts the component catalog is worse than one that fails to render |
| Documented setup, build, test, lint, type-check, generation, and validation commands run | Exit code, environment, and date |
| Examples validate against schemas and implementation | Including public examples against the supported surface |
| Referenced versions and environment assumptions hold | Against the pinned revision |
| Dependency and license outputs inspected | Against the manifests, not against the package's summary of them |
| No accidental secrets or prohibited public detail | Type and location; never the value |
| Duplicated facts across documents agree | Numbers, dates, owners, statuses, component names |
| Every public claim maps to the internal claim register and approved evidence | Claim-by-claim, `06-public/**` sentence to `CL-` row |

Record `not executed` with its reason rather than implying success. `engagement.allowedActions.runTests: false` produces a package in which every command claim is marked `not executed` — that is a correct and honest package, and presenting it as verified is a `Critical` finding.

## Step 6 — perform the pass

Each pass completes its lens and records findings **before** any edit is made anywhere. The pass writes exactly one file:

```
.dossier/runs/<run-id>/pass-A.md
.dossier/runs/<run-id>/pass-B.md
.dossier/runs/<run-id>/pass-C.md
```

Line 1 is the `DOSSIER_AUDIT` marker defined in `references/finding-schema.md`. A pass that produced no findings still writes its file, with `findings=0`.

No pass may dismiss another pass's finding, because no pass can see another pass's findings. That rule lands on reconciliation instead, where it takes a stronger form: a finding is dismissed by evidence or not at all.

## Step 7 — report findings before repair

Findings are published before any repair, in the row shape defined by `references/finding-schema.md`. All ten required fields; `verifier_evidence` on every row; `status` always `Open`.

The ordering is load-bearing. Repairing first and reporting after produces a report written by someone who already knows the ending, and it makes the pre-repair state — which is the actual audit result — unrecoverable.

## Step 8 — score independently

Each pass scores all ten dimensions using the anchors in `references/scorecard-rubric.md`, citing at least one of **its own** finding IDs for every deduction.

| Rule | Rationale |
|---|---|
| A pass scores all ten dimensions, not only the ones its lens covers | A lens-limited score cannot be compared across passes, and comparison is the point |
| A pass may not read another pass's score, or the author's | Anchoring |
| Deductions cite finding IDs from that pass only | A deduction with no finding behind it is an impression |
| Per-pass scores are **inputs**, not the verdict | `dossier-scorer` issues the single authoritative score and the gate verdict, seeing the final package and the adjudicated findings but never the drafting or repair rationale |
| Divergence above 2.0 points on any dimension between passes is recorded in the verification report as a confidence note | Large divergence means the dimension is being read differently, which is information about the rubric as much as about the package |

## Step 9 — improve, then re-audit

**Not a pass step.** Executed by the reconciliation owner after every pass file exists.

1. Preserve valid author content and unrelated changes.
2. Correct `Critical` and `High` findings first.
3. Correct `Medium` and `Low` findings where evidence permits.
4. Update the evidence, assumption, contradiction, disclosure, terminology, ownership, and verification registers.
5. Remove or qualify unsupported public claims.
6. Reduce duplication and repair cross-links.
7. Re-run every check affected by a correction. A repair whose check was not re-run leaves its finding `Open`.
8. Repeat all three passes when a correction materially changes product behaviour, architecture, data handling, security, reliability, or a public claim.
9. Provide before-and-after scores.

Bounded by `verification.maxRounds`. When rounds are exhausted with conditions still failing, the package is issued `conditionally ready` or `not ready` with exact blockers and evidence requests — never as a pass with an asterisk.

Where evidence is missing, do not paper over the gap: mark the affected document `partially verified`, record the question and its decision impact in the open-questions register, and request the smallest specific evidence that would settle it.

## Required output

Each pass returns its findings file and its dimension scores. Reconciliation writes `07-verification/documentation-verification-report.md`, which must contain:

| # | Section |
|---:|---|
| 1 | Independent verdict: `release-ready` \| `conditionally ready` \| `not ready` |
| 2 | Project version and evidence cutoff |
| 3 | Audit scope and source coverage |
| 4 | Reviewer-pass independence method, including the tier table and the model-diversity statement |
| 5 | Checks executed versus not executed, with reasons |
| 6 | Claim sample method, strata, sizes, seed, and defect rate |
| 7 | Trace coverage, including substitutions and dropped slots with reasons |
| 8 | Initial score and post-repair score, per dimension, with the deduction ledger |
| 9 | Release-gate result, condition by condition, per `references/release-gate-conditions.md` |
| 10 | Findings by severity and status |
| 11 | Material contradictions, including every `CT-` row opened by a cross-pass disagreement |
| 12 | Unsupported, removed, or qualified public claims |
| 13 | Corrections made |
| 14 | Residual uncertainty and accepted risks, with accepting owners named |
| 15 | Exact next evidence requests and owners |
| 16 | The three highest-value improvements still available |

Do not report that the package is perfect. Report what was verified, what remains uncertain, and whether the defined gates pass.
