---
name: goal-contract-capture
description: "Capture a FlowGoal contract as a project-local `.flow/goals/<id>.goal.yaml` file with outcome, acceptance criteria (with verification commands), specification elements (non-goals, failure modes, interface contracts), constraints, evaluator binding, continuation policy, and lifecycle frontmatter. Use when /flow:start passes the Spec Validation Gate, when /flow:goal create is invoked, or when /flow:review and /flow:address need a completion contract for a PR. This skill MUST be consulted because acceptance criteria alone do not constitute a contract — without an evaluator binding, boundaries, and lifecycle state, downstream phases cannot detect premature completion, the Stop hook cannot enforce evidence, and goals cannot resume across sessions."
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
context: fork
agent: general-purpose
---

# Goal Contract Capture

You produce a FlowGoal contract — a durable completion contract that turns acceptance criteria + specification into a machine-readable, file-backed artifact. This skill is the 5th invoker of the existing `specification-capture` pattern; it wraps that skill (does NOT replace it) and adds the goal-specific fields needed for evaluator/Stop-hook enforcement.

## Iron Law

**No `/flow:goal create` without a complete contract. No `.flow/goals/<id>.goal.yaml` without an evaluator binding. The contract is the source of truth for the Stop hook and `/flow:goal evaluate`; gaps here cascade into silent premature completion.**

## Relationship to existing skills

This skill is a **wrapper**, not a fork:

| Existing skill | What it gives us | What this skill adds |
|---|---|---|
| `specification-capture` | non-goals, failure modes, interface contracts | the `specification` block in the goal YAML |
| `criterion-verification-map` | per-AC verification commands + expected evidence | the `objective.acceptance_criteria[].verification_command` field |
| `evidence-based-development` | ASSERTION/EVIDENCE/VERIFIED discipline | the `evidence_ref` linking the AC back to a FlowEvidence sidecar |

If those skills have already produced their outputs (decision journal manifest entries), this skill **reads from them** rather than re-asking the user.

## Inputs

The invoking command MUST pass:

1. **Goal id** — typically `issue-{N}`, `pr-{N}-review`, `pr-{N}-address`, or an ad-hoc slug. Validated against the schema's `^[a-z0-9][a-z0-9-]{0,63}$` pattern.
2. **Scope** — `repo`, `branch`, optionally `issue` and/or `pr`, optionally a `journal` path (`.decisions/issue-{N}.md`).
3. **Source** — typically the GitHub issue body (parsed for AC) or the PR description (parsed for review/address scope).
4. **Invocation reason** — `start | goal-create | review | address`. Used to choose the right outcome template and the right `evaluator.type`.

## Outputs

Single file: `.flow/goals/<id>.goal.yaml` conforming to `plugins/flow/schemas/v1/goal.schema.json`. Written via `bin/flow-goal-record.sh` (atomic, O_NOFOLLOW-defended).

Plus: one `goal-created` artifact appended to the linked decision journal via `bin/journal-record.sh --type goal-created --metadata goal_id=<id> --metadata source=<src>`.

## Workflow

1. **Pre-flight check** — refuse if `.flow/goals/<id>.goal.yaml` already exists and `lifecycle.status` is not in `{cancelled, failed}`. Surface the existing goal to the user via the six-field escalation; never silently overwrite an active goal.

2. **Compose `metadata`**:
   ```yaml
   metadata:
     id: <derived-from-invocation>
     created_at: <ISO-8601 UTC now>
     created_by: <invoking command, e.g. /flow:start>
     owner: <git user.email or @me>
   ```

3. **Compose `scope`** — from inputs. Set `journal` to the linked decision journal path. Leave `run_id` empty until M3 wires FlowRun creation.

