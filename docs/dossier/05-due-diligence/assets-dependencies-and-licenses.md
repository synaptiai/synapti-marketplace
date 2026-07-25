---
dossier-header: internal-v1
title: Assets, Dependencies, and Licenses
purpose: Establishes what the project owns, what it borrows, and on what terms — the questions a fork, an acquisition, or a legal review would ask first.
audience: Reviewer, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d0fa737
last-verified: 2026-07-26
review-trigger: A dependency, plugin source, or licence declaration changes; a LICENSE file is added
related: [05-due-diligence/technical-due-diligence-report.md, 03-assurance/security-privacy-and-compliance.md, 00-control/assumptions-questions-and-contradictions.md]
---
# Assets, Dependencies, and Licenses
<!-- contract: references/package-contract-05-due-diligence.md#assets-dependencies-and-licenses -->

The headline finding sits at the top because it governs every other row: **the repository publishes no `LICENSE` file, and GitHub detects no licence for it** [EV-0018], [EV-0019]. Each plugin manifest declares one — six MIT, one Apache-2.0 [EV-0021] — and the README asserts MIT with a badge linking to a file that does not exist [EV-0020]. Under default copyright, an installer or forker has no grant of rights whatever the manifests say. This is CT-0001, and it is unresolved.

## Asset inventory

| Asset | Class | Owner of record | Provenance | Criticality | Maintenance status | Recovery path if lost | Evidence |
|---|---|---|---|---|---|---|---|
| 112 skill files | intellectual property | Daniel Bentes | Written for this repository | critical | active — most recent commit 2026-07-25 | git history in any clone | [EV-0004], [EV-0034] |
| 61 command files | intellectual property | Daniel Bentes | Written here | critical | active | git | [EV-0005] |
| 29 agent definitions | intellectual property | Daniel Bentes | Written here | high | active | git | [EV-0006] |
| 26 helper scripts | code | Daniel Bentes | Written here; `cascade-resolve.sh` exists twice by deliberate copy | high | active | git | [EV-0007] |
| 16 hook scripts | code | Daniel Bentes | Written here | **critical to trust** — they execute on operator machines | active | git | [EV-0040] |
| `marketplace.json` | distribution asset | Daniel Bentes | Written here | critical | active | git | [EV-0001] |
| 2 test suites | quality asset | Daniel Bentes | Written here; dossier's harness copied from flow | high | active | git | [EV-0008], [EV-0009] |
| `agent-capability-standard` tree | borrowed IP | Daniel Bentes, separate repository | Git submodule at `95f7ac2` | medium | pinned 2 commits past `v1.2.0` | the upstream repository | [EV-0031] |
| `prompt-decorators` plugin | borrowed IP | Daniel Bentes, separate repository | `git-subdir` at ref `main` | medium | **never inspected from here** (AQ-0005) | the upstream repository | [EV-0030] |
| 57 release tags and their assets | distribution asset | Daniel Bentes | Built by CI on publish | medium | active — latest v4.6.2 | Rebuildable from any tag | [EV-0032] |
| The `synaptiai/synapti-marketplace` name | brand asset | Daniel Bentes | GitHub namespace | high | active | Not recoverable if the namespace is lost | [EV-0051] |
| 10 decision records | knowledge asset | Daniel Bentes | Produced by the flow plugin during development | low | active | git | [EV-0046] |

## Dependencies

| Dependency | Kind | Direct or transitive | Version | License | Support status | End of life | Known restrictions | Replacement difficulty | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| `pyyaml` | runtime, one plugin | direct | `>=6.0` | MIT | actively maintained | none | none | low | [EV-0041] |
| `claude-agent-sdk` | optional extra | direct | unpinned | per its own terms | active | none | none | medium | [EV-0041] |
| `pytest`, `mypy`, `ruff`, `hypothesis`, `jsonschema`, `types-PyYAML` | development, one plugin | direct | pinned by floor | permissive | active | none | none | low | [EV-0041] |
| `actions/checkout` | CI | direct | `@v4` — **major tag, not a SHA** | MIT | active | none | none | low | [EV-0042] |
| `github/codeql-action` | CI | direct | `@v3` — major tag | MIT | active | none | GitHub's terms for CodeQL on private repositories; this repository is public | low | [EV-0042] |
| `git`, `bash`, `jq`, `gh` | tooling | direct | unpinned | permissive | active | none | none | low | [EV-0007] |
| Claude Code client | platform | direct | whatever the operator has | proprietary, Anthropic | active | none | **Total lock-in.** Nothing in this project functions without it | **none — no replacement exists** | [EV-0043] |
| GitHub | platform | direct | — | proprietary | active | none | Hosting, distribution, CI, releases | low-to-medium | [EV-0051] |

**One declared third-party runtime dependency in the entire repository** [EV-0041]. That is a genuinely strong position for a supply-chain review: the attack surface is not the dependency tree, it is the two external plugin sources and the two unpinned CI actions.

