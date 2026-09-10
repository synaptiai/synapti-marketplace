---
dossier-header: internal-v1
title: Operations and Incident Response
purpose: States what happens when something this project ships breaks on someone else's machine, and who would know.
audience: Maintainer, Reviewer, Installing operator
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: The project acquires a runtime or a service, a security disclosure channel is established, or an incident occurs
related: [02-architecture/infrastructure-and-deployment.md, 03-assurance/reliability-performance-and-observability.md, 03-assurance/security-privacy-and-compliance.md]
---
# Operations and Incident Response
<!-- contract: references/package-contract-04-operating.md#operations-and-incident-response -->

This project operates nothing. There is no service, no on-call rotation, no incident process, and no status page [EV-0044, observed 2026-07-26]. Most of the sections below are therefore `N/A`, and that is the accurate answer rather than a gap.

What is **not** `N/A`: the project ships shell scripts that execute on other people's machines [EV-0162], [EV-0168]. Detection before release exists, but not in CI. A macOS defect in flow's runtime scripts was found by a local suite run under Apple's `/bin/bash` 3.2.57, and commit 16b4dc4 fixed it [EV-0144]. Inferred: no CI job runs on macOS, so the pipeline could not have found it — every observed Actions run is `ubuntu-latest` [EV-0126], AQ-0019.

What has no mechanism at all is the step after that. Both published releases still carry the pre-fix scripts, and this project cannot reach the operators running them [EV-0144].

Seven rows this document rests on were observed on 2026-07-26 and no 2026-09-10 row re-checks them: EV-0036, EV-0037, EV-0042, EV-0043, EV-0044, EV-0049 and EV-0051 (AQ-0022). Each is dated where it is cited.

## Operational scope and responsibility

| Function | Responsible | Accountable | Hours | Escalation | Evidence |
|---|---|---|---|---|---|
| Repository availability | GitHub | GitHub | GitHub's | none | [EV-0051], observed 2026-07-26 |
| Manifest correctness | Daniel Bentes | Daniel Bentes | none stated | **none — no second person exists** | [EV-0064], [EV-0127], [EV-0163] |
| Plugin correctness | Daniel Bentes | Daniel Bentes | none stated | none | [EV-0163] |
| CI | Daniel Bentes | Daniel Bentes | none stated | none | [EV-0123], [EV-0126] |
| Release | Daniel Bentes | Daniel Bentes | none stated | none | [EV-0066], [EV-0177] |
| Security disclosure intake | **unassigned** | Daniel Bentes by default | none | **no channel exists** | [EV-0036], observed 2026-07-26 |
| Operator-side execution | The operator | The operator | theirs | theirs | [EV-0162] |

One author identity carries all 214 commits on `main` [EV-0163]. Every escalation cell above is empty for that reason, not because a path was omitted.

## Service and dependency inventory

| Service or dependency | Criticality | Owner | Failure impact | Recovery path | Evidence |
|---|---|---|---|---|---|
| GitHub | critical | GitHub | No installs, no updates, no CI, no releases. Already-installed plugins keep working | wait | [EV-0051], observed 2026-07-26 |
| Claude Code client | critical | Anthropic | Nothing in this project functions | none available to this project | [EV-0043, I, observed 2026-07-26] |
| `prompt-decorators` `git-subdir` source at sha `9c792fe` | high, for one plugin | Daniel Bentes | Installers receive the pinned tree. Contents are unverified from this repository (AQ-0005) | move the pin | [EV-0058], [EV-0127] |
| `agent-capability-standard` `github` source at sha `9e2f65b` | medium | Daniel Bentes | The pinned upstream tree is what installs. It registers its own hooks, so it executes on the operator's machine | move the pin | [EV-0058], [EV-0127], [EV-0168] |
| `actions/checkout@v4`, `github/codeql-action@v3` | medium | third party | CI cannot run. Merges are unaffected because no check is required | pin to SHAs | [EV-0042], observed 2026-07-26 |
| `pyyaml` | high | PyPI | flow's journal, FlowRun state and FlowGoal machinery do not run without it [EV-0189]. `hooks/scripts/session-end-state.sh` reaches the requirement without the operator invoking anything, so a machine without it is affected before any command is typed [EV-0189]. No file in the repository declares it [EV-0186], [EV-0187] | `pip install --user pyyaml` on the operator's machine. Whether to declare, guard or remove the requirement is open (AQ-0032) | [EV-0186], [EV-0187], [EV-0189] |

