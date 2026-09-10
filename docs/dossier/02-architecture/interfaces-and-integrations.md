---
dossier-header: internal-v1
title: Interfaces and Integrations
purpose: Lets an integrator or plugin author work against this project's contracts without reading its source, and see which of them are stable.
audience: Contributor, Installing operator, Reviewer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A command, hook event, settings key, or manifest field is added, renamed, or removed
related: [02-architecture/system-architecture.md, 02-architecture/components-and-codebase.md, 06-public/technical-partner-guide.md, 00-control/claim-and-disclosure-register.md]
---
# Interfaces and Integrations
<!-- contract: references/package-contract-02-architecture.md#interfaces-and-integrations -->

This project exposes no network API. Its interfaces are the manifest it publishes and the commands and hook bindings the Claude Code client reads. They also include the settings files it consumes from a project, and the files it writes into a consuming repository. It now also consumes one outbound integration. The marketplace manifest check reads each external entry's own manifest through the GitHub API, at that entry's pinned sha [EV-0080], [EV-0081]. Each interface is a contract with someone, and each is listed here on those terms.

Rows dated 2026-07-26 in this document were carried forward from the July baseline and were not re-checked on 2026-09-10. Where a row was re-checked, its evidence carries the later observation.

## Interface inventory

| Interface | Kind | Producer | Consumers | Owner | Transport | Authentication | Authorization | Schema | Version | Lifecycle | Disclosure | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `marketplace.json` | Discovery manifest | this repository | Claude Code client | Daniel Bentes | git over HTTPS | public read | none | Client-defined. Version agreement and external-source `sha` presence are checked by the marketplace manifest check, TM-0033 [EV-0080], [EV-0081]. Whether the file parses and every source resolves is checked nowhere (AQ-0020) | `metadata.version` 4.10.0, observed at `15bcb24` [EV-0057]; 8 entries at d3fc744 [EV-0181] | stable | public | [EV-0057], [EV-0181], [EV-0080] |
| `plugin.json` | Plugin identity | each of the 6 in-tree plugins | Claude Code client | Daniel Bentes | filesystem | none | none | Client-defined | per plugin; every in-tree version matches its marketplace entry [EV-0064] | stable | public | [EV-0058], [EV-0064] |
| `/flow:*` | Slash commands | flow | operators | Daniel Bentes | session | none | Tier 1/2/3 gating inside the command bodies | Markdown frontmatter | 3.3.0 [EV-0179] | stable | public | [EV-0179], [EV-0129] |
| `/dossier:*` | Slash commands | dossier | operators | Daniel Bentes | session | none | Tier gating plus an action ceiling [EV-0077] | Markdown frontmatter | 1.2.0 [EV-0065] | published — the entry is on `main` [EV-0181] and releases v4.9.0 and v4.10.0 exist [EV-0066] | public | [EV-0065], [EV-0181], [EV-0066] |
| `/gh-*` | Slash commands | gh-workflow | operators | Daniel Bentes | session | none | none stated, as observed 2026-07-26 | Markdown frontmatter | 1.9.0 | legacy — superseded by flow, not deprecated in writing | public | [EV-0004] |
| Hook bindings, in-tree | Lifecycle interception | flow (14 scripts), dossier (5 scripts) | Claude Code client | Daniel Bentes | process execution on the operator's machine | none | **none — hooks inherit the operator's privileges** | `hooks.json`, client-defined | flow 3.3.0, dossier 1.2.0 | stable | public | [EV-0129], [EV-0162] |
| Hook bindings, external | Lifecycle interception from a repository this one does not control | the `agent-capability-standard` tree at pinned sha `9e2f65b` | Claude Code client | Daniel Bentes owns the pin; the upstream tree is not this project's | process execution on the operator's machine | none | **none — hooks inherit the operator's privileges** | `hooks.json`, `pretooluse_require_checkpoint.sh`, `posttooluse_log_tool.sh` | the pinned sha | pinned; moves only when the pin moves | public | [EV-0168], [EV-0058] |
| `agent-capability-standard` source resolution | External plugin fetch | `synaptiai/agent-capability-standard` | Claude Code client | Daniel Bentes owns the pin | git over HTTPS, resolved client-side | public read | none | `github` source pinned to sha `9e2f65b`; no `.gitmodules` exists and the local path is gitignored [EV-0059], [EV-0060] | advertised 1.2.0; 42 skills at the pin [EV-0183] | changed in this range — was a git submodule whose gitlink resolved to 0 entries in a plain clone [EV-0167] | public | [EV-0058], [EV-0059], [EV-0060], [EV-0167], [EV-0183] |
| Marketplace manifest check (TM-0033) | Outbound CI integration | `.github/workflows/marketplace-manifest.yml` | GitHub REST API | Daniel Bentes | HTTPS from an Actions runner, via `gh api` | the runner's GitHub token | `permissions: contents: read` | Each external entry's own manifest, read at that entry's pinned sha | tracks the manifest | new in this range | public | [EV-0080], [EV-0081], [EV-0127] |
| `.claude/settings.dossier.json` | Consumed configuration | the consuming project | dossier | the consuming project | filesystem | none | none | `plugins/dossier/schema.json`, Draft-07 | 1.2.0 [EV-0065] | stable; this repository's own copy pinned `expectedPluginVersion` at 1.0.0 against a plugin at 1.2.0 until commit `d5a5166` corrected it [EV-0139] | public | [EV-0086], [EV-0139] |
| flow settings | Consumed configuration | the consuming project | flow | the consuming project | filesystem | none | none | `plugins/flow/schema.json` | 3.3.0 [EV-0179] | stable | public | [EV-0179] |
| `docs/dossier/**` | Produced artifact | dossier | humans, and dossier's own refresh | the consuming project | filesystem | none | Write confined by `enforce-output-root.sh` | 23-file package contract | 1.2.0 [EV-0065] | stable | public | [EV-0047], [EV-0065] |
| `.flow/`, `.decisions/` | Produced artifact | flow | humans, and flow's own commands | the consuming project | filesystem | none | none | flow's own conventions. `.flow/` holds `goals/` with paired `*.goal.yaml` and `.lock` files, and `runs/` named `<ISO8601>-<workflow>` [EV-0137]. `.decisions/` holds 21 tracked records [EV-0169] | 3.3.0 | stable | public | [EV-0137], [EV-0169] |
| `templates/ci/dossier-docs-refresh.yml` | Emitted CI workflow | dossier | the consuming repository's GitHub Actions | the consuming project after scaffolding | file, rendered at setup | GitHub OIDC at run time | Jobs split by privilege; a separate `scan` job installs osv-scanner and pyscn, distinct from the `policy` job [EV-0075] | GitHub Actions schema | 1.2.0 | **never executed** (AQ-0002); no such workflow is installed in this repository [EV-0084] | public | [EV-0075], [EV-0084], [EV-0045] |
| Desktop skill ZIPs | Release artifact | `package-desktop-skills.sh` | Claude Desktop | Daniel Bentes | GitHub release download | public | none | Desktop's skill package layout; `release-desktop-skills.yml` uploads `dist/desktop/**/*.zip` with `--clobber` and records no producing commit [EV-0133] | per release | stable | public | [EV-0133] |

