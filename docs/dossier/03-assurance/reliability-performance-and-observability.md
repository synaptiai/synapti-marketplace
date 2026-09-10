---
dossier-header: internal-v1
title: Reliability, Performance, and Observability
purpose: Establishes what can fail for an installer and how anyone would find out, given that the project runs nothing itself.
audience: Reviewer, Maintainer, Installing operator
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: d3fc744
last-verified: 2026-09-10
review-trigger: The project acquires a runtime, a hosted service, or any telemetry; a new failure mode is reported by an operator
related: [02-architecture/system-architecture.md, 02-architecture/infrastructure-and-deployment.md, 04-operating/operations-and-incident-response.md, 00-control/evidence-ledger.md]
---
# Reliability, Performance, and Observability
<!-- contract: references/package-contract-03-assurance.md#reliability-performance-and-observability -->

Most of the runtime half of this document is `N/A`, and the reason is architectural rather than an omission: **the project operates no service** [EV-0044]. There is no uptime to measure, no latency budget, no error rate, and no capacity model, because nothing runs that could exhibit them.

Two things remain in scope. First, the project has distribution and delivery failure modes rather than runtime ones. They land on installers. Second, observability splits in two.

**The delivery path is now observed and measurable**. Five workflows are tracked [EV-0123]. Every Actions run across the merged range was green on `ubuntu-latest` [EV-0126]. Three CodeQL analyses report zero results against zero open alerts [EV-0140].

**The product in use is observed by nothing at all**. There is no install signal and no usage signal. The only error report is a human filing an issue [EV-0044].

The Actions, CodeQL and manifest-check reads in this document were obtained outside this engagement's action ceiling, which sets `networkAccess` false (AQ-0012). They are recorded evidence rather than agent-collected observation.

## Critical user journeys

| Journey | Actor | Why it is critical | Components involved | Dependencies | Evidence |
|---|---|---|---|---|---|
| Add the marketplace and install a plugin | Operator | The only path into the product. If it fails, nothing else exists | `marketplace.json`, the plugin tree, the Claude Code plugin client | GitHub, the client | [EV-0051] observed 2026-07-26, [EV-0181] |
| Receive an update | Operator | `autoUpdate` was `true` on the one observed profile, so this happens without the operator acting | `main`, the client's sync | GitHub, the client | [EV-0051] observed 2026-07-26 |
| Invoke a command | Operator | The visible product surface: flow ships 23 commands and dossier 9, across six in-tree plugins | Command file, its declared skills, any `bin/` scripts | The client, `jq`, sometimes `gh` | [EV-0162], [EV-0175] |
| A hook fires | Operator, passively | Executes on the operator's machine with their privileges, at points they did not choose. flow registers 14 hook scripts and dossier 5 | `hooks.json`, a hook script | The client, bash | [EV-0129], [EV-0166] |
| Cut a release | Maintainer | Produces the tags and desktop artifacts installers and Desktop users consume. 63 tags exist; the two most recent releases published 2026-09-10 | Tag, GitHub release, packaging workflow | GitHub Actions | [EV-0177], [EV-0066] |

## Objectives

| Journey or service | Dimension | Objective | Window | Approved in | Evidence |
|---|---|---|---|---|---|
| N/A | availability, latency, throughput, durability, freshness, correctness | **No objective exists on any of these six dimensions for anything in this project** | — | — | There is no service to set an objective for, and no measurement that could evaluate one [EV-0044] |

Stating "no objectives" is the accurate answer here rather than a gap to be filled. An objective for a git repository would be an objective about GitHub, which this project neither controls nor could report on.

## Indicators, objectives, agreements, and error budgets

| Service | SLI (what is measured, and how) | SLO (internal objective) | SLA (contractual commitment) | Error budget | Budget consumed | Evidence |
|---|---|---|---|---|---|---|
| N/A — the project operates no service | nothing is measured | none | **none — no contract exists with anyone** | N/A | N/A | [EV-0044] |

The delivery-path figures in the next section are measurements of CI, not indicators against any objective. Nothing in this project converts them into a target, and no summary here should be read as one.

## Measured performance

