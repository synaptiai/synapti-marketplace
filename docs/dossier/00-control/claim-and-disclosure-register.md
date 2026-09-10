---
dossier-header: internal-v1
title: Claim and Disclosure Register
purpose: Governs which sentences may appear in the public documents, so nothing reaches an outside reader that is not both approved and evidenced.
audience: Maintainer, Reviewer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: Any edit to 06-public/**, or any evidence row a public claim depends on changing state
related: [00-control/evidence-ledger.md, 06-public/technical-partner-guide.md, 06-public/customer-product-and-trust-guide.md]
---
# Claim and Disclosure Register
<!-- contract: references/package-contract-00-control.md#claim-and-disclosure-register -->

## Method

Every sentence in `06-public/**` that makes a claim maps to one `approved` row below, matching its `Proposed wording` verbatim. Column definitions and identifier grammar are in the plugin reference `references/register-schemas.md`.

The package cannot approve its own claims. Where human approval is required by the disclosure policy and has not been recorded, `Status` is `pending` and the sentence does not ship. Zero unsupported public claims is a release gate.

**Disclosure policy in force:** `public`. The repository is public, the manifest is public, and this package is committed to the same public repository. `confidentiality` defaults to `Public`.

**Approval authority:** `disclosure.publicClaimApproval` is `required`. Daniel Bentes is the sole approver for every claim type.

The register carries 48 rows. Thirty-five were approved on 2026-07-26 in the session that produced this package. Eleven of those thirty-five have since been superseded: ten by claims the 7e4a097..1372b19 range falsified, and CL-0009 by the removal of the tree's only dependency manifest. On 2026-09-10 twelve replacement and new claims were presented individually — each with its wording, evidence, scope and limitation — and ten were approved. CL-0043 (maintainer concentration) and CL-0047 (absence of a vulnerability scan) were held: both are true and evidenced, and the approver chose not to state either in a public document. CL-0048 was registered the same day and is not yet presented. A held claim and an unwritten one are distinguished here deliberately, so a later reader can tell a decision from an omission.

**A pending claim does not ship.** Where a held claim replaced an approved one, the subject leaves the public documents entirely rather than reverting to the superseded wording.

## Public claim inventory

| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |
|---|---|---|---|---|---|---|---|---|---|---|---|
| CL-0001 | The marketplace publishes eight Claude Code plugins. | capability | [EV-0001] | 06b1586 | The manifest on this branch | The published `main` manifest carries seven; the eighth is dossier, added here | Daniel Bentes | Public | partner | superseded | Direct read of the manifest; the branch qualification is carried in the document. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0045, approved 2026-09-10 |
| CL-0002 | Six plugins are versioned in this repository. Two are published from external sources — one git submodule and one `git-subdir` entry. | capability | [EV-0003] | 06b1586 | Distribution shape | — | Daniel Bentes | Public | partner | superseded | Manifest and `.gitmodules` agree. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0036, approved 2026-09-10 |
| CL-0003 | Add the marketplace, then install individual plugins by name. | capability | [EV-0051], [EV-0052] | live | The install path | Verified on a profile that already had the marketplace registered; a cold first install is unobserved (AQ-0003) | Daniel Bentes | Public | partner, customer | approved | The client's own state files show the marketplace resolved from GitHub and six plugins installed from it |
| CL-0004 | The flow plugin ships 32 skills, 23 commands, 9 agents, and 12 hook scripts. | capability | [EV-0004], [EV-0038] | 06b1586 | flow | Counts are file counts; a skill directory without a `SKILL.md` is not a skill | Daniel Bentes | Public | partner | superseded | File counts executed directly; supersedes the plugin README's "33 skills" (CT-0002). Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0037, approved 2026-09-10 |
| CL-0005 | The flow and dossier plugins ship automated test suites — 1022 and 1241 assertions respectively — both passing at the assessed commit. | quality | [EV-0008], [EV-0009] | 06b1586 | flow, dossier | Assertion counts measure the suites, not coverage of the plugins | Daniel Bentes | Public | partner | superseded | Both suites executed during this assessment. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0038, approved 2026-09-10 |
| CL-0006 | Five of the seven in-repository plugins ship no automated test suite. | quality | [EV-0010] | 06b1586 | In-tree plugins | `agent-capability-standard` carries a Python suite that was not executed here (AQ-0001) | Daniel Bentes | Public | partner, customer | superseded | Approved deliberately alongside CL-0005 so the strong number is not read as covering everything. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0039, approved 2026-09-10 |
| CL-0007 | Plugins run inside your own Claude Code session. The marketplace operates no service and collects no telemetry. | security | [EV-0044] | 06b1586 | Architecture | — | Daniel Bentes | Public | partner, customer | approved | Follows from the artifact inventory: Markdown, JSON, and shell only, with one dependency manifest |
| CL-0008 | Three plugins register hooks — shell scripts the Claude Code client runs on your machine at defined lifecycle points. | security | [EV-0040], [EV-0038], [EV-0039] | 06b1586 | flow, dossier, agent-capability-standard | — | Daniel Bentes | Public | partner, customer | superseded | Disclosed because it is the only mechanism that executes without the operator invoking it. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0040, approved 2026-09-10 |
| CL-0009 | The repository's only declared third-party runtime dependency is `pyyaml`, required by the agent-capability-standard plugin. | security | [EV-0041] | 95f7ac2 | Dependency surface | Declared dependencies only; it does not cover what the Claude Code client itself requires | Daniel Bentes | Public | partner, customer | superseded | Single dependency manifest in the tree. Falsified on 2026-09-10: no dependency manifest is tracked at all [EV-0186], and the manifest that declared `pyyaml` left the tree with agent-capability-standard. Replaced by CL-0048, which is pending approval |
| CL-0010 | The prompt-decorators entry is pinned to the floating ref `main`, so two installs performed on different days need not resolve to the same contents. | capability | [EV-0030] | 06b1586 | prompt-decorators | — | Daniel Bentes | Public | partner | superseded | Read directly from the manifest entry. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0041, approved 2026-09-10 |
| CL-0011 | The marketplace has published 57 tags; the most recent release is v4.6.2, dated 2026-05-29. | capability | [EV-0032] | live | Release history | — | Daniel Bentes | Public | partner, customer | superseded | Tag list and release list agree. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0042, approved 2026-09-10 |
| CL-0012 | The project is maintained by one person. All 370 commits across all branches carry a single author identity, and no component has a named backup owner. | posture | [EV-0035] | 06b1586 | Whole project | — | Daniel Bentes | Public | partner, customer | superseded | Approved as a bus-factor disclosure an installer is entitled to weigh. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0043, which the approver held on 2026-09-10; the subject leaves the public documents |
| CL-0013 | The `main` branch carries no branch protection and no rulesets, so both test workflows are advisory rather than required. | posture | [EV-0016], [EV-0017] | live | Repository settings | — | Daniel Bentes | Public | partner, customer | approved | Read from the GitHub API during this assessment |
| CL-0014 | The repository is licensed under Apache-2.0, and every plugin manifest declares the same licence. | licence | [EV-0019], [EV-0020], [EV-0021] | live | Licensing | — | Daniel Bentes | Public | partner, customer | approved | Approved with the rights consequence attached rather than as a bare fact. Required qualification retired by Daniel Bentes on 2026-09-10: it warned that GitHub would report the licence only after this branch merged. `LICENSE` reached `main` on 2026-07-26 and GitHub reports Apache-2.0 today [EV-0132], so the condition is met. CL-0034 remains the live caveat, covering copies taken before that date |
| CL-0015 | The repository publishes no security policy and no private disclosure channel. | posture | [EV-0036] | 06b1586 | Vulnerability intake | — | Daniel Bentes | Public | partner, customer | approved | Material because three plugins ship hooks that execute on operator machines |
| CL-0016 | No credential matching the project's own detector pattern set appears in any tracked file. | security | [EV-0037] | 06b1586 | Tracked files | Must ship with the qualification below | Daniel Bentes | Public | partner, customer | approved | A negative result over an enumerated pattern set |
| CL-0017 | The dossier plugin's post-merge documentation automation has never been executed end to end. Its components are tested; the assembled behaviour is not. | posture | [EV-0045], [EV-0009] | live | dossier | — | Daniel Bentes | Public | partner, customer | approved | Approved so that no reader takes the passing suite as proof the workflow runs |
| CL-0018 | Two open issues report that the shipped shell scripts fail under Windows and Git Bash, and neither test workflow runs on Windows. | posture | [EV-0049], [EV-0012] | live | Portability | The real scope is unmeasured (AQ-0008) | Daniel Bentes | Public | partner, customer | approved | Directly relevant to any operator not on macOS or Linux |
| CL-0019 | The marketplace holds no personal data. It has no accounts, no server, and no database. | privacy | [EV-0044] | 06b1586 | Privacy posture | Covers the marketplace itself, not the Claude Code client or the model provider | Daniel Bentes | Public | customer | approved | Follows from the same architectural fact as CL-0007 |
| CL-0020 | Hooks execute without you invoking them. They run with your user privileges, in your shell, with access to whatever you have access to. There is no sandbox. | security | [EV-0040] | 06b1586 | the hook mechanism | **Must ship adjacent to the hook inventory.** | Daniel Bentes | Public | partner, customer | approved | The single most consequential fact for an installer, and the reason the hook count is disclosed at all |
| CL-0021 | Assertion counts describe the suites, not coverage of the plugins they guard. | quality | [EV-0008], [EV-0009] | 06b1586 | the two test suites | — | Daniel Bentes | Public | partner | approved | A qualification without which CL-0005's numbers read as coverage |
| CL-0022 | This covers declared dependencies, not what the Claude Code client itself requires. | security | [EV-0041] | 06b1586 | the dependency surface | — | Daniel Bentes | Public | partner, customer | superseded | A qualification on CL-0009. Superseded on 2026-09-10 with the claim it qualified: CL-0009 is falsified [EV-0186] and its replacement CL-0048 is pending, so there is no dependency claim left for this sentence to accompany |
| CL-0023 | Verified on a profile that already had the marketplace registered; a first install on a clean profile has not been observed. | capability | [EV-0051], [EV-0052] | 06b1586 | the install path | — | Daniel Bentes | Public | partner, customer | approved | A qualification on CL-0003, carrying AQ-0003 |
| CL-0024 | The published `main` manifest carries seven entries; the eighth exists only on the branch this guide was produced from. | capability | [EV-0001], [EV-0054] | 06b1586 | the plugin count | — | Daniel Bentes | Public | partner, customer | superseded | A qualification on CL-0001. Falsified by the changes in 7e4a097..d3fc744; replaced by CL-0044, approved 2026-09-10 |
| CL-0025 | Counts are file counts — a skill directory without a `SKILL.md` is not a skill. | capability | [EV-0004], [EV-0029] | 06b1586 | artifact counts | — | Daniel Bentes | Public | partner | approved | A qualification on CL-0004 |
| CL-0026 | Claude Code's plugin client defaults to auto-updating an added marketplace. Changes reach you without your acting, on the client's schedule. | posture | [EV-0051] | 06b1586 | update propagation | — | Daniel Bentes | Public | partner, customer | approved | Material because it converts an ungated `main` into an unattended delivery channel |
| CL-0027 | Helper scripts under each plugin's `bin/` are internal. They are executable and documented, but they carry no stability commitment and may change without notice. | capability | [EV-0007] | 06b1586 | the helper scripts | — | Daniel Bentes | Public | partner | approved | Prevents an integrator from building against an unstable surface |
| CL-0028 | There is no sandbox environment and no staging marketplace. A scratch repository is the recommended way to evaluate a workflow plugin before pointing it at anything you care about. | capability | [EV-0044] | 06b1586 | evaluation | — | Daniel Bentes | Public | partner | approved | States the absence rather than leaving an integrator to discover it |
| CL-0029 | This is an open-source project published without warranty or commitment. | posture | [EV-0019] | 06b1586 | the whole distribution | — | Daniel Bentes | Public | partner, customer | approved | Apache-2.0 disclaims warranty; stating it plainly is not a substitute for the licence but is what a reader acts on |
| CL-0030 | Your Claude Code session sends data to Anthropic under your own agreement with them, and a plugin's hooks run on your machine with your privileges. Neither is governed by this project. | privacy | [EV-0044], [EV-0040] | 06b1586 | the boundary of CL-0019 | **Must ship adjacent to the no-personal-data claim.** | Daniel Bentes | Public | customer | approved | Without it, "holds no personal data" reads as a broader privacy assurance than it is |
| CL-0031 | Every statement in this guide maps to an approved claim backed by a verified evidence row. | posture | [EV-0047], [EV-0048] | 06b1586 | both public documents | This is the claim the whole register exists to make true; if the scan reports an unregistered sentence, this claim is false | Daniel Bentes | Public | partner, customer | approved | A reader relies on it to decide how much to trust the rest |
| CL-0032 | Where a claim is only true within a scope, the scope is stated next to it rather than in a footnote. | posture | [EV-0047] | 06b1586 | both public documents | — | Daniel Bentes | Public | partner | approved | States the convention a reader needs to read the qualifications correctly |
| CL-0033 | This guide is for anyone deciding whether to install these plugins. | posture | — | 06b1586 | the customer guide | — | Daniel Bentes | Public | customer | approved | Audience statement; the reader acts on it |
| CL-0034 | Until 2026-07-26 no `LICENSE` file existed at all, while the README asserted MIT. A copy taken before that date predates the licence; ask before relying on the earlier state. | licence | [EV-0019], [EV-0020] | 06b1586 | copies taken before 2026-07-26 | **Must ship adjacent to the licence claim.** | Daniel Bentes | Public | customer | approved | Anyone who forked earlier is entitled to know the state they forked from |
| CL-0035 | Two things bound that risk, and you should verify both yourself. | security | [EV-0007], [EV-0038] | 06b1586 | the hook mechanism | — | Daniel Bentes | Public | partner, customer | approved | Introduces the two mitigations; an unqualified hook disclosure would read as unmitigated |
| CL-0036 | Six plugins are versioned in this repository. Two are published from other repositories, each pinned to a commit sha. | capability | [EV-0058], [EV-0127] | 7ee4923 | Distribution shape | The manifest uses three resolution mechanisms: six relative paths, one `github` source, one `git-subdir` source | Daniel Bentes | Public | partner | approved | Replaces CL-0002. There is no submodule: `.gitmodules` was removed and the entry became a pinned `github` source [EV-0059]. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0037 | The flow plugin ships 32 skills, 23 commands, 9 agents, and 14 hook scripts. | capability | [EV-0162] | 7ee4923 | The tracked tree | File counts — a skill directory without a `SKILL.md` is not a skill | Daniel Bentes | Public | partner | approved | Replaces CL-0004, which recorded 12 hook scripts against 14 tracked. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0038 | The flow and dossier plugins ship automated test suites — 2336 and 1951 assertions respectively — both passing. | capability | [EV-0098], [EV-0107], [EV-0126] | 7ee4923 | Both suites, macOS and Linux | Assertion counts describe the suites, not coverage of the plugins they guard. The macOS results were observed on one machine; the Linux results are GitHub Actions runs | Daniel Bentes | Public | partner | approved | Replaces CL-0005. Both suites roughly doubled in this range and both pass on Apple's system bash as well as on `ubuntu-latest`. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0039 | Four of the six in-repository plugins ship no automated test suite. | capability | [EV-0010], [EV-0162] | 7ee4923 | The tracked tree | decipon, gh-workflow, context-ledger and ai-first-org-design-kit carry no `tests/` directory | Daniel Bentes | Public | partner, customer | approved | Replaces CL-0006. The count changed because the repository now vendors six plugins, not seven — `agent-capability-standard` is no longer in the tree. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation. Destination widened to `partner, customer` by Daniel Bentes on 2026-09-10: the predecessor claim reached both audiences, and CL-0020's required adjacency to a hook inventory cannot be met in the customer guide without it |
| CL-0040 | Two of the plugins in this repository register hooks — shell scripts the Claude Code client runs on your machine at defined lifecycle points — and so does the externally sourced agent-capability-standard. | posture | [EV-0162], [EV-0168] | 7ee4923 | Hook surface | 19 hook scripts across the two tracked manifests, plus a `hooks.json` and two scripts at the pinned external tree | Daniel Bentes | Public | partner, customer | approved | Replaces CL-0008. The count of three still holds, but one of the three is no longer code this repository carries. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation. Destination widened to `partner, customer` by Daniel Bentes on 2026-09-10: the predecessor claim reached both audiences, and CL-0020's required adjacency to a hook inventory cannot be met in the customer guide without it |
| CL-0041 | Both externally sourced plugins are pinned to a commit sha, so two installs performed on different days resolve the same tree. | capability | [EV-0058], [EV-0127] | 7ee4923 | Supply chain | A pin that is stale but self-consistent still passes the CI check; staleness is reported, not failed | Daniel Bentes | Public | partner | approved | Replaces CL-0010, which recorded prompt-decorators on the floating ref `main`. This is a reproducibility improvement and is safe to state as one. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0042 | The marketplace has published 63 tags; the most recent release is v4.10.0, dated 2026-09-10. | capability | [EV-0177], [EV-0066] | 7ee4923 | Release history | — | Daniel Bentes | Public | partner | approved | Replaces CL-0011, which recorded 57 tags and v4.6.2. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0043 | The project is maintained by one person. All 214 commits on `main` carry a single author identity, and no component has a backup owner. | posture | [EV-0163], [EV-0131] | 7ee4923 | `main` | A wider count across every ref returns three identities; the other two are not on `main`, and three of those commits came from a test-suite leak [EV-0164] | Daniel Bentes | Public | partner | pending | Replaces CL-0012, whose "370 commits across all branches" phrasing does not survive a recount. The concentration itself is unchanged. Presented to Daniel Bentes on 2026-09-10 and deliberately held: the concentration is true and evidenced, but the approver chose not to state it in a public document. Held, not forgotten — the subject does not appear in `06-public/**` in any form |
| CL-0044 | The published `main` manifest carries all eight entries. | capability | [EV-0057] | 7ee4923 | The default branch | — | Daniel Bentes | Public | partner | approved | Replaces CL-0024. dossier reached `main` and was published in v4.9.0, so the branch qualification that guide carried is now wrong rather than merely cautious. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0045 | The marketplace publishes eight Claude Code plugins. | capability | [EV-0057], [EV-0064] | 7ee4923 | The published manifest | Each entry's advertised version is checked against its source in CI [EV-0080], [EV-0127] | Daniel Bentes | Public | partner, customer | approved | Replaces CL-0001, whose limitation column said the eighth plugin existed only on a feature branch. It is on `main`. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation. Destination widened to `partner, customer` by Daniel Bentes on 2026-09-10: the predecessor claim reached both audiences, and CL-0020's required adjacency to a hook inventory cannot be met in the customer guide without it |
| CL-0046 | Every marketplace entry's advertised version is checked against its source in continuous integration, on manifest changes, weekly, and on demand. | capability | [EV-0080], [EV-0081], [EV-0127] | 7ee4923 | Manifest consistency | The check compares manifests and does not read prose, so a README figure can drift while the check passes [EV-0170]. A pin that is stale but self-consistent is reported, not failed | Daniel Bentes | Public | partner | approved | New claim. Nothing in the register covers the manifest check, which is the only automated safeguard on the highest-blast-radius file in the repository. Approved by Daniel Bentes on 2026-09-10, presented individually with wording, evidence, scope and limitation |
| CL-0047 | No dependency-vulnerability scan has been run against this repository, and no scan artifact exists. | posture | [EV-0121], [EV-0073] | 7ee4923 | Vulnerability evidence | CodeQL runs and reports zero open alerts [EV-0140], but it analyses only the `actions` and `python` matrix languages [EV-0134]; the 37 shell scripts under plugin `bin/` directories and the 19 hook scripts are outside every configured language, while the 3 Python files there are inside it | Daniel Bentes | Public | partner | pending | New claim. The dependency surface is small and it is also unscanned; a reader must not be allowed to read the first as the second. Presented to Daniel Bentes on 2026-09-10 and deliberately held. Held, not forgotten — no statement about vulnerability scanning appears in `06-public/**` |
| CL-0048 | The repository declares no third-party dependencies. Two of the flow plugin's Python entrypoints require PyYAML at runtime, and no file in the repository declares it for an operator installing the plugin. | posture | [EV-0186], [EV-0187] | 1372b19 | Dependency surface | The two continuous-integration workflows pin `pyyaml==6.0.2`, so CI is unaffected; the gap is an operator install | Daniel Bentes | Public | partner | pending | Replaces CL-0009, which attributed the dependency to a plugin that is no longer in the tree. Registered on 2026-09-10, awaiting approval |

## Required qualifications

| Claim ID | Qualification that must accompany it | Where it appears |
|---|---|---|
| CL-0016 | The scan covers tracked files against an enumerated pattern set. It proves that none of those formats appears, not that no credential exists. | `06-public/customer-product-and-trust-guide.md`, in the same paragraph as the claim |
| CL-0003 | Verified on a profile with the marketplace already registered; a first install on a clean profile has not been observed. | `06-public/technical-partner-guide.md`, adjacent to the install instructions |
| CL-0045 | Each entry's advertised version is checked against its source in continuous integration. | Both guides, adjacent to the count |
| CL-0038 | Assertion counts describe the suites, not coverage of the plugins they guard. The macOS results were observed on one machine; the Linux results are GitHub Actions runs. | `06-public/technical-partner-guide.md`, adjacent to the numbers |
| CL-0036 | The manifest uses three resolution mechanisms: six relative paths, one `github` source, one `git-subdir` source. | `06-public/technical-partner-guide.md`, in the same paragraph as the claim |

## Rejected and withdrawn claims

| ID | Wording | Reason declined | Date | What would make it publishable |
|---|---|---|---|---|
| CL-R01 | The Synapti Plugin Marketplace is MIT-licensed. | Contradicted by evidence when proposed: no `LICENSE` file existed and GitHub detected no licence. Superseded rather than revived — the owner chose Apache-2.0 on 2026-07-26, so the MIT wording is now wrong for a different reason and must not be re-proposed | 2026-07-26 | Nothing. The correct claim is CL-0014 |
| CL-R02 | The dossier plugin automatically refreshes your documentation after a pull request merges. | The capability has never been observed working (AQ-0002). Its parts pass 1241 assertions; the assembled workflow has never run | 2026-07-26 | One end-to-end run in a live repository, with the run URL and the resulting documentation pull request recorded as evidence |
| CL-R03 | The marketplace's plugins are used by *n* operators. | No install telemetry exists for plugin marketplaces, and the plugins emit none by design (AQ-0004) | 2026-07-26 | Nothing available from this repository. The claim is unprovable here and should not be re-proposed |
| CL-R04 | The marketplace is production-ready. | Not a claim with an evidence shape. It would need a definition of production-readiness and a check against it; the underlying facts are already published as CL-0005, CL-0006, CL-0013, and CL-0017 | 2026-07-26 | Do not re-propose. Publish the constituent facts instead |

## Confidentiality and disclosure risks

| Risk | Material at risk | Leak path | Control | Owner |
|---|---|---|---|---|
| Assessment machine paths | Absolute paths under the maintainer's home directory were read to verify install state [EV-0051] | A path pasted into an evidence row or a public document | Evidence rows reference the client state files by role, not by absolute path; no `/Users/...` path appears in any public document | Daniel Bentes |
| Credential formats in detector definitions | The repository's own hook scripts and tests contain credential *patterns* by necessity | A scan result quoting a matched line verbatim | `dossier-claim-scan.sh` redacts matched values before reporting; the ledger records type and location category only | Daniel Bentes |
| Unreleased branch state | This documentation package is produced on `docs/dossier-refresh` and describes a tree that has not merged | A public document describing branch-only capability as shipped | Every public claim carries `Applicable version`. The branch qualification CL-0001 carried is retired: dossier reached `main` and published in v4.9.0, and the manifest on `main` now carries all eight entries [EV-0057] | Daniel Bentes |
| Held claims read as absent facts | CL-0043 (single-maintainer concentration) and CL-0047 (no dependency-vulnerability scan) are true, evidenced, and deliberately not published | A reader inferring from silence that the project is multi-maintained or that its dependencies are scanned | Neither subject appears in `06-public/**` in any form, so the guides make no statement a reader could invert. Both facts remain readable in this register and in the internal documents | Daniel Bentes |
| Security posture disclosure | CL-0013 and CL-0015 tell a reader that `main` is unprotected and that no disclosure channel exists | The public documents themselves | Accepted deliberately. Both facts are already readable from the public repository by anyone who checks, so disclosure costs nothing and withholding them would misrepresent the posture | Daniel Bentes |

## Mapping to public documents

Rebuilt on 2026-09-10 by matching each approved row's `Proposed wording` against the derived guides, not carried forward from the previous round. Every claim listed below was found in the section named.

### `06-public/technical-partner-guide.md`

| Section | Claim ID | Status |
|---|---|---|
| Front matter | CL-0031, CL-0032 | approved |
| What this is | CL-0036, CL-0044, CL-0045 | approved |
| How an integration fits together | — | diagram only; the section asserts nothing in prose, so it carries no claim |
| Installing | CL-0003, CL-0023 | approved |
| What ships in each plugin | CL-0025, CL-0037, CL-0041 | approved |
| Public interfaces | CL-0027 | approved |
| How it executes on your machine | CL-0007, CL-0020, CL-0035, CL-0040 | approved |
| Versioning and compatibility | CL-0026, CL-0042, CL-0046 | approved |
| Testing your integration | CL-0028 | approved |
| Quality signals | CL-0021, CL-0038, CL-0039 | approved |
| Commitments | CL-0029 | approved |
| Known limitations | CL-0013, CL-0017, CL-0018 | approved |

### `06-public/customer-product-and-trust-guide.md`

| Section | Claim ID | Status |
|---|---|---|
| Front matter | CL-0031, CL-0033 | approved |
| What the marketplace is | CL-0007, CL-0045 | approved |
| Getting started | CL-0003, CL-0023 | approved |
| What it can and cannot do | CL-0013, CL-0017, CL-0018, CL-0039 | approved |
| Accounts, permissions, and controls | CL-0026 | approved |
| What runs on your machine | CL-0020, CL-0035, CL-0040 | approved |
| Your data | CL-0019, CL-0030 | approved |
| Security, privacy, reliability, and accessibility | CL-0015, CL-0016 | approved |
| Licensing | CL-0014, CL-0029, CL-0034 | approved |

### Approved but unused

CL-0014, CL-0015 and CL-0016 carry `Destination: partner, customer` and appear only in the customer guide. A destination permits a claim to appear; it does not require it. **CL-0014 is the one worth revisiting** — the technical partner guide states the project is published without warranty (CL-0029) but never names the licence, and a partner evaluating whether to build against these plugins needs it. Adding it is an editorial decision, not an approval one, since the row is already approved for that destination.

CL-0022 no longer appears anywhere and is superseded. CL-0043, CL-0047 and CL-0048 are pending and appear nowhere, which is the register working as designed.

## Register summary

| Measure | Count |
|---|---|
| Total claims | 48 |
| Approved | 33 |
| Pending | 3 |
| Superseded | 12 |
| Rejected or withdrawn | 4 |
| Approved claims resting on a state other than `V` or `C` | 0 |
| Sentences in `06-public/**` with no matching row | 0 |

Pending: CL-0043 and CL-0047 were presented on 2026-09-10 and held by the approver; CL-0048 was registered the same day and has not been presented.

CL-0033 ("This guide is for anyone deciding whether to install these plugins") carries no evidence citation. It describes the document's own audience rather than the project, so there is nothing to observe; it is retained because the scan requires every public sentence to map to a row.

The zero in the last line is `dossier-claim-scan.sh`'s result, re-run after the guides were derived. It was falsified twice with a canary sentence appended to each guide in turn — both times the scanner fired and named the line — so the zero reflects the scanner working, not the scanner sleeping. It remains a proxy for tables, bullets and fenced blocks, which the scanner skips; those were swept by reading.
