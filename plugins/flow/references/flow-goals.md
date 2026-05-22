# FlowGoal — completion contracts for the flow plugin

FlowGoal is the flow plugin's project-local replacement for Claude Code's session-only `/goal` built-in. Plugins cannot invoke `/goal` (no `SlashCommand` tool exists; the only post-turn hook is `Stop`), so flow ships its own file-backed equivalent.

## What a FlowGoal is

A FlowGoal is a durable, schema-validated YAML file at `.flow/goals/<id>.goal.yaml` that captures:

1. **Outcome** — one-sentence verifiable success statement
2. **Acceptance criteria** — list of ACs with `verification_command` and `must_pass` flags; criteria from the issue / PR / ad-hoc invocation
3. **Specification** — non-goals, failure modes, interface contracts (lifted from `specification-capture` skill output)
4. **Constraints** — denied paths, allowed paths, no-Tier-3-without-confirmation
5. **Evaluator binding** — which agent runs the satisfaction check, what context is denied to it
6. **Continuation policy** — what to do on incomplete/blocked/complete (mark achieved, escalate, etc.)
7. **Lifecycle** — current state machine position: `draft → active → {waiting_for_user, waiting_for_ci, blocked} → {achieved, failed, cancelled}`

The full schema lives at `plugins/flow/schemas/v1/goal.schema.json`.

## Enabling v3 in your project

Flow v3 ships dormant by default — the feature flags default to `false` so v2 projects upgrade with zero behavioral change. To turn on FlowGoals for `/flow:start` and `/flow:pr` / `/flow:merge`, add to `.claude/settings.flow.json`:

```json
{
  "flow": {
    "goals": {
      "requireGoalForStart": true,
      "executeVerificationCommands": true
    }
  }
}
```

- `requireGoalForStart: true` — `/flow:start <issue>` auto-creates `.flow/goals/issue-<N>.goal.yaml` after the Spec Validation Gate.
- `executeVerificationCommands: true` — lets the Stop hook's deterministic-checks runner execute each AC's `verification_command` rather than reporting `not_executed`. Governs only the Stop hook path (`bin/flow-run-deterministic-checks.sh`); `/flow:goal evaluate` and `Skill(goal-evaluator)` execute verification commands when present regardless. Set `true` only when you trust the source of `.flow/goals/*.goal.yaml` (Stop hook fires on every turn — running unvetted commands every turn is a hostile-fork attack surface).

`/flow:start` will also prompt you the first time you run it in a project that has neither `.claude/settings.flow.json` nor `.flow/` — answer **Enable v3** and the same flags are written automatically.

See [`flow-goals-quickstart.md`](flow-goals-quickstart.md) for a 5-minute walkthrough on a synthetic issue, and [`migration-v2-to-v3.md`](migration-v2-to-v3.md) for the step-by-step v2 → v3 opt-in across all four feature areas (goals, Stop hook, workflows, triggers).

## Goal lifecycle

```
       ┌────────────────────────────────────────────────────────┐
       ▼                                                        │
   ┌───────┐                                                    │
   │ draft │──┐                                                 │
   └───────┘  │                                                 │
              ▼                                                 │
       ┌──────────┐                                             │
       │  active  │────────────────────────────┐                │
       └──────────┘                            │                │
        │  │  │  │                             │                │
        │  │  │  └─→ waiting_for_ci    ────────┤                │
        │  │  └────→ waiting_for_user  ────────┤                │
        │  └───────→ blocked           ────────┤                │
        │                                      ▼                │
        ├──────────────────────────────→  achieved              │
        ├──────────────────────────────→  failed                │
        └──────────────────────────────→  cancelled  ───────────┘

       Terminal: {achieved, failed, cancelled}
       Resumable: {waiting_for_user, waiting_for_ci, blocked}
```

State transitions are mediated through the `goal-lifecycle` skill — every transition writes a `goal-evaluation` artifact to the linked decision journal. See `plugins/flow/skills/goal-lifecycle/SKILL.md` for the full state machine + allowed-transition table.