| Metric | Value | Window | Environment | Measurement source | Observed | Evidence |
|---|---|---|---|---|---|---|
| flow test suite result | 2336 passing assertions, 0 failures, exit 0 | per run | macOS 25.6 arm64, `/bin/bash` 3.2.57 | `plugins/flow/tests/run.sh` (CHK-51) | 2026-09-10 | [EV-0098] |
| dossier test suite result | 1951 passing assertions, 0 failures, exit 0 | per run | macOS 25.6 arm64, `/bin/bash` 3.2.57 | `plugins/dossier/tests/run.sh` (CHK-54) | 2026-09-10 | [EV-0107] |
| Both suites on Linux | green for every merge commit in the range | per run | GitHub-hosted `ubuntu-latest` | Actions run history (CHK-68) | 2026-09-10 | [EV-0126] |
| Manifest version check result | 8 plugins checked, 0 failed, 0 unverifiable, exit 0 | per run | local clone plus `gh api` | `scripts/check-plugin-versions.sh` (CHK-69) | 2026-09-10 | [EV-0127] |
| CodeQL analysis result | 3 analyses uploaded, `results_count` 0 each, 0 open alerts | per merge commit | `ubuntu-latest`, matrix `actions` and `python` | GitHub code-scanning API (CHK-80) | 2026-09-10 | [EV-0140], [EV-0134] |
| Wall-clock runtime of either suite | **Unknown: no ledger row records a runtime for `flow/tests/run.sh` or `dossier/tests/run.sh`** | — | — | — | — | — |
| Test coverage of either suite | **Unknown: no ledger row records a coverage measurement, and no coverage tool appears in either suite's evidence** | — | — | — | — | assertion counts [EV-0098], [EV-0107] are not coverage |
| Install latency | **not measured** | — | — | — | — | [EV-0044] |
| Hook execution latency | **not measured.** A non-zero hook exit does refuse the operator's Bash call: three refusals were observed on one machine during this refresh | — | macOS 25.6, installed flow 3.3.0 | session tool results (CHK-101) | 2026-09-10 | [EV-0172] |
| Skill context cost | **not measured** | — | — | — | — | [EV-0044] |

| Assumption | Value | Basis | Verified | Evidence |
|---|---|---|---|---|
| Hooks are fast enough not to be noticed | assumed | Local shell doing filesystem and text inspection, with no network calls | **no** | [EV-0129] |
| Loading a skill costs acceptable context | assumed | Skills load on demand rather than eagerly | **no** | [EV-0044] |
| CI duration stays inside the free-tier budget for a public repository | assumed | Every run in the range completed and reported success | **no — duration was never read** | [EV-0126] |

Three performance assumptions, none measured. Assertion counts and pass rates say the suites are correct, not that they are fast or complete. Coverage and runtime are both unmeasured, and neither is inferable from the other figures in this table.

## Capacity model and tested limits

| Dimension | Modelled limit | Tested limit | Test method | Test date | Headroom at current load | Evidence |
|---|---|---|---|---|---|---|
| Concurrent installers | none — a git read scales on GitHub's side | not tested | — | — | effectively unbounded | [EV-0043, I] |
| Actions minutes | free-tier for a public repository | not tested | — | — | unquantified. 5 workflows are tracked; the manifest check is path- and cron-filtered and the desktop packaging runs only on release publication | [EV-0123], [EV-0081], [EV-0133] |
| Skills loadable in one session | unmodelled | not tested | — | — | unknown | [EV-0044] |
| Plugins one maintainer can keep correct | 8 published entries | **exceeded in practice** — see the four current instances below | observation across this refresh | 2026-09-10 | none | [EV-0181], [EV-0144], [EV-0173], [EV-0164], [EV-0139] |

The maintainer row is the only real capacity finding in the project, and every other dimension has large headroom. The finding is unchanged from the July baseline. The evidence for it is entirely new, because the July examples were fixed [EV-0170], [EV-0171], [EV-0058]. Four current instances:

- Both published releases shipped with a known macOS defect. v4.9.0 and v4.10.0 were published at 07:18Z and 07:48Z, and the fix merged at 10:39Z the same day [EV-0144].

- A shipped hook produced three false refusals in one session. It matches raw command text rather than parsed shell grammar [EV-0172], [EV-0173], AQ-0026.

- The flow test suite leaked two branches carrying three commits into the repository it was run in [EV-0164].

