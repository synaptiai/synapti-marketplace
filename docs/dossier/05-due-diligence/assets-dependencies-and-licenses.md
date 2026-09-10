---
dossier-header: internal-v1
title: Assets, Dependencies, and Licenses
purpose: Establishes what the project owns, what it borrows, and on what terms — the questions a fork, an acquisition, or a legal review would ask first.
audience: Reviewer, Maintainer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A dependency, plugin source, or licence declaration changes; a LICENSE file is added
related: [05-due-diligence/technical-due-diligence-report.md, 03-assurance/security-privacy-and-compliance.md, 00-control/assumptions-questions-and-contradictions.md]
---
# Assets, Dependencies, and Licenses
<!-- contract: references/package-contract-05-due-diligence.md#assets-dependencies-and-licenses -->

Two facts govern every table below.

**The licence position is settled in the tree.** A `LICENSE` file carrying the canonical Apache-2.0 text sits at the repository root [EV-0019]. The README badge and licence section point at it and resolve [EV-0020]. As read on 2026-07-26 at commit `f57126f`, 7 in-tree plugin manifests and 8 marketplace entries all declared Apache-2.0 [EV-0021]. Six in-tree manifests remain at this HEAD [EV-0182]. The seventh left the tree when `agent-capability-standard` became an externally sourced entry [EV-0058], [EV-0059].

Unknown: GitHub's repository-level licence detection is computed from the default branch, and it was not re-read at this HEAD (AQ-0011). Do not treat the repository badge as confirming Apache-2.0.

Unknown: no evidence row re-reads the licence field of the 6 remaining in-tree manifests at this HEAD. The blob-identity chain that carries other plugin claims forward does not reach back to `f57126f` [EV-0143], [EV-0174]. No register row yet — an AQ row is requested in this draft's handback.

**The dependency surface is undeclared and it is unscanned.** No dependency manifest of any kind is tracked in the repository [EV-0186]. No `.dossier/scan/` directory exists, and no SARIF, osv-scanner or Dependabot artifact is tracked anywhere [EV-0121]. An undeclared surface is not a bounded one. Nothing in this document says the supply chain has no known vulnerabilities.

## Plugin sources and pins

The manifest publishes 8 plugin entries. Six are sources inside this repository. Two are external, and both carry a commit sha.

| Entry | Source kind at HEAD | Pin | Reproducible across days | Evidence |
|---|---|---|---|---|
| `agent-capability-standard` | `github` source, not a submodule and not vendored | sha `9e2f65b` | yes, per the manifest | [EV-0058], [EV-0059], [EV-0060] |
| `prompt-decorators` | `git-subdir` source | sha `9c792fe` | yes, per the manifest | [EV-0058] |
| the other 6 entries | relative-path sources inside this repository | the commit itself | yes | [EV-0058] |

No `.gitmodules` file exists in the tracked tree [EV-0059]. A populated `plugins/agent-capability-standard/` directory is present on the assessment machine, but it is untracked and ignored by `.gitignore` [EV-0060]. It is working-tree residue, not repository content.

Both pinned trees report the version the marketplace advertises. `agent-capability-standard` resolves to 1.2.0 at `9e2f65b`, and `prompt-decorators` resolves to 0.1.1 at `9c792fe` [EV-0127]. That check was executed by the session operator outside this engagement's action ceiling, because `networkAccess` is false (AQ-0012).

Inferred: two installs on different days now resolve the same tree for both entries. Each source carries a commit sha rather than a branch name [EV-0058]. This reads the manifest. No evidence row here observes the Claude Code client performing such an install at the pinned sha.

Unknown: what separates the pinned sha `9e2f65b` from upstream tag `v1.2.0` has not been examined (AQ-0006).

## Asset inventory

Counts are tracked-tree counts unless the row says otherwise.

