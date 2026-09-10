---
dossier-header: internal-v1
title: Product and Domain
purpose: Establishes who the product serves, what it promises them, and where its stated behaviour and its implemented behaviour diverge.
audience: Maintainer, Reviewer, Prospective contributor
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A plugin is added or removed; a plugin's stated purpose or description changes; the intended audience changes
related: [01-project/executive-project-brief.md, 00-control/terminology-and-ownership.md, 02-architecture/components-and-codebase.md, 04-operating/decisions-technical-debt-and-risks.md]
---
# Product and Domain
<!-- contract: references/package-contract-01-project.md#product-and-domain -->

## Where these facts live

Every claim here summarises a row in `00-control/evidence-ledger.md`, which stays canonical when this document goes stale. Entity names, owners and boundaries come from `00-control/terminology-and-ownership.md` and are cited as `TM-####`. Unresolved items carry an `AQ-` or `CT-` identifier from `00-control/assumptions-questions-and-contradictions.md`.

This document describes what the product is and who it serves. Component structure, trust boundaries and deployment belong to `02-architecture/`, and the ten-minute summary belongs to `01-project/executive-project-brief.md`. Where a fact lives there, this document points rather than restates.

Several rows cited here were observed by the session operator (TM-0034) running commands the engagement's action ceiling denies to dispatched agents (AQ-0012). Each such row says so in the ledger. Every row keeps its observation date in the ledger, and this document puts that date in the sentence wherever the fact could since have moved.

## Vision, mission, goals, and non-goals

No document in the repository carries a vision statement. Read at `06b1586` on 2026-07-26, `README.md` stated the purpose in one line: *"Agentic harnesses for Claude Code — specialized AI agents for complex analytical tasks"*. What evidence establishes is the shape of the thing. It is a curated distribution of eight worked-out methods, each installable in one command [EV-0057]. Three of the eight carry safety rails of their own [EV-0040].

| Goal | Measure of success | Evidence |
|---|---|---|
| Make reusable Claude Code methods installable | 8 published plugin entries at marketplace version 4.10.0, resolvable by the client | V — [EV-0057], [EV-0051] |
| Ship methods that are safe to run unattended | 19 hook scripts across the 2 tracked `hooks.json` manifests — 14 in flow, 5 in dossier. dossier's action ceiling defaults to all-false except reading source | V — [EV-0129], [EV-0162], [EV-0039] |
| Ship methods that are auditable before installing | Every shipped artifact is plain text: 37 shell scripts and 3 Python files under plugin `bin/`, plus Markdown and JSON. No binaries, no bundles | V — [EV-0175], [EV-0044] |
| Keep the artifacts correct | 4287 passing assertions and 0 failures across 2 plugins, at `af6e632` on macOS under `/bin/bash` 3.2.57 | V, partial — [EV-0098], [EV-0107] |
| Evaluate what the prompts actually produce | A behavioural eval harness exists for `flow` alone — 4 cases with hidden tests and trap variants. Nothing in CI runs it | V, scoped — [EV-0095]; AQ-0024 for the other 7 entries |
| **Whether operators are helped** | no measure exists | **U** — no install telemetry for plugin marketplaces, no user research (AQ-0004) |

The coverage caveat on the test row is not small. At 2026-07-26 only 2 of the then 7 in-tree plugins carried a shell suite [EV-0010], and six plugins are in-tree at `d3fc744` [EV-0058]. Unknown: how many of those six carry a suite at `d3fc744` — no evidence row counts it (AQ-0032, CT-0022).

| Non-goal | Why excluded | Evidence |
|---|---|---|
| Operating a service | The product is content the client executes locally. Nothing is hosted | [EV-0044] |
| Collecting usage data | No endpoint exists to collect to, and none is proposed anywhere in the repository | [EV-0044] |
| Windows support | Not excluded by decision — **excluded by omission.** Issue #100 proposes a marketplace policy on it and was open at 2026-07-26 | [EV-0049] |
| Charging for plugins | No pricing, entitlement, licence check, or payment path exists anywhere | [EV-0044] |
| Supporting Claude clients other than Claude Code | The only exception is the desktop-skill packaging path, which strips Claude Code frontmatter for Claude Desktop and runs on release publication | [EV-0133]; AQ-0023 |

