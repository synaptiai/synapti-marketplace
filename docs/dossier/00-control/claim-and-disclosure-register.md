---
dossier-header: internal-v1
title: Claim and Disclosure Register
purpose: Governs which sentences may appear in the public documents, so nothing reaches an outside reader that is not both approved and evidenced.
audience: Maintainer, Reviewer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
last-verified: 2026-07-26
review-trigger: Any edit to 06-public/**, or any evidence row a public claim depends on changing state
related: [00-control/evidence-ledger.md, 06-public/technical-partner-guide.md, 06-public/customer-product-and-trust-guide.md]
---
# Claim and Disclosure Register
<!-- contract: references/package-contract-00-control.md#claim-and-disclosure-register -->

## Method

Every sentence in `06-public/**` that makes a claim maps to one `approved` row below, matching its `Proposed wording` verbatim. Column definitions and identifier grammar are in the plugin reference `references/register-schemas.md`.

The package cannot approve its own claims. Where human approval is required by the disclosure policy and has not been recorded, `Status` is `pending` and the sentence does not ship. Zero unsupported public claims is a release gate.

**Disclosure policy in force:** `public`. The repository is public, the manifest is public, and this package is committed to the same public repository. `confidentiality` defaults to `Public`.

**Approval authority:** `disclosure.publicClaimApproval` is `required`. Daniel Bentes is the sole approver for every claim type. All 35 rows below were approved on 2026-07-26 in the session that produced this package, with the posture claims explicitly included after being presented separately from the capability claims.

## Public claim inventory

| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |
|---|---|---|---|---|---|---|---|---|---|---|---|
| CL-0001 | The marketplace publishes eight Claude Code plugins. | capability | [EV-0001] | 06b1586 | The manifest on this branch | The published `main` manifest carries seven; the eighth is dossier, added here | Daniel Bentes | Public | partner | approved | Direct read of the manifest; the branch qualification is carried in the document |
| CL-0002 | Six plugins are versioned in this repository. Two are published from external sources — one git submodule and one `git-subdir` entry. | capability | [EV-0003] | 06b1586 | Distribution shape | — | Daniel Bentes | Public | partner | approved | Manifest and `.gitmodules` agree |
| CL-0003 | Add the marketplace, then install individual plugins by name. | capability | [EV-0051], [EV-0052] | live | The install path | Verified on a profile that already had the marketplace registered; a cold first install is unobserved (AQ-0003) | Daniel Bentes | Public | partner, customer | approved | The client's own state files show the marketplace resolved from GitHub and six plugins installed from it |
| CL-0004 | The flow plugin ships 32 skills, 23 commands, 9 agents, and 12 hook scripts. | capability | [EV-0004], [EV-0038] | 06b1586 | flow | Counts are file counts; a skill directory without a `SKILL.md` is not a skill | Daniel Bentes | Public | partner | approved | File counts executed directly; supersedes the plugin README's "33 skills" (CT-0002) |
| CL-0005 | The flow and dossier plugins ship automated test suites — 1022 and 1241 assertions respectively — both passing at the assessed commit. | quality | [EV-0008], [EV-0009] | 06b1586 | flow, dossier | Assertion counts measure the suites, not coverage of the plugins | Daniel Bentes | Public | partner | approved | Both suites executed during this assessment |
| CL-0006 | Five of the seven in-repository plugins ship no automated test suite. | quality | [EV-0010] | 06b1586 | In-tree plugins | `agent-capability-standard` carries a Python suite that was not executed here (AQ-0001) | Daniel Bentes | Public | partner, customer | approved | Approved deliberately alongside CL-0005 so the strong number is not read as covering everything |
| CL-0007 | Plugins run inside your own Claude Code session. The marketplace operates no service and collects no telemetry. | security | [EV-0044] | 06b1586 | Architecture | — | Daniel Bentes | Public | partner, customer | approved | Follows from the artifact inventory: Markdown, JSON, and shell only, with one dependency manifest |
| CL-0008 | Three plugins register hooks — shell scripts the Claude Code client runs on your machine at defined lifecycle points. | security | [EV-0040], [EV-0038], [EV-0039] | 06b1586 | flow, dossier, agent-capability-standard | — | Daniel Bentes | Public | partner, customer | approved | Disclosed because it is the only mechanism that executes without the operator invoking it |
| CL-0009 | The repository's only declared third-party runtime dependency is `pyyaml`, required by the agent-capability-standard plugin. | security | [EV-0041] | 95f7ac2 | Dependency surface | Declared dependencies only; it does not cover what the Claude Code client itself requires | Daniel Bentes | Public | partner, customer | approved | Single dependency manifest in the tree |
| CL-0010 | The prompt-decorators entry is pinned to the floating ref `main`, so two installs performed on different days need not resolve to the same contents. | capability | [EV-0030] | 06b1586 | prompt-decorators | — | Daniel Bentes | Public | partner | approved | Read directly from the manifest entry |
| CL-0011 | The marketplace has published 57 tags; the most recent release is v4.6.2, dated 2026-05-29. | capability | [EV-0032] | live | Release history | — | Daniel Bentes | Public | partner, customer | approved | Tag list and release list agree |
| CL-0012 | The project is maintained by one person. All 370 commits across all branches carry a single author identity, and no component has a named backup owner. | posture | [EV-0035] | 06b1586 | Whole project | — | Daniel Bentes | Public | partner, customer | approved | Approved as a bus-factor disclosure an installer is entitled to weigh |
| CL-0013 | The `main` branch carries no branch protection and no rulesets, so both test workflows are advisory rather than required. | posture | [EV-0016], [EV-0017] | live | Repository settings | — | Daniel Bentes | Public | partner, customer | approved | Read from the GitHub API during this assessment |
| CL-0014 | The repository is licensed under Apache-2.0, and every plugin manifest declares the same licence. | licence | [EV-0019], [EV-0020], [EV-0021] | live | Licensing | Must ship with the qualification below | Daniel Bentes | Public | partner, customer | approved | Approved with the rights consequence attached rather than as a bare fact |
| CL-0015 | The repository publishes no security policy and no private disclosure channel. | posture | [EV-0036] | 06b1586 | Vulnerability intake | — | Daniel Bentes | Public | partner, customer | approved | Material because three plugins ship hooks that execute on operator machines |
| CL-0016 | No credential matching the project's own detector pattern set appears in any tracked file. | security | [EV-0037] | 06b1586 | Tracked files | Must ship with the qualification below | Daniel Bentes | Public | partner, customer | approved | A negative result over an enumerated pattern set |
| CL-0017 | The dossier plugin's post-merge documentation automation has never been executed end to end. Its components are tested; the assembled behaviour is not. | posture | [EV-0045], [EV-0009] | live | dossier | — | Daniel Bentes | Public | partner, customer | approved | Approved so that no reader takes the passing suite as proof the workflow runs |
| CL-0018 | Two open issues report that the shipped shell scripts fail under Windows and Git Bash, and neither test workflow runs on Windows. | posture | [EV-0049], [EV-0012] | live | Portability | The real scope is unmeasured (AQ-0008) | Daniel Bentes | Public | partner, customer | approved | Directly relevant to any operator not on macOS or Linux |
| CL-0019 | The marketplace holds no personal data. It has no accounts, no server, and no database. | privacy | [EV-0044] | 06b1586 | Privacy posture | Covers the marketplace itself, not the Claude Code client or the model provider | Daniel Bentes | Public | customer | approved | Follows from the same architectural fact as CL-0007 |
| CL-0020 | Hooks execute without you invoking them. They run with your user privileges, in your shell, with access to whatever you have access to. There is no sandbox. | security | [EV-0040] | 06b1586 | the hook mechanism | **Must ship adjacent to the hook inventory.** | Daniel Bentes | Public | partner, customer | approved | The single most consequential fact for an installer, and the reason the hook count is disclosed at all |
| CL-0021 | Assertion counts describe the suites, not coverage of the plugins they guard. | quality | [EV-0008], [EV-0009] | 06b1586 | the two test suites | — | Daniel Bentes | Public | partner | approved | A qualification without which CL-0005's numbers read as coverage |
| CL-0022 | This covers declared dependencies, not what the Claude Code client itself requires. | security | [EV-0041] | 06b1586 | the dependency surface | — | Daniel Bentes | Public | partner, customer | approved | A qualification on CL-0009 |
| CL-0023 | Verified on a profile that already had the marketplace registered; a first install on a clean profile has not been observed. | capability | [EV-0051], [EV-0052] | 06b1586 | the install path | — | Daniel Bentes | Public | partner, customer | approved | A qualification on CL-0003, carrying AQ-0003 |
| CL-0024 | The published `main` manifest carries seven entries; the eighth exists only on the branch this guide was produced from. | capability | [EV-0001], [EV-0054] | 06b1586 | the plugin count | — | Daniel Bentes | Public | partner, customer | approved | A qualification on CL-0001 |
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

## Required qualifications

| Claim ID | Qualification that must accompany it | Where it appears |
|---|---|---|
| CL-0014 | GitHub's repository-level licence badge is computed from the default branch, so the badge reports it only after this branch merges. | `06-public/customer-product-and-trust-guide.md`, in the same paragraph as the claim |
| CL-0016 | The scan covers tracked files against an enumerated pattern set. It proves that none of those formats appears, not that no credential exists. | `06-public/customer-product-and-trust-guide.md`, in the same paragraph as the claim |
| CL-0003 | Verified on a profile with the marketplace already registered; a first install on a clean profile has not been observed. | `06-public/technical-partner-guide.md`, adjacent to the install instructions |
| CL-0001 | The published `main` manifest carries seven entries; the eighth exists only on the branch this package was produced from. | `06-public/technical-partner-guide.md`, adjacent to the count |
| CL-0005 | Assertion counts describe the suites, not coverage of the plugins they guard. | `06-public/technical-partner-guide.md`, adjacent to the numbers |

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
| Unreleased branch state | Version 4.7.0 and the entire dossier plugin exist only on an unmerged branch [EV-0054] | A public document describing branch-only capability as shipped | Every public claim carries `Applicable version`, and CL-0001 ships with a branch qualification | Daniel Bentes |
| Security posture disclosure | CL-0013 and CL-0015 tell a reader that `main` is unprotected and that no disclosure channel exists | The public documents themselves | Accepted deliberately. Both facts are already readable from the public repository by anyone who checks, so disclosure costs nothing and withholding them would misrepresent the posture | Daniel Bentes |

## Mapping to public documents

### `06-public/technical-partner-guide.md`

| Section | Claim ID | Status |
|---|---|---|
| What this is | CL-0001, CL-0002 | approved |
| How an integration fits together | — | diagram only; the section asserts nothing in prose, so it carries no claim |
| Installing | CL-0003 | approved |
| What ships in each plugin | CL-0004, CL-0009, CL-0010 | approved |
| How it executes on your machine | CL-0007, CL-0008 | approved |
| Quality signals | CL-0005, CL-0006 | approved |
| Release history | CL-0011 | approved |
| Known limitations | CL-0013, CL-0017, CL-0018 | approved |

### `06-public/customer-product-and-trust-guide.md`

| Section | Claim ID | Status |
|---|---|---|
| What the marketplace is | CL-0001, CL-0007 | approved |
| Getting started | CL-0003 | approved |
| What runs on your machine | CL-0008, CL-0009 | approved |
| Data handling | CL-0019, CL-0016 | approved |
| Licensing | CL-0014 | approved |
| Maintenance and support | CL-0012, CL-0015 | approved |
| What we do not claim | CL-0013, CL-0017, CL-0018 | approved |

## Register summary

| Measure | Count |
|---|---|
| Total claims | 35 |
| Approved | 35 |
| Pending | 0 |
| Rejected or withdrawn | 4 |
| Approved claims resting on a state other than `V` or `C` | 0 |
| Sentences in `06-public/**` with no matching row | 0 |
