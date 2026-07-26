---
dossier-header: internal-v1
title: Reliability, Performance, and Observability
purpose: Establishes what can fail for an installer and how anyone would find out, given that the project runs nothing itself.
audience: Reviewer, Maintainer, Installing operator
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
last-verified: 2026-07-26
review-trigger: The project acquires a runtime, a hosted service, or any telemetry; a new failure mode is reported by an operator
related: [02-architecture/system-architecture.md, 02-architecture/infrastructure-and-deployment.md, 04-operating/operations-and-incident-response.md, 00-control/evidence-ledger.md]
---
# Reliability, Performance, and Observability
<!-- contract: references/package-contract-03-assurance.md#reliability-performance-and-observability -->

Most of this document is `N/A`, and the reason is architectural rather than an omission: **the project operates no service** [EV-0044]. There is no uptime to measure, no latency budget, no error rate, and no capacity model, because nothing runs that could exhibit them.

Two things remain genuinely in scope, and they are what this document is about. First, the project *does* have failure modes — they are just distribution failure modes rather than runtime ones, and they land on installers. Second, it has **no observability of any kind**, so every one of those failures is invisible to the maintainer until a human reports it [EV-0044], [EV-0049].

## Critical user journeys

| Journey | Actor | Why it is critical | Components involved | Dependencies | Evidence |
|---|---|---|---|---|---|
| Add the marketplace and install a plugin | Operator | The only path into the product. If it fails, nothing else exists | `marketplace.json`, the plugin tree, the Claude Code client | GitHub, the client | [EV-0051], [EV-0052] |
| Receive an update | Operator | `autoUpdate` is `true` on the observed profile, so this happens without the operator acting | `main`, the client's sync | GitHub, the client | [EV-0051] |
| Invoke a command | Operator | The visible product surface — 61 commands | Command file, its declared skills, any `bin/` scripts | The client, `jq`, sometimes `gh` | [EV-0005], [EV-0007] |
| A hook fires | Operator, passively | Executes on the operator's machine with their privileges, at points they did not choose. The highest-consequence journey and the least visible | `hooks.json`, a hook script | The client, bash | [EV-0040] |
| Cut a release | Maintainer | Produces the tags and desktop artifacts installers and Desktop users consume | Tag, GitHub release, packaging workflow | GitHub Actions | [EV-0032] |

## Objectives

| Journey or service | Dimension | Objective | Window | Approved in | Evidence |
|---|---|---|---|---|---|
| N/A | — | **No availability, latency, or error-rate objective exists for anything in this project** | — | — | There is no service to set an objective for, and no measurement that could evaluate one [EV-0044] |

Stating "no objectives" is the accurate answer here rather than a gap to be filled. An SLO for a git repository would be an objective about GitHub, which this project neither controls nor could report on.

## Indicators, objectives, agreements, and error budgets

| Service | SLI (what is measured, and how) | SLO (internal objective) | SLA (contractual commitment) | Error budget | Budget consumed | Evidence |
|---|---|---|---|---|---|---|
| N/A | nothing is measured | none | **none — no contract exists with anyone** | N/A | N/A | [EV-0044] |

## Measured performance

| Metric | Value | Window | Environment | Measurement source | Observed | Evidence |
|---|---|---|---|---|---|---|
| flow test suite runtime | seconds | per run | macOS 25.5 and ubuntu-latest | `tests/run.sh` | 2026-07-26 | [EV-0008] |
| dossier test suite runtime | seconds | per run | same | `tests/run.sh` | 2026-07-26 | [EV-0009] |
| CodeQL analysis | 38s (`actions`), 49s (`python`) | per run | ubuntu-latest | Actions run log | 2026-07-25 | [EV-0012] |
| Repository size | ~3.0 MB, 572 tracked files | live | GitHub | GitHub API | 2026-07-26 | [EV-0034] |
| Install latency | **not measured** | — | — | — | — | [EV-0052] |
| Hook execution latency | **not measured** — and `PreToolUse` hooks block the operator's tool call while they run | — | — | — | — | [EV-0040] |
| Skill context cost | **not measured** | — | — | — | — | [EV-0004] |

| Assumption | Value | Basis | Verified | Evidence |
|---|---|---|---|---|
| Hooks are fast enough not to be noticed | assumed | They are local shell doing filesystem and text inspection, with no network calls | **no** | [EV-0040] |
| Loading a skill costs acceptable context | assumed | Skills load on demand rather than eagerly | **no** | [EV-0004] |
| A clone of ~3.0 MB installs quickly | assumed | Size measured; install time never timed | partially | [EV-0034] |

