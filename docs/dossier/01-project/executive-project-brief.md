---
dossier-header: internal-v1
title: Executive Project Brief
purpose: Gives a decision-maker the shape of the project and its material risks in one read, without needing the rest of the package.
audience: Reviewer, Maintainer, Prospective contributor
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A plugin is added or removed; a release is cut; any top risk changes state
related: [01-project/product-and-domain.md, 02-architecture/system-architecture.md, 04-operating/decisions-technical-debt-and-risks.md, 05-due-diligence/technical-due-diligence-report.md, 00-control/evidence-ledger.md]
---
# Executive Project Brief
<!-- contract: references/package-contract-01-project.md#executive-project-brief -->

## Where these facts live

Every claim here summarises a row in `00-control/evidence-ledger.md`, which stays canonical when this brief goes stale. Entity names and owners come from `00-control/terminology-and-ownership.md`. Unresolved items carry an `AQ-` or `CT-` identifier and live in `00-control/assumptions-questions-and-contradictions.md`.

Several rows cited here were observed by the session operator running commands the engagement's action ceiling denies to dispatched agents (AQ-0012). Each such row says so in the ledger.

## Problem, users, and intended outcome

Claude Code operators rebuild the same scaffolding in every session: a path from issue to merged pull request, a method for analysis, a documentation discipline. Each rebuild is private and lost when the session ends. The Synapti Plugin Marketplace packages that scaffolding as installable plugins, published as 8 manifest entries at marketplace version 4.10.0 [EV-0057].

The user is the operator: one person running Claude Code who installs a plugin. The project has no accounts, no tenants and no server-side identity, because it runs no process of its own [EV-0044]. The intended outcome is that an operator installs one command and inherits a worked-out method together with its safety rails.

Unknown: whether that outcome is reached for anyone other than the maintainer. No install or usage telemetry exists for plugin marketplaces, and the plugins emit none (AQ-0004). The one observation available is that 6 of this marketplace's plugins were installed on the maintainer's own machine on 2026-07-26 [EV-0052].

## Lifecycle stage and actual scope

| Field | Value | Evidence |
|---|---|---|
| Lifecycle stage | Production. All 8 published entries, including `dossier` at 1.2.0 and `flow` at 3.3.0, are served from `main` at manifest version 4.10.0 | [EV-0057], [EV-0065], [EV-0163] |
| Basis for that stage | Two releases published on 2026-09-10, a public repository with a detected licence, and an observed install — not the presence of a production configuration file | [EV-0066], [EV-0132], [EV-0052] |
| Latest releases | v4.9.0 at 07:18Z and v4.10.0 at 07:48Z, both on 2026-09-10 | [EV-0066] |
| Actual deployed scope | A public git repository the Claude Code client clones. No service, no hosting, no build step. 71 skills, 61 commands, 29 agents and 40 plugin `bin/` scripts in tree | [EV-0162], [EV-0044] |
| Install-time surface | 19 hook scripts across 2 tracked manifests — 14 in `flow` and 5 in `dossier` at `e104483` | [EV-0162], [EV-0129] |
| Users or tenants served | Unknown. No telemetry exists and none can be collected from here (AQ-0004) | [EV-0044] |

## Capabilities: implemented versus planned

| Capability | State | Evidence | Note |
|---|---|---|---|
| Plugin discovery and installation | implemented | [EV-0051], [EV-0052] | Observed against the client's own state files on one machine on 2026-07-26. A cold-profile install stays unobserved (AQ-0003) |
| `flow` — GitHub workflow harness | implemented | [EV-0162], [EV-0098] | 32 skills, 23 commands, 9 agents. 2336 passing assertions, 0 failures |
| `dossier` — evidence-first documentation | implemented, published at 1.2.0 | [EV-0065], [EV-0107] | 1951 passing assertions, 0 failures. This package is its output |
| `dossier` — post-merge documentation automation | built, never executed end to end | [EV-0045], [EV-0123] | Its parts pass structural tests. No docs-refresh workflow is installed in this repository (AQ-0002, blocking) |
| `gh-workflow`, `decipon`, `context-ledger`, `ai-first-org-design-kit` | implemented, no test suite | [EV-0010], [EV-0162] | At 2026-07-26 only 2 of the then 7 in-tree plugins carried a shell suite |
| `agent-capability-standard` | implemented, external source | [EV-0058], [EV-0127] | A `github` source pinned to sha `9e2f65b`, whose tree reports the advertised 1.2.0. What separates that sha from tag `v1.2.0` is unexamined (AQ-0006) |
| `prompt-decorators` | published, unverified from here | [EV-0058], [EV-0127] | A `git-subdir` source pinned to sha `9c792fe`. Its contents have not been inspected (AQ-0005) |
| Marketplace manifest version checking | implemented | [EV-0080], [EV-0081], [EV-0127] | 8 entries checked, 0 failed, 0 unverifiable, both external sources read at their pinned sha |
| Desktop skill packaging | implemented | [EV-0133] | Runs on release publication and uploads with `--clobber`. Whether archives are reproducible is unknown (AQ-0021) |
| Behavioural evaluation of prompt output | implemented for `flow` only | [EV-0095] | 4 cases with hidden tests and trap variants. Nothing in CI runs it, and no other plugin has one (AQ-0024) |
| Windows support | not implemented | [EV-0049] | Two issues open at 2026-07-26 report Git Bash failures, and no CI job runs on Windows (AQ-0008) |
| Portability to any non-Claude-Code client | not established | — | No row shows any artifact loading under a second client. Treat lock-in as total (AQ-0023) |

