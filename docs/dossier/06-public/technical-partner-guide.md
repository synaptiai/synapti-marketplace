---
dossier-header: public-v1
title: Technical Partner Guide
audience: Plugin authors, integrators, and operators evaluating the marketplace
product-version: 4.10.0
last-updated: 2026-09-10
---
# Technical Partner Guide
<!-- contract: references/package-contract-06-public.md#technical-partner-guide -->

Every factual statement in this guide maps to an approved claim backed by a verified evidence row. Where a claim is only true within a scope, the scope is stated next to it rather than in a footnote.

## What this is

The marketplace publishes eight Claude Code plugins. *Each entry's advertised version is checked against its source in continuous integration.* The published `main` manifest carries all eight entries.

Six plugins are versioned in this repository. Two are published from other repositories, each pinned to a commit sha. *The manifest uses three resolution mechanisms: six relative paths, one `github` source, one `git-subdir` source.*

The repository is licensed under Apache-2.0, and every plugin manifest declares the same licence.

## How an integration fits together

```mermaid
%% Your side, the published surface, and your session. Nothing runs on our
%% infrastructure at any point on this path.
graph LR
  you["Your project"] --> client["Claude Code<br/>your client"]
  client --> manifest["The published marketplace<br/>a list of installable plugins"]
  manifest --> plugin["The plugin you chose"]
  plugin --> session["Your session<br/>commands, skills, and hooks"]
  session --> repo["Your repository<br/>on your machine"]
```

## Supported use cases

| Use case | What it enables | Supported | Not supported |
|---|---|---|---|
| Installing a plugin into Claude Code | A worked-out method, its commands, and its safety hooks become available in your sessions | yes | Any client other than Claude Code, except the packaged skill export for Claude Desktop |
| Reading the source before trusting it | Every executable artifact ships as plain text you can read | yes | Signature, checksum, or provenance verification — see below |
| Pinning to a specific version | In-repository plugins resolve to the commit your client reads | yes | The two externally sourced entries — see below |
| Running on macOS or Linux | bash 3.2 and later | yes — with the macOS defect under Known limitations | **Windows** — see Known limitations |

No checksum, signature, attestation or provenance step exists anywhere in the release path.

## Prerequisites and access

| Step | What it is | How to obtain | Typical lead time |
|---|---|---|---|
| Claude Code | The client that resolves, installs, and executes every artifact | Anthropic | immediate |
| `git` | Used by the client to fetch the marketplace | preinstalled on macOS and Linux | immediate |
| `jq` | Required by several plugins' helper scripts | package manager | immediate |
| `gh` CLI, authenticated | Required by the GitHub workflow commands | `gh auth login` | minutes |
| `python3` | Required by several scripts, and declared by no manifest | package manager | immediate |
| PyYAML and `jsonschema` | Required at runtime, and declared by no manifest | `pip install pyyaml jsonschema` | immediate |
| GNU `timeout` | Needed by the FlowGoal evaluator | package manager (`coreutils` on macOS) | immediate |

Beyond Claude Code, `git`, `jq` and an authenticated `gh`, the plugins require `python3`, PyYAML and `jsonschema`, none of which any manifest declares. GNU `timeout` is needed by the FlowGoal evaluator.

## Installing

```
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install <plugin-name>
```

Add the marketplace, then install individual plugins by name. *Verified on a profile that already had the marketplace registered; a first install on a clean profile has not been observed.*

## What ships in each plugin

The flow plugin ships 32 skills, 23 commands, 9 agents, and 14 hook scripts. *Counts are file counts — a skill directory without a `SKILL.md` is not a skill.*

Both externally sourced plugins carry a pinned commit sha in the manifest, alongside a `ref` of `main`.

Every release since v4.7.0 carries dozens of `.zip` skill bundles. Their contents are Markdown only — no executable is packaged.

## Public interfaces

| Interface | Kind | Purpose | Stability | Since version |
|---|---|---|---|---|
| `.claude-plugin/marketplace.json` | discovery manifest | Names every plugin and how to resolve it | no commitment — see Commitments | 1.0.0 |
| `plugins/*/.claude-plugin/plugin.json` | plugin identity | Name, version, description, licence | no commitment — see Commitments | 1.0.0 |
| Slash commands | session interface | The visible surface of each plugin | no commitment — see Commitments | per plugin |
| Hook registrations | lifecycle interception | Scripts the client runs at defined events | no commitment — see Commitments | per plugin |
| Release assets | distribution | Skill packages for Claude Desktop | no commitment — see Commitments | — |

