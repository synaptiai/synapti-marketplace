---
dossier-header: internal-v1
title: Terminology and Ownership
purpose: Fixes one name per thing so the rest of the package cannot drift, and states plainly who owns each part.
audience: Reviewer, Maintainer, Contributor
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 13c99b1
last-verified: 2026-07-26
review-trigger: A plugin is added, renamed, or removed; ownership of any component changes
related: [00-control/evidence-ledger.md, 02-architecture/components-and-codebase.md, 04-operating/decisions-technical-debt-and-risks.md]
---
# Terminology and Ownership
<!-- contract: references/package-contract-00-control.md#terminology-and-ownership -->

## Method

The canonical name for everything this package names, plus who owns it. Every other document draws its vocabulary from here. Column definitions and identifier grammar are in the plugin reference `references/register-schemas.md`.

An owner is never invented. `unassigned` is the correct value where no evidence establishes ownership, and the count of `unassigned` entries on critical components is itself a diligence signal.

## Glossary

| ID | Canonical name | Class | Definition | Aliases | Owner | Decision rights | Source of truth | Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| TM-0001 | marketplace | term | A `marketplace.json` manifest that a Claude Code client reads to discover installable plugins. Not a storefront, not a registry — the client resolves each entry's `source` itself | plugin marketplace, catalogue | Daniel Bentes | Daniel Bentes | `.claude-plugin/marketplace.json` | [EV-0001] | current |
| TM-0002 | plugin | term | One installable unit: a directory containing `.claude-plugin/plugin.json` and any of `skills/`, `commands/`, `agents/`, `hooks/`, `bin/` | — | Daniel Bentes | Daniel Bentes | `plugins/*/.claude-plugin/plugin.json` | [EV-0001] | current |
| TM-0003 | skill | term | One `SKILL.md` file. A directory under `skills/` without a `SKILL.md` is **not** a skill, which is why counts in this package are file counts and never directory counts | — | Daniel Bentes | Daniel Bentes | `find plugins -name SKILL.md` | [EV-0004], [EV-0029] | current |
| TM-0004 | command | term | One Markdown file under a plugin's `commands/`, invoked as `/<plugin>:<filename>`. The filename is the command name; there is no `name:` key | slash command | Daniel Bentes | Daniel Bentes | `plugins/*/commands/*.md` | [EV-0005] | current |
| TM-0005 | agent | term | One Markdown file under a plugin's `agents/`, dispatched into a separate context with its own tool and skill allowlist | subagent | Daniel Bentes | Daniel Bentes | `plugins/*/agents/*.md` | [EV-0006] | current |
| TM-0006 | hook | term | A shell script a plugin registers in `hooks/hooks.json` that the Claude Code client executes at a lifecycle point on the operator's machine. The marketplace's only mechanism that runs without an operator asking | — | Daniel Bentes | Daniel Bentes | `plugins/*/hooks/hooks.json` | [EV-0038], [EV-0039], [EV-0040] | current |
| TM-0007 | in-tree plugin | term | A plugin whose source is a repository-relative path, and whose files are therefore versioned with the marketplace itself | vendored plugin | Daniel Bentes | Daniel Bentes | `.claude-plugin/marketplace.json` | [EV-0003] | current |
| TM-0008 | external plugin | term | A published entry whose source is another repository — a git submodule or a `git-subdir` source. Its contents are not versioned here | — | Daniel Bentes | Daniel Bentes | `.gitmodules`, marketplace entry `source` | [EV-0003], [EV-0030] | current |
| TM-0009 | operator | term | The person running Claude Code who installs a plugin. The marketplace's only user role; it has no accounts, no tenants, and no server-side identity | user, installer | — | — | — | [EV-0044] | current |
| TM-0010 | evidence-first documentation | term | The method the dossier plugin encodes: no assertion without a ledger row and a claim state; unknowns are recorded as unknown rather than omitted | — | Daniel Bentes | Daniel Bentes | `plugins/dossier/skills/evidence-ledger/SKILL.md` | [EV-0009] | current |
| TM-0011 | release gate | term | A conjunctive binary check. All 17 conditions pass or the package is NOT-RELEASABLE; a high score never substitutes for a failed condition | — | Daniel Bentes | Daniel Bentes | `plugins/dossier/references/release-gate-conditions.md` | [EV-0009] | current |
| TM-0012 | desktop skill package | term | A ZIP built from a `SKILL.md` with Claude Code-specific frontmatter stripped, attached to a GitHub release for use in Claude Desktop | — | Daniel Bentes | Daniel Bentes | `scripts/package-desktop-skills.sh` | [EV-0012] | current |