- `.claude/settings.dossier.json` pinned `expectedPluginVersion` at 1.0.0 while the plugin read 1.2.0, two minor versions apart, with no check noticing [EV-0139].

## Resilience mechanisms

| Mechanism | Where | Configuration | Behaviour on trip | Tested | Evidence |
|---|---|---|---|---|---|
| Timeouts | none in this project's own code | — | — | no | [EV-0044] |
| Retries | none | — | — | no | [EV-0044] |
| Backpressure | N/A — no request path exists | — | — | — | [EV-0044] |
| Privilege split in the refresh template | `templates/ci/dossier-docs-refresh.yml` | A `scan` job separate from the `policy` job | Scanning cannot borrow the policy job's permissions | structurally, in the dossier suite | [EV-0075] |
| Fail-visible on a failed lookup | `dossier-policy.sh` and the same template | `existing_pr_lookup_failed` | Reports "unknown (lookup failed)" instead of "no pull request", and the guard sits before the branch-recreate fallback | yes, by executed test (CHK-87, CHK-88) | [EV-0155], [EV-0156] |
| Rotation telemetry | The same template | Seven `rotation_*` job outputs, each asserted by `workflow-template.test.sh` | Reports rotation intent rather than acting silently | structurally | [EV-0157] |
| Guarded temp-directory allocation | `plugins/dossier/tests/lib/assert.sh` | `_dossier_require_mktemp_dir` | Aborts the test process with exit 2 instead of continuing in the wrong directory | yes — 14 of 14 assertions (CHK-85) | [EV-0145], [EV-0147] |
| Circuit breaker | dossier's CI refresh template | **Unknown: the July draft recorded a cap of 6 documentation pull requests per 24 hours at `ci.circuitBreaker.maxDocPrsPer24h`, citing rows since superseded. No 2026-09-10 row re-checks the setting or its value** | unknown | not re-checked | — |
| Queue | dossier's CI refresh template | **Unknown: the July draft recorded an Actions `concurrency` group with `cancel-in-progress: false`, citing rows since superseded. No 2026-09-10 row re-checks it** | unknown | not re-checked | — |
| Caches | The Claude Code client's plugin cache, not this project's | client-controlled | client-controlled | no | [EV-0052] observed 2026-07-26 |

The first three template mechanisms belong to a workflow that has never executed end to end in any repository (AQ-0002). No dossier docs-refresh workflow is installed here [EV-0123]. They are tested as structure and as unit behaviour, never as a running pipeline.

## Observability

| Signal | Coverage | Where it lands | Retention | Gaps | Evidence |
|---|---|---|---|---|---|
| Logs | **none from the product** — nothing runs to log | — | — | total for the product | [EV-0044] |
| Metrics | **none** | — | — | total | [EV-0044] |
| Traces | **none** | — | — | total | [EV-0044] |
| CI results | 5 workflows; every run across the merged range succeeded on `ubuntu-latest` | GitHub Actions | GitHub's retention | Advisory only — no required status check exists [EV-0131] | [EV-0123], [EV-0126] |
| Static analysis | CodeQL over `actions` and `python` only. The 37 `bin/` shell scripts and every hook script sit outside both configured languages. The 3 Python files under `plugins/flow/bin/` are inside `python` | GitHub code scanning | GitHub's retention | shellcheck covers dossier's `bin/` and hook scripts and nothing else, so flow's 17 `bin/` and 14 hook scripts are unlinted (AQ-0019) | [EV-0134], [EV-0175], [EV-0176], [EV-0165] |
| Manifest checking | `check-plugin-versions.sh` runs on manifest-touching pushes and pull requests, on a weekly Monday cron, and on dispatch | GitHub Actions | GitHub's retention | Compares advertised versions and requires a `sha`; whether a malformed or unresolvable entry is caught before publication is not established (AQ-0020) | [EV-0080], [EV-0081], [EV-0127] |
| Business signals | **none.** No install count, no usage count, no active-operator count. GitHub exposes none for plugin marketplaces and the plugins emit none by design | — | — | total (AQ-0004) | [EV-0044] |

The split is the point. Everything the project *builds* is now observed on every merge, and nothing the project *ships to an operator* is observed at all. A green pipeline says the tree is consistent, and says nothing about whether any install works.