The Windows row is the honest one. A non-goal reached by omission behaves the same as a decision for the operator who meets it. Only a decision can be stated in advance, and this one has not been.

## Actors

| Actor | Class | What they need from the product | Access path | Evidence |
|---|---|---|---|---|
| Installing operator | primary user | To find a plugin that fits, install it, and trust what it does on their machine | `claude plugin marketplace add` then `claude plugin install` | [EV-0051], [EV-0052] |
| Evaluating operator | primary user | To decide whether to install, from the README and the repository alone | Reading `README.md` and the plugin trees | [EV-0022], [EV-0023] |
| Contributor | secondary | A stated process, a review path, and a way to know their change is correct | GitHub pull request. **No `CONTRIBUTING.md`, no CODEOWNERS and no template** at 2026-07-26, not re-checked since (AQ-0022). All 214 commits on `main` carry one author identity at `d3fc744` | [EV-0036], [EV-0163], AQ-0007 |
| Security researcher | secondary | A private channel to report a flaw in code that runs on other people's machines | **None existed at 2026-07-26.** A public issue was the only option. Not re-checked since (AQ-0022) | [EV-0036] |
| Maintainer | operator | To ship changes without breaking installers | Direct write access, ungated: no branch protection, no rulesets at `e104483` | [EV-0131], [EV-0163] |
| Claude Desktop user | tertiary | Skills usable outside Claude Code | Downloading ZIP assets from a release | [EV-0133] |
| Claude Code client | system | A manifest it can parse and sources it can resolve | git clone. **Inferred:** distribution is a git read by the client rather than a registry publish, reasoned from the absence of any registry manifest and any publish step | [EV-0043, I] |

## Jobs to be done and user journeys

| Job | Actor | Journey | Success criterion | Evidence |
|---|---|---|---|---|
| "Give me a disciplined GitHub workflow" | Installing operator | Add marketplace → install `flow` → use `/flow:start`, `/flow:pr`, `/flow:review`, `/flow:merge` | The workflow runs and its hooks block unsafe actions | V for install [EV-0052]; **U for outcome** |
| "Stop me doing something destructive" | Installing operator | Install `flow` → a `PreToolUse` hook blocks the tool call | Destructive commands are blocked | V for firing — three refusals were observed during this refresh, and the client honoured each [EV-0173]. All three were false positives of raw-text matching (AQ-0026), and general hook blocking semantics stay unknown (AQ-0025) |
| "Document what this project actually does" | Installing operator | Install `dossier` → `/dossier:init` → `/dossier:baseline` → `/dossier:audit` → `/dossier:gate` | An evidence-cited package with an honest gate verdict | V — this package is the artifact [EV-0047], [EV-0048] |
| "Keep documentation current after merges" | Installing operator | `/dossier:setup` scaffolds a workflow → a merge triggers a documentation pull request | Documentation refreshes without being asked | **U — never executed end to end**, and no docs-refresh workflow is installed here at `af6e632` (AQ-0002) [EV-0045], [EV-0123] |
| "Analyse content for manipulation" | Installing operator | Install `decipon` → run its commands | An NCI analysis | R — asserted by the plugin's description; no test suite existed at 2026-07-26 [EV-0010] |
| "Evaluate before installing" | Evaluating operator | Read `README.md` | An accurate picture of what is available | **Broken at 2026-07-26, resolved at `d3fc744`** — the badge read 6 against 8, two versions were stale, dossier was absent [EV-0022]–[EV-0025]. All four corrected [EV-0170], [EV-0171], [EV-0179] |
| "Contribute a fix" | Contributor | Fork, branch, pull request | Merged | **U — never exercised by anyone but the maintainer** (AQ-0007) [EV-0163] |
| "Report a vulnerability privately" | Security researcher | — | — | **Not supported at 2026-07-26**, not re-checked (AQ-0022) [EV-0036] |

One journey remains broken rather than merely unverified: private vulnerability reporting, which had no path at all when last observed [EV-0036]. Evaluation-before-install was broken at the July baseline and is repaired at `d3fc744`, where no known figure in `README.md` disagrees with the tree [EV-0171].

