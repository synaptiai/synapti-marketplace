# Windows support policy

This marketplace ships plugins that run shell scripts. A plugin whose scripts
cannot run on a user's machine does not announce itself: Claude Code silently
skips a hook that fails to start, so a Windows user installing such a plugin
gets no journal entries, no destructive-command guard and no commit safety
check — and no error either. The failure looks exactly like the hooks having
nothing to say.

This document says what each plugin owes a Windows user, and how to prove it.

## The three surfaces

A plugin can reach the shell in three ways, and each needs its own answer.

| Surface | What it is | What Windows needs |
|---|---|---|
| `hooks.json` entries | Scripts Claude Code runs on tool and session events | A shell that can run them, or a per-hook `"shell": "powershell"` and a PowerShell implementation |
| `bin/` executables | Scripts commands invoke by path | The same shell, reached the same way |
| `` ```! `` blocks in skill and command markdown | Inline shell run at command time | The same shell; the block also has to survive the inline executor, which is not the same thing as being valid shell |

That last row is not theoretical. Claude Code hands an inline block to `bash -c`
as one string, and on Windows the executor mangles `#` comment handling: an
apostrophe inside a comment becomes a live quote character, and a block with an
unpaired one dies with `unexpected EOF while looking for matching '` before it
runs. Ten of flow's commands had that defect (issue #130). `bash -n` passes on
every one of them, so validity is not the property to check —
`plugins/flow/tests/review-gate-portability.test.sh` checks the right one.

## The three acceptable strategies

Pick one per plugin and declare it. Any of the three is acceptable; leaving it
unstated is not.

### 1. Git Bash required

The plugin ships POSIX shell scripts and states that a Windows user needs Git
for Windows installed. Claude Code uses Git Bash when it is present, so the
scripts run unmodified.

- **Cost to the user:** one install they very likely already have, since the
  plugins here are for people working with git.
- **Cost to the maintainer:** none beyond keeping the scripts portable, plus a
  CI job on a Windows runner so the claim is tested rather than asserted.
- **What it does not cover:** a Windows user without Git Bash. They must be told
  before installing, not after.

### 2. Native PowerShell

The plugin ships a `.ps1` alongside each script and declares
`"shell": "powershell"` on the relevant hooks, or uses the exec form with
`args`. Claude Code supports both.

- **Cost to the user:** none.
- **Cost to the maintainer:** two implementations of every guard, kept in step
  forever. For flow that would be 8 hooks and 24 `bin/` scripts, and the
  `` ```! `` blocks inside 29 files would still assume a POSIX shell.
- **When it is right:** a plugin with one or two small hooks.

### 3. Declared opt-out

The plugin states that it does not support Windows, in its `plugin.json`
description, so the text is visible in the marketplace listing before anyone
installs it.

- **Cost to the user:** they know, which is the whole point.
- **When it is right:** a plugin whose value is tied to a POSIX environment.

## What every plugin owes

1. **A declaration.** One of the three strategies, in the plugin's
   `plugin.json` description and its README. A user must be able to learn the
   answer before installing.
2. **Evidence, if it claims support.** A CI job on `windows-latest` that runs
   the plugin's hooks and reports. A claim of support with no Windows job is an
   assertion, and this policy exists because assertions about silent failures
   are worth nothing.
3. **No silent degradation.** Where a prerequisite is missing, say so on stderr
   once. Exiting 0 quietly is what made this invisible in the first place.

## Where each plugin stands

| Plugin | Ships | Strategy | Evidence |
|---|---|---|---|
| `flow` | 9 hooks, 24 `bin/` scripts, `` ```! `` blocks in 29 files | Git Bash required | `.github/workflows/windows-hooks.yml` runs `plugins/flow/tests/windows-hooks-smoke.sh` on `windows-latest` every time the hooks change |
| `dossier` | 1 hook, 20 `bin/` scripts, `` ```! `` blocks in 11 files | Git Bash required | Same workflow, same smoke check shape — tracked in its own issue |
| `agent-capability-standard` | 2 hooks | Undeclared | Sourced from its own repository (`synaptiai/agent-capability-standard`), not from this tree, so the change belongs there. Tracking issue filed |
| `decipon`, `gh-workflow`, `context-ledger`, `ai-first-org-design-kit`, `prompt-decorators` | No hooks, no `bin/`, no `` ```! `` blocks | Not applicable | Nothing reaches the shell |

## The reference implementation

`flow` is the worked example. What it does, which a plugin adopting strategy 1
should copy:

- **States the requirement where it is read.** `plugins/flow/README.md` lists
  `bash` alongside `git`, `gh`, `jq` and `python3`, and says what breaks without
  each. The `plugin.json` description names the Git Bash requirement so it shows
  in the marketplace listing.
- **Tests it on the platform.** `windows-hooks-smoke.sh` feeds each hook the
  payload the hook runner sends and checks the exit code, then parses every
  shipped script with `bash -n`. It runs on `windows-latest` under Git Bash, and
  on Ubuntu and macOS in the same job matrix so a regression is attributed to
  the platform rather than to the change.
- **Checks the inline blocks separately.** Validity is not portability;
  `review-gate-portability.test.sh` scans every `` ```! `` block in every
  command for the comment-apostrophe defect.
- **Degrades loudly.** Each hook checks for `jq`, `awk` and `python3` and says
  what it cannot do without them.

## Adding a plugin

If it ships a hook, a `bin/` script, or a `` ```! `` block:

1. Pick a strategy and write it in `plugin.json` and the README.
2. If the strategy is 1 or 2, add the plugin to the Windows workflow.
3. Add the plugin to the table above.

A plugin that ships shell and declares nothing is not ready to merge.