Two facts qualify the release artifact. `Unknown:` whether two runs of `package-desktop-skills.sh` over the same tree produce byte-identical archives (AQ-0021). The workflow also records no producing commit, so an asset cannot be traced to a tree from the asset alone [EV-0133]. Both currently published releases carry the flow runtime defects that commit `16b4dc4` fixed: v4.9.0 and v4.10.0 were published before that commit merged [EV-0144].

## Machine-readable contracts

| Contract | Format | Location | Generated from | Generation command | Versioned how | Validated where | Drift check | Evidence |
|---|---|---|---|---|---|---|---|---|
| dossier settings schema | JSON Schema Draft-07 | `plugins/dossier/schema.json` | hand-written | — | With the plugin | `bin/dossier-validate-config.sh`, plus `jsonschema` when available | `config-schema.test.sh` asserts the schema and `settings.json` agree, and that `config.example.json` validates | [EV-0086], [EV-0107] |
| flow settings schema | JSON Schema | `plugins/flow/schema.json` | hand-written | — | With the plugin | flow's validator | flow's suite, 2336 assertions passing | [EV-0098] |
| Package contract | Markdown references, one per output directory | `plugins/dossier/references/package-contract-0*.md` | hand-written against the templates | — | With the plugin | `bin/dossier-package-check.sh` resolves every contract pointer to a real anchor | `package-contract.test.sh` asserts a bijection between the 23 templates and the 8 contract documents | [EV-0107] |
| `marketplace.json` | JSON | `.claude-plugin/marketplace.json` | hand-written | — | `metadata.version` | `scripts/check-plugin-versions.sh` in `marketplace-manifest.yml`, on manifest changes, weekly at 06:00 UTC Monday, and on manual dispatch [EV-0080], [EV-0081] | Version agreement per entry, and a required `sha` on every external source. 8 plugins checked, 0 failed, 0 unverifiable [EV-0127] | [EV-0080], [EV-0081], [EV-0127] |
| `plugin.json` (×6) | JSON | `plugins/*/.claude-plugin/plugin.json` | hand-written | — | semver | flow and dossier validate their own; the manifest check compares all 6 against their entries | Every in-tree entry matched its source at `15bcb24` [EV-0064] | [EV-0058], [EV-0064], [EV-0080] |