## Commands

| Command | Purpose | Tier |
|---|---|---|
| `/flow:goal` (or `/flow:goal status`) | Show the active goal + AC pass/fail state | autonomous |
| `/flow:goal create <kind> [id]` | Create a goal from issue / PR-review / PR-address / adhoc | journal |
| `/flow:goal inspect <id>` | Read-only deep dump of a specific goal | autonomous |
| `/flow:goal evaluate <id>` | Run deterministic checks + (optional) judge; update lifecycle | journal |
| `/flow:goal pause <id>` | `active → waiting_for_user` | journal |
| `/flow:goal resume <id>` | `{waiting_for_user, waiting_for_ci, blocked} → active` | journal |
| `/flow:goal clear <id>` | `<any non-terminal> → cancelled` (requires confirmation) | journal |
| `/flow:goal history` | List all goals (active + terminal) | autonomous |

## Stop hook integration

The Stop hook (`hooks/scripts/flow-goal-stop.sh`) fires after every conversation turn. Three modes (configurable via `flow.goals.stopHookEnforcement`):

| Mode | Behavior | Cost | When to use |
|---|---|---|---|
| `warn` (default) | Reads `.flow/goals/*.goal.yaml`, runs deterministic checks, emits warning when active goal lacks evidence | $0/turn | Most teams. Nudges without forcing. |
| `block` | Same check, but uses `decision:block` to inject warning as next-turn prompt | $0/turn | Stricter UX. Forces evidence capture before continuing. |
| `evaluator-loop` | Active mode — spawns Haiku judge per turn; `decision:block` on `not_achieved` continues the agent loop | ~$0.001/turn | True Claude `/goal` UX parity. Opt-in. |

See `references/stop-hook-goal-enforcement.md` for the full Stop hook architecture, recursion guard, throttling, and budget enforcement.

## Verdict delta semantics

Every `/flow:goal evaluate` (and every Stop-hook evaluator-loop turn) produces a verdict with a `delta` field. It compares the current evaluation's pass-set against the previous verdict persisted at `.flow/runs/<run-id>/last-verdict.json`.

| Value | Meaning | Computed when |
|---|---|---|
| `made_progress` | At least one AC moved from a failing/pending state to a passing/evidence-collected state since the last verdict — OR the very first evaluation of a run (no prior verdict to compare against). | The deterministic checker observes an AC's `status` advancing; the judge sees stronger evidence than the prior bundle. |
| `unchanged` | The pass-set is identical to the previous turn's pass-set. | The evaluator can't see forward progress — the same ACs are still passing/failing. |
| `regressed` | An AC that previously passed is no longer passing. | The evaluator detects a step backward (test that used to be green is now red; evidence that was sufficient is no longer there). |

**Who consumes `delta`:**

- **Stuck detection** (`flow-goal-evaluator.sh` evaluator-loop mode): increments a per-run counter on `unchanged`; resets on `made_progress` or `regressed`. After `flow.goals.failAfterStuckTurns` consecutive `unchanged` (default 3), the goal transitions to `failed` with reason `stuck_no_progress`.
- **`/flow:learn` pattern analysis** (when `flow.goals.enabled: true`): counts `unchanged` runs and stuck-detection-fired events across goals to surface recurring stuck patterns.
- **`/flow:goal status`**: surfaces the latest verdict's delta in the output so the user sees what direction the goal is moving turn-over-turn.

**Where the value lives:** `.flow/runs/<run-id>/last-verdict.json` — the verdict file produced by `bin/flow-record-verdict.sh`. Schema enforces `delta ∈ {made_progress, unchanged, regressed}` at write time.

## Settings (cascade-resolved)

All settings live under `flow.goals.*` and resolve via `bin/cascade-resolve.sh` (highest priority first):

1. `.claude/settings.flow.local.json` (project-local, gitignored)
2. `.claude/settings.flow.json` (project-shared, committed)
3. `~/.claude/settings.flow.json` (user-global)
4. `plugins/flow/settings.json` (defaults)

