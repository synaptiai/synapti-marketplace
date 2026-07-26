---
dossier-header: internal-v1
title: Product and Domain
purpose: Establishes who the product serves, what it promises them, and where its stated behaviour and its implemented behaviour diverge.
audience: Maintainer, Reviewer, Prospective contributor
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d8c10fa
last-verified: 2026-07-26
review-trigger: A plugin is added or removed; a plugin's stated purpose or description changes; the intended audience changes
related: [01-project/executive-project-brief.md, 00-control/terminology-and-ownership.md, 02-architecture/components-and-codebase.md, 04-operating/decisions-technical-debt-and-risks.md]
---
# Product and Domain
<!-- contract: references/package-contract-01-project.md#product-and-domain -->

## Vision, mission, goals, and non-goals

The repository states its own purpose in one line: *"Agentic harnesses for Claude Code — specialized AI agents for complex analytical tasks"* (`README.md`). The manifest states it more plainly: *"Synapti plugin marketplace"* [EV-0002].

Neither is a vision statement, and no document in the repository contains one. What can be established from evidence is the shape of the thing: a curated distribution of eight worked-out methods, each installable in one command, each carrying its own safety rails.

| Goal | Measure of success | Evidence |
|---|---|---|
| Make reusable Claude Code methods installable | 8 published plugin entries resolvable by the client | V — [EV-0001], [EV-0051] |
| Ship methods that are safe to run unattended | 16 hook scripts, of which flow's three are purely restrictive; dossier's action ceiling defaults to all-false except reading source | V — [EV-0038], [EV-0039] |
| Ship methods that are auditable before installing | Every executable artifact is plain shell or Markdown; no binaries, no bundles | V — [EV-0007], [EV-0044] |
| Keep the artifacts correct | 2,212 passing assertions across 2 plugins | V, partial — covers 2 of 7 in-tree plugins [EV-0008], [EV-0009], [EV-0010] |
| **Whether operators are helped** | no measure exists | **U** — no telemetry, no evaluation suite, no user research (AQ-0004) |

| Non-goal | Why excluded | Evidence |
|---|---|---|
| Operating a service | The product is content the client executes locally. Nothing is hosted | [EV-0044] |
| Collecting usage data | No endpoint exists to collect to, and none is proposed anywhere in the repository | [EV-0044] |
| Windows support | Not excluded by decision — **excluded by omission.** Issue #100 proposes a marketplace policy on it and remains open | [EV-0049] |
| Charging for plugins | No pricing, entitlement, licence check, or payment path exists anywhere | [EV-0044] |
| Supporting Claude clients other than Claude Code | The only exception is the desktop-skill packaging path, which strips Claude Code frontmatter for Claude Desktop | [EV-0012] |

The Windows row is the honest one. A non-goal reached by omission behaves the same as a decision for the operator who hits it, but only a decision can be communicated in advance — and this one has not been.

## Actors

| Actor | Class | What they need from the product | Access path | Evidence |
|---|---|---|---|---|
| Installing operator | primary user | To find a plugin that fits, install it, and trust what it does on their machine | `claude plugin marketplace add` then `claude plugin install` | [EV-0051], [EV-0052] |
| Evaluating operator | primary user | To decide whether to install, from the README and the repository alone | Reading `README.md` and the plugin trees | [EV-0022], [EV-0023] |
| Contributor | secondary | A stated process, a review path, and a way to know their change is correct | GitHub pull request. **No `CONTRIBUTING.md`, no CODEOWNERS, no template, and no external contribution has ever been merged** | [EV-0036], AQ-0007 |
| Security researcher | secondary | A private channel to report a flaw in code that runs on other people's machines | **None exists.** A public issue is the only option | [EV-0036] |
| Maintainer | operator | To ship changes without breaking installers | Direct write access, ungated | [EV-0016], [EV-0035] |
| Claude Desktop user | tertiary | Skills usable outside Claude Code | Downloading ZIP assets from a release | [EV-0012] |
| Claude Code client | system | A manifest it can parse and sources it can resolve | git clone | [EV-0043] |

## Jobs to be done and user journeys

