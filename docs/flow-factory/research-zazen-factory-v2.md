# The ZazenCodes software factory (v2) for Claude Code: analysis

## Sources and scope

- **Repository read:** `zazencodes/zazencodes-season-3`, branch `main`, fetched 2026-11-11 at HEAD `5fc7c983`. The most recent commit touching the v2 folder is `de4598a8` (2026-11-03). The recursive tree listing was not truncated (`.truncated=false`).
- **Path prefixes used below:**
  - `v2/` means `https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code-v2/`
  - `v1/` means `.../src/software-factory-claude-code/`
- **Read in full (v2):** README, DESIGN.md, INSTALL.md, the factory skill (`.claude/skills/factory/SKILL.md`), all 8 agents, `factory/config.json`, `factory/checks.sh`, and the three scripts `factory/bin/job`, `factory/bin/gate` and `factory/bin/route`. I also read every file of the four example jobs, except that I only spot-read job 002's `spec.md` and `build.md`. 003's `spec.md` came back empty in my output and I did not re-fetch it. The `job.json` files for 001, 002, 003 and 005 were all read.
- **Read in part (v2):** `factory/dashboard.html`, by grep only (how it loads data, the 2-second poll, cost display). `LICENSE`, header only (GPLv3).
- **Not read:** the two PNG images in `v2/docs/assets/`.
- **Read (v1):** README, BUILD_PROMPT.md, the factory skill, `backlog.md`, `approver.md`, the header of `builder.md`, and the `job.json` of example job 001.
- **What is absent:** the whole repository tree has no `.github/` path. A grep of every v2 file I fetched found no `claude -p`, `--print`, cron, schedule or `/loop`. The only match was DESIGN.md: "Nothing runs in GitHub Actions or on a schedule".

## 1. Concept and stated goals

From `v2/DESIGN.md`:

> "A software factory turns a queue of requests into merged code with a fixed pipeline. Scripts handle the deterministic stages, such as running the tests, moving state and merging. Agents do the judgment in between... Each stage leaves a file behind."

From `v2/README.md`:

> "Label an issue `factory`, run `/factory run`, and agents decide whether it's worth building, write a spec, build it, test it with your own checks, review it, and open a pull request that closes the issue. The approver merges what it's sure of and hands you the rest."

The design rests on four principles:

- **Issues are the queue.** GitHub issues labeled `factory` are what gets built.
- **One orchestrator.** A single interactive Claude Code session runs `/factory` and coordinates every job.
- **One file per agent.** Each agent writes exactly one file and replies with one line.
- **A deterministic spine.** Python scripts are the only writers of state and enforce the legal moves between stages.

The whole thing is small: one skill, 8 agents, 3 Python scripts (standard library only), a config file, `checks.sh` and a dashboard (`v2/DESIGN.md` "Pieces").

## 2. Pipeline, end to end

The stages are listed in `v2/DESIGN.md`. The legal moves between them are in `TRANSITIONS` in `v2/factory/bin/job`, lines 41–51.

| # | Stage | Done by | Reads | Writes |
|---|---|---|---|---|
| 0 | queue / create | `job queue`, `job create <n>` | open issues labeled `factory` | `job.json`; `issue.md` (body and trusted comments, quoted with `>`) |
| 1 | intake | `intake` agent (Fable) | `issue.md`, earlier `intake-*.md`, AGENTS.md, code | `intake.md`: header lines `DECISION`, `RISK`, `SURFACES`, `RESCOPED`, then Summary, Scope, Why and Questions sections |
| 1a | after intake | `bin/job advance` | `intake.md` header | Posts the decision as an issue comment. NEEDS-INFO adds the `factory:needs-info` label; REJECT removes `factory`; ACCEPT creates the worktree `.worktrees/<id>` on branch `factory/<id>` from `origin/<base>` |
| 2 | route | `bin/route` | `intake.risk` and `.surfaces` in `job.json`; `config.json` | `job.json.agents.reviewers` |
| 3 | spec | `spec-writer` (Opus) | `issue.md`, `intake.md` (its Scope is binding), AGENTS.md, code | `spec.md`: Summary, Context, Requirements, Acceptance criteria, Out of scope, Assumptions |
| 4 | build | `builder` (Opus), named `builder-<id>` and resumed with SendMessage | `spec.md`, earlier `checks.md` or `checks.log`, reviews, `feedback-*.md` | Commits and push; a draft PR with "Closes #n"; `build.md` (`STATUS: READY` or `STATUS: BLOCKED`) |
| 5 | build → gate | `bin/job advance` | `build.md` first line; `git status`; commits ahead of base; local HEAD equal to the remote; exactly one open PR | `job.pr` |
| 6 | gate | `bin/gate` | the main checkout's `checks.sh`, run inside the worktree; diff against `protected_paths` | `round-N/checks.md` (`GATE:`, `COMMIT:`) and `checks.log` |
| 7 | review | routed reviewers, run in parallel, and the orchestrator waits for all of them | spec, build, diff, the reviewer's own earlier review | `round-N/review-<r>.md` (`VERDICT: PASS` or `VERDICT: CHANGES`) |
| 8 | approve | `approver` (Opus) | the whole job folder and the diff | `decision.md` (`APPROVE` or `ESCALATE`) |
| 9 | merge | `job merge` | — | Merges `origin/<base>` into the branch, re-runs the gate (`merge-checks.md`), pushes, marks the PR ready, then `gh pr merge --<method>` and deletes the branch. The job ends in `merged`, or in `needs-human` on any failure |
| 9' | escalate | `advance needs-human` | `decision.md` | Marks the PR ready, posts the decision as a PR comment, adds the `factory:needs-human` label |

