---
dossier-header: internal-v1
title: Data and AI
purpose: Lets a reader establish what data the marketplace holds and what AI behaviour it induces in an operator's session, before they install it.
audience: Reviewer, Installing operator, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d0fa737
last-verified: 2026-07-26
review-trigger: A plugin begins storing data, invoking a model directly, or shipping an evaluation suite
related: [02-architecture/system-architecture.md, 03-assurance/security-privacy-and-compliance.md, 00-control/evidence-ledger.md]
---
# Data and AI
<!-- contract: references/package-contract-02-architecture.md#data-and-ai -->

Two facts frame this document, and both are unusual enough to state before any table.

**The marketplace holds no data.** It has no store, no schema, no migration, no backup, and no retention policy, because it has no runtime [EV-0044]. Sections that would describe those things are `N/A` with the reason, not omitted.

**It is nonetheless an AI system, of an unusual kind.** Its entire product is 112 skill files, 61 command files, and 29 agent definitions [EV-0004], [EV-0005], [EV-0006] — prompts that a model reads and acts on. The project invokes no model itself and pays for no inference. It ships *instructions* that change how someone else's model behaves inside someone else's session. The AI risk section below is written against that shape, and it is the section a reviewer should read.

## Data model

| Entity | Definition | Owning component | Store | Key | Relationships | Evidence |
|---|---|---|---|---|---|---|
| Plugin entry | One installable unit advertised in the manifest | `marketplace.json` | git | `name` | Points to exactly one source: a repository path, a submodule, or an external subdirectory | [EV-0001], [EV-0003] |
| Plugin manifest | A plugin's own identity record | `plugins/*/.claude-plugin/plugin.json` | git | `name` | Must agree with its marketplace entry's `version` | [EV-0026] |
| Skill | One `SKILL.md`: frontmatter plus body | the plugin | git | directory name | Belongs to one plugin; referenced by commands and agents | [EV-0004] |
| Command | One Markdown file invoked as `/plugin:name` | the plugin | git | filename | Declares the skills it invokes | [EV-0005] |
| Agent definition | A subagent's system prompt, tool list, and skill list | the plugin | git | filename | Names the skills it may load | [EV-0006] |
| Hook registration | An event-to-script binding | `hooks/hooks.json` | git | event kind plus matcher | Points to a script under `hooks/scripts/` | [EV-0040] |

Every entity above is a file in git. There is no database, no serialization format beyond JSON and YAML frontmatter, and no identifier that outlives a commit.

## Stores

| Store | Technology | Data held | Owner | Residency | Classification | Retention | Lifecycle | Evidence |
|---|---|---|---|---|---|---|---|---|
| This git repository | git / GitHub | All plugin content and history | Daniel Bentes | GitHub, public | Public | indefinite | Append-only history; `main` is unprotected | [EV-0016], [EV-0044] |
| GitHub Releases | GitHub | 57 tags and their desktop-skill ZIP assets | Daniel Bentes | GitHub, public | Public | indefinite | Assets overwritten by `--clobber` on re-upload | [EV-0032] |
| Operator's plugin cache | Local filesystem | A copy of installed plugins | The operator | The operator's machine | Public content | Until uninstalled; refreshed by `autoUpdate` | Not controlled by this project | [EV-0051], [EV-0052] |

**No store owned by this project holds personal data, credentials, customer data, or telemetry.** There is nowhere for such data to be held.

## Sources, sinks, and lineage

| Flow | Source | Transformation | Sink | Trigger | Synchronization | Evidence |
|---|---|---|---|---|---|---|
| Publish | Maintainer's working tree | none | `main` | `git push` | Immediate; ungated | [EV-0016] |
| Distribute | `main` | none | Operator's plugin cache | `plugin install`, or `autoUpdate` re-sync | Eventually consistent, client-scheduled | [EV-0051] |
| Desktop packaging | Every `SKILL.md` | Claude Code-specific frontmatter stripped; reference files bundled; ZIP created | GitHub release assets | Release published | One-shot per release | [EV-0012] |
| Submodule sync | `synaptiai/agent-capability-standard` | none | The submodule pointer in this repository | Manual `git submodule update` | Currently 2 commits past `v1.2.0` | [EV-0031] |
| External subdir sync | `synaptiai/prompt-decorators` at `main` | none | Operator's plugin cache, directly | Every install | **Unsynchronized** — this repository never observes what is fetched | [EV-0030] |

The last row is the only lineage gap in the system: content reaches an operator under this marketplace's name without ever passing through this repository, and nothing here records which commit they received.

## Consistency, caching, indexing, and search