### The primary journey, traced

The install-and-run path is the one every other journey depends on. It crosses these components, named as `00-control/terminology-and-ownership.md` names them. Component detail lives in `02-architecture/system-architecture.md`, not here.

1. The operator adds the marketplace. The Claude Code plugin client (TM-0031) resolves `source: github, repo: synaptiai/synapti-marketplace` and holds a clone with `autoUpdate: true` [EV-0051].

2. The client reads the marketplace (TM-0001) manifest and offers 8 plugin entries at metadata version 4.10.0 [EV-0057].

3. The operator installs one plugin (TM-0002). Six entries resolve to a repository-relative path, and two resolve from another repository at a pinned sha [EV-0058].

4. The client caches the plugin tree. Six of this marketplace's plugins were observed installed and cached on the maintainer's own machine on 2026-07-26 [EV-0052].

5. Any hooks (TM-0006) the plugin registers now run at lifecycle points without the operator invoking them. Three of the eight entries register hooks [EV-0040], [EV-0168].

6. The operator invokes a command (TM-0004), which loads its declared skills (TM-0003) and may dispatch agents (TM-0005) [EV-0005], [EV-0006].

Unknown: whether a cold-profile install succeeds — every observation above comes from one machine that already had the marketplace (AQ-0003). Unknown: what delivery, ordering and blocking semantics the client applies to step 5 (AQ-0025).

## Feature and capability map

| Capability | State | Actor | Entry point | Evidence | Note |
|---|---|---|---|---|---|
| Plugin discovery | implemented | operator | `marketplace.json` | [EV-0057] | 8 entries at metadata version 4.10.0 |
| Manifest version checking | implemented | maintainer, in CI | marketplace manifest check (TM-0033) | [EV-0080], [EV-0081], [EV-0127] | 8 entries checked, 0 failed, 0 unverifiable. Compares advertised versions only; that the file parses and every source resolves is unchecked (AQ-0020) |
| Plugin install | implemented | operator | `claude plugin install` | [EV-0052] | Observed against the client's own state on one machine, 2026-07-26 (AQ-0003) |
| Auto-update | implemented, client-owned | operator | client | [EV-0051] | `autoUpdate: true` observed 2026-07-26. Changes propagate without the operator acting |
| GitHub workflow harness | implemented | operator | `flow` (TM-0021) — 32 skills, 23 commands, 9 agents | [EV-0162], [EV-0065] | Version 3.3.0. Tested: 2336 assertions, 0 failures at `af6e632` [EV-0098] |
| Behavioural evaluation of prompt output | implemented for `flow` only | maintainer | correctness eval harness (TM-0035) | [EV-0095] | 4 cases with hidden tests and trap variants. Nothing in CI runs it, and no other entry has one (AQ-0024). **Reported:** the retained summary gives 105 runs across 2 models and a `keep-enforce` verdict, and calls its own reading provisional [EV-0096, R] |
| Legacy workflow harness | implemented, superseded | operator | `gh-workflow` (TM-0025) — 7 skills, 14 commands, 4 agents | [EV-0162] | No deprecation notice; `.claude/CLAUDE.md` says enable only one of the two |
| Evidence-first documentation | implemented, published at 1.2.0 | operator | `dossier` (TM-0022) — 10 skills, 9 commands, 6 agents | [EV-0162], [EV-0065] | Tested: 1951 assertions, 0 failures at `af6e632` [EV-0107]. Carried by the `main` manifest at both `d3fc744` and `origin/main` [EV-0181] |
| Post-merge doc automation | built, never executed end to end | operator | `/dossier:setup` | [EV-0045], [EV-0123] | No docs-refresh workflow is installed in this repository (AQ-0002) |
| Content analysis | implemented | operator | `decipon` (TM-0026) — 2 skills, 7 commands, 5 agents | [EV-0162] | No shell suite at 2026-07-26 [EV-0010] |
| Product-development ledger | implemented | operator | `context-ledger` (TM-0027) — 5 skills, 8 commands, 5 agents | [EV-0162] | No shell suite at 2026-07-26 [EV-0010] |
| Organizational design | implemented | operator | `ai-first-org-design-kit` (TM-0024) — 15 skills, no commands, no agents | [EV-0162] | The "Fourteen opinionated skills" description was corrected to fifteen at `7ee4923` [EV-0170] |
| Agent capability specification | implemented, external source | operator | `agent-capability-standard` (TM-0023) | [EV-0058], [EV-0127] | A `github` source pinned to sha `9e2f65b`, whose tree reports the advertised 1.2.0. Nothing of it is tracked here [EV-0059]. Its skill count was 42 at the former pointer `95f7ac2` on 2026-07-26 [EV-0094]; no row counts it at `9e2f65b` (AQ-0006) |
| Prompt decoration | published, unverified here | operator | `prompt-decorators` (TM-0028) | [EV-0058], [EV-0127] | A `git-subdir` source pinned to sha `9c792fe`. Contents never inspected (AQ-0005) |
| Desktop skill export | implemented | Desktop user | Release assets | [EV-0133] | Runs on release publication, uploads with `--clobber`. Archive reproducibility unknown (AQ-0021) |
| Safety hooks | implemented | operator, passively | lifecycle events | [EV-0040], [EV-0129], [EV-0168] | 3 of 8 entries register hooks. Two `hooks.json` manifests are tracked here — 14 flow scripts, 5 dossier scripts — and the third set lives in the external pinned tree |
| Windows support | not implemented | operator | — | [EV-0049] | Two issues reported Git Bash failures at 2026-07-26, and no CI job runs on Windows (AQ-0008) |

