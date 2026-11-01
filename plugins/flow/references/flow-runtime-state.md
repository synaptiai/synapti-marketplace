# Flow runtime state — the `.flow/` directory

The flow plugin's runtime layer stores project-local execution state in the runtime directory: `flow.runtime.stateDir`, default `.flow`, a path relative to the repository top. Every reader and writer takes it from `bin/flow-runtime-dir.sh` (Python callers from `runtime_dir()` in `bin/_repo_dir.py`). A value that is absolute, starts with `~`, has a `..` component, or does not end inside the repository with no symlink on the way prints one warning naming the setting and `.flow` is used. In this document and the other references, `.flow/` stands for the runtime directory. It is not the per-user state directory (`FLOW_STATE_DIR`, default `~/.claude/flow-state`). This document describes what lives there, what's tracked vs gitignored, and how the layer composes with the existing decision journal at `.decisions/`.

## Directory layout

```
.flow/
├── goals/<id>.goal.yaml              # FlowGoal contracts (tracked)
├── workflows/<id>.workflow.yaml       # FlowWorkflow definitions (tracked; rare overrides)
├── triggers/<id>.trigger.yaml         # FlowTrigger configs (tracked)
├── watch/                             # issue-watch snapshots (ignored by a `.gitignore` of `*` that flow writes inside it)
└── runs/<ISO-timestamp-id>/           # FlowRun records (per-developer; see Gitignore policy)
    ├── run.yaml                       # the run document
    ├── activities/<NNN>-<name>.yaml   # sequence-numbered FlowActivity records
    ├── events.jsonl                   # append-only event ledger
    ├── .lock                          # flock target for activity/evidence appends
    ├── last-verdict.json              # most-recent evaluator verdict (replace-semantics; consumed by next-turn delta computation)
    ├── .verdict.lock                  # per-target flock for verdict writes (separate from .lock so replace and append progress concurrently)
    └── evidence/                      # FlowEvidence sidecars + raw output
        ├── <id>.evidence.yaml
        └── <id>.txt
```

## Gitignore policy

`/flow:setup` adds these lines to the project's `.gitignore` when they are missing:

```
.claude/settings.flow.local.json
.claude/*.lock
.flow/watch/
<journal dir>/auto-log/
```

It does not ignore `.flow/runs/`. Add that line yourself to keep run records out of commits:

```
# Per-developer runtime records (add this line yourself)
.flow/runs/

# Team-shared contracts (tracked)
# .flow/goals/*.goal.yaml
# .flow/workflows/*.workflow.yaml
# .flow/triggers/*.trigger.yaml
# .flow/review-exceptions.md
```

Rationale:
- **`runs/`** (activities, events and evidence sidecars) is session-bound, per-developer execution noise. Committing it would bloat history and surface non-reproducible artifacts.
- **`goals/`** and **`workflows/`** are intentional team contracts — teams may want to share goal contracts across developers (e.g., a project-wide quality goal). The schemas keep these files diff-friendly.
- **`triggers/`** holds `<id>.trigger.yaml` files, the shared trigger configs. Flow reads only files with that suffix; it has no per-developer trigger file.

Teams wanting fully-private goals add `.flow/goals/` to their personal `.gitignore`. The helper writes don't depend on git state.

## Atomic writes

All `.flow/` writes go through `bin/_journal_atomic.py` (or one of its wrappers):

| Helper | Writes |
|---|---|
| `bin/flow-goal-record.sh` | `.flow/goals/<id>.goal.yaml` (create + update-lifecycle modes) |
| `bin/flow-record-activity.sh` | `.flow/runs/<id>/activities/<NNN>-<name>.yaml` + appends `events.jsonl` |
| `bin/flow-record-evidence.sh` | `.flow/runs/<id>/evidence/<id>.evidence.yaml` + optional `<id>.txt` |
| `bin/journal-record.sh` | `.decisions/issue-N.md` (or `session-YYYY-MM-DD.md` with `--session`) manifest entries (not `.flow/`) |

