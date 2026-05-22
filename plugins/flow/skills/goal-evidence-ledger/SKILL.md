---
name: goal-evidence-ledger
description: "Maintain an append-only evidence ledger as `.flow/runs/<run-id>/evidence/*.evidence.yaml` sidecars (structured metadata) plus matching `.txt` raw-output captures, written exclusively via `bin/flow-record-evidence.sh`. Use when goal-evaluator runs a verification command, when a Stop hook captures a deterministic check, or when /flow:goal evaluate produces a judge report. This skill MUST be consulted because evidence-by-transcript dies with the session — only file-backed, schema-validated sidecars survive across sessions, prove ACs durably, and satisfy the verdict-judge's Independence Protocol (judges only see surfaced evidence, not free-form transcripts)."
allowed-tools: Bash, Read, Write
context: fork
agent: general-purpose
---

# Goal Evidence Ledger

You record evidence durably. Every assertion about an AC must be backed by a file-backed FlowEvidence sidecar — not a transcript message, not a console log that vanishes when the session ends, not an LLM's recollection. This skill enforces the **negative space** discipline from `evidence-based-development`: every evidence entry MUST declare what it does NOT prove.

## Iron Law

**No AC transitions to `pass` without a corresponding FlowEvidence sidecar. The sidecar's `proves: [<AC.id>]` field is the load-bearing link. Without it, the verdict-judge has no surfaced evidence to evaluate and falls back to transcript text — defeating the Independence Protocol.**

## Relationship to existing skills

This skill **wraps** `evidence-based-development` (which encodes ASSERTION/EVIDENCE/VERIFIED discipline). It adds:
- File-backed persistence (vs. transcript-only)
- Schema-validated structure (vs. free-form)
- Cross-session durability (vs. session-scoped)
- Concurrent-safe writes (via `_journal_atomic.py`)

If `evidence-based-development` has produced findings in a session, this skill **materializes** those findings as `.evidence.yaml` sidecars.

## Inputs

The invoking command/skill MUST pass:
1. **Evidence id** — typically `evidence-<AC.id>-<descriptor>-<turn>`. Lowercase + digits + `_-`.
2. **Evidence type** — one of the enum values from `evidence.schema.json` (command_result, test_result, lint_result, runtime_smoke_result, visual_result, git_diff, holdout_validation, verdict, human_approval, review_comment_snapshot, ci_status, llm_judge_report, artifact_check, path_boundary_check).
3. **Proves** — list of AC ids this evidence supports.
4. **Optional**: `command`, `exit_code`, raw output path, `limitations` list, `negative_cases` list.

## Outputs

1. `.flow/runs/<run-id>/evidence/<evidence-id>.evidence.yaml` — structured sidecar.
2. `.flow/runs/<run-id>/evidence/<evidence-id>.txt` — raw stdout/stderr capture (when applicable).
3. `evidence-captured` artifact in the linked decision journal.
4. One line appended to `.flow/runs/<run-id>/events.jsonl`.

## Workflow

### Step 1: Compose the FlowEvidence YAML

```yaml
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: <evidence-id>
  goal: <goal-id>
  run_id: <run-id>
  activity_id: <activity-id, if any>
  created_at: <ISO-8601 UTC>
evidence:
  type: <enum-value>
  command: <bash command, if applicable>
  exit_code: <captured, if command type>
  output_ref: <relative path to .txt, if captured>
  proves:
    - <AC.id>
  limitations:
    - <what this evidence does NOT prove — required for non-trivial evidence>
  negative_cases:
    - <adversarial cases or boundary conditions tested>
```

### Step 2: Negative space discipline

**Mandatory fields when applicable:**

| Evidence type | Mandatory negative-space field | Rationale |
|---|---|---|
| `command_result`, `test_result` | `limitations` | What the command did NOT test (other code paths, edge cases) |
| `runtime_smoke_result` | `limitations` + `negative_cases` | Smoke tests are inherently shallow; surface that explicitly |
| `visual_result` | `limitations` | Visual diffs don't catch behavior; name that |
| `holdout_validation`, `verdict` | none (already structured) | The verdict format owns its own negative space |
| `llm_judge_report` | `limitations` | LLM reasoning is fuzzy; surface confidence band |

A sidecar of type `command_result` without a `limitations` field is rejected by the schema (the rejection happens at write time, not at read time — fail fast).

### Step 3: Write the sidecar

Invoke `bin/flow-record-evidence.sh`:

```bash
bin/flow-record-evidence.sh \
  --run-id <run-id> \
  --evidence-file <path-to-composed-yaml> \
  --raw-output <path-to-stdout-capture>
```

The helper handles:
- Atomic write (tempfile + rename via `_journal_atomic.py`)
- Symlink defense (O_NOFOLLOW on lockfile + target)
- Schema validation (when `jsonschema` is available)
- Raw output copy alongside the sidecar

### Step 4: Record manifest artifact

```bash
bin/journal-record.sh --issue {N} --type evidence-captured \
  --metadata evidence_id=<id> \
  --metadata goal_id=<goal-id> \
  --metadata proves=<comma-list of AC ids>
```

### Step 5: Update the goal AC's `evidence_ref`

The `goal-evaluator` skill (the typical caller) updates the AC entry in `.flow/goals/<id>.goal.yaml` to point at the new sidecar:

```yaml
acceptance_criteria:
  - id: AC1
    text: '...'
    status: evidence_collected  # was: pending
    evidence_ref: .flow/runs/<run-id>/evidence/<evidence-id>.evidence.yaml
    last_evaluated_at: <now>
```

## Anti-patterns

- ❌ Writing evidence by `echo > .evidence.yaml` instead of via the helper — bypasses atomicity + schema validation.
- ❌ Omitting `limitations` on a `command_result` — claim without scope = useless evidence.
- ❌ Pointing two ACs to the same evidence file without `proves: [AC1, AC2]` — the link is bidirectional.
- ❌ Editing a sidecar in place — evidence is append-only; corrections are NEW sidecars (e.g., `evidence-AC1-retest-turn2`) and the AC's `evidence_ref` is updated to the new one. The old sidecar stays as audit trail.
- ❌ Writing evidence after a goal has transitioned to `achieved` — evidence is captured BEFORE the verdict, not after.

## Reuse map

- `plugins/flow/skills/evidence-based-development/SKILL.md` — ASSERTION/EVIDENCE/VERIFIED protocol.
- `plugins/flow/bin/flow-record-evidence.sh` — atomic writer.
- `plugins/flow/schemas/v1/evidence.schema.json` — sidecar schema.
- `plugins/flow/references/evidence-bundle-format.md` — bundle layout the verdict-judge consumes.