**Stages:** `intake`, `needs-info`, `spec`, `build`, `gate`, `review`, `approve`, `merging`, `needs-human`, `merged`, `rejected`. Any unfinished job can move to `merged` once its PR has been merged on GitHub (`bin/job` lines 369 and 553–555; commit `0e29a152`).

**Round budget:** at most `max_rounds` (3) rounds. When the last round fails, the move to `needs-human` is forced by the `last == (stage == "needs-human")` check (`bin/job` lines 452–454 and 468–470). Human feedback grants a fresh budget: `round_limit = round + max_rounds` (line 486).

## 3. Each component: role, inputs, outputs, tools

| Component | Model | Tools | Role |
|---|---|---|---|
| `intake` | `fable` | Read, Grep, Glob, Write (no Bash) | "Your decision is the most important one in the factory." Decides ACCEPT, NEEDS-INFO or REJECT; may rescope to "a smaller first slice"; rates risk (low/medium/high) and surfaces (ui/security). Writes `intake.md`. |
| `spec-writer` | opus | Read, Grep, Glob, Bash, Write | "Don't stop to ask"; records its own calls under Assumptions; smallest change; each acceptance criterion comes with how to verify it; never requires a change to a protected path. |
| `builder` | opus | Read, Grep, Glob, Bash, Edit, Write; has a `Stop` hook | Works in the worktree; first checks that the branch is right; runs `checks.sh`; checks UI criteria in a browser with `agent-browser --session <id>-builder` on its own port; stages explicit paths only; opens a draft PR and never marks it ready or merges it; writes `build.md`, keeping a log entry per round. |
| `reviewer-code` | haiku (overridden by routing) | Read, Grep, Glob, Bash, Write | Correctness, simplicity, reuse, conventions, docs, tests ("no existing test was weakened"). "Don't re-run the test suite". |
| `reviewer-security` | opus | same | Access control, input, XSS, data exposure, payments, abuse, secrets, dependencies. Does not block on issues the change did not introduce. |
| `reviewer-ux` | sonnet | same | Uses the page like a visitor with agent-browser; "Don't sign in or submit forms". Checks flows, states, copy, accessibility and phone width. |
| `reviewer-ui` | haiku | same | Screenshots at desktop and phone widths; consistency with the design tokens; contrast. |
| `approver` | opus | Read, Grep, Glob, Bash, Write | APPROVE only when every criterion is met with evidence, it has spot-checked one itself, the gate passed and every review passed, and the change stays inside intake's scope. ESCALATE for money, auth, deploy/CI, migrations, email, production data, new dependencies, or a business assumption. "Don't escalate to be safe." |
| `factory` skill | session model | — | The only orchestrator. "You never write code... never edit `job.json`." Reads agents' files only by their first line: "Your context has to last the whole run." |
| `bin/job` | Python | — | The only writer of `job.json` (holds an `flock` lock and writes atomically). Commands: `queue`, `create`, `advance`, `merge`, `feedback`, `reject`, `agents`, `sync`, `summary`. Also performs the GitHub side effects (comments, labels, PR ready/close/merge, worktree add/remove). |
| `bin/gate` | Python | — | Runs the main checkout's `checks.sh` in the worktree, checks `protected_paths`, and writes `checks.md`. With `--hook` it is the builder's stop nudge (exit code 2). |
| `bin/route` | Python | — | Maps risk and surfaces to the reviewer set through `config.json`. |
| `dashboard.html` | static JS | — | Polls `jobs/` every 2 s (`POLL_MS = 2000`) through `python3 -m http.server`. Shows a card per job, chips per round, cost and time, and a drawer showing the job's files. |