The gap this table recorded in July is closed for one failure mode and open for another. Version drift between a marketplace entry and its source is now caught in continuous integration [EV-0080], [EV-0081], [EV-0127]. `Unknown:` whether a malformed manifest would be caught before publication (AQ-0020). Nothing asserts that the file parses, or that every source resolves. The manifest is the highest-blast-radius file here, because one malformed copy breaks discovery for all eight entries at once.

## Examples

Adding the marketplace and installing a plugin — the whole integration surface for an operator:

```
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install flow
```

The client then records the marketplace and its resolved source. On the assessment machine, as observed 2026-07-26, `~/.claude/plugins/known_marketplaces.json` held [EV-0051]:

```json
{
  "source": { "source": "github", "repo": "synaptiai/synapti-marketplace" },
  "installLocation": "<client plugin dir>/marketplaces/synapti-marketplace",
  "lastUpdated": "2026-07-20T18:48:38.579Z",
  "autoUpdate": true
}
```

A marketplace entry, showing all three source kinds side by side [EV-0058]:

```json
{ "name": "flow", "source": "./plugins/flow", "version": "3.3.0", "category": "workflow" }
```

```json
{ "name": "agent-capability-standard",
  "source": { "source": "github",
              "repo": "synaptiai/agent-capability-standard",
              "ref": "main",
              "sha": "9e2f65b087cd3d92ca01a4073a7da26489dca50c" },
  "version": "1.2.0" }
```

```json
{ "name": "prompt-decorators",
  "source": { "source": "git-subdir",
              "url": "https://github.com/synaptiai/prompt-decorators.git",
              "path": "claude-code-plugin",
              "ref": "main",
              "sha": "9c792feb7e6db8feb42d26c98728dc6a29420e41" },
  "version": "0.1.1" }
```

Both external forms now carry a `sha` beside the `ref` [EV-0058]. In July the `prompt-decorators` entry pinned only `ref: main` [EV-0030], so two installs on different days need not have resolved the same tree. The `sha` field is what makes them reproducible, and the manifest check refuses an external source that omits it [EV-0080].

A `bin/` script's calling convention — the boundary between deterministic logic and model judgment:

```
$ plugins/dossier/bin/dossier-validate-config.sh --config .claude/settings.dossier.json
CONFIG_SOURCE=.claude/settings.dossier.json
CONFIG_DELIVERY_MODE=full
CONFIG_OUTPUT_ROOT=docs/dossier
CONFIG_SCHEMA_VALIDATION=pass
CONFIG_FINDINGS=0
CONFIG_VALID=true
```