## Dashboards, alerts, and escalation

| Alert | Condition | Threshold basis | Fires to | Runbook | False-positive history | Evidence |
|---|---|---|---|---|---|---|
| CI failure notification | Any of the 5 workflow runs fails | GitHub default, not tuned | The maintainer's GitHub notifications | none | not tracked | [EV-0123] |
| CodeQL alert | A finding in `actions` or `python` | CodeQL default query suite, `build-mode: none` | GitHub Security tab | none | 0 alerts have ever been open; 3 analyses report 0 results | [EV-0134], [EV-0140] |
| Weekly manifest check | Version drift between an entry and its source, or a missing `sha` | Exact match, defined by the script | The maintainer's GitHub notifications | none | not tracked | [EV-0081] |
| **No other alert exists** | — | — | — | — | — | [EV-0044] |

| Dashboard | Answers | Owner | Evidence |
|---|---|---|---|
| GitHub Actions run history | Did CI pass for this commit | Daniel Bentes | [EV-0126] |
| GitHub code scanning | Does CodeQL hold an open finding | Daniel Bentes | [EV-0140] |
| **No dashboard answers "is the product working for anyone"** | — | — | [EV-0044] |

Every alert above fires to one person's notifications, with no second recipient and no escalation path.

## Failure and recovery scenarios

| Scenario | Expected behaviour | Detection | Recovery | Data loss window | Exercised | Evidence |
|---|---|---|---|---|---|---|
| Dependency failure — GitHub is unavailable | No installs, no updates, no CI. Already-installed plugins keep working | GitHub status page | wait | none | no | [EV-0043, I], [EV-0051] |
| Dependency failure — the Claude Code client changes its plugin contract | Plugins may fail to resolve or load | An operator reports it | Adapt the manifest or the plugins | none | no | [EV-0043, I], AQ-0023 |
| Regional failure | N/A — no infrastructure is operated | — | — | — | — | [EV-0044] |
| Data corruption | N/A — no data store. A corrupted commit is a git-level event, recoverable from any clone | git | `git revert` or re-clone | none | no | [EV-0044] |
| Partial failure and retry storm | N/A — no retries, no queues, no concurrent writers | — | — | — | — | [EV-0044] |
| **A defective plugin reaches a published release** | Installers receive the defect until the next release | **none automated** — nothing compares a release tag against fixes merged after it | Publish a new release | none | **it happened in this range**: both published releases carry defects fixed three hours later | [EV-0144] |
| **A hook refuses legitimate operator work** | The operator's tool call is blocked on their own machine | The operator sees the refusal | Fix the matcher, or the operator works around it | none | **observed three times in one session** | [EV-0172], [EV-0173], AQ-0026 |
| **A malformed or unresolvable manifest entry reaches `main`** | Affected plugins become undiscoverable | The weekly and per-push version check catches version drift and a missing `sha`; whether it catches malformed or unresolvable entries is not established (AQ-0020) | Fix and push; installers re-sync | none | no | [EV-0080], [EV-0081], [EV-0127] |
| A pinned external source is unavailable or moves | Both external entries pin a sha rather than a branch [EV-0058]. Inferred: a moving upstream `main` therefore cannot change what installers resolve, which assumes the client honours the pin (AQ-0003) | The version check reports an unverifiable entry | Re-pin | none | no | [EV-0058], [EV-0127] |
| Windows operator installs | Shell scripts fail | The operator reports it — two did | Fix the scripts, or document non-support | none | no | [EV-0049] observed 2026-07-26, AQ-0008 |

Both bolded rows that actually occurred share one property with the rest. Detection is a human noticing. No automated signal linked the release tags to the later fix. No automated signal reported the hook refusals.

## Test evidence

