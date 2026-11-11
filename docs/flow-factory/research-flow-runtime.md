The flow plugin can't run a software factory without a person present today. Its durable state and safety gates are solid, but nothing in it starts, chains or schedules work on its own.

- **No orchestrator.** The workflow YAMLs describe each command but are never executed.
- **No chaining.** Each command ends by suggesting the next one rather than running it.
- **No scheduler or queue.** Triggers record when work should happen; a person, a `/loop` the person starts, or a hook or CI job they write has to run them. The `queue` setting only writes a journal entry.
- **No multi-issue model.** There is no queue, epic or sub-issue handling and no dependency graph between issues. Worktrees are used only to review someone else's pull request.

Scope: this rests on the plugin tree at `/Users/danielbentes/synapti-marketplace/plugins/flow` as of 2026-11-11 (main at `aab0d132`, flow 3.16.0). I read the four runtime references, the stop-hook reference up to the evaluator-loop section, `run.md`, the trigger templates, `start-issue.workflow.yaml`, `hooks.json`, `settings.json`, the relevant schema entries, and the Contract sections of the seven runtime skills. I did not read `commands/goal.md`, `workflow.md` or `trigger.md` in full; what I say about them comes from the reference docs. All paths below are relative to that plugin root.

## 1. What each primitive is

