---
dossier-header: internal-v1
title: Operations and Incident Response
purpose: States what happens when something this project ships breaks on someone else's machine, and who would know.
audience: Maintainer, Reviewer, Installing operator
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: fd884b2
last-verified: 2026-07-26
review-trigger: The project acquires a runtime or a service; a security disclosure channel is established; an incident occurs
related: [02-architecture/infrastructure-and-deployment.md, 03-assurance/reliability-performance-and-observability.md, 03-assurance/security-privacy-and-compliance.md]
---
# Operations and Incident Response
<!-- contract: references/package-contract-04-operating.md#operations-and-incident-response -->

This project operates nothing. There is no service, no on-call rotation, no incident process, and no status page [EV-0044]. Most of the sections below are therefore `N/A`, and that is the accurate answer rather than a gap.

What is **not** `N/A`, and what this document is really about: the project ships shell scripts that execute on other people's machines [EV-0040], and it has no way to detect, contain, or communicate when one of them goes wrong. The distinction matters. "Nothing to operate" is a property of the architecture; "no way to tell anyone when the thing we shipped breaks them" is a gap.

## Operational scope and responsibility

| Function | Responsible | Accountable | Hours | Escalation | Evidence |
|---|---|---|---|---|---|
| Repository availability | GitHub | GitHub | GitHub's | none | [EV-0051] |
| Manifest correctness | Daniel Bentes | Daniel Bentes | none stated | **none — no second person exists** | [EV-0026], [EV-0035] |
| Plugin correctness | Daniel Bentes | Daniel Bentes | none stated | none | [EV-0035] |
| CI | Daniel Bentes | Daniel Bentes | none stated | none | [EV-0012] |
| Release | Daniel Bentes | Daniel Bentes | none stated | none | [EV-0032] |
| Security disclosure intake | **unassigned** | Daniel Bentes by default | none | **no channel exists** | [EV-0036] |
| Operator-side execution | The operator | The operator | theirs | theirs | [EV-0040] |

## Service and dependency inventory

| Service or dependency | Criticality | Owner | Failure impact | Recovery path | Evidence |
|---|---|---|---|---|---|
| GitHub | critical | GitHub | No installs, no updates, no CI, no releases. Already-installed plugins keep working | wait | [EV-0051] |
| Claude Code client | critical | Anthropic | Nothing in this project functions | none available to this project | [EV-0043] |
| `synaptiai/prompt-decorators` `main` | high, for one plugin | Daniel Bentes | Installers of that plugin receive whatever is there, with no signal here | pin the ref to a tag | [EV-0030] |
| `agent-capability-standard` submodule | medium | Daniel Bentes | The pinned tree is what ships, 2 commits past the advertised tag | move the pointer | [EV-0031] |
| `actions/checkout@v4`, `github/codeql-action@v3` | medium | third party | CI cannot run; merges are unaffected because CI is advisory | pin to SHAs | [EV-0042] |
| `pyyaml>=6.0` | low | PyPI | One plugin's runtime; one optional test leg degrades with a stated skip | vendor or pin | [EV-0041] |

## Standard procedures

| Procedure | Command or runbook | Preconditions | Blast radius | Authorization | Rollback | Verification | Last executed |
|---|---|---|---|---|---|---|---|
| Deploy | `git push origin main` | none enforced | **Every installer, on their next client sync** | none required | `git revert` and push | Both suites run afterwards, advisory | 2026-07-25 [EV-0034] |
| Rollback | `git revert <sha>` then push | none | Every installer, eventually | none required | — | Both suites | never recorded |
| Restart | N/A — nothing runs | — | — | — | — | — | — |
| Failover | N/A — nothing to fail over to | — | — | — | — | — | — |
| Backup | N/A — no formal backup. Every clone is a full copy | — | — | — | — | — | never |
| Restore | `git clone`, or reset from any existing clone | a surviving clone | — | none | — | **never tested** | never |
| Scale | N/A | — | — | — | — | — | — |
| Maintenance | N/A — no maintenance window is meaningful | — | — | — | — | — | — |