That output was re-observed at HEAD: `CONFIG_SCHEMA_VALIDATION=pass`, `CONFIG_FINDINGS=0`, `CONFIG_VALID=true` [EV-0086]. Every helper script emits `KEY=value` lines on stdout and signals outcome by exit code. Nothing returns prose for a model to parse loosely.

## Behaviour contract

| Interface | Error model | Retry guidance | Idempotency | Ordering | Rate limits | Timeouts | Pagination | Compatibility policy | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| `bin/*.sh` | Exit `0` success, `1` findings, `2` usage or infrastructure error; `3` inconclusive for `dossier-gate.sh` | Safe to re-run — all are read-only or idempotent writes | yes | N/A | none | none | N/A | Undeclared. Scripts are internal to their plugin, though nothing prevents external use | [EV-0175], [EV-0107] |
| Slash commands | Reported in-session as prose plus `KEY=value` blocks; blocked states report a reason rather than failing silently | Operator re-invokes | Depends on the command; `init` and `scaffold` never overwrite | Operator-driven | none | none | N/A | Undeclared | [EV-0005] |
| Hooks | The client refused three Bash tool calls during this refresh after a `PreToolUse` hook exited non-zero [EV-0172]. `Unknown:` what delivery, ordering and blocking semantics the client applies in general (AQ-0025) | not retried | yes | `Unknown:` client-determined, and no evidence establishes the order (AQ-0025) | none | none — a slow hook blocks the operator | N/A | Client-defined | [EV-0172], [EV-0173] |
| Marketplace manifest check | Non-zero exit fails the workflow job; `permissions: contents: read` bounds the damage | Re-run the job | yes | N/A | GitHub API's | Actions default | N/A | Tracks the manifest schema | [EV-0081], [EV-0127] |
| Marketplace resolution | Client-side | Client-side | yes | N/A | GitHub's | GitHub's | N/A | Client-defined; can change without notice | `Inferred:` distribution is a git read performed by the client, reasoned from the manifest and the absence of any publish step [EV-0043, I] |

| Code | Meaning | Retryable | Caller action | Evidence |
|---|---|---|---|---|
| 0 | Success, or no findings | — | Continue | [EV-0107] |
| 1 | Findings present, or a required condition failed | no | Read the emitted findings and act | [EV-0107] |
| 2 | Usage error, missing argument, or infrastructure failure | after fixing the invocation | Fix the call | [EV-0107] |
| 3 | Inconclusive — `dossier-gate.sh` only, when mechanical checks pass but no scorer verdict exists | no | Obtain the missing judgment. **A gate can never return PASS from mechanical checks alone** | [EV-0107] |

Exit code 3 is worth naming explicitly. It exists so a reader can tell a missing human or model judgment apart from a failure and from a pass. The failure mode it prevents is a documentation package certifying itself.

Hook invocation is the one interface here whose contract is not established. The July draft stated that a non-zero `PreToolUse` exit blocks the tool call, as though the client documented it. What the evidence supports is narrower: three refusals were observed on one machine, against the installed flow 3.3.0 cache [EV-0172]. `Unknown:` what blocking, ordering and delivery semantics the client applies in general (AQ-0025). This matters because 19 in-tree hook scripts [EV-0162] and the external plugin's own two [EV-0168] are described across this package as controls, and that argument rests on the unestablished behaviour.

All three observed refusals were false positives of one kind: `block-destructive.sh` matches raw command text rather than parsed shell grammar [EV-0173]. AQ-0026 records whether it should parse instead.

## Integration prerequisites and environment differences

