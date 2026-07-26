---
dossier-header: internal-v1
title: Components and Codebase
purpose: Lets someone new place a change correctly on their first day without reading the whole tree.
audience: Contributor, Maintainer, Reviewer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 13c99b1
last-verified: 2026-07-26
review-trigger: A plugin is added or removed; a convention changes; a bin/ or hooks/ script is added
related: [02-architecture/system-architecture.md, 00-control/terminology-and-ownership.md, 03-assurance/testing-quality-and-delivery.md, 04-operating/onboarding-and-local-development.md]
---
# Components and Codebase
<!-- contract: references/package-contract-02-architecture.md#components-and-codebase -->

This document explains structure and decision-relevant hotspots. It does not reproduce the file tree — a reader who wants the tree can run `ls`, and a pasted tree is stale on the next commit.

## Repository and module map

| Repository | Purpose | Language / runtime | Build system | Owner | Criticality | Evidence |
|---|---|---|---|---|---|---|
| `synaptiai/synapti-marketplace` | This repository. Manifest plus 6 in-tree plugins | Markdown, JSON, bash | none — there is no build step for the plugins themselves | Daniel Bentes | critical | [EV-0001], [EV-0044] |
| `synaptiai/agent-capability-standard` | Submodule at `plugins/agent-capability-standard`, pinned to `95f7ac2` | Python 3.10+, Markdown | `pyproject.toml`, package name `grounded-agency` | Daniel Bentes | medium | [EV-0031], [EV-0041] |
| `synaptiai/prompt-decorators` | External `git-subdir` source at `claude-code-plugin`, ref `main` | not inspected (AQ-0005) | not inspected | Daniel Bentes | medium | [EV-0030] |

| Module or package | Repository | Responsibility | Depends on | Depended on by | Evidence |
|---|---|---|---|---|---|
| `.claude-plugin/marketplace.json` | this | Discovery manifest for all 8 entries | every plugin's `plugin.json` for version agreement | the Claude Code client | [EV-0001], [EV-0026] |
| `plugins/flow` | this | GitHub development workflow. 32 skills, 23 commands, 9 agents, 12 hook scripts, 12 `bin/` scripts | nothing in-repo at runtime | dossier borrowed its cascade resolver and test harness by copy | [EV-0004], [EV-0038] |
| `plugins/dossier` | this | Evidence-first documentation and post-merge automation. 9 skills, 9 commands, 6 agents, 4 hook scripts, 14 `bin/` scripts | nothing at runtime | nothing | [EV-0009] |
| `plugins/gh-workflow` | this | Predecessor of flow. 7 skills, 14 commands, 4 agents | nothing | nothing. Mutually exclusive with flow by instruction, not by mechanism | [EV-0004] |
| `plugins/decipon` | this | Manipulation and disinformation analysis. 2 skills, 7 commands, 5 agents | nothing | nothing | [EV-0004] |
| `plugins/context-ledger` | this | Evidence-based product development. 5 skills, 8 commands, 5 agents | nothing | nothing | [EV-0004] |
| `plugins/ai-first-org-design-kit` | this | Organizational design. 15 skills, no commands, no agents | nothing | nothing | [EV-0004], [EV-0027] |
| `plugins/agent-capability-standard` | submodule | 42 skills. The only module with a dependency manifest | `pyyaml>=6.0` | nothing in this repository | [EV-0041] |
| `.github/workflows` | this | 4 workflows | `plugins/*/tests/run.sh`, `scripts/package-desktop-skills.sh` | nothing | [EV-0012] |
| `scripts/package-desktop-skills.sh` | this | Builds Claude Desktop skill ZIPs from `SKILL.md` files | every `SKILL.md` in the tree | `release-desktop-skills.yml` | [EV-0012] |

No in-tree plugin depends on another at runtime. That is deliberate: plugins install independently, so a shared library would be unresolvable at the installed-plugin level. Where two plugins need the same logic, the logic is copied — `cascade-resolve.sh` and the test harness both exist twice.

## Component catalog