The deploy row is the operational summary of this project: an unauthorized, unverified, unreversible-in-practice action with a blast radius of every installer's machine, requiring one keystroke [EV-0016], [EV-0017].

## Alert triage

| Alert | First check | Second check | Escalate when | Runbook |
|---|---|---|---|---|
| CI workflow failure | The Actions run log | Reproduce with `tests/run.sh` locally | never — there is nobody to escalate to | none exists |
| CodeQL finding | GitHub Security tab | Read the flagged workflow or Python file | never | none exists |
| **No other alert exists** | — | — | — | — |

| Question | Where to look | Command or query | Access required |
|---|---|---|---|
| Is it up? | N/A — nothing runs. The nearest question is "does the manifest resolve", which **nothing checks** | `jq '.plugins \| length' .claude-plugin/marketplace.json` | public read |
| Is it slow? | N/A | — | — |
| Is it erroring? | GitHub issues — the only channel through which a failure becomes visible | `gh issue list --state open` | public read |
| Which change caused it? | git history | `git log --oneline` | public read |
| Is data affected? | N/A — no data exists | — | — |

Three of five triage questions are `N/A` and one has no mechanism. The only working answer to "is something broken" is: someone filed an issue. Two operators have [EV-0049].

## Runbook catalog

| Failure mode | Runbook | Owner | Last exercised | Exercise result | Evidence |
|---|---|---|---|---|---|
| Malformed manifest reaches `main` | **none** | Daniel Bentes | never | — | [EV-0026] |
| A broken hook reaches `main` | **none** | Daniel Bentes | never | — | [EV-0040] |
| A credential is committed | Partially: flow's `block-secrets.sh` prevents it during an active session. No rotation or purge runbook exists | Daniel Bentes | never | — | [EV-0037], [EV-0038] |
| Upstream `prompt-decorators` breaks | **none** | Daniel Bentes | never | — | [EV-0030] |
| Windows operator cannot run the plugins | **none** — two issues open without resolution | Daniel Bentes | never | — | [EV-0049] |
| A vulnerability is reported | **none, and no intake channel exists** | unassigned | never | — | [EV-0036] |

Six identified failure modes, zero runbooks, zero exercises.

## Incident management

| Severity | Definition | Declaration authority | Response time | Communication cadence | Evidence |
|---|---|---|---|---|---|
| **No severity scale is defined** | — | — | — | — | No incident process exists in the repository [EV-0036] |

| Phase | Actions | Roles | Artifacts produced |
|---|---|---|---|
| Detection | An operator files a GitHub issue. There is no other detection path | operator | the issue |
| Declaration | Not defined | — | — |
| Command | Not defined. One person would do everything | Daniel Bentes | — |
| Mitigation | Revert and push. Propagation to installers is on the client's schedule, which this project does not control | Daniel Bentes | a commit |
| Recovery | The same push | Daniel Bentes | — |
| Closure | Close the issue | Daniel Bentes | the issue thread |
| Post-incident review | Not defined. The `.decisions/` journal holds 11 records, none of which is an incident review | — | — |

## Security and privacy incidents

| Aspect | Procedure | Differs from standard incident how | Owner | Evidence |
|---|---|---|---|---|
| Detection and triage | Public GitHub issue, or nothing | It cannot differ — there is no standard incident process to differ from | unassigned | [EV-0036] |
| Containment | Revert and push. **The bad version remains installed on every machine that synced it, and this project cannot tell how many that is** | — | Daniel Bentes | [EV-0051], AQ-0004 |
| Evidence preservation | git history and Actions logs. Note that `main` has no force-push protection, so history is rewritable | — | Daniel Bentes | [EV-0016] |
| Notification decision | Not defined. **There is no channel to notify installers through** | — | unassigned | AQ-0004 |
| External reporting | Not defined. No regulatory obligation attaches — the project processes no personal data | — | unassigned | [EV-0044] |

The containment row is the most serious operational finding in this package. If a malicious or destructive hook reached `main`, the project could revert it in seconds and would then have **no way to reach the operators already running it, and no way to count them.**

