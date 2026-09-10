---
dossier-header: internal-v1
title: Components and Codebase
purpose: Lets someone new place a change correctly on their first day without reading the whole tree.
audience: Contributor, Maintainer, Reviewer
confidentiality: Public
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A plugin is added or removed; a convention changes; a bin/ or hooks/ script is added
related: [02-architecture/system-architecture.md, 00-control/terminology-and-ownership.md, 03-assurance/testing-quality-and-delivery.md, 04-operating/onboarding-and-local-development.md]
---
# Components and Codebase
<!-- contract: references/package-contract-02-architecture.md#components-and-codebase -->

This document explains structure and decision-relevant hotspots. It does not reproduce the file tree. A reader who wants the tree can run `ls`, and a pasted tree is stale on the next commit.

Some claims here rest on live GitHub or client-machine reads that this engagement's action ceiling forbids re-running (AQ-0012). Every one of those carries its observation date inline, in its own table cell or sentence. A claim with no date was re-read in the tree at `7ee4923`.

## Repository and module map

| Repository | Purpose | Language / runtime | Build system | Owner | Criticality | Evidence |
|---|---|---|---|---|---|---|
| `synaptiai/synapti-marketplace` | This repository. One manifest publishing 8 entries, of which 6 are in-tree plugins | Markdown, JSON, bash, plus one Python eval driver | none — the plugins have no build step | Daniel Bentes | critical | [EV-0057], [EV-0058], [EV-0095] |
| `synaptiai/agent-capability-standard` | Published as a `github` source pinned to sha `9e2f65b`. No copy of it is tracked here | not inspected at the pinned sha (AQ-0006) | not inspected (AQ-0006) | Daniel Bentes | medium | [EV-0058], [EV-0059], [EV-0127] |
| `synaptiai/prompt-decorators` | Published as a `git-subdir` source at `claude-code-plugin`, pinned to sha `9c792fe` | not inspected (AQ-0005) | not inspected | Daniel Bentes | medium | [EV-0058], [EV-0127] |

Neither external source is a git submodule. No `.gitmodules` file exists in the tracked tree [EV-0059].

| Module or package | Repository | Responsibility | Depends on | Depended on by | Evidence |
|---|---|---|---|---|---|
| `.claude-plugin/marketplace.json` | this | Discovery manifest for all 8 entries, at metadata version 4.10.0 | each entry's own `plugin.json` for version agreement | the Claude Code client | [EV-0057], [EV-0064] |
| `plugins/flow` | this | GitHub development workflow. 32 skills, 23 commands, 9 agents, 14 hook scripts, 20 `bin/` scripts | nothing in-repo at runtime | nothing. Dossier carries its own resolver and test harness under the same names | [EV-0162], [EV-0129] |
| `plugins/flow/evals` | this | Correctness evaluation harness: 4 cases with hidden tests and trap variants, 82 tracked files | `bin/flow-eval-run.sh`, `bin/_flow_eval.py` | nothing | [EV-0095] |
| `plugins/dossier` | this | Evidence-first documentation and post-merge automation. 10 skills, 9 commands, 6 agents, 5 hook scripts, 20 `bin/` scripts | nothing at runtime | nothing | [EV-0162], [EV-0129] |
| `plugins/gh-workflow` | this | Predecessor of flow. 7 skills, 14 commands, 4 agents | nothing | nothing. Mutually exclusive with flow by instruction, not by mechanism | [EV-0162] |
| `plugins/decipon` | this | Manipulation and disinformation analysis. 2 skills, 7 commands, 5 agents | nothing | nothing | [EV-0162] |
| `plugins/context-ledger` | this | Evidence-based product development. 5 skills, 8 commands, 5 agents | nothing | nothing | [EV-0162] |
| `plugins/ai-first-org-design-kit` | this | Organizational design. 15 skills, no commands, no agents | nothing | nothing | [EV-0162] |
| `.github/workflows` | this | 5 workflows: codeql, dossier-tests, flow-tests, marketplace-manifest, release-desktop-skills | `plugins/{flow,dossier}/tests/run.sh`, `scripts/check-plugin-versions.sh`, `scripts/package-desktop-skills.sh` | nothing | [EV-0123], [EV-0081] |
| `scripts/check-plugin-versions.sh` | this | The marketplace manifest check (TM-0033). 252 lines. Compares every entry's advertised version against its source | `gh api` for external sources | `marketplace-manifest.yml` | [EV-0080], [EV-0081] |
| `scripts/package-desktop-skills.sh` | this | Builds Claude Desktop skill ZIPs from `SKILL.md` files | every `SKILL.md` in the tree | `release-desktop-skills.yml` | [EV-0012], [EV-0123] |