## License obligations

| License | Dependencies under it | Obligation | Triggered by | Does this project trigger it | Evidence |
|---|---|---|---|---|---|
| MIT | `pyyaml`, `actions/checkout`, `github/codeql-action` | Preserve copyright and licence text when redistributing | Redistribution of the covered code | **No** — none of these is redistributed. They are consumed at CI time or installed separately by the operator | [EV-0041], [EV-0042] |
| Apache-2.0 | `agent-capability-standard` (submodule), `prompt-decorators` (external entry) | Preserve notices; state changes; include the licence | Distribution of the covered code | **Yes for the submodule** — its tree is present in this repository and is cloned by every installer. Its own `LICENSE` and manifest travel with it, which satisfies the obligation at the plugin level. It is **not** restated at repository level, where the missing root `LICENSE` compounds the ambiguity | [EV-0021], [EV-0031] |
| **The project's own terms** | its own 112 skills, 61 commands, 29 agents, 42 scripts | Grant recipients rights to use, modify, and redistribute | Publishing source publicly | **Cannot be determined.** Six manifests say MIT, one says Apache-2.0, the README says MIT — and no `LICENSE` file exists, so default copyright applies | [EV-0018], [EV-0019], [EV-0021], CT-0001 |

| Distribution mode | What is distributed | To whom | Obligations that attach |
|---|---|---|---|
| Git clone by the Claude Code client | The whole repository, including the submodule tree | Any operator who adds the marketplace | Whatever the project's own terms grant — **currently undetermined** |
| GitHub release assets | Desktop skill ZIPs built from `SKILL.md` files | Anyone who downloads a release | Same |
| Public repository browsing | Everything | Anyone | Same |

Every row of the second table ends in the same place. Until CT-0001 is resolved, the project distributes source through three channels under terms nobody can state.

## Commercial terms requiring human review

| Party | What is licensed or contracted | Term that needs review | Why | Owner |
|---|---|---|---|---|
| Anthropic | The Claude Code client that executes every artifact | Whether distributing plugins that instruct the client has any term attached | The project's entire distribution depends on it, and no review of its terms is recorded anywhere | Daniel Bentes |
| Recipients of the six MIT-declared plugins | Their grant of rights | Whether a `plugin.json` `license` field constitutes a licence grant absent a `LICENSE` file | The difference between "MIT-licensed" and "all rights reserved with a misleading badge" | Daniel Bentes |
| Contributors, if any join | Copyright assignment or inbound licence | No CLA, no DCO, no `CONTRIBUTING.md` — a contribution's terms would be undefined | AQ-0007 — untested because no external contribution has occurred | Daniel Bentes |

## Generated, copied, vendored, and contributed material

| Material | Origin | Kind | License of origin | Attribution present | Cleared | Evidence |
|---|---|---|---|---|---|---|
| `plugins/dossier/bin/cascade-resolve.sh` | `plugins/flow/bin/cascade-resolve.sh` | copied, then diverged | same project | **no** — neither file records that the other exists | N/A — same owner | [EV-0007] |
| `plugins/dossier/tests/{run.sh,lib/assert.sh}` | the flow test harness | copied, identifiers renamed | same project | no | N/A | [EV-0009] |
| `plugins/agent-capability-standard/**` | `synaptiai/agent-capability-standard` | vendored via submodule | Apache-2.0 | yes — its own `LICENSE` and manifest travel with the tree | yes | [EV-0031] |
| `prompt-decorators` | `synaptiai/prompt-decorators` | referenced, not vendored | Apache-2.0 per its marketplace entry | Not verifiable from here (AQ-0005) | unverified | [EV-0030] |
| `dist/desktop/**` | every `SKILL.md`, via `package-desktop-skills.sh` | generated | inherits the project's terms | N/A | inherits CT-0001 | [EV-0012] |
| External contributions | — | **none exist** | — | — | — | [EV-0035] |

The first row is a maintenance hazard rather than a licensing one, and it has already materialized: the two copies have diverged, dossier's carries a fix flow's does not, and neither points at the other [TD-05].

## Software bill of materials

| Field | Value |
|---|---|
| SBOM produced | **no** |
| Format | — |
| Generated by | — |
| Generated on | — |
| Scope covered | — |
| Scope not covered | — |
| Location | — |

No SBOM exists and no tooling produces one. The mitigating fact is that the complete dependency list fits in the table above — one runtime dependency, two CI actions, and four standard command-line tools [EV-0041], [EV-0042]. An SBOM here would be short enough to be uninteresting, which is a reasonable argument for not having one and not an argument that the supply chain is controlled.

## Vulnerability evidence