**Routing** (`v2/factory/config.json`): `low` → code review on Haiku; `medium` and `high` → code review on Sonnet. The `ui` surface adds ux (Sonnet) and ui (Haiku); the `security` surface adds security (Opus).

**Ports** (`v2/factory/config.json`, SKILL.md): base 5100, step 10. For job number `n`, the builder gets `5100+10n`, ux `5101+10n` and ui `5102+10n`.

**Builder hook** (`v2/.claude/agents/builder.md` frontmatter): the builder agent declares a `Stop` hook that runs the factory's `gate` script in hook mode.

DESIGN.md and the `gate` docstring call this a "SubagentStop hook", while the frontmatter declares `Stop`. I did not check the Claude Code hooks documentation to see how a `Stop` hook in agent frontmatter maps to subagent stop. The hook gets the job id by reading the first line of the agent's transcript and splitting on `"Job: "` (`bin/gate` `hook()`). It fires once per stop, because it exits early when `stop_hook_active` is set.

## 4. Autonomy

**What runs unattended:** after one manual `/factory run`, the whole intake → merge chain runs without a human, including the automatic merge on APPROVE. SKILL.md, under "/factory run":

> "Each time a job finishes, run `factory/bin/job queue` again and start its `resume` lines... When nothing is queued or running, print `factory/bin/job summary`".

**Trigger:** manual only. From DESIGN.md:

> "Nothing runs in GitHub Actions or on a schedule: the factory runs on your machine, on your Claude plan, when you start it. An issue can't start a Claude Code session by itself."

**What is not used** (based on the v2 files listed in Sources, plus the absence of any `.github/` in the repository): headless `claude -p`, cron, `/loop` and GitHub Actions workflows. The orchestrator learns that a background subagent has finished through the session's own notification: "While agents run, don't poll and don't wait: end your turn with a one-line status" (SKILL.md "Spawning agents").

**Parallelism:**

- Up to `concurrency` jobs (default 3) at once. This is enforced by the scripts (`require_slot`, and the hold rows in `cmd_queue`; commit `3ce1b9c2`). Every job in a running stage holds a slot even when no agent is working on it.
- Reviewers are spawned "in one message" so they run in parallel.
- DESIGN.md states: "Claude Code allows 20 concurrent subagents per session by default, which covers three jobs with four reviewers each." I did not verify this limit against the Claude Code documentation.

**Isolation:**

- Each job has its own worktree at `.worktrees/<id>` and its own branch `factory/<id>`.
- Each job has its own dev-server ports and agent-browser sessions, and agents stop only the server on their own port: "never kill by process name" (builder and reviewer prompts; commit `34dbccec`).
- The main checkout is never modified, because the merge happens through `gh pr merge`.

## 5. Human checkpoints

1. **Labeling an issue `factory`.** This is the trust boundary: "only people with triage or write access can add labels" (`v2/DESIGN.md` Guardrails). `job create` refuses an issue without the label.
2. **NEEDS-INFO.** Intake asks the author on the issue and the job parks. `replied_since_question()` sees a reply posted after the factory's last marked comment, and `queue` then shows the job as `resume` (`bin/job` lines 221–230).
3. **ESCALATE or BLOCKED → `needs-human`.** The PR is marked ready and the decision is posted on it. The human then either:
   - merges the PR on GitHub, which approves it (`queue` moves the job to `merged`);
   - runs `/factory <feedback>` → `job feedback` → writes `feedback-k.md` → a new build round with a fresh budget;
   - runs `/factory reject` → `rejection.md` → a comment on the issue, the labels are removed, the PR is closed and the branch deleted.
4. **Starting a run** is itself a human action.
5. **Install hand-off** (`v2/INSTALL.md` step 4): "Ask before pushing". The README also advises: "Start with `concurrency: 1` and read every PR until you trust it."

There is no human approval of the spec. The spec-writer is told explicitly "Don't stop to ask".

## 6. Quality controls