| Primitive | What it is | Where it lives | Commands | Sources |
|---|---|---|---|---|
| **FlowGoal** | A completion contract in YAML: the outcome, acceptance criteria with `verification_command` and `must_pass`, the specification (non-goals, failure modes, interface contracts, risk map), constraints, which evaluator judges it, a continuation policy (`max_iterations` 20), and a lifecycle. States: draft → active → {waiting_for_user, waiting_for_ci, blocked} → {achieved, failed, cancelled}. Each goal belongs to one branch (`scope.branch`). | `.flow/goals/<id>.goal.yaml`, committed | `/flow:goal status, create, inspect, evaluate, pause, resume, clear, history` | `references/flow-goals.md:5-17, 46-71, 140-149`; `schemas/v1/goal.schema.json` |
| Goal skills | **goal-contract-capture** writes a draft goal and invents nothing; every element comes from the journal or is escalated. **goal-lifecycle** makes all status changes go through `bin/flow-goal-record.sh` and writes a journal entry for each. **goal-evaluator** runs the verification commands first and the judge only for criteria without a command; it proposes `achieved` or `failed` but never writes them. **goal-evidence-ledger** writes evidence files, and a criterion can't pass without one. | — | — | `skills/goal-contract-capture`, `goal-lifecycle`, `goal-evaluator`, `goal-evidence-ledger` (`SKILL.md` Contract sections) |
| **Trust ledger** | A per-user record of which goals flow created. Only a trusted goal's verification commands run automatically; a goal that arrived with a checkout is untrusted. | `~/.claude/flow-state/goal-trust.jsonl` | `bin/flow-goal-trust.sh` | `README.md:16`; `references/flow-goals.md:40` |
| **FlowWorkflow** | A machine-readable description of each `/flow:*` command: inputs, required skills and agents, phases (bash, mixed, agent, loop, parallel_then_judge), gates, a tier per action, and a completion gate. **It is documentation that gets validated, not something that runs.** The command markdown is what Claude actually follows. `completion_gate.documented_requirements` is advisory. | `workflows/*.workflow.yaml` (7 shipped), optional overrides in `.flow/workflows/` | `/flow:workflow list, inspect, validate, graph` | `references/flow-workflows.md:3, 14, 19-29, 31-41`; `skills/workflow-validation/SKILL.md` |
| **FlowTrigger** | A record of when work should be resumed and what to run (`target.command`, `target.workflow`, `target.goal`), with allowed and forbidden actions, a concurrency policy (skip_if_running, queue, cancel_previous), stop conditions and recursion limits. Default allowed types are manual, hook and loop_prompt. github_actions, local_cron and local_daemon pass the schema, but flow ships no runner for them, and local_daemon is marked "(Future adapter design)". | Templates in `triggers/templates/` (pr, ci, issue, branch, nightly); instances in `.flow/triggers/` | `/flow:trigger`, `/flow:watch`, `/flow:run trigger <id>` | `references/flow-triggers.md:3-19, 31-43`; `skills/trigger-policy/SKILL.md` |
| **FlowRun and FlowActivity** | A local execution record per attempt: `run.yaml`, numbered activity files, an append-only `events.jsonl`, evidence files and the last verdict. Status is active → completed, blocked or cancelled. | `.flow/runs/<ISO-id>/` | `/flow:resume` | `references/flow-runtime-state.md:7-24`; `skills/run-state-management/SKILL.md` |
| **Stored questions** | Escalations saved as files with a status (open, answered, withdrawn) and a class (decision, permission, default), so they survive the session ending or a session with no one to answer. | `.flow/questions/<id>.yaml` | `bin/flow-question.sh`; shown by `/flow:status` and `/flow:resume` | `references/escalation-format.md:97-118`; `references/flow-runtime-state.md:53` |
| **Decision journal** | The long-term, cross-PR record. Every significant change under `.flow/` also writes an entry here (goal-created, goal-evaluation, workflow-run, evidence-captured, trigger-fired). | `.decisions/issue-N.md` | — | `references/flow-runtime-state.md:78-90` |
| **Hooks** | Before each Bash command: force-push, destructive and unchecked-merge blocks, a secrets check, an ask on issue creation, and `tier-gate.sh`. On AskUserQuestion: `ask-policy.sh`. After edits and commands: change logging, quality-run recording, System One text screening. On task completion: `verify-task-completion.sh`. On idle teammate: a nudge. At session end: learning and run-state recording. On Stop: `flow-goal-stop.sh` and `reply-style-check.sh`. At session start: `tier-session-start.sh`, which puts flow's `git` and `gh` wrappers on PATH. | `hooks/hooks.json` | — | `hooks/hooks.json`; `references/three-tier-safety.md` |
| **Stop-hook evaluator** | Three modes. `warn` (default) never blocks. `block` refuses the stop when evidence is missing, up to `failAfterStuckTurns` (3) times in a row. `evaluator-loop` is opt-in: `flow-goal-stop.sh` hands off to `flow-goal-evaluator.sh`, which asks a Haiku judge each turn. It is limited three ways: 3 continuations per 5 minutes per session, failed after 3 turns with no progress, and failed when `max_iterations` (20) is used up. | — | — | `references/flow-goals.md:151-161, 175-177`; `hooks/scripts/flow-goal-stop.sh:26, 476-513`; `hooks/scripts/flow-goal-evaluator.sh:13, 195-215` |
| **bin scripts** | `flow-judge.sh` runs a judge as `claude --print` with all tools disabled. Its callers are the evaluator-loop, `/flow:goal evaluate` (through `flow-goal-judge-run.sh`) and `/flow:start`'s verdict judge. Other scripts: atomic writers (`flow-goal-record`, `flow-record-activity`, `flow-record-evidence`, `flow-record-verdict`, on top of `_journal_atomic.py`), the trigger checks (schema, tier-3, recursion, concurrency), `flow-watch-create`, `flow-question`, `flow-ask-policy`, `cascade-resolve` and `flow-eval-run`. | — | — | `bin/flow-judge.sh:1-40`; `references/flow-runtime-state.md:58-76`; `references/flow-triggers.md:117-119` |
| **System One** | An optional small classifier that answers narrow questions (yes/no, multiple choice or a score) with a probability. Every use is off by default. It has no tools and generates no text. | `system-one/questions.yaml` | `bin/flow-s1.sh` | `references/system-one.md:1-30`; `settings.json` `systemOne` |
| **Evals** | Headless `claude -p` runs on tasks with planted bugs, scored against hidden tests. They measure the TDD and risk-map settings and how precise reviews are. | `evals/` (4 cases) | `bin/flow-eval-run.sh` | `references/correctness-eval.md:1-25, 286-300` |
| **Settings** | A cascade from local to project to user to plugin defaults. Relevant keys: `tiers.*`, `autonomous` (false), `agentTeams` (false), `reviewCycleLimit` and `fixForwardMaxIterations` (10 each), `flow.goals.*`, `flow.triggers.*` (`allowAutonomousMerge` false, `maxActiveTriggers` 5, `defaultConcurrency` skip_if_running). | `settings.json`, `schema.json` | — | `settings.json`; `schema.json:594-615` |