Helper scripts under each plugin's `bin/` are internal. They are executable and documented, but they carry no stability commitment and may change without notice.

## How it executes on your machine

Plugins run inside your own Claude Code session. The marketplace operates no service and collects no telemetry.

Two of the plugins in this repository register hooks — shell scripts the Claude Code client runs on your machine at defined lifecycle points — and so does the externally sourced agent-capability-standard.

**Hooks execute without you invoking them.** They run with your user privileges, in your shell, with access to whatever you have access to. There is no sandbox.

Two things bound that risk, and you should verify both yourself.

- Every hook ships as plain text you can read before installing.
- The hooks in the flow plugin are restrictive by design — they block destructive commands, force-pushes, and writes containing credential patterns.

The plugins write into your repository at `.decisions/`, `.flow/goals/`, `.flow/runs/` and `.claude/settings.flow.json`, and into your home directory under `~/.claude/`. `/flow:setup` appends to your `CLAUDE.md`, after asking. Whether those files survive an uninstall has not been tested.

No telemetry, analytics or reporting endpoint exists in any tracked file. Outbound traffic is limited to `gh` and `git` against GitHub under your own credentials.

## Authentication and authorization

| Scope or permission | Grants | Required for |
|---|---|---|
| none | The marketplace has no accounts, no keys, and no permission model of its own | — |
| Your GitHub auth (`gh`) | Used by the workflow plugins to act on repositories you already control | flow and gh-workflow commands |
| Your Anthropic account | Pays for and executes all model usage the plugins induce | every plugin |

## Versioning and compatibility

| Aspect | Policy |
|---|---|
| Versioning scheme | Semantic versioning per plugin, mirrored into its marketplace entry. The marketplace itself carries a separate version |
| What counts as a breaking change | **Not defined.** No document states what constitutes a breaking change to a skill, a command, or a settings key |
| Supported versions | The current one. No prior version is maintained |
| Deprecation notice period | **None defined.** No plugin has been deprecated or removed to date |
| How changes are announced | GitHub releases and per-plugin CHANGELOGs. There is no announcement channel, mailing list, or status page |

The marketplace has published 63 tags; the most recent release is v4.10.0, dated 2026-09-10.

Every marketplace entry's advertised version is checked against its source in continuous integration, on manifest changes, weekly, and on demand. The check reached `main` after v4.10.0 was cut, so it does not exist in that released tree.

Claude Code's plugin client defaults to auto-updating an added marketplace. Changes reach you without your acting, on the client's schedule.

## Behaviour a partner must handle

| Behaviour | What happens | What your integration should do |
|---|---|---|
| Errors | Exit-code conventions differ between the two plugins — see below | Treat a non-zero exit as authoritative; read the emitted `KEY=value` lines |
| Retries | See below | Re-invoke only after checking what the previous call wrote |
| Idempotency | Scaffolding behaviour depends on the existing file — see below | Check a scaffolded file before assuming it was preserved |
| Rate limits | See below | Handle GitHub's limits |
| Timeouts | See below | Expect blocking behaviour from hooks |
| Pagination | Not applicable | — |

The dossier plugin's helper scripts exit 2 on a usage error. The flow plugin's helper scripts do not follow that convention: eleven of seventeen exit 1 and two exit 0.

No script in either plugin retries anything.

Scaffolding leaves an existing document alone when it begins with a frontmatter fence. A file that does not is treated as damaged and replaced.

The marketplace imposes no rate limits. GitHub's own limits apply to clone and API traffic.

The project's own code does set timeouts — both scanners default to 300 seconds — and no hook registration declares one. A `PreToolUse` hook blocks your tool call while it runs.

| Code | Meaning | Retryable | What to do |
|---|---|---|---|
| 0 | Success, or no findings | — | Continue |
| 1 | Findings present, or a required condition failed | no | Read the findings and act |
| 2 | Usage error or infrastructure failure | after fixing the call | Fix the invocation |
| 3 | Inconclusive — used where a required judgment is absent rather than failed | no | Obtain the missing judgment |

The exit-code table describes helper scripts, not hooks. Flow's `PreToolUse` hooks exit 2 to block a tool call, which is the client's hook protocol and not a usage error.

## Testing your integration

| Facility | What it offers | Differences from production | How to get access |
|---|---|---|---|
| The repository itself | Clone it and run the test suites directly | None — the repository is the artifact; there is no build step | Public |
| flow and dossier test suites | Each plugin ships a runnable suite | Runs against the working tree rather than an installed copy | Public |
| A scratch repository | Install the plugins and exercise the commands against work you do not mind changing | None | Your own |

