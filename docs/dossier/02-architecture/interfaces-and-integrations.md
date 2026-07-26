---
dossier-header: internal-v1
title: Interfaces and Integrations
purpose: Lets an integrator or plugin author work against this project's contracts without reading its source, and see which of them are stable.
audience: Contributor, Installing operator, Reviewer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: fd884b2
last-verified: 2026-07-26
review-trigger: A command, hook event, settings key, or manifest field is added, renamed, or removed
related: [02-architecture/system-architecture.md, 02-architecture/components-and-codebase.md, 06-public/technical-partner-guide.md, 00-control/claim-and-disclosure-register.md]
---
# Interfaces and Integrations
<!-- contract: references/package-contract-02-architecture.md#interfaces-and-integrations -->

This project exposes no network API. Its interfaces are the manifest it publishes, the commands and hook bindings the Claude Code client reads, the settings files it consumes from a project, and the files it writes into a consuming repository. Each is a contract with someone, and each is listed here on those terms.

## Interface inventory

| Interface | Kind | Producer | Consumers | Owner | Transport | Authentication | Authorization | Schema | Version | Lifecycle | Disclosure | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `marketplace.json` | Discovery manifest | this repository | Claude Code client | Daniel Bentes | git over HTTPS | public read | none | Defined by the client; **not validated anywhere in this repository** | `metadata.version` 4.7.0 | stable | public | [EV-0001], [EV-0002] |
| `plugin.json` | Plugin identity | each plugin | Claude Code client | Daniel Bentes | filesystem | none | none | Client-defined | per plugin | stable | public | [EV-0026] |
| `/flow:*` | Slash commands | flow | operators | Daniel Bentes | session | none | Tier 1/2/3 gating inside the command bodies | Markdown frontmatter | 3.2.2 | stable | public | [EV-0004] |
| `/dossier:*` | Slash commands | dossier | operators | Daniel Bentes | session | none | Tier gating plus an action ceiling | Markdown frontmatter | 1.0.0 | new — unreleased | public | [EV-0009] |
| `/gh-*` | Slash commands | gh-workflow | operators | Daniel Bentes | session | none | none stated | Markdown frontmatter | 1.9.0 | legacy — superseded by flow, not deprecated in writing | public | [EV-0004] |
| Hook bindings | Lifecycle interception | flow, dossier, agent-capability-standard | Claude Code client | Daniel Bentes | process execution on the operator's machine | none | **none — hooks inherit the operator's privileges** | `hooks.json`, client-defined | per plugin | stable | public | [EV-0038], [EV-0039], [EV-0040] |
| `.claude/settings.dossier.json` | Consumed configuration | the consuming project | dossier | the consuming project | filesystem | none | none | `plugins/dossier/schema.json`, Draft-07 | 1.0.0 | new | public | [EV-0048] |
| flow settings | Consumed configuration | the consuming project | flow | the consuming project | filesystem | none | none | `plugins/flow/schema.json` | 3.2.2 | stable | public | [EV-0008] |
| `docs/dossier/**` | Produced artifact | dossier | humans, and dossier's own refresh | the consuming project | filesystem | none | Write confined by `enforce-output-root.sh` | 23-file package contract | 1.0.0 | new | public | [EV-0047] |
| `.flow/`, `.decisions/` | Produced artifact | flow | humans, and flow's own commands | the consuming project | filesystem | none | none | flow's own conventions | 3.2.2 | stable | public | [EV-0046] |
| `templates/ci/dossier-docs-refresh.yml` | Emitted CI workflow | dossier | the consuming repository's GitHub Actions | the consuming project after scaffolding | file, rendered at setup | GitHub OIDC at run time | Three jobs split by privilege | GitHub Actions schema | 1.0.0 | **never executed** (AQ-0002) | public | [EV-0045] |
| Desktop skill ZIPs | Release artifact | `package-desktop-skills.sh` | Claude Desktop | Daniel Bentes | GitHub release download | public | none | Desktop's skill package layout | per release | stable | public | [EV-0012] |

## Machine-readable contracts