| Prerequisite | Applies to | How obtained | Lead time | Evidence |
|---|---|---|---|---|
| Claude Code client | every plugin | Anthropic | immediate | [EV-0051] |
| `git` | every plugin | preinstalled on macOS and Linux | immediate | [EV-0044] |
| `jq` | flow and dossier helper scripts | package manager | immediate | [EV-0175] |
| `bash` 3.2 or later | every shell script | preinstalled | immediate | [EV-0098], [EV-0107] |
| `gh` CLI, authenticated | flow's GitHub commands; dossier's setup preflight; the manifest check's reads of external sources | `gh auth login` | minutes | [EV-0080], [EV-0125] |
| `python3` with `pyyaml` | **required, not optional.** flow's journal, FlowRun state and FlowGoal machinery refuse to run without it [EV-0189]. dossier's workflow-template test uses it for one leg and skips that leg when it is absent [EV-0107] | package manager | minutes | [EV-0186], [EV-0187], [EV-0189] |
| An Anthropic API key as a repository secret | dossier's post-merge CI only | Anthropic console | minutes | [EV-0045] |

| Behaviour | Local | Test | Staging | Production | Evidence |
|---|---|---|---|---|---|
| Shell version | Both suites pass on Apple's `/bin/bash` 3.2.57 — flow 2336 assertions, dossier 1951 | Green on `ubuntu-latest` for every commit this range added to `main` | N/A | N/A | Both are targeted; the suites fail on bash 4+ constructs precisely because of this split | [EV-0098], [EV-0107], [EV-0126] |
| Windows | **unsupported** — two open issues reported failures under Git Bash, as observed 2026-07-26 | not tested; no `windows-latest` job exists among the 5 tracked workflows | N/A | N/A | [EV-0049], [EV-0123] |
| Interactivity | Commands may ask the operator questions | CI runs headless; dossier's CI path is designed for zero interaction via `DOSSIER_*` environment overrides | N/A | N/A | [EV-0086] |

There is no staging and no production, because there is no deployment. The only meaningful environment axis in this project is the operator's shell. The repository holds 0 Actions secrets [EV-0131]. The API-key prerequisite above is therefore unsatisfied, and no dossier refresh workflow is installed [EV-0084].

## Contract tests and verification coverage

| Interface | Contract test | Runs where | Covers | Does not cover | Last run | Evidence |
|---|---|---|---|---|---|---|
| dossier settings schema | `config-schema.test.sh` | local, `dossier-tests.yml` | Schema validity, cascade precedence with real fixtures, explicit-empty and explicit-false handling, semantic rules the schema deliberately omits | Whether the client honours the resulting configuration | 2026-09-10, pass within the whole suite | [EV-0107], [EV-0126] |
| dossier package contract | `package-contract.test.sh` | local, CI | 23 templates in 8 directories, contract-to-template bijection, declared header style versus the template's actual | Whether a drafted document satisfies its contract's prose | 2026-09-10, pass within the whole suite | [EV-0107], [EV-0126] |
| dossier CI workflow | `workflow-template.test.sh` | local, CI | YAML parses; jobs split by privilege, now including a separate `scan` job distinct from `policy` [EV-0075]; loop guards; no forced push; no untrusted interpolation in a `run:` body; the tool allowlist includes what the refresh actually dispatches; seven rotation job outputs each mapped to the rotation step's own output [EV-0157] | **Whether the workflow works.** It has never been executed (AQ-0002) | 2026-09-10, pass within the whole suite | [EV-0107], [EV-0075], [EV-0157], [EV-0045] |
| dossier agent independence | `agent-independence.test.sh` | local, CI | All three verification passes exist, carry `memory: none`, load three different second skills, none loads the reconciliation skill, and all are dispatched in a single message | Whether independence produces different findings in practice | 2026-09-10, pass within the whole suite | [EV-0107], [EV-0126] |
| `bin/*.sh` | `bin-scripts.test.sh` | local, CI | Syntax, executable bit, `set -u`, usage header, bash 3.2 portability, exit code 2 on bad flags, and that the gate cannot emit PASS without a scorer verdict | Behaviour against real repositories at scale | 2026-09-10, pass within the whole suite | [EV-0107], [EV-0126] |
| flow's whole surface | `plugins/flow/tests/run.sh` | local, `flow-tests.yml` | 2336 assertions, 0 failures | Windows; behavioural efficacy | 2026-09-10, pass on macOS and on `ubuntu-latest` | [EV-0098], [EV-0126] |
| dossier's whole surface | `plugins/dossier/tests/run.sh` | local, `dossier-tests.yml` | 1951 assertions, 0 failures | Behaviour against real repositories at scale | 2026-09-10, pass on macOS and on `ubuntu-latest` | [EV-0107], [EV-0126] |
| `marketplace.json` | `scripts/check-plugin-versions.sh` in `marketplace-manifest.yml` | local, CI, weekly cron | Every entry's advertised version against its source's own manifest, reading external sources at their pinned sha; a required `sha` on each external source | Whether the file parses and whether every source resolves (AQ-0020) | 2026-09-10, pass — 8 plugins, 0 failed, 0 unverifiable | [EV-0080], [EV-0081], [EV-0127] |
| Shell lint | shellcheck v0.11.0, pinned release URL, in `dossier-tests.yml` | CI | dossier's `bin/`, `hooks/scripts/` and `tests/` | flow's own `bin/` and hook scripts, which nothing lints (AQ-0019) | 2026-09-10, pass | [EV-0165], [EV-0126] |
| Static analysis | `github/codeql-action@v3` in `codeql.yml` | CI | A two-entry matrix, `actions` and `python`, both `build-mode: none`. Of the 40 tracked files under plugin `bin/`, 3 are Python and 37 carry a `.sh` extension | The 37 shell scripts, which no configured CodeQL language covers | 2026-09-10 — an analysis at each of the three merge commits in this range, each reporting 0 results | [EV-0134], [EV-0175], [EV-0140] |
| The other 4 in-repository plugins | **none** | — | — | everything | never | [EV-0182] |
| Slash-command behaviour end to end | **none** | — | — | everything | never | [EV-0098], [EV-0107] |

