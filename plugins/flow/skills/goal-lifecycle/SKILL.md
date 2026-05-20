---
name: goal-lifecycle
description: "Enforce the FlowGoal state machine — every status transition (draft → active → {waiting_for_user, waiting_for_ci, blocked, achieved, failed, cancelled}) writes both the new lifecycle block to `.flow/goals/<id>.goal.yaml` AND a `goal-evaluation` artifact to the linked decision journal, in a single atomic operation via `bin/flow-goal-record.sh`. Use when any code path mutates `lifecycle.status`, when /flow:goal pause/resume/clear is invoked, when the Stop hook detects a stuck pass-set, or when the evaluator returns a verdict. This skill MUST be consulted because state machines without recorded transitions become liars — a goal in `failed` status with no `goal-evaluation` artifact explaining why is worse than no state machine at all."
allowed-tools: Bash, Read, Edit
context: fork
agent: general-purpose
---

# Goal Lifecycle

You own the FlowGoal state machine. Every `lifecycle.status` transition is mediated through this skill — no exceptions, no shortcuts, no "I'll just edit the YAML directly."

## Iron Law

**No transition without an audit-trail entry. The decision journal MUST receive a `goal-evaluation` artifact (or `goal-created` for the initial draft→active) on every transition. A `lifecycle.last_evaluation` block without a matching journal entry is a bug.**

## State machine

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

Allowed transitions:

| From | To | Trigger |
|---|---|---|
| `draft` | `active` | `goal-contract-capture` completes; `/flow:goal create` returns |
| `active` | `waiting_for_user` | judge verdict `needs_human_review`; `AskUserQuestion` mid-evaluation |
| `active` | `waiting_for_ci` | CI run pending; goal waits on external signal |
| `active` | `blocked` | judge verdict `blocked` (with `blocker_type`); path-boundary violation |
| `active` | `achieved` | deterministic all-pass + (no fuzzy OR judge `achieved`) |
| `active` | `failed` | budget exhausted (max_iterations or max_runtime); stuck pass-set ≥ N turns; deterministic must_pass FAIL with no fix path |
| `active` | `cancelled` | user invokes `/flow:goal clear <id>` |
| `waiting_for_user` | `active` | `AskUserQuestion` resolves; user runs `/flow:goal resume` |
| `waiting_for_ci` | `active` | CI status transitions to terminal |
| `blocked` | `active` | blocker resolved (manual or `/flow:goal resume` after fix) |

**Disallowed transitions** (the helper rejects these):

- `terminal → any` — once `achieved/failed/cancelled`, the goal is immutable. New work requires a new goal id.
- `active → draft` — no going back to draft.
- `blocked → achieved` direct — must transition through `active` first (forces an evaluation step).

## Inputs

The invoking command/skill MUST pass:
1. **Goal id** — must point to an existing `.flow/goals/<id>.goal.yaml`.
2. **From state** — what the caller observed (used for race-detection).
3. **To state** — one of the enum values.
4. **Reason** — free-form string explaining why; surfaced in the journal artifact.
5. **Trigger** — `evaluator | command | hook | user`. Affects which journal artifact type is written.

## Outputs

1. Updated `.flow/goals/<id>.goal.yaml` with new `lifecycle.status`, `lifecycle.last_evaluation`, and (optionally) new `lifecycle.current_phase` / `current_activity`.
2. Decision journal artifact:
   - `goal-created` if from=`draft` to=`active`
   - `goal-evaluation` for all other transitions
3. One event line in `.flow/runs/<run-id>/events.jsonl` (when run_id is set).

## Workflow

### Step 1: Validate the transition

Read the current `.flow/goals/<id>.goal.yaml`. Compare `lifecycle.status` with the caller's `from` parameter:
- Match → proceed.
- Mismatch → race condition. Surface via six-field escalation: another process transitioned the goal between the caller's read and this skill's invocation.

Check the transition is allowed (per the table above). Reject disallowed transitions with stderr explanation and exit 1.

### Step 2: Compose new lifecycle block

```yaml
lifecycle:
  status: <to>
  current_phase: <preserved or updated by caller>
  current_activity: <preserved or updated by caller>
  turns_evaluated: <incremented if from active and to in {active, waiting_*, blocked}>
  last_evaluation:
    result: <maps to status: pass→achieved, incomplete→active, fail→active (with failing AC), blocked→blocked, needs_human_review→waiting_for_user>
    reason: <caller-provided>
    at: <ISO-8601 UTC now>
```

### Step 3: Write atomically

Invoke `bin/flow-goal-record.sh --update-lifecycle` with the new block. The helper:
- Acquires lockfile (`O_NOFOLLOW`)
- Reads the current YAML
- Merges the new lifecycle into the existing document (preserves all other fields)
- Validates against `schemas/v1/goal.schema.json` (when jsonschema available)
- Writes via tempfile + rename + fsync

### Step 4: Record the journal artifact

For `draft → active`:
```bash
bin/journal-record.sh --issue {N} --type goal-created \
  --metadata goal_id=<id> \
  --metadata source=<e.g., github_issue:42>
```

For all other transitions:
```bash
bin/journal-record.sh --issue {N} --type goal-evaluation \
  --metadata goal_id=<id> \
  --metadata result=<to-state> \
  --metadata reason=<short, comma-safe>
```

When the journal-issue link is unavailable (ad-hoc goals from `/flow:goal create` with no issue), write to a session-scoped journal (`.decisions/session-{YYYY-MM-DD}.md`) per the existing convention.

### Step 5: Append run event (if run_id is set)

```python
# Conceptually — actual call goes through bin/flow-record-activity.sh
# or a future bin/flow-record-event.sh
event = {
    "at": <now>,
    "type": "lifecycle_transition",
    "goal_id": <id>,
    "from": <from>,
    "to": <to>,
}
append_jsonl(f".flow/runs/{run_id}/events.jsonl", event)
```

## Anti-patterns

- ❌ Editing `.flow/goals/<id>.goal.yaml` outside `bin/flow-goal-record.sh` — race conditions, no audit trail.
- ❌ Transitioning a `terminal` goal back to `active` — by design impossible. New goal id required.
- ❌ Skipping the journal artifact "because the lifecycle block already records it" — the journal is the cross-PR audit trail; the goal YAML is local state. Both are needed.
- ❌ Bypassing the from-state check — race conditions silently lose evidence of prior transitions.
- ❌ Writing `last_evaluation.reason` as a free-form essay — keep it < 200 chars, comma-safe; full reasoning lives in the journal artifact body.

## Reuse map

- `plugins/flow/bin/flow-goal-record.sh` — atomic lifecycle writer.
- `plugins/flow/bin/journal-record.sh` — manifest artifact recorder.
- `plugins/flow/references/decision-journal-schema.md` — `goal-created` and `goal-evaluation` artifact-type rows.
- `plugins/flow/references/escalation-format.md` — six-field escalation for race-condition mismatches.
- `plugins/flow/schemas/v1/goal.schema.json` — lifecycle.status enum.
