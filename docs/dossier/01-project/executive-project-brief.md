---
dossier-header: internal-v1
title: Executive Project Brief
purpose: Gives a decision-maker the shape of the project and its material risks in one read, without needing the rest of the package.
audience: Reviewer, Maintainer, Prospective contributor
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
last-verified: 2026-07-26
review-trigger: A plugin is added or removed; a release is cut; any top risk changes state
related: [01-project/product-and-domain.md, 02-architecture/system-architecture.md, 05-due-diligence/technical-due-diligence-report.md, 00-control/evidence-ledger.md]
---
# Executive Project Brief
<!-- contract: references/package-contract-01-project.md#executive-project-brief -->

## Problem, users, and intended outcome

Claude Code operators repeatedly rebuild the same scaffolding: a workflow for taking an issue to a merged pull request, a method for analysing content, a discipline for documenting what a system actually does. Each rebuild is private, unversioned, and lost when the session ends.

The Synapti Plugin Marketplace packages that scaffolding as installable plugins. Eight are published [EV-0001]: workflow harnesses (`flow`, `gh-workflow`), analysis harnesses (`decipon`, `context-ledger`), organizational-design and agent-specification kits (`ai-first-org-design-kit`, `agent-capability-standard`), prompt tooling (`prompt-decorators`), and documentation automation (`dossier`).

The intended outcome is that an operator installs one command and inherits a worked-out method — including its safety rails. The single largest thing this package cannot tell you is whether that outcome is achieved: **no install or usage telemetry exists for plugin marketplaces, and the plugins emit none by design** (AQ-0004) [EV-0044].

## Lifecycle stage and actual scope

| Field | Value | Evidence |
|---|---|---|
| Lifecycle stage | production for the 7 published plugins; pre-production for `dossier`, which exists only on an unmerged branch | [EV-0032], [EV-0054] |
| In production since | First commit 2025-12-19; 57 tags published; latest release `v4.6.2` on 2026-05-29 | [EV-0032], [EV-0034] |
| Actual deployed scope | A git repository the Claude Code client clones. No service, no hosting, no build step. 112 skills, 61 commands, 29 agents, 26 helper scripts, 16 hook scripts | [EV-0004]–[EV-0007], [EV-0040], [EV-0044] |
| Users or tenants served | **unknown.** No telemetry exists. The one observation available: 6 of this marketplace's plugins are installed on the assessment machine, which is the maintainer's own | [EV-0052], AQ-0004 |

## Capabilities: implemented versus planned

| Capability | State | Evidence | Note |
|---|---|---|---|
| Plugin discovery and installation | implemented | [EV-0051], [EV-0052] | Verified against the Claude Code client's own state files on one machine |
| flow — GitHub workflow harness | implemented | [EV-0004], [EV-0008] | 32 skills, 23 commands, 9 agents, 12 hook scripts, 1022 passing assertions |
| dossier — evidence-first documentation | implemented, unreleased | [EV-0009] | 1241 passing assertions; produced this package |
| dossier — post-merge documentation automation | **built, never executed** | [EV-0045] | Its parts pass structural tests; the assembled workflow has never run (AQ-0002) |
| gh-workflow, decipon, context-ledger, ai-first-org-design-kit | implemented, **untested** | [EV-0010] | 5 of 7 in-tree plugins ship no test suite |
| agent-capability-standard | implemented, tested upstream | [EV-0011], [EV-0031] | Pinned 2 commits past the advertised `v1.2.0` |
| prompt-decorators | published, **unverified from here** | [EV-0030] | External source pinned to the floating ref `main` (AQ-0005) |
| Desktop skill packaging | implemented | [EV-0012] | ZIPs attached to each published release |
| Windows support | **not implemented** | [EV-0049] | Two open issues report failures; no CI runs on Windows |
| Behavioural evaluation of any prompt | **not implemented** | [EV-0008], [EV-0009] | No evaluation suite exists for a product made of prompts |

## Architecture and operating model