| Job | Actor | Journey | Success criterion | Evidence |
|---|---|---|---|---|
| "Give me a disciplined GitHub workflow" | Installing operator | Add marketplace → install `flow` → use `/flow:start`, `/flow:pr`, `/flow:review`, `/flow:merge` | The workflow runs and its hooks block unsafe actions | V for install [EV-0052]; **U for outcome** |
| "Stop me doing something destructive" | Installing operator | Install `flow` → a `PreToolUse` hook blocks the tool call | Destructive commands are blocked | V — observed blocking two `rm -rf` invocations during this project's own development [EV-0038] |
| "Document what this project actually does" | Installing operator | Install `dossier` → `/dossier:init` → `/dossier:baseline` → `/dossier:audit` → `/dossier:gate` | An evidence-cited package with an honest gate verdict | V — this package is the artifact [EV-0047], [EV-0048] |
| "Keep documentation current after merges" | Installing operator | `/dossier:setup` scaffolds a workflow → a merge triggers a documentation pull request | Documentation refreshes without being asked | **U — never executed** (AQ-0002) [EV-0045] |
| "Analyse content for manipulation" | Installing operator | Install `decipon` → run its commands | An NCI analysis | R — asserted by the plugin's description; no test suite exists [EV-0010] |
| "Evaluate before installing" | Evaluating operator | Read `README.md` | An accurate picture of what is available | **Fails today** — the badge says 6 plugins where 8 exist, two versions are stale, and dossier is absent entirely [EV-0022]–[EV-0025] |
| "Contribute a fix" | Contributor | Fork, branch, pull request | Merged | **U — never exercised by anyone but the maintainer** (AQ-0007) |
| "Report a vulnerability privately" | Security researcher | — | — | **Not supported** [EV-0036] |

Two journeys are known to be broken rather than merely unverified: evaluation-before-install, which reads a stale storefront, and private vulnerability reporting, which has no path at all.

## Feature and capability map

| Capability | State | Actor | Entry point | Evidence | Note |
|---|---|---|---|---|---|
| Plugin discovery | implemented | operator | `marketplace.json` | [EV-0001] | 8 entries; nothing validates the manifest |
| Plugin install | implemented | operator | `claude plugin install` | [EV-0052] | Verified against the client's own state |
| Auto-update | implemented, client-owned | operator | client | [EV-0051] | `autoUpdate: true` observed. Changes propagate without the operator acting |
| GitHub workflow harness | implemented | operator | `/flow:*` — 23 commands | [EV-0004], [EV-0008] | Tested: 1022 assertions |
| Legacy workflow harness | implemented, superseded | operator | `/gh-*` — 14 commands | [EV-0004] | No deprecation notice; `.claude/CLAUDE.md` says enable only one of the two |
| Evidence-first documentation | implemented | operator | `/dossier:*` — 9 commands | [EV-0009] | Tested: 1190 assertions. Unreleased |
| Post-merge doc automation | built, unexecuted | operator | `/dossier:setup` | [EV-0045] | AQ-0002 |
| Content analysis | implemented | operator | `decipon` commands | [EV-0004] | Untested |
| Product-development ledger | implemented | operator | `context-ledger` commands | [EV-0004] | Untested |
| Organizational design | implemented | operator | 15 skills | [EV-0027] | Untested; description says fourteen |
| Agent capability specification | implemented | operator | 42 skills | [EV-0031] | Submodule, pinned past its advertised tag |
| Prompt decoration | published, unverified here | operator | `prompt-decorators` | [EV-0030] | External source, floating ref |
| Desktop skill export | implemented | Desktop user | Release assets | [EV-0012] | Built on every published release |
| Safety hooks | implemented | operator, passively | lifecycle events | [EV-0038], [EV-0040] | 3 of 8 plugins |

## Business model and commercial constraints

| Plan or entitlement | What it grants | Technical enforcement point | Evidence |
|---|---|---|---|
| **None.** There is no plan, tier, entitlement, licence key, or payment path anywhere in the repository | Everything, to everyone | none — and none exists to enforce | [EV-0044] |

The commercial constraints that do apply are indirect and worth stating: the project pays nothing to operate, and it induces unmeasured model-usage cost in every operator's own account [EV-0044]. The only place that induced cost could land on a *repository* rather than a person is dossier's post-merge automation, which caps turns per run but cannot cap spend — and has never run [EV-0045].

## Product boundaries

| Boundary | In scope | Explicitly out of scope | Evidence |
|---|---|---|---|
| Execution | Content the Claude Code client loads and executes locally | Anything hosted, served, or scheduled by this project | [EV-0044] |
| Platform | macOS and Linux shells, bash 3.2 and later | Windows — **by omission, not by decision** | [EV-0008], [EV-0049] |
| Client | Claude Code, plus a packaged export path for Claude Desktop | Other agent clients | [EV-0012] |
| Data | None held, none transmitted, none collected | All data handling | [EV-0044] |
| Plugin contents | The 6 in-tree plugin trees | `prompt-decorators`, whose contents live elsewhere and were never inspected (AQ-0005); the submodule's upstream history beyond the pinned commit (AQ-0006) | [EV-0030], [EV-0031] |

## Domain model

