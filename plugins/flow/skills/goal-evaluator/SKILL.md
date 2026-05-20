---
name: goal-evaluator
description: "Evaluate a FlowGoal against its evidence ledger and update lifecycle status to one of {pass, incomplete, fail, needs_human_review, blocked} by running deterministic verification commands first, then (when stopHookEnforcement=evaluator-loop or explicit /flow:goal evaluate invocation) dispatching the goal-evaluator-judge agent for fuzzy rubric criteria. Use when /flow:goal evaluate is invoked, when the Stop hook fires in evaluator-loop mode, or when /flow:start Phase 4 needs to convert AC evidence into a verdict. This skill MUST be consulted because lifecycle transitions without deterministic evidence enable silent premature completion — the goal contract is only as good as the evaluator that proves or disproves it."
allowed-tools: Bash, Read, Edit, Agent
context: fork
agent: general-purpose
---

# Goal Evaluator

You convert a goal's evidence ledger into a verdict and update the goal's lifecycle. This skill wraps `criterion-verification-map` (which produces per-AC commands at plan time) and adds the loop-time evaluation: run the commands, capture evidence, judge satisfaction, transition state.

## Iron Law

**Deterministic checks beat LLM judgment when they apply. The LLM judge runs only when the contract has fuzzy rubric criteria that no command can prove. Always run deterministic checks first; never substitute judge output for a runnable command's exit code.**

## Inputs

