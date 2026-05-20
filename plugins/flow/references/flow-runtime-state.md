# Flow runtime state — the `.flow/` directory

The flow plugin's v3 runtime layer stores project-local execution state under `.flow/`. This document describes what lives there, what's tracked vs gitignored, and how the layer composes with the existing decision journal at `.decisions/`.

## Directory layout

```
.flow/
├── goals/<id>.goal.yaml              # FlowGoal contracts (M2; tracked)
├── workflows/<id>.workflow.yaml       # FlowWorkflow definitions (M4; tracked; rare overrides)
├── triggers/<id>.trigger.yaml         # FlowTrigger configs (M5; tracked)
├── triggers/<id>.local.yaml           # local-only triggers (gitignored)
└── runs/<ISO-timestamp-id>/           # FlowRun records (M3; gitignored)
    ├── run.yaml                       # the run document
    ├── activities/<NNN>-<name>.yaml   # sequence-numbered FlowActivity records
    ├── events.jsonl                   # append-only event ledger
    ├── .lock                          # flock target (gitignored)
    └── evidence/                      # FlowEvidence sidecars + raw output
        ├── <id>.evidence.yaml
        └── <id>.txt
```

## Gitignore policy

Settled in M1's `.gitignore`:

```
# Per-developer runtime noise (gitignored)
.flow/runs/
.flow/evidence/
.flow/triggers/*.local.yaml

# Team-shared contracts (tracked)
# .flow/goals/*.goal.yaml
# .flow/workflows/*.workflow.yaml
# .flow/triggers/*.trigger.yaml (non-.local)
```

Rationale:
- **`runs/`** and **`evidence/`** are session-bound or per-developer execution noise. Committing them would bloat history and surface non-reproducible artifacts.
- **`goals/`** and **`workflows/`** are intentional team contracts — teams may want to share goal contracts across developers (e.g., a project-wide quality goal). The schemas keep these files diff-friendly.
- **`triggers/`** is split: `<id>.trigger.yaml` is the shared trigger config; `<id>.local.yaml` is a per-developer override.

Teams wanting fully-private goals add `.flow/goals/` to their personal `.gitignore`. The helper writes don't depend on git state.

## Atomic writes

All `.flow/` writes go through `bin/_journal_atomic.py` (or one of its wrappers):

| Helper | Writes |
|---|---|
| `bin/flow-goal-record.sh` | `.flow/goals/<id>.goal.yaml` (create + update-lifecycle modes) |
| `bin/flow-record-activity.sh` | `.flow/runs/<id>/activities/<NNN>-<name>.yaml` + appends `events.jsonl` |
| `bin/flow-record-evidence.sh` | `.flow/runs/<id>/evidence/<id>.evidence.yaml` + optional `<id>.txt` |
| `bin/journal-record.sh` | `.decisions/issue-N.md` manifest entries (M1 refactor; not `.flow/`) |

Atomicity guarantees:
- `O_NOFOLLOW` on lockfile + target — symlinks rejected atomically
- `fcntl.flock(LOCK_EX)` — serializes concurrent writes
- `tempfile.mkstemp` + `os.rename` — POSIX-atomic publish
- `os.fsync` on file + directory fds — durable across power loss

If your code needs to write under `.flow/`, use one of these helpers. Direct file writes will work but skip the atomicity defenses, which becomes painful at scale.

## Composition with `.decisions/`

The decision journal at `.decisions/issue-{N}.md` remains the primary audit trail. The `.flow/` runtime layer COMPLEMENTS it:

| Question | Lives in |
|---|---|
| What decisions were made and why? | `.decisions/issue-{N}.md` (manifest frontmatter + body) |
| What activities ran in this execution attempt? | `.flow/runs/<id>/activities/*.yaml` |
| What's the goal's contract + lifecycle state? | `.flow/goals/<id>.goal.yaml` |
| What evidence proves AC1? | `.flow/runs/<id>/evidence/<id>.evidence.yaml` |
| When did the goal transition from active to achieved? | `.decisions/issue-{N}.md` manifest (`goal-evaluation` artifact) |

Every `.flow/` mutation that has long-term significance ALSO writes a journal manifest artifact (`goal-created`, `goal-evaluation`, `workflow-run`, `activity-completed`, etc.). The journal is the cross-PR, multi-session source of truth; `.flow/` is the in-flight working state.

## What `.flow/` is NOT

1. **Not a database.** No queries beyond `glob.glob` + per-file YAML parsing. Adding query semantics is M5+ territory.
2. **Not a CI artifact store.** Use existing CI artifact mechanisms; `.flow/runs/` is for local resumability.
3. **Not Temporal.** No exactly-once execution. No deterministic replay. Resume reads `state.completed_activities[]` and tells the user where to pick up — the user decides whether to re-run partially-completed phases.
4. **Not a long-term archive.** `runRetentionDays` (default 30; cascade-resolved via `flow.runtime.runRetentionDays`) bounds run records. A future cleanup helper will prune by mtime.

## Resumability

`/flow:resume` reads `.flow/runs/<id>/run.yaml` for runs with `state.status` in `{active, blocked}` and reports:
- which phase the run was in
- which activity was current
- what completed activities exist
- what `events.jsonl` shows for recent activity

The command is **informational only** — it never auto-executes the next phase. The user decides whether to continue, restart, or cancel.

When SessionEnd fires (`hooks/scripts/session-end-state.sh`), every active FlowRun gets a `session_end` event appended to its `events.jsonl`. No `run.yaml` mutations — those are user decisions via `/flow:resume`.

## Settings

All `.flow/` behavior is gated by `flow.runtime.enabled` (cascade-resolved; default `true`). When disabled:
- No `.flow/` writes happen
- Existing `.flow/` files remain readable
- `/flow:resume` and `/flow:goal` print a notice and exit 0
- The Stop hook fast-paths to `{"decision":"approve","reason":"runtime disabled"}`

This switch is meant for users who want to opt out entirely; the per-feature switches (`flow.goals.enabled`, `flow.workflows.enabled`, `flow.triggers.enabled`) provide finer-grained control.

## References

- `plugins/flow/schemas/v1/` — JSON Schemas for goal, run, activity, evidence (workflow + trigger in M4/M5).
- `plugins/flow/bin/_journal_atomic.py` — atomicity primitives (M1).
- `plugins/flow/skills/run-state-management/SKILL.md` — owns run state mutations (M3).
- `plugins/flow/commands/resume.md` — `/flow:resume` command (M3).
- `plugins/flow/hooks/scripts/session-end-state.sh` — SessionEnd persistence (M3).
- `plugins/flow/references/flow-goals.md` — FlowGoal model documentation.
- `plugins/flow/references/stop-hook-goal-enforcement.md` — Stop hook architecture.
- `plugins/flow/references/decision-journal-schema.md` — `.decisions/` manifest + journal artifact types.
