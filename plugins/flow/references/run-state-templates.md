# Run State Templates

Reference for the `run-state-management` skill: the exact document shapes it writes under `.flow/runs/<id>/`. Both conform to the JSON Schemas at `plugins/flow/schemas/v1/run.schema.json` and `plugins/flow/schemas/v1/activity.schema.json`; the schemas win on any disagreement.

## FlowRun (`.flow/runs/<id>/run.yaml`)

Written once at command entry by a direct file write — race-free because the run directory does not exist yet. Every later mutation goes through `bin/_journal_atomic.py` (`acquire_lock(run.yaml.lock)` + atomic write).

```yaml
apiVersion: flow.synapti.ai/v1
kind: FlowRun
metadata:
  id: ${RUN_ID}                 # <ISO-8601-compact-timestamp>-<target-slug>, e.g. 2026-05-20T143000Z-issue-42
  workflow: ${WORKFLOW_ID}      # start-issue | debug | address-pr | review-pr | merge-pr | release
  workflow_version: 1
  goal: ${GOAL_ID:-null}        # linked FlowGoal id, or null
  created_at: ${NOW}
context:
  repo: ${REPO}
  branch: ${BRANCH}
  issue: ${ISSUE:-null}
  pr: ${PR:-null}
  journal: ${JOURNAL}           # linked decision journal path
state:
  status: active                # active | completed | failed | blocked | cancelled
  current_phase: ${INITIAL_PHASE}
  current_activity: null
  completed_activities: []
  blocked_reason: null          # set only when status is blocked
limits:
  max_iterations: 10
  max_runtime_minutes: null
events:
  - at: ${NOW}
    type: run_started
```

Journal artifact emitted alongside creation, and again on the terminal transition with the final `status`:

```bash
bin/journal-record.sh --issue ${N} --type workflow-run \
  --metadata workflow=${WORKFLOW_ID} \
  --metadata run_id=${RUN_ID} \
  --metadata status=active
```

## FlowActivity (`.flow/runs/<id>/activities/<NNN>-<name>.yaml`)

Composed to a temp file and handed to `bin/flow-record-activity.sh --run-id ${RUN_ID} --activity-file <path>`. The helper assigns the sequence number (`001-`, `002-`, ...), validates against `activity.schema.json`, writes atomically (O_NOFOLLOW + flock + tempfile+rename), and appends one line to `events.jsonl`.

```yaml
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  id: ${ACTIVITY_NAME}
  run_id: ${RUN_ID}
  workflow: ${WORKFLOW_ID}
  phase: ${PHASE}
activity:
  type: ${TYPE}                 # bash | skill | agent | task | gate | evaluation
  name: '${HUMAN_NAME}'
  status: passed                # running | passed | failed | skipped | blocked
  started_at: ${START_TIME}
  completed_at: ${NOW}
outputs:
  evidence_refs: [${EVIDENCE_REF_LIST}]
  files_changed: [${FILES_LIST}]
  command_exit_code: ${EXIT_CODE}
result:
  summary: '${SUMMARY}'
  confidence: ${high|medium|low}
```

## State update after each activity

```yaml
state:
  status: active
  current_phase: ${NEW_PHASE}          # advance at a phase boundary
  current_activity: ${NEXT_ACTIVITY_ID}
  completed_activities:
    - ${PRIOR_ACTIVITY_IDS}
    - ${JUST_RECORDED_ACTIVITY_ID}     # append the one just written
```

## Terminal transition

```yaml
state:
  status: completed                    # or failed | cancelled | blocked
  current_phase: <last>
  current_activity: <last>
  completed_activities: [...]
  blocked_reason: null                 # required text when status is blocked
```

## Phase order per workflow

| Workflow | Phase order |
|---|---|
| `start-issue` | preflight → explore → plan → code → verify |
| `debug` | preflight → reproduce → diagnose → fix → verify |
| `address-pr` | preflight → categorize → resolve → verify |
| `review-pr` | preflight → fan-out → consolidate → report |
| `merge-pr` | preflight → verify → confirm → merge |
| `release` | preflight → bump → confirm → tag |

Machine-readable equivalents: `plugins/flow/workflows/<id>.workflow.yaml`.