## Business model and commercial constraints

| Plan or entitlement | What it grants | Technical enforcement point | Evidence |
|---|---|---|---|
| **None.** There is no plan, tier, entitlement, licence key, or payment path anywhere in the repository | Everything, to everyone | none — and none exists to enforce | [EV-0044] |

Two indirect commercial constraints apply. The project pays nothing to operate, and it induces unmeasured model-usage cost in every operator's own account [EV-0044]. Only one path could land that induced cost on a *repository* rather than a person: dossier's post-merge automation. It caps turns per run, cannot cap spend, and has never run [EV-0045], [EV-0123].

## Product boundaries

| Boundary | In scope | Explicitly out of scope | Evidence |
|---|---|---|---|
| Execution | Content the Claude Code client loads and executes locally | Anything hosted, served, or scheduled by this project | [EV-0044] |
| Platform | macOS and Linux shells, bash 3.2 and later. Both suites pass on macOS under `/bin/bash` 3.2.57 and on `ubuntu-latest` | Windows — **by omission, not by decision** | [EV-0098], [EV-0107], [EV-0126], [EV-0049] |
| Client | Claude Code, plus a packaged export path for Claude Desktop | Other agent clients. No row establishes that any artifact loads under a second client (AQ-0023) | [EV-0133] |
| Data | None held, none transmitted, none collected | All data handling | [EV-0044] |
| Plugin contents | The 6 in-tree plugins (TM-0007), whose files are versioned with the marketplace | The 2 external plugins (TM-0008), whose contents are versioned elsewhere: `prompt-decorators`, never inspected (AQ-0005), and `agent-capability-standard`, whose tree at the pinned sha is not tracked here (AQ-0006) | [EV-0058], [EV-0059], [EV-0060] |

## Domain model

| Entity | Definition | Owns | Lifecycle | Canonical name (`TM-####`) | Evidence |
|---|---|---|---|---|---|
| Marketplace | The manifest a client reads to discover plugins | 8 plugin entries | Versioned by `metadata.version`, 4.10.0, plus a git tag | TM-0001 | [EV-0057] |
| Plugin | One installable unit with its own manifest | Its skills, commands, agents, hooks, and scripts | semver in two files that must agree | TM-0002 | [EV-0064] |
| In-tree plugin | A plugin whose source is a repository-relative path | Its own files, versioned with the marketplace | 6 of the 8 entries | TM-0007 | [EV-0058] |
| External plugin | A published entry resolved from another repository at a pinned sha | Nothing here — its contents are versioned elsewhere | 2 of the 8 entries, one `github` and one `git-subdir` | TM-0008 | [EV-0058], [EV-0127] |
| Skill | One `SKILL.md` — the unit of method | Its own frontmatter and body | Versioned with its plugin | TM-0003 | [EV-0004] |
| Command | One Markdown file invoked as `/plugin:name` | Its declared skills and phases | Versioned with its plugin | TM-0004 | [EV-0005] |
| Agent | A subagent definition with a tool and skill allowlist | Its own context when dispatched | Versioned with its plugin | TM-0005 | [EV-0006] |
| Hook | An event-to-script binding executed by the client | Nothing; it inspects and permits or blocks | Versioned with its plugin | TM-0006 | [EV-0040] |
| Operator | The person running Claude Code | Their own machine and session | Not modelled — the product has no notion of identity | TM-0009 | [EV-0044] |