The per-plugin census at `7ee4923` [EV-0162]:

| Plugin | Skills | Commands | Agents | `bin/` scripts | `hooks.json` |
|---|---|---|---|---|---|
| flow | 32 | 23 | 9 | 20 | yes |
| ai-first-org-design-kit | 15 | 0 | 0 | 0 | no |
| dossier | 10 | 9 | 6 | 20 | yes |
| gh-workflow | 7 | 14 | 4 | 0 | no |
| context-ledger | 5 | 8 | 5 | 0 | no |
| decipon | 2 | 7 | 5 | 0 | no |

The 40 `bin/` scripts supersede the tree-wide figure of 37 recorded at an earlier commit [EV-0162], [EV-0093].

`ai-first-org-design-kit` ships skills and nothing else [EV-0162]. It is the one entry whose whole surface is a skill library, which is why it has no command or hook surface to test.

No in-tree plugin depends on another at runtime. That is deliberate. Plugins install independently, so a shared library would be unresolvable at the installed-plugin level. Where two plugins need the same logic, each carries its own copy. `cascade-resolve.sh` and the test harness both exist twice, under the same names and with different behaviour [EV-0142].

A fully populated `plugins/agent-capability-standard/` directory exists on the maintainer's machine, but it is untracked and ignored at `.gitignore` line 54 [EV-0060]. It is working-tree residue of a removed submodule, not repository content. Any `find plugins ...` count taken on that machine silently includes it [EV-0060].

Commit `efb4f75` records why the submodule was replaced by a pinned source. The gitlink resolved to 0 entries in a plain clone, so the advertised plugin could not install at all. The pin was also 17 commits and 74 files behind upstream, while both it and upstream reported version 1.2.0 [EV-0167].

## Component catalog

| Component | Purpose | Owner | Language / runtime | Entry point | Interfaces exposed | Dependencies | State owned | Deployment unit | Criticality | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Marketplace manifest | Discovery | Daniel Bentes | JSON | `.claude-plugin/marketplace.json` | Read by the Claude Code client | none | none | the repository | critical | [EV-0057] |
| Marketplace manifest check (TM-0033) | Version-agreement gate | Daniel Bentes | bash | `scripts/check-plugin-versions.sh` | Exit code plus a per-entry report; runs in `marketplace-manifest.yml` | `jq`, `gh api` for external sources | none | CI job | high | [EV-0080], [EV-0081] |
| flow | Workflow harness | Daniel Bentes | Markdown, bash, Python (evals only) | `plugins/flow/.claude-plugin/plugin.json` | 23 `/flow:*` commands, the hook events in `hooks/hooks.json`, `.flow/` state | none at runtime | `.flow/`, and `.decisions/` — 21 tracked records here | plugin | critical | [EV-0162], [EV-0095], [EV-0169] |
| dossier | Documentation harness | Daniel Bentes | Markdown, bash | `plugins/dossier/.claude-plugin/plugin.json` | 9 `/dossier:*` commands, 5 hook scripts, a settings schema, a CI workflow template | none at runtime | `docs/dossier/`, `.dossier/` in the consuming repository | plugin | high | [EV-0162], [EV-0039], [EV-0166] |
| gh-workflow | Workflow harness (predecessor) | Daniel Bentes | Markdown | `plugins/gh-workflow/.claude-plugin/plugin.json` | 7 skills, 14 commands, 4 agents | none | none | plugin | medium | [EV-0162] |
| decipon | Content analysis | Daniel Bentes | Markdown | its `plugin.json` | 2 skills, 7 commands, 5 agents | none | none | plugin | medium | [EV-0162] |
| context-ledger | Product development | Daniel Bentes | Markdown | its `plugin.json` | 5 skills, 8 commands, 5 agents | none | none | plugin | medium | [EV-0162] |
| ai-first-org-design-kit | Organizational design | Daniel Bentes | Markdown | its `plugin.json` | 15 skills, no commands, no agents | none | none | plugin | medium | [EV-0162] |
| agent-capability-standard | Agent capability specification | Daniel Bentes | not inspected at sha `9e2f65b` | its own `plugin.json` upstream | not inspected (AQ-0006) | not inspected | none | external plugin entry | medium | [EV-0058], [EV-0127] |
| Desktop packager | Release-time artifact build | Daniel Bentes | bash | `scripts/package-desktop-skills.sh` | ZIPs attached to GitHub releases | `zip`, `gh` | `dist/desktop` (untracked) | script | low | [EV-0012] |