- **Deterministic gate** (`v2/factory/bin/gate`). It runs `factory/checks.sh` from the main checkout, "so a branch can't edit the checks it is judged by". It fails when a file matching `protected_paths` is modified or deleted (adding new files is allowed). It runs before any review and again after syncing with the base branch, before the merge.
- **Freshness of the gate result.** `advance gate→review` requires `checks.md`'s `COMMIT` to equal the current HEAD: "checks.md was written for another commit; run the gate again" (`bin/job` lines 445–446).
- **Preconditions for build → gate.** `STATUS: READY`, a clean tree, at least one commit, local equal to remote, and exactly one open PR (lines 420–434).
- **Reviews.** All routed reviewers must have written a file with a valid verdict line (`check_reviews_done`), and every review must pass before the move to approve.
- **Approver.** Spot-checks at least one acceptance criterion itself and escalates per its list.
- **Test integrity.** `protected_paths` holds only `factory/checks.sh` and `factory/config.json`. Tests are deliberately left unprotected, and the code reviewer is relied on to catch weakened tests. INSTALL.md: "a protected test blocks the job with no way through" (commit `629500c1`, "Stop protecting project tests").
- **Stop hook** on the builder: a nudge only — "the gate is still what decides".
- **Rollback:** none. `bin/job` has no revert command, and on `rejected` or `merged` the worktree is force-removed (lines 500–502). Failures before the merge (conflict, gate failure after sync, `gh` failure) move the job to `needs-human` (`cmd_merge` `fail()`). Nothing verifies the result after the merge, and "The factory never deploys."

## 7. State, memory and resuming

- **Where state lives.** `factory/jobs/<id>/` is gitignored and local to the machine: `job.json`, `issue.md`, `intake[-k].md`, `spec.md`, `build.md`, `round-N/{checks.md, checks.log, merge-checks.md, review-*.md}`, `decision.md`, `feedback-k.md`, `rejection.md`, and a `.lock` file.
- **Fields derived from files.** `sync()` re-derives intake, gate, reviews and cost from the files, so the files are the source of truth.
- **Resuming.** From SKILL.md: "a new session picks up where a dead one stopped." Each stage is re-run idempotently:
  - `build` starts a new builder told it is resuming (it reads `build.md` and `git log`);
  - `review` spawns only the reviewers whose file is missing;
  - `merging` re-runs `job merge`.
- **Memory across rounds.** The builder is resumed with SendMessage to `builder-<id>`, so its conversation context carries over. Reviewers read their own review from the previous round. The log in `build.md` accumulates.
- **Cost.** `cost_usd()` scans `~/.claude/projects/<project>/*/subagents/agent-*.jsonl` for transcripts whose first prompt contains `Job folder: <path>/`, and prices them with `prices_usd_per_mtok`. DESIGN.md: "The transcript format isn't a documented interface, so a Claude Code update could break this."

## 8. Strengths and weaknesses

### Strengths

1. **Scripts hold authority over state.** The orchestrating model cannot make an illegal move: "When a script refuses, its message says why. Fix the cause or stop... never work around it." Its preconditions are checked against files and git (COMMIT equals HEAD, pushed, clean tree).
2. **Intake is a real filter, and decisions go back on the issue.** Example 003 rescoped a "full scientific calculator" issue down to three functions. Example 005 rejected a crypto-mining request: "That is cryptojacking".
3. **Review cost follows risk,** and the routing table lives in config rather than in prompts.
4. **Every artifact opens with a machine-readable first line and a Summary section.** This keeps the orchestrator's context small and makes the dashboard possible.
5. **Prompt-injection controls.** Issue text is quoted and labeled as data, only comments from the author and the operator are kept, the agent that reads it first (intake) has no shell, and the label is the trust boundary.
6. **Merging through GitHub** applies branch protection, plus a re-gate after syncing with the base branch to catch interference between jobs.
7. **Resuming works by construction,** because state is in files and each stage re-runs idempotently.
8. **The escalation bar is two-sided:** "Don't escalate to be safe."

### Weaknesses and failure modes

Each item is confirmed in the code unless it is marked as inferred.