No ledger row records a planned capability. The one pending decision, whether a release carrying the flow fix is cut, is in the decisions table below.

## Architecture and operating model

| Aspect | Summary | Canonical source |
|---|---|---|
| System shape | A manifest plus a content tree, with no runtime of its own. Everything executes inside the operator's session, on their machine, with their privileges [EV-0044]. The boundary that matters is install-time, because 19 hook scripts run on lifecycle events the operator never invokes [EV-0162], [EV-0129]. Unknown: what delivery and blocking semantics the client applies to a hook (AQ-0025) | `02-architecture/system-architecture.md` |
| Deployment | One environment. `main` is production and a push is the deploy. Inferred: distribution is a git read performed by the client rather than a registry publish, reasoned from the absence of any registry manifest or publish step [EV-0043, I] | `02-architecture/infrastructure-and-deployment.md` |
| Delivery model | 4287 passing assertions and 0 failures across the 2 plugins that carry suites, run on macOS 25.6 under `/bin/bash` 3.2.57 [EV-0098], [EV-0107]. Every Actions run across this refresh's range concluded success on `ubuntu-latest` [EV-0126]. All 5 workflows are advisory, because `main` carries no branch protection, no rulesets and no required checks [EV-0123], [EV-0131] | `03-assurance/testing-quality-and-delivery.md` |
| Static analysis | CodeQL analyses `actions` and `python` only, reporting 0 results and 0 open alerts [EV-0134], [EV-0140]. shellcheck covers `dossier`'s scripts in one workflow, and nothing lints `flow`'s [EV-0165], AQ-0019 | `03-assurance/security-privacy-and-compliance.md` |
| Operating model | Nothing to operate. No on-call, no incident record and no telemetry [EV-0044]. A failure is a distribution failure, and the only intake is a public issue, because no `SECURITY.md` existed at 2026-07-26 [EV-0036] | `04-operating/operations-and-incident-response.md` |

## Metrics

| Metric | Value | Window | Environment | State | Evidence |
|---|---|---|---|---|---|
| Published plugin entries | 8, at manifest version 4.10.0 | 2026-09-10 | production | V | [EV-0057] |
| Releases published | v4.9.0 and v4.10.0, both 2026-09-10 | 2026-09-10 | production | V | [EV-0066] |
| Skills / commands / agents in tree | 71 / 61 / 29 | 7ee4923 | repository | V | [EV-0162] |
| Plugin `bin/` scripts | 40, of which 20 in `flow` and 20 in `dossier` | 7ee4923 | repository | V | [EV-0162] |
| Test assertions passing | 4287 across 2 plugins, 0 failures | 2026-09-10 | macOS 25.6, `/bin/bash` 3.2.57, at `af6e632` | V | [EV-0098], [EV-0107] |
| Linux CI outcome | success for every commit this refresh added to `main` | 2026-09-10 | `ubuntu-latest` | V | [EV-0126] |
| Commits on `main` | 214, all under one author identity | full history to 7ee4923 | production | V | [EV-0163] |
| Author identities across all refs | 3, of which 2 appear only off `main` | full history | repository | V | [EV-0163], [EV-0164] |
| Tracked decision records | 21 | 7ee4923 | repository | V | [EV-0169] |
| Actions secrets held | 0 | 2026-09-10 | production | V | [EV-0131] |
| Dependency vulnerabilities | Unknown — no scan artifact exists anywhere | — | — | U | [EV-0121] |
| Installs, active users, usage | Unknown — unmeasurable from here | — | — | U | AQ-0004 |
| Incidents, change failure rate, defect escape rate | Unknown — no incident record exists | — | — | U | [EV-0036] |