| Component | Purpose | Owner | Language / runtime | Entry point | Interfaces exposed | Dependencies | State owned | Deployment unit | Criticality | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Marketplace manifest | Discovery | Daniel Bentes | JSON | `.claude-plugin/marketplace.json` | Read by the Claude Code client | none | none | the repository | critical | [EV-0001] |
| flow | Workflow harness | Daniel Bentes | Markdown + bash | `plugins/flow/.claude-plugin/plugin.json` | 23 `/flow:*` commands, 6 hook events, `.flow/` state | none | `.flow/`, `.decisions/` in the consuming repository | plugin | critical | [EV-0038], [EV-0046] |
| dossier | Documentation harness | Daniel Bentes | Markdown + bash | `plugins/dossier/.claude-plugin/plugin.json` | 9 `/dossier:*` commands, 3 hook events, a settings schema, a CI workflow template | none | `docs/dossier/`, `.dossier/` in the consuming repository | plugin | high | [EV-0009], [EV-0039] |
| gh-workflow | Workflow harness (predecessor) | Daniel Bentes | Markdown | `plugins/gh-workflow/.claude-plugin/plugin.json` | 14 `/gh-*` commands | none | none | plugin | medium | [EV-0004] |
| decipon | Content analysis | Daniel Bentes | Markdown | its `plugin.json` | 7 commands, 5 agents | none | none | plugin | medium | [EV-0004] |
| context-ledger | Product development | Daniel Bentes | Markdown | its `plugin.json` | 8 commands, 5 agents | none | none | plugin | medium | [EV-0004] |
| ai-first-org-design-kit | Organizational design | Daniel Bentes | Markdown | its `plugin.json` | 15 skills, no commands | none | none | plugin | medium | [EV-0027] |
| agent-capability-standard | Agent capability specification | Daniel Bentes | Markdown + Python | its `plugin.json`, `pyproject.toml` | 42 skills, 2 hook events | `pyyaml>=6.0` | none | plugin (submodule) | medium | [EV-0031], [EV-0041] |
| Desktop packager | Release-time artifact build | Daniel Bentes | bash | `scripts/package-desktop-skills.sh` | ZIPs attached to GitHub releases | `zip`, `gh` | `dist/desktop` (untracked) | script | low | [EV-0012] |

## Directory and package conventions

| Convention | Rule | Enforced by | Consequence of ignoring it | Evidence |
|---|---|---|---|---|
| Plugin identity | Every plugin has `.claude-plugin/plugin.json` with `name`, `version`, `description`, `author`, `license` | review; **tested only for flow and dossier** | The client cannot resolve the plugin | [EV-0010] |
| Version agreement | `plugin.json.version` equals the `marketplace.json` entry version | review; tested inside the flow and dossier suites for their own plugin only | An operator installs a version different from the one advertised | [EV-0026] |
| One skill, one directory | `skills/<name>/SKILL.md`; the directory name matches the skill's `name` | flow and dossier test suites | The skill does not load, or loads under an unexpected name | [EV-0004] |
| A directory is not a skill | Only a directory containing `SKILL.md` counts. `skills/learned/` holds only `.gitkeep` | unenforced | Counting directories yields 33 for flow where 32 skills exist — the origin of CT-0002 | [EV-0029] |
| Command naming | The filename is the command name. Command files carry no `name:` key | dossier test suite for its own commands | A `name:` key is ignored, so the file silently answers to a different name than intended | [EV-0005] |
| Shell portability | No `declare -A`, `readarray`, `mapfile`, or `${var^^}`; `set -u` required; a `# Usage:` header required | flow and dossier test suites | Breaks on macOS bash 3.2, which is the default shell on the maintainer's own platform | [EV-0008], [EV-0009] |
| Executable bit | Every `bin/` and `hooks/scripts/` file is executable | flow and dossier test suites, and `dossier-tests.yml` | The client cannot run the hook; the failure surfaces in the operator's session, not here | [EV-0007] |
| Commit format | `<type>(<scope>): <subject>`; branch `feature/issue-{n}-{desc}` | `.claude/CLAUDE.md`; unenforced by CI | Inconsistent history; no functional consequence | `.claude/CLAUDE.md` |
| No Claude attribution in commits | No `Co-Authored-By: Claude` lines | `.claude/CLAUDE.md`; unenforced | — | `.claude/CLAUDE.md` |

Two conventions above are enforced only within the plugins that invented them. Nothing checks the other five plugins, and nothing checks the manifest at all.

## Lifecycle through the code

The path a unit of work takes from entry to completion.

