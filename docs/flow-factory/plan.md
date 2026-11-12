# Flow factory: from a labelled issue queue to a ready PR, with no person starting each step

## Context

Flow (3.16.0, main at aab0d132) runs each step only when a person starts it: `/flow:start`, `/flow:pr`, `/flow:review`, `/flow:address`, `/flow:merge`. Goals, workflows and triggers exist, but nothing pulls work from a queue and drives it through every step.

Two references were compared with flow's code.

**zazen software-factory v2** (zazencodes-season-3 at 5fc7c983, GPLv3, so this plan takes ideas only, no code or prompt text):
- issues with a `factory` label form the queue;
- a single job state machine is the only thing that writes job state;
- the stages are intake, spec, build, then a gate. The gate runs checks from main, rejects changes to protected paths, and requires the checked commit to be HEAD;
- after the gate come routed reviewers and an approver, then a merge with a re-check;
- everything runs inside one interactive orchestrator session.

**AWS AI-DLC v2** (awslabs/aidlc-workflows at ca2c816c): 5 phases, 33 stages, 11 scopes and 134 audit event types. It has explicit approval points, an audit trail, and an orchestration engine that holds state.

The gap analysis found 24 gaps (G1–G24), and all 24 held up when checked against flow's code. The main ones:
- no queue or job state;
- no headless execution model;
- specification-capture stops to ask on almost every ordinary issue unless the journal is seeded first;
- no gate bound to a commit;
- no review routing;
- no base-sync loop;
- no record of GitHub writes as Tier 2 actions.

Flow already has dependency and migration review, per-task checkpoints and project-scoped review exceptions. The factory reuses them.

**The outcome:** a person labels an issue, and the factory drives it to a draft PR that has passed the gate, been reviewed and synced, and is marked ready. A person merges it. Opt-in auto-merge comes later, in phase 2.

## Your decisions (both rounds and this turn)

| Topic | Decision |
|---|---|
| First scope | Queue to a ready PR (G1–G8, G11–G13, G16) |
| Merge | Opt-in auto-merge in phase 2. Only the runner outside sessions can use it, a user-level switch turns it on, it ships off and is released after a live run, and the docs state it is an exception to Tier 3 |
| GitHub writes by the factory | Tier 2, under a new `tiers.issueUpdate` key |
| Spec approval | Only for high-risk jobs (`specApproval: high`, or `all`) |
| Executors | Both: a headless runner, and a full interactive executor |
| Interactive executor | The session runs the queue and asks each question the moment a job needs it. Work runs in separate `claude -p` processes, each of which waits in place for the answer |
| A conflict it cannot resolve mechanically | Stop and ask (`resolve.nonTrivial: park`) |
| A reply from someone without write access | Counts only after someone with triage access or higher confirms it |
| Sending a ready PR back | A trusted "request changes" review, or a trusted `/flow-factory rework <text>` comment. The comment is a recorded exception to "request changes only", because GitHub does not let you request changes on your own PR |
| Filing the design (2026-11-12) | Approved for filing. The sandbox repository and the read-only worker token are still asked at phase 0 |
| Comments and other GitHub writes made with your token (2026-11-12) | Accepted as a risk. No rule holds comments posted with your GitHub accounts, and workers do not run as a separate OS user. A worker or any Claude session running as you can read your keyring write token with `gh auth token` (checked 2026-11-12: scopes repo, workflow, delete_repo, gist, read:org) and post command comments, add labels, edit, close or merge as you. This closes the comment-channel defect in Step 1.2 by decision. Before auto-merge can be switched on in phase 2, this risk is shown to you again, because under auto-merge a comment posted as you could lead to a merge |
| Workers reading raw issue and PR comments (2026-11-12) | Accepted. "Workers read issue and PR text only from trust-filtered files" is a recorded departure: the prompts and the fenced input files are the only guard |
| A retry after the issue changed (2026-11-12) | The job goes back through intake, so the changed issue is judged again, and the intake launch stays the only writer of the baseline |
| Cloud credentials in workers (2026-11-12) | Always passed (every `AWS_*` variable and `GOOGLE_APPLICATION_CREDENTIALS`), with no setting to drop them. A recorded residual risk |

## Design

The full design is the revised design file (see Step 1). In short:

