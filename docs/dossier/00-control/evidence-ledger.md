---
dossier-header: internal-v1
title: Evidence Ledger
purpose: Lets a reader check whether any claim elsewhere in this package is grounded, and in what, before acting on it.
audience: Reviewer, Maintainer, Installing operator
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
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
| 1 | Observed runtime behaviour and reproducible checks | Shell commands executed against the working tree at `06b1586`, and `gh api` reads of live repository state |
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
| EV-0001 | The marketplace publishes 8 plugin entries | V | `.claude-plugin/marketplace.json` | yes | 2 | 06b1586 | 2026-07-26 | until marketplace.json changes | Public | yes | 01, 02, 06 | `jq` over `.plugins` → 8. Superseded by EV-0057 |
| EV-0002 | Marketplace metadata version is 4.7.0 | V | `.claude-plugin/marketplace.json` | yes | 2 | 06b1586 | 2026-07-26 | until next release | Public | no | 01, 04 | Branch state; exceeds the latest published tag — see EV-0033. Superseded by EV-0057 |
| EV-0003 | 6 plugins are vendored in-tree, 1 is a git submodule, 1 is an external `git-subdir` source | V | `git:06b1586:.gitmodules`, `.claude-plugin/marketplace.json` | yes | 2 | 06b1586 | 2026-07-26 | until sources change | Public | yes | 02, 05 | Submodule `agent-capability-standard`; subdir `prompt-decorators`. Superseded by EV-0058: `.gitmodules` was removed by efb4f75 and the entry is now a pinned `github` source. Locator qualified to the commit at which the file existed |
| EV-0004 | 112 `SKILL.md` files exist across the 7 in-tree plugin trees | V | `cmd:CHK-01` | yes | 1 | 06b1586 | 2026-07-26 | until a skill is added or removed | Public | yes | 02, 06 | 42 + 15 + 5 + 2 + 9 + 32 + 7. Superseded by EV-0093; see EV-0094 on what the 42-file term was |
| EV-0005 | 61 command definition files exist | V | `cmd:CHK-01` | yes | 1 | 06b1586 | 2026-07-26 | until a command changes | Public | no | 02, 06 | `find plugins -path '*/commands/*.md'` |
| EV-0006 | 29 agent definition files exist | V | `cmd:CHK-01` | yes | 1 | 06b1586 | 2026-07-26 | until an agent changes | Public | no | 02 | |
| EV-0007 | 26 shell scripts exist under plugin `bin/` directories | V | `cmd:CHK-01` | yes | 1 | 06b1586 | 2026-07-26 | until a script changes | Public | no | 02, 03 | The main body of executable code the marketplace ships |
| EV-0008 | The flow test suite reports 1022 passing assertions and 0 failures | V | `cmd:CHK-02` | yes | 1 | 06b1586 | 2026-07-26 | until flow changes | Public | yes | 03, 05 | `plugins/flow/tests/run.sh`. Superseded by EV-0068 |
| EV-0009 | The dossier test suite reports 1241 passing assertions and 0 failures | V | `cmd:CHK-03` | yes | 1 | 06b1586 | 2026-07-26 | until dossier changes | Public | yes | 03, 05 | `plugins/dossier/tests/run.sh`. Superseded by EV-0067 |
| EV-0010 | Only 2 of the 7 in-tree plugins carry a shell test suite | V | `cmd:CHK-04` | yes | 1 | 06b1586 | 2026-07-26 | until a suite is added | Public | yes | 03, 04, 05 | flow and dossier only |
| EV-0011 | `agent-capability-standard` carries a Python test suite | V | `plugins/agent-capability-standard/tests/` | yes | 2 | 95f7ac2 | 2026-07-26 | until the submodule pointer moves | Public | no | 03, 05 | pytest; not executed here — see CHK-09 |
| EV-0012 | The repository defines 4 GitHub Actions workflows | V | `.github/workflows/` | yes | 2 | 06b1586 | 2026-07-26 | until workflows change | Public | yes | 02, 03, 04 | codeql, dossier-tests, flow-tests, release-desktop-skills |
| EV-0013 | Both plugin test workflows declare `permissions: contents: read` | V | `cmd:CHK-05` | yes | 1 | 06b1586 | 2026-07-26 | until workflows change | Public | no | 03 | |
| EV-0014 | `codeql.yml` declares no top-level `permissions` block | V | `cmd:CHK-05` | yes | 1 | 06b1586 | 2026-07-26 | until the workflow changes | Public | no | 03, 04 | Falls back to the repository-default token scope |
| EV-0015 | `release-desktop-skills.yml` interpolates `${{ github.event.release.tag_name }}` inside a `run:` body | V | `cmd:CHK-06` | yes | 1 | 06b1586 | 2026-07-26 | until the workflow changes | Public | no | 03, 04 | Detected by the same rule the dossier CI template enforces on itself |
| EV-0016 | The `main` branch has no branch-protection configuration | V | `cmd: gh api branches/main/protection` | yes | 1 | live | 2026-07-26 | 30 days | Public | yes | 03, 04, 05 | HTTP 404 "Branch not protected" |
| EV-0017 | The repository defines no rulesets | V | `cmd: gh api rulesets` | yes | 1 | live | 2026-07-26 | 30 days | Public | yes | 03, 04, 05 | Empty array |
| EV-0018 | GitHub's repository-level licence detection still reports `null`, because it is computed from the default branch and `LICENSE` exists only on this one | V | `cmd: gh api repos/synaptiai/synapti-marketplace` | yes | 1 | live | 2026-07-26 | until this branch merges | Public | no | 05 | The per-ref licence endpoint returns 404 for a non-default ref, so branch-level detection cannot be observed at all. Detection resolves on merge — tracked as AQ-0011 |
| EV-0019 | A `LICENSE` file exists at the repository root carrying the canonical Apache-2.0 text, and the same blob is present on the remote | C | `LICENSE`, `cmd:CHK-29` | yes | 2 | f57126f | 2026-07-26 | until the file changes | Public | yes | 05 | 201 lines, 11312 bytes. Copyright line reads `Copyright 2025-2026 Synapti AI` |
| EV-0020 | `README.md` renders an Apache-2.0 badge whose link target is `LICENSE`, and the target now resolves | V | `README.md` | yes | 2 | f57126f | 2026-07-26 | until README changes | Public | yes | 05 | Resolves CT-0001 — the badge, the licence section, and the file agree |
| EV-0021 | All 7 in-tree `plugin.json` files and all 8 marketplace entries declare Apache-2.0, matching the `LICENSE` file | V | `cmd:CHK-08` | yes | 1 | f57126f | 2026-07-26 | until a declaration changes | Public | yes | 05 | Previously 6 MIT and 1 Apache-2.0 against no LICENSE file at all |
| EV-0022 | The README plugin-count badge reads 6; the marketplace publishes 8 | V | `cmd:CHK-10` | yes | 1 | 06b1586 | 2026-07-26 | until README changes | Public | no | 04, 06 | |
| EV-0023 | `README.md` contains no occurrence of the string "dossier" | V | `cmd:CHK-10` | yes | 1 | 06b1586 | 2026-07-26 | until README changes | Public | no | 04, 06 | A published plugin absent from the storefront |
| EV-0024 | The README plugin table lists flow at 3.2.0; `marketplace.json` says 3.2.2 | V | `cmd:CHK-10` | yes | 1 | 06b1586 | 2026-07-26 | until README changes | Public | no | 04 | |
| EV-0025 | The README lists prompt-decorators at 0.1.0; `marketplace.json` says 0.1.1 | V | `cmd:CHK-10` | yes | 1 | 06b1586 | 2026-07-26 | until README changes | Public | no | 04 | |
| EV-0026 | For all 7 in-tree plugins, `plugin.json.version` equals the `marketplace.json` entry version | V | `cmd:CHK-11` | yes | 1 | 06b1586 | 2026-07-26 | until a version changes | Public | no | 03, 04 | The machine-readable pair is consistent; the prose is not |
| EV-0027 | The `ai-first-org-design-kit` description says "Fourteen opinionated skills"; the tree contains 15 | V | `cmd:CHK-12` | yes | 1 | 06b1586 | 2026-07-26 | until the description or skill set changes | Public | no | 04 | |
| EV-0028 | The flow README claims "33 skills"; the tree contains 32 `SKILL.md` files | V | `cmd:CHK-12` | yes | 1 | 06b1586 | 2026-07-26 | until flow changes | Public | no | 04 | |
| EV-0029 | `plugins/flow/skills/learned/` contains only `.gitkeep` and no `SKILL.md` | V | `cmd:CHK-13` | yes | 1 | 06b1586 | 2026-07-26 | until the directory is populated | Public | no | 02, 04 | Directory-counting yields 33, file-counting 32 — the origin of EV-0028 |
| EV-0030 | The `prompt-decorators` marketplace source pins `ref: "main"` | V | `.claude-plugin/marketplace.json` | yes | 2 | 06b1586 | 2026-07-26 | until the entry changes | Public | yes | 02, 05 | A floating ref; two installs on different days need not agree |
| EV-0031 | The `agent-capability-standard` submodule is pinned to `95f7ac2`, 2 commits past tag `v1.2.0` | V | `cmd:CHK-14` | yes | 1 | 06b1586 | 2026-07-26 | until the pointer moves | Public | no | 02, 05 | `git describe` → `v1.2.0-2-g95f7ac2` |
| EV-0032 | 57 git tags exist; the latest published release is `v4.6.2`, dated 2026-05-29 | V | `cmd:CHK-15`, `cmd: gh api releases` | yes | 3 | live | 2026-07-26 | until the next release | Public | yes | 03, 04 | |
| EV-0033 | `marketplace.json` metadata version 4.7.0 has no corresponding release tag | V | `derived: EV-0002 + EV-0032` | yes | 1 | 06b1586 | 2026-07-26 | until 4.7.0 is released | Public | no | 04 | Expected on an unmerged feature branch |
| EV-0034 | The assessed branch has 193 commits; first 2025-12-19, most recent 2026-07-26 | V | `cmd:CHK-16` | yes | 1 | 06b1586 | 2026-07-26 | continuously | Public | no | 01, 04 | |
| EV-0035 | All commits across all refs carry one author identity, Daniel Bentes | V | `cmd:CHK-17` | yes | 1 | 06b1586 | 2026-07-26 | until another contributor commits | Public | yes | 01, 04, 05 | `git shortlog -sne --all` returns a single line, 370 commits |
| EV-0036 | The repository has no `SECURITY.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `dependabot.yml`, issue templates, or pull-request template | V | `cmd:CHK-18` | yes | 1 | 06b1586 | 2026-07-26 | until any is added | Public | yes | 03, 04, 05 | 9 of 9 paths absent |
| EV-0037 | No credential matching the repository's own detector pattern set appears in tracked files outside detector definitions and their fixtures | V | `cmd:CHK-19` | yes | 1 | 06b1586 | 2026-07-26 | every commit | Public | yes | 03 | A negative result over a known pattern set, not proof of absence |
| EV-0038 | The flow plugin ships 12 hook scripts, including `block-secrets.sh`, `block-destructive.sh`, and `block-force-push.sh` | V | `plugins/flow/hooks/scripts/` | yes | 2 | 06b1586 | 2026-07-26 | until hooks change | Public | yes | 02, 03 | |
| EV-0039 | The dossier plugin ships 4 hook scripts enforcing output-root containment, the action ceiling, claim registration, and header staleness | V | `plugins/dossier/hooks/scripts/` | yes | 2 | 06b1586 | 2026-07-26 | until hooks change | Public | yes | 02, 03 | |
| EV-0040 | 3 of the 7 in-tree plugins register hooks | V | `cmd:CHK-20` | yes | 1 | 06b1586 | 2026-07-26 | until hooks change | Public | yes | 02, 03 | flow, dossier, agent-capability-standard |
| EV-0041 | The only declared third-party runtime dependency in the repository is `pyyaml>=6.0` | V | `plugins/agent-capability-standard/pyproject.toml` | yes | 2 | 95f7ac2 | 2026-07-26 | until the manifest changes | Public | yes | 05 | The single dependency manifest in the tree |
| EV-0042 | CI consumes 2 third-party action sources: `actions/checkout@v4` and `github/codeql-action@v3` | V | `cmd:CHK-21` | yes | 1 | 06b1586 | 2026-07-26 | until workflows change | Public | no | 03, 05 | Pinned by major tag, not by commit SHA |
| EV-0043 | The marketplace publishes to no package registry; distribution is a git read performed by the Claude Code plugin client | I | `inference: EV-0001, absence of any publish step in the 4 workflows` | yes | 7 | 06b1586 | 2026-07-26 | until a publish step is added | Public | no | 02, 04 | Chain: no root package manifest, no publish job, and every in-tree entry's `source` is a repository-relative path |
| EV-0044 | The marketplace has no runtime process; shipped artifacts are Markdown, JSON, and shell executed inside the operator's own Claude Code session | V | `derived: EV-0004..EV-0007, EV-0041` | yes | 2 | 06b1586 | 2026-07-26 | until an executable service is added | Public | yes | 02, 03, 04 | Determines that most availability and observability questions are `N/A` |
| EV-0045 | The dossier post-merge refresh workflow has never executed in this repository | V | `cmd:CHK-22` | yes | 1 | live | 2026-07-26 | until it runs | Public | yes | 03, 04, 05 | Actions history lists 4 workflow names; the refresh job is not among them |
| EV-0046 | `.decisions/` holds 11 tracked decision records | V | `cmd:CHK-23` | yes | 1 | 06b1586 | 2026-07-26 | until a record is added | Public | no | 04 | |
| EV-0047 | The dossier scaffold created 23 of 23 canonical files with 0 failures | V | `cmd:CHK-24` | yes | 1 | 06b1586 | 2026-07-26 | one-time | Public | no | 07 | |
| EV-0048 | `dossier-validate-config.sh` reports `CONFIG_VALID=true` with 0 findings for this project's configuration | V | `cmd:CHK-25` | yes | 1 | 06b1586 | 2026-07-26 | until the configuration changes | Public | no | 07 | |
| EV-0049 | 2 pull requests and 2 issues are open; both open issues concern Windows and Git Bash portability | V | `cmd: gh api issues`, `cmd: gh api pulls` | yes | 3 | live | 2026-07-26 | days | Public | yes | 04 | Issues #100 and #130 |
| EV-0050 | 62 pull requests have been merged | V | `cmd: gh api pulls?state=merged` | yes | 3 | live | 2026-07-26 | days | Public | no | 04 | Against 193 commits on the assessed branch |
| EV-0051 | The Claude Code client resolves this marketplace from `source: github, repo: synaptiai/synapti-marketplace` and holds a clone last updated 2026-07-20 with `autoUpdate: true` | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until the client re-syncs | Public | yes | 02, 04, 06 | Observed on the assessment machine, not on a clean profile |
| EV-0052 | 6 plugins from this marketplace are installed and cached on the assessment machine | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until install state changes | Public | yes | 04, 06 | flow, gh-workflow, decipon, context-ledger, ai-first-org-design-kit, prompt-decorators |
| EV-0053 | The client's clone populates the `agent-capability-standard` submodule, so a submodule-sourced entry resolves to real files for an installer | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until the client changes | Public | no | 02, 05 | 30 entries present in the client's copy of the submodule path. Superseded by EV-0059: no submodule exists at HEAD |
| EV-0055 | The flow test suite failed 4 assertions in `flow-goal-stop.test.sh` on one run, then passed 10 consecutive runs including 6 back-to-back | V | `cmd:CHK-31` | yes | 1 | f57126f | 2026-07-26 | until reproduced or fixed | Public | no | 03 | Not reproduced. Recorded because an intermittent failure in a suite that is already advisory is worth less than its pass count suggests |
| EV-0056 | Both test suites leaked temp directories every run — flow ~254, dossier ~81 — because test files are sourced and an `EXIT` trap set by one is replaced by the next file's | V | `cmd:CHK-32` | yes | 1 | f57126f | 2026-07-26 | until fixed | Public | no | 03 | Measured by counting `TMPDIR` entries before and after a run. Fixed in dossier by scoping `TMPDIR` to a runner-owned directory; still present in flow |
| EV-0054 | The client's cached manifest reports metadata version 4.6.2 with 7 plugin entries | V | `cmd:CHK-28` | yes | 1 | live | 2026-07-26 | until the next release | Public | yes | 04 | The published `main` state; corroborates that 4.7.0 and the dossier entry exist only on the feature branch [EV-0033] |
| EV-0057 | Marketplace metadata version is 4.10.0 and the manifest publishes 8 plugin entries | V | `.claude-plugin/marketplace.json` | yes | 2 | 15bcb24 | 2026-09-10 | until the next release | Public | pending | 01, 02, 04, 06 | `jq` reads of `.metadata.version` and the length of `.plugins`. Supersedes the figures in EV-0001 and EV-0002 |
| EV-0058 | 6 plugins are vendored in-tree as relative-path sources, 1 (`agent-capability-standard`) is a `github` source pinned to sha `9e2f65b`, and 1 (`prompt-decorators`) is a `git-subdir` source pinned to sha `9c792fe` | V | `.claude-plugin/marketplace.json` | yes | 2 | 15bcb24 | 2026-09-10 | until a source entry changes | Public | pending | 02, 05 | Supersedes EV-0003. No entry is a git submodule at this commit |
| EV-0059 | No `.gitmodules` file exists in the tracked tree | V | `cmd:CHK-33` | yes | 1 | 15bcb24 | 2026-09-10 | until a submodule is added | Public | pending | 02, 05 | Removed by efb4f75 (PR #165). This is what invalidated EV-0003's locator |
| EV-0060 | A fully populated `plugins/agent-capability-standard/` directory exists on the assessment machine but is untracked and ignored by `.gitignore` line 54 | V | `cmd:CHK-33` | yes | 1 | macOS working tree at 15bcb24 | 2026-09-10 | until the operator deletes the leftover directory | Public | pending | 02, 05 | Working-tree residue of the removed submodule, not repository content. `git ls-files` returns 0 entries for the path. Any `find plugins ...` count taken on this machine silently includes it |
| EV-0061 | Whether the `agent-capability-standard` tree at pinned sha `9e2f65b` reports version 1.2.0 is unknown | U | `inference: marketplace entry pins 9e2f65b; the only local copy is the ex-submodule residue at an older pointer` | yes | 7 | 15bcb24 | 2026-09-10 | none | Public | pending | 02, 05 | `networkAccess` is false, so the pinned tree was not fetched. The local residue's `plugin.json` says 1.2.0 but is not the pinned revision |
| EV-0062 | Whether the `prompt-decorators` tree at pinned sha `9c792fe` reports version 0.1.1 is unknown | U | `inference: marketplace entry pins 9c792fe; no local copy of the source exists` | yes | 7 | 15bcb24 | 2026-09-10 | none | Public | pending | 02, 05 | `networkAccess` is false. Extends AQ-0005 to the newly added pin |
| EV-0063 | `.github/workflows/codeql.yml` contains no `submodules:` key on its checkout step | V | `.github/workflows/codeql.yml` | yes | 2 | 15bcb24 | 2026-09-10 | until the workflow changes | Public | pending | 03 | The file's comment block states the python analysis remains. Whether CodeQL still scans any Python at HEAD was not checked |
| EV-0064 | Every one of the 6 in-tree plugins advertises in `.claude-plugin/marketplace.json` the version its own `plugin.json` reports | V | `cmd:CHK-34` | yes | 1 | 15bcb24 | 2026-09-10 | until any version changes | Public | pending | 02, 04 | dossier 1.2.0, flow 3.3.0, gh-workflow 1.9.0, decipon 1.5.0, context-ledger 1.0.0, ai-first-org-design-kit 1.5.1 |
| EV-0065 | The dossier plugin is at version 1.2.0 and the flow plugin at 3.3.0 | V | `plugins/dossier/.claude-plugin/plugin.json`, `plugins/flow/.claude-plugin/plugin.json` | yes | 2 | 15bcb24 | 2026-09-10 | until the next release | Public | pending | 01, 02, 04 | Raised from 1.1.0 (PR #164) and 3.2.2 (PR #163) in this range |
| EV-0066 | Releases v4.9.0 and v4.10.0 were published on 2026-09-10 | V | `release:v4.10.0`, `release:v4.9.0` | yes | 3 | live | 2026-09-10 | until the next release | Public | pending | 04 | Read from `.dossier/evidence/releases.json`, this run's retained GitHub API read. v4.9.0 07:18Z, v4.10.0 07:48Z |
| EV-0067 | The dossier test suite reports 1951 passing assertions and 0 failures | V | `cmd:CHK-35` | yes | 1 | 15bcb24 | 2026-09-10 | until dossier changes | Public | pending | 03, 05 | Executed on macOS 25.6. Supersedes EV-0009 (1241 at 06b1586) |
| EV-0068 | The flow test suite reports 2222 passing assertions and 114 failures across 4 test files | V | `cmd:CHK-36` | yes | 1 | 15bcb24 | 2026-09-10 | until flow changes or the failures are fixed | Public | pending | 03, 05 | Executed on macOS 25.6, exit 1. Failing files: `ask-issue-create.test.sh` (20), `flow-eval-harness.test.sh` (2), `flow-quality-ledger.test.sh` (15), `verify-task-completion.test.sh` (77). Supersedes EV-0008 (1022 pass, 0 fail at 06b1586) |
| EV-0069 | All 4 failing flow test files exercise components the flow 3.3.0 changelog lists as added or changed in this release | V | `plugins/flow/CHANGELOG.md`, `cmd:CHK-36` | yes | 2 | 15bcb24 | 2026-09-10 | until the failures are fixed | Internal | pending | 03 | `ask-issue-create.sh` and `flow-quality-ledger.sh` are new files in this range; `verify-task-completion.sh` was modified in it; the eval harness is new |
| EV-0070 | Whether the flow test suite passes on the Linux CI runner at 15bcb24 is unknown | U | `inference: CHK-36 was executed only on macOS 25.6; no Actions run was read` | yes | 7 | 15bcb24 | 2026-09-10 | none | Internal | pending | 03 | `networkAccess` is false, so no `gh run` read was made. The observed failure mode (empty hook output) is platform-sensitive and this repository has a recorded history of macOS/Linux divergence in both directions |
| EV-0071 | `bin/dossier-gate.sh` implements 19 release-gate conditions, G01 through G19 | V | `cmd:CHK-37` | yes | 1 | 15bcb24 | 2026-09-10 | until the gate script changes | Public | pending | 03, 07 | Distinct `G##` tokens in the script, sorted unique |
| EV-0072 | G19 records `INCONCLUSIVE` — never `PASS` — when the ledger holds no vulnerability-scan evidence, and when the scan artifact could not be parsed | V | `plugins/dossier/bin/dossier-gate.sh` | yes | 2 | 15bcb24 | 2026-09-10 | until the gate script changes | Public | pending | 03, 07 | Read from the three `record G19 mechanical INCONCLUSIVE` branches. Evidence about what the script says; no gate run was executed at this commit |
| EV-0073 | `bin/dossier-scan-security.sh` emits status `disabled` and does not invoke osv-scanner when `dossier.engagement.allowedActions.runSecurityScan` resolves false | V | `plugins/dossier/bin/dossier-scan-security.sh` | yes | 2 | 15bcb24 | 2026-09-10 | until the script changes | Public | pending | 03 | Code read at the gating branch. Not executed here |
| EV-0074 | `bin/dossier-scan-quality.sh` emits status `disabled` and does not invoke pyscn when `dossier.engagement.allowedActions.runCodeQualityScan` resolves false | V | `plugins/dossier/bin/dossier-scan-quality.sh` | yes | 2 | 15bcb24 | 2026-09-10 | until the script changes | Public | pending | 03 | Code read at the gating branch. Not executed here. The two flags are resolved independently |
| EV-0075 | `templates/ci/dossier-docs-refresh.yml` defines a separate `scan` job that installs osv-scanner and pyscn, distinct from the `policy` job | V | `plugins/dossier/templates/ci/dossier-docs-refresh.yml` | yes | 2 | 15bcb24 | 2026-09-10 | until the template changes | Public | pending | 03 | Evidence about the template's contents. This template is not installed in this repository's own `.github/workflows/` — see EV-0084 |
| EV-0076 | The rotation telemetry step is wired into the refresh template's `policy` job and exposes six `rotation_*` job outputs | V | `plugins/dossier/templates/ci/dossier-docs-refresh.yml` | yes | 2 | 15bcb24 | 2026-09-10 | until the template changes | Public | pending | 03, 04 | `would_rotate`, `reason`, `age_days`, `age_source`, `accumulated_files`, `accumulated_lines`. Evidence about the template, not about any executed run |
| EV-0077 | The resolved action ceiling for this repository is runTests true; runBuild, networkAccess, runSecurityScan, runCodeQualityScan, readSecrets and writeOutsideOutputRoot all false | V | `cmd:CHK-38` | yes | 1 | 15bcb24 | 2026-09-10 | until the configuration changes | Internal | pending | 03, 07 | Resolved through `bin/dossier-resolve-config.sh`, not by reading a settings file directly. `runSecurityScan` and `runCodeQualityScan` are absent from `.claude/settings.dossier.json` and fall to their false defaults |
| EV-0078 | No vulnerability-scan artifact was located for this run | U | `cmd:CHK-39` | yes | 1 | 15bcb24 | 2026-09-10 | none | Public | pending | 03, 05 | No `.dossier/scan/` directory exists, and `git ls-files` matches 0 tracked paths named for SARIF, osv-scanner or Dependabot output. This is the absence of a scan, not a clean bill of health: no statement about this project's vulnerability status is supported. See the Unavailable evidence section |
| EV-0079 | Whether CodeQL has produced findings for this repository is unknown | U | `inference: codeql.yml uploads SARIF to GitHub code scanning, which is not readable without network access` | yes | 7 | 15bcb24 | 2026-09-10 | none | Internal | pending | 03 | `networkAccess` is false. Recorded so EV-0078 is bounded rather than absolute |
| EV-0080 | `scripts/check-plugin-versions.sh` exists at HEAD, 252 lines, and checks that each marketplace entry's version matches its source's own `plugin.json` and that every external source carries a `sha` | V | `scripts/check-plugin-versions.sh` | yes | 2 | 15bcb24 | 2026-09-10 | until the script changes | Public | pending | 02, 03, 04 | New in this range (PR #166, commit 15bcb24). Its own header states it cannot catch a pin that is stale but self-consistent, and that staleness is reported rather than failed |
| EV-0081 | `.github/workflows/marketplace-manifest.yml` runs `scripts/check-plugin-versions.sh` on pull requests and pushes touching the manifest, plugin manifests or the script, on a weekly cron at 06:00 UTC Monday, and on manual dispatch, with `permissions: contents: read` | V | `.github/workflows/marketplace-manifest.yml` | yes | 2 | 15bcb24 | 2026-09-10 | until the workflow changes | Public | pending | 03 | Evidence about the workflow file. Whether it has ever executed is EV-0082 |
| EV-0082 | Whether `marketplace-manifest.yml` has ever executed, and with what result, is unknown | U | `inference: no Actions run history was read` | yes | 7 | 15bcb24 | 2026-09-10 | none | Internal | pending | 03 | `networkAccess` is false. The workflow was added in the tip commit of this range, so no run predates it |
| EV-0083 | `.github/workflows/` contains 5 tracked workflows: codeql, dossier-tests, flow-tests, marketplace-manifest, release-desktop-skills | V | `cmd:CHK-40` | yes | 1 | 15bcb24 | 2026-09-10 | until a workflow is added or removed | Public | pending | 03 | Supersedes the 4-workflow figure behind CHK-05 and CHK-22 |
| EV-0084 | No dossier documentation-refresh workflow is installed in this repository's `.github/workflows/` | V | `cmd:CHK-40` | yes | 1 | 15bcb24 | 2026-09-10 | until one is installed | Public | pending | 03, 07 | The plugin ships the template (EV-0075); this repository has not adopted it. Every refresh of this package has therefore been run by hand |
| EV-0085 | `.claude/settings.dossier.json` sets `dossier.ci.expectedPluginVersion` to "1.0.0" while the dossier plugin is at 1.2.0 | V | `.claude/settings.dossier.json`, `plugins/dossier/.claude-plugin/plugin.json` | yes | 2 | 15bcb24 | 2026-09-10 | until the configuration is updated | Internal | pending | 03, 04 | A stale pin in the repository's own dossier configuration. `bin/dossier-validate-config.sh` does not flag it (EV-0086), because schema validity and semantic currency are different checks |
| EV-0086 | `bin/dossier-validate-config.sh` reports CONFIG_SCHEMA_VALIDATION=pass, CONFIG_FINDINGS=0, CONFIG_VALID=true at HEAD | V | `cmd:CHK-41` | yes | 1 | 15bcb24 | 2026-09-10 | until the configuration or schema changes | Public | pending | 03, 07 | Executed. Supersedes CHK-25's 2026-07-26 result |
| EV-0087 | `bin/dossier-ledger-lint.sh` reported 56 rows, 1 error and 0 warnings against this package before this run's rows were appended | V | `cmd:CHK-42` | yes | 1 | 15bcb24 | 2026-09-10 | until the ledger changes | Internal | pending | 00, 07 | The single error was EV-0003's `.gitmodules` locator failing to resolve |
| EV-0088 | Every documentation file in the package carrying a `last-verified` field states 2026-07-26, and every file carrying `project-version` states `06b1586` | V | `cmd:CHK-43` | yes | 1 | 15bcb24 | 2026-09-10 | expired — the package describes a commit 16 commits behind HEAD | Internal | pending | 00, 07 | 24 markdown files: 21 carry `last-verified`, the 2 public files carry `last-updated: 2026-07-26` and `product-version: 06b1586`, and `README.md` carries no header. The package has not been re-verified since 2026-07-26 |
| EV-0089 | The package's own verification report records three verification rounds plus a fix cycle, all dated 2026-07-26, a score of 87 against a configured minimum of 95, and a release-gate result of FAIL on two conditions | V | `docs/dossier/07-verification/documentation-verification-report.md` | yes | 2 | 15bcb24 | 2026-09-10 | until a new verification round runs | Internal | pending | 07 | Evidence about what that report states, at the commit it describes (`06b1586`). The failing conditions were total score and the reliability-and-verification-depth dimension at 60% against a minimum of 80% |
| EV-0090 | No verification round and no gate run has been recorded since 2026-07-26 | V | `cmd:CHK-44` | yes | 1 | 15bcb24 | 2026-09-10 | until a round runs | Internal | pending | 07 | `.dossier/runs/` holds exactly three run records, `2026-07-26-r1`, `-r2` and `-r3`. Zero rounds have run against any commit in this range |
| EV-0091 | No `.scope.json` exists in `docs/dossier/00-control/` | V | `cmd:CHK-44` | yes | 1 | 15bcb24 | 2026-09-10 | until Phase 0 writes one | Internal | pending | 00, 07 | This run's inspection boundary was resolved through `bin/dossier-resolve-config.sh` instead. The run's contract file is absent, so batch boundaries and access limitations for this run are not recorded anywhere but here |
| EV-0092 | HEAD 15bcb24 is on branch `docs/dossier-refresh`, not on `main` | V | `cmd:CHK-45` | yes | 1 | 15bcb24 | 2026-09-10 | until the branch is merged | Internal | pending | 00, 04 | Every claim in this run's rows describes this branch. The same branch-versus-main distinction EV-0033 and EV-0054 record for the previous assessment applies again |
| EV-0093 | At HEAD the tracked tree holds 71 `SKILL.md` files, 61 command definitions, 29 agent definitions, 37 plugin `bin/` shell scripts and 2 `hooks.json` manifests | V | `cmd:CHK-46` | yes | 1 | 15bcb24 | 2026-09-10 | until a plugin artifact is added or removed | Public | pending | 02, 06 | Counted with `git ls-files`, which excludes the ignored working-tree residue at EV-0060. Per plugin: flow 32, ai-first-org-design-kit 15, dossier 10, gh-workflow 7, context-ledger 5, decipon 2 |
| EV-0094 | The untracked `plugins/agent-capability-standard/` residue holds 42 `SKILL.md` files, the exact term EV-0004's 112-file total itemizes for the then-submodule | V | `cmd:CHK-33` | yes | 1 | 15bcb24 | 2026-09-10 | none | Internal | pending | 02, 06 | Counted on the assessment machine with `find`. Inferred, and not re-derived against the 06b1586 tree: the 112-skill figure recorded then counted files that are no longer repository content. The residue is machine state, not repository content (EV-0060) |
| EV-0095 | `plugins/flow/evals/` holds a correctness evaluation harness — 4 cases, per-case hidden tests and trap variants, and 82 tracked files — driven by `bin/flow-eval-run.sh` and `bin/_flow_eval.py` | V | `cmd:CHK-46` | yes | 1 | 15bcb24 | 2026-09-10 | until the harness changes | Public | pending | 02, 03 | Cases: four-stream-codec, interval-algebra, money-allocator, sliding-window-limiter. All new in this range |
| EV-0096 | The retained eval summary reports 105 runs across 2 models, 7 arms and 4 cases at a total cost of $184.65, and a `keep-enforce` verdict for both `claude-opus-5` and `claude-sonnet-5` | R | `plugins/flow/evals/results-2026-09-09-round2/summary.md` | yes | 2 | 15bcb24 | 2026-09-10 | until the harness is re-run against a newer model | Internal | pending | 03 | Reported by the harness's own retained output, dated 2026-09-09. Not re-executed here: `runTests` covers the shell suites, not a paid multi-model eval. The summary's own text states the comparison is incomplete because not every arm has at least 3 runs on every case, and calls its reading provisional |
| EV-0097 | No prompt-injection attempt was found in the untrusted evidence bundle | V | `cmd:CHK-47` | yes | 1 | 15bcb24 | 2026-09-10 | until new contributor text enters the range | Internal | pending | 00, 03 | Pattern set: ignore/disregard prior instructions, "as an ai", "system prompt", "new instructions", "do not record", "skip the check/verification/gate", "write outside", "widen scope", plus path traversal in `changed-paths.txt`. Scanned commit bodies and subjects, pull-request bodies, and changed paths. Two hits on "widen" were descriptive prose in a security-fix commit message, not directives. A negative result over an enumerated pattern set is not proof that no injection exists |

## Source inventory and inspection coverage

| Source | Class | Made available | Inspected | Coverage | Note |
|---|---|---|---|---|---|
| `plugins/dossier/` | Source tree | yes | yes | full | The subject of the pull request under which this package was produced |
| `plugins/flow/` | Source tree | yes | yes | sampled | Structure, hooks, and test results verified in full; individual skill prose sampled |
| `plugins/gh-workflow/`, `plugins/decipon/`, `plugins/context-ledger/`, `plugins/ai-first-org-design-kit/` | Source tree | yes | yes | partial | Manifests, structure, and artifact counts verified; prose not audited |
| `plugins/agent-capability-standard/` | Git submodule | yes | yes | partial | Pointer, manifest, and dependency set read from the checked-out tree; upstream history not audited |
| `plugins/agent-capability-standard/` (at 15bcb24) | Pinned `github` source, no longer a submodule | no | no | none | Not repository content at this commit (EV-0058, EV-0059). The populated directory on the assessment machine is untracked, ignored residue at the old submodule pointer and was not inspected as evidence for this run (EV-0060). Supersedes the row above, which records the 2026-07-26 inspection |
| `prompt-decorators` | External `git-subdir` | no | no | none | Not present in this repository; only its marketplace entry is verifiable here |
| `.github/workflows/` | CI definitions | yes | yes | full | All 4 workflows parsed and rule-checked |
| `.claude-plugin/marketplace.json` | Distribution manifest | yes | yes | full | |
| `README.md` | Existing documentation | yes | yes | full | 663 lines; every version and count claim cross-checked against the manifest |
| Live repository settings | GitHub API | yes | yes | full | Protection, rulesets, license detection, releases, issues, Actions history |
| Install analytics | Operational telemetry | no | no | none | Not exposed by GitHub for plugin marketplaces |
| `scripts/` | Source tree | yes | yes | full | 2 scripts; `check-plugin-versions.sh` new in this range and read in full |
| `plugins/flow/evals/` | Evaluation suite | yes | yes | partial | Structure, harness entry points and the retained 2026-09-09 summary read; the 4 cases' hidden tests and trap variants not audited |
| `.dossier/evidence/` | Change-evidence bundle for `7e4a097..15bcb24` | yes | yes | partial | `source.diff` is truncated at 524288 of 2315071 bytes; affected files were read from the checkout instead. Contributor-authored content treated as untrusted (EV-0097) |
| `.dossier/scan/` | Vulnerability-scan bundle | no | no | none | Not produced for this run; `runSecurityScan` is false (EV-0078) |
| GitHub Actions run history and code-scanning alerts | Operational telemetry | no | no | none | `networkAccess` is false for this run, unlike the 2026-07-26 assessment (EV-0070, EV-0079, EV-0082) |
| Production telemetry | Operational telemetry | N/A | N/A | none | The project has no runtime (EV-0044) |

## Executed checks

Every `cmd:` locator in the evidence table appears here. A check that could not run is recorded as `not executed` with the reason — never as passed.

| Check | Command | Scope | Environment | Date | Result | Output artifact |
|---|---|---|---|---|---|---|
| CHK-01 | `find plugins -name SKILL.md \| wc -l`, and siblings for commands, agents, and `bin/` | Whole tree | macOS 25.5, zsh | 2026-07-26 | passed | 112 / 61 / 29 / 26 |
| CHK-02 | `plugins/flow/tests/run.sh` | flow plugin | macOS 25.5, bash | 2026-07-26 | passed | `TOTAL pass=1022 fail=0` |
| CHK-03 | `plugins/dossier/tests/run.sh` | dossier plugin | macOS 25.5, bash | 2026-07-26 | passed | `TOTAL pass=1241 fail=0` |
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
| CHK-16 | `git rev-list --count HEAD` plus first and last commit dates | The assessed branch, not `main` | git | 2026-07-26 | passed | 193; 2025-12-19 → 2026-07-26 |
| CHK-17 | `git shortlog -sne --all` | All refs | git | 2026-07-26 | passed | 1 identity, 370 commits |
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
| CHK-29 | `gh api repos/synaptiai/synapti-marketplace/contents/LICENSE?ref=fix/gate-verdict-integrity` | Remote | gh | 2026-07-26 | passed | Blob present, 11312 bytes |
| CHK-30 | `gh api repos/synaptiai/synapti-marketplace/license?ref=…` | Remote licence detection | gh | 2026-07-26 | **not executed** | Returns 404 for any non-default ref — GitHub computes detection from the default branch only. Recorded as AQ-0011 |
| CHK-28 | `jq` reads of `~/.claude/plugins/known_marketplaces.json`, `installed_plugins.json`, the client's marketplace clone, and its cached manifest | Client install state | macOS 25.5, jq | 2026-07-26 | passed | Marketplace resolved from GitHub; 6 plugins installed; submodule path populated; cached manifest at 4.6.2 / 7 entries |
| CHK-33 | `ls .gitmodules`, `git ls-files .gitmodules`, `git ls-files plugins/agent-capability-standard`, `git check-ignore -v plugins/agent-capability-standard`, `find plugins/agent-capability-standard -name SKILL.md` | Submodule removal | macOS 25.6, git | 2026-09-10 | passed | No `.gitmodules`; 0 tracked files under the path; ignored at `.gitignore:54`; directory populated on disk with 42 `SKILL.md` files |
| CHK-34 | `jq` comparison of each `plugins/*/.claude-plugin/plugin.json` version against its `.claude-plugin/marketplace.json` entry | 6 in-tree plugins | macOS 25.6, jq | 2026-09-10 | passed | 6 of 6 match |
| CHK-35 | `plugins/dossier/tests/run.sh` | dossier plugin | macOS 25.6, bash | 2026-09-10 | passed | `TOTAL pass=1951 fail=0`, exit 0 |
| CHK-36 | `plugins/flow/tests/run.sh` | flow plugin | macOS 25.6, bash | 2026-09-10 | **failed** | `TOTAL pass=2222 fail=114`, exit 1. Failing files: `ask-issue-create.test.sh` 20, `flow-eval-harness.test.sh` 2, `flow-quality-ledger.test.sh` 15, `verify-task-completion.test.sh` 77 |
| CHK-37 | `grep -oE '\bG[0-9]{2}\b' plugins/dossier/bin/dossier-gate.sh` sorted unique | Release gate | macOS 25.6 | 2026-09-10 | passed | G01 through G19, 19 distinct conditions |
| CHK-38 | `bin/dossier-resolve-config.sh` for each `dossier.engagement.allowedActions` key | Action ceiling | bash | 2026-09-10 | passed | runTests true; runBuild, networkAccess, runSecurityScan, runCodeQualityScan, readSecrets, writeOutsideOutputRoot false |
| CHK-39 | `ls .dossier/scan` and `git ls-files` filtered for SARIF, osv-scanner and Dependabot artifact names | Vulnerability evidence | macOS 25.6, git | 2026-09-10 | passed | No `.dossier/scan/` directory; 0 tracked matches. Recorded as EV-0078, not as a clean result |
| CHK-40 | `git ls-files '.github/workflows/*'` | CI definitions | git | 2026-09-10 | passed | 5 workflows; no dossier docs-refresh workflow among them |
| CHK-41 | `bin/dossier-validate-config.sh` | Configuration | bash | 2026-09-10 | passed | `CONFIG_SCHEMA_VALIDATION=pass CONFIG_FINDINGS=0 CONFIG_VALID=true` |
| CHK-42 | `bin/dossier-ledger-lint.sh --output-root docs/dossier` | This package | bash | 2026-09-10 | **failed** | Before this run's edits: `LEDGER_ROWS=56 LEDGER_ERRORS=1`, EV-0003's `.gitmodules` locator unresolvable. Re-run after the edits: see CHK-48 |
| CHK-43 | Per-file read of `last-verified`, `last-updated`, `project-version` and `product-version` across every markdown file under `docs/dossier` | This package | macOS 25.6 | 2026-09-10 | passed | 24 files; every dated header reads 2026-07-26 and every version header reads `06b1586` |
| CHK-44 | `ls .dossier/runs/` and an existence test on `docs/dossier/00-control/.scope.json` | Run records | macOS 25.6 | 2026-09-10 | passed | 3 run records, all 2026-07-26; no `.scope.json` |
| CHK-45 | `git branch --show-current`, `git rev-parse HEAD` | Assessed revision | git | 2026-09-10 | passed | `docs/dossier-refresh` at `15bcb24d2a00c04341772310700d68f86e420f15` |
| CHK-46 | `git ls-files` counts for `SKILL.md`, commands, agents, plugin `bin/` scripts, `hooks.json`, and `plugins/flow/evals` | Whole tracked tree | git | 2026-09-10 | passed | 71 / 61 / 29 / 37 / 2, and 82 tracked files under `plugins/flow/evals` |
| CHK-47 | `grep -niE` over an injection pattern set applied to commit bodies and subjects, pull-request bodies, and changed paths in `.dossier/evidence/` | This range's untrusted contributor text | macOS 25.6 | 2026-09-10 | passed | No directive-shaped text found; 2 hits on "widen" were descriptive prose in a security-fix message |
| CHK-48 | `bin/dossier-ledger-lint.sh --output-root docs/dossier`, re-run after this run's rows were appended | This package | bash | 2026-09-10 | passed | `LEDGER_ROWS=97 LEDGER_ERRORS=0 LEDGER_WARNINGS=0 LEDGER_DANGLING_CITATIONS=0` |
| CHK-49 | `scripts/check-plugin-versions.sh` | Marketplace manifest consistency | — | 2026-09-10 | **not executed** | The script reads other repositories' `plugin.json` through `gh api`; `dossier.engagement.allowedActions.networkAccess` is false (EV-0077). Its local-source checks were reproduced independently as CHK-34 |
| CHK-50 | `plugins/flow/bin/flow-eval-run.sh` | flow correctness eval harness | — | 2026-09-10 | **not executed** | Requires paid multi-model API access and network; `networkAccess` is false. The retained 2026-09-09 output is cited as reported evidence instead (EV-0096) |

## Unavailable evidence

| Source sought | Why it matters | Why unavailable | Would settle | Open question |
|---|---|---|---|---|
| Install and usage counts per plugin | The only direct measure of whether any plugin is used, and by how many operators | GitHub exposes no install telemetry for plugin marketplaces, and the plugins emit none by design | Whether the marketplace has users, and which plugins matter | AQ-0004 |
| The `prompt-decorators` source tree | It is a published marketplace entry whose quality is asserted here on the strength of its manifest alone | The source lives in a separate repository and is not vendored | Whether the entry's description matches its contents | AQ-0005 |
| Upstream `agent-capability-standard` history beyond the pinned commit | Determines whether the pinned tree matches the version the marketplace advertises | The submodule is pinned 2 commits past `v1.2.0`; those commits were not read | Whether "1.2.0" accurately labels what installs | AQ-0006 |
| A record of an external contribution being reviewed and merged | Distinguishes a project that could accept contribution from one that has | Only one commit identity exists across all refs | Whether the contribution path works in practice | AQ-0007 |
| Windows and Git Bash execution results for the shipped shell scripts | The marketplace ships 26 shell scripts and hooks that run on the operator's machine, and two open issues assert portability defects | No Windows environment was available to this assessment | The real portability surface | AQ-0008 |
| A vulnerability-scan artifact for this range | Nothing in this package can state anything about the project's dependency-vulnerability status without one | No `.dossier/scan/` bundle was produced for this run and no scan artifact is checked in; `runSecurityScan` is false, so no scanner was invoked | Whether any dependency of any shipped plugin carries a known vulnerability | not yet registered — see EV-0078 |
| CodeQL findings for this repository | `codeql.yml` runs, but its results are the only automated security signal this repository produces | SARIF is uploaded to GitHub code scanning, which is not readable with `networkAccess` false | Whether the shipped shell and Python code has open code-scanning alerts | not yet registered — see EV-0079 |
| The `agent-capability-standard` tree at pinned sha `9e2f65b` and the `prompt-decorators` tree at pinned sha `9c792fe` | Two of eight published entries install from these pins, and the manifest asserts a version for each | Neither is vendored here and `networkAccess` is false | Whether the advertised versions 1.2.0 and 0.1.1 match what an installer actually receives | AQ-0005 extended — see EV-0061, EV-0062 |
| GitHub Actions run results at `15bcb24` | The flow suite fails 114 assertions locally; whether CI agrees decides whether this is a platform artefact or a real defect | No Actions history was read; `networkAccess` is false | Whether `flow-tests.yml` and the new `marketplace-manifest.yml` pass at this commit | not yet registered — see EV-0070, EV-0082 |

## Stale evidence

| Evidence ID | Expiry basis | Expired on | Current state | Required refresh action | Owner |
|---|---|---|---|---|---|
| `EV-0001` | "until marketplace.json changes" | 2026-09-10 | 8 entries, metadata 4.10.0 | Superseded by EV-0057 | Daniel Bentes |
| `EV-0002` | "until next release" | 2026-09-10 | 4.10.0 | Superseded by EV-0057 | Daniel Bentes |
| `EV-0003` | "until sources change" | efb4f75, 2026-09-10 | No `.gitmodules`; a pinned `github` source | Superseded by EV-0058 | Daniel Bentes |
| `EV-0004` | "until a skill is added or removed" | 2026-09-10 | 71 tracked `SKILL.md` files | Superseded by EV-0093 | Daniel Bentes |
| `EV-0008` | "until flow changes" | 2026-09-10 | pass=2222 fail=114 | Superseded by EV-0068 | Daniel Bentes |
| `EV-0009` | "until dossier changes" | 2026-09-10 | pass=1951 fail=0 | Superseded by EV-0067 | Daniel Bentes |
| `EV-0053` | "until the client changes" | efb4f75, 2026-09-10 | There is no submodule to populate | Superseded by EV-0059 | Daniel Bentes |
| All 21 dated package documents | `last-verified: 2026-07-26` against a HEAD 16 commits ahead | 2026-09-10 | Every document describes `06b1586` | Redraft under this refresh, then re-run verification and the gate | Daniel Bentes |

Rows EV-0001 to EV-0056 were observed on 2026-07-26 against commit `06b1586`. Rows EV-0057 to EV-0097 were observed on 2026-09-10 against commit `15bcb24` on branch `docs/dossier-refresh` (EV-0092). The rows listed above have passed their stated freshness horizon and are superseded as named; they keep their state until every consuming document has moved.

## Secrets and sensitive material encountered

Type and location category only. No values, no excerpts, no exploitable detail.

| Type | Location category | Severity | Confidentiality | Remediation need | Reported through |
|---|---|---|---|---|---|
| none | — | — | — | none | `cmd:CHK-19` returned no match outside detector definitions and their fixtures |

The scan covered tracked files only, using the pattern set the repository's own `block-secrets.sh` and `dossier-validate-patch.sh` enforce. A negative result over a known pattern set proves that none of the enumerated formats appears — not that no credential exists. Untracked working-tree files were not scanned.