| Test type | Last run | Scope | Environment | Result | Artifact | Evidence |
|---|---|---|---|---|---|---|
| Chaos | not executed | — | — | — | — | [EV-0044] |
| Load | not executed | — | — | — | — | [EV-0044] |
| Soak | not executed | — | — | — | — | [EV-0044] |
| Failover | not executed | — | — | — | — | There is nothing to fail over to [EV-0044] |
| Backup | not executed | — | — | — | — | No backup policy exists; git clones are redundancy, not backup [EV-0044] |
| Recovery of a bad commit already propagated to installers | not executed | — | — | — | no ledger row records such a rehearsal | — |
| Structural and script | 2026-09-10 | flow and dossier | macOS 25.6 arm64, `/bin/bash` 3.2.57, and `ubuntu-latest` | 2336 and 1951 assertions, 0 failures; green on Linux for every merge commit in the range | `TOTAL pass=… fail=0` (CHK-51, CHK-54, CHK-68) | [EV-0098], [EV-0107], [EV-0126] |
| Hook and guard behaviour | 2026-09-10 | dossier hooks and the mktemp guard | macOS 25.6, `/bin/bash` 3.2.57 | 119 and 14 assertions, 0 failures | CHK-85, CHK-86 | [EV-0147], [EV-0149] |
| End-to-end refresh pipeline | never | dossier's post-merge automation | — | — | — | AQ-0002, [EV-0123] |

Two flakiness findings are carried forward from the July baseline and were **not** re-checked in this refresh. Observed 2026-07-26: one run of the flow suite failed 4 assertions in `flow-goal-stop.test.sh`, then 10 consecutive runs passed [EV-0055]. Observed 2026-07-26: both suites leaked temp directories on every run, roughly 254 for flow and 81 for dossier [EV-0056]. The cause is that a sourced test file's `EXIT` trap replaces the previous file's. The same check recorded 0 leaked directories for dossier after a same-day fix (CHK-32). flow's leak has no later row, so it cannot be reported as fixed.

## Blind spots and operational risks

| Blind spot | What would go undetected | How long | Consequence | Proposed remedy | Owner |
|---|---|---|---|---|---|
| Nothing links a release to fixes merged after it | That a published release carries a defect already fixed on `main` | Until the next release | Both current releases ship a known macOS defect [EV-0144] | Recommendation: compare each release tag against `main` at publication, and re-cut when a fix is newer | Daniel Bentes |
| No resolvability check on the manifest | A malformed or unresolvable `marketplace.json` entry, which the version check is not established to catch (AQ-0020) | Until an operator reports it — unbounded | Affected plugins undiscoverable, with the maintainer unaware | Recommendation: extend the existing weekly job to parse the manifest and resolve every source, not only compare versions | Daniel Bentes |
| No install or usage signal | That nobody uses the product, or that everybody's install is broken | indefinitely | Every quality decision is made without knowing whether it matters (AQ-0004) | Recommendation: accept it as unmeasurable, and stop treating artifact quality as a proxy for operator outcome | Daniel Bentes |
| flow's shell is unlinted, and `block-destructive.sh` matches text rather than grammar | A hook that blocks the wrong thing, as three refusals in this refresh already did [EV-0173] | Until an operator is blocked or unprotected | flow's 17 `bin/` and 14 hook scripts run on operator machines with no static analysis [EV-0165], AQ-0019 | Recommendation: extend the shellcheck step to flow, and parse shell grammar in `block-destructive.sh` (AQ-0026) | Daniel Bentes |
| Advisory CI | A merge that breaks every installer | Immediately propagated, detected only by report | 4287 assertions are information, not enforcement — `main` carries no branch protection and no rulesets [EV-0131] | Recommendation: require both test workflows and the manifest check in branch protection | Daniel Bentes |
| No coverage measurement | Which code paths the 4287 assertions never touch | indefinitely | Suite growth is measured in assertions, which cannot show a gap | Recommendation: measure coverage for both shell suites once, and record the figure | Daniel Bentes |
| No Windows environment | Every Windows-specific defect | Until an operator reports it — two already have [EV-0049] | An unknown share of operators cannot use the plugins (AQ-0008) | Recommendation: add a `windows-latest` matrix leg | Daniel Bentes |
| The dossier refresh has never run end to end | Whether the plugin's headline capability works at all | Until someone runs it | A published plugin whose central claim is unverified (AQ-0002), and no docs-refresh workflow is installed here [EV-0123] | Recommendation: perform one end-to-end run in a scratch repository | Daniel Bentes |

Every remedy above is a workflow, a job, or a setting. The pattern is not that hard problems are unsolved. It is that the delivery path is now well observed while the operator's experience of the product is observed by nothing.
