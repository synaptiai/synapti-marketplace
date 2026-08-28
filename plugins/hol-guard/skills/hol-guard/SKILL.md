---
name: hol-guard
description: Use when setting up HOL Guard, protecting Claude Code or another detected local AI harness, reviewing Guard approvals, or verifying runtime protection before agent tools run.
license: Apache-2.0
---

# HOL Guard

HOL Guard is a local runtime safety layer for AI coding agents. Use it to detect supported harnesses, install Guard-owned protection, dry-run protected launches, review approval requests, and verify status before tools execute.

## Safety rules

- Never read `.env` files or expose secrets.
- Never bypass a Guard approval or claim a request was approved without evidence.
- Never claim a harness is protected until a Guard status or doctor command proves it.
- Prefer Guard-owned commands over hand-editing Claude Code or other harness configuration.
- Preserve existing user changes.

## Check and install

Probe the CLI directly:

```bash
hol-guard --version
```

If that command is unavailable and the user wants runtime protection, prefer an isolated install:

```bash
pipx install hol-guard
```

If `pipx` is unavailable, explain the recommended isolated installation path rather than silently changing the user's Python environment.

Then inspect the local environment:

```bash
hol-guard detect --json
hol-guard status
```

Use the detected harness name returned by HOL Guard rather than maintaining a hard-coded list in this skill.

## Protect Claude Code

For a Claude Code workspace, use the Guard-owned flow:

```bash
hol-guard bootstrap
hol-guard install claude-code
hol-guard run claude-code --dry-run
hol-guard run claude-code
hol-guard doctor claude-code --json
hol-guard status
```

Run the dry-run before the protected launch. Do not replace this flow with direct edits to Claude hooks or settings.

## Protect another detected harness

When `hol-guard detect --json` identifies another supported harness, substitute the exact detected harness identifier:

```bash
hol-guard bootstrap
hol-guard install <detected-harness>
hol-guard run <detected-harness> --dry-run
hol-guard run <detected-harness>
hol-guard doctor <detected-harness> --json
```

Do not guess a harness identifier.

## Review blocked work

Inspect requests and receipts before taking action:

```bash
hol-guard approvals
hol-guard approvals open <request-id>
hol-guard receipts
```

Use the request ID returned by `hol-guard approvals` when opening a pending request.

Terminal approval decisions require the specific request ID:

```bash
hol-guard approvals approve <request-id>
hol-guard approvals deny <request-id>
```

Only approve after reading the risk reason and understanding the requested scope.

## Diagnose and verify

Use Guard's own evidence surfaces:

```bash
hol-guard doctor
hol-guard detect --json
hol-guard status
hol-guard receipts
hol-guard inventory
hol-guard events
```

Report the command that ran, what Guard found, what remains blocked, and the exact next command when user action is required.