| Stage | Handled by | Input | Output | Errors surfaced how | Evidence |
|---|---|---|---|---|---|
| Discovery | `.claude-plugin/marketplace.json` | A marketplace name | 8 plugin entries with resolvable sources | Client-side error; nothing in this repository detects a malformed manifest | [EV-0001] |
| Resolution | The Claude Code client | One entry's `source` | A materialized plugin directory in the client cache | Client-side | [EV-0052] |
| Registration | `hooks/hooks.json`, `plugin.json` | The plugin directory | Registered commands, skills, agents, and hook bindings | Client-side | [EV-0040] |
| Invocation | `commands/*.md`, `skills/*/SKILL.md` | Operator input or a skill trigger | Markdown loaded into session context | Model-visible; a broken cross-reference degrades silently | [EV-0004], [EV-0005] |
| Deterministic work | `bin/*.sh` | Command arguments and repository state | `KEY=value` lines on stdout, exit codes 0/1/2 | Exit codes and `::error` style lines; the calling command interprets them | [EV-0007] |
| Interception | `hooks/scripts/*.sh` | The pending tool call | permit or block | Non-zero exit blocks the tool call | [EV-0038] |
| Verification | `tests/run.sh` in flow and dossier | The tree | `TOTAL pass=<n> fail=<n>` | Non-zero exit; surfaced in CI, but advisory | [EV-0008], [EV-0009] |
| Release | `git tag` plus a published GitHub release | A version bump in two files | Tag, release, and desktop ZIPs | Workflow failure leaves a release without assets | [EV-0012], [EV-0032] |

### Trace

One concrete path, from an operator's keystroke to a decision, through the dossier plugin — the same path this documentation package was produced by:

1. The operator types `/dossier:init`. The client loads `plugins/dossier/commands/init.md` into context. The file's frontmatter declares `allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, AskUserQuestion`, which bounds what the command may do before a single line of its body runs.
2. The command's Phase 0 `!` block resolves the plugin root. It cannot rely on `CLAUDE_PLUGIN_ROOT` being set, so it falls back through four candidate paths — the in-tree path, the versioned client cache, and the marketplace clone — testing each for an executable `bin/dossier-resolve-config.sh`. This fallback exists because the environment variable proved unset in slash-command bash blocks.
3. It calls `bin/dossier-resolve-config.sh dossier.project.outputRoot`, which walks the settings cascade: `DOSSIER_*` environment variables, then `.claude/settings.dossier.local.json`, then `.claude/settings.dossier.json`, then `$HOME/.claude/settings.dossier.json`, then the plugin's own `settings.json`. Absence at each layer is decided by `jq -e '(path) != null'`, not by shell emptiness, so an explicit `""` or `false` at a higher layer is honoured rather than falling through.
4. It emits `KEY=value` lines. The command reads them from the transcript. This is the boundary between deterministic logic and model judgment: the script decides, the model orchestrates.
5. `bin/dossier-validate-config.sh` runs. Conditional and cross-field rules live here rather than in `schema.json`, because the documented fallback validator silently ignores `if`/`then` when `jsonschema` is absent — a schema conditional would report success and enforce nothing on exactly the machines that lack the dependency.
6. `bin/dossier-scaffold.sh --output-root docs/dossier` copies 23 templates. It never overwrites: an existing file is skipped, not merged, because the package holds hand-written evidence and a scaffold that clobbers is one nobody dares re-run. It emits `SCAFFOLD_CREATED=23 SCAFFOLD_SKIPPED=0 SCAFFOLD_FAILED=0` [EV-0047].
7. `bin/dossier-package-check.sh` parses each file's YAML frontmatter with a shell path — no Python dependency — asserts the header enum values, and reads body line 2 to check that the contract pointer resolves to a real anchor in a real reference file. Immediately after scaffolding it reports 175 findings, all unfilled `{fill}` header fields, which is the correct answer at that stage.

The files a contributor touches on that path: one command file, one or two `bin/` scripts, and the tests that guard them. Nothing else.

## Extension points and common change paths

| Change a teammate commonly makes | Where to make it | What else must change | Tests to run | Evidence |
|---|---|---|---|---|
| Add a skill to a plugin | `plugins/<p>/skills/<name>/SKILL.md` | Any prose stating a skill count — the plugin README and the marketplace description both currently drift | `plugins/<p>/tests/run.sh` where one exists | [EV-0027], [EV-0028] |
| Add a command | `plugins/<p>/commands/<name>.md` | `## Required Skills` must list every `Skill(X)` the body invokes, and each must resolve on disk | dossier and flow suites lint this for their own plugins | [EV-0005] |
| Add a `bin/` script | `plugins/<p>/bin/<name>.sh` | Executable bit; a `# Usage:` header; `set -u`; no bash 4 constructs | `bin-scripts.test.sh` in flow or dossier | [EV-0007] |
| Add a hook | `plugins/<p>/hooks/hooks.json` plus a script | The hook runs on every operator's machine — this is the highest-consequence change in the repository | `hooks.test.sh`; there is no runtime test | [EV-0040] |
| Add a plugin | `plugins/<name>/` plus a `marketplace.json` entry | Marketplace version; the README plugin table and badge; the category list | Nothing validates the manifest | [EV-0022] |
| Bump a plugin version | `plugin.json` **and** the `marketplace.json` entry | Both, always. They are checked against each other by hand only | Nothing automated | [EV-0026] |
| Cut a release | Tag plus a GitHub release | `marketplace.json` `metadata.version` | `release-desktop-skills.yml` fires automatically | [EV-0032] |