| Asset | Class | Owner of record | Provenance | Criticality | Maintenance status | Recovery path if lost | Evidence |
|---|---|---|---|---|---|---|---|
| 71 skill files | intellectual property | Daniel Bentes | Written for this repository | critical | active | git history in any clone | [EV-0093] |
| 61 command files | intellectual property | Daniel Bentes | Written here | critical | active | git | [EV-0093] |
| 29 agent definitions | intellectual property | Daniel Bentes | Written here | high | active | git | [EV-0093] |
| 37 plugin `bin/` shell scripts | code | Daniel Bentes | Written here | high | active | git | [EV-0093] |
| Hook scripts: 14 in `flow`, 5 in `dossier`, under 2 `hooks.json` manifests | code | Daniel Bentes | Written here | critical to trust, because they execute on operator machines | active | git | [EV-0093], [EV-0129] |
| `marketplace.json` | distribution asset | Daniel Bentes | Written here | critical | active. Entry-versus-source version drift is checked in CI (TM-0033) | git | [EV-0057], [EV-0080], [EV-0081] |
| 2 shell test suites | quality asset | Daniel Bentes | Written here | high | active. 2336 flow assertions and 1951 dossier assertions pass | git | [EV-0098], [EV-0107] |
| `agent-capability-standard` tree | borrowed IP | Daniel Bentes, separate repository | `github` source pinned to sha `9e2f65b`. Not vendored here | medium | pinned. Reports 1.2.0 [EV-0127] | the upstream repository | [EV-0058], [EV-0059], [EV-0127] |
| `prompt-decorators` plugin | borrowed IP | Daniel Bentes, separate repository | `git-subdir` source pinned to sha `9c792fe`. Not present here | medium | pinned. Reports 0.1.1 [EV-0127]. Contents never inspected (AQ-0005) | the upstream repository | [EV-0058], [EV-0127] |
| 63 git tags | distribution asset | Daniel Bentes | Built by CI on publish | medium | 63 tags at `d3fc744`, all merged into it, and the GitHub tags endpoint returns the same 63 [EV-0177]. The two most recent releases, v4.9.0 and v4.10.0, were published 2026-09-10 [EV-0066]. Unknown: no evidence row counts the assets attached to those tags | Rebuildable from any tag | [EV-0177], [EV-0066] |
| The `synaptiai/synapti-marketplace` name | brand asset | Daniel Bentes | GitHub namespace | high | active | Not recoverable if the namespace is lost | [EV-0051] |
| 21 decision records | knowledge asset | Daniel Bentes | Produced by the flow plugin during development | low | active. `.decisions/` holds 21 tracked `issue-*.md` records at `7ee4923`, superseding the count of 11 read on 2026-07-26 | git | [EV-0169] |

Asset classes with no instance in this project, and one that was not inspected:

| Asset class | Status | Basis |
|---|---|---|
| Deployed services, infrastructure, reserved capacity | N/A | The marketplace has no runtime process. Shipped artifacts execute inside the operator's own client session [EV-0044] |
| Package-registry artifacts | N/A | The project publishes to no package registry. Distribution is a git read by the client [EV-0043, I] |
| Datasets, trained models, model weights | N/A | No dataset or model artifact is tracked. The shipped artifacts are Markdown, JSON and shell [EV-0044] |
| Schemas | N/A as a separate asset | The only declarative contracts are `marketplace.json` and the plugin manifests, inventoried above [EV-0057] |
| Domains, TLS certificates, cloud accounts | Unknown | Not inspected. The project's only observed hosting is the GitHub namespace [EV-0051] (AQ-pending) |
| Device or hardware assets | N/A | No hardware component. The product is plugin content for a client application [EV-0044] |

Backup owner is `unassigned` for every component in the ownership model. That is a single-person concentration, not an oversight of this document.

## Dependencies

| Dependency | Kind | Direct or transitive | Version | License | Support status | End of life | Known restrictions | Replacement difficulty | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| `pyyaml` | runtime, the flow plugin | direct | undeclared. No floor exists anywhere in the tree [EV-0186]. The two CI workflows pin `6.0.2`, which governs CI and not an install [EV-0187] | Unknown: no evidence row establishes it (AQ-pending) | Unknown: not established (AQ-pending) | Unknown (AQ-pending) | Not declared where an operator installing the plugin would see it [EV-0187] | Inferred: not low. It carries flow's journal and run-state machinery [EV-0189, I] | [EV-0186], [EV-0187], [EV-0189] |
| `actions/checkout` | CI | direct | `@v4`, a major tag rather than a commit sha | MIT | active | none stated | none | low | [EV-0042] |
| `github/codeql-action` | CI | direct | `@v3`, a major tag rather than a commit sha | MIT | active | none stated | GitHub's terms for CodeQL on private repositories. This repository is public | low | [EV-0042] |
| `git`, `bash`, `jq`, `gh`, `python3` | tooling | direct | unpinned, and not enumerated by any manifest [EV-0186] | permissive | active | none stated | `python3` runs the flow entrypoints that import PyYAML [EV-0187]. Inferred: the other four are required by the shell scripts, from [EV-0093]. No row enumerates the set | low | [EV-0093], [EV-0186], [EV-0187] |
| Claude Code client | platform | direct | whatever the operator has | proprietary, Anthropic | active | none stated | Inferred: total lock-in. Nothing here functions without it | no replacement exists | [EV-0043, I] |
| GitHub | platform | direct | — | proprietary | active | none stated | Hosting, distribution, CI, releases | low to medium | [EV-0051] |