The `agent-capability-standard` row was a git submodule until commit efb4f75. There is no `.gitmodules` in the tracked tree [EV-0059]. The leftover directory on the assessment machine is untracked and gitignored [EV-0060]. The manifest entry is a `github` source pinned to `9e2f65b` [EV-0058].

The commit records why: the gitlink resolved to zero entries in a plain clone, so the advertised plugin could not install [EV-0167]. The pinned tree reports the advertised version 1.2.0 [EV-0127]. Unknown: what separates that sha from the upstream tag `v1.2.0` is still unexamined (AQ-0006).

## Standard procedures

| Procedure | Command or runbook | Preconditions | Blast radius | Authorization | Rollback | Verification | Last executed |
|---|---|---|---|---|---|---|---|
| Deploy | `git push origin main` | none enforced | **Every installer, on their next client sync** | none required | `git revert` and push | Up to four CI checks run afterwards, path-filtered, none required to pass | 2026-09-10, `main` at 0e79776 [EV-0181] |
| Rollback, unreleased | `git revert <sha>` then push | none | Every installer, eventually | none required | — | The same path-filtered checks | never recorded |
| Rollback, published release | **none exists.** A tag cannot be un-shipped. The only forward path is a new release | — | Every operator who installed the tag | none required | — | — | never |
| Restart | N/A — nothing runs | — | — | — | — | — | — |
| Failover | N/A — nothing to fail over to | — | — | — | — | — | — |
| Backup | N/A — no formal backup. Every clone is a full copy | — | — | — | — | — | never |
| Restore | `git clone`, or reset from any existing clone | a surviving clone | — | none | — | **never tested** | never |
| Scale | N/A | — | — | — | — | — | — |
| Maintenance | N/A — no maintenance window is meaningful | — | — | — | — | — | — |

The four CI checks are Flow Plugin Tests, Dossier Plugin Tests, Marketplace Manifest, and CodeQL [EV-0123]. Each is path-filtered, so a given push may run one, some, or all. Across this range only CodeQL ran at every commit, and every run that did fire was green on `ubuntu-latest` [EV-0126]. None of them gates a merge: `main` carries no branch protection and no rulesets, re-read live on 2026-09-10 [EV-0131]. That read was performed by the session operator, outside this engagement's action ceiling (AQ-0012).

The deploy row is the operational summary of this project. One keystroke, no authorization, no required check, and a blast radius of every installer's machine [EV-0131].

The third row is the one that matters right now. Releases v4.9.0 and v4.10.0 were both published on 2026-09-10, hours before commit 16b4dc4 merged, and both ship flow 3.3.0 with the pre-fix `record-quality-run.sh` and `flow-quality-ledger.sh` [EV-0066], [EV-0144]. Unknown: what an operator on macOS actually experiences at v4.10.0 is not established by any row [EV-0144]. This refresh raises it as a new register question, named in the drafter report and not yet numbered. Recommendation: cut a patch release that carries 16b4dc4, and state in the release notes which scripts changed.

## Alert triage

| Alert | First check | Second check | Escalate when | Runbook |
|---|---|---|---|---|
| Flow or Dossier test workflow failure | The Actions run log | Reproduce with the plugin's own `tests/run.sh` locally | never — there is nobody to escalate to | none exists |
| Marketplace Manifest workflow failure | The Actions run log. This job also runs on a weekly cron, so it can fail with no triggering commit | `scripts/check-plugin-versions.sh` locally, which needs `gh` network reads | never | none exists |
| CodeQL finding | GitHub Security tab | Read the flagged workflow or Python file | never | none exists |
| A flow hook refuses a legitimate command | Read the hook's stderr line, which names the token it matched | Re-issue the command without the matched text in a heredoc body or a multi-line script | never | none exists |
| **No other alert exists** | — | — | — | — |