The `agent-capability-standard` entry advertises 1.2.0, and the tree at sha `9e2f65b` reports that same version [EV-0127]. That result was observed by the session operator, outside this engagement's action ceiling (AQ-0012).

Dossier's fifth hook script is `detect-local-merge.sh`, a `PostToolUse` hook watching for merge-shaped Bash commands against the default branch and gated by `dossier.local.onLocalMerge` [EV-0166]. Its own header states that it never reads another plugin's settings, state or presence, which is the self-containment rule every plugin here follows [EV-0166].

## Directory and package conventions

| Convention | Rule | Enforced by | Consequence of ignoring it | Evidence |
|---|---|---|---|---|
| Plugin identity | Every plugin has `.claude-plugin/plugin.json` with `name`, `version`, `description`, `author`, `license` | review; **tested only for flow and dossier** | The client cannot resolve the plugin | [EV-0010] |
| Version agreement | `plugin.json.version` equals the `marketplace.json` entry version, for in-tree and external sources alike | `scripts/check-plugin-versions.sh`, run in CI by `marketplace-manifest.yml` (TM-0033) | The check fails the job. Before this existed, an operator could install a version other than the advertised one | [EV-0080], [EV-0081], [EV-0127] |
| External sources are pinned | Every external entry carries a `sha` alongside its `ref` | the same check, which fails an external source with no `sha` | Two installs on different days need not agree | [EV-0058], [EV-0080] |
| One skill, one directory | `skills/<name>/SKILL.md`; the directory name matches the skill's `name` | flow and dossier test suites | The skill does not load, or loads under an unexpected name | [EV-0093] |
| A directory is not a skill | Only a directory containing `SKILL.md` counts. `skills/learned/` holds only `.gitkeep` | unenforced | Counting directories yields 33 for flow where 32 skills exist. That was CT-0002, resolved when flow's README was corrected at `7ee4923` | [EV-0029], [EV-0170] |
| Command naming | The filename is the command name. Command files carry no `name:` key | dossier test suite for its own commands | A `name:` key is ignored, so the file silently answers to a different name than intended | [EV-0005] |
| Shell portability | No `declare -A`, `readarray`, `mapfile`, or `${var^^}`; `set -u` required; a `# Usage:` header required | flow and dossier test suites | Breaks on macOS bash 3.2, the maintainer's own default shell | [EV-0098], [EV-0107] |
| Executable bit | Every `bin/` and `hooks/scripts/` file is executable | flow and dossier test suites, and `dossier-tests.yml` | The client cannot run the hook. The failure surfaces in the operator's session, not here | [EV-0093], [EV-0129] |
| Commit format | `<type>(<scope>): <subject>`; branch `feature/issue-{n}-{desc}` | `.claude/CLAUDE.md`; unenforced by CI | Inconsistent history; no functional consequence | `.claude/CLAUDE.md` |
| No Claude attribution in commits | No `Co-Authored-By: Claude` lines | `.claude/CLAUDE.md`; unenforced | — | `.claude/CLAUDE.md` |

Structural conventions are enforced only inside the two plugins that invented them. The manifest itself is no longer unchecked: version agreement and sha presence now fail a CI job [EV-0080], [EV-0081]. That check reports a pin that is stale but self-consistent rather than failing it [EV-0080].

## Lifecycle through the code

The path a unit of work takes from entry to completion.