| Entity | Definition | Owns | Lifecycle | Canonical name (`TM-####`) | Evidence |
|---|---|---|---|---|---|
| Marketplace | The manifest a client reads to discover plugins | 8 plugin entries | Versioned by `metadata.version` plus a git tag | TM-0001 | [EV-0001] |
| Plugin | One installable unit with its own manifest | Its skills, commands, agents, hooks, and scripts | semver in two files that must agree | TM-0002 | [EV-0026] |
| Skill | One `SKILL.md` — the unit of method | Its own frontmatter and body | Versioned with its plugin | TM-0003 | [EV-0004] |
| Command | One Markdown file invoked as `/plugin:name` | Its declared skills and phases | Versioned with its plugin | TM-0004 | [EV-0005] |
| Agent | A subagent definition with a tool and skill allowlist | Its own context when dispatched | Versioned with its plugin | TM-0005 | [EV-0006] |
| Hook | An event-to-script binding executed by the client | Nothing; it inspects and permits or blocks | Versioned with its plugin | TM-0006 | [EV-0040] |
| Operator | The person running Claude Code | Their own machine and session | Not modelled — the product has no notion of identity | TM-0009 | [EV-0044] |

| Rule or invariant | Enforced where | Enforcement kind | What breaks if violated | Evidence |
|---|---|---|---|---|
| A plugin's version equals its marketplace entry's version | nowhere | **convention only** | An operator installs a version different from the one advertised | [EV-0026] |
| A skill directory contains a `SKILL.md` | flow and dossier suites, for themselves | test | Counting directories overstates the skill count — the origin of the flow README's off-by-one | [EV-0029] |
| A command's declared skills all resolve on disk | flow and dossier suites | test | A command references a skill that does not exist | [EV-0009] |
| Public documents contain only approved claims | dossier's claim register and `dossier-claim-scan.sh` | test plus runtime hook | Unapproved claims reach an external reader | [EV-0039] |
| Shell scripts run on bash 3.2 | flow and dossier suites | test | Scripts break on the maintainer's own platform | [EV-0008], [EV-0009] |
| Every executable ships with the executable bit | flow and dossier suites, plus `dossier-tests.yml` | test | The client cannot run the hook | [EV-0009] |
| The manifest parses and every source resolves | **nowhere** | **none** | All 8 plugins become undiscoverable at once | [EV-0026] |

## Permissions and role model

| Role | Grants | Denies | Assignment path | Evidence |
|---|---|---|---|---|
| Operator | Install, uninstall, and invoke any plugin. Installed hooks then run with the operator's own privileges | Nothing — the product has no permission model of its own | Self-service | [EV-0040], [EV-0052] |
| Maintainer | Push, merge, tag, release, and change repository settings, all ungated | Nothing | GitHub write access | [EV-0016], [EV-0017] |
| Contributor | Open a pull request | Merge | GitHub fork | AQ-0007 |

The product has no roles. Every "role" above is a GitHub or operating-system role, which is the accurate answer and worth stating so that no reader assumes an authorization layer exists.

## Experience and interaction

| Aspect | Current state | Source of truth | Evidence |
|---|---|---|---|
| Information architecture | Plugin → skills, commands, agents, hooks. Discovery is the README table and `marketplace.json`; the README table is stale in four places | `marketplace.json` | [EV-0022]–[EV-0025] |
| Interaction model | Slash commands typed by the operator, skills triggered by context, and hooks fired by lifecycle events without the operator acting | Command and skill frontmatter | [EV-0005], [EV-0040] |
| Design system | N/A — there is no user interface. Output is Markdown rendered by the operator's client | — | [EV-0044] |
| Important states (empty, loading, error, partial, offline) | Commands report blocked states with a stated reason rather than failing silently; helper scripts emit `KEY=value` and exit 0/1/2, with 3 reserved for inconclusive | `bin/*.sh` conventions | [EV-0007], [EV-0009] |
| Content and voice conventions | Documented in `.claude/CLAUDE.md` and enforced partially by the flow and dossier suites: skill descriptions are three sentences, commands carry no `name:` key, commits use semantic prefixes with no Claude attribution | `.claude/CLAUDE.md` | [EV-0009] |

## Product analytics

| Metric | Definition | Instrumented where | Coverage | Evidence |
|---|---|---|---|---|
| **none** | — | nowhere | zero | No analytics exist. GitHub exposes no install telemetry for plugin marketplaces, and the plugins emit none by design (AQ-0004) [EV-0044] |

The consequence is the single most important product fact in this package: **every quality decision in this project is made without any signal about use.** Artifact quality is measured well; outcome is not measured at all.

## Accessibility, internationalization, and platforms

| Aspect | Current state | Standard or target | Verified how | Evidence |
|---|---|---|---|---|
| Accessibility | N/A — no interface is rendered by this project | — | — | [EV-0044] |
| Internationalization | English only, throughout. No localization mechanism exists and none is proposed | none stated | direct read | [EV-0004] |
| Supported platforms | macOS and Linux, bash 3.2+. **Windows unsupported and untested**; two open issues report failures and no CI leg exists | none stated | Both suites forbid bash 4+ constructs; no `windows-latest` job | [EV-0008], [EV-0009], [EV-0049], [EV-0012] |

