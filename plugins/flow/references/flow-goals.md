# FlowGoal — completion contracts for the flow plugin

FlowGoal is the flow plugin's project-local replacement for Claude Code's session-only `/goal` built-in. Plugins cannot invoke `/goal` (no `SlashCommand` tool exists; the only post-turn hook is `Stop`), so flow ships its own file-backed equivalent.

## What a FlowGoal is

A FlowGoal is a durable, schema-validated YAML file at `.flow/goals/<id>.goal.yaml` that captures:

1. **Outcome** — one-sentence verifiable success statement
2. **Acceptance criteria** — list of ACs with `verification_command` and `must_pass` flags; criteria from the issue / PR / ad-hoc invocation
3. **Specification** — non-goals, failure modes, interface contracts, and the risk map (`risk_map`: one row per area with the plausible wrong version and the check that discriminates it) — all lifted from the journal section `specification-capture` writes; `risk_map` is omitted when the journal has no `### Risk map`
4. **Constraints** — denied paths, allowed paths, no-Tier-3-without-confirmation
5. **Evaluator binding** — which agent runs the satisfaction check, what context is denied to it
6. **Continuation policy** — what to do on incomplete/blocked/complete (mark achieved, escalate, etc.)
7. **Lifecycle** — current state machine position: `draft → active → {waiting_for_user, waiting_for_ci, blocked} → {achieved, failed, cancelled}`

The full schema lives at `plugins/flow/schemas/v1/goal.schema.json`.

## FlowGoals are on by default (v3.1)

As of v3.1, `/flow:start` records FlowGoals automatically — `flow.goals.goalCreation` defaults to `auto`. There is no opt-in prompt; goals, runs, and evidence are written to `.flow/` behind the scenes and surfaced through `/flow:status`. You interact with outcomes, not the runtime.

`goalCreation` is a 3-state setting in `.claude/settings.flow.json`:

```json
{
  "flow": {
    "goals": {
      "goalCreation": "auto",
      "executeVerificationCommands": false
    }
  }
}
```

- `goalCreation: auto` (default) — `/flow:start <issue>` creates `.flow/goals/issue-<N>.goal.yaml` **iff** the Spec Validation Gate passed with ≥1 acceptance criterion carrying a `verification_command` (labels do not veto). An issue that yields zero verifiable ACs (e.g. a spec-free `documentation`/`chore` issue) creates **no** goal, silently.
- `goalCreation: always` — create a goal unconditionally; a degenerate goal (no verifiable ACs) is allowed but flagged in the compact summary.
- `goalCreation: off` — never auto-create; manual `/flow:goal create` still works.
- `flow.goals.enabled: false` — disables the whole feature (Stop hook fast-paths, `/flow:goal` disabled). Distinct from `goalCreation: off`, which keeps the feature on and only suppresses auto-creation.
- `executeVerificationCommands: true` — lets the Stop hook's deterministic-checks runner execute every goal's `verification_command` strings, trusted or not. Governs only the Stop hook path (`hooks/scripts/flow-run-deterministic-checks.sh`); `/flow:goal evaluate` and `Skill(goal-evaluator)` execute verification commands when present regardless. You rarely need it: goals created through flow are recorded in the per-user **trust ledger** (`bin/flow-goal-trust.sh`, `${FLOW_STATE_DIR:-~/.claude/flow-state}/goal-trust.jsonl`) and the Stop hook executes a trusted goal's commands with the flag left `false`. A goal that arrived with a checkout is untrusted; its ACs are reported `not_executed` until you run `bin/flow-goal-trust.sh record --goal-file .flow/goals/<id>.goal.yaml` (also required after editing a `verification_command` by hand). Set the flag `true` only when every `.flow/goals/*.goal.yaml` source is trusted — the Stop hook fires on every turn, so unvetted commands run every turn.

> **Upgrading from the v3.0 `requireGoalForStart` flag?** It is mapped read-only — `true` → `always`, `false` → `off`, absent → `auto` — and your settings file is never rewritten. See `migration-v2-to-v3.md`.

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

State transitions are mediated through the `goal-lifecycle` skill — every transition writes a `goal-evaluation` artifact to the linked decision journal. The allowed-transition table, the disallowed transitions, and the evaluator's verdict → status mapping live in [`goal-lifecycle-transitions.md`](goal-lifecycle-transitions.md); `bin/flow-goal-record.sh` enforces the same table.

## Goal YAML example