| Key | Default | Description |
|---|---|---|
| `flow.runtime.enabled` | `true` | Master switch for `.flow/` runtime layer |
| `flow.goals.enabled` | `true` | Master switch for FlowGoal feature |
| `flow.goals.requireGoalForStart` | `false` | If `true`, `/flow:start` auto-creates a goal after Spec Validation Gate |
| `flow.goals.stopHookEnforcement` | `warn` | `warn \| block \| evaluator-loop` |
| `flow.goals.failAfterStuckTurns` | `3` | evaluator-loop fails goal after N turns of unchanged pass-set |
| `flow.goals.judge.model` | `haiku` | Judge subprocess model |
| `flow.goals.judge.timeoutSeconds` | `60` | Judge subprocess timeout |

The schema validation rules for these keys live in `plugins/flow/schema.json`.

## Gitignore policy

```
.flow/runs/             # gitignored — per-developer execution noise
.flow/evidence/         # gitignored — per-developer evidence captures
.flow/triggers/*.local.yaml  # gitignored — local trigger configs
.flow/goals/*.goal.yaml      # tracked — teams share goal contracts
.flow/workflows/*.workflow.yaml  # tracked
.flow/triggers/*.trigger.yaml    # tracked (non-.local variants)
```

Teams that want fully-private goals can add `.flow/goals/` to their personal `.gitignore`; the helper writes don't depend on git state.

## What FlowGoal explicitly does NOT do

These are non-goals — flow v3 makes no claim to provide them:

1. **Native /goal invocation** — plugins can't call Claude Code's built-in slash commands. FlowGoal is a replacement, not a wrapper.
2. **Exactly-once execution** — `.flow/runs/` writes are atomic per-file but flow makes no claim to deterministic replay or crash-safe distributed execution.
3. **Background execution** — the Stop hook fires inside the user's turn; goals don't run "in the background" without an external trigger (CI, cron, user-driven `/loop`).
4. **Tier 3 autonomy** — goals can never grant merge or release autonomy. Those remain AskUserQuestion-gated.

If your needs require any of the above, FlowGoal is the wrong primitive — escalate to a durable runtime adapter (github_actions, temporal) via `runtime_target`.

## Compose with other flow features

- **`/flow:start <issue>`** — when `requireGoalForStart: true`, creates `.flow/goals/issue-<N>.goal.yaml` after Spec Validation Gate. Lifecycle stays `active` through Phase 4 (CODE, VERIFY); `verdict-judge` PASS transitions to `achieved`.
- **`/flow:review <PR>`** — creates a `pr-<N>-review.goal.yaml` with review-checklist ACs.
- **`/flow:address <PR>`** — creates a `pr-<N>-address.goal.yaml` with one AC per unresolved finding.
- **`/flow:debug`** — Goal with `outcome: "The reported failure is reproduced, root-caused, and a fix is verified."` and ACs derived from the bug hypothesis.

## Architectural references

- `plugins/flow/skills/goal-contract-capture/SKILL.md` — captures the contract from inputs
- `plugins/flow/skills/goal-evaluator/SKILL.md` — runs deterministic checks + judge dispatch
- `plugins/flow/skills/goal-evidence-ledger/SKILL.md` — file-backed evidence sidecars
- `plugins/flow/skills/goal-lifecycle/SKILL.md` — state machine enforcement
- `plugins/flow/agents/goal-evaluator-judge.md` — Independent verdict judge
- `plugins/flow/schemas/v1/goal.schema.json` — schema definition
- `plugins/flow/hooks/scripts/flow-goal-stop.sh` — passive warn mode hook
- `plugins/flow/hooks/scripts/flow-goal-evaluator.sh` — opt-in active loop hook
- `plugins/flow/bin/flow-goal-record.sh` — atomic goal writer
- `docs/plans/flow-v3-goals-workflows-triggers-plan.md` — full v3 design (local-only; not committed)