## Principal dependencies and constraints

| Dependency or constraint | Type | Why it matters | Replaceability | Evidence |
|---|---|---|---|---|
| The Claude Code plugin client | technical | Resolves, installs and executes every artifact. Its manifest schema, cache layout and hook contract are external and can change without notice | none | [EV-0043, I], [EV-0044], AQ-0023 |
| GitHub | technical | Hosting, distribution, releases, and the only execution environment the project itself operates | low | [EV-0123], [EV-0132] |
| Single maintainer | organizational | 214 commits on `main` under one identity, and no component has a backup owner. No release, merge or security response happens without that person | none | [EV-0163] |
| Two externally sourced entries | technical | `agent-capability-standard` and `prompt-decorators` ship under this marketplace's name from other repositories. Both are sha-pinned, and CI checks both at their pin | moderate | [EV-0058], [EV-0127], AQ-0005 |
| PyYAML | technical | flow's journal, FlowRun state and FlowGoal machinery require it at runtime, and no file in the repository declares it for an operator installing the plugin [EV-0186], [EV-0187], [EV-0189]. A SessionEnd hook reaches that requirement without the operator invoking anything [EV-0189] | high | [EV-0186], [EV-0187], [EV-0189] |
| Apache-2.0 | legal | GitHub now detects Apache-2.0 for the repository, and the plugin manifests, marketplace entries and README all match the file | resolved | [EV-0132], [EV-0021] |
| No spend control on induced model usage | commercial | The project pays nothing. Operators pay for whatever the plugins induce, unmeasured | none | [EV-0044], AQ-0004 |

## Strengths

| Strength | Why it is material | Evidence |
|---|---|---|
| Everything executable is readable plain text | 40 plugin scripts and 19 hook scripts, no binaries and no bundles. An installer can audit before trusting, which matters here because hooks run unprompted | [EV-0162], [EV-0129], [EV-0044] |
| Test coverage where it exists is substantial and green on both platforms | 4287 assertions with 0 failures on macOS, and every Actions run in this range concluded success on `ubuntu-latest` | [EV-0098], [EV-0107], [EV-0126] |
| Safety rails are restrictive by default and tested against real attack shapes | With every action denied, the ceiling hook rejects `find -exec` wrappers, disguised spellings and normalization hazards. Three bash expansion spellings are still permitted, and that limit is pinned by its own test | [EV-0149], [EV-0150], [EV-0152], [EV-0153] |
| Harness defects are closed with executed proof rather than a claim | The mktemp-guard suite passes 14 of 14 assertions, including a static lint over every test file for the shape that swallowed the guard | [EV-0147] |
| Version consistency is machine-checked in CI | 8 entries checked, 0 failed, 0 unverifiable, including both external sources at their pinned sha | [EV-0064], [EV-0127] |
| Static analysis reports nothing within its configured scope | CodeQL uploaded an analysis at each of the three merge commits, each with 0 results, against 0 open alerts | [EV-0134], [EV-0140] |
| No credential in tracked files | Verified with the project's own detector pattern set on 2026-07-26. Not re-checked since, which is recorded as AQ-0022 | [EV-0037] |

## Top risks, unknowns, and near-term decisions