| Stage | Handled by | Input | Output | Errors surfaced how | Evidence |
|---|---|---|---|---|---|
| Discovery | `.claude-plugin/marketplace.json` | A marketplace name | 8 plugin entries with resolvable sources | Version disagreement and a missing external `sha` fail the CI check. No row establishes that malformed JSON is caught here | [EV-0057], [EV-0080] |
| Resolution | The Claude Code client | One entry's `source` | A materialized plugin directory in the client cache | Client-side | Inferred: distribution is a git read by the client, reasoned from the absence of any publish step [EV-0043, I] |
| Registration | `hooks/hooks.json`, `plugin.json` | The plugin directory | Registered commands, skills, agents, and hook bindings | Client-side | [EV-0093], [EV-0129] |
| Invocation | `commands/*.md`, `skills/*/SKILL.md` | Operator input or a skill trigger | Markdown loaded into session context | Model-visible. A broken cross-reference degrades silently | [EV-0093], [EV-0005] |
| Deterministic work | `bin/*.sh` | Command arguments and repository state | `KEY=value` lines on stdout, exit codes 0/1/2 | Exit codes and `::error` style lines. The calling command interprets them | [EV-0093] |
| Interception | `hooks/scripts/*.sh` | The pending tool call | permit or block | Non-zero exit blocks the tool call | [EV-0129], [EV-0039] |
| Verification | `tests/run.sh` in flow and dossier | The tree | `TOTAL pass=<n> fail=<n>` | Non-zero exit, surfaced in CI, but advisory | [EV-0098], [EV-0107] |
| Release | `git tag` plus a published GitHub release | A version bump in two files | Tag, release, and desktop ZIPs | Workflow failure leaves a release without assets | [EV-0012], [EV-0032] |

### Trace

One concrete path, from an operator's keystroke to a decision, through the dossier plugin. It is the same path this documentation package was produced by. Each step below was re-read in the tree at `691bcdb`. Commit `7ee4923` changed only the marketplace description and two README lines [EV-0170], so no step moved. This is the package's only end-to-end trace, which AQ-0014 records as a gap against the three the modelling method asks for.

1. The operator types `/dossier:init`. The client loads `plugins/dossier/commands/init.md`. Its frontmatter declares `allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, AskUserQuestion`. That bounds what the command may do before a line of its body runs.

2. The command's Phase 0 `!` block resolves the plugin root, and cannot rely on `CLAUDE_PLUGIN_ROOT` being set. It tries the in-tree path `plugins/dossier` first. Then every versioned client cache directory under `$HOME/.claude/plugins/cache/synapti-marketplace/dossier/`, newest first, then the marketplace clone. Each candidate is tested for an executable `bin/dossier-resolve-config.sh`. If none matches, Phase 0 prints `DOSSIER_STATE=blocked` and stops.

3. It calls `bin/dossier-resolve-config.sh dossier.project.outputRoot`. That wraps `bin/cascade-resolve.sh`, which walks four settings files in precedence order: `.claude/settings.dossier.local.json`, `.claude/settings.dossier.json`, `$HOME/.claude/settings.dossier.json`, then the plugin's own `settings.json`. `DOSSIER_*` environment variables are applied by the wrapper, above all four.

4. The local layer carries a guard a teammate will otherwise trip over. `cascade-resolve.sh` checks `git ls-files --error-unmatch` on `.claude/settings.dossier.local.json`. If that file is tracked, the layer is dropped with a warning on stderr. The layer is admitted on the evidence that it is untracked. A committed one would let a pull request silently outrank `ci.writeAllowlist`, `disclosure.policy`, and `engagement.allowedActions`.

5. Absence at each layer is decided by `jq -e '(path) != null'`, not by shell emptiness. An explicit `""` or `false` at a higher layer is honoured rather than falling through.

6. The script emits `KEY=value` lines, and the command reads them from the transcript. This is the boundary between deterministic logic and model judgment: the script decides, the model orchestrates.

7. `bin/dossier-validate-config.sh` runs. Conditional and cross-field rules live in the script rather than in `schema.json`. The documented fallback validator ignores `if`/`then` when the `jsonschema` package is absent. A schema conditional would therefore report success and enforce nothing, on exactly the machines that lack the dependency.

8. `bin/dossier-scaffold.sh --output-root docs/dossier` copies the 23 canonical templates and writes a `README.md` signpost at the output root. It never overwrites, and an existing file is skipped rather than merged. The package holds hand-written evidence, and a scaffold that clobbers is one nobody dares re-run. The July run at `06b1586` emitted `SCAFFOLD_CREATED=23 SCAFFOLD_SKIPPED=0 SCAFFOLD_FAILED=0` [EV-0047]. The script now also emits `SCAFFOLD_README=created|skipped|failed`, which that recorded output predates.

9. `bin/dossier-package-check.sh` parses each file's YAML frontmatter with a shell path, so no Python dependency is needed. It checks the five properties below.