| Mechanism | Applies to | Behaviour | Staleness window | Invalidation | Evidence |
|---|---|---|---|---|---|
| Client marketplace clone | The whole manifest | The client keeps a local clone and re-syncs it | Client-determined; `autoUpdate: true` on the observed profile | Client-internal | [EV-0051] |
| Client plugin cache | Installed plugins | A materialized copy per installed plugin | Until the client re-syncs | Reinstall | [EV-0052] |
| Floating `main` ref | `prompt-decorators` only | Resolves to whatever upstream `main` is at install time | Unbounded | None — there is no version to invalidate against | [EV-0030] |

There is no index and no search. There is no cache this project controls.

| Transactional boundary | Spans | What is not atomic across it | Compensation | Evidence |
|---|---|---|---|---|
| A single git commit | Every file changed together | Nothing within one commit | N/A | [EV-0034] |
| A version bump | `plugin.json` **and** the matching `marketplace.json` entry | These are two files. Nothing enforces that both change together; the pair was verified by hand during this assessment | Manual correction after discovery | [EV-0026] |
| A release | Tag, GitHub release, and `marketplace.json` `metadata.version` | Three separate acts. Version 4.7.0 currently exists in the manifest with no corresponding tag | Publish the tag, or revert the manifest | [EV-0033] |

The version-bump row is the only real atomicity hazard in the project, and it is a documented convention rather than a mechanism.

## Migrations, backup, restore, archival, deletion, and retention

| Operation | Procedure | Frequency | Last executed | Verified how | Reversible | Evidence |
|---|---|---|---|---|---|---|
| Migration | N/A — no schema and no persisted data exist to migrate | — | — | — | — | [EV-0044] |
| Backup | N/A for the project. The repository is hosted on GitHub and cloned by every installer, which is redundancy without being a backup policy | — | — | — | — | [EV-0044] |
| Restore | `git revert` or `git reset` on a branch | as needed | not measured | Working-tree comparison | yes | [EV-0034] |
| Archival | N/A | — | — | — | — | [EV-0044] |
| Deletion | N/A — there is no personal or customer data to delete, and no deletion request can arise | — | — | — | — | [EV-0044] |

No backup or restore test has ever been performed, and none is meaningful: the recovery procedure for this project is `git clone`.

## Analytics and reporting

| Pipeline | Source | Destination | Schedule | Owner | Data classification | Evidence |
|---|---|---|---|---|---|---|
| N/A | — | — | — | — | — | No analytics pipeline exists. The project collects no usage data, and GitHub exposes no install telemetry for plugin marketplaces (AQ-0004) [EV-0044] |

The consequence is worth naming rather than leaving implicit: **there is no measurement of whether any plugin is used, by whom, or whether any of them work in practice.** Every quality signal in this package is a property of the artifacts, not of their use.

## Sensitive and regulated data

| Data class | Examples (categories, never values) | Where stored | Where transits | Legal basis | Controls | Evidence |
|---|---|---|---|---|---|---|
| none held by the project | — | — | — | — | — | [EV-0044], [EV-0037] |
| Credential *patterns* (not values) | Regular expressions matching API key and private-key formats | `plugins/flow/hooks/scripts/block-secrets.sh`, `plugins/dossier/bin/dossier-validate-patch.sh`, and their test fixtures | never | N/A | These are detectors. `dossier-claim-scan.sh` redacts any matched value before reporting it, so a scan cannot leak what it finds | [EV-0037], [EV-0039] |
| Operator data reachable at runtime | Anything on the operator's machine that a hook could read | not stored by this project | not transmitted by this project | N/A | **None enforced by this project.** Hooks run with the operator's privileges; the control is that every script is readable plain text before install | [EV-0040], [EV-0007] |

The third row is the honest answer to "does this handle sensitive data". The project holds none, and simultaneously ships code that could reach any of it on an operator's machine. Both are true and the second is the one that matters.

## Data quality

| Control | What it checks | Where it runs | On failure | Coverage gap | Evidence |
|---|---|---|---|---|---|
| flow test suite | 1022 assertions over the flow tree's structure and script behaviour | Locally and in `flow-tests.yml` | Non-zero exit; **advisory, since no check is required for merge** | Covers only flow | [EV-0008], [EV-0016] |
| dossier test suite | 1034 assertions, including frontmatter shape, cross-reference resolution, and script portability | Locally and in `dossier-tests.yml` | Non-zero exit; advisory | Covers only dossier | [EV-0009] |
| CodeQL | Static analysis over `actions` and `python` | `codeql.yml` on push, pull request, and schedule | Alerts | Does not analyse shell, which is the language of all 26 `bin/` scripts and all 16 hook scripts | [EV-0012], [EV-0007] |
| Manifest validation | — | nowhere | — | **Total gap.** Nothing validates that `marketplace.json` parses, that every `source` resolves, or that versions agree | [EV-0026] |
| README accuracy | — | nowhere | — | **Total gap.** Four verified-stale facts are live today | [EV-0022], [EV-0023], [EV-0024], [EV-0025] |