The suite results were measured before `d3fc744`. They still describe the tree this document pins: `plugins/` is blob-identical from `af6e632` through `7ee4923` to `d3fc744` [EV-0143], [EV-0174], [EV-0184].

The five per-test coverage descriptions above describe what each dossier test asserted at the July baseline. The suite has grown since — 1241 assertions then [EV-0009], 1951 now [EV-0107] — so each description is a floor rather than a current inventory.

Both plugin test workflows remain advisory. `main` carries no branch protection and no rulesets at `e104483` [EV-0131], so a failing contract test does not stop a change reaching every installer. The manifest check runs under the same condition.

Two of the results in this table were produced outside the engagement's own action ceiling, which sets `networkAccess` false [EV-0077]. The session operator ran the Actions-history read [EV-0126] and the manifest check [EV-0127] directly, because the dispatched collector could not [EV-0125]. AQ-0012 records whether the package may rest on them.

## Third-party dependencies and failure behaviour

| Dependency | Used for | Criticality | Failure behaviour | Timeout | Fallback | Tested | Evidence |
|---|---|---|---|---|---|---|---|
| Claude Code client | Everything. It resolves, installs, and executes every artifact | critical | Total — nothing in this project works without it | client-controlled | none possible | no | [EV-0044], [EV-0043, I] |
| GitHub | Hosting, distribution, releases, CI | critical | No installs, no releases, no CI | GitHub's | none | no | [EV-0051] |
| `actions/checkout@v4` | Every workflow | high | CI cannot run; merges are unaffected because CI is advisory | Actions default | none | implicitly, by every CI run | [EV-0042] |
| `github/codeql-action@v3` | Static analysis of `actions` and `python` | medium | No analysis; nothing blocks | Actions default | none | implicitly; 0 results at each of the three merge commits in this range | [EV-0134], [EV-0140] |
| GitHub REST API | The manifest check's reads of external plugin manifests at their pinned sha | medium | The check reports an entry it cannot fetch as unverifiable rather than as matching; the run at `af6e632` reported 0 unverifiable [EV-0127]. `Unknown:` what exit status an unverifiable entry produces — no row records it | GitHub's | none | yes — 0 unverifiable at `af6e632` | [EV-0080], [EV-0127] |
| `synaptiai/agent-capability-standard` at `9e2f65b` | One published plugin entry, resolved by the client and not by this repository | medium | `Unknown:` what the client does when a `github` source is unreachable (AQ-0023). The predecessor failure is on record: the gitlink resolved to 0 entries in a plain clone, so the advertised plugin could not install [EV-0167] | client-controlled | none | no | [EV-0058], [EV-0167] |
| `pyyaml`, on flow's runtime path | flow's journal writes, FlowRun state and FlowGoal enforcement, reached through `_journal_atomic.py` and `_flow_evidence_bundle.py` | high | flow's journal and run-state machinery does not run [EV-0189]. Whether to declare, guard or remove the requirement is open (AQ-0032) | none | none — no file in the repository declares the dependency for an operator [EV-0186], [EV-0187] | no | [EV-0186], [EV-0187], [EV-0189] |
| `pyyaml`, on dossier's test path | One leg of `workflow-template.test.sh` | low | The leg records a pass with "parse check skipped" and the structural checks continue [EV-0107] | none | Structural checks continue | yes, by the skip path itself | [EV-0107] |
| `jq` | flow and dossier helper scripts | high | Scripts exit non-zero with a stated reason | none | none | yes | [EV-0175] |
| `gh` CLI | flow's GitHub commands; dossier's setup preflight; the manifest check's reads of external sources | medium | Commands report a blocked state with the reason rather than proceeding; the manifest check could not run at all under this engagement's ceiling [EV-0125] | none | Manual GitHub use | partially | [EV-0080], [EV-0125] |