| Item | Kind | Impact | Owner | Evidence or register ID |
|---|---|---|---|---|
| A fixed defect is in both published releases | risk | v4.9.0 and v4.10.0 carry the pre-fix `record-quality-run.sh` and `flow-quality-ledger.sh`, because the fix merged at 10:39Z after both tags. What an operator on macOS experiences at v4.10.0 is not established | Daniel Bentes | [EV-0144] |
| Key-person concentration | risk | 214 commits on `main` under one identity, every component owned by that one person, and no backup owner anywhere. A wider read of all refs returns 3 identities, but the other 2 sit off `main` and 3 of their commits are a test-suite leak | Daniel Bentes | [EV-0163], [EV-0164] |
| Nothing gates `main` | risk | Any change, mistaken or malicious, reaches installers as executable code with no check having to pass. No branch protection, no rulesets, 5 advisory workflows | Daniel Bentes | [EV-0131], [EV-0123] |
| The dependency surface has never been scanned | risk | No SARIF, osv-scanner or Dependabot artifact exists in the repository. This is the absence of a scan, not a clean bill of health | Daniel Bentes | [EV-0121] |
| The headline automation has never run end to end | risk | A plugin published at 1.2.0 whose central capability rests on unit tests of its parts, with no docs-refresh workflow installed here | Daniel Bentes | [EV-0045], [EV-0123], AQ-0002 |
| No security disclosure channel | risk | A researcher finding a flaw in a hook that runs on operator machines must disclose publicly. Observed 2026-07-26 and not re-checked | Daniel Bentes | [EV-0036], AQ-0022 |
| `flow`'s shell is unlinted | risk | shellcheck covers `dossier` only, while `flow`'s hooks run as blocking calls on a contributor's machine | Daniel Bentes | [EV-0165], AQ-0019 |
| The test suite writes into the repository | risk | The `flow` suite leaked two branches carrying 3 commits under a test identity. The branches were deleted, and the suite defect is not fixed | Daniel Bentes | [EV-0164] |
| Whether the product is used at all | unknown | Every quality decision is made without knowing whether it reaches anyone | — | AQ-0004 |
| Whether a hook exit actually blocks a tool call | unknown | The package's entire control-point argument rests on it, and no evidence establishes it | Daniel Bentes | AQ-0025 |
| Windows portability scope | unknown | Two operators reported failures at 2026-07-26, and the real scope is unmeasured | Daniel Bentes | [EV-0049], AQ-0008 |
| Prompt efficacy outside `flow` | unknown | `flow`'s harness is the only behavioural evaluation of prompt output in the marketplace | Daniel Bentes | [EV-0095], AQ-0024 |
| README currency at HEAD | unknown | Three README drifts were corrected at 7ee4923. The plugin-count badge, read as 6 against a manifest publishing 8 on 2026-07-26, is not re-checked by any row | Daniel Bentes | [EV-0170], [EV-0022] |
| Whether to cut a patch release carrying the flow fix | decision | Until a release ships that fix, the corrected scripts exist on `main` only | Daniel Bentes | [EV-0144], [EV-0143] |
| Whether `dossier` may be described as working before it has been observed working | decision | Blocks any public claim about the automation | Daniel Bentes | AQ-0002 |
| Whether read-only GitHub queries may run inside the action ceiling | decision | Several rows in this package were observed outside the ceiling by the session operator | Daniel Bentes | AQ-0012 |

## Documentation confidence

| Grouping | Content |
|---|---|
| Verified facts | 46 of the 47 evidence rows this brief cites are `V`, and 1 is `I`. Release state, artifact census, test results, Linux CI outcome, repository settings, licence detection, commit identity and manifest version consistency were each established by direct read or executed command |
| Reported assertions, not independently verified | None carry decision weight here. The two open questions the brief leans on for external content are the `prompt-decorators` description (AQ-0005) and the gap between the pinned `agent-capability-standard` sha and its tag (AQ-0006) |
| Inferences | One row: that distribution is a git read by the client rather than a registry publish [EV-0043, I], reasoned from the absence of any registry manifest and any publish step |
| Unknowns | Whether anyone uses the product (AQ-0004), whether the post-merge automation works (AQ-0002), whether a cold-profile install succeeds (AQ-0003), the dependency-vulnerability surface [EV-0121], hook blocking semantics (AQ-0025), the Windows scope (AQ-0008), and prompt efficacy outside `flow` (AQ-0024) |

| Measure | Value |
|---|---|
| Overall confidence | High for artifacts, repository state and test results. Low for outcomes |
| Basis for that rating | Every material claim above traces to a ledger row, and 46 of the 47 rows are `V`. Two suites and the Linux CI outcome were observed rather than described |
| Largest source of residual uncertainty | The package documents artifacts thoroughly and outcomes not at all. There is no telemetry, no cross-plugin evaluation and no user research. Treat every quality signal here as a property of the code, never of its effect |
| Evidence that would move the assessment most | One observed end-to-end run of the post-merge automation (AQ-0002), one dependency scan [EV-0121], and one named backup owner [EV-0163] |
| Package status | The last recorded release-gate result is FAIL, dated 2026-07-26 [EV-0089], and no verification round or gate run has been recorded since [EV-0090]. The current verdict is not established by this document |