## 2. How they compose

- `/flow:start <issue>` does the following, in order (`references/flow-goals.md:239`):
  1. Opens a FlowRun.
  2. Captures the specification into the journal.
  3. Runs the Spec Validation Gate.
  4. Creates the goal (auto, when at least one criterion has a verification command) and activates it.
  5. Plans, codes and verifies, writing activity records.
  6. Evaluates the goal at the end of VERIFY. It moves to `achieved` without a question only if it is trusted, every command passes and the verdict judge passes every criterion that has no command.
- `/flow:pr` continues the same `start-issue` run rather than opening its own (`commands/pr.md:732`).
- `/flow:merge` checks the goal of the pull request's head branch, and only `achieved` lets it through (`references/flow-goals.md:242`). It also checks the review and resolution markers.
- `/flow:review` and `/flow:address` create no goal. They read the goal on the PR head, and their posted review markers are the lasting record (`references/flow-goals.md:240-241`).
- A trigger points to a workflow, a command and a goal. Each `/flow:run` creates a new FlowRun tagged with the trigger id, and that tag is what the concurrency check counts (`references/flow-triggers.md:76-80`; `commands/run.md`).
- The Stop hook enforces the goal for the current branch on every turn of the session. With two active goals on one branch it judges neither (`references/stop-hook-goal-enforcement.md`, section "Which goal is judged").

## 3. What runs unattended and what needs a person

| Step | Unattended? | Why | Sources |
|---|---|---|---|
| Hooks (tier gate, guards, logging, Stop evaluation, session-end recording) | Yes, but only inside a session that is already running | Hooks fire on that session's events | `hooks/hooks.json` |
| Evaluator-loop continuation | Partly | Keeps one session working toward one goal, within the three limits in section 1 | `hooks/scripts/flow-goal-evaluator.sh:13, 213` |
| Starting any `/flow:*` command | No | A person types it, or a `/loop` the person started runs it | `references/flow-triggers.md:3, 25-27` |
| Moving from one command to the next (start → pr → review/address → merge) | No | Each command ends by suggesting the next: start suggests `/flow:pr`, review suggests `/flow:pr` or `/flow:address` | `commands/start.md:1294-1300`; `commands/review.md:2375` |
| `/flow:resume` | No | Only reports; never runs the next phase | `references/flow-runtime-state.md:96, 107`; `commands/resume.md:2, 377` |
| Running a trigger | No | `/flow:run` runs once. `/flow:watch` writes a loop prompt that the person starts with `/loop`. For `ci` triggers flow ships no hook that fires them. | `commands/run.md`; `commands/watch.md:82, 221-225` |
| `queue` concurrency | Not a queue | Only writes a journal entry; nothing holds the run for later | `commands/run.md:53` |
| Push, PR creation, issue creation and assignment (Tier 2) | Yes | Default `journal`: runs and leaves a note; can be set to `autonomous` | `settings.json` `tiers`; `README.md:470` |
| Merge, release, tag push (Tier 3) | Never | Always asks. In `claude -p` an ask becomes a refusal. Triggers must list merge and release as forbidden unless the user's own `allowAutonomousMerge` allows otherwise. | `references/three-tier-safety.md:77`; `references/flow-triggers.md:28`; `commands/run.md` (Tier Classification) |
| Questions under `autonomous: true` | Partly | Questions that are only a default get the recommended option, recorded as `default-taken`. Decisions and permissions are still asked. | `references/ask-policy.md:5-24, 30-48` |
| Questions with nobody there (`claude -p`, where AskUserQuestion is missing) | Partly | Blocking ones stop the run and are stored; soft and non-blocking ones take the recommendation and are listed in the PR | `references/escalation-format.md:115-118`; `references/ask-policy.md:56` |
| Ending a goal as `achieved` or `failed`, clearing a goal | Usually needs a person | `/flow:goal evaluate` asks before writing either; `/flow:start` can mark achieved alone under the strict conditions in section 2 | `references/flow-goals.md:145-148, 239` |
| Headless sessions | Only in the evals | `flow-eval-run.sh` is the one place flow itself starts `claude -p` sessions | `references/correctness-eval.md:292-300, 1005-1007` |

