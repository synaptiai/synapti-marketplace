---
description: "Read interrupted FlowRun state and propose the next safe action. Use /flow:resume (no args) for the most-recent active run, or /flow:resume <run-id> for a specific run. Informational only — never auto-executes the next phase. The user decides whether to continue."
allowed-tools: Bash, Read, AskUserQuestion
---

# /flow:resume — pick up an interrupted FlowRun

When a session ends mid-workflow (interrupted, paused, blocked), `.flow/runs/<id>/run.yaml` persists with `state.status: active` (or `blocked`). This command reads that state and tells the user where to resume — without making the resume decision for them.

## Required Skills

- `run-state-management` — for reading the run document and computing next-action hints.

## Pre-flight

```bash
ENABLED=$("$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh" \
  --default "true" '.flow.runtime.enabled')
if [ "$ENABLED" != "true" ]; then
  echo "flow.runtime.enabled is false — /flow:resume requires the runtime layer." >&2
  exit 0
fi

if [ ! -d .flow/runs ]; then
  echo "No FlowRuns exist (.flow/runs/ not found). Start one via /flow:start, /flow:debug, etc."
  exit 0
fi
```

## Workflow

### Step 1: Identify the run

If `$ARGUMENTS` is supplied: use it as the run-id directly. Verify `.flow/runs/<id>/run.yaml` exists; error if not.

If no arguments: find the most-recently-modified `run.yaml` with `state.status` in `{active, blocked}`.

```bash
RUN_ID="$ARGUMENTS"  # bare form so Claude Code substitutes it (a default-operator form would NOT be substituted); empty when no arg passed
if [ -z "$RUN_ID" ]; then
  RUN_ID=$(python3 - <<'PYEOF'
import os, glob, sys, yaml
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
candidates = []
for run_yaml in glob.glob(".flow/runs/*/run.yaml"):
    try:
        with open(run_yaml) as f:
            data = yaml.safe_load(f) or {}
        status = (data.get("state") or {}).get("status")
        if status in ("active", "blocked"):
            mtime = os.path.getmtime(run_yaml)
            candidates.append((mtime, data.get("metadata", {}).get("id", "")))
    except Exception:
        continue
if candidates:
    candidates.sort(reverse=True)
    print(candidates[0][1])
PYEOF
  )
fi

if [ -z "$RUN_ID" ]; then
  echo "No active or blocked FlowRuns found. All runs are in terminal status."
  exit 0
fi
```

### Step 2: Read the run document

```bash
RUN_DIR=".flow/runs/$RUN_ID"
RUN_YAML="$RUN_DIR/run.yaml"

if [ ! -f "$RUN_YAML" ]; then
  echo "Run not found: $RUN_YAML" >&2
  exit 1
fi
```

### Step 3: Compute the resume report

Extract from `run.yaml`:
- `metadata.workflow` — which flow command was running
- `metadata.goal` — linked FlowGoal (if any)
- `state.status` — active or blocked
- `state.current_phase` — last phase the run was in
- `state.current_activity` — the activity that was either in progress or just completed
- `state.completed_activities[]` — what's already done
- `state.blocked_reason` (when blocked) — why the run paused

Read the last 5 lines of `events.jsonl` for additional context.

Read the linked goal (if any): `.flow/goals/<metadata.goal>.goal.yaml`. Show AC pass/fail state.

### Step 3.5: Detect unlinked working-tree changes (#111 AC-6)

Flow records its own artifacts under `.flow/` and the decision journal under `.decisions/`. **Any other tracked change in the working tree is "unlinked"** — most likely unrelated human work that `/flow:resume` must not silently fold into a continuation.

```!
# Treat any porcelain entry whose path is NOT under .flow/ or .decisions/ as
# unlinked. Conservative by design (#111 AC-6 chose the simple definition over
# diffing against the run's recorded paths): better to ask once too often than
# to absorb a human's unrelated edits into a resumed workflow.
UNLINKED=$(git -c core.quotePath=false status --porcelain 2>/dev/null | awk '
  { path = substr($0, 4) }
  { n = index(path, " -> "); if (n) path = substr(path, n + 4) }   # rename: take destination
  { sub(/^"/, "", path); sub(/"$/, "", path) }                     # unquote special-char paths
  path !~ /^\.flow\// && path !~ /^\.decisions\// { print path }
')
if [ -n "$UNLINKED" ]; then
  echo "FLOW_RESUME_UNLINKED=1"
  printf '%s\n' "$UNLINKED" | sed 's/^/  /'
else
  echo "FLOW_RESUME_UNLINKED=0"
fi
true
```