Nothing in this repository declares a third-party dependency. No `requirements` file, `pyproject.toml`, `package.json`, `Gemfile`, `go.mod`, `Cargo.toml`, `setup.py` or `Pipfile` is tracked [EV-0186]. The `pyproject.toml` that carried `pyyaml>=6.0` belonged to `agent-capability-standard`, which left the tree when that plugin became an externally sourced entry [EV-0186], [EV-0162]. No development dependency is declared either [EV-0186].

One package is required all the same. PyYAML is a hard runtime requirement of the flow plugin's journal and run-state machinery, not an optional test dependency [EV-0189]. Two flow Python entrypoints import it, and no file an operator reads before installing names it [EV-0187]. The register carries this as CL-0048, which is pending approval and therefore stays out of the public documents.

Unknown: whether `jsonschema` is a second undeclared requirement of the same shape. No evidence row covers it (AQ-pending).

One dossier test does degrade gracefully when PyYAML is absent. `workflow-template.test.sh` records a pass with a skip reason [EV-0107]. That is one leg of one test, and it describes that test rather than the dependency surface.

CI consumes two third-party action sources, both pinned by major tag rather than by commit sha [EV-0042]. A major tag is mutable. The publisher can move `v4` to any commit, and this repository's CI will execute it without a review here. That is a supply-chain exposure. It sits beside the undeclared PyYAML requirement above [EV-0186], [EV-0187], and both plugin sources are sha-pinned by comparison.

## License obligations

| License | Dependencies under it | Obligation | Triggered by | Does this project trigger it | Evidence |
|---|---|---|---|---|---|
| MIT | `actions/checkout`, `github/codeql-action` | Preserve copyright and licence text on redistribution | Redistribution of the covered code | No copy of either is tracked in this repository. Both are referenced by workflow files [EV-0042] | [EV-0042] |
| Apache-2.0 | `agent-capability-standard`, `prompt-decorators` | Preserve notices, state changes, include the licence | Distribution of the covered code | Neither tree is tracked in this repository [EV-0059], [EV-0060]. The manifest declares an external source and a sha for each [EV-0058]. Whether publishing such an entry is itself distribution is flagged for counsel below | [EV-0058], [EV-0059], [EV-0060] |
| Apache-2.0, the project's own licence | Its own 71 skills, 61 commands, 29 agents, 37 scripts | Preserve notices, state changes, include the licence. The patent grant and its termination clause bind both directions | Publishing source publicly, and any redistribution by a recipient | The licence text is present at the repository root [EV-0019], and the manifests declare the same identifier as read 2026-07-26 [EV-0021] | [EV-0019], [EV-0020], [EV-0021], [EV-0093] |

PyYAML has no row in this table. Its licence was previously read from a manifest that is no longer in the tree [EV-0186], and it is imported rather than redistributed [EV-0187].

Unknown: PyYAML's licence terms, and whether any vendored copy exists here. No evidence row establishes either (AQ-pending).

Unknown: whether the `agent-capability-standard` tree at sha `9e2f65b` carries its own `LICENSE` file (AQ-pending). EV-0127 established the version that tree reports, not its licence text. The only local copy is untracked residue at an older pointer [EV-0060].

| Distribution mode | What is distributed | To whom | Obligations that attach |
|---|---|---|---|
| Git clone by the Claude Code client | This repository and its 6 in-tree plugin sources. The manifest points the other 2 entries at external repositories [EV-0058] | Any operator who adds the marketplace | Apache-2.0. Retain the licence and notices, state changes on modification |
| GitHub release assets | Desktop skill ZIPs built from `SKILL.md` files | Anyone who downloads a release | Same |
| Public repository browsing | Everything tracked | Anyone | Same |

All three channels carry the same terms. A recipient's rights do not depend on which channel they arrived through.

## Commercial terms requiring human review