The last row is not hypothetical. The Claude Code client refused three Bash tool calls on 2026-09-10 after flow's `block-destructive.sh` exited non-zero at `PreToolUse` [EV-0172].

All three were false positives [EV-0173]. The hook matches raw command text rather than parsed shell grammar. It read the first token of a multi-line script as a branch name. It also matched denied strings inside heredoc bodies, where they were document text (AQ-0026). The control fires and the client honours it. What it fires on is wrong.

| Question | Where to look | Command or query | Access required |
|---|---|---|---|
| Is it up? | N/A — nothing runs. The nearest question is whether the manifest is coherent, which the Marketplace Manifest job now answers in part | `scripts/check-plugin-versions.sh` | public read plus `gh` auth |
| Is it slow? | N/A | — | — |
| Is it erroring? | GitHub issues — the only channel through which an operator-side failure becomes visible | `gh issue list --state open` | public read |
| Which change caused it? | git history | `git log --oneline` | public read |
| Is data affected? | N/A — no data exists | — | — |

Three of five triage questions are `N/A`. The manifest question is partly answered. `scripts/check-plugin-versions.sh` compares every entry's advertised version against its source, and requires a `sha` on external sources [EV-0080]. It passed at 8 plugins checked, 0 failed, 0 unverifiable [EV-0127]. Unknown: nothing asserts that the file parses and that every source resolves (AQ-0020).

The only working answer to whether something is broken for an operator remains that someone filed an issue. Two had, as of 2026-07-26 [EV-0049].

## Runbook catalog

| Failure mode | Runbook | Owner | Last exercised | Exercise result | Evidence |
|---|---|---|---|---|---|
| A plugin version disagrees with its source | The Marketplace Manifest job turns the check red. Nothing blocks the merge [EV-0131], and no written recovery steps exist | Daniel Bentes | 2026-09-10 — green in CI [EV-0126], and run locally by the session operator (AQ-0012) | pass — 8 checked, 0 failed, 0 unverifiable [EV-0127] | [EV-0080], [EV-0081] |
| A malformed or unresolvable manifest reaches `main` | **none.** The version check does not assert that the file parses or that a source resolves | Daniel Bentes | never | — | [EV-0080], AQ-0020 |
| A broken hook reaches `main` | **none** | Daniel Bentes | never | — | [EV-0162] |
| A published release ships a defective runtime script | **none.** Both published releases carry the pre-fix flow scripts and no patch release exists | Daniel Bentes | never | — | [EV-0144] |
| The flow test suite writes branches into the host repository | **none.** Two branches and 3 commits authored by a test identity were left behind | Daniel Bentes | never | — | [EV-0164] |
| A credential is committed | Partial. flow ships `block-secrets.sh` [EV-0038, observed 2026-07-26] among its 14 hook scripts [EV-0129]. No rotation or purge runbook exists | Daniel Bentes | never | — | [EV-0037, observed 2026-07-26], AQ-0025 |
| Upstream `prompt-decorators` changes under the pin | **none.** The pin makes the change visible only when someone moves it | Daniel Bentes | never | — | [EV-0058], AQ-0005 |
| Windows operator cannot run the plugins | **none** — two issues open without resolution as of 2026-07-26 | Daniel Bentes | never | — | [EV-0049], AQ-0008 |
| A vulnerability is reported | **none, and no intake channel exists** | unassigned | never | — | [EV-0036], observed 2026-07-26 |

Inferred: the credential row treats `block-secrets.sh` as preventive because a non-zero `PreToolUse` exit was observed blocking a tool call once, for a different flow hook, on one machine and one client version [EV-0172]. Nothing establishes the client's hook contract in general (AQ-0025). Nine failure modes, one exercised runbook, and that one is a CI job rather than a written procedure.

## Incident management

| Severity | Definition | Declaration authority | Response time | Communication cadence | Evidence |
|---|---|---|---|---|---|
| **No severity scale is defined** | — | — | — | — | No incident process exists in the repository [EV-0036], observed 2026-07-26 |