| Rule or invariant | Enforced where | Enforcement kind | What breaks if violated | Evidence |
|---|---|---|---|---|
| A plugin's version equals its marketplace entry's version | the marketplace manifest check (TM-0033), in CI on manifest changes, weekly, and on demand | script plus CI | An operator installs a version different from the one advertised | [EV-0080], [EV-0081], [EV-0127], [EV-0064] |
| An external entry's source carries a `sha` | the same check | script plus CI | A floating ref means two installs on different days need not agree | [EV-0080], [EV-0127] |
| A skill directory contains a `SKILL.md` | flow and dossier suites, for themselves | test | Counting directories overstates the skill count — the origin of the flow README's off-by-one, corrected at `7ee4923` | [EV-0029], [EV-0170] |
| A command's declared skills all resolve on disk | flow and dossier suites | test | A command references a skill that does not exist | [EV-0009] |
| Public documents contain only approved claims | dossier's claim register and `dossier-claim-scan.sh` | test plus runtime hook | Unapproved claims reach an external reader | [EV-0039] |
| Shell scripts run on bash 3.2 | flow and dossier suites | test | Scripts break on the maintainer's own platform. **Violated in what shipped:** both published releases carry pre-fix `flow` runtime scripts that failed under `/bin/bash` 3.2.57 | [EV-0098], [EV-0107], [EV-0144] |
| Every executable ships with the executable bit | flow and dossier suites, plus `dossier-tests.yml` | test | The client cannot run the hook | [EV-0107] |
| The manifest parses and every source resolves | partly — the manifest check resolves both external sources at their pin, and nothing asserts that the whole file parses | **partial** | All 8 plugins become undiscoverable at once | [EV-0127], AQ-0020 |

## Permissions and role model

| Role | Grants | Denies | Assignment path | Evidence |
|---|---|---|---|---|
| Operator | Install, uninstall, and invoke any plugin. Installed hooks then run with the operator's own privileges | Nothing — the product has no permission model of its own | Self-service | [EV-0040], [EV-0052] |
| Maintainer | Push, merge, tag, release, and change repository settings, all ungated | Nothing | GitHub write access | [EV-0131] |
| Contributor | Open a pull request | Merge | GitHub fork | AQ-0007 |

The product has no roles. Every "role" above is a GitHub or operating-system role. State that plainly, so no reader assumes an authorization layer exists.

## Experience and interaction

| Aspect | Current state | Source of truth | Evidence |
|---|---|---|---|
| Information architecture | Plugin → skills, commands, agents, hooks. Discovery is the README table and `marketplace.json`. The README table was stale in four places at 2026-07-26 and matches the tree at `d3fc744` | `marketplace.json` | [EV-0022]–[EV-0025], [EV-0170], [EV-0171], [EV-0179] |
| Interaction model | Slash commands typed by the operator, skills triggered by context, and hooks fired by lifecycle events without the operator acting | Command and skill frontmatter | [EV-0005], [EV-0040] |
| Design system | N/A — there is no user interface. Output is Markdown rendered by the operator's client | — | [EV-0044] |
| Important states (empty, loading, error, partial, offline) | Commands report blocked states with a stated reason rather than failing silently; helper scripts emit `KEY=value` and exit 0/1/2, with 3 reserved for inconclusive | `bin/*.sh` conventions | [EV-0175], [EV-0107] |
| Content and voice conventions | Documented in `.claude/CLAUDE.md` and enforced partially by the flow and dossier suites: skill descriptions are three sentences, commands carry no `name:` key, commits use semantic prefixes with no Claude attribution | `.claude/CLAUDE.md` | [EV-0107] |