Three performance assumptions, none verified. They are all plausible, and none has been measured — which is worth stating plainly rather than presenting the plausibility as evidence.

## Capacity model and tested limits

| Dimension | Modelled limit | Tested limit | Test method | Test date | Headroom at current load | Evidence |
|---|---|---|---|---|---|---|
| Concurrent installers | none — git clone scales on GitHub's side | not tested | — | — | effectively unbounded | [EV-0043] |
| Repository size | GitHub's limits | not tested | — | — | large | [EV-0034] |
| Actions minutes | free-tier for a public repository | not tested | — | — | large; 4 path-filtered workflows | [EV-0012] |
| Skills loadable in one session | unmodelled | not tested | — | — | unknown | [EV-0004] |
| Maintainer capacity | 1 person | **exceeded in practice** — the README has drifted, a submodule pointer has drifted, and 5 plugins remain untested | observation | 2026-07-26 | none | [EV-0035], [EV-0022]–[EV-0025], [EV-0031] |

The maintainer row is the only real capacity finding in the project. Every other dimension has enormous headroom; that one has none, and its symptoms are already visible in the drift this assessment found.

## Resilience mechanisms

| Mechanism | Where | Configuration | Behaviour on trip | Tested | Evidence |
|---|---|---|---|---|---|
| Timeouts | none in this project's own code | — | — | no | [EV-0044] |
| Retries | none | — | — | no | [EV-0044] |
| Backpressure | N/A | — | — | — | [EV-0044] |
| Circuit breakers | dossier's CI template only: at most 6 documentation pull requests per 24 hours | `ci.circuitBreaker.maxDocPrsPer24h` | Refresh stops opening pull requests | structurally, in the dossier suite; **never at runtime** (AQ-0002) | [EV-0009], [EV-0045] |
| Queues | GitHub Actions `concurrency` group with `cancel-in-progress: false` in the dossier template | per template | Runs serialize instead of cancelling mid-agent | structurally | [EV-0009] |
| Caches | The Claude Code client's plugin cache — not this project's | client-controlled | client-controlled | no | [EV-0052] |
| Graceful degradation | `workflow-template.test.sh` records a pass with a stated reason when `pyyaml` is absent and continues structural checks | per test | Reduced coverage, explicitly reported rather than silent | yes — the skip path itself is the tested behaviour | [EV-0009] |

Only one resilience mechanism in this project has ever executed, and it is a test's own degradation path. The circuit breaker and the concurrency group belong to a workflow that has never run.

## Observability

| Signal | Coverage | Where it lands | Retention | Gaps | Evidence |
|---|---|---|---|---|---|
| Logs | **none** — nothing runs to log | — | — | total | [EV-0044] |
| Metrics | **none** | — | — | total | [EV-0044] |
| Traces | **none** | — | — | total | [EV-0044] |
| Events | GitHub events only: pushes, releases, Actions runs | GitHub | GitHub's retention | Covers the repository, not the product's use | [EV-0012] |
| Synthetic checks | **none.** No check verifies that the marketplace resolves, that a plugin installs, or that the manifest parses | — | — | total | [EV-0026] |
| Business signals | **none.** No install count, no usage count, no active-operator count. GitHub exposes none for plugin marketplaces and the plugins emit none by design | — | — | total (AQ-0004) | [EV-0044] |

Five of six signal classes are entirely absent, and for four of them that is correct — there is genuinely nothing to observe. **The synthetic-check row is the real gap**: a single scheduled job that parses the manifest and resolves each source would convert the project's largest blind spot into a detected failure, and nothing like it exists.

## Dashboards, alerts, and escalation

| Alert | Condition | Threshold basis | Fires to | Runbook | False-positive history | Evidence |
|---|---|---|---|---|---|---|
| CI failure notification | A workflow run fails | GitHub default | The maintainer's GitHub notifications | none | not tracked | [EV-0012] |
| CodeQL alert | A finding in `actions` or `python` | CodeQL default | GitHub Security tab | none | not tracked | [EV-0012] |
| **No other alert exists** | — | — | — | — | — | [EV-0044] |

| Dashboard | Answers | Owner | Evidence |
|---|---|---|---|
| GitHub Actions run history | Did CI pass | Daniel Bentes | [EV-0012] |
| GitHub Insights | Commit and contributor activity | Daniel Bentes | [EV-0034] |
| **No dashboard answers "is the product working for anyone"** | — | — | [EV-0044] |