| Aspect | Summary | Canonical source |
|---|---|---|
| System shape | A manifest plus a content tree. No runtime. All execution happens in the operator's own session, on their machine, with their privileges. The one boundary that matters is install-time: 16 hook scripts run on lifecycle events the operator never invokes | `02-architecture/system-architecture.md` |
| Deployment and environments | One environment. `main` is production, and a push is the deploy. No build step, no promotion, no staging | `02-architecture/infrastructure-and-deployment.md` |
| Delivery model | 2,263 passing assertions across 2 of 7 in-tree plugins, run by 2 CI workflows — **both advisory.** No branch protection, no rulesets, no required checks | `03-assurance/testing-quality-and-delivery.md` |
| Operating model | Nothing to operate. No on-call, no incidents, no telemetry. Failures are distribution failures, detected only when an operator files an issue | `04-operating/operations-and-incident-response.md` |

## Metrics

| Metric | Value | Window | Environment | State | Evidence |
|---|---|---|---|---|---|
| Published plugins | 8 (7 on `main`, 8 on this branch) | live | production | V | [EV-0001], [EV-0054] |
| Skills / commands / agents | 112 / 61 / 29 | 06b1586 | repository | V | [EV-0004]–[EV-0006] |
| Test assertions passing | 2,212 across 2 plugins, 0 failures | 2026-07-26 | macOS 25.5 | V | [EV-0008], [EV-0009] |
| In-tree plugins with a test suite | 2 of 7 | 06b1586 | repository | V | [EV-0010] |
| Commits on the assessed branch | 193 | 2025-12-19 → 2026-07-26 | production | V | [EV-0034] |
| Merged pull requests | 62 | full history | production | V | [EV-0050] |
| Releases published | 57 tags; latest `v4.6.2` | live | production | V | [EV-0032] |
| Contributors | 1 | full history, all refs | repository | V | [EV-0035] |
| Open issues | 2, both Windows portability | live | production | V | [EV-0049] |
| Installs, active users, usage | **unknown — unmeasurable from here** | — | — | U | AQ-0004 |
| Incidents, change failure rate, defect escape rate | **unknown — no incident record exists** | — | — | U | [EV-0036] |

## Principal dependencies and constraints

| Dependency or constraint | Type | Why it matters | Replaceability | Evidence |
|---|---|---|---|---|
| The Claude Code client | technical | Resolves, installs, and executes every artifact. Its manifest schema, cache layout, and hook contract are external and can change without notice | **none** | [EV-0043] |
| GitHub | technical | Hosting, distribution, releases, and CI | low | [EV-0051] |
| Single maintainer | organizational | No release, merge, security response, or fix happens without one person, and no component has a backup owner | **none** | [EV-0035] |
| Apache-2.0, effective 2026-07-26 | legal | The repository carried no `LICENSE` file before that date while the README asserted MIT. Every declaration now matches the file | resolved | [EV-0019], [EV-0021] |
| `synaptiai/prompt-decorators` at `ref: main` | technical | Changes what installers receive under this marketplace's name, with no commit or record here | immediate — pin a tag | [EV-0030] |
| `pyyaml>=6.0` | technical | The only declared third-party runtime dependency in the whole repository | high | [EV-0041] |
| No spend control on induced model usage | commercial | The project pays nothing; operators pay for whatever the plugins induce, unmeasured | none | [EV-0044] |

## Strengths

| Strength | Why it is material | Evidence |
|---|---|---|
| Everything executable is readable plain text | 26 helper scripts and 16 hook scripts, no binaries, no bundles. An installer can audit before trusting — which matters more here than usual, because hooks run unprompted | [EV-0007], [EV-0044] |
| Substantial structural testing where it exists | 2,263 assertions covering frontmatter shape, cross-reference resolution, bash 3.2 portability, and cross-artifact invariants. Markdown has no compiler; these suites substitute for one | [EV-0008], [EV-0009] |
| Safety rails are restrictive by default | flow's hooks block destructive commands, force-pushes, and secret writes. dossier's action ceiling defaults every capability to `false` except reading source | [EV-0038], [EV-0039] |
| Tests catch real defects | The destructive-command hook blocked two `rm -rf` invocations during this project's own development, and dossier's own suite surfaced a settings-cascade defect before release | [EV-0038], [EV-0009] |
| Machine-readable version consistency holds | All 7 in-tree plugins agree with their manifest entries, verified directly | [EV-0026] |
| No credentials anywhere in tracked files | Verified with the project's own detector pattern set | [EV-0037] |

