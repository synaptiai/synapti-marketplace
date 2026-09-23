---
description: "Read interrupted FlowRun state and propose the next safe action. Use /flow:resume (no args) for the most-recent active run, or /flow:resume <run-id> for a specific run. Informational only — never auto-executes the next phase. The user decides whether to continue."
allowed-tools: Bash, Read, AskUserQuestion
---

# /flow:resume — pick up an interrupted FlowRun

When a session ends mid-workflow (interrupted, paused, blocked), `.flow/runs/<id>/run.yaml` persists with `state.status: active` (or `blocked`). This command reads that state and tells the user where to resume — without making the resume decision for them.

## Required Skills

- `run-state-management` — for reading the run document and computing next-action hints.

```!
# Inline the Required Skills above so their rules are in context before the
# first phase runs (commands cannot preload skills from frontmatter). Ambient
# skills load whole; dispatched skills (context: fork / agent:) load their
# `## Contract` section and run in full when this command invokes
# Skill(<name>). Output per `references/command-output-format.md`.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-load-skills.sh" run-state-management

true
```

## Pre-flight

```bash
ENABLED=$("$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh" \
  --default "true" '.flow.runtime.enabled')
if [ "$ENABLED" != "true" ]; then
  printf '%s\n' "flow.runtime.enabled is false — /flow:resume requires the runtime layer." >&2
  exit 0
fi

if [ ! -d .flow/runs ]; then
  printf '%s\n' "No FlowRuns exist (.flow/runs/ not found). Start one via /flow:start, /flow:debug, etc."
  exit 0
fi
```

## Workflow

### Step 1: Identify the run

If `$ARGUMENTS` is supplied: use it as the run-id directly. Verify `.flow/runs/<id>/run.yaml` exists; error if not.

If no arguments: find the most-recently-modified `run.yaml` with `state.status` in `{active, blocked}`.

```bash
# RESUME_SCAN_BLOCK_BEGIN
RUN_ID="$ARGUMENTS"  # bare form so Claude Code substitutes it (a default-operator form would NOT be substituted); empty when no arg passed
RUN_SCAN_STATE=""
if [ -z "$RUN_ID" ]; then
  # A run.yaml the scan cannot read is not a run in a terminal status. Skipping
  # the unreadable ones and then announcing "All runs are in terminal status"
  # asserts about every skipped file the one thing the scan never established.
  RUN_SCAN=$(python3 - <<'PYEOF'
import os, glob, sys, yaml
sys.path[:] = [p for p in sys.path if p not in ("", ".")]


def one_line(v):
    return " ".join(str(v).splitlines()).strip()[:200]


candidates = []
unreadable = []
for run_yaml in sorted(glob.glob(".flow/runs/*/run.yaml")):
    try:
        with open(run_yaml, encoding="utf-8") as f:
            data = yaml.safe_load(f)
        if data is None:
            data = {}
        if not isinstance(data, dict):
            raise ValueError("the run is not a mapping")
        state = data.get("state")
        if state is None:
            state = {}
        if not isinstance(state, dict):
            raise ValueError("state is not a mapping")
        if state.get("status") in ("active", "blocked"):
            metadata = data.get("metadata")
            if metadata is None:
                metadata = {}
            if not isinstance(metadata, dict):
                raise ValueError("metadata is not a mapping")
            run_id = metadata.get("id")
            # A run that is active but carries no id cannot be resumed and
            # cannot be named. Appended as a blank candidate it emptied RUN_ID,
            # and the caller then said every run had reached a terminal status.
            if not run_id:
                raise ValueError("the run is active but carries no metadata.id")
            candidates.append((os.path.getmtime(run_yaml), str(run_id)))
    except Exception as exc:
        unreadable.append("RUN_UNREADABLE=%s — %s" % (run_yaml, one_line(exc)))

for line in unreadable:
    print(line)
if candidates:
    candidates.sort(reverse=True)
    print("STATE=ok")
    print("RUN_ID=%s" % candidates[0][1])
elif unreadable:
    print("STATE=unavailable")
    print("REASON=%d run file(s) could not be read, so whether every run has finished is unknown" % len(unreadable))
else:
    print("STATE=none")
PYEOF
  ); RUN_SCAN_EXIT=$?
  # A scan that died (python3 or PyYAML missing, interpreter killed) prints
  # nothing at all, which reads exactly like "every run has finished".
  if [ "$RUN_SCAN_EXIT" -ne 0 ] || [ "$(printf '%s\n' "$RUN_SCAN" | grep -c '^STATE=')" != "1" ]; then
    RUN_SCAN="STATE=unavailable