## Entities

| ID | Canonical name | Class | Definition | Aliases | Owner | Decision rights | Source of truth | Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| TM-0020 | Synapti Plugin Marketplace | product | This repository, published at `synaptiai/synapti-marketplace`, distributing 8 plugin entries | synapti-marketplace | Daniel Bentes | Daniel Bentes | `.claude-plugin/marketplace.json` | [EV-0001] | current |
| TM-0021 | flow | plugin | GitHub development workflow: 32 skills, 23 commands, 9 agents, 12 hook scripts, its own settings schema and test suite. The largest and most depended-on plugin | — | Daniel Bentes | Daniel Bentes | `plugins/flow/` | [EV-0004], [EV-0008] | current |
| TM-0022 | dossier | plugin | Evidence-first documentation and post-merge documentation automation: 9 skills, 9 commands, 6 agents, 4 hook scripts, 14 shell scripts | — | Daniel Bentes | Daniel Bentes | `plugins/dossier/` | [EV-0009] | current |
| TM-0023 | agent-capability-standard | plugin | 42 skills. Distributed as a **git submodule** from `synaptiai/agent-capability-standard`; Apache-2.0; carries the repository's only dependency manifest | grounded-agency (package name) | Daniel Bentes | Daniel Bentes | `.gitmodules`, submodule tree | [EV-0031], [EV-0041] | current |
| TM-0024 | ai-first-org-design-kit | plugin | 15 skills for organizational design. Its published description says fourteen — see CT-0003 | — | Daniel Bentes | Daniel Bentes | `plugins/ai-first-org-design-kit/` | [EV-0027] | current |
| TM-0025 | gh-workflow | plugin | 7 skills, 14 commands, 4 agents. Predates flow and overlaps it; the project instructions state only one may be enabled at a time | — | Daniel Bentes | Daniel Bentes | `plugins/gh-workflow/` | [EV-0004] | current |
| TM-0026 | decipon | plugin | 2 skills, 7 commands, 5 agents for manipulation and disinformation analysis | — | Daniel Bentes | Daniel Bentes | `plugins/decipon/` | [EV-0004] | current |
| TM-0027 | context-ledger | plugin | 5 skills, 8 commands, 5 agents for evidence-based product development | — | Daniel Bentes | Daniel Bentes | `plugins/context-ledger/` | [EV-0004] | current |
| TM-0028 | prompt-decorators | plugin | Published from a `git-subdir` source in `synaptiai/prompt-decorators`, pinned to the floating ref `main`. Not present in this repository | — | Daniel Bentes | Daniel Bentes | marketplace entry only | [EV-0030], AQ-0005 | current |
| TM-0029 | `main` | environment | The default branch. The only ref from which scheduled workflows run and from which releases are cut. Carries no branch protection and no rulesets | — | Daniel Bentes | Daniel Bentes | `api:branches/main` | [EV-0016], [EV-0017] | current |
| TM-0030 | GitHub Actions | external system | The only execution environment the project itself operates: 4 workflows, 2 third-party action sources | CI | Daniel Bentes | Daniel Bentes | `.github/workflows/` | [EV-0012], [EV-0042] | current |
| TM-0031 | Claude Code plugin client | external system | Reads `marketplace.json`, resolves each entry's source, and executes skills, commands, agents, and hooks on the operator's machine. Not built or controlled by this project | — | Anthropic | Anthropic | — | [EV-0043] | current |
| TM-0032 | `.decisions/` | component | 11 tracked decision records written by the flow plugin's journal during development of this repository | decision journal | Daniel Bentes | Daniel Bentes | `.decisions/` | [EV-0046] | current |

## Component and capability ownership