The invoking command/hook MUST pass:
1. **Goal id** — `<id>` such that `.flow/goals/<id>.goal.yaml` exists with `lifecycle.status == active` (or `waiting_for_user`, `waiting_for_ci`, `blocked` — evaluator can resurrect these on resume).
2. **Run id** — for evidence ledger writes (`.flow/runs/<run-id>/evidence/`). If absent, evaluator infers from the goal's `scope.run_id`.
3. **Trigger** — `manual | stop-hook | command`. Affects whether judge subprocess runs (Stop hook in `evaluator-loop` mode auto-runs judge; `manual` invocation runs judge per the goal's `evaluator.type`).

## Outputs

1. Updated `.flow/goals/<id>.goal.yaml` with new `lifecycle.last_evaluation` and possibly new `lifecycle.status`.
2. New `*.evidence.yaml` sidecars under `.flow/runs/<run-id>/evidence/` for each verification command run.
3. `goal-evaluation` artifact appended to the linked decision journal.
4. Updated AC entries: `status` transitions from `pending → evidence_collected → pass | fail`; `evidence_ref` set to the new sidecar path.

## Workflow

### Step 1: Load contract + ledger

Read `.flow/goals/<id>.goal.yaml`. Verify schema. Read existing evidence sidecars under `.flow/runs/<run-id>/evidence/` for any AC with `evidence_ref` already set.

### Step 2: Run deterministic checks

For each AC where `verification_command` is set and `must_pass` is true OR all-pass evaluation is required:

```bash
# Capture stdout + exit code
OUTPUT=$(mktemp)
bash -c "${AC.verification_command}" > "$OUTPUT" 2>&1
EXIT_CODE=$?
```

Then assemble a FlowEvidence YAML and write via `bin/flow-record-evidence.sh`:

```yaml
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: evidence-<AC.id>-eval-<turn>
  goal: <goal-id>
  run_id: <run-id>
  created_at: <now>
evidence:
  type: command_result
  command: <AC.verification_command>
  exit_code: <captured>
  output_ref: <relative path to .txt copy>
  proves:
    - <AC.id>
  limitations:
    - <list from criterion-verification-map's "Does NOT promise" field if present>
```

Update the AC entry: `status: evidence_collected`, `evidence_ref: <sidecar path>`, `last_evaluated_at: <now>`, `last_result: <exit-code or summary>`.

### Step 3: Deterministic verdict

After all deterministic checks:
- All AC with `must_pass: true` have `exit_code == 0` → status candidate = `pass`.
- Any `must_pass: true` AC with `exit_code != 0` → status candidate = `fail`.
- AC missing `verification_command` (= fuzzy criterion) → status candidate = `incomplete` (LLM judge required).

### Step 4: Path-boundary check

If the goal has `constraints.allowed_paths`, run `git diff --name-only` (current branch vs. base). Any modified file outside `allowed_paths` → emit a `path_boundary_check` FlowEvidence with `proves: []` and the violating filenames; transition status to `blocked` with reason `path_boundary_violation`.

### Step 5: LLM judge (conditional)

Run the judge subprocess ONLY when:
- `evaluator.type == hybrid` AND deterministic candidate is `incomplete` (= fuzzy criteria remain), OR
- `evaluator.type == flow_verdict_judge` and the user explicitly invoked `/flow:goal evaluate` (manual review).

Spawn `Agent(goal-evaluator-judge)` with:
- The goal's outcome + AC table
- The just-written evidence sidecars (paths only — the judge reads them itself)
- The transcript-level evidence bundle (Bundle format: `plugins/flow/references/evidence-bundle-format.md`)
- The `denied_context` list (passed verbatim)

The judge returns verdict + confidence + delta + next_step_hint as a structured table.

### Step 6: Compose lifecycle update

| Deterministic candidate | Judge verdict | Final lifecycle.status |
|---|---|---|
| `pass` (all must_pass green, no fuzzy) | (judge skipped) | `achieved` |
| `pass` + fuzzy criteria | `achieved` | `achieved` |
| `pass` + fuzzy criteria | `not_achieved` | `active` (continue) |
| `fail` | (judge may run for context) | `active` (continue, surface failing AC) |
| `incomplete` | `not_achieved` | `active` |
| `incomplete` | `blocked` (with blocker_type) | `blocked` |
| `incomplete` | `needs_human_review` | `waiting_for_user` |
| `path_boundary_violation` | (judge skipped) | `blocked` |

Update `lifecycle.status`, `lifecycle.turns_evaluated += 1`, `lifecycle.last_evaluation = {result, reason, at}`. Write back via `bin/flow-goal-record.sh`.

### Step 7: Record manifest artifact

```bash
bin/journal-record.sh --issue {N} --type goal-evaluation \
  --metadata goal_id=<id> \
  --metadata result=<lifecycle.status> \
  --metadata evidence_bundle=<run-dir relative path> \
  --metadata failures=<comma-list of failing AC ids or 'none'>
```

### Step 8: Persist the verdict for next-turn delta (MANDATORY, non-fatal)

Write the structured verdict to `.flow/runs/<run-id>/last-verdict.json` via `bin/flow-record-verdict.sh`. Without this step, the next evaluator-loop turn (or the next manual evaluation) cannot compute `delta` against a previous state — every turn becomes "unchanged" and the stuck-detection in Step 9 is broken.

```bash
TMP=$(mktemp -t flow-verdict.XXXXXX.json)
trap 'rm -f "$TMP"' EXIT
jq -n \
  --arg v "<verdict>" \
  --argjson c <confidence> \
  --arg d "<delta>" \
  --arg r "<reason>" \
  --arg h "<next_step_hint>" \
  '{verdict:$v, confidence:$c, delta:$d, reason:$r, next_step_hint:$h, source:"skill"}' > "$TMP"
bin/flow-record-verdict.sh --run-id "<run-id>" --verdict-file "$TMP" \
  || echo "skill: last-verdict.json write failed; next turn's delta will be 'unchanged'" >&2
```

**Contract** (resolves the prior "MANDATORY heading vs SHOULD body" ambiguity):
- The step is **MANDATORY**: every verdict-producing path MUST invoke this helper.
- The step is **non-fatal**: a helper failure (malformed JSON, symlink rejected, disk full) MUST surface to stderr via the `||` clause shown above, MUST NOT retry within the same turn, and MUST NOT abort the calling skill or hook. The in-memory verdict for this turn is still correct; only the next turn loses delta semantics.
- When called from `flow-goal-evaluator.sh` (evaluator-loop mode), the hook already invokes the helper after the judge subprocess returns — Step 8 in that path is a SKIP, not a double-write. Detect via the `CLAUDE_HOOK_GOAL_JUDGE_MODE=true` environment variable that the evaluator-loop sets in subprocesses.

### Step 9: Stuck detection (Stop-hook evaluator-loop mode only)

If `trigger == stop-hook` AND the new pass-set hash matches the previous turn's hash for `flow.goals.failAfterStuckTurns` consecutive turns (default 3), transition status to `failed` with reason `stuck_no_progress`. This prevents the evaluator loop from churning indefinitely on a goal that can't make forward progress.

## Anti-patterns

- ❌ Running LLM judge when deterministic checks suffice — costs money, slower, less reliable.
- ❌ Updating `lifecycle.status` without writing a `goal-evaluation` artifact — breaks audit trail.
- ❌ Marking an AC as `pass` without an `evidence_ref` — bypasses the evidence ledger.
- ❌ Skipping path-boundary check when `allowed_paths` is set — goals exist to fence scope.

## Reuse map

- `plugins/flow/skills/criterion-verification-map/SKILL.md` — AC → verification command shape.
- `plugins/flow/agents/verdict-judge.md` — independence protocol the LLM judge inherits.
- `plugins/flow/agents/goal-evaluator-judge.md` — the specialized judge this skill dispatches.
- `plugins/flow/bin/flow-record-evidence.sh` — atomic evidence sidecar writes.
- `plugins/flow/bin/flow-goal-record.sh` — atomic goal lifecycle updates.
- `plugins/flow/bin/flow-record-verdict.sh` — last-verdict.json producer; Step 8 invokes this.
- `plugins/flow/references/evidence-bundle-format.md` — canonical evidence layout.