| Party | What is licensed or contracted | Term that needs review | Why | Owner |
|---|---|---|---|---|
| Anthropic | The Claude Code client that executes every artifact | Whether distributing plugins that instruct the client has any term attached | The project's entire distribution depends on it. No review of its terms is recorded anywhere | Daniel Bentes |
| Anyone who cloned or forked before 2026-07-26 | Their grant of rights for that copy | Whether a copy taken while no `LICENSE` file existed is covered by the licence added afterwards | This is a question of law, not of code | Daniel Bentes |
| Contributors, if any join | Copyright assignment or inbound licence | No CLA, no DCO, no `CONTRIBUTING.md`. A contribution's terms would be undefined | AQ-0007. No commit authored by a third party is established [EV-0192], so nothing has tested the path. 22 commits carry an assistant co-author identity whose rights position is unexamined [EV-0192] | Daniel Bentes |

## Generated, copied, vendored, and contributed material

| Material | Origin | Kind | License of origin | Attribution present | Cleared | Evidence |
|---|---|---|---|---|---|---|
| `plugins/dossier/bin/cascade-resolve.sh` | `plugins/flow/bin/cascade-resolve.sh` | Unknown: no evidence row records the copy or its divergence at this HEAD (AQ-pending) | same project | unestablished | N/A, same owner | [EV-0093] |
| `plugins/dossier/tests/{run.sh,lib/assert.sh}` | the flow test harness | Unknown: no evidence row records the copy (AQ-pending) | same project | unestablished | N/A, same owner | [EV-0107] |
| `plugins/agent-capability-standard/**` | `synaptiai/agent-capability-standard` | **not vendored at HEAD.** Fetched by the client from a `github` source at sha `9e2f65b` | Apache-2.0 per its marketplace entry | Not established at the pinned sha | unverified | [EV-0058], [EV-0059], [EV-0060] |
| `prompt-decorators` | `synaptiai/prompt-decorators` | referenced at sha `9c792fe`, not vendored | Apache-2.0 per its marketplace entry | Not verifiable from here (AQ-0005) | unverified | [EV-0058] |
| `dist/desktop/**` | every `SKILL.md`, via `package-desktop-skills.sh` | generated | Apache-2.0, inherited from the project | N/A | yes | [EV-0019], [EV-0123] |
| Commits carrying a second author identity | this repository's own history | 22 of the 480 commits across all refs carry `Claude <noreply@anthropic.com>`, which the ledger records as an assistant co-author trailer rather than a third-party contributor [EV-0192]. `main`'s 214 commits carry one identity [EV-0163] | Unknown: no evidence row establishes the terms these commits arrived under (AQ-0007) | yes, as a commit trailer [EV-0192] | no. Flagged for counsel below | [EV-0163], [EV-0192] |

No evidence row establishes a commit authored by a person other than the owner [EV-0192]. That is a narrower statement than "no external contribution exists". An identity count is not a contributor count, and [EV-0192] says so on its own row.

Unknown: whether the 22 commits under the assistant identity change this project's inbound-rights position. The nearest register row is AQ-0007, which asks a different question: whether the contribution path works for anyone but the maintainer. No row asks the rights question directly. A dedicated AQ row is requested in this draft's handback, and the question is carried to counsel below.

Unknown: whether the two `cascade-resolve.sh` copies still diverge (AQ-pending). The debt register carries the item as [TD-05]. Either way this is a maintenance hazard, not a licensing one.

## Software bill of materials

| Field | Value |
|---|---|
| SBOM produced | no |
| Format | — |
| Generated by | — |
| Generated on | — |
| Scope covered | — |
| Scope not covered | — |
| Location | — |

No SBOM exists and no tooling produces one. There is also no declared list to convert into one, because the repository declares nothing [EV-0186]. What the system actually requires is PyYAML [EV-0187], [EV-0189], two CI actions [EV-0042], two sha-pinned plugin sources [EV-0058], and five command-line tools including `python3` [EV-0093], [EV-0187]. That set was assembled by reading code, which is the work an SBOM exists to avoid repeating.

## Vulnerability evidence