When `FLOW_RESUME_UNLINKED=1`, you MUST surface the listed paths and **ask before suggesting continuation** — do not jump to the Step 5 next-action suggestion. Use `AskUserQuestion`:

> Uncommitted changes exist that aren't linked to FlowRun `<RUN_ID>` (they're outside `.flow/` and `.decisions/`):
> `<the listed paths>`
>
> Options:
> 1. These belong to this run — continue (proceed to the resume suggestion)
> 2. These are unrelated work — I'll handle them separately (stop here; do not suggest continuation)
> 3. Cancel

Remain informational-only: even on Option 1, `/flow:resume` never auto-executes the next phase — it only unlocks the Step 5 suggestion. When `FLOW_RESUME_UNLINKED=0`, proceed normally.

### Step 4: Format the resume report

```
FlowRun: <RUN_ID>
Workflow: <metadata.workflow>
Status: <state.status>
Started: <metadata.created_at>

Current phase: <state.current_phase>
Current activity: <state.current_activity>

Completed activities (<N>):
  001-preflight_issue_start (passed)
  002-fetch_issue_context (passed)
  003-specification_capture (passed)
  ...

Linked FlowGoal: <metadata.goal>
  Outcome: <objective.outcome>
  AC state: <count> pass, <count> evidence_collected, <count> pending

Recent events:
  <last 5 lines from events.jsonl>

Blocked reason (when applicable): <state.blocked_reason>

Next safe action:
  <suggestion based on workflow + current_phase>
```

### Step 5: Next-action suggestion

Map `(workflow, current_phase, has_goal)` to a suggested next command:

| Workflow | Current phase | Has active goal | Suggested next |
|---|---|---|---|
| `start-issue` | `explore`, `plan` | yes | Continue: `/flow:start <issue>` re-enters at the same phase |
| `start-issue` | `code`, `verify` | yes | Resume coding; run `/flow:goal evaluate <goal-id>` after next change |
| `debug` | `reproduce`, `diagnose` | (any) | Continue: `/flow:debug` re-enters |
| `address-pr` | (any) | yes | `/flow:address <PR>` re-enters |
| `merge-pr` | `confirm` | yes | `/flow:merge <PR>` — requires the AskUserQuestion confirmation |
| (any) | (any) | no | Start a new goal: `/flow:goal create <kind>` first if needed |

When the run is `blocked` with a `blocked_reason`, the suggestion includes resolving the blocker first.

### Step 6: Optional AskUserQuestion

If the user explicitly wants to act on the resume rather than just inspect, offer the suggested next command via AskUserQuestion. Otherwise just print the report and exit.

## Anti-patterns

- ❌ Auto-executing the next phase. /flow:resume is informational; the user decides whether to continue.
- ❌ Suggesting continuation when unlinked working-tree changes exist (changes outside `.flow/` and `.decisions/`) without asking first (#111 AC-6). Flow must not absorb unrelated human work into a resumed run.
- ❌ Resuming a `blocked` run without surfacing the blocker. If the blocker is "needs CI to pass," running the next phase before CI passes will fail again.
- ❌ Resuming a run whose linked goal is `cancelled` or `failed`. Surface the goal's terminal state and recommend creating a new goal.
- ❌ Reading `events.jsonl` lines without tolerating partial reads. Per the helper's design, the last line may be incomplete if a writer was killed mid-line.

## Critical references

- `plugins/flow/skills/run-state-management/SKILL.md` — owns run state mutations.
- `plugins/flow/schemas/v1/run.schema.json` — run document schema.
- `plugins/flow/bin/flow-record-activity.sh` — activity writer (called by run-state-management).
- `plugins/flow/references/flow-runtime-state.md` — user-facing runtime layer doc.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read `.flow/runs/*/run.yaml` to identify active/blocked runs | 1 | Autonomous, read-only |
| Read `git status --porcelain` to detect unlinked working-tree changes | 1 | Autonomous, read-only |
| Read linked `.flow/goals/<id>.goal.yaml` for goal context | 1 | Autonomous, read-only |
| Read last N lines of `events.jsonl` for recent activity | 1 | Autonomous, read-only |
| Format and print resume report | 1 | Autonomous, output-only |
| Optional AskUserQuestion offering the suggested next command | 2 | Asks only if the user explicitly wants to act; outcome is the user's choice to invoke the next command (`/flow:resume` itself never auto-executes) |

`/flow:resume` is purely informational. It cannot modify run state, transition lifecycles, or invoke workflow phases — those happen only when the user explicitly invokes the suggested next command.