The two total gaps are the highest-value data-quality work available, and both are small: one workflow step each.

## AI architecture

| Element | Description | Version | Owner | Evidence |
|---|---|---|---|---|
| Models | **None invoked by this project.** The plugins run inside a Claude Code session whose model the operator chose and pays for. One documented exception is opt-in and lives outside this repository: the `prompt-decorators` auto-selector, described by its marketplace entry as using a small model to pick decorators | N/A | Anthropic, not this project | [EV-0044], [EV-0030] |
| Agents | 29 agent definitions across 6 plugins. Each is a system prompt plus a tool allowlist and a skill allowlist, dispatched into a separate context | per plugin | Daniel Bentes | [EV-0006] |
| Prompts | 112 skills and 61 commands. This is the product | per plugin | Daniel Bentes | [EV-0004], [EV-0005] |
| Tools | Declared per skill via `allowed-tools` and per agent via `tools:`. The plugins define no tools of their own; they constrain which of the client's tools each artifact may use | per plugin | Daniel Bentes | [EV-0004] |
| Retrieval | None. Skills reference `references/*.md` files by path, read by the model as ordinary files. There is no embedding, no vector store, and no retrieval ranking | N/A | — | [EV-0004] |
| Memory | The flow plugin writes durable state to `.flow/` and `.decisions/` in the consuming repository; dossier's verification agents are declared `memory: none` so that independent passes cannot converge | per plugin | Daniel Bentes | [EV-0046], [EV-0009] |
| Evaluation | **No behavioural evaluation exists for any plugin.** The 2,056 assertions test structure and script behaviour, not whether a skill produces good output when a model reads it | — | — | [EV-0008], [EV-0009] |

The evaluation row is the most important line in this document. This is a prompt-engineering product with a large structural test suite and **no measurement of prompt efficacy at all**. A skill can pass every assertion, load correctly, and still make a model behave worse than it would have unaided; nothing here would detect that.

## Model and dataset provenance

| Asset | Origin | License or terms | Permitted uses | Restrictions | Evidence |
|---|---|---|---|---|---|
| Skills, commands, agents (in-tree) | Written for this repository | Declared MIT in 6 plugin manifests — **but no `LICENSE` file exists and GitHub detects no licence**, so the effective grant is unclear (CT-0001) | Unclear pending CT-0001 | Unclear pending CT-0001 | [EV-0018], [EV-0019], [EV-0021] |
| `agent-capability-standard` | `synaptiai/agent-capability-standard` | Apache-2.0, declared in both `plugin.json` and `pyproject.toml` | Per Apache-2.0 | Per Apache-2.0 | [EV-0021], [EV-0041] |
| `prompt-decorators` | `synaptiai/prompt-decorators` | Apache-2.0 per its marketplace entry | Per Apache-2.0 | Not verified from here (AQ-0005) | [EV-0030] |
| Training data | **None.** No model is trained, fine-tuned, or distilled by this project | N/A | N/A | N/A | [EV-0044] |
| Datasets | None | N/A | N/A | N/A | [EV-0044] |

## Lifecycle: training through rollback

| Stage | Process | Trigger | Owner | Artifacts retained | Evidence |
|---|---|---|---|---|---|
| Training | N/A — no model is trained | — | — | — | [EV-0044] |
| Fine-tuning | N/A | — | — | — | [EV-0044] |
| Inference | Performed by the operator's Claude Code session, on the operator's account, with the model the operator selected | Operator action | The operator | Whatever the operator's client retains | [EV-0044] |
| Evaluation | **None exists.** No prompt, skill, or agent has a behavioural evaluation | — | — | — | [EV-0008], [EV-0009] |
| Monitoring | None. No telemetry is emitted or collected | — | — | — | [EV-0044] |
| Feedback | GitHub issues only. 2 are open, both about shell portability | Operator files an issue | Daniel Bentes | The issue thread | [EV-0049] |
| Rollback | `git revert` plus a push. Installers pick it up on their next `autoUpdate` sync — **the propagation delay is client-controlled and unknown to this project** | Maintainer decision | Daniel Bentes | git history | [EV-0051] |

## AI risk controls

