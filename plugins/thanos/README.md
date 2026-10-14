# Thanos

A read-only reviewer that applies Steve Jobs's philosophy of simplicity to
code, designs and architecture. It removes everything that isn't essential
until what remains feels inevitable. It recommends; you decide. It never
edits files.

Internal, v0.1.

## Install

```bash
claude plugin marketplace add synaptiai/synapti-marketplace
claude plugin install thanos@synapti-marketplace
```

To try a local checkout instead: `claude --plugin-dir plugins/thanos`.

## Usage

| Command | Reviews |
| --- | --- |
| `/snap` | The current branch against its merge-base with the default branch, plus uncommitted and untracked changes |
| `/snap <ref range>` | That diff, e.g. `/snap main..HEAD` |
| `/snap <commit>` | That one commit |
| `/snap <file.md>` | The file as a design document, including a check for a non-goals section |
| `/snap <path>` | Those code files or that directory as they stand, not a diff |
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
through six lenses (**Soul, Mind, Reality, Space, Power, Time**), at most one
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

During the pilot, log every Snap item in the team's shared Thanos log:
the item, whether you **accepted**, **rejected** or **deferred** it, and a
one-line reason when you rejected it. That log decides what changes in
v0.2: mostly rejected means Thanos is too trigger-happy; rarely cutting
anything means it is too timid.

## Limits

- Read-only is enforced by the subagent's tool list (no Write or Edit) and
  its instructions for Bash. Claude Code cannot scope a plugin subagent's
  Bash to specific commands, so Bash read-only is a rule, not a sandbox;
  your normal permission prompts still apply.
- No CI, PR comments or automatic triggering in v0.1.

## Tests

```bash
plugins/thanos/tests/e2e.sh          # how /snap picks its target; no model calls
plugins/thanos/tests/e2e.sh --live   # also runs real reviews on the fixtures with `claude -p`
```

Each scenario writes an artifact (inputs, output, every check with PASS or
FAIL) to `THANOS_E2E_ARTIFACT_DIR`, or to a printed temporary directory.
The fixtures in `tests/fixtures/` cover an over-engineered change, a clean
one, a small one, one that adds validation and tests, and a design document
without non-goals.