| Property checked | Failure it catches |
|---|---|
| All 23 canonical files exist | A dropped file, which reads the same as an incomplete run |
| Every header field is present and non-empty | An unfilled `{fill}`, which counts as empty |
| Every internal markdown link resolves | A cross-reference that went stale after a rename |
| The body line 2 contract pointer resolves to a real anchor | A document drafted against a contract section that does not exist |
| Each `last-verified` date is well formed | A date a staleness check cannot read |

A freshly scaffolded package therefore reports one finding per unfilled header field, which is correct at that stage.

The files a contributor touches on that path: one command file, one or two `bin/` scripts, and the tests that guard them. Nothing else.

## Extension points and common change paths

| Change a teammate commonly makes | Where to make it | What else must change | Tests to run | Evidence |
|---|---|---|---|---|
| Add a skill to a plugin | `plugins/<p>/skills/<name>/SKILL.md` | Any prose stating a skill count. Both the plugin README and the marketplace description have drifted this way before, and were corrected at `7ee4923` | `plugins/<p>/tests/run.sh` where one exists | [EV-0170] |
| Add a command | `plugins/<p>/commands/<name>.md` | `## Required Skills` must list every `Skill(X)` the body invokes, and each must resolve on disk | dossier and flow suites lint this for their own plugins | [EV-0005] |
| Add a `bin/` script | `plugins/<p>/bin/<name>.sh` | Executable bit, a `# Usage:` header, `set -u`, no bash 4 constructs | `bin-scripts.test.sh` in flow or dossier | [EV-0093], [EV-0107] |
| Add a hook | `plugins/<p>/hooks/hooks.json` plus a script | The hook runs on every operator's machine. This is the highest-consequence change in the repository | `hooks.test.sh`. There is no runtime test | [EV-0093], [EV-0129] |
| Add a plugin | `plugins/<name>/` plus a `marketplace.json` entry | Marketplace version; the README plugin table and badge; the category list. An external source needs a `sha` | `bash scripts/check-plugin-versions.sh`, which also runs in CI (TM-0033) | [EV-0080], [EV-0081] |
| Bump a plugin version | `plugin.json` **and** the `marketplace.json` entry | Both, always. Disagreement fails the `marketplace-manifest.yml` job | `bash scripts/check-plugin-versions.sh` | [EV-0080], [EV-0081], [EV-0127] |
| Move an external pin | The entry's `source.sha` in `.claude-plugin/marketplace.json` | Nothing else. The advertised `version` must match the new tree, or the check fails | `bash scripts/check-plugin-versions.sh` | [EV-0080], [EV-0127] |
| Cut a release | Tag plus a GitHub release | `marketplace.json` `metadata.version` | `release-desktop-skills.yml` fires automatically | [EV-0032] |

## Generated and vendored code

| Path | Kind | Generated or vendored from | Regeneration command | Edited by hand | Evidence |
|---|---|---|---|---|---|
| `plugins/dossier/bin/cascade-resolve.sh` | duplicated logic | the same-named resolver in `plugins/flow/bin/`. Derivation direction is not established by a diff and is not asserted | none. Each plugin maintains its own copy | **yes** — the two differ by 66 lines, 5.4K against 3.7K | [EV-0142] |
| `plugins/dossier/tests/lib/assert.sh`, `tests/run.sh` | duplicated logic | the same-named files in `plugins/flow/tests/` | none. Each plugin maintains its own copy | yes — dossier's identifiers are `_dossier_*` where flow's are `_flow_*` | read at `7ee4923`: `plugins/dossier/tests/lib/assert.sh` against `plugins/flow/tests/lib/assert.sh` |
| `plugins/agent-capability-standard/**` | neither generated nor vendored | not applicable. The path is untracked and ignored at `.gitignore` line 54, and the plugin ships as a `github` source pinned to sha `9e2f65b` | none. Moving the pin is a `marketplace.json` edit | not applicable — `git ls-files` returns 0 entries for the path | [EV-0058], [EV-0059], [EV-0060], [EV-0167] |
| `dist/desktop/**` | generated | every `SKILL.md`, by `scripts/package-desktop-skills.sh` | `bash scripts/package-desktop-skills.sh --clean` | no — untracked, built on release | [EV-0012] |

The first row is a real hazard of duplicated logic, and it has already materialized [EV-0142]. Read at `7ee4923`, dossier's copy differs from flow's in three behaviours. It decides absence with `jq -e`. It drops a git-tracked `.local.json` layer with a warning. It exits 2 when `mktemp` fails, where flow's copy uses a `/tmp` path instead.