## Product analytics

| Metric | Definition | Instrumented where | Coverage | Evidence |
|---|---|---|---|---|
| **none** | — | nowhere | zero | No analytics exist. GitHub exposes no install telemetry for plugin marketplaces, and the plugins emit none by design (AQ-0004) [EV-0044] |

The consequence is a central product fact: **every quality decision in this project is made without any signal about use.** Artifact quality is measured. Outcome is not measured at all. One partial exception exists. The correctness eval harness (TM-0035) measures what `flow`'s prompts produce on four authored cases [EV-0095]. It measures nothing an operator experiences, and nothing about the other seven entries (AQ-0024).

## Accessibility, internationalization, and platforms

| Aspect | Current state | Standard or target | Verified how | Evidence |
|---|---|---|---|---|
| Accessibility | N/A — no interface is rendered by this project | — | — | [EV-0044] |
| Internationalization | English only, throughout. No localization mechanism exists and none is proposed | none stated | direct read | [EV-0093] |
| Supported platforms | macOS and Linux, bash 3.2+. **Windows unsupported and untested**; two issues reported failures at 2026-07-26 and no CI leg exists | none stated | Both suites pass under `/bin/bash` 3.2.57 and on `ubuntu-latest`; no `windows-latest` job among the 5 tracked workflows | [EV-0098], [EV-0107], [EV-0126], [EV-0123], [EV-0049] |

## Roadmap

| Planned item | Stage | Committed date | Evidence |
|---|---|---|---|
| **No roadmap exists** | — | — | No milestone, project board, or planning document is present in the repository. The 21 decision records are retrospective, not forward-looking [EV-0169] |
| Windows support policy | proposed | none | Issue #100, open at 2026-07-26. Not re-checked — `networkAccess` is false for dispatched agents (AQ-0012) [EV-0049] |
| Windows/Git Bash defect fix | reported | none | Issue #130, open at 2026-07-26. Not re-checked (AQ-0012) [EV-0049] |
| Whether to cut a patch release carrying the `flow` fix | undecided | none | Both published releases carry the pre-fix scripts; the corrected code exists on `main` only [EV-0144] |

`dossier` is at 1.2.0 and carried by the `main` manifest [EV-0065], [EV-0181]. Releases v4.9.0 and v4.10.0 were both published on 2026-09-10, at manifest version 4.10.0 [EV-0066], [EV-0057].

## Intended versus implemented behaviour