## 4. Limitations the docs state

These are flow's own statements, not platform facts I checked:

- "Plugins cannot invoke `/goal` (no `SlashCommand` tool exists; the only post-turn hook is `Stop`)" (`references/flow-goals.md:3`; `references/stop-hook-goal-enforcement.md`, "Why this exists").
- "Flow CANNOT invoke `/loop` from plugin code" (`references/flow-triggers.md:25`; `commands/watch.md`).
- Workflow validation fails hard on `/goal`, `/loop`, `/schedule` or `/routine` used as invoked commands (`references/flow-workflows.md:40`).
- Flow lists what it does not do:
  - No background execution (`references/flow-triggers.md:27`; `references/flow-goals.md:232`).
  - No exactly-once execution and no deterministic replay; the runtime directory is "Not Temporal" and "Not a database", with no queries (`references/flow-runtime-state.md:94-96`).
  - No Tier 3 autonomy (`references/flow-goals.md:233`).
- The FlowGoal reference says: "flow ships no durable runtime adapter" (`references/flow-goals.md:235`).
- Nothing checks at run time whether a command was started by a trigger, so the recursion limits are only checked when a trigger is validated (`commands/run.md`, "Recursion enforcement").
- Stale active runs are not detected automatically (`commands/run.md`, Anti-patterns).
- Runs that ended are deleted after 30 days (`references/flow-runtime-state.md:97`).
- **One contradiction:** `references/flow-triggers.md:10` says a hook script calls `/flow:run trigger <id>` programmatically, but `commands/watch.md:82` says "Flow ships no hook that fires it", and `hooks.json` has no such hook.

## 5. Existing notions of a pipeline, queue or multi-issue orchestration

- **"Pipeline"** in the docs means the six commands that share one ask-policy preflight: start, pr, address, review, commit and resolve (`references/ask-policy.md:10`). It is not an execution graph.
- **Queue:** only the trigger `concurrency.policy: queue` value, which records and nothing more (`schemas/v1/trigger.schema.json:115`; `commands/run.md:53`).
- **Parallel work inside one issue:**
  - Agent teams (`agentTeams`, default false, also needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) for adversarial review, or for parallel implementation when an issue has more than 5 criteria (`skills/team-coordination/SKILL.md`).
  - `parallel_then_judge` phases and parallel reviewer fan-out (`references/flow-workflows.md:59`).
- **Multi-issue orchestration: none found.** I searched `commands/`, `skills/`, `bin/` and `hooks/`, plus the md, yaml and json files outside `evals/`, for epic, sub-issue, blocked by, depends on, queue, pipeline, multi-issue, backlog, orchestrat, headless and worktree. The only hits were unrelated: "dep" in `bin/flow-dep-diff.sh` and `bin/_flow_dep_parse.py` means package dependencies; "orchestrator" means a command calling its own skills; worktrees appear only for reviewing an external PR (`commands/review.md:573-666`). The closest things are:
  - `/flow:watch issue <N>`, which is read-only and only suggests `/flow:start N` when the issue is assigned to you (`triggers/templates/issue-watch.loop.md`).
  - The disabled nightly-maintenance template, which needs a `/loop` the user starts (`triggers/templates/nightly-maintenance.trigger.yaml`).
  - Goals and FlowRuns, which are scoped to one issue and one branch.

## Direction from the changelog

The last releases (3.13.0 to 3.16.0, 2026-11-01 to 2026-11-11) are mostly about making unattended runs safe:

- `autonomous: true` is now enforced by a hook, and escalations are stored with a status (3.15.0).
- The tier gate no longer stops unattended `/flow:start` runs on flow's own journal writes (3.15.1).
- The tier gate reads only shell it can parse, and `/flow:setup` can add Claude Code ask rules for merges and releases (3.16.0).
- Earlier: the `runtime.stateDir` and `runRetentionDays` settings now take effect, plus `allowAutonomousMerge` and `defaultConcurrency` (3.13.0).

No roadmap entry mentions a scheduler, a queue or multi-issue work (`CHANGELOG.md:3-160`).

This session also lists `loop` and `schedule` skills and Cron and RemoteTrigger tools. I did not check whether a plugin can use any of these; that needs checking at design time.