| Scan | Tool | Scope | Date | Findings by severity | Source of advisory data | Evidence |
|---|---|---|---|---|---|---|
| Dependency vulnerability scan | **no vulnerability-scan output located** | — | — | — | — | [EV-0121] |
| Static analysis | CodeQL | `actions` and `python`, both `build-mode: none`. flow's 3 `bin/*.py` files sit under the scanned path. The 37 tracked `bin/*.sh` files do not [EV-0176], [EV-0175] | runs green across the range, 2026-09-10 | **Unknown.** A green run means the analysis completed, not that it reported nothing (AQ-pending) | GitHub Advisory Database | [EV-0123], [EV-0126] |
| Credential scan | `git grep` over the project's own detector pattern set | all tracked files | 2026-07-26 | 0 | the project's own patterns | [EV-0037] |
| Shell analysis | shellcheck v0.11.0 at `-S warning`, installed by pinned release URL in `dossier-tests.yml`. No other workflow runs it [EV-0165] | dossier's 20 `bin/` and 5 hook scripts, plus dossier's tests with `-x`. flow's 17 `.sh` bin scripts and 14 hook scripts are outside it [EV-0165], [EV-0175], [EV-0129] | present in the workflow at `7ee4923` [EV-0165]. **Unknown:** no evidence row records a run of this step | **Unknown.** No evidence row records the step's finding count | shellcheck's own rule set | [EV-0165], [EV-0175], [EV-0129] |
| Workflow injection scan | `awk` run-block scanner, executed during the 2026-07-26 round | the 4 workflows then present | 2026-07-26 | 1, in `release-desktop-skills.yml` | this assessment | [EV-0015] |

Three limits on this table. First, no dependency-vulnerability scan has ever run here [EV-0121], [EV-0078]. Second, CodeQL configures `actions` and `python` only [EV-0176], and no configured language covers the 37 tracked `bin/*.sh` files. shellcheck covers 20 of those 37, all of them in dossier [EV-0165], [EV-0175].

Third, the credential and workflow-injection results are dated 2026-07-26 against a 4-workflow tree. Five workflows exist at HEAD [EV-0123], and neither check was re-run at this HEAD.

Unknown: the CodeQL finding count at this HEAD. Alerts do not fail the workflow, so a green run does not establish zero.

The green-run result was observed by the session operator outside this engagement's action ceiling [EV-0126] (AQ-0012).

## Fragile dependencies

| Dependency | Concern | Last upstream release | Maintainers | Consequence if abandoned | Alternative | Evidence |
|---|---|---|---|---|---|---|
| Claude Code client | Inferred: total lock-in. Its manifest schema, resolution order, cache layout, and hook contract can change without notice | continuous | Anthropic | Every plugin stops working. Nothing here can adapt in advance | none | [EV-0043, I] |
| `actions/checkout@v4`, `github/codeql-action@v3` | Mutable major tags. The publisher can move the tag under this repository's CI | continuous | GitHub | CI executes code that was never reviewed here | Pin each to a commit sha | [EV-0042] |
| `synaptiai/agent-capability-standard` at `9e2f65b` | The pin is reproducible, but the distance from tag `v1.2.0` is unexamined | `v1.2.0` | Daniel Bentes | Installers receive a tree nobody here has read | Read the diff, or move the pin to the tag | [EV-0058], [EV-0127], AQ-0006 |
| `synaptiai/prompt-decorators` at `9c792fe` | The pin is reproducible. The contents have never been inspected from here | unknown from here | Daniel Bentes | Installers receive a plugin published under this marketplace's name and unread | Inspect the subdirectory upstream | [EV-0058], AQ-0005 |
| `pyyaml` | Required at runtime by code inside this repository, and declared by no file an operator installing the plugin reads [EV-0187], [EV-0189] | Unknown (AQ-pending) | Unknown (AQ-pending) | Flow's journal and run-state machinery stops working on a machine without it [EV-0189]. Unknown: the failure mode each caller presents is not established by any evidence row (AQ-pending) | Declare it in a manifest, vendor it, or drop the YAML path | [EV-0186], [EV-0187], [EV-0189] |

Both external plugin sources are repositories under the same owner. Each is fixable by one edit, by the person who already owns them.

## External services and lock-in