1. **No unattended trigger.** It needs a live interactive session (DESIGN.md). Nothing runs on a schedule or from CI, and nothing reacts to new issues or to an author's reply to NEEDS-INFO until the next manual run.
2. **One orchestrator for everything.** Long runs depend on one session's context ("Your context has to last the whole run") and on its subagent limit. Resuming mitigates a dead session; that a compaction partway through a run could also cause trouble is my inference.
3. **`protected_paths` is narrow.** It covers only `factory/checks.sh` and `factory/config.json` (`config.json`), not `factory/bin/*`, `.claude/agents/*` or `.claude/skills/factory/*`. In the current revision, a branch that edits the gate, the job script or the approver prompt passes the gate, and only an LLM reviewer or the approver would flag it.
4. **The gate's integrity is partial.** `checks.sh` comes from the main checkout, but the commands it runs (for example `npm test`, a package.json script) resolve inside the worktree, which the builder controls. This is inferred from the gate running with `cwd=worktree`. Tests are unprotected by design.
5. **ESCALATE rules are prose only.** "Adds a dependency" and "changes CI or deploy config" are enforced by the approver model alone. No script checks the diff for lockfiles or workflow files before merging.
6. **No post-merge verification and no rollback.** The re-gate covers a local `checks.sh` on the merged-with-base commit. Reviewers do not re-review after the sync merge (`cmd_merge` re-runs only the gate). There is no CI watch and no revert path.
7. **Merge conflicts always need a human.** `cmd_merge` aborts the merge and escalates: "The branch conflicts with main". There is no automatic rebase or conflict resolution.
8. **No dependencies or ordering between issues.** Jobs are taken in issue-number order (`cmd_queue` sorts by number). Rescoped work that intake "left out" is not filed as follow-up issues.
9. **Spec quality has no gate of its own.** Example 003 (from an earlier revision) shows the spec requiring a change to a protected file. It took three rounds before anyone escalated, and two of them were spent on the contradiction.
10. **Cost tracking depends on the undocumented transcript format** and on the exact header string, as DESIGN.md itself acknowledges. The orchestrator's own tokens are not counted.
11. **`cmd_create` checks for duplicates only against local `factory/jobs/`** (line 518). The `.worktrees` and state are per machine, so two machines running the factory on the same repo would each create jobs. That last consequence is inferred.
12. **The examples do not match the current code.**
    - The example job state records `agents.builder: "haiku"`, but the current `route` writes only reviewers.
    - The examples behave as if `tests/test_calc.py` was protected (the 003 gate failure), whereas the current config protects only factory files.
    - Example 003's `decision.md` contains a `## Summary` section that `escalate()` does not write.
    - Example 003's `job.json` says round 3, but there is no `round-3/` folder.

    They are illustrations from an earlier revision, not output of the current code.
13. **Coordination is by text conventions.** It relies on the `Job: <id>.` prompt prefix (the hook parses it), the `Job folder: <path>/` string (cost), and first-line formats. INSTALL.md warns that "Claude Code ignores unknown keys without a warning, so a typo silently changes behaviour."
14. **Resolving a job by issue number** returns the first match (`resolve`, line 148). Collisions are mostly prevented by `create` refusing duplicates, but a rejected-then-recreated issue requires deleting its folder by hand.

## Changes from v1 to v2

Sources: the "What changed from v1" table in `v2/DESIGN.md`, and `v1/` README and SKILL.md.

| v1 | v2 |
|---|---|
| `/factory <feature>` or `/factory next` from `backlog.md`; one job per session; parallelism by opening several sessions | `/factory run` takes from the issue queue, one orchestrator, `concurrency` jobs at once |
| The skill wrote `job.json` itself | The `bin/job` state machine is the only writer and refuses illegal moves |
| All 4 reviewers always run (code review on Sonnet) | Fable intake plus script routing by risk and surfaces |
| Every verdict comes from a model | `checks.sh` gate before review and before merge; protected paths |
| Local `git merge --no-ff` into a clean `main` checkout; "Never push" | A PR per issue, `gh pr merge`, re-gate after syncing |
| `/factory approve`, `/factory rework` | Merge on GitHub, or `/factory <feedback>` → `job feedback` / `job reject` |
| The spec-writer could stall on questions | Intake asks on the issue and parks the job (NEEDS-INFO) |
| No cost visibility | Cost and time per job from transcripts |
| `MAX_RESUMES = 2`; the orchestrator wrote ESCALATE itself when rounds ran out | `max_rounds` enforced by the script; `escalate()` writes `decision.md` |
| Worktrees at `../<repo>-factory/<id>` | `.worktrees/<id>` inside the repo |
| The v1 approver ran `git merge-tree` to check for conflicts | Conflicts are handled by `job merge` |
| No hook on the builder (v1 `builder.md` frontmatter has only name, description, tools, model) | Builder has a stop hook running the gate |
| No license | GPLv3 |

`v1/BUILD_PROMPT.md` keeps the original one-shot prompt that built v1, which used a single `board.json` (later replaced by one `job.json` per job).