REASON=the run scan did not complete (exit $RUN_SCAN_EXIT), so whether every run has finished is unknown"
  fi
  printf '%s\n' "$RUN_SCAN"
  RUN_SCAN_STATE=$(printf '%s\n' "$RUN_SCAN" | sed -n 's/^STATE=//p' | head -1)
  RUN_ID=$(printf '%s\n' "$RUN_SCAN" | sed -n 's/^RUN_ID=//p')
fi

if [ -z "$RUN_ID" ]; then
  if [ "$RUN_SCAN_STATE" = "unavailable" ]; then
    printf '%s\n' "No resumable FlowRun was identified, and the run files named above could not be read — whether they are in a terminal status is unknown."
  else
    printf '%s\n' "No active or blocked FlowRuns found. All runs are in terminal status."
  fi
  exit 0
fi
# RESUME_SCAN_BLOCK_END
```

### Step 2: Read the run document

```bash
RUN_DIR=".flow/runs/$RUN_ID"
RUN_YAML="$RUN_DIR/run.yaml"

if [ ! -f "$RUN_YAML" ]; then
  printf '%s\n' "Run not found: $RUN_YAML" >&2
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

### Step 3.5: Detect unlinked working-tree changes

Flow records its own artifacts under `.flow/` and the decision journal under `.decisions/`. **Any other tracked change in the working tree is "unlinked"** — most likely unrelated human work that `/flow:resume` must not silently fold into a continuation.

```!
# Treat any porcelain entry whose path is NOT under .flow/ or .decisions/ as
# unlinked. Conservative by design (simple prefix test rather than diffing
# against the run recorded paths): better to ask once too often than to
# absorb a human unrelated edits into a resumed workflow.
#
# Capture git is exit code separately: a git failure (not a repo, git missing)
# must NOT be read as "clean tree" — that would silently skip the guard. The
# rename-arrow strip is gated to R/C status lines so a file literally named
# `x -> .flow/y` cannot masquerade as a flow-owned path and slip the filter.
# Capture git output and exit code BEFORE piping, so a git failure is not masked
# by awk exit status (the pipeline runs in a subshell where PIPESTATUS would
# not survive the command-substitution assignment).
PORCELAIN=$(git -c core.quotePath=false status --porcelain 2>/dev/null); GIT_EXIT=$?
UNLINKED=$(printf '%s\n' "$PORCELAIN" | awk '
  NF == 0 { next }
  { st = substr($0, 1, 2); path = substr($0, 4) }
  st ~ /^[RC]/ { n = index(path, " -> "); if (n) path = substr(path, n + 4) }  # rename/copy dest
  { sub(/^"/, "", path); sub(/"$/, "", path) }                                 # unquote special-char paths
  path !~ /^\.flow\// && path !~ /^\.decisions\// { print path }
')
if [ "$GIT_EXIT" -ne 0 ]; then
  printf '%s\n' "FLOW_RESUME_UNLINKED=unknown"
  printf '%s\n' "FLOW_RESUME_UNLINKED_REASON=git status failed (exit $GIT_EXIT) — cannot assess unlinked changes"
elif [ -n "$UNLINKED" ]; then
  printf '%s\n' "FLOW_RESUME_UNLINKED=1"
  printf '%s\n' "$UNLINKED" | sed 's/^/  /'
else
  printf '%s\n' "FLOW_RESUME_UNLINKED=0"
fi
true
```

When `FLOW_RESUME_UNLINKED=unknown`, treat it like `1` for safety: surface that the working tree could not be assessed and ask before suggesting continuation. When `FLOW_RESUME_UNLINKED=1`, you MUST surface the listed paths and **ask before suggesting continuation** — do not jump to the Step 5 next-action suggestion. Use `AskUserQuestion`:

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
- ❌ Suggesting continuation when unlinked working-tree changes exist (changes outside `.flow/` and `.decisions/`) without asking first. Flow must not absorb unrelated human work into a resumed run.
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