1. **Engine.**
   - `bin/flow-factory.sh` is a thin shell wrapper around `bin/_flow_factory.py`. The engine is Python because macOS bash 3.2 has no `wait -n`, `setsid` or `flock`.
   - The engine is the only writer of job state, which lives in `.flow/factory/jobs/issue-N/`. Every state change goes through one TRANSITIONS table.
   - It does every deterministic step itself: GitHub sync, all GitHub writes (as Tier 2 with breadcrumbs), worktrees, bootstrap, the gate, diff categories, review routing, base sync, and holding locks and leases.
   - The wrapper answers `context --mode` without starting Python, so ordinary flow runs are unaffected.
   - It runs the interpreter recorded at probe time with `-E`. The recorded interpreter is a real binary, never a pyenv shim.
2. **Judges.** Intake, and the phase 2 approver, are new `flow-judge.sh` judge kinds that run with no tools.
3. **Workers.**
   - Each stage runs as a `claude -p` process in a per-job worktree outside the repository, under `${XDG_STATE_HOME:-~/.local/state}/flow-factory`. Each worker has its own budget, turn limit, timeout and cleaned environment.
   - The stages are spec, build, PR text, review, rework and conflict resolution. Each runs the existing flow commands in a validated factory mode.
   - Workers read issue and PR text only from trust-filtered files written outside the worktree, and make no GitHub writes.
4. **Factory mode in existing commands.** `flow-ask-policy.sh` gains a halt mode, and its 11 callers and the ask hook follow it. Other commands change too:
   - start, pr, commit, review, address and resolve;
   - specification-capture: the spec stage writes a `## Specification` marked with the job key, so `/flow:start` does not stop to ask, and an old journal is never reused;
   - escalation-format, branch-and-task-management and merge-conflict-resolution.
5. **Gate.**
   - Commands come from the base branch.
   - Protected-path check, freeze, and diff risk check.
   - Per-SHA gate and review records, which bind the result to a commit. FlowGoal lifecycle and `/flow:merge` stay unchanged.
6. **Review markers.** Markers are posted as PR reviews. The factory trusts a marker author only when `/flow:merge` would, so an outsider's comment cannot park a job.
7. **Two executors over the same engine.**
   - **Headless runner:** `flow-factory.sh run`, with launchd and cron templates. Questions go to GitHub, and the job parks.
   - **Interactive:** `/flow:factory run`. A worker with a blocking question waits in place. The session asks it at once with AskUserQuestion, and the worker continues.
   - Both executors must reach the same defined set of results.
8. **Before launch.**
   - Tier 2 keys set to `confirm` are checked before a job spends anything; the job parks in `waiting_operator`.
   - Person-only subcommands (approve-spec, answer, confirm, feedback, rework, retry, reject, cancel, rebuild) are refused from worker environments, and tier-gate denies them in worker sessions.

## Step 1: run /flow:design and file the epic

`/flow:design` was not run during planning. The design came from a workflow: research, gap analysis, three design candidates scored by judges, a synthesis and a critic, then a revision with two fix rounds. The last check (2026-11-11) covered only the 22 items still open before the final fix round. Items closed in earlier rounds were not re-checked against the final text. That check also found about 13 new contradictions in the sections it read. Open items went from 40 to 22 to the list below, with new ones each round, so fixing the transitions table by editing prose is not converging.

