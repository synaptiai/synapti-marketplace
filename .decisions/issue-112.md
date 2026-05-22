# Issue #112 — Configurable model for flow agent-team (Path A) review

Branch: `feature/issue-112-configurable-agentteam-model`

## Summary

Path A (agent-team) review in `/flow:review` spawns ~20 subagents, all `model: inherit`,
so an Opus session multiplies Opus-rate tokens ~4×. Make the Path A review-agent model
configurable via a settings key (cascade-resolved), default `sonnet`. Path B unchanged.

## Design decisions

- **Key**: top-level `agentTeamModel` in plugin `settings.json`, sibling of `agentTeams`
  (the model modifies the agent-teams feature). Resolved via the standard 4-tier cascade
  using `bin/cascade-resolve.sh` (local > project > user > plugin default), the same
  cascade `agentTeams` uses. Enum `["haiku","sonnet","opus","inherit"]`, default `sonnet`.
- **Mechanism**: the Path A gate in `commands/review.md` resolves the key into
  `AGENT_TEAM_MODEL`; A.1 and A.3 dispatches pass it as the per-invocation `model`
  parameter, which overrides each agent's `model: inherit` frontmatter
  (precedence: dispatch param > frontmatter > session). `inherit` → omit the param
  (reproduces pre-#112 behavior).
- **Documentation**: schema.json description cross-references `flow.goals.judge.model`;
  README + gate-configuration.md document the key next to `agentTeams`.

## Specification

### Non-goals
- Path B (single-session, default) review behavior is NOT changed — its agents keep inheriting the session model.
- Other agent-dispatching commands (start, pr, address, debug, design, brainstorm) are NOT changed.
- The two `Skill(holdout-validation)` invocations are NOT model-dispatched (skills run inline) — unaffected.
- No global "all subagents" model setting is introduced.

### Failure modes
- Invalid `agentTeamModel` value (typo, non-enum) → emit a clear WARN naming the value + allowed set, reject it, fall back to `sonnet` (NOT silent — AC6).
- `jq` not installed → `cascade-resolve.sh` returns the `--default sonnet` backstop.
- Per-source JSON parse error → `cascade-resolve.sh` emits per-source WARN and continues the cascade.

### Interface contracts
- New top-level settings key: `agentTeamModel` : enum `["haiku","sonnet","opus","inherit"]`, default `"sonnet"` (settings.json + schema.json).
- Path A gate emits `AGENT_TEAM_MODEL=<resolved-value>` (only when `USE_PATH_A=1`).
- Path A dispatches (A.1 paired reviewers, A.3 challenge rounds) carry `model=$AGENT_TEAM_MODEL`; when value is `inherit`, the `model` param is omitted.

<!-- auto-log: 2026-05-23 01:04 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-112.md -->

<!-- auto-log: 2026-05-23 01:06 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-agentteam-model.test.sh -->

<!-- auto-log: 2026-05-23 01:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/settings.json -->

<!-- auto-log: 2026-05-23 01:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/schema.json -->

<!-- auto-log: 2026-05-23 01:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 01:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 01:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 01:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-23 01:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/README.md -->

<!-- auto-log: 2026-05-23 01:07 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/README.md -->

<!-- auto-log: 2026-05-23 01:08 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/gate-configuration.md -->