Both third-party actions are pinned by **major tag**, not by commit SHA, as observed 2026-07-26 [EV-0042]. `actions/checkout@v4` resolves to whatever the `v4` tag points at, so a compromise of that tag would execute in this repository's CI. The exposure is bounded — the test workflows and `marketplace-manifest.yml` hold `contents: read` [EV-0081] — but `release-desktop-skills.yml` runs with `contents: write` [EV-0133].

## Deprecation and versioning policy

| Aspect | Policy | Enforced how | Evidence |
|---|---|---|---|
| Versioning scheme | semver per plugin, mirrored into the marketplace entry; a separate semver for the marketplace itself | Convention in `.claude/CLAUDE.md`, now enforced per entry by the marketplace manifest check (TM-0033) | [EV-0080], [EV-0081], [EV-0064] |
| Breaking-change definition | **None stated.** No document defines what a breaking change is for a skill, a command, or a settings key, as observed 2026-07-26 | unenforced | [EV-0036] |
| Deprecation notice period | **None stated.** `gh-workflow` is superseded by flow in practice, with no deprecation notice, no sunset date, and both still published | unenforced | [EV-0181] |
| Sunset process | **None stated.** No plugin has been removed; the manifest still carries eight entries. One entry changed source kind in this range, from an in-tree submodule to a pinned external fetch [EV-0167] | unenforced | [EV-0181], [EV-0167] |

Three of four rows are absent policy. The missing breaking-change definition is the one with teeth. The client observed on 2026-07-26 held `autoUpdate: true` [EV-0051], so a renamed command or settings key reaches every installed operator on the next sync. Nothing declares whether that was permitted.

The version-key drift the check now guards against is not hypothetical. This repository's own `.claude/settings.dossier.json` pinned `dossier.ci.expectedPluginVersion` at 1.0.0 while the plugin read 1.2.0, and commit `d5a5166` corrected it [EV-0139]. That key is a consumed-configuration field, not a manifest entry, so the manifest check does not cover it.

## Undocumented and unstable interfaces

