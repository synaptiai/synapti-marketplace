---
dossier-header: public-v1
title: Product and Trust Guide
audience: Operators deciding whether to install
product-version: 4.10.0
last-updated: 2026-09-10
---
# Product and Trust Guide
<!-- contract: references/package-contract-06-public.md#customer-product-and-trust-guide -->

This guide is for anyone deciding whether to install these plugins. Every factual statement in this guide maps to an approved claim backed by a verified evidence row.

## What the marketplace is

The marketplace publishes eight Claude Code plugins. *Each entry's advertised version is checked against its source in continuous integration.*

Plugins run inside your own Claude Code session. The marketplace operates no service and collects no telemetry.

## Getting started

```
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install <plugin-name>
```

Add the marketplace, then install individual plugins by name. *Verified on a profile that already had the marketplace registered; a first install on a clean profile has not been observed.*

Beyond Claude Code, `git`, `jq` and an authenticated `gh`, the plugins require `python3`, PyYAML and `jsonschema`, none of which any manifest declares. GNU `timeout` is needed by the FlowGoal evaluator.

## What it can and cannot do

| Capability | What it does | Available to |
|---|---|---|
| Workflow harnesses | Structured GitHub workflows — issue to branch to commit to review to merge — with safety rails | anyone who installs |
| Documentation tooling | Builds an evidence-cited documentation package for a project, and refuses to certify one that is not grounded | anyone who installs |
| Content analysis | Manipulation and disinformation analysis; evidence-based product decisions | anyone who installs |
| Organizational and agent design | Skills for designing AI-first organizations and specifying agent capabilities | anyone who installs |
| Prompt tooling | Composable prompt decorators | anyone who installs |

| Limitation | What this means for you | Workaround |
|---|---|---|
| Both published releases, v4.9.0 and v4.10.0, carry a defect that deadlocks flow's task-completion gate on macOS. Re-running your tests cannot clear it | If you install the current release on macOS, you will hit this | Set the task-completion gate to `warn` or `off` for the session |
| No continuous-integration workflow runs on macOS or Windows. All five run on Linux | macOS is listed as supported but nothing checks it automatically | Try it on a scratch repository before relying on it |
| The plugins require `python3`, PyYAML and `jsonschema`, and no manifest declares them | Install can appear to succeed and then fail when a script runs | Install the three yourself before using a plugin |
| Four of the six in-repository plugins ship no automated test suite | Most of the collection has no verification of even structural validity | Prefer the tested plugins; read the others before relying on them |
| The dossier plugin's post-merge documentation automation has never been executed end to end | A capability that is built and unit-tested but never observed working | Run it once in a scratch repository before depending on it |
| Two open issues report that the shipped shell scripts fail under Windows and Git Bash | Windows is not usable today | Use macOS or Linux |
| The `main` branch carries no branch protection and no rulesets, so both test workflows are advisory rather than required | A change can reach you without any check having to pass | Pin your own copy, or review what changed between syncs |

## Key journeys

| Journey | Steps | Result |
|---|---|---|
| Try a plugin | Add the marketplace, install one plugin, use its commands in a scratch repository | You can judge it on your own work before trusting it anywhere important |
| Audit before installing | Browse the public repository and read the hooks and helper scripts a plugin would install | You can read the hooks and helper scripts that would run on your machine, before they do |
| Remove it | Uninstall the plugin through Claude Code | The plugin stops loading. Whether the files it wrote are removed with it has not been tested |

## Accounts, permissions, and controls

| Role | Can | Cannot | How it is assigned |
|---|---|---|---|
| You, the operator | Install, uninstall, and use any plugin | Nothing is restricted — there is no permission model | Self-service |
| The project | Publish changes that reach you when your client next syncs | Reach your machine any other way | — |

| Control available to you | What it does | Where to find it |
|---|---|---|
| Choosing what to install | Each plugin is installed by name; installing the marketplace does not install its plugins | `claude plugin install` |
| Reading before installing | Every executable artifact ships as plain text you can read | The public repository |
| Uninstalling | Stops the plugin loading in your sessions; whether the files it wrote are removed has not been tested | Claude Code |
| Your Anthropic budget | Model usage the plugins induce is billed to your own account | The Anthropic console |

Every marketplace entry's advertised version is checked against its source in continuous integration, on manifest changes, weekly, and on demand. The check reached `main` after v4.10.0 was cut, so it does not exist in that released tree.

Claude Code's plugin client defaults to auto-updating an added marketplace. Changes reach you without your acting, on the client's schedule.

No checksum, signature, attestation or provenance step exists anywhere in the release path.

## What runs on your machine

Two of the plugins in this repository register hooks — shell scripts the Claude Code client runs on your machine at defined lifecycle points — and so does the externally sourced agent-capability-standard.

**Hooks execute without you invoking them.** They run with your user privileges, in your shell, with access to whatever you have access to. There is no sandbox.

Two things bound that risk, and you should verify both yourself.