| Phase | Actions | Roles | Artifacts produced |
|---|---|---|---|
| Detection, pre-release | A local suite run or a CI check fails. The flow macOS defect was found locally, not in CI, which runs only on `ubuntu-latest` [EV-0126], [EV-0144] | Daniel Bentes | an Actions run, or a local run log |
| Detection, post-release | An operator files a GitHub issue. There is no other path [EV-0049] | operator | the issue |
| Declaration | Not defined | — | — |
| Command | Not defined. One person would do everything [EV-0163] | Daniel Bentes | — |
| Mitigation | Revert and push. Propagation to installers follows the client's own sync schedule, which this project does not control | Daniel Bentes | a commit |
| Recovery | The same push, for unreleased state. For a published tag it needs a new release [EV-0144] | Daniel Bentes | a commit, or a release |
| Closure | Close the issue | Daniel Bentes | the issue thread |
| Post-incident review | Not defined. The `.decisions/` journal holds 21 records, none of which is an incident review | — | — |

The journal holds 21 tracked records at 7ee4923 [EV-0169].

## Security and privacy incidents

| Aspect | Procedure | Differs from standard incident how | Owner | Evidence |
|---|---|---|---|---|
| Detection and triage | Public GitHub issue, or nothing | It cannot differ — there is no standard incident process to differ from | unassigned | [EV-0036], observed 2026-07-26 |
| Containment | Revert and push. **The bad version stays installed on every machine that synced it, and this project cannot count those machines** | — | Daniel Bentes | [EV-0051, observed 2026-07-26], AQ-0004 |
| Evidence preservation | git history and Actions logs. `main` has no force-push protection, so history is rewritable [EV-0131] | — | Daniel Bentes | [EV-0131] |
| Notification decision | Not defined. **There is no channel to notify installers through** | — | unassigned | AQ-0004 |
| External reporting | Not defined. No regulatory obligation attaches — the project processes no personal data | — | unassigned | [EV-0044], observed 2026-07-26 |

The containment row is the most serious operational finding in this package, and this refresh gives it a concrete instance. If a destructive hook reached `main`, the project could revert it in seconds. It would then have **no way to reach the operators already running it, and no way to count them** [EV-0051], AQ-0004. The same gap is what leaves the pre-fix flow scripts sitting in two published tags [EV-0144].

## Communication boundaries

| Audience | Who may communicate | What may be said | What must not be said | Approval |
|---|---|---|---|---|
| Customers | N/A — no customers, no contracts, no accounts | — | — | — |
| Partners | N/A | — | — | — |
| Regulators | N/A — no regulatory obligation attaches | — | — | — |
| Public | Daniel Bentes | Anything already in the public repository | The evidence rows this package marks `Internal`, which include live repository-settings reads [EV-0131] and the assessment machine's own local state [EV-0172], [EV-0173] | Daniel Bentes, per the claim register |

The public-facing disclosure policy for this engagement is `public`, and the repository, the manifest and the releases are all public. That does not make every ledger row public. Rows observed on the maintainer's machine, and rows describing the repository's access configuration, carry `Internal` and stay out of the two published guides.

## Notification obligations

| Obligation | Source | Trigger | Deadline | Owner | Evidence |
|---|---|---|---|---|---|
| **none** | — | — | — | — | No contract, no regulated data, no personal data processing [EV-0044], observed 2026-07-26 |

The absence of a *legal* obligation is worth separating from the absence of an *ethical* one. Nothing requires this project to tell installers that a defective version reached their machines. Nothing enables it either, and two published releases are in exactly that position today [EV-0144].

## Status, review, and learning