## Failure and recovery scenarios

| Scenario | Expected behaviour | Detection | Recovery | Data loss window | Exercised | Evidence |
|---|---|---|---|---|---|---|
| Dependency failure — GitHub is unavailable | No installs, no updates, no CI. Already-installed plugins keep working | GitHub status page | wait | none | no | [EV-0051] |
| Dependency failure — the Claude Code client changes its plugin contract | Plugins may fail to resolve or load | An operator reports it | Adapt the manifest or the plugins | none | no | [EV-0043] |
| Regional failure | N/A — no infrastructure is operated | — | — | — | — | [EV-0044] |
| Data corruption | N/A — no data store. A corrupted commit is a git-level event, recoverable from any clone | git | `git revert` or re-clone | none | no | [EV-0034] |
| Partial failure and retry storm | N/A — no retries, no queues, no concurrent writers | — | — | — | — | [EV-0044] |
| **Malformed manifest reaches `main`** | All 8 plugins become undiscoverable at once | **none automated** — an operator would report it | Fix and push; installers re-sync | none | no | [EV-0026] |
| **A broken hook reaches `main`** | Every installer's session breaks or is blocked on the client's next sync | **none automated** — an operator would report it | Revert and push | none | no | [EV-0040], [EV-0051] |
| **Upstream `prompt-decorators` `main` breaks** | Installers of that plugin receive broken content, with no commit in this repository | **none** | Pin the ref, or wait for upstream | none | no | [EV-0030] |
| Windows operator installs | Shell scripts fail | The operator reports it — and two already have | Fix the scripts, or document non-support | none | no | [EV-0049] |

The three bolded rows are the project's real failure modes. All three share one property: **detection is a human noticing and choosing to file an issue.** The two open issues are the only evidence that this detection path works at all, and they establish that it works slowly.

## Test evidence

| Test type | Last run | Scope | Environment | Result | Artifact | Evidence |
|---|---|---|---|---|---|---|
| Chaos | never | — | — | — | — | [EV-0044] |
| Load | never | — | — | — | — | [EV-0044] |
| Soak | never | — | — | — | — | [EV-0044] |
| Failover | never | — | — | — | — | There is nothing to fail over to [EV-0044] |
| Backup | never | — | — | — | — | No backup policy exists; git clones are redundancy, not backup [EV-0044] |
| Recovery | never | — | — | — | — | [EV-0036] |
| Structural and script | 2026-07-26 | flow and dossier | macOS 25.5, bash | 1022 and 1241 assertions, 0 failures | `TOTAL pass=… fail=0` | [EV-0008], [EV-0009] |

Six of seven rows are `never`, and for five of them that is the correct answer for a project with no runtime. The exception is **recovery**: a documented, exercised procedure for "a bad commit reached every installer" would be meaningful here, and none exists.

## Blind spots and operational risks

| Blind spot | What would go undetected | How long | Consequence | Proposed remedy | Owner |
|---|---|---|---|---|---|
| No synthetic check on the manifest | A malformed or mis-resolving `marketplace.json` | Until an operator reports it — unbounded | All 8 plugins undiscoverable, with the maintainer unaware | One scheduled workflow: parse the manifest, resolve each source, compare each version to its `plugin.json` | Daniel Bentes |
| No install or usage signal | That nobody uses the product, or that everybody's install is broken | indefinitely | Every quality decision is made without knowing whether it matters (AQ-0004) | Accept it as unmeasurable, and stop treating artifact quality as a proxy for user outcome | Daniel Bentes |
| No behavioural test of any hook | A hook that no longer blocks what it claims to block | Until an operator is harmed by the thing it should have blocked | The security controls this project advertises are structurally verified, not behaviourally | One integration test per blocking hook | Daniel Bentes |
| Advisory CI | A merge that breaks every installer | Immediately propagated, detected only by report | The 2,263 assertions are information, not enforcement | Require both workflows in branch protection | Daniel Bentes |
| No Windows environment | Every Windows-specific defect | Until an operator reports it — two already have | An unknown share of operators cannot use the plugins | A `windows-latest` matrix leg | Daniel Bentes |
| The dossier refresh has never run | Whether the plugin's headline capability works at all | Until someone runs it | A published plugin whose central claim is unverified (AQ-0002) | One end-to-end run in a scratch repository | Daniel Bentes |

Every remedy above is small — one workflow, one job, one setting. The pattern is not that hard problems are unsolved; it is that cheap detection is absent everywhere, so the project learns about its failures from strangers.