4. **Compose `objective`** — pull AC text + verification commands from the existing `criterion-verification-map` output. Each AC is one entry with `status: pending` and `evidence_ref: null` initially. The `outcome` is a one-sentence statement derived from invocation reason:
   - `start` → "Issue #{N} is implemented and verified."
   - `goal-create` → user-supplied via AskUserQuestion.
   - `review` → "PR #{N} review completed with findings posted or no-finding evidence recorded."
   - `address` → "All unresolved findings on PR #{N} are resolved, commented, or escalated."

5. **Compose `specification`** — lift from `specification-capture`'s journal entries:
   - `non_goals` from the `## Specification > ### Non-goals` body
   - `failure_modes` from `### Failure modes`
   - `interface_contracts` from `### Interface contracts`

   If any block is empty, raise the six-field escalation per `references/escalation-format.md` — do NOT silently fill with placeholders.

6. **Compose `constraints`** — default to `tdd_required: true`, `require_all_pass: true`, `no_calendar_estimates: true`, `no_tier3_without_confirmation: true`. Add `denied_paths` from settings (`flow.goals.denied_paths` cascade key); add `allowed_paths` only if the goal narrows the tier model (e.g., a focused refactor).

7. **Compose `evaluator`**:
   ```yaml
   evaluator:
     type: flow_verdict_judge          # hybrid for fuzzy criteria; deterministic for command-only
     command: /flow:goal evaluate
     judge_agent: goal-evaluator-judge
     evidence_bundle_format: plugins/flow/references/evidence-bundle-format.md
     denied_context:
       - implementation_rationale
       - self_review_findings
   ```

8. **Compose `continuation`** — defaults: `mode: flow_managed`, `on_incomplete: continue_next_activity`, `on_blocked: six_field_escalation`, `on_complete: mark_achieved`, `max_iterations: <from settings, default 20>`.

9. **Compose `lifecycle`** — initial state:
   ```yaml
   lifecycle:
     status: active
     current_phase: <derived; start→explore, review→fan-out, address→categorize>
     current_activity: <first activity id>
     turns_evaluated: 0
     last_evaluation:
       result: incomplete
       reason: "Goal created; evidence not yet collected."
       at: <now>
   ```

10. **Write atomically** — call `bin/flow-goal-record.sh` with the composed YAML. Verify exit 0; surface stderr on any failure.

11. **Record journal artifact** — `bin/journal-record.sh --issue {N} --type goal-created --metadata goal_id=<id> --metadata source=<src>`.

12. **Verify the artifact** — read back `.flow/goals/<id>.goal.yaml` and validate against the schema (Python jsonschema if available). A schema mismatch here means the skill or the schema is broken; fail hard.

## Per-invoker scope

| Invoker | Captures | Skips |
|---|---|---|
| `start` | All blocks; outcome derived from issue title | nothing |
| `goal-create` | All blocks; outcome from AskUserQuestion | journal manifest if no issue |
| `review` | Outcome + AC (= review checklist) + constraints | specification (use issue's existing capture) |
| `address` | Outcome + AC (= one per unresolved PR comment) + constraints | specification (inherit from review goal) |

## Anti-patterns

- ❌ Silently overwriting an active goal — always surface and escalate.
- ❌ Filling in empty specification blocks with placeholders — escalate via six-field.
- ❌ Bypassing `bin/flow-goal-record.sh` for "speed" — atomicity + symlink defense matters.
- ❌ Setting `lifecycle.status: achieved` at creation — the only way to `achieved` is through `/flow:goal evaluate`.

## Reuse map

- `plugins/flow/skills/specification-capture/SKILL.md` — read the per-invoker scope table; this skill adds row 5 (`goal-create`).
- `plugins/flow/skills/criterion-verification-map/SKILL.md` — read for the AC verification-command shape.
- `plugins/flow/schemas/v1/goal.schema.json` — the canonical schema this skill writes against.
- `plugins/flow/bin/flow-goal-record.sh` — atomic writer (M2 helper).
- `plugins/flow/bin/journal-record.sh` — for the `goal-created` manifest artifact.
- `plugins/flow/references/escalation-format.md` — six-field escalation for any empty/ambiguous block.