## Communication boundaries

| Audience | Who may communicate | What may be said | What must not be said | Approval |
|---|---|---|---|---|
| Customers | N/A — no customers, no contracts, no accounts | — | — | — |
| Partners | N/A | — | — | — |
| Regulators | N/A — no regulatory obligation attaches | — | — | — |
| Public | Daniel Bentes | Anything already in the public repository | Nothing is restricted — the disclosure policy for this project is `public` and every fact in this package is independently checkable | Daniel Bentes, per the claim register |

## Notification obligations

| Obligation | Source | Trigger | Deadline | Owner | Evidence |
|---|---|---|---|---|---|
| **none** | — | — | — | — | No contract, no regulated data, no personal data processing [EV-0044] |

The absence of a *legal* obligation is worth separating from the absence of an *ethical* one. Nothing requires this project to notify installers that a bad version reached their machines; nothing enables it either.

## Status, review, and learning

| Mechanism | Where | Owner | Cadence | Evidence |
|---|---|---|---|---|
| Status communication | **none.** No status page, no announcement channel, no release notes beyond tags and CHANGELOGs | — | — | [EV-0032] |
| Post-incident review | **none defined** | — | — | [EV-0036] |
| Action tracking | GitHub issues — 2 open, both Windows portability, neither resolved | Daniel Bentes | none | [EV-0049] |
| Recurrence check | **none** | — | — | [EV-0036] |
| Decision journalling | `.decisions/` — 11 records, produced by the flow plugin during development | Daniel Bentes | per issue worked | [EV-0046] |

The last row is the one genuine learning mechanism the project has, and it is a byproduct of using its own plugin.

## Business continuity and disaster recovery

| Scenario | Continuity plan | Recovery objective | Last exercised | Result | Evidence |
|---|---|---|---|---|---|
| GitHub becomes unavailable | Wait. Every clone is a full copy, so nothing is lost — but nothing can be published either | none stated | never | — | [EV-0051] |
| The repository is deleted or lost | Re-push from any clone. **GitHub-side state — settings, secrets, release assets — is in no clone** | none stated | never | — | [EV-0034] |
| The maintainer becomes unavailable | **No plan.** No backup owner, no second identity with write access, no succession path. 8 published plugins would freeze | none | never | — | [EV-0035] |
| The Claude Code plugin contract changes | Adapt the manifest and the plugins. No advance notice mechanism exists | none stated | never | — | [EV-0043] |

The third row is the project's real continuity risk. It is not a technical problem and it has a cheap partial mitigation: naming a second maintainer, or stating plainly in the README that the project is single-maintainer so installers can weigh it themselves.

## Manual operations and unsafe gaps

| Operation | Why it is manual | Who can do it | Risk if done wrong | Reversible | Proposed remedy |
|---|---|---|---|---|---|
| Version bump across `plugin.json` and `marketplace.json` | Two files, no enforcement | Daniel Bentes | An operator installs a version different from the one advertised | yes | Extend dossier's own version-drift check to all 8 entries |
| Tagging a release to match `metadata.version` | Manual, unverified | Daniel Bentes | The manifest advertises a release that does not exist — true right now at 4.7.0 | yes | Same CI step |
| Updating the README when a plugin changes | Manual, unverified | Daniel Bentes | **Already failed four times** | yes | A CI step comparing README facts to the manifest |
| Moving the submodule pointer to a tagged commit | Manual, unverified | Daniel Bentes | **Already drifted** — 2 commits past `v1.2.0` | yes | Assert `git describe --exact-match` on the pointer |
| Repository settings — protection, rulesets, secrets | GitHub UI, in no file | Daniel Bentes | The entire access model can change with no commit and no review | yes | Record intended settings in the repository and check them in CI |
| Pushing to `main` | No gate exists | anyone with write access | Every installer receives it | by revert only | Enable branch protection with both suites required |

Six manual operations, of which three have already failed at least once and two are failing right now. Every proposed remedy is one CI step or one settings change.