## Top risks, unknowns, and near-term decisions

| Item | Kind | Impact | Owner | Evidence or register ID |
|---|---|---|---|---|
| Nothing gates `main` | risk | Any change — mistaken or malicious — reaches every installer's machine as executable code, with no check having to pass | Daniel Bentes | [EV-0016], [EV-0017] |
| dossier's headline capability has never executed | risk | A published plugin whose central claim rests on unit tests of its parts | Daniel Bentes | AQ-0002 |
| Bus factor of one | risk | No release, merge, security response, or fix is possible without one person | Daniel Bentes | [EV-0035] |
| No security disclosure channel | risk | A researcher who finds a flaw in a hook that runs on operator machines must disclose publicly or not at all | Daniel Bentes | [EV-0036] |
| Shell is not statically analysed | risk | The entire executable surface on operator machines has no automated security analysis; CodeQL's presence makes this easy to miss | Daniel Bentes | [EV-0012] |
| The README misstates plugin count and two versions, and omits dossier | risk | The storefront is the first thing a prospective operator reads, and four of its facts are wrong today | Daniel Bentes | [EV-0022]–[EV-0025] |
| Whether the product is used at all | unknown | Every quality decision is made without knowing whether it matters | — | AQ-0004 |
| Windows portability scope | unknown | Two operators have reported failures; the real scope is unmeasured | Daniel Bentes | AQ-0008 |
| Prompt efficacy | unknown | This is a prompt-engineering product with no evaluation of whether its prompts help | Daniel Bentes | [EV-0008], [EV-0009] |
| Whether dossier may be described as working before it has been observed working | decision | Blocks any public claim about the automation | Daniel Bentes | AQ-0002 |

## Documentation confidence

| Grouping | Content |
|---|---|
| Verified facts | 55 of 56 evidence rows are `V` or `C`. Artifact counts, test results, workflow definitions, repository settings, licence detection, release history, contributor count, dependency surface, install state, and version agreement were each established by direct read or executed command |
| Reported assertions, not independently verified | The `prompt-decorators` entry's description of its own contents (AQ-0005); the `agent-capability-standard` version label, where the pinned tree is 2 commits past the tag it advertises (AQ-0006); the Windows failure reports in issues #100 and #130 (AQ-0008) |
| Inferences | One row: that distribution is a git read rather than a registry publish [EV-0043], reasoned from the absence of any registry manifest and any publish step, with the chain stated |
| Unknowns | Whether anyone uses the product; whether the dossier automation works; whether a clean-profile install succeeds; whether the submodule's Python suite passes; the Windows portability scope; whether any prompt improves model behaviour |

| Measure | Value |
|---|---|
| Overall confidence | **high**, for what the package covers |
| Basis for that rating | 56 evidence rows, of which 55 are `V` or `C` and 1 is `I` with its chain stated. 30 of 32 planned checks were executed with retained output; the 2 that were not are named, with the reason and the open question each is recorded under. Every material claim traces to a row |
| Largest source of residual uncertainty | The package documents artifacts thoroughly and outcomes not at all. Nothing here establishes that any plugin helps anyone, because nothing can: there is no telemetry, no evaluation suite, and no user research. A reader should treat every quality signal in this package as a property of the code, never of its effect |
| Package status | Complete against its contract, and **NOT-RELEASABLE** against the release gate. The licence contradiction that failed the gate on round 1 is resolved; one open blocking question remains (AQ-0002), alongside the score and dimension minima. Recorded rather than worked around, which is the intended behaviour |