- You can read every hook before you install it.
- The hooks that exist are mostly restrictive — they block destructive commands, force-pushes, and writes containing credential patterns.

Every release since v4.7.0 carries dozens of `.zip` skill bundles. Their contents are Markdown only — no executable is packaged.

## What the plugins write

The plugins write into your repository at `.decisions/`, `.flow/goals/`, `.flow/runs/` and `.claude/settings.flow.json`, and into your home directory under `~/.claude/`. `/flow:setup` appends to your `CLAUDE.md`, after asking. Whether those files survive an uninstall has not been tested.

## Your data

| Data | Why it is collected | How it is used | Your choices | How to delete it |
|---|---|---|---|---|
| **none** | The marketplace collects nothing | — | — | — |

The marketplace holds no personal data. It has no accounts, no server, and no database. Your Claude Code session sends data to Anthropic under your own agreement with them, and a plugin's hooks run on your machine with your privileges. Neither is governed by this project.

No telemetry, analytics or reporting endpoint exists in any tracked file. Outbound traffic is limited to `gh` and `git` against GitHub under your own credentials.

| Question | Answer |
|---|---|
| Where is data stored | Nowhere. The project has no store of any kind |
| How long is it kept | Not applicable |
| Who can access it | Not applicable |
| Is it shared with third parties | No — there is nothing to share |
| How to export it | Not applicable |
| How to request deletion | Not applicable |

## Security, privacy, reliability, and accessibility

| Area | What is true | Scope it holds within |
|---|---|---|
| Security | No credential matching the project's own detector pattern set appears in any tracked file. *The scan covers tracked files against an enumerated pattern set, as observed on 2026-07-26. It proves that none of those formats appears, not that no credential exists, and it has not been re-run since.* | The repository's tracked files |
| Security | The `main` branch carries no branch protection and no rulesets, so both test workflows are advisory rather than required. In practice: a change can reach you without any check having to pass, and the plugin client auto-updates an added marketplace by default | Live repository settings |
| Security | The repository publishes no security policy and no private disclosure channel. A researcher who finds a flaw has no private way to report it | Current state |
| Security | No checksum, signature, attestation or provenance step exists anywhere in the release path | The release path |
| Privacy | The marketplace holds no personal data | The marketplace itself, not the Claude Code client or the model provider |
| Reliability | There is no service to be up or down | The marketplace itself |
| Accessibility | Not applicable — the project renders no interface. Output is Markdown displayed by your own client | — |

## Licensing

The repository is licensed under Apache-2.0, and every plugin manifest declares the same licence.

Until 2026-07-26 no `LICENSE` file existed at all, while the README asserted MIT. A copy taken before that date predates the licence; ask before relying on the earlier state.

This is an open-source project published without warranty or commitment.

## AI features

| Question | Answer |
|---|---|
| Where AI is used | The plugins *are* prompts. They instruct the model in your Claude Code session; the project invokes no model of its own and pays for no inference |
| What it does and does not decide | The plugins structure how a model works on your repository. Actions with consequences — merging, releasing, publishing — are gated behind explicit confirmation in the workflow plugins |
| Human oversight | Every plugin runs interactively in your session by default. The one automated path — the post-merge documentation refresh — has never been executed end to end |
| Your controls | Install only what you want; read it first; uninstall at any time; set a budget in your Anthropic console |
| Whether your data trains models | Not through this project. Your session's relationship with Anthropic is governed by your own agreement with them |
| Whether the plugins measurably help | Evaluated for one plugin only — see below |

A behavioural evaluation of the flow plugin exists and has been run: 105 sessions across two models and seven configuration arms. It found no measurable difference against a no-plugin baseline. Seven of the eight marketplace plugins have no behavioural evaluation of any kind.

## Supported platforms and regions

| Aspect | Supported | Not supported |
|---|---|---|
| Platforms | macOS and Linux, with bash 3.2 or later — but no automated check runs on macOS, and both published releases carry a macOS defect | **Windows** — two open issues report failures under Windows and Git Bash, and neither test workflow runs on Windows |
| Regions | Anywhere GitHub is reachable | — |
| Languages | English | Everything else — no localization mechanism exists |
| Compatibility requirements | Claude Code, `git`, `jq`, an authenticated `gh` CLI for some plugins, plus `python3`, PyYAML, `jsonschema` and GNU `timeout` | Other agent clients, except a packaged skill export for Claude Desktop |

## Support and status

| Need | Where to go | Expected response |
|---|---|---|
| A bug | GitHub issues | **None stated** |
| A question | GitHub issues | **None stated** |
| A security report | **No private channel exists** | — |

| Channel | Purpose |
|---|---|
| Status page | None exists |
| Incident notifications | None exist. There is no way for the project to reach you if something it published breaks your machine |
| Escalation | **None defined** |

## Document details

| Field | Value |
|---|---|
| Applies to product version | 4.10.0 |
| Last updated | 2026-09-10 |

Every factual statement in this guide maps to an approved claim backed by a verified evidence row.