| Service | Function | Substitutable | Migration cost driver | Contractual exit terms | Continuity if unavailable | Evidence |
|---|---|---|---|---|---|---|
| Claude Code client | Resolves, installs, and executes everything | no | The product is defined in terms of the client's plugin model | none. No contract exists | Inferred: the product ceases to function | [EV-0043, I], [EV-0044] |
| GitHub | Hosting, distribution, CI, releases | partially | The client's `github` and `git-subdir` source forms and the Actions workflows are GitHub-specific | standard terms | Existing installs keep working. Nothing new publishes | [EV-0051], [EV-0058] |
| GitHub Actions | Tests, analysis, release packaging, manifest check | yes | 5 short workflows | standard terms | Tests run locally. Releases become manual | [EV-0123], [EV-0126] |
| Anthropic API | Consumed by operators, and by dossier's CI path in a consuming repository | no | — | the operator's own agreement | Plugins needing inference stop working for that operator | [EV-0044] |

## Unknown provenance and ownership

Unknown provenance is a material diligence risk here, not a bookkeeping gap. Two of eight published plugins are fetched from outside this repository, and neither tree has been read from here.

| Item | What is unknown | Why it matters to the decision | What would resolve it | Register ID |
|---|---|---|---|---|
| `prompt-decorators` contents at `9c792fe` | Whether the published entry matches what it describes, and whether its Apache-2.0 declaration appears in the source | It is published to installers under this marketplace's name | Inspecting the `claude-code-plugin` subdirectory at that sha | AQ-0005 |
| The distance from `v1.2.0` to `9e2f65b` | What those commits change | The pin is reproducible but unreviewed | `git log v1.2.0..9e2f65b` upstream | AQ-0006 |
| GitHub's derived licence field | Whether the repository badge and automated scanners report Apache-2.0 | Every licence scanner reads the derived field, not the file | Re-reading `gh api repos/…` once this branch merges | AQ-0011 |
| Inbound contribution terms | What terms a contribution would arrive under | No contribution has occurred, so nothing has tested it | A `CONTRIBUTING.md` stating inbound terms | AQ-0007 |
| Dependency vulnerability status | Whether PyYAML [EV-0187] or either CI action [EV-0042] carries a known advisory | No vulnerability-scan artifact was located [EV-0078, U], [EV-0121] | One `osv-scanner` run, or enabling Dependabot | AQ-pending |

## Items flagged for qualified legal review

| Item | Question for counsel | Why it exceeds a technical assessment | Owner |
|---|---|---|---|
| Copies taken before the licence was added | What is the position of anyone who installed or forked while the README's MIT badge pointed at a file that did not exist? | Whether a metadata declaration was legally operative, and whether a later licence covers an earlier copy, are questions of law | Daniel Bentes |
| Relicensing six plugins from MIT to Apache-2.0 | The sole author holds copyright in all of them. Does the change bind a recipient who took a copy under the earlier declaration? | Relicensing analysis | Daniel Bentes |
| Inbound contribution terms | Should a CLA or DCO be adopted before the first external contribution? | A policy question with legal consequences | Daniel Bentes |
| Commits recorded under an assistant co-author identity | Do 22 commits carrying `Claude <noreply@anthropic.com>` [EV-0192] affect authorship, copyright ownership, or the inbound licence position for this repository? | Authorship and copyrightability of machine-assisted contributions is a question of law, not of code | Daniel Bentes |
| Redistribution of two externally sourced plugins | Does publishing a marketplace entry that causes a client to fetch third-party code constitute distribution of that code? | The repository no longer carries either tree [EV-0058], [EV-0059]. Whether that changes the obligation is a legal question | Daniel Bentes |

## Recommendations

Recommendation: pin `actions/checkout` and `github/codeql-action` to commit shas rather than major tags. Both are mutable today [EV-0042].

Recommendation: declare PyYAML in a manifest an operator reads before installing the flow plugin. Nothing in the repository declares it today [EV-0186], [EV-0187].

Recommendation: run one dependency-vulnerability scan and retain its output. None has ever run [EV-0121].

Recommendation: read the upstream diff from `v1.2.0` to `9e2f65b`, and inspect `prompt-decorators` at `9c792fe`. Both close standing provenance gaps (AQ-0005, AQ-0006).

None of the above is implemented. Each describes a change, not the present state.

## Canonical sources of truth

| Question | Where the answer lives |
|---|---|
| What each plugin's source and pin is | `.claude-plugin/marketplace.json` |
| Whether an entry's advertised version matches its source | `scripts/check-plugin-versions.sh`, run by `marketplace-manifest.yml` [EV-0080], [EV-0081] |
| The project's licence text | `LICENSE` at the repository root [EV-0019] |
| Entity names, owners, and boundaries | `00-control/terminology-and-ownership.md` |
| Every claim above | `00-control/evidence-ledger.md` |