Atomicity guarantees:
- `O_NOFOLLOW` on lockfile + target — symlinks rejected atomically
- No write through a symlinked directory: when `.flow`, `.flow/runs`, a run directory, `.flow/goals` or the journal directory is a symlink (a repository can commit one pointing outside the checkout), the helper creates and writes nothing and exits 2. Command blocks create these directories with `bin/flow-mkdir.sh`, which applies the same rule, never with `mkdir -p`
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

Every `.flow/` mutation that has long-term significance ALSO writes a journal manifest artifact (`goal-created`, `goal-evaluation`, `workflow-run`, `evidence-captured`, `trigger-fired`). The journal is the cross-PR, multi-session source of truth; `.flow/` is the in-flight working state.

## What `.flow/` is NOT

1. **Not a database.** No queries beyond `glob.glob` + per-file YAML parsing. Adding query semantics is out of scope.
2. **Not a CI artifact store.** Use existing CI artifact mechanisms; `.flow/runs/` is for local resumability.
3. **Not Temporal.** No exactly-once execution. No deterministic replay. Resume reads `state.completed_activities[]` and tells the user where to pick up — the user decides whether to re-run partially-completed phases.
4. **Not a long-term archive.** At the end of each session the SessionEnd hook removes runs that ended (`completed` or `cancelled`) and whose `run.yaml` was last written more than `flow.runtime.runRetentionDays` days ago (default 30; a value that is not a whole number of at least 1 means 30). Active and blocked runs are kept, and so is a run whose `run.yaml` cannot be parsed. Nothing is removed while `flow.runtime.enabled` is false, or through a symlinked `.flow`, `.flow/runs` or run directory.

## Resumability

`/flow:resume` reads `.flow/runs/<id>/run.yaml` for runs with `state.status` in `{active, blocked}` and reports:
- which phase the run was in
- which activity was current
- what completed activities exist
- what `events.jsonl` shows for recent activity

The command is **informational only** — it never auto-executes the next phase. The user decides whether to continue, restart, or cancel.

When SessionEnd fires (`hooks/scripts/session-end-state.sh`), every active FlowRun gets a `session_end` event appended to its `events.jsonl`. No `run.yaml` mutations — those are user decisions via `/flow:resume`.

## Settings

FlowRun records are gated by `flow.runtime.enabled` (cascade-resolved; default `true`). When disabled:
- `/flow:start`, `/flow:debug`, `/flow:review`, `/flow:address`, `/flow:merge` and `/flow:release` create no FlowRun (`FLOW_RUN_STATE=skip`)
- Existing `.flow/` files remain readable
- `/flow:resume` prints a notice and exits 0, and the SessionEnd hook records nothing
- `/flow:goal` and the Stop hook do not read this switch; `/flow:goal` follows `flow.goals.enabled`
- `/flow:watch`, `/flow:trigger` and `/flow:run` do not read this switch; they follow `flow.triggers.enabled` and still write `.flow/triggers/` and `.flow/watch/`

This switch turns off run records only; the per-feature switches (`flow.goals.enabled`, `flow.workflows.enabled`, `flow.triggers.enabled`) provide finer-grained control.

## References

- `plugins/flow/schemas/v1/` — JSON Schemas for goal, run, activity, evidence, workflow, trigger.
- `plugins/flow/bin/_journal_atomic.py` — atomicity primitives.
- `plugins/flow/skills/run-state-management/SKILL.md` — owns run state mutations.
- `plugins/flow/commands/resume.md` — `/flow:resume` command.
- `plugins/flow/hooks/scripts/session-end-state.sh` — SessionEnd persistence.
- `plugins/flow/references/flow-goals.md` — FlowGoal model documentation.
- `plugins/flow/references/stop-hook-goal-enforcement.md` — Stop hook architecture.
- `plugins/flow/references/decision-journal-schema.md` — `.decisions/` manifest + journal artifact types.