| Contract | Format | Location | Generated from | Generation command | Versioned how | Validated where | Drift check | Evidence |
|---|---|---|---|---|---|---|---|---|
| dossier settings schema | JSON Schema Draft-07 | `plugins/dossier/schema.json` | hand-written | — | With the plugin | `bin/dossier-validate-config.sh`, plus `jsonschema` when available | `config-schema.test.sh` asserts the schema and `settings.json` agree, and that `config.example.json` validates | [EV-0009], [EV-0048] |
| flow settings schema | JSON Schema | `plugins/flow/schema.json` | hand-written | — | With the plugin | flow's validator | flow's suite | [EV-0008] |
| Package contract | Markdown references, one per output directory | `plugins/dossier/references/package-contract-0*.md` | hand-written against the templates | — | With the plugin | `bin/dossier-package-check.sh` resolves every contract pointer to a real anchor | `package-contract.test.sh` asserts a bijection between the 23 templates and the 8 contract documents | [EV-0009] |
| `marketplace.json` | JSON | `.claude-plugin/marketplace.json` | hand-written | — | `metadata.version` | **nowhere** | **none** | [EV-0001], [EV-0026] |
| `plugin.json` (×7) | JSON | `plugins/*/.claude-plugin/plugin.json` | hand-written | — | semver | flow and dossier validate their own only | Version agreement with the manifest is checked by hand | [EV-0026] |

The pattern is visible in the last two rows: the contracts that belong to a *plugin* are validated by that plugin's own suite, and the contracts that belong to the *marketplace* are validated by nothing. The manifest is the highest-blast-radius file in the repository and the only one with no check at all.

## Examples

Adding the marketplace and installing a plugin — the whole integration surface for an operator:

```
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install flow
```

The client then records the marketplace and its resolved source. On the assessment machine, `~/.claude/plugins/known_marketplaces.json` holds:

```json
{
  "source": { "source": "github", "repo": "synaptiai/synapti-marketplace" },
  "installLocation": "<client plugin dir>/marketplaces/synapti-marketplace",
  "lastUpdated": "2026-07-20T18:48:38.579Z",
  "autoUpdate": true
}
```

A marketplace entry, showing the two source kinds side by side:

```json
{ "name": "flow", "source": "./plugins/flow", "version": "3.2.2", "category": "workflow" }
```

```json
{ "name": "prompt-decorators",
  "source": { "source": "git-subdir",
              "url": "https://github.com/synaptiai/prompt-decorators.git",
              "path": "claude-code-plugin",
              "ref": "main" },
  "version": "0.1.1" }
```

The second form carries a `ref`, and it is `main`. That single field is the difference between an install that is reproducible and one that is not [EV-0030].

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

Every helper script emits `KEY=value` lines on stdout and signals outcome by exit code. Nothing returns prose for a model to parse loosely.

## Behaviour contract

| Interface | Error model | Retry guidance | Idempotency | Ordering | Rate limits | Timeouts | Pagination | Compatibility policy | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| `bin/*.sh` | Exit `0` success, `1` findings, `2` usage or infrastructure error; `3` inconclusive for `dossier-gate.sh` | Safe to re-run — all are read-only or idempotent writes | yes | N/A | none | none | N/A | Undeclared. Scripts are internal to their plugin, though nothing prevents external use | [EV-0007], [EV-0009] |
| Slash commands | Reported in-session as prose plus `KEY=value` blocks; blocked states report a reason rather than failing silently | Operator re-invokes | Depends on the command; `init` and `scaffold` never overwrite | Operator-driven | none | none | N/A | Undeclared | [EV-0005] |
| Hooks | A non-zero exit from a `PreToolUse` hook **blocks the tool call** — this is the intended mechanism, not an error | not retried | yes | Client-determined | none | none — a slow hook blocks the operator | N/A | Client-defined | [EV-0038] |
| Marketplace resolution | Client-side | Client-side | yes | N/A | GitHub's | GitHub's | N/A | Client-defined; can change without notice | [EV-0043] |

| Code | Meaning | Retryable | Caller action | Evidence |
|---|---|---|---|---|
| 0 | Success, or no findings | — | Continue | [EV-0009] |
| 1 | Findings present, or a required condition failed | no | Read the emitted findings and act | [EV-0009] |
| 2 | Usage error, missing argument, or infrastructure failure | after fixing the invocation | Fix the call | [EV-0009] |
| 3 | Inconclusive — `dossier-gate.sh` only, when mechanical checks pass but no scorer verdict exists | no | Obtain the missing judgment. **A gate can never return PASS from mechanical checks alone** | [EV-0009] |

Exit code 3 is worth naming explicitly. It exists so that the absence of a human or model judgment is distinguishable from a failure and from a pass — the failure mode it prevents is a documentation package certifying itself.

## Integration prerequisites and environment differences