Dossier's copy carries a header comment calling itself a byte-for-byte behavioural twin of flow's, which the three differences contradict (CT-0007). Neither file records that the other exists, so a reader of flow's copy cannot learn that the same defects were found and fixed next door.

## Configuration model

| Setting | Purpose | Sources in precedence order | Default | Validated where | Evidence |
|---|---|---|---|---|---|
| `dossier.project.outputRoot` | Where the documentation package is written | `DOSSIER_PROJECT_OUTPUT_ROOT` → `.claude/settings.dossier.local.json` → `.claude/settings.dossier.json` → `$HOME/.claude/settings.dossier.json` → plugin `settings.json` | `docs/dossier` | `schema.json` pattern plus `bin/dossier-validate-config.sh` | [EV-0048] |
| `dossier.engagement.allowedActions.*` | The action ceiling for a documentation run: read secrets, run builds, run tests, network, write outside the output root, contact humans | same cascade | every capability `false` except `readSource` | `schema.json`; enforced at runtime by `hooks/scripts/enforce-allowed-actions.sh` | [EV-0039] |
| `dossier.disclosure.policy` | Governs what may appear in `06-public/**` | same cascade | `internal-only` | `bin/dossier-validate-config.sh` rejects self-approval of public claims | [EV-0048] |
| `dossier.ci.*` | Post-merge automation: triggers, branch strategy, thresholds, write allowlist | same cascade | path-filtered, rolling branch, `docs/dossier/**` allowlist | `schema.json` plus the validator | [EV-0048] |
| `flow.*` | The flow plugin's own settings tree, including the merge gate's `markerTrust` | the equivalent flow cascade | see `plugins/flow/settings.json` | `plugins/flow/schema.json` | [EV-0098] |

The `.local.json` layer outranks every other layer, and it is honoured only while untracked. Committing it makes `cascade-resolve.sh` ignore it and warn, as step 4 of the trace describes.

No secret value appears in this table. As of 2026-07-26, no credential matching the repository's own detector pattern set appeared in tracked files outside detector definitions and their fixtures [EV-0037].

## Feature flags and rollout controls

| Flag | Controls | Default | Current state per environment | Owner | Removal condition | Evidence |
|---|---|---|---|---|---|---|
| `dossier.ci.enabled` | Whether the post-merge refresh runs at all | `true` in the plugin default | not installed here. The 5 tracked workflows include no dossier docs-refresh workflow. Never executed as of 2026-07-26 | Daniel Bentes | none stated | [EV-0123], [EV-0045] |
| `dossier.ci.instructionSource` | `plugin` reads skill text from marketplace `main`; `vendored` copies it into the consuming repository | `plugin` | not applicable here | Daniel Bentes | When `plugin_marketplaces` accepts a ref | [EV-0045] |
| `dossier.local.onLocalMerge` | Whether a local merge to the default branch suggests a documentation refresh | `suggest` | not exercised as of 2026-07-26. The hook that acts on it is `hooks/scripts/detect-local-merge.sh` | Daniel Bentes | none stated | [EV-0045], [EV-0166] |

There are no runtime feature flags, because there is no runtime [EV-0044]. Every row above is an install-time configuration default. Two of the three have no removal condition, which is recorded as debt in `04-operating/decisions-technical-debt-and-risks.md`.

## Build and artifact production

| Artifact | Produced by | Command | Inputs | Output location | Reproducible | Evidence |
|---|---|---|---|---|---|---|
| Installed plugin | The Claude Code client | `claude plugin install <name>` | The repository at the resolved ref | `~/.claude/plugins/cache/<marketplace>/<plugin>` | yes for in-tree plugins. Both external entries now pin a `sha`, so two installs at one manifest version resolve the same trees | [EV-0058], [EV-0127] |
| Desktop skill ZIPs | `scripts/package-desktop-skills.sh` | `bash scripts/package-desktop-skills.sh --clean` | Every `SKILL.md` in the tree | `dist/desktop/**` — untracked | unknown — never verified byte-for-byte across two runs (AQ-0021) | [EV-0012] |
| GitHub release | Manual tag plus release | `gh release create` | The tag | GitHub Releases | yes | [EV-0032] |

There is no build step for the plugins themselves. What is committed is what installs [EV-0044].

The client install state on the assessment machine dates from 2026-07-26 and was not re-checked since. The marketplace resolved from GitHub with `autoUpdate: true`, and 6 plugins were installed [EV-0051].

## Legacy, deprecated, experimental, and orphaned areas

