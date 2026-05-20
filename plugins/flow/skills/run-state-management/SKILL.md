---
name: run-state-management
description: "Manage FlowRun state at `.flow/runs/<ISO-timestamp-id>/run.yaml` — create runs at command entry, write activity records via `bin/flow-record-activity.sh` at phase boundaries, transition `state.status` (active → completed | blocked | cancelled), and persist resumable next-action hints to `events.jsonl`. Use when a flow command begins (creates the run), when a phase boundary completes (writes an activity), or when SessionEnd needs to mark a resumable next action. This skill MUST be consulted because runs without recorded activities cannot be resumed — `/flow:resume` reads `state.completed_activities[]` to identify the next safe action; an empty array forces the user to start over."
allowed-tools: Bash, Read, Write
context: fork
agent: general-purpose
---

# Run State Management

You own FlowRun durability. Every long-running flow command (start, debug, address, review, pr, merge, release) writes a `.flow/runs/<id>/run.yaml` at entry, appends an activity record at every phase boundary, and updates `state.status` on completion. Without this skill, runs are session-scoped and die when the conversation ends — defeating the resumability promise of the v3 runtime layer.

## Iron Law

**No phase transitions without an activity write. `state.completed_activities[]` is the source of truth for `/flow:resume` — a missing activity means the resume command will skip ahead and the user loses work.**

## Relationship to existing skills

This skill **wraps** `autonomous-workflow` (which encodes the phase structure of `/flow:start` and friends). It adds:
- Durable file-backed state (vs. session-only TODO tracking)
- Phase-boundary checkpointing (so resume can pick up mid-workflow)
- Audit trail via `.flow/runs/<id>/events.jsonl`

If `autonomous-workflow` says "next phase is VERIFY," this skill writes the corresponding activity YAML and updates `state.current_phase`.

## Inputs

The invoking command MUST pass:
1. **Workflow id** — `start-issue | debug | address-pr | review-pr | merge-pr | release` (matches the workflow YAML filenames under `plugins/flow/workflows/`).
2. **Run id** — typically `<ISO-8601-compact-timestamp>-<target-slug>` (e.g., `2026-05-20T143000Z-issue-42`).
3. **Context** — repo, branch, issue/pr number, linked journal path, linked goal id (when available).
4. **Phase** — initial phase id (`preflight`, `explore`, `plan`, `code`, `verify`).

## Outputs

1. `.flow/runs/<id>/run.yaml` — FlowRun document conforming to `schemas/v1/run.schema.json`.
2. `.flow/runs/<id>/activities/<NNN>-<name>.yaml` — activity records written per phase boundary.
3. `.flow/runs/<id>/events.jsonl` — line-per-event ledger.
4. `workflow-run` artifact appended to linked decision journal.

## Workflow

### Step 1: Create the FlowRun

When the command begins:

```bash
# Compose the FlowRun YAML
cat > /tmp/run.yaml <<EOF
apiVersion: flow.synapti.ai/v1
kind: FlowRun
metadata:
  id: ${RUN_ID}
  workflow: ${WORKFLOW_ID}
  workflow_version: 1
  goal: ${GOAL_ID:-null}
  created_at: ${NOW}
context:
  repo: ${REPO}
  branch: ${BRANCH}
  issue: ${ISSUE:-null}
  pr: ${PR:-null}
  journal: ${JOURNAL}
state:
  status: active
  current_phase: ${INITIAL_PHASE}
  current_activity: null
  completed_activities: []
  blocked_reason: null
limits:
  max_iterations: 10
  max_runtime_minutes: null
events:
  - at: ${NOW}
    type: run_started
EOF
```

