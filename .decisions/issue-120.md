---
issue: 120
created: '2026-05-25T16:04:58Z'
artifacts:
- type: goal-created
  captured_at: '2026-05-25T16:04:58Z'
  goal_id: issue-120
  source: issue
- type: goal-evaluation
  captured_at: '2026-05-25T16:11:30Z'
  goal_id: issue-120
  result: achieved
  evidence_bundle: .flow/runs/20260525T1810Z-issue-120-eval
  failures: none
---
# Issue #120 — `${ARGUMENTS%% *}` in command !-blocks expands to empty

**Branch**: `fix/issue-120-arguments-param-expansion`
**Type**: bug (flow plugin self-fix)

## Problem

Claude Code's slash-command preprocessor substitutes bare `$ARGUMENTS` and
`${ARGUMENTS}` (no operator), but NOT bash parameter expansions like
`${ARGUMENTS%% *}`. The bash interpreter then sees an undefined `ARGUMENTS`
variable and the expansion yields the empty string, so `ISSUE_NUM` ends up
empty and downstream gates (`PREFLIGHT_STATE`, `FLOW_GOAL_STATE`) silently
degrade to their no-issue paths even when the user passed a number.

Self-demonstrated this session: invoking `/flow:start <120 URL>` rendered
`ISSUE_NUM=` (empty), `PREFLIGHT_STATE=BLOCKED`, `RUN_ID=...issue-nonum`.

## Why it was never caught

The unit fixture `flow-start-onboarding.test.sh` ran the gate block as
`ARGUMENTS="42" bash -c "$BLOCK"` — injecting `ARGUMENTS` as a real bash env
var, so `${ARGUMENTS%% *}` expanded correctly *in the test*. The lint
`command-frontmatter.test.sh` Test 3 only checked that `$ARGUMENTS` was
*quoted* (word-split safety) and explicitly blessed `"${ARGUMENTS%% *}"` as
the "case-validated form". Neither test modeled Claude Code's text-only
substitution, so both stayed green while production was broken.

## Specification

### Non-goals
- Not changing the first-token extraction *semantics* (still strip trailing
  prose; still reject non-digit input where it was rejected before).
- Not the documentation-only alternative from the issue — the code refactor
  is definitive; docs alone leave the silent-degradation behavior.
- Not touching bare `$ARGUMENTS` uses in prose / agent-prompt strings (those
  are substituted correctly).

### Failure modes
- Lint over-matches and flags legitimate `${SOMEVAR%% *}` on non-ARGUMENTS
  vars → anchor strictly to `${ARGUMENTS<op>`.
- Refactor introduces an unquoted `$ARGUMENTS` → existing Test 3 still guards
  quoting; keep it.
- `_RAW` name collides with an existing var in a block → grep confirms no
  prior `_RAW` usage.

### Interface contract
Replace `ARG1="${ARGUMENTS%% *}"` with:
```bash
_RAW="$ARGUMENTS"        # Claude Code substitutes bare $ARGUMENTS
ARG1="${_RAW%% *}"       # bash parameter-expansion now hits a real var
```
Inline one-liner form (start.md:662) collapses to:
`_RAW="$ARGUMENTS"; ARG1="${_RAW%% *}"; case "$ARG1" in ...`

## Acceptance criteria (derived — issue had none)

| # | Criterion | Verification command |
|---|-----------|----------------------|
| 1 | No `${ARGUMENTS<op>}` param-expansion remains in flow command !-blocks | `grep -rn '\${ARGUMENTS[%#/^,:+@]' plugins/flow/commands/` → zero |
| 2 | Onboarding fixture simulates CC substitution, not env-var injection | `bash plugins/flow/tests/run.sh flow-start-onboarding.test.sh` |
| 3 | Static lint rejects the broken form (regression guard) | `bash plugins/flow/tests/run.sh command-frontmatter.test.sh` |
| 4 | Full flow test suite passes | `bash plugins/flow/tests/run.sh` |

Scope confirmed with user: **Full fix + regression guard** (all 7 commands +
fixture fix + lint guard).

<!-- auto-log: 2026-05-25 17:29 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-120.md -->

<!-- auto-log: 2026-05-25 17:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resolve.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/design.md -->

<!-- auto-log: 2026-05-25 17:32 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/brainstorm.md -->

<!-- auto-log: 2026-05-25 17:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-25 17:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:35 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-start-onboarding.test.sh -->

<!-- auto-log: 2026-05-25 17:42 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/comment_strip_hash_operator.md -->

<!-- auto-log: 2026-05-25 17:42 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-05-25 17:44 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/command-frontmatter.test.sh -->

<!-- auto-log: 2026-05-25 17:47 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-start-onboarding.test.sh -->

<!-- auto-log: 2026-05-25 17:47 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-start-onboarding.test.sh -->

<!-- auto-log: 2026-05-25 17:47 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-start-onboarding.test.sh -->

<!-- auto-log: 2026-05-25 17:48 commit "fix(flow): copy $ARGUMENTS into a local before bash parameter-expansion in command blocks" -->

<!-- auto-log: 2026-05-25 18:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-25 18:07 commit "fix(flow): copy $ARGUMENTS into a local before bash parameter-expansion in command blocks" -->

<!-- auto-log: 2026-05-25 18:34 Edit /Users/danielbentes/synapti-marketplace/.gitignore -->

<!-- auto-log: 2026-05-25 18:34 commit "chore(flow): add achieved FlowGoal contract for issue 120" -->