| Prerequisite | Applies to | How obtained | Lead time | Evidence |
|---|---|---|---|---|
| Claude Code client | every plugin | Anthropic | immediate | [EV-0051] |
| `git` | every plugin | preinstalled on macOS and Linux | immediate | [EV-0044] |
| `jq` | flow and dossier helper scripts | package manager | immediate | [EV-0007] |
| `bash` 3.2 or later | every shell script | preinstalled | immediate | [EV-0008], [EV-0009] |
| `gh` CLI, authenticated | flow's GitHub commands; dossier's setup preflight | `gh auth login` | minutes | [EV-0012] |
| `python3` with `pyyaml` | optional. Used by dossier's workflow-template test and by `agent-capability-standard` | package manager | minutes | [EV-0041] |
| An Anthropic API key as a repository secret | dossier's post-merge CI only | Anthropic console | minutes | [EV-0045] |

| Behaviour | Local | Test | Staging | Production | Evidence |
|---|---|---|---|---|---|
| Shell version | macOS ships bash 3.2 | ubuntu-latest ships bash 5 | N/A | N/A | Both are targeted; the suites fail on bash 4+ constructs precisely because of this split | [EV-0008], [EV-0009] |
| Windows | **unsupported** — two open issues report failures under Git Bash | not tested; no `windows-latest` job exists | N/A | N/A | [EV-0049], [EV-0012] |
| Interactivity | Commands may ask the operator questions | CI runs headless; dossier's CI path is designed for zero interaction via `DOSSIER_*` environment overrides | N/A | N/A | [EV-0048] |

There is no staging and no production, because there is no deployment. The only meaningful environment axis in this project is the operator's shell.

## Contract tests and verification coverage

| Interface | Contract test | Runs where | Covers | Does not cover | Last run | Evidence |
|---|---|---|---|---|---|---|
| dossier settings schema | `config-schema.test.sh` | local, `dossier-tests.yml` | Schema validity, cascade precedence with real fixtures, explicit-empty and explicit-false handling, semantic rules the schema deliberately omits | Whether the client honours the resulting configuration | 2026-07-26, pass | [EV-0009] |
| dossier package contract | `package-contract.test.sh` | local, CI | 23 templates in 8 directories, contract-to-template bijection, declared header style versus the template's actual | Whether a drafted document satisfies its contract's prose | 2026-07-26, pass | [EV-0009] |
| dossier CI workflow | `workflow-template.test.sh` | local, CI | YAML parses; three jobs with the intended privilege split; four loop guards; no forced push; no untrusted interpolation in a `run:` body; the tool allowlist includes what the refresh actually dispatches | **Whether the workflow works.** It has never been executed (AQ-0002) | 2026-07-26, pass | [EV-0009], [EV-0045] |
| dossier agent independence | `agent-independence.test.sh` | local, CI | All three verification passes exist, carry `memory: none`, load three different second skills, none loads the reconciliation skill, and all are dispatched in a single message | Whether independence produces different findings in practice | 2026-07-26, pass | [EV-0009] |
| `bin/*.sh` | `bin-scripts.test.sh` | local, CI | Syntax, executable bit, `set -u`, usage header, bash 3.2 portability, exit code 2 on bad flags, and that the gate cannot emit PASS without a scorer verdict | Behaviour against real repositories at scale | 2026-07-26, pass | [EV-0009] |
| flow's whole surface | `plugins/flow/tests/run.sh` | local, `flow-tests.yml` | 1022 assertions | Windows; behavioural efficacy | 2026-07-26, pass | [EV-0008] |
| `marketplace.json` | **none** | — | — | everything | never | [EV-0026] |
| The other 5 in-tree plugins | **none** | — | — | everything | never | [EV-0010] |
| Slash-command behaviour end to end | **none** | — | — | everything | never | [EV-0008], [EV-0009] |

Both CI test workflows are advisory: `main` has no branch protection and no required checks, so a failing contract test does not prevent the change from reaching every installer [EV-0016], [EV-0017].

## Third-party dependencies and failure behaviour

