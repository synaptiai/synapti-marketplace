# Thanos

A read-only reviewer that applies Steve Jobs's philosophy of simplicity to
code, designs and architecture. It reviews a diff, a design document or
code and lists what can be removed, merged or simplified, with a simpler
alternative for each. It recommends; you decide. It never edits files.

Version 0.1.

## Install

```bash
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install thanos@synapti-marketplace
```

To try a local checkout instead: `claude --plugin-dir plugins/thanos`.

Requires `bash` and `git`. On Windows, run Claude Code with Git Bash.

## Usage

| Command | Reviews |
| --- | --- |
| `/snap` | The current branch against its merge-base with the default branch, plus uncommitted and untracked changes |
| `/snap <ref range>` | That diff, e.g. `/snap main..HEAD` |
| `/snap <commit>` | That one commit; a merge commit against its first parent |
| `/snap <file.md>` | The file as a design document, including a check for a non-goals section |
| `/snap <path>` | That code file or directory as it stands, not a diff |
| `/rethink <path or description>` | The subsystem from scratch: the smallest version that delivers its essence, and a safe stepwise path there |

If another plugin also has a `/snap` or `/rethink`, use `/thanos:snap` and
`/thanos:rethink`. You can also ask for a Thanos review in plain words; the
`thanos` subagent picks it up.

The default branch is detected (the remote's `HEAD`, then
`init.defaultBranch`, then `main` or `master`), not assumed. When there is
nothing to review, `/snap` says so in one line and stops.

## What you get

Every review has the same shape: the **essence** in one sentence, **The
Snap** (what to remove, merge or collapse, each with why it probably exists,
the cost of removing it, the simpler alternative and a confidence), findings
under six stones, each a lens on the work (**Soul, Mind, Reality, Space,
Power, Time**), at most one
out-of-scope note, and a **verdict**:

- **INEVITABLE**: ship it.
- **UNBALANCED**: sound direction, needs rework; the path is given.
- **SNAP**: rethink the approach; the simpler one is named.

Thanos never proposes removing security, input validation, error handling,
tests, data integrity, accessibility, production observability or
compliance work. It may propose simpler ways to do them.

The method lives in one place, [`skills/thanos-doctrine/SKILL.md`](skills/thanos-doctrine/SKILL.md).
The subagent and commands only decide what to review and how to show it.

## Example

A review of a hypothetical PR that adds response caching. This is the
target quality and length.

```markdown
# Thanos review: feat/response-cache (14 files, +620 / -40)

**Essence:** Make repeated identical API calls return instantly without
hitting the model provider.

## The Snap
1. CacheStrategy interface with three implementations (LRU, TTL, LFU)
   - only TTL is used anywhere. Exists because: flexibility for future
   needs. Cost: low, nothing calls the other two. Instead: one TTL cache
   class; add another strategy when a second real need appears.
   Confidence: high
2. cache.yaml with 9 options - 7 are never read. Exists because: mirrors
   the strategy interface. Cost: low. Instead: two settings (enabled,
   ttl_seconds) in existing config. Confidence: high

## Stones
**Reality** (high): `get_or_compute()` silently swallows provider
errors and caches None, so failures look like empty successes. Raise,
and never cache failed calls.
**Mind** (medium): cache keys are built in three places with slightly
different normalisation. One key function, one home.

## Verdict: UNBALANCED
Right idea, about three times the needed surface. Collapse to one TTL
cache with one key function and fix the error path, and it is
inevitable.
```

Note what it does not do: no style nits, no praise padding, no suggestion
to remove the error handling, and every cut names the simpler alternative.

## Giving feedback

While you try Thanos, keep a log of every Snap item wherever your team
tracks feedback: the item, whether you **accepted**, **rejected** or
**deferred** it, and a one-line reason when you rejected it. That log
decides what changes in v0.2: mostly rejected means Thanos is too
trigger-happy; rarely cutting anything means it is too timid.

## Limits

- Read-only is enforced by the subagent's tool list (no Write or Edit) and
  its instructions for Bash. Claude Code cannot scope a plugin subagent's
  Bash to specific commands, so Bash read-only is a rule, not a sandbox;
  your normal permission prompts still apply. Even read-only git commands
  can write a file (`git diff --output=<file>`), so a permission rule such
  as `Bash(git diff:*)` does not by itself stop writes.
- `/snap` never pastes your argument into shell text. Its built-in step
  runs only with no argument; with one, Claude runs the target script with
  the argument as a single quoted word, which your permission rules see.
  The git command it hands the reviewer holds only commit ids, and paths
  are read with the Read tool.
- No PR comments or automatic triggering in v0.1.
- Windows is not tested. The plugin declares Git Bash as its Windows
  requirement, but its tests run only on Linux and macOS in CI.

## Tests

```bash
plugins/thanos/tests/e2e.sh          # how /snap picks its target; no model calls
plugins/thanos/tests/e2e.sh --live   # also runs real reviews on the fixtures with `claude -p`
```

Each scenario writes an artifact (inputs, output, every check with PASS or
FAIL) to `THANOS_E2E_ARTIFACT_DIR`, or to a printed temporary directory.
CI runs the first command on Linux and macOS for every pull request that
touches the plugin.
The fixtures in `tests/fixtures/` cover an over-engineered change, a clean
one, a small one, one that adds validation and tests, and a design document
without non-goals.