| Scan | Tool | Scope | Date | Findings by severity | Source of advisory data | Evidence |
|---|---|---|---|---|---|---|
| Static analysis | CodeQL | `actions`, `python` | 2026-07-25 | 0 reported | GitHub Advisory Database | [EV-0012] |
| Credential scan | `git grep` over the project's own detector pattern set | all tracked files | 2026-07-26 | 0 | the project's own patterns | [EV-0037] |
| Dependency scan | **none exists** — no `dependabot.yml`, no scanning workflow | — | — | — | — | [EV-0036] |
| Shell analysis | **none exists** — no `shellcheck` | — | — | — | — | [EV-0007] |
| Workflow injection scan | `awk` run-block scanner, executed during this assessment | all 4 workflows | 2026-07-26 | **1** — `release-desktop-skills.yml` line 24 | this assessment | [EV-0015] |

CodeQL's clean result covers `actions` and `python`. It does not cover shell, which is the language of all 42 executable files this project ships to operator machines. That gap is the reason the workflow-injection finding was found by hand rather than by a tool.

## Fragile dependencies

| Dependency | Concern | Last upstream release | Maintainers | Consequence if abandoned | Alternative | Evidence |
|---|---|---|---|---|---|---|
| Claude Code client | Total lock-in. Its manifest schema, resolution order, cache layout, and hook contract are external contracts that can change without notice | continuous | Anthropic | Every plugin stops working; nothing in this project can adapt in advance | **none** | [EV-0043] |
| `synaptiai/prompt-decorators` at `ref: main` | Content reaches installers with no commit, review, or record here | unknown from here | Daniel Bentes | Installers of that plugin receive whatever is upstream, including nothing | Pin a tag, or vendor it | [EV-0030] |
| `agent-capability-standard` submodule | Pointer sits 2 commits past the version the marketplace advertises | `v1.2.0` plus 2 commits | Daniel Bentes | The advertised version is not what installs | Move the pointer to the tag | [EV-0031] |
| `pyyaml` | The only third-party runtime dependency | active | community | One plugin's runtime; one optional test leg degrades with a stated skip | vendor, or drop the YAML path | [EV-0041] |

Two of the four fragile dependencies are the project's own repositories, which is unusual and is the good news: both are fixable by one edit each, by the person who already owns them.

## External services and lock-in

| Service | Function | Substitutable | Migration cost driver | Contractual exit terms | Continuity if unavailable | Evidence |
|---|---|---|---|---|---|---|
| Claude Code client | Resolves, installs, and executes everything | **no** | The product is defined in terms of the client's plugin model | none — no contract exists | **The product ceases to function** | [EV-0043] |
| GitHub | Hosting, distribution, CI, releases | partially | The marketplace source kind is git; the client's `github` source form and the Actions workflows are GitHub-specific | standard terms | Existing installs keep working; nothing new publishes | [EV-0051] |
| GitHub Actions | Tests, analysis, release packaging | yes | 4 short workflows | standard terms | Tests run locally; releases are manual | [EV-0012] |
| Anthropic API | Consumed by operators, and by dossier's CI path in a consuming repository | no | — | the operator's own agreement | Plugins that need inference stop working for that operator | [EV-0044] |

## Unknown provenance and ownership

| Item | What is unknown | Why it matters to the decision | What would resolve it | Register ID |
|---|---|---|---|---|
| `prompt-decorators` contents | Whether the published entry matches what it describes, and whether its Apache-2.0 declaration is present in the source | It is published to installers from this manifest under this marketplace's name | Inspecting the `claude-code-plugin` subdirectory upstream | AQ-0005 |
| The 2 commits past `v1.2.0` | What they change | The marketplace advertises a version it does not ship | `git log v1.2.0..95f7ac2` upstream | AQ-0006 |
| The project's own licence terms | Which licence, if any, is granted to recipients | Governs every fork, install, and reuse | Adding a `LICENSE` file | CT-0001 |
| Inbound contribution terms | What terms a contribution would arrive under | No contribution has occurred, so nothing has tested it | A `CONTRIBUTING.md` stating inbound terms | AQ-0007 |

## Items flagged for qualified legal review

| Item | Question for counsel | Why it exceeds a technical assessment | Owner |
|---|---|---|---|
| Missing root `LICENSE` against per-plugin declarations | Does a `license` field in a `plugin.json` constitute an effective grant to a recipient absent a `LICENSE` file, and what is the position of anyone who has already installed or forked in reliance on the README's MIT badge? | Whether a declaration in a metadata file is legally operative is a question of law, not of code. This assessment can establish only that the file is absent and the badge is present | Daniel Bentes |
| Mixed MIT and Apache-2.0 within one distributed tree | Does distributing an Apache-2.0 submodule inside an otherwise-MIT repository create any compatibility or notice obligation at the repository level? | Licence compatibility analysis | Daniel Bentes |
| Inbound contribution terms | Should a CLA or DCO be adopted before the first external contribution? | A policy question with legal consequences | Daniel Bentes |

Three items, all downstream of the same absent file. Resolving CT-0001 narrows the second and third to routine choices.