```yaml
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: issue-42
  created_at: '2026-05-20T14:30:00Z'
  created_by: /flow:start
scope:
  repo: synaptiai/synapti-marketplace
  branch: feature/issue-42-search-fix
  issue: 42
  journal: .decisions/issue-42.md
objective:
  outcome: Issue #42 is implemented and verified.
  acceptance_criteria:
    - id: AC1
      text: Searching for an exact match returns the match.
      verification_command: npm test -- --grep search
      must_pass: true
      status: pending
      evidence_ref: null
specification:
  non_goals:
    - Do not refactor unrelated search index code.
  failure_modes:
    - timeout
    - malformed query
  interface_contracts:
    - 'search(q: string) -> Promise<Result[]>'
  risk_map:                       # lifted from the journal's "### Risk map" table; omitted when absent
    - area: query normalisation
      plausible_wrong_version: lowercasing the query also strips diacritics, so accented terms stop matching
      discriminating_check: search("café") returns the café record while search("cafe") does not
constraints:
  tdd_required: true
  require_all_pass: true
  no_calendar_estimates: true
  no_tier3_without_confirmation: true
  denied_paths: ['.env*', 'infra/prod/**']
evaluator:
  type: flow_verdict_judge
  command: /flow:goal evaluate
  judge_agent: goal-evaluator-judge
  evidence_bundle_format: plugins/flow/references/evidence-bundle-format.md
  denied_context: [implementation_rationale, self_review_findings]
continuation:
  mode: flow_managed
  on_incomplete: continue_next_activity
  on_blocked: six_field_escalation
  on_complete: mark_achieved
  max_iterations: 20
lifecycle:
  status: active
  current_phase: explore
  turns_evaluated: 0
  last_evaluation:
    result: incomplete
    reason: Goal created; evidence not yet collected.
    at: '2026-05-20T14:30:00Z'
```

Each `risk_map` row carries the three columns of the journal table (`Area | Plausible wrong version | Discriminating check`) as `area`, `plausible_wrong_version`, `discriminating_check`; all three are required and non-empty when the key is present. Goals written before the risk map existed simply lack the key.

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
| `warn` (default) | Runs deterministic checks; when the active goal lacks evidence it **allows the stop** with a reason that starts `FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)` and ends with how to enforce, printed to stderr too. Never blocks. | $0/turn | Most teams. Nudges without forcing. |
| `block` | Same checks; `decision:block` on failing ACs, path violations, or ACs with no `verification_command`, so the reason becomes the next-turn prompt. Verification commands run for trusted goals (trust ledger) without `executeVerificationCommands`; an untrusted goal's not-executed ACs never block on their own. Consecutive blocks per session and goal are capped at `failAfterStuckTurns`, then the stop is allowed with `FLOW_GOAL_BLOCK_CAP`. | $0/turn | Stricter UX. Keeps the agent working until the contract has evidence. |
| `evaluator-loop` | Active mode — spawns Haiku judge per turn; `decision:block` on `not_achieved` continues the agent loop | ~$0.001/turn | True Claude `/goal` UX parity. Opt-in. |

See `references/stop-hook-goal-enforcement.md` for the full Stop hook architecture, the trust ledger, the block cap, recursion guard, throttling, and budget enforcement.

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
| `flow.goals.goalCreation` | `auto` | `auto` (create iff ≥1 verifiable AC) \| `always` \| `off`. Replaces the deprecated `requireGoalForStart` (migrated read-only: `true`→`always`, `false`→`off`) |
| `flow.goals.stopHookEnforcement` | `warn` | `warn \| block \| evaluator-loop` |
| `flow.goals.failAfterStuckTurns` | `3` | evaluator-loop fails the goal after N turns of unchanged pass-set; `block` mode allows the stop (`FLOW_GOAL_BLOCK_CAP`) after N consecutive blocks |
| `flow.goals.executeVerificationCommands` | `false` | Stop hook runs every goal's `verification_command` strings, trusted or not. Normally unnecessary — trusted goals (trust ledger) already execute |
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

- **`/flow:start <issue>`** — under `goalCreation: auto` (default), creates `.flow/goals/issue-<N>.goal.yaml` after the Spec Validation Gate **iff** ≥1 AC carries a `verification_command`. Lifecycle stays `active` through Phase 4 (CODE, VERIFY); `verdict-judge` PASS transitions to `achieved`.
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
- `plugins/flow/bin/flow-goal-record.sh` — atomic goal writer (records the goal in the trust ledger on `--create`)
- `plugins/flow/bin/flow-goal-trust.sh` — per-user trust ledger: `record | check | list`
- `plugins/flow/references/goal-lifecycle-transitions.md` — transition tables and verdict → status mapping
- `docs/plans/flow-v3-goals-workflows-triggers-plan.md` — full v3 design (local-only; not committed)