1. **Save the design inputs.** They exist only in the session scratchpad, `/private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/e852dfbc-33ef-4ff2-abeb-dc5bc5659433/scratchpad/`, which is cleared on reboot. A durable copy of the design is the `fix-2` result line in `~/.claude/projects/-Users-danielbentes-synapti-marketplace/e852dfbc-33ef-4ff2-abeb-dc5bc5659433/subagents/workflows/wf_9e20cc98-454/journal.jsonl`.
   - On a branch `docs/issue-<epic>-flow-factory-design`, copy into `docs/flow-factory/`:
     - `design.json` (the design, about 150 KB);
     - `design-check-2026-11-11.json`;
     - `gaps.md`;
     - the four `research-*.md` reports;
     - `design-critic.json`.
   - Open a docs PR. The epic links to these files, because the design is too large for an issue body (GitHub's limit is about 65,000 characters).
2. **Run `/flow:design`** on the factory, with those files as input. It writes the transitions table as data, together with a script that derives the entry and exit lists and checks that every guard case has an exit. Then it closes the defects below (checked against `design.json` on 2026-11-11):
   - **GitHub comment channel.** Workers get the person's GitHub token, so a worker could post a trusted `/flow-factory approve-spec` comment through curl or python. `/flow:design` chooses between two fixes:
     - give workers no GitHub credentials, so the engine does every GitHub read and write. This may conflict with the gh calls P1 expects workers to make;
     - give workers a read-only token. You would have to create the token.
   - **Marker trust.** The factory reads the trust list from `origin/<base>`, while `/flow:merge` reads it from the working tree. If the trust settings cannot be parsed, an outsider can still park a job. Match `/flow:merge` on both.
   - **The detached-process escape** from the person-only refusal stays a stated residual risk. P2 must test the deny for every person subcommand, not only three.
   - **Transitions:**
     - `sync` has no exit when marker agreement fails while the base is unchanged;
     - a PR merged by a person during gate, review, rework, sync or resolve is not recorded as `merged`;
     - the entry and exit table leaves out the resume rows (15, 41, 41b, 44) and row 52;
     - the baseline digest is set in two different places (queued, and intake ACCEPT);
     - nothing tells a needs-info reply apart from other trusted discussion.
   - **Restarts:** row 39 resets a dirty tree but then resumes the same session, so the model remembers edits that are gone. A relaunch after a reset must start fresh, and the text saying "never re-expands" must be corrected.
   - **Environment:** `FLOW_FACTORY_BRANCH` and `FLOW_FACTORY_GOAL_ID` are defined only in `job.env`. The launcher must export them.
   - **Probe staleness:**
     - say whether the wrapper refuses `next` while the probe record is out of date;
     - give a re-run command and a status line for the environment probe group, so that a routine gh or git update does not stop a headless run with no way to recover.
   - **Auto mode:** the classifier is not deterministic, so one P9 sample cannot show that an ask reaches a person.
     - In auto mode, interactive `confirm` items are always handled like the runner's: park before launch, confirm in a terminal.
     - The same applies to every person subcommand that "always asks": approve-spec, reject, cancel, retry, rework, feedback and rebuild.
     - In auto mode, these run only from a terminal, or the engine requires a recorded AskUserQuestion answer before it acts.
   - **Smaller fixes:**
     - list `rebuild` as a person subcommand everywhere;
     - align the worker-session deny exceptions with the defined subcommand forms;
     - add a row for the terminal `rework` subcommand, and record `feedback` and `rework` as exceptions next to the comment.
3. **File the epic** with `/flow:issue`. It gets one child issue for phase 0, one for each of 1a–1h, one for phase 2, and one for each later gap (G14–G24). Each child links to the design files. Creating the issues writes to GitHub, so I ask you first.

## How the implementation runs

- **Approving this plan authorises:**
  - local work;
  - branches;
  - pushes;
  - draft PRs and issue creation, which are Tier 2 actions.

  Every merge and release still stops for your confirmation. So do the sandbox approval and the live run.
- **Each sub-phase** (0, 1a–1h, 2) is one child issue, one branch and one PR. Each is built with a Workflow, as you asked with ultracode: implement, run the E2E tests, review with adversarial checks, then `/flow:pr`.
- **1a–1g merge to main as they finish, with the factory off.**
  - Without a `factory` setting, the wrapper prints `FACTORY_MODE=off` and nothing else changes.
  - Each merge needs your confirmation.
- **The first release** that announces the factory is at 1h, after the live run.

## Step 2: phase 0 probes (go/no-go)

Each probe has a fallback. The probes are grouped by what makes their result out of date: platform (`claude --version`), interactive (version and permission mode), environment (interpreter, gh, git, plist), and GitHub writes.

- **Before any probe writes to GitHub,** I ask you to approve a named sandbox repository. If you decline, phases 1c–1h do not start.
- **P1:** `!` blocks, factory mode, worktree and io writes, and per-dispatch model in headless `/flow:start`, `/flow:pr`, `/flow:review` and `/flow:address`. If both fallbacks fail, phase 1 stops.
- **P2:** hooks in workers (tier-gate deny, Stop, SessionEnd, TaskCompleted).
- **P3:** auth and signing in the cleaned environment, plus a sandbox push and draft PR.
- **P4:** a single plugin load when run with `--plugin-dir`.
- **P5:** `--session-id`, then `--resume --fork-session` with limits, cost tracking, and no blocks re-run.
- **P6:** on the sandbox: an own-PR review comment returns an id; its author_association; the CI effect of `gh pr ready`/`--undo`. P6 must pass before 1f and 1g are built.
- **P7–P11 and P13:**
  - P7: trust-ledger isolation;
  - P8: GitHub event fields;
  - P9: the interactive wake source and confirm prompts, in both auto and default mode;
  - P10: tool restrictions in `-p`;
  - P11: the interpreter, which must not be a shim;
  - P13: the launchd or cron context.
- **P14:** a worker holds a blocking question and continues in the same context after the session answers it.
- **P12** (session detection) belongs to phase 2.

## Phases

Each phase is one child issue and ends in a release, with `plugin.json` and `marketplace.json` in sync.

**Phase 1: queue to a ready PR**
- **1a.** Engine, wrapper and interpreter recording; schemas; TRANSITIONS; locks, leases, launcher, events and outbox; rebuild; person-only refusal; probe groups; status.
- **1b.** Trust-filtered text module; vouch rule; intake judge; `tiers.issueUpdate` across tier-gate, tier-runtime, schema, settings and docs; engine GitHub writes; confirm by intent id; the pre-launch tier check; needs-info.
- **1c.** Worker area, worktrees, ignore rules, bootstrap, ports, auth, per-job state; headless runner; launchd and cron templates; the `/flow:factory` interactive executor with its wake source, question hold and `await`.
- **1d.** Factory mode in the ask policy and its callers, and in the commands and skills listed above; the spec stage and its approval; the spec-hash rule.
- **1e.** The gate, protected-path check, freeze, diff risk, and per-SHA records.
- **1f** (after P6). Categories, routing, markers and ledger, and marker trust that matches `/flow:merge`.
- **1g** (after P6). Sync and re-gate; resolve; ready and undo; needs_human; feedback, rework, retry, reject and answer; cost cap; waiting_operator.
- **1h.** Setup, router, status and resume lines, docs, the full E2E suite, a live run and the release.

**Phase 2: opt-in auto-merge.** Approver judge, eligibility rules, merge from the runner only, tier-gate classification, P12 and P13, Tier 3 docs, and the auto-merge E2E tests. It ships with the switch off, after a live run with it on.

**After phase 2, each as its own child issue, in this order:** G14 (compaction), G15, the rest of G9/G10, G17, G23 (racing machines), G18, G19, G24, G21, G22, G20.

## Critical files

**New:**
- `bin/flow-factory.sh`
- `bin/_flow_factory.py`
- `bin/_flow_factory_schema.py`
- `commands/factory.md`
- `references/flow-factory.md`
- launchd and cron templates
- `tests/e2e-factory-*.test.sh`

**Changed:**
- **bin:** `bin/flow-ask-policy.sh`, `bin/flow-judge.sh` (intake and approver kinds), `bin/flow-question.sh` (`--issue`)
- **hooks:** `hooks/scripts/tier-gate.sh` and `hooks/scripts/ask-policy.sh`
- **commands:** `commands/start.md` (branch passed in; `GOAL_LINK` at :550), `pr.md`, `review.md`, `address.md`, `resolve.md`, `merge.md` (docs only), `setup.md` (ignore lines)
- **skills:** `skills/specification-capture/SKILL.md` and `skills/merge-conflict-resolution`
- **references:** `references/escalation-format.md`, `three-tier-safety.md` and `ask-policy.md`
- `settings.json` and its schema (`factory.*`, `tiers.issueUpdate`)

**Reused:**
- `flow-judge.sh` (judges with no tools)
- `flow-question.sh` (stored questions)
- `journal-append.sh --replace-heading`
- `flow-dep-diff.sh` and `flow-risk-check.sh` (diff risk)
- `cascade-resolve.sh` (settings)
- the `/flow:merge` marker-trust order
- `flow-eval-run.sh` (the `claude -p` flags and the environment it keeps)

## Verification

- **E2E tests** for every phase, using `plugins/flow/tests/lib/e2e.sh`:
  - the engine: every TRANSITIONS row, and that the docs table equals the engine table;
  - factory mode in each changed command;
  - the trust filter, including outsider markers and vouching;
  - the executors: interactive and headless reach the same result set;
  - the person-only refusal in its wrapped forms;
  - the pre-launch tier check.
- Each test file runs while it is being developed; the full suite runs before each push.
- **Probes** P1–P14 record their results in `probes.json`, which is kept as an artifact.
- **Live run:** one sandbox issue, from label to ready PR, under each executor. The live run writes to GitHub, so I ask for your approval at that step.
- **Release gate:** version sync across `plugin.json` and `marketplace.json`.