## Roadmap

| Planned item | Stage | Committed date | Evidence |
|---|---|---|---|
| **No roadmap exists** | — | — | No milestone, project board, or planning document is present in the repository. The 11 decision records are retrospective, not forward-looking [EV-0046] |
| Windows support policy | proposed | none | Issue #100, open [EV-0049] |
| Windows/Git Bash defect fix | reported | none | Issue #130, open [EV-0049] |
| dossier release | in progress | none | Pull request #131, open; version 4.7.0 staged in the manifest with no tag [EV-0033] |

## Intended versus implemented behaviour

| Subject | Intended | Implemented | Divergence | Impact | Evidence |
|---|---|---|---|---|---|
| Marketplace size | README badge: 6 plugins | 8 published entries | **stale by 2** | A prospective operator undercounts what is available | [EV-0022] |
| dossier's presence | Published in the manifest on this branch | **Absent from the README entirely** | complete omission | The newest plugin is invisible on the storefront | [EV-0023] |
| flow version | README table: 3.2.0 | 3.2.2 | stale by 2 patches | Minor, but it is a version number in a table of version numbers | [EV-0024] |
| prompt-decorators version | README table: 0.1.0 | 0.1.1 | stale by 1 patch | Minor | [EV-0025] |
| ai-first-org-design-kit size | Description: "Fourteen opinionated skills" | 15 `SKILL.md` files | off by one | An installer looks for a fourteenth skill and finds fifteen | [EV-0027], CT-0003 |
| flow size | README: "33 skills" | 32 `SKILL.md` files | off by one — `skills/learned/` holds only `.gitkeep` | An installer looks for a skill that does not exist | [EV-0028], CT-0002 |
| Licensing | README: Apache-2.0, badge linking to `LICENSE` | `LICENSE` present with the Apache-2.0 text; every manifest declares the same | **none — resolved 2026-07-26** | Was: installers and forkers had no grant of rights | [EV-0019], [EV-0020], [EV-0021] |
| agent-capability-standard version | Manifest: 1.2.0 | Submodule pinned 2 commits past `v1.2.0` | pointer drift | The advertised version is not what installs | [EV-0031] |
| Shell-injection rule | dossier's CI template forbids `${{ github.event.* }}` in a `run:` body, and ships a test enforcing it | `release-desktop-skills.yml` line 24 does exactly that | the repository fails a rule it publishes | Low exploitability — it requires release-publishing access — but the inconsistency is real | [EV-0015], CT-0004 |
| Test coverage | 2,212 passing assertions | Covering 2 of 7 in-tree plugins | The strong number invites over-reading | 5 plugins are entirely unverified | [EV-0010] |
| CI as a quality gate | Two test workflows run on every relevant push | **Neither is a required check; `main` has no protection** | Advisory, not enforcing | A failing suite does not stop a change reaching every installer | [EV-0016], [EV-0017] |

Eleven divergences, of which six are the same underlying failure: **prose that states a fact which the machine-readable source contradicts.** That is precisely the failure mode the dossier plugin was built to prevent, found in the repository that ships it. It is the strongest available argument for the plugin and the sharpest indictment of the project's current documentation practice, and both readings are correct.

## Product assumptions, constraints, risks, and open decisions

| Item | Kind | Impact | Owner | Register ID |
|---|---|---|---|---|
| The product has users other than its maintainer | assumption | Determines whether stale README facts are a real harm or a private inconvenience | — | AQ-0004 |
| A clean-profile install succeeds | assumption | Every claim about how an operator gets the plugins rests on it | Daniel Bentes | AQ-0003 |
| The `prompt-decorators` entry describes its actual contents | assumption | It is published to installers from this manifest | Daniel Bentes | AQ-0005 |
| The README misstates four facts | risk | The storefront misleads on first read | Daniel Bentes | [EV-0022]–[EV-0025] |
| Windows is unsupported by omission | risk | An unknown share of operators cannot use the product, and were never told | Daniel Bentes | AQ-0008 |
| Prompt efficacy is unmeasured | risk | The product's core value proposition has no evidence for or against it | Daniel Bentes | [EV-0008], [EV-0009] |
| Whether to state a Windows support policy | decision | Issue #100 has been open without resolution | Daniel Bentes | AQ-0008 |
| Whether to deprecate `gh-workflow` | decision | Two overlapping workflow plugins ship, with conflicting hooks and no deprecation notice | Daniel Bentes | [EV-0004] |
| Whether dossier may be described as working before it has been observed working | decision | Blocks any public claim about the automation | Daniel Bentes | AQ-0002 |
