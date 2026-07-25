---
dossier-header: internal-v1
title: Evidence Ledger
purpose: Lets a reader check whether any claim elsewhere in this package is grounded, and in what, before acting on it.
audience: Reviewer, Maintainer, Installing operator
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d0fa737
last-verified: 2026-07-26
review-trigger: Any change under plugins/, .claude-plugin/marketplace.json, .github/workflows/, or README.md
related: [00-control/assumptions-questions-and-contradictions.md, 00-control/claim-and-disclosure-register.md, 00-control/documentation-index.md]
---
# Evidence Ledger
<!-- contract: references/package-contract-00-control.md#evidence-ledger -->

## Method

Every material claim in this package traces to one row below. Column definitions, the `EV-####` grammar, append-only rules, and the `[EV-####]` citation syntax are specified in the plugin reference `references/evidence-ledger-schema.md`.

**Claim states**

| State | Meaning |
|---|---|
| `V` | Verified — directly supported by authoritative, current evidence, or by an executed check whose output is retained |
| `C` | Corroborated — two independent current sources agree, at least one authoritative for the claim type |
| `R` | Reported — stated by a stakeholder or existing document, not independently verified |
| `I` | Inferred — reasoned from indirect evidence, chain stated |
| `U` | Unknown — required information unavailable, inaccessible, or contradictory |
| `N/A` | Not applicable — demonstrably irrelevant, with a reason |

Only `V` and `C` may appear unqualified in public documents. Absence of evidence is never recorded as evidence of absence.

**Authority levels**

| Level | Source class | Instantiated here as |
|---:|---|---|
| 1 | Observed runtime behaviour and reproducible checks | Shell commands executed against the working tree at `d0fa737`, and `gh api` reads of live repository state |
| 2 | Versioned code, schemas, infrastructure, tests, immutable records | Tracked files — `marketplace.json`, `plugin.json`, `SKILL.md`, `hooks.json`, workflow YAML, shell scripts |
| 3 | Current operational telemetry and release evidence | GitHub release list, tag list, Actions run history, issue and pull-request state |
| 4 | Current approved specifications and decision records | `.claude/CLAUDE.md`, `.decisions/*.md`, plugin `references/*.md` |
| 5 | Tickets, planning documents, existing prose documentation | Repository `README.md`, per-plugin `README.md` and `CHANGELOG.md` |
| 6 | Stakeholder recollection | Not used — no claim in this package rests on recollection |
| 7 | Inference | Reasoning from the above, with the chain stated in the row |

## Evidence table

Locator prefixes: `file:` a tracked path · `cmd:` an executed check, output in the executed-checks table · `api:` a GitHub REST read.

| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EV-0001 | The marketplace publishes 8 plugin entries | V | `.claude-plugin/marketplace.json` | yes | 2 | d0fa737 | 2026-07-26 | until marketplace.json changes | Public | yes | 01, 02, 06 | `jq` over `.plugins` → 8 |
| EV-0002 | Marketplace metadata version is 4.7.0 | V | `.claude-plugin/marketplace.json` | yes | 2 | d0fa737 | 2026-07-26 | until next release | Public | no | 01, 04 | Branch state; exceeds the latest published tag — see EV-0033 |
| EV-0003 | 6 plugins are vendored in-tree, 1 is a git submodule, 1 is an external `git-subdir` source | V | `.gitmodules`, `.claude-plugin/marketplace.json` | yes | 2 | d0fa737 | 2026-07-26 | until sources change | Public | yes | 02, 05 | Submodule `agent-capability-standard`; subdir `prompt-decorators` |
| EV-0004 | 112 `SKILL.md` files exist across the 7 in-tree plugin trees | V | `cmd:CHK-01` | yes | 1 | d0fa737 | 2026-07-26 | until a skill is added or removed | Public | yes | 02, 06 | 42 + 15 + 5 + 2 + 9 + 32 + 7 |
| EV-0005 | 61 command definition files exist | V | `cmd:CHK-01` | yes | 1 | d0fa737 | 2026-07-26 | until a command changes | Public | no | 02, 06 | `find plugins -path '*/commands/*.md'` |
| EV-0006 | 29 agent definition files exist | V | `cmd:CHK-01` | yes | 1 | d0fa737 | 2026-07-26 | until an agent changes | Public | no | 02 | |
| EV-0007 | 26 shell scripts exist under plugin `bin/` directories | V | `cmd:CHK-01` | yes | 1 | d0fa737 | 2026-07-26 | until a script changes | Public | no | 02, 03 | The main body of executable code the marketplace ships |
| EV-0008 | The flow test suite reports 1022 passing assertions and 0 failures | V | `cmd:CHK-02` | yes | 1 | d0fa737 | 2026-07-26 | until flow changes | Public | yes | 03, 05 | `plugins/flow/tests/run.sh` |
| EV-0009 | The dossier test suite reports 1034 passing assertions and 0 failures | V | `cmd:CHK-03` | yes | 1 | d0fa737 | 2026-07-26 | until dossier changes | Public | yes | 03, 05 | `plugins/dossier/tests/run.sh` |
| EV-0010 | Only 2 of the 7 in-tree plugins carry a shell test suite | V | `cmd:CHK-04` | yes | 1 | d0fa737 | 2026-07-26 | until a suite is added | Public | yes | 03, 04, 05 | flow and dossier only |
| EV-0011 | `agent-capability-standard` carries a Python test suite | V | `plugins/agent-capability-standard/tests/` | yes | 2 | 95f7ac2 | 2026-07-26 | until the submodule pointer moves | Public | no | 03, 05 | pytest; not executed here — see CHK-09 |
| EV-0012 | The repository defines 4 GitHub Actions workflows | V | `.github/workflows/` | yes | 2 | d0fa737 | 2026-07-26 | until workflows change | Public | yes | 02, 03, 04 | codeql, dossier-tests, flow-tests, release-desktop-skills |
| EV-0013 | Both plugin test workflows declare `permissions: contents: read` | V | `cmd:CHK-05` | yes | 1 | d0fa737 | 2026-07-26 | until workflows change | Public | no | 03 | |
| EV-0014 | `codeql.yml` declares no top-level `permissions` block | V | `cmd:CHK-05` | yes | 1 | d0fa737 | 2026-07-26 | until the workflow changes | Public | no | 03, 04 | Falls back to the repository-default token scope |
| EV-0015 | `release-desktop-skills.yml` interpolates `${{ github.event.release.tag_name }}` inside a `run:` body | V | `cmd:CHK-06` | yes | 1 | d0fa737 | 2026-07-26 | until the workflow changes | Public | no | 03, 04 | Detected by the same rule the dossier CI template enforces on itself |
| EV-0016 | The `main` branch has no branch-protection configuration | V | `cmd: gh api branches/main/protection` | yes | 1 | live | 2026-07-26 | 30 days | Public | yes | 03, 04, 05 | HTTP 404 "Branch not protected" |
| EV-0017 | The repository defines no rulesets | V | `cmd: gh api rulesets` | yes | 1 | live | 2026-07-26 | 30 days | Public | yes | 03, 04, 05 | Empty array |
| EV-0018 | GitHub's repository-level licence detection still reports `null`, because it is computed from the default branch and `LICENSE` exists only on this one | V | `cmd: gh api repos/synaptiai/synapti-marketplace` | yes | 1 | live | 2026-07-26 | until this branch merges | Public | no | 05 | The per-ref licence endpoint returns 404 for a non-default ref, so branch-level detection cannot be observed at all. Detection resolves on merge — tracked as AQ-0011 |
| EV-0019 | A `LICENSE` file exists at the repository root carrying the canonical Apache-2.0 text, and the same blob is present on the remote | C | `LICENSE`, `cmd:CHK-29` | yes | 2 | f57126f | 2026-07-26 | until the file changes | Public | yes | 05 | 201 lines, 11312 bytes. Copyright line reads `Copyright 2025-2026 Synapti AI` |
| EV-0020 | `README.md` renders an Apache-2.0 badge whose link target is `LICENSE`, and the target now resolves | V | `README.md` | yes | 2 | f57126f | 2026-07-26 | until README changes | Public | yes | 05 | Resolves CT-0001 — the badge, the licence section, and the file agree |
| EV-0021 | All 7 in-tree `plugin.json` files and all 8 marketplace entries declare Apache-2.0, matching the `LICENSE` file | V | `cmd:CHK-08` | yes | 1 | f57126f | 2026-07-26 | until a declaration changes | Public | yes | 05 | Previously 6 MIT and 1 Apache-2.0 against no LICENSE file at all |
| EV-0022 | The README plugin-count badge reads 6; the marketplace publishes 8 | V | `cmd:CHK-10` | yes | 1 | d0fa737 | 2026-07-26 | until README changes | Public | no | 04, 06 | |
| EV-0023 | `README.md` contains no occurrence of the string "dossier" | V | `cmd:CHK-10` | yes | 1 | d0fa737 | 2026-07-26 | until README changes | Public | no | 04, 06 | A published plugin absent from the storefront |
| EV-0024 | The README plugin table lists flow at 3.2.0; `marketplace.json` says 3.2.2 | V | `cmd:CHK-10` | yes | 1 | d0fa737 | 2026-07-26 | until README changes | Public | no | 04 | |
| EV-0025 | The README lists prompt-decorators at 0.1.0; `marketplace.json` says 0.1.1 | V | `cmd:CHK-10` | yes | 1 | d0fa737 | 2026-07-26 | until README changes | Public | no | 04 | |
| EV-0026 | For all 7 in-tree plugins, `plugin.json.version` equals the `marketplace.json` entry version | V | `cmd:CHK-11` | yes | 1 | d0fa737 | 2026-07-26 | until a version changes | Public | no | 03, 04 | The machine-readable pair is consistent; the prose is not |
| EV-0027 | The `ai-first-org-design-kit` description says "Fourteen opinionated skills"; the tree contains 15 | V | `cmd:CHK-12` | yes | 1 | d0fa737 | 2026-07-26 | until the description or skill set changes | Public | no | 04 | |
| EV-0028 | The flow README claims "33 skills"; the tree contains 32 `SKILL.md` files | V | `cmd:CHK-12` | yes | 1 | d0fa737 | 2026-07-26 | until flow changes | Public | no | 04 | |
| EV-0029 | `plugins/flow/skills/learned/` contains only `.gitkeep` and no `SKILL.md` | V | `cmd:CHK-13` | yes | 1 | d0fa737 | 2026-07-26 | until the directory is populated | Public | no | 02, 04 | Directory-counting yields 33, file-counting 32 — the origin of EV-0028 |
| EV-0030 | The `prompt-decorators` marketplace source pins `ref: "main"` | V | `.claude-plugin/marketplace.json` | yes | 2 | d0fa737 | 2026-07-26 | until the entry changes | Public | yes | 02, 05 | A floating ref; two installs on different days need not agree |
| EV-0031 | The `agent-capability-standard` submodule is pinned to `95f7ac2`, 2 commits past tag `v1.2.0` | V | `cmd:CHK-14` | yes | 1 | d0fa737 | 2026-07-26 | until the pointer moves | Public | no | 02, 05 | `git describe` → `v1.2.0-2-g95f7ac2` |
| EV-0032 | 57 git tags exist; the latest published release is `v4.6.2`, dated 2026-05-29 | V | `cmd:CHK-15`, `cmd: gh api releases` | yes | 3 | live | 2026-07-26 | until the next release | Public | yes | 03, 04 | |
| EV-0033 | `marketplace.json` metadata version 4.7.0 has no corresponding release tag | V | `derived: EV-0002 + EV-0032` | yes | 1 | d0fa737 | 2026-07-26 | until 4.7.0 is released | Public | no | 04 | Expected on an unmerged feature branch |
| EV-0034 | The default branch has 194 commits; first 2025-12-19, most recent 2026-07-25 | V | `cmd:CHK-16` | yes | 1 | d0fa737 | 2026-07-26 | continuously | Public | no | 01, 04 | |
| EV-0035 | All commits across all refs carry one author identity, Daniel Bentes | V | `cmd:CHK-17` | yes | 1 | d0fa737 | 2026-07-26 | until another contributor commits | Public | yes | 01, 04, 05 | `git shortlog -sne --all` returns a single line, 351 commits |
| EV-0036 | The repository has no `SECURITY.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `dependabot.yml`, issue templates, or pull-request template | V | `cmd:CHK-18` | yes | 1 | d0fa737 | 2026-07-26 | until any is added | Public | yes | 03, 04, 05 | 9 of 9 paths absent |
| EV-0037 | No credential matching the repository's own detector pattern set appears in tracked files outside detector definitions and their fixtures | V | `cmd:CHK-19` | yes | 1 | d0fa737 | 2026-07-26 | every commit | Public | yes | 03 | A negative result over a known pattern set, not proof of absence |
| EV-0038 | The flow plugin ships 12 hook scripts, including `block-secrets.sh`, `block-destructive.sh`, and `block-force-push.sh` | V | `plugins/flow/hooks/scripts/` | yes | 2 | d0fa737 | 2026-07-26 | until hooks change | Public | yes | 02, 03 | |
| EV-0039 | The dossier plugin ships 4 hook scripts enforcing output-root containment, the action ceiling, claim registration, and header staleness | V | `plugins/dossier/hooks/scripts/` | yes | 2 | d0fa737 | 2026-07-26 | until hooks change | Public | yes | 02, 03 | |
| EV-0040 | 3 of the 7 in-tree plugins register hooks | V | `cmd:CHK-20` | yes | 1 | d0fa737 | 2026-07-26 | until hooks change | Public | yes | 02, 03 | flow, dossier, agent-capability-standard |
| EV-0041 | The only declared third-party runtime dependency in the repository is `pyyaml>=6.0` | V | `plugins/agent-capability-standard/pyproject.toml` | yes | 2 | 95f7ac2 | 2026-07-26 | until the manifest changes | Public | yes | 05 | The single dependency manifest in the tree |
| EV-0042 | CI consumes 2 third-party action sources: `actions/checkout@v4` and `github/codeql-action@v3` | V | `cmd:CHK-21` | yes | 1 | d0fa737 | 2026-07-26 | until workflows change | Public | no | 03, 05 | Pinned by major tag, not by commit SHA |
| EV-0043 | The marketplace publishes to no package registry; distribution is a git read performed by the Claude Code plugin client | I | `inference: EV-0001, absence of any publish step in the 4 workflows` | yes | 7 | d0fa737 | 2026-07-26 | until a publish step is added | Public | no | 02, 04 | Chain: no root package manifest, no publish job, and every in-tree entry's `source` is a repository-relative path |
| EV-0044 | The marketplace has no runtime process; shipped artifacts are Markdown, JSON, and shell executed inside the operator's own Claude Code session | V | `derived: EV-0004..EV-0007, EV-0041` | yes | 2 | d0fa737 | 2026-07-26 | until an executable service is added | Public | yes | 02, 03, 04 | Determines that most availability and observability questions are `N/A` |
| EV-0045 | The dossier post-merge refresh workflow has never executed in this repository | V | `cmd:CHK-22` | yes | 1 | live | 2026-07-26 | until it runs | Public | yes | 03, 04, 05 | Actions history lists 4 workflow names; the refresh job is not among them |
| EV-0046 | `.decisions/` holds 10 tracked decision records | V | `cmd:CHK-23` | yes | 1 | d0fa737 | 2026-07-26 | until a record is added | Public | no | 04 | |
| EV-0047 | The dossier scaffold created 23 of 23 canonical files with 0 failures | V | `cmd:CHK-24` | yes | 1 | d0fa737 | 2026-07-26 | one-time | Public | no | 07 | |
| EV-0048 | `dossier-validate-config.sh` reports `CONFIG_VALID=true` with 0 findings for this project's configuration | V | `cmd:CHK-25` | yes | 1 | d0fa737 | 2026-07-26 | until the configuration changes | Public | no | 07 | |
| EV-0049 | 2 pull requests and 2 issues are open; both open issues concern Windows and Git Bash portability | V | `cmd: gh api issues`, `cmd: gh api pulls` | yes | 3 | live | 2026-07-26 | days | Public | yes | 04 | Issues #100 and #130 |
| EV-0050 | 62 pull requests have been merged | V | `cmd: gh api pulls?state=merged` | yes | 3 | live | 2026-07-26 | days | Public | no | 04 | Against 194 commits on the default branch |
| EV-0051 | The Claude Code client resolves this marketplace from `source: github, repo: synaptiai/synapti-marketplace` and holds a clone last updated 2026-07-20 with `autoUpdate: true` | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until the client re-syncs | Public | yes | 02, 04, 06 | Observed on the assessment machine, not on a clean profile |
| EV-0052 | 6 plugins from this marketplace are installed and cached on the assessment machine | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until install state changes | Public | yes | 04, 06 | flow, gh-workflow, decipon, context-ledger, ai-first-org-design-kit, prompt-decorators |
| EV-0053 | The client's clone populates the `agent-capability-standard` submodule, so a submodule-sourced entry resolves to real files for an installer | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until the client changes | Public | no | 02, 05 | 30 entries present in the client's copy of the submodule path |
| EV-0055 | The flow test suite failed 4 assertions in `flow-goal-stop.test.sh` on one run, then passed 10 consecutive runs including 6 back-to-back | V | `cmd:CHK-31` | yes | 1 | f57126f | 2026-07-26 | until reproduced or fixed | Public | no | 03 | Not reproduced. Recorded because an intermittent failure in a suite that is already advisory is worth less than its pass count suggests |
| EV-0056 | Both test suites leaked temp directories every run — flow ~254, dossier ~81 — because test files are sourced and an `EXIT` trap set by one is replaced by the next file's | V | `cmd:CHK-32` | yes | 1 | f57126f | 2026-07-26 | until fixed | Public | no | 03 | Measured by counting `TMPDIR` entries before and after a run. Fixed in dossier by scoping `TMPDIR` to a runner-owned directory; still present in flow |
| EV-0054 | The client's cached manifest reports metadata version 4.6.2 with 7 plugin entries | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until the next release | Public | yes | 04 | The published `main` state; corroborates that 4.7.0 and the dossier entry exist only on the feature branch [EV-0033] |

## Source inventory and inspection coverage

| Source | Class | Made available | Inspected | Coverage | Note |
|---|---|---|---|---|---|
| `plugins/dossier/` | Source tree | yes | yes | full | The subject of the pull request under which this package was produced |
| `plugins/flow/` | Source tree | yes | yes | sampled | Structure, hooks, and test results verified in full; individual skill prose sampled |
| `plugins/gh-workflow/`, `plugins/decipon/`, `plugins/context-ledger/`, `plugins/ai-first-org-design-kit/` | Source tree | yes | yes | partial | Manifests, structure, and artifact counts verified; prose not audited |
| `plugins/agent-capability-standard/` | Git submodule | yes | yes | partial | Pointer, manifest, and dependency set read from the checked-out tree; upstream history not audited |
| `prompt-decorators` | External `git-subdir` | no | no | none | Not present in this repository; only its marketplace entry is verifiable here |
| `.github/workflows/` | CI definitions | yes | yes | full | All 4 workflows parsed and rule-checked |
| `.claude-plugin/marketplace.json` | Distribution manifest | yes | yes | full | |
| `README.md` | Existing documentation | yes | yes | full | 663 lines; every version and count claim cross-checked against the manifest |
| Live repository settings | GitHub API | yes | yes | full | Protection, rulesets, license detection, releases, issues, Actions history |
| Install analytics | Operational telemetry | no | no | none | Not exposed by GitHub for plugin marketplaces |
| Production telemetry | Operational telemetry | N/A | N/A | none | The project has no runtime (EV-0044) |

## Executed checks

Every `cmd:` locator in the evidence table appears here. A check that could not run is recorded as `not executed` with the reason — never as passed.

| Check | Command | Scope | Environment | Date | Result | Output artifact |
|---|---|---|---|---|---|---|
| CHK-01 | `find plugins -name SKILL.md \| wc -l`, and siblings for commands, agents, and `bin/` | Whole tree | macOS 25.5, zsh | 2026-07-26 | passed | 112 / 61 / 29 / 26 |
| CHK-02 | `plugins/flow/tests/run.sh` | flow plugin | macOS 25.5, bash | 2026-07-26 | passed | `TOTAL pass=1022 fail=0` |
| CHK-03 | `plugins/dossier/tests/run.sh` | dossier plugin | macOS 25.5, bash | 2026-07-26 | passed | `TOTAL pass=1034 fail=0` |
| CHK-04 | `ls plugins/*/tests/run.sh` | Whole tree | macOS 25.5 | 2026-07-26 | passed | 2 matches |
| CHK-05 | `python3` + `yaml.safe_load` per workflow, printing triggers, permissions, and jobs | `.github/workflows/` | python3, pyyaml | 2026-07-26 | passed | 4 workflows parsed |
| CHK-06 | `awk` run-block scanner for `${{ github.event…}}` inside `run:` bodies | `.github/workflows/` | macOS 25.5 | 2026-07-26 | failed | 1 hit: `release-desktop-skills.yml` line 24 |
| CHK-07 | `ls LICENSE` plus a text check for the Apache-2.0 markers | Repository root | macOS 25.5 | 2026-07-26 | passed | Present, 201 lines, Apache-2.0 |
| CHK-08 | `jq -r '.license'` over all 7 plugin manifests and all 8 marketplace entries | In-tree plugins and manifest | jq | 2026-07-26 | passed | 7 of 7 and 8 of 8 Apache-2.0 |
| CHK-09 | `pytest plugins/agent-capability-standard` | Submodule | — | 2026-07-26 | **not executed** | Requires installing a Python environment; `engagement.allowedActions.runBuild` is false. Recorded as AQ-0001 |
| CHK-10 | `grep` of the README badge, version cells, and plugin names | `README.md` | macOS 25.5 | 2026-07-26 | failed | Badge 6 vs 8; flow 3.2.0 vs 3.2.2; prompt-decorators 0.1.0 vs 0.1.1; zero occurrences of "dossier" |
| CHK-11 | Per-plugin comparison of `plugin.json.version` to its marketplace entry | In-tree plugins | jq | 2026-07-26 | passed | 7 of 7 match |
| CHK-12 | Skill counts compared against prose claims | ai-first-org-design-kit, flow | macOS 25.5 | 2026-07-26 | failed | 15 vs "Fourteen"; 32 vs "33 skills" |
| CHK-13 | `ls -la plugins/flow/skills/learned/` | flow | macOS 25.5 | 2026-07-26 | passed | `.gitkeep` only |
| CHK-14 | `git submodule status` | Submodule | git | 2026-07-26 | passed | `v1.2.0-2-g95f7ac2` |
| CHK-15 | `git tag --list \| wc -l`, `gh release list` | Repository | git, gh | 2026-07-26 | passed | 57 tags; latest v4.6.2 |
| CHK-16 | `git rev-list --count HEAD` plus first and last commit dates | Default branch | git | 2026-07-26 | passed | 194; 2025-12-19 → 2026-07-25 |
| CHK-17 | `git shortlog -sne --all` | All refs | git | 2026-07-26 | passed | 1 identity, 351 commits |
| CHK-18 | Existence test over 9 community-health paths | Repository | macOS 25.5 | 2026-07-26 | failed | 9 of 9 absent |
| CHK-19 | `git grep -nE` over the repository's own credential pattern set | Tracked files | git | 2026-07-26 | passed | No match outside detector definitions and their fixtures |
| CHK-20 | `ls plugins/*/hooks/hooks.json` | In-tree plugins | macOS 25.5 | 2026-07-26 | passed | 3 matches |
| CHK-21 | `grep -hoE '^\s*uses: '` over all workflows | `.github/workflows/` | macOS 25.5 | 2026-07-26 | passed | 2 distinct action sources |
| CHK-22 | `gh run list --json workflowName` | Actions history | gh | 2026-07-26 | passed | 4 names; the refresh workflow is absent |
| CHK-23 | `git ls-files .decisions/` | Repository | git | 2026-07-26 | passed | 11 tracked records |
| CHK-24 | `dossier-scaffold.sh --output-root docs/dossier` | Output root | bash | 2026-07-26 | passed | `SCAFFOLD_CREATED=23 SCAFFOLD_FAILED=0` |
| CHK-25 | `dossier-validate-config.sh --config .claude/settings.dossier.json` | Configuration | bash | 2026-07-26 | passed | `CONFIG_VALID=true CONFIG_FINDINGS=0` |
| CHK-26 | End-to-end execution of the dossier post-merge workflow in a live repository | CI template | — | 2026-07-26 | **not executed** | Requires a scratch repository, an API-key secret, and a merged pull request. Recorded as AQ-0002 |
| CHK-27 | Install of the marketplace from a clean Claude Code profile | Distribution | — | 2026-07-26 | **not executed** | `engagement.allowedActions.networkAccess` is false. Recorded as AQ-0003 |
| CHK-31 | `plugins/flow/tests/run.sh` repeated 10 times | flow plugin | macOS 25.5, bash | 2026-07-26 | passed 10 of 11 | One run reported `fail=4` in `flow-goal-stop.test.sh`; not reproduced |
| CHK-32 | `TMPDIR` entry count before and after each suite run | both suites | macOS 25.5 | 2026-07-26 | failed | flow +254, dossier +81 per run before the fix; dossier +0 after |
| CHK-29 | `gh api repos/synaptiai/synapti-marketplace/contents/LICENSE?ref=feature/dossier-documentation-plugin` | Remote | gh | 2026-07-26 | passed | Blob present, 11312 bytes |
| CHK-30 | `gh api repos/synaptiai/synapti-marketplace/license?ref=…` | Remote licence detection | gh | 2026-07-26 | **not executed** | Returns 404 for any non-default ref — GitHub computes detection from the default branch only. Recorded as AQ-0011 |
| CHK-28 | `jq` reads of `~/.claude/plugins/known_marketplaces.json`, `installed_plugins.json`, the client's marketplace clone, and its cached manifest | Client install state | macOS 25.5, jq | 2026-07-26 | passed | Marketplace resolved from GitHub; 6 plugins installed; submodule path populated; cached manifest at 4.6.2 / 7 entries |

## Unavailable evidence

| Source sought | Why it matters | Why unavailable | Would settle | Open question |
|---|---|---|---|---|
| Install and usage counts per plugin | The only direct measure of whether any plugin is used, and by how many operators | GitHub exposes no install telemetry for plugin marketplaces, and the plugins emit none by design | Whether the marketplace has users, and which plugins matter | AQ-0004 |
| The `prompt-decorators` source tree | It is a published marketplace entry whose quality is asserted here on the strength of its manifest alone | The source lives in a separate repository and is not vendored | Whether the entry's description matches its contents | AQ-0005 |
| Upstream `agent-capability-standard` history beyond the pinned commit | Determines whether the pinned tree matches the version the marketplace advertises | The submodule is pinned 2 commits past `v1.2.0`; those commits were not read | Whether "1.2.0" accurately labels what installs | AQ-0006 |
| A record of an external contribution being reviewed and merged | Distinguishes a project that could accept contribution from one that has | Only one commit identity exists across all refs | Whether the contribution path works in practice | AQ-0007 |
| Windows and Git Bash execution results for the shipped shell scripts | The marketplace ships 26 shell scripts and hooks that run on the operator's machine, and two open issues assert portability defects | No Windows environment was available to this assessment | The real portability surface | AQ-0008 |

## Stale evidence

| Evidence ID | Expiry basis | Expired on | Current state | Required refresh action | Owner |
|---|---|---|---|---|---|
| none | — | — | — | — | — |

Every row above was observed on 2026-07-26 against commit `d0fa737` or against live repository state read the same day. No row has passed its stated freshness horizon.

## Secrets and sensitive material encountered

Type and location category only. No values, no excerpts, no exploitable detail.

| Type | Location category | Severity | Confidentiality | Remediation need | Reported through |
|---|---|---|---|---|---|
| none | — | — | — | none | `cmd:CHK-19` returned no match outside detector definitions and their fixtures |

The scan covered tracked files only, using the pattern set the repository's own `block-secrets.sh` and `dossier-validate-patch.sh` enforce. A negative result over a known pattern set proves that none of the enumerated formats appears — not that no credential exists. Untracked working-tree files were not scanned.