| Risk | Exposure in this system | Control | Implemented / policy-only / planned / unknown | Tested | Evidence |
|---|---|---|---|---|---|
| Prompt injection | Real and specific. Skills instruct a model that then reads untrusted content — issue bodies, pull-request titles, diffs, third-party files. The dossier CI template is the sharpest case: it passes a *static* prompt carrying a path, never content, and marks untrusted values in an explicit `untrusted: []` array in the evidence manifest | Static prompts; untrusted data passed as data with explicit marking; a tool allowlist and denylist per invocation; the agent job holds no write token | implemented for dossier's CI path; **unknown for the other 7 plugins**, none of which state an injection posture | Structurally, in the dossier suite. **Never behaviourally** | [EV-0009], [EV-0045] |
| Data leakage through model or logs | An operator's session reads their own repository; a skill could instruct the model to copy sensitive content into an output file or a public document | flow's `block-secrets.sh` blocks writes matching credential patterns; dossier's `dossier-claim-scan.sh` redacts matched values before reporting and gates `06-public/**` behind an approved claim register | implemented in 2 of 8 plugins | Structurally | [EV-0038], [EV-0039] |
| Unsafe or harmful output | Low intrinsic exposure — the plugins produce documentation, commits, and reviews, not user-facing content. `decipon` analyses manipulation and disinformation, so its outputs are judgments about content | None specific to the plugins | none | no | [EV-0004] |
| Excessive autonomy | The central risk of a workflow harness. flow can commit, push, open pull requests, and merge; dossier can write files and open documentation pull requests | Tiered actions — Tier 1 autonomous, Tier 2 journalled, Tier 3 requires explicit confirmation. Merge and release are Tier 3 in flow. `PreToolUse` hooks block destructive commands and force-pushes. dossier's `enforce-allowed-actions.sh` enforces a configured action ceiling whose defaults are all `false` except reading source | implemented in flow and dossier | Structurally, in both suites | [EV-0038], [EV-0039], [EV-0008], [EV-0009] |
| Model drift | The operator's model changes under the plugins without notice — a new model version can read the same skill and behave differently | **None.** There is no evaluation suite to detect it, and no pinned model anywhere | none | no | [EV-0008], [EV-0009] |
| Human oversight | Every plugin runs interactively in a human's session by default. The exception is dossier's post-merge CI path, which runs headless | Tier 3 confirmations; the CI design splits privilege across three jobs so the agent job never holds a write token, and every patch is validated against a path allowlist twice | implemented in design; **the CI path has never executed end to end** (AQ-0002) | Structurally only | [EV-0045], [EV-0009] |

Two rows carry the weight. **Model drift is entirely uncontrolled**, and for a product made of prompts that is the sharpest architectural risk in the project: the artifact is stable while its interpreter changes underneath it. And the excessive-autonomy controls, which are genuinely well-designed, are verified structurally rather than behaviourally — the tests prove the hook is registered and the script is portable, not that it blocks the right thing when a live model tries.

## Model limitations, cost, latency, and vendor dependency

| Aspect | Current state | Measured or estimated | Fallback | Evidence |
|---|---|---|---|---|
| Known limitations | Skills consume context in the operator's session. 112 skills exist, loaded on demand rather than eagerly, but a heavily-loaded session pays for what it triggers | estimated — never measured | Operator installs fewer plugins | [EV-0004] |
| Cost per unit of work | Borne entirely by the operator; the project pays nothing and observes nothing. The one exception is dossier's CI path, where a refresh run's cost lands on the consuming repository's API key with a per-run turn cap but no spend cap | not measured — never executed (AQ-0002) | The plugin's own documentation points at the Anthropic console budget rather than claiming a guarantee | [EV-0045] |
| Latency | `PreToolUse` hooks block the operator's tool call while they run. All 16 are shell scripts doing local inspection | not measured | none | [EV-0040] |
| Vendor dependency | Total on Anthropic. The plugins are meaningless without Claude Code, whose manifest schema, resolution order, cache layout, and hook contract are all external and can change without notice | not measured | none, and none is possible | [EV-0043] |

## Reproducibility and versioning

| Artifact | Versioning scheme | Pinned where | Reproducible from | Evidence |
|---|---|---|---|---|
| In-tree plugin | semver in `plugin.json`, mirrored in `marketplace.json` | Both files, agreeing today by hand-checked convention | The repository commit | [EV-0026] |
| Marketplace | semver in `metadata.version`, plus a git tag | Currently 4.7.0 in the manifest with **no matching tag** | The commit | [EV-0033] |
| `agent-capability-standard` | Advertised as 1.2.0; the submodule points at `95f7ac2`, which is 2 commits past tag `v1.2.0` | `.gitmodules` plus the pointer | The pinned commit — reproducible, but **not the version advertised** | [EV-0031] |
| `prompt-decorators` | Advertised as 0.1.1; the source pins `ref: main` | Nothing | **Not reproducible.** Two installs on different days may differ | [EV-0030] |
| Desktop skill ZIPs | Attached per release tag | The release | `bash scripts/package-desktop-skills.sh --clean` | [EV-0012] |
| Session behaviour | Not versioned. The model the plugins instruct is chosen by the operator and changes over time | nowhere | not reproducible | [EV-0044] |

Three of the six rows are not reproducible, and the reasons differ: one is an unpublished version, one is a pointer that drifted past its label, and one is a floating ref by design. Only the last is a deliberate choice, and it is the one an installer is least able to detect.