| Mechanism | Where | Owner | Cadence | Evidence |
|---|---|---|---|---|
| Status communication | **none.** No status page and no announcement channel. Releases carry tags and CHANGELOGs only | — | — | [EV-0066], [EV-0177] |
| Post-incident review | **none defined** | — | — | [EV-0036], observed 2026-07-26 |
| Action tracking | GitHub issues — 2 open at 2026-07-26, both Windows portability, neither resolved | Daniel Bentes | none | [EV-0049], observed 2026-07-26 |
| Recurrence check | Partial. The Marketplace Manifest job runs weekly on cron, so version drift is re-checked without a commit | Daniel Bentes | weekly | [EV-0081] |
| Decision journalling | `.decisions/` — 21 records, written by the flow plugin's journal during development | Daniel Bentes | per issue worked | [EV-0169] |

The last row is the project's one genuine learning mechanism, and it is a byproduct of using its own plugin. The weekly cron above runs whether or not anyone commits [EV-0081].

## Business continuity and disaster recovery

| Scenario | Continuity plan | Recovery objective | Last exercised | Result | Evidence |
|---|---|---|---|---|---|
| GitHub becomes unavailable | Wait. Every clone is a full copy, so nothing is lost. Nothing can be published either | none stated | never | — | [EV-0051], observed 2026-07-26 |
| The repository is deleted or lost | Re-push from any clone. **GitHub-side state is in no clone** — repository settings, release notes, and uploaded release assets. All 63 tags are merged into `d3fc744` and travel with every clone [EV-0177] | none stated | never | — | [EV-0177], [EV-0131] |
| The maintainer becomes unavailable | **No plan.** No backup owner, no second identity with write access, no succession path. 8 published plugin entries would freeze | none | never | — | [EV-0057], [EV-0163] |
| The Claude Code plugin contract changes | Adapt the manifest and the plugins. No advance notice mechanism exists | none stated | never | — | [EV-0043, I, observed 2026-07-26] |

The third row is the project's real continuity risk. It is not a technical problem, and it has a cheap partial mitigation. Recommendation: name a second maintainer, or state in the README that the project is single-maintainer so installers can weigh that themselves.

The repository holds 0 Actions secrets, re-read live on 2026-09-10 [EV-0131]. Losing GitHub-side state therefore costs settings and release assets, not credentials.

## Manual operations and unsafe gaps

| Operation | Why it is manual | Who can do it | Risk if done wrong | Reversible | Proposed remedy |
|---|---|---|---|---|---|
| Version bump across `plugin.json` and `marketplace.json` | The edit is manual. Agreement between the two is now checked in CI | Daniel Bentes | An operator installs a version different from the one advertised | yes | Already remedied for agreement [EV-0080], [EV-0081], [EV-0127] |
| Tagging a release to match `metadata.version` | Manual, unchecked | Daniel Bentes | The manifest advertises a release that does not exist | yes | Assert tag existence in CI |
| Cutting a patch release after a runtime fix merges | Manual, unchecked, and not done | Daniel Bentes | **Published tags keep shipping the defect** — true right now at v4.10.0 | yes | A release check comparing the newest tag against the newest runtime-path commit |
| Updating the README when a plugin changes | Manual, unchecked | Daniel Bentes | Advertised facts drift from the tree | yes | A CI step comparing README facts to the manifest |
| Moving the pinned sha for an external marketplace source | Manual, unchecked | Daniel Bentes | The pin goes stale while staying self-consistent, which the version check reports rather than fails | yes | Assert the pin resolves to a tagged upstream commit |
| Repository settings — protection, rulesets, secrets | GitHub UI, in no file | Daniel Bentes | The access model can change with no commit and no review | yes | Record intended settings in the repository and check them in CI |
| Pushing to `main` | No gate exists | anyone with write access | Every installer receives it | by revert only | Enable branch protection requiring the three test workflows |

Seven manual operations. One is now checked in CI [EV-0080], [EV-0081], [EV-0127]. The README drift this document reported at 2026-07-26 was corrected in commit 7ee4923, and is absent at d3fc744 [EV-0170], [EV-0179]. Nothing prevents it recurring, because the version check reads manifests and not prose [EV-0080]. The metadata-version gap is closed: metadata reads 4.10.0 across 8 entries [EV-0057] and v4.10.0 was published on 2026-09-10 [EV-0066]. One row is failing today, and it is the patch release that has not been cut [EV-0144].