Write to `.flow/runs/<id>/run.yaml` via direct file write (no atomic helper needed for the initial creation — race-free because the directory doesn't yet exist).

Append `workflow-run` artifact to the linked journal:
```bash
bin/journal-record.sh --issue ${N} --type workflow-run \
  --metadata workflow=${WORKFLOW_ID} \
  --metadata run_id=${RUN_ID} \
  --metadata status=active
```

### Step 2: Record activity at every phase boundary

At the end of each phase (or significant sub-step within a phase), compose a FlowActivity YAML and invoke `bin/flow-record-activity.sh`:

```bash
ACT_FILE=$(mktemp)
cat > "${ACT_FILE}" <<EOF
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  id: ${ACTIVITY_NAME}
  run_id: ${RUN_ID}
  workflow: ${WORKFLOW_ID}
  phase: ${PHASE}
activity:
  type: ${TYPE}              # bash | skill | agent | task | gate | evaluation
  name: '${HUMAN_NAME}'
  status: passed             # or running | failed | skipped | blocked
  started_at: ${START_TIME}
  completed_at: ${NOW}
outputs:
  evidence_refs: [${EVIDENCE_REF_LIST}]
  files_changed: [${FILES_LIST}]
  command_exit_code: ${EXIT_CODE}
result:
  summary: '${SUMMARY}'
  confidence: ${high|medium|low}
EOF

bin/flow-record-activity.sh --run-id ${RUN_ID} --activity-file "${ACT_FILE}"
rm "${ACT_FILE}"
```

The helper:
- Assigns the next sequence number (`001-`, `002-`, ...)
- Validates against `schemas/v1/activity.schema.json`
- Writes atomically (O_NOFOLLOW + flock + tempfile+rename)
- Appends one line to `events.jsonl`

### Step 3: Update FlowRun state.current_*

After each activity write, update `run.yaml` to reflect the new phase/activity:

```yaml
state:
  status: active
  current_phase: ${NEW_PHASE}      # advance if at phase boundary
  current_activity: ${NEXT_ACTIVITY_ID}
  completed_activities:
    - ${PRIOR_ACTIVITY_IDS}
    - ${JUST_RECORDED_ACTIVITY_ID}   # append the one we just wrote
```

This update is atomic via the same helper pattern: direct read-merge-write through Python with `_journal_atomic.py.acquire_lock(run.yaml.lock)`.

### Step 4: Transition to terminal state

When the command completes (success, failure, or cancellation):

```yaml
state:
  status: completed   # or failed, cancelled, blocked
  current_phase: <last>
  current_activity: <last>
  completed_activities: [...]
  blocked_reason: null   # set when status is blocked
```

Update the `workflow-run` journal artifact with the final status (via a second `journal-record.sh` call with the updated metadata).

### Step 5: SessionEnd persistence

When SessionEnd fires (separate hook: `session-end-state.sh`), if an active FlowRun exists:
- Append an event: `{type: session_end, at: <now>}`
- Set `state.blocked_reason: "session ended"` if no terminal transition happened
- Print a one-line notice: `Active FlowRun <id> persisted; use /flow:resume to continue`

## Phase order table

| Workflow | Phase order |
|---|---|
| `start-issue` | preflight → explore → plan → code → verify |
| `debug` | preflight → reproduce → diagnose → fix → verify |
| `address-pr` | preflight → categorize → resolve → verify |
| `review-pr` | preflight → fan-out → consolidate → report |
| `merge-pr` | preflight → verify → confirm → merge |
| `release` | preflight → bump → tag → push |

The machine-readable equivalents live at `plugins/flow/workflows/<id>.workflow.yaml`.

## Anti-patterns

- ❌ Writing `run.yaml` outside the helper or direct create — concurrent updates need flock.
- ❌ Updating `state.current_phase` without writing an activity — phases without activities can't be resumed.
- ❌ Marking `state.status: completed` while `completed_activities[]` is empty — implausible; the run did nothing.
- ❌ Reading from `events.jsonl` and trusting partial lines — readers MUST skip un-parseable trailing lines (atomicity at write time, tolerance at read time).
- ❌ Auto-resuming a `blocked` run without checking why it was blocked — surface the blocker first.

## Reuse map

- `plugins/flow/skills/autonomous-workflow/SKILL.md` — phase structure source of truth.
- `plugins/flow/bin/flow-record-activity.sh` — atomic activity writer.
- `plugins/flow/bin/_journal_atomic.py` — exposed `acquire_lock`, `_atomic_write` for run.yaml updates.
- `plugins/flow/schemas/v1/run.schema.json` — run document schema.
- `plugins/flow/schemas/v1/activity.schema.json` — activity document schema.
- `plugins/flow/references/decision-journal-schema.md` — `workflow-run` and `activity-completed` artifact-type rows.