| Dependency | Used for | Criticality | Failure behaviour | Timeout | Fallback | Tested | Evidence |
|---|---|---|---|---|---|---|---|
| Claude Code client | Everything. It resolves, installs, and executes every artifact | critical | Total — nothing in this project works without it | client-controlled | none possible | no | [EV-0043] |
| GitHub | Hosting, distribution, releases, CI | critical | No installs, no releases, no CI | GitHub's | none | no | [EV-0051] |
| `actions/checkout@v4` | Every workflow | high | CI cannot run; merges are unaffected because CI is advisory | Actions default | none | implicitly, by every CI run | [EV-0042] |
| `github/codeql-action@v3` | Static analysis | medium | No analysis; nothing blocks | Actions default | none | implicitly | [EV-0042] |
| `pyyaml>=6.0` | `agent-capability-standard` at runtime; dossier's workflow test optionally | low | The dossier test degrades gracefully — it records a pass with "parse check skipped" and continues structural checks | none | Structural checks continue | yes, by the skip path itself | [EV-0041], [EV-0009] |
| `jq` | flow and dossier helper scripts | high | Scripts exit non-zero with a stated reason | none | none | yes | [EV-0007] |
| `gh` CLI | flow's GitHub commands; dossier's setup preflight | medium | Commands report a blocked state with the reason rather than proceeding | none | Manual GitHub use | partially | [EV-0012] |

Both third-party actions are pinned by **major tag**, not by commit SHA [EV-0042]. `actions/checkout@v4` resolves to whatever the `v4` tag points at, so a compromise of that tag would execute in this repository's CI. The exposure is bounded — both test workflows hold `contents: read` — but `release-desktop-skills.yml` runs with `contents: write` and also uses `checkout@v4`.

## Deprecation and versioning policy

| Aspect | Policy | Enforced how | Evidence |
|---|---|---|---|
| Versioning scheme | semver per plugin, mirrored into the marketplace entry; a separate semver for the marketplace itself | Convention in `.claude/CLAUDE.md`; verified by hand | [EV-0026], [EV-0002] |
| Breaking-change definition | **None stated.** No document defines what a breaking change is for a skill, a command, or a settings key | unenforced | [EV-0036] |
| Deprecation notice period | **None stated.** `gh-workflow` is superseded by flow in practice, with no deprecation notice, no sunset date, and both still published | unenforced | [EV-0004] |
| Sunset process | **None stated.** No plugin has ever been removed | unenforced | [EV-0001] |

Three of four rows are absent policy. For a marketplace whose installers use `autoUpdate: true` by default [EV-0051], the missing breaking-change definition is the one with teeth: a renamed command or settings key reaches every installed operator on the client's next sync, with nothing declaring whether that was permitted.

## Undocumented and unstable interfaces

| Interface | Reachable by | Why undocumented | In use by anyone | Risk | Evidence |
|---|---|---|---|---|---|
| `bin/*.sh` invoked directly | anyone with the plugin installed | They are internal helpers, but they are executable, documented with usage headers, and on disk | unknown | Low. They are read-only or write inside a configured output root | [EV-0007] |
| `CLAUDE_PLUGIN_ROOT` | command `!` blocks | Undocumented by the client, and observed unset in slash-command bash blocks. Both flow and dossier ship a four-candidate fallback resolver because of it | yes — every dossier command depends on the fallback | Medium. If the client changes its cache layout, the fallback's candidate paths go stale | [EV-0005] |
| `~/.claude/plugins/*.json` | anything on the operator's machine | Client-internal state, read during this assessment to verify install behaviour | this assessment did | Low for reading; the files are the client's contract, not this project's | [EV-0051], [EV-0052] |
| `plugins/flow/skills/learned/` | flow | A reserved location for learned skills, currently holding only `.gitkeep` | no | Low, but it is the reason flow's advertised skill count is off by one | [EV-0029] |

## Mapping to the partner guide

| Interface | Disclosure decision | Claim ID | Appears in partner guide | Rationale if withheld |
|---|---|---|---|---|
| Marketplace and plugin install | disclose | CL-0003 | yes | — |
| Plugin inventory and counts | disclose | CL-0001, CL-0002, CL-0004 | yes | — |
| Hook bindings | disclose | CL-0008 | yes | Disclosed deliberately: it is the only mechanism that executes without the operator invoking it |
| Third-party dependency surface | disclose | CL-0009 | yes | — |
| Floating ref on `prompt-decorators` | disclose | CL-0010 | yes | An installer cannot detect this themselves without reading the manifest |
| Contract-test coverage | disclose, with both sides | CL-0005, CL-0006 | yes | The strong number ships next to the gap it does not cover |
| Release history | disclose | CL-0011 | yes | — |
| Windows portability | disclose | CL-0018 | yes | — |
| Unexecuted CI template | disclose | CL-0017 | yes | Withholding it would let a passing test suite read as proof the workflow runs |
| `bin/*.sh` calling convention | withhold | — | no | Internal helper interface with no stability commitment. Documenting it in a public guide would imply one |
| `CLAUDE_PLUGIN_ROOT` fallback | withhold | — | no | An implementation detail of a client behaviour this project does not control |