| Component or capability | Owner | Backup owner | Criticality | Evidence for ownership | Note |
|---|---|---|---|---|---|
| `marketplace.json` manifest | Daniel Bentes | unassigned | critical | Sole commit identity [EV-0035] | A malformed manifest breaks discovery for every plugin at once |
| flow plugin | Daniel Bentes | unassigned | critical | [EV-0035] | 1022 assertions guard it; no second reviewer exists |
| dossier plugin | Daniel Bentes | unassigned | high | [EV-0035] | 1229 assertions; headline capability unproven end to end (AQ-0002) |
| gh-workflow, decipon, context-ledger, ai-first-org-design-kit | Daniel Bentes | unassigned | medium | [EV-0035] | No test suite [EV-0010] |
| agent-capability-standard | Daniel Bentes | unassigned | medium | `.gitmodules`, upstream repository under the same owner | Submodule pointer sits 2 commits past the advertised tag [EV-0031] |
| prompt-decorators | Daniel Bentes | unassigned | medium | Marketplace entry author field | Contents unverified from here (AQ-0005) |
| CI workflows | Daniel Bentes | unassigned | high | [EV-0012], [EV-0035] | Advisory only — no required status checks exist [EV-0016] |
| Release process | Daniel Bentes | unassigned | high | 57 tags, single identity [EV-0032], [EV-0035] | |
| Desktop skill packaging | Daniel Bentes | unassigned | low | `scripts/package-desktop-skills.sh` | Runs only on release publication |

## Decision ownership and escalation

| Decision domain | Decides | Consulted | Escalates to | Evidence |
|---|---|---|---|---|
| Adding or removing a plugin from the marketplace | Daniel Bentes | — | no escalation path exists | [EV-0035] |
| Plugin version bumps and marketplace version | Daniel Bentes | — | no escalation path exists | `.claude/CLAUDE.md` versioning section |
| Merging to `main` | Daniel Bentes | — | no escalation path exists | [EV-0016], [EV-0035] |
| Cutting a release | Daniel Bentes | — | no escalation path exists | [EV-0032] |
| Accepting an external contribution | Daniel Bentes | — | no escalation path exists | AQ-0007 — never exercised |
| Security disclosure handling | unassigned | — | no path published | [EV-0036] — no `SECURITY.md` |

## Operational ownership

| Service or system | On-call owner | Business hours owner | Escalation path | Runbook | Evidence |
|---|---|---|---|---|---|
| N/A — the project operates no service | N/A | N/A | N/A | N/A | The marketplace has no runtime; every artifact executes inside the operator's own session [EV-0044] |
| GitHub Actions workflows | unassigned | Daniel Bentes | none | none | [EV-0012], [EV-0036] |

There is no on-call rotation because there is nothing to be on call for. This is a property of the architecture, not a gap.

## Documentation ownership

| Document | Owner | Review cadence | Review trigger |
|---|---|---|---|
| All 23 files in this package | Daniel Bentes | on change | The `review-trigger` in each file's own header |
| `README.md` | Daniel Bentes | none recorded | Currently drifts — 4 stale facts [EV-0022] to [EV-0025] |
| Per-plugin `README.md` | Daniel Bentes | none recorded | flow's skill count is stale [EV-0028] |
| `.claude/CLAUDE.md` | Daniel Bentes | none recorded | Plugin or convention changes |

## Ownership gaps and bus-factor concerns

| Gap | What is unowned | Criticality | Consequence | Evidence | Proposed resolution |
|---|---|---|---|---|---|
| Bus factor of one | Every component | critical | If the sole maintainer stops, 8 published plugins have no one who can cut a release, merge a fix, or answer a security report | [EV-0035] — one identity across all 366 commits on all refs | Name a backup maintainer, or state in the README that the project is single-maintainer so installers can weight that themselves |
| No security contact | Vulnerability intake | high | A researcher who finds a flaw in a hook that runs on operator machines has no private channel; the only option is a public issue | [EV-0036] | Add `SECURITY.md` with one contact address |
| No merge gate | `main` | high | Any push to `main` lands without review or a passing test run; the 2212 assertions across both suites are advisory | [EV-0016], [EV-0017] | Enable branch protection requiring both test workflows |
| No contribution path | External contribution | medium | A would-be contributor has no stated process, no CODEOWNERS, and no template | [EV-0036], AQ-0007 | Add `CONTRIBUTING.md` |

| Measure | Count |
|---|---|
| Entities with `unassigned` owner | 0 |
| Critical components with `unassigned` owner | 0 |
| Components with a single contributor in the inspected history | 9 of 9 |
| Decision domains with no recorded escalation path | 6 of 6 |

Every component has an owner; every component has the *same* owner, and no component has a backup. That is the finding — not an absence of names.

## Public naming

| Internal canonical name | Approved public name | Claim ID | Note |
|---|---|---|---|
| N/A | N/A | N/A | Every entity above is already public. The repository is public, the manifest is public, and the disclosure policy for this engagement is `public`. No internal-only name exists to protect |