| Area | Classification | Still executed | Safe to remove | What blocks removal | Evidence |
|---|---|---|---|---|---|
| `plugins/gh-workflow` | legacy | yes, if an operator enables it | no | It is published and installed, and carries no deprecation notice. `.claude/CLAUDE.md` says to enable only one of gh-workflow and flow, which is guidance, not a mechanism | [EV-0162] |
| `.claude/commands/gh-*.md` | legacy | yes, in this repository's own sessions | unknown | The repository's own `CLAUDE.md` documents both the `/gh-*` and `/flow:*` command sets as current | `.claude/CLAUDE.md` |
| `plugins/flow/skills/learned/` | experimental | no — it is empty | no | It is a reserved location for learned skills. Removing it would remove the convention | [EV-0029] |
| `plugins/agent-capability-standard/` on a maintainer machine | orphaned working-tree residue | no | yes | Nothing. It is untracked and ignored, and deleting it removes a source of inflated `find` counts | [EV-0060] |
| `dist/desktop/` | generated | on release only | yes, at any time | Nothing — it is untracked | [EV-0012] |
| Root-level drafts: `flow_plugin_medium_article_grounded.md`, `Provably_correct_code_with_Flow_AI_agents_eng.txt` | orphaned | no | unknown | Untracked working-tree files, not repository content. Both still present at `7ee4923` | working tree at `7ee4923` |

## Code ownership and bus factor

| Area | Owner | Contributors in inspected history | Bus factor | Consequence | Evidence |
|---|---|---|---|---|---|
| Every path in this repository | Daniel Bentes | 1 | 1 | No component has a second person who has ever changed it | [EV-0035] |
| `plugins/flow` | Daniel Bentes | 1 | 1 | The largest plugin, 2336 assertions on macOS, one reader | [EV-0098], [EV-0035] |
| `plugins/dossier` | Daniel Bentes | 1 | 1 | 1951 assertions on macOS, one reader | [EV-0107], [EV-0035] |
| `.github/workflows` | Daniel Bentes | 1 | 1 | A workflow change lands with no second opinion. No required check existed as of 2026-07-26 | [EV-0016], [EV-0035] |

Both assertion totals were executed on macOS with `/bin/bash` 3.2.57 [EV-0098], [EV-0107]. Neither speaks for Linux CI.

The inspected history window dates from 2026-07-26 and was not re-measured since. It covers the full repository history across all refs: 370 commits, first 2025-12-19, most recent 2026-07-26 [EV-0035]. Contributor counts describe that window, not who understands the code today. With a single identity across the whole window, the two coincide.

## Where to make this change

| Task | Start here | Then | Verify with | Evidence |
|---|---|---|---|---|
| Fix a stale README fact | `README.md` | Cross-check every version cell against `marketplace.json`, and the badge count against `.plugins \| length`. All eight advertised versions match at `7ee4923`; the badge read 6 against 8 entries as of 2026-07-26 | `jq` comparison. The version check reads manifests, not prose, so README drift passes it | [EV-0170], [EV-0022], [EV-0080] |
| Make CI blocking | GitHub repository settings, not a file | Enable branch protection on `main` requiring the test workflows and `marketplace-manifest`. None existed as of 2026-07-26 | `gh api repos/.../branches/main/protection` returns 200 | [EV-0016], [EV-0123] |
| Fix a flow behaviour | The relevant `plugins/flow/skills/*/SKILL.md` or `bin/*.sh` | Update or add the matching assertion in `plugins/flow/tests/` | `plugins/flow/tests/run.sh` | [EV-0098] |
| Fix a dossier behaviour | `plugins/dossier/{skills,commands,bin}/…` | Add a regression assertion. The suite's convention is one test per defect | `plugins/dossier/tests/run.sh` | [EV-0107] |
| Port a cascade fix between plugins | The `cascade-resolve.sh` copy that has the fix | Apply the same change to the other copy, then diff the two | Both `tests/run.sh` suites | [EV-0142] |
| Change what an external entry ships | The entry's `source.sha` and `version` in `.claude-plugin/marketplace.json` | Confirm the pinned tree reports that version | `bash scripts/check-plugin-versions.sh` | [EV-0080], [EV-0127] |
| Add Windows support | Both test workflows | A `windows-latest` matrix leg, then fix what it surfaces | The new CI leg, and the two portability issues open as of 2026-07-26 | [EV-0049] |