| Interface | Reachable by | Why undocumented | In use by anyone | Risk | Evidence |
|---|---|---|---|---|---|
| `bin/*.sh` invoked directly | anyone with the plugin installed | They are internal helpers, but they are executable, documented with usage headers, and on disk. 40 tracked files sit under plugin `bin/` — 37 with a `.sh` extension, 3 Python | unknown | Low. They are read-only or write inside a configured output root | [EV-0175] |
| Raw-text command matching in flow's `block-destructive.sh` | any operator with flow installed | It is a guard, not a published interface, but it decides whether an operator's tool call proceeds | yes — it refused three calls during this refresh [EV-0172] | Medium. All three refusals were false positives caused by matching command text rather than parsed shell grammar; AQ-0026 records whether it should parse instead | [EV-0172], [EV-0173] |
| `CLAUDE_PLUGIN_ROOT` | command `!` blocks | Undocumented by the client, and observed unset in slash-command bash blocks. Both flow and dossier ship a four-candidate fallback resolver because of it | yes — every dossier command depends on the fallback | Medium. If the client changes its cache layout, the fallback's candidate paths go stale | [EV-0005] |
| `~/.claude/plugins/*.json` | anything on the operator's machine | Client-internal state, read 2026-07-26 to verify install behaviour | this assessment did | Low for reading; the files are the client's contract, not this project's | [EV-0051], [EV-0052] |
| `plugins/flow/skills/learned/` | flow | A reserved location for learned skills, holding only `.gitkeep` as observed 2026-07-26 | no | Low. The skill-count discrepancy it once explained is resolved: flow's README claims 32 against 32 tracked files at `d3fc744` | [EV-0029], [EV-0179] |
| `.flow/` layout in a consuming repository | flow | This repository, which authors flow, holds `goals/` and `runs/` under `.flow/` [EV-0137] | yes — this repository holds both | `Unknown:` no evidence describes the loop's contract or what a consuming repository receives (AQ-0016) | [EV-0137], [EV-0136] |

## Mapping to the partner guide

| Interface | Disclosure decision | Claim ID | Register status | Appears in partner guide | Rationale if withheld |
|---|---|---|---|---|---|
| Marketplace and plugin install | disclose | CL-0003 | approved | yes | — |
| Plugin inventory and counts | disclose | CL-0045, CL-0036, CL-0037 | pending; they replace CL-0001, CL-0002 and CL-0004 | the guide still carries the superseded wording (CT-0012, CT-0013) | — |
| Hook bindings | disclose | CL-0040 | pending; replaces CL-0008 | the superseded wording | Disclosed deliberately: it is the only mechanism that executes without the operator invoking it |
| Third-party dependency surface | disclose | CL-0009, CL-0047 | CL-0009 approved; CL-0047 pending | partly | CL-0047 exists so a small dependency surface is not read as a scanned one |
| Sha pinning of both external entries | disclose | CL-0041 | pending; replaces CL-0010, which recorded the floating `main` ref | the superseded wording | An installer cannot detect this themselves without reading the manifest |
| Contract-test coverage | disclose, with both sides | CL-0038, CL-0039 | pending; they replace CL-0005 and CL-0006 | the superseded wording (CT-0022) | The strong number ships next to the gap it does not cover |
| Manifest check | disclose | CL-0046 | pending — a new claim | no | It is the only automated safeguard on the highest-blast-radius file in the repository |
| Release history | disclose | CL-0042 | pending; replaces CL-0011 | the superseded wording (CT-0011) | — |
| Windows portability | disclose | CL-0018 | approved | yes | — |
| Unexecuted CI template | disclose | CL-0017 | approved | yes | Withholding it would let a passing test suite read as proof the workflow runs |
| `bin/*.sh` calling convention | withhold | — | — | no | Internal helper interface with no stability commitment. Documenting it in a public guide would imply one |
| `CLAUDE_PLUGIN_ROOT` fallback | withhold | — | — | no | An implementation detail of a client behaviour this project does not control |
| Hook blocking semantics | withhold | — | — | no | The contract is not established (AQ-0025). A public sentence would assert a client behaviour no row supports |

Read the status column before the disclosure column. Seven of the interfaces above are now covered by `pending` rows. Their approved predecessors were falsified in this range, so the partner guide still states the older wording. `Unknown:` whether the guide may keep a superseded sentence while its replacement waits for approval (AQ-0028). Until that is decided, no interface in this table should be treated as correctly disclosed merely because it appears in the guide.