| Subject | Intended | Implemented | Divergence | Impact | Evidence |
|---|---|---|---|---|---|
| Marketplace size | README badge: 6 plugins | 8 published entries | **resolved at `7ee4923`** — the badge reads 8 | Was: a prospective operator undercounted what is available | [EV-0022], [EV-0171] |
| dossier's presence | Published in the manifest | **Absent from the README entirely** at 2026-07-26 | **resolved**, observed at `d3fc744` — the README lists dossier at 1.2.0 | Was: the newest plugin was invisible on the storefront | [EV-0023], [EV-0170], [EV-0179] |
| flow version | README table: 3.2.0 | 3.2.2 at 2026-07-26 | **resolved**, observed at `d3fc744` — README and manifest both read 3.3.0 | Minor | [EV-0024], [EV-0179] |
| prompt-decorators version | README table: 0.1.0 | 0.1.1 | **resolved**, observed at `d3fc744` | Minor | [EV-0025], [EV-0179] |
| ai-first-org-design-kit size | Description: "Fourteen opinionated skills" | 15 `SKILL.md` files | **resolved at `7ee4923`** — the description reads fifteen | Was: an installer looked for a fourteenth skill and found fifteen | [EV-0027], [EV-0170], CT-0003 |
| flow size | README: "33 skills" | 32 `SKILL.md` files — `skills/learned/` holds only `.gitkeep` | **resolved at `7ee4923`** — the README claims 32 | Was: an installer looked for a skill that does not exist | [EV-0028], [EV-0029], [EV-0170], CT-0002 |
| Licensing | README: Apache-2.0, badge linking to `LICENSE` | `LICENSE` present with the Apache-2.0 text; every manifest declares the same, and GitHub's own detection reports Apache-2.0 | **resolved** — closes AQ-0011 | Was: installers and forkers had no grant of rights | [EV-0019], [EV-0021], [EV-0132], [EV-0171] |
| agent-capability-standard resolution | Manifest: 1.2.0 | A `github` source pinned to sha `9e2f65b`, whose tree reports 1.2.0 and is checked in CI | **resolved at the new pin.** The former submodule gitlink resolved to 0 entries in a plain clone, so the advertised plugin could not install, and that pointer sat 17 commits behind upstream while both reported 1.2.0 | Was: what installed was not what was advertised, and for a plain clone nothing installed | [EV-0058], [EV-0127], [EV-0167] |
| Shell-injection rule | dossier's CI template forbids `${{ github.event.* }}` in a `run:` body, and ships a test enforcing it | `release-desktop-skills.yml` still does exactly that at `e104483` | **live** — the repository fails a rule it publishes | Low exploitability — it requires release-publishing access — but the inconsistency is real | [EV-0133], CT-0004 |
| Test coverage | 4287 passing assertions | Covering 2 plugins | **live** — the strong number invites over-reading | Unknown: how many of the 6 in-tree plugins carry a suite at `d3fc744` (AQ-0032, CT-0022) | [EV-0098], [EV-0107], [EV-0010] |
| CI as a quality gate | Five workflows run on relevant pushes, all green on Linux across this range | **None is a required check; `main` has no protection and no rulesets at `e104483`** | **live** — advisory, not enforcing | A failing suite does not stop a change reaching every installer | [EV-0126], [EV-0131], [EV-0123] |
| What the published releases contain | Shell scripts run on bash 3.2, tested in both suites | v4.9.0 and v4.10.0 carry the pre-fix `flow` runtime scripts; the fix merged after both tags | **live** — the fixed code is on `main` only | What an operator on macOS experiences at v4.10.0 is not established | [EV-0144] |

Twelve divergences, of which eight are resolved and four are live. Six of the eight resolved were the same underlying failure: **prose that states a fact which the machine-readable source contradicts**. That is the failure mode the dossier plugin exists to prevent, found in the repository that ships it.

All six were closed by hand at or before `7ee4923`, not by a check. The marketplace manifest check compares manifests and does not read prose [EV-0170], [EV-0080]. Nothing prevents the seventh.

## Product assumptions, constraints, risks, and open decisions

| Item | Kind | Impact | Owner | Register ID |
|---|---|---|---|---|
| The product has users other than its maintainer | assumption | Determines whether stale README facts are a real harm or a private inconvenience | — | AQ-0004 |
| A clean-profile install succeeds | assumption | Every claim about how an operator gets the plugins rests on it | Daniel Bentes | AQ-0003 |
| The `prompt-decorators` entry describes its actual contents | assumption | It is published to installers from this manifest | Daniel Bentes | AQ-0005 |
| A non-zero hook exit actually blocks a tool call | assumption | The product's entire safety-rail proposition rests on it, across 19 tracked hook scripts | Daniel Bentes | AQ-0025, [EV-0162] |
| Windows is unsupported by omission | risk | An unknown share of operators cannot use the product, and were never told | Daniel Bentes | AQ-0008 |
| Prompt efficacy is unmeasured outside `flow` | risk | Seven of the eight entries have no behavioural evaluation of what their prompts produce | Daniel Bentes | [EV-0095], AQ-0024 |
| Total dependence on one client | risk | The manifest, skills, commands, agents and hooks are all Claude Code constructs. No row establishes that any artifact is portable | Daniel Bentes | AQ-0023 |
| Published releases carry a defect fixed after the tags | risk | The corrected `flow` runtime scripts exist on `main` only | Daniel Bentes | [EV-0144] |
| Whether to state a Windows support policy | decision | Issue #100 was open without resolution at 2026-07-26 | Daniel Bentes | AQ-0008 |
| Whether to deprecate `gh-workflow` | decision | Two overlapping workflow plugins ship, with conflicting hooks and no deprecation notice | Daniel Bentes | [EV-0162] |
| Whether dossier may be described as working before it has been observed working | decision | Blocks any public claim about the automation | Daniel Bentes | AQ-0002 |
