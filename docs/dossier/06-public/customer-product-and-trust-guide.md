---
dossier-header: public-v1
title: Product and Trust Guide
audience: Operators deciding whether to install
product-version: 06b1586
last-updated: 2026-07-26
---
# Product and Trust Guide
<!-- contract: references/package-contract-06-public.md#customer-product-and-trust-guide -->

This guide is for anyone deciding whether to install these plugins. Every statement in this guide maps to an approved claim backed by a verified evidence row.

## What the marketplace is

The marketplace publishes eight Claude Code plugins. *The published `main` manifest carries seven entries; the eighth exists only on the branch this guide was produced from.*

Plugins run inside your own Claude Code session. The marketplace operates no service and collects no telemetry.

## Getting started

```
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install <plugin-name>
```

Add the marketplace, then install individual plugins by name. *Verified on a profile that already had the marketplace registered; a first install on a clean profile has not been observed.*

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
| Five of the seven in-repository plugins ship no automated test suite | Most of the collection has no verification of even structural validity | Prefer the tested plugins; read the others before relying on them |
| The dossier plugin's post-merge documentation automation has never been executed end to end | A capability that is built and unit-tested but never observed working | Run it once in a scratch repository before depending on it |
| Two open issues report that the shipped shell scripts fail under Windows and Git Bash | Windows is not usable today | Use macOS or Linux |
| The project is maintained by one person, and no component has a named backup owner | Fixes, releases, and security responses depend on one person's availability | Weigh this as you would any single-maintainer dependency |

## Key journeys

| Journey | Steps | Result |
|---|---|---|
| Try a plugin | Add the marketplace, install one plugin, use its commands in a scratch repository | You can judge it on your own work before trusting it anywhere important |
| Audit before installing | Browse the public repository and read `plugins/<name>/hooks/` and `bin/` | You see everything that will execute on your machine, in plain text, before it does |
| Remove it | Uninstall the plugin through Claude Code | The plugin stops loading. Nothing of yours was held anywhere |

## Accounts, permissions, and controls

| Role | Can | Cannot | How it is assigned |
|---|---|---|---|
| You, the operator | Install, uninstall, and use any plugin | Nothing is restricted — there is no permission model | Self-service |
| The project | Publish changes that reach you when your client next syncs | Reach your machine any other way | — |

| Control available to you | What it does | Where to find it |
|---|---|---|
| Choosing what to install | Each plugin is installed by name; installing the marketplace does not install its plugins | `claude plugin install` |
| Reading before installing | Every executable artifact is plain shell or Markdown | The public repository |
| Uninstalling | Removes the plugin and its hooks from your sessions | Claude Code |
| Your Anthropic budget | Model usage the plugins induce is billed to your own account | The Anthropic console |

## What runs on your machine

Three plugins register hooks — shell scripts the Claude Code client runs on your machine at defined lifecycle points.

**Hooks execute without you invoking them.** They run with your user privileges, in your shell, with access to whatever you have access to. There is no sandbox.

Two things bound that risk, and you should verify both yourself.

- Everything is readable. There are no binaries and no bundles; you can read every hook before you install it.
- The hooks that exist are mostly restrictive — they block destructive commands, force-pushes, and writes containing credential patterns.

The repository's only declared third-party runtime dependency is `pyyaml`, required by the agent-capability-standard plugin. *This covers declared dependencies, not what the Claude Code client itself requires.*

## Your data

| Data | Why it is collected | How it is used | Your choices | How to delete it |
|---|---|---|---|---|
| **none** | The marketplace collects nothing | — | — | — |

The marketplace holds no personal data. It has no accounts, no server, and no database.

| Question | Answer |
|---|---|
| Where is data stored | Nowhere. The project has no store of any kind |
| How long is it kept | Not applicable |
| Who can access it | Not applicable |
| Is it shared with third parties | No — there is nothing to share |
| How to export it | Not applicable |
| How to request deletion | Not applicable |

Your Claude Code session sends data to Anthropic under your own agreement with them, and a plugin's hooks run on your machine with your privileges. Neither is governed by this project.

## Security, privacy, reliability, and accessibility

| Area | What is true | Scope it holds within |
|---|---|---|
| Security | No credential matching the project's own detector pattern set appears in any tracked file. *The scan covers tracked files against an enumerated pattern set — it proves that none of those formats appears, not that no credential exists.* | The repository's tracked files |
| Security | The `main` branch carries no branch protection and no rulesets, so both test workflows are advisory rather than required. In practice: a change can reach you without any check having to pass, and the plugin client auto-updates an added marketplace by default | Live repository settings |
| Security | The repository publishes no security policy and no private disclosure channel. A researcher who finds a flaw in a hook that runs on your machine has no private way to report it | Current state |
| Privacy | The marketplace holds no personal data | The marketplace itself, not the Claude Code client or the model provider |
| Reliability | There is no service to be up or down. Once installed, a plugin works offline; only installs and updates need the network | The marketplace itself |
| Accessibility | Not applicable — the project renders no interface. Output is Markdown displayed by your own client | — |

## Licensing

The repository is licensed under Apache-2.0, and every plugin manifest declares the same licence. *GitHub's repository-level licence badge is computed from the default branch, so the badge reports it only after this branch merges.*

Until 2026-07-26 no `LICENSE` file existed at all, while the README asserted MIT. A copy taken before that date predates the licence; ask before relying on the earlier state.

## AI features

| Question | Answer |
|---|---|
| Where AI is used | The plugins *are* prompts. They instruct the model in your Claude Code session; the project invokes no model of its own and pays for no inference |
| What it does and does not decide | The plugins structure how a model works on your repository. Actions with consequences — merging, releasing, publishing — are gated behind explicit confirmation in the workflow plugins |
| Known limitations | The plugins have no behavioural evaluation. Their structure is tested; whether their instructions improve a model's output is not measured |
| Human oversight | Every plugin runs interactively in your session by default. The one automated path — dossier's post-merge refresh — has never been executed end to end |
| Your controls | Install only what you want; read it first; uninstall at any time; set a budget in your Anthropic console |
| Whether your data trains models | Not through this project. It transmits nothing. Your session's relationship with Anthropic is governed by your own agreement with them |

## Supported platforms and regions

| Aspect | Supported | Not supported |
|---|---|---|
| Platforms | macOS and Linux, with bash 3.2 or later | **Windows** — two open issues report failures under Windows and Git Bash, and neither test workflow runs on Windows |
| Regions | Anywhere GitHub is reachable | — |
| Languages | English | Everything else — no localization mechanism exists |
| Compatibility requirements | Claude Code. `git`, `jq`, and for some plugins an authenticated `gh` CLI | Other agent clients, except a packaged skill export for Claude Desktop |

## Support and status

| Need | Where to go | Expected response |
|---|---|---|
| A bug | GitHub issues | None stated. The project is maintained by one person |
| A question | GitHub issues | None stated |
| A security report | **No private channel exists** | — |

| Channel | Purpose |
|---|---|
| Status page | None exists |
| Incident notifications | None exist. There is no way for the project to reach you if something it published breaks your machine |
| Escalation | None — there is no second person |

## Document details

| Field | Value |
|---|---|
| Applies to product version | `06b1586` |
| Last updated | 2026-07-26 |

Every statement in this guide maps to an approved claim backed by a verified evidence row.