## Generated and vendored code

| Path | Kind | Generated or vendored from | Regeneration command | Edited by hand | Evidence |
|---|---|---|---|---|---|
| `plugins/dossier/bin/cascade-resolve.sh` | copied | `plugins/flow/bin/cascade-resolve.sh` | none — copied once, then diverged | **yes** — dossier's copy now decides absence with `jq -e`, which flow's does not | [EV-0007] |
| `plugins/dossier/tests/lib/assert.sh`, `tests/run.sh` | copied | the flow test harness | none | yes — identifiers were renamed from `_flow_*` to `_dossier_*` | [EV-0009] |
| `plugins/agent-capability-standard/**` | vendored | `synaptiai/agent-capability-standard` at `95f7ac2` | `git submodule update --remote` | no | [EV-0031] |
| `dist/desktop/**` | generated | every `SKILL.md`, by `scripts/package-desktop-skills.sh` | `bash scripts/package-desktop-skills.sh --clean` | no — untracked, built on release | [EV-0012] |

The first row is a real hazard of copy-vendoring, and it has already materialized: the two `cascade-resolve.sh` files no longer behave identically. Dossier's copy treats an explicit empty string as a value; flow's treats it as absence. Neither file records that the other exists, so a future reader of flow's copy has no way to learn that the same bug was found and fixed next door.

## Configuration model

| Setting | Purpose | Sources in precedence order | Default | Validated where | Evidence |
|---|---|---|---|---|---|
| `dossier.project.outputRoot` | Where the documentation package is written | `DOSSIER_PROJECT_OUTPUT_ROOT` → `.claude/settings.dossier.local.json` → `.claude/settings.dossier.json` → `$HOME/.claude/settings.dossier.json` → plugin `settings.json` | `docs/dossier` | `schema.json` pattern plus `bin/dossier-validate-config.sh` | [EV-0048] |
| `dossier.engagement.allowedActions.*` | The action ceiling for a documentation run — read secrets, run builds, run tests, network, write outside the output root, contact humans | same cascade | every capability `false` except `readSource` | `schema.json`; enforced at runtime by `hooks/scripts/enforce-allowed-actions.sh` | [EV-0039] |
| `dossier.disclosure.policy` | Governs what may appear in `06-public/**` | same cascade | `internal-only` | `bin/dossier-validate-config.sh` rejects self-approval of public claims | [EV-0048] |
| `dossier.ci.*` | Post-merge automation: triggers, branch strategy, thresholds, write allowlist | same cascade | path-filtered, rolling branch, `docs/dossier/**` allowlist | `schema.json` plus the validator | [EV-0048] |
| `flow.*` | The flow plugin's own settings tree, including the merge gate's `markerTrust` | the equivalent flow cascade | see `plugins/flow/settings.json` | `plugins/flow/schema.json` | [EV-0008] |

No secret value appears in this table, and none exists in the repository to appear [EV-0037].

## Feature flags and rollout controls

| Flag | Controls | Default | Current state per environment | Owner | Removal condition | Evidence |
|---|---|---|---|---|---|---|
| `dossier.ci.enabled` | Whether the post-merge refresh runs at all | `true` in the plugin default; the scaffolded workflow is absent from this repository | not installed here | Daniel Bentes | none stated | [EV-0045] |
| `dossier.ci.instructionSource` | `plugin` reads skill text from marketplace `main`; `vendored` copies it into the consuming repository | `plugin` | not applicable here | Daniel Bentes | When `plugin_marketplaces` accepts a ref | [EV-0030] |
| `dossier.local.onFlowMerge` | Whether a flow merge suggests a documentation refresh | `suggest` | not exercised | Daniel Bentes | none stated | [EV-0045] |

There are no runtime feature flags, because there is no runtime. Every row above is an install-time configuration default. Two of the three have no removal condition, which is recorded as debt in `04-operating/decisions-technical-debt-and-risks.md`.

## Build and artifact production