There is no sandbox environment and no staging marketplace. A scratch repository is the recommended way to evaluate a workflow plugin before pointing it at anything you care about.

## Quality signals

The flow and dossier plugins ship automated test suites — 2336 and 1951 assertions respectively — both passing. *Assertion counts describe the suites, not coverage of the plugins they guard. The macOS results were observed on one machine; the Linux results are GitHub Actions runs.*

Four of the six in-repository plugins ship no automated test suite.

No continuous-integration workflow runs on macOS or Windows. All five run on Linux.

The bash 3.2 portability assertion covers 20 of the 59 tracked scripts, all of them dossier's.

Dossier's suite asserts that every registered hook exists and is executable. Flow's suite has no equivalent.

Twenty-six of the twenty-seven scripts that read `CLAUDE_PLUGIN_ROOT` supply a fallback.

A behavioural evaluation of the flow plugin exists and has been run: 105 sessions across two models and seven configuration arms. It found no measurable difference against a no-plugin baseline. Seven of the eight marketplace plugins have no behavioural evaluation of any kind.

## Security and data responsibility

| Responsibility | Product | Partner |
|---|---|---|
| Auditing what will execute | Ships everything as readable plain text | **Read the hooks and scripts before installing** |
| Isolating execution | Provides no sandbox | Decide what machine and what account you run this on |
| Protecting credentials | Ships no credentials and requires none | Your own keys, in your own environment |
| Verifying what you received | No checksum, signature, attestation or provenance step exists | Compare against the public repository yourself |
| Model usage cost | Induces it; measures nothing | Set a budget in your Anthropic console |
| Credential scanning | No credential matching the project's own detector pattern set appears in any tracked file. *The scan covers tracked files against an enumerated pattern set, as observed on 2026-07-26. It proves that none of those formats appears, not that no credential exists, and it has not been re-run since.* | Re-run your own scan against the tree you install |

The repository publishes no security policy and no private disclosure channel.

## Operations and support

| Aspect | Detail |
|---|---|
| Support channel | GitHub issues, public |
| Response expectations | **None stated** |
| Escalation path | **None defined** |
| Status page | None |
| Maintenance notification | None |

## Commitments

| Commitment | Applies to | Conditions | Where it is contractually defined |
|---|---|---|---|
| **none** | — | — | Nowhere. There is no contract, no SLA, and no support agreement with anyone |

This is an open-source project published without warranty or commitment.

## Change communication

| Change type | Notice | Channel |
|---|---|---|
| New plugin or version | none in advance | The marketplace manifest and a GitHub release |
| Breaking change | **none — no policy exists** | The same |
| Removal or deprecation | **none — no policy exists** | The same |
| Security fix | none | A commit |

## Known limitations

| Limitation | Effect on your integration | Workaround |
|---|---|---|
| Both published releases, v4.9.0 and v4.10.0, carry a defect that deadlocks flow's task-completion gate on macOS. Re-running your tests cannot clear it | A macOS operator installing the current release hits this | Set the task-completion gate to `warn` or `off` for the session |
| No continuous-integration workflow runs on macOS or Windows. All five run on Linux | macOS is supported but unverified by any automated check | Run the suites yourself on your own platform |
| The `main` branch carries no branch protection and no rulesets, so both test workflows are advisory rather than required | Any change reaches installers without a check having to pass, and the client auto-updates by default | Pin your own copy, or review the diff between syncs |
| The dossier plugin's post-merge documentation automation has never been executed end to end. Its components are tested; the assembled behaviour is not | Do not depend on it working until you have run it yourself | Run it once in a scratch repository first |
| Two open issues report that the shipped shell scripts fail under Windows and Git Bash, and neither test workflow runs on Windows | Windows operators should expect failures | Use macOS or Linux |

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| The task-completion gate never clears on macOS | The defect carried by both published releases | Set the gate to `warn` or `off`; report it |
| A script fails with `declare: -A: invalid option` | An older bash than the script expects | The portability assertion does not cover that script; report it as a bug |
| A hook never fires | The file lacks the executable bit | Report it — dossier's suite checks for this, flow's does not |
| A command cannot find its plugin root | An environment variable the client does not always set | Most scripts ship a fallback; report it if you hit one that does not |
| Anything on Windows | Known and unresolved | Use macOS or Linux |