| Artifact | Produced by | Command | Inputs | Output location | Reproducible | Evidence |
|---|---|---|---|---|---|---|
| Installed plugin | The Claude Code client | `claude plugin install <name>` | The repository at the resolved ref | `~/.claude/plugins/cache/<marketplace>/<plugin>` | yes for in-tree plugins; **no** for `prompt-decorators`, which floats on `main` | [EV-0030], [EV-0052] |
| Desktop skill ZIPs | `scripts/package-desktop-skills.sh` | `bash scripts/package-desktop-skills.sh --clean` | Every `SKILL.md` in the tree | `dist/desktop/**` — untracked | unknown — never verified byte-for-byte across two runs | [EV-0012] |
| GitHub release | Manual tag plus release | `gh release create` | The tag | GitHub Releases | yes | [EV-0032] |

There is no build step for the plugins themselves. What is committed is what installs.

## Legacy, deprecated, experimental, and orphaned areas

| Area | Classification | Still executed | Safe to remove | What blocks removal | Evidence |
|---|---|---|---|---|---|
| `plugins/gh-workflow` | legacy | yes, if an operator enables it | no | It is published and installed; it has 14 commands and no deprecation notice. `.claude/CLAUDE.md` says to enable only one of gh-workflow and flow, which is guidance, not a mechanism | [EV-0004] |
| `.claude/commands/gh-*.md` | legacy | yes, in this repository's own sessions | unknown | The repository's own `CLAUDE.md` documents both the `/gh-*` and `/flow:*` command sets as current | `.claude/CLAUDE.md` |
| `plugins/flow/skills/learned/` | experimental | no — it is empty | no | It is a reserved location for learned skills; removing it would remove the convention | [EV-0029] |
| `dist/desktop/` | generated | on release only | yes, at any time | Nothing — it is untracked | [EV-0012] |
| Root-level drafts: `flow_plugin_medium_article_grounded.md`, `Provably_correct_code_with_Flow_AI_agents_eng.txt` | orphaned | no | unknown | Untracked working-tree files, not part of the repository | working tree at `13c99b1` |

## Code ownership and bus factor

| Area | Owner | Contributors in inspected history | Bus factor | Consequence | Evidence |
|---|---|---|---|---|---|
| Every path in this repository | Daniel Bentes | 1 | 1 | No component has a second person who has ever changed it | [EV-0035] |
| `plugins/flow` | Daniel Bentes | 1 | 1 | The largest plugin, 1022 assertions, one reader | [EV-0008], [EV-0035] |
| `plugins/dossier` | Daniel Bentes | 1 | 1 | 1229 assertions, one reader | [EV-0009], [EV-0035] |
| `.github/workflows` | Daniel Bentes | 1 | 1 | A workflow change lands with no second opinion and no required check | [EV-0016], [EV-0035] |

The inspected history window is the full repository history across all refs: 366 commits, first 2025-12-19, most recent 2026-07-26 [EV-0034], [EV-0035]. Contributor counts describe that window, not who understands the code today — but with a single identity across the whole window, the two coincide.

## Where to make this change

| Task | Start here | Then | Verify with | Evidence |
|---|---|---|---|---|
| Fix a stale README fact | `README.md` | Cross-check every version cell against `marketplace.json`, and the badge count against `.plugins \| length` | `jq` comparison; nothing automated exists | [EV-0022]–[EV-0025] |
| Add a licence | `LICENSE` at the repository root | Nothing else — the plugin manifests already declare MIT and Apache-2.0 | `gh api repos/... --jq .license` returns non-null | [EV-0018], [EV-0019] |
| Make CI blocking | GitHub repository settings, not a file | Enable branch protection on `main` requiring both test workflows | `gh api repos/.../branches/main/protection` returns 200 | [EV-0016] |
| Fix a flow behaviour | The relevant `plugins/flow/skills/*/SKILL.md` or `bin/*.sh` | Update or add the matching assertion in `plugins/flow/tests/` | `plugins/flow/tests/run.sh` | [EV-0008] |
| Fix a dossier behaviour | `plugins/dossier/{skills,commands,bin}/…` | Add a regression assertion — the suite's convention is one test per defect | `plugins/dossier/tests/run.sh` | [EV-0009] |
| Pin `prompt-decorators` | The entry's `source.ref` in `.claude-plugin/marketplace.json` | Choose a tag that exists upstream | Re-install and compare | [EV-0030] |
| Add Windows support | Both test workflows | A `windows-latest` matrix leg, then fix what it surfaces | The new CI leg; issues #100 and #130 | [EV-0049] |
