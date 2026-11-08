# Design record: a router and an unattended worker mode for flow

**Date**: 2026-11-06
**Status**: Proposed (decisions taken by the maintainer on 2026-11-06; nothing built)
**Scope**: `plugins/flow` and a new router layer that serves several repositories
**Layout**: the decision-record layout of `plugins/flow/references/architecture-decision-record.md`
**Alternative**: `2026-11-06-flow-harness.md` puts the router in a separate harness built on the Claude Agent SDK. Both records are kept so they can be compared; Phase 1 below applies to both.

## Summary

Flow runs one issue at a time, in a session a person watches. This record decides how flow gets two
things it lacks: a **router** that takes requests and hands each to its own worker, and a **worker
mode** in which flow's pipelines run without a person at the terminal and reach that person only at
the right moments.

The decision, in one paragraph: first make flow's own pipelines safe to run unattended (the ask policy,
stored questions and four defect fixes shipped in flow 3.15.0; report states and a worker role are
left); then add a personal,
cross-repository router whose state lives in a private git control folder, whose agent cannot edit
code, and which starts one sandboxed background worker per ticket. Workers reach GitHub only through
the router's send helper; they may push their own branch and open a draft pull request, and every
other kind of send waits for the owner's yes. Questions are stored, shown in an inbox, and mirrored to
the GitHub thread only on issues the owner labelled for the router; only blocking questions
interrupt, within a daily budget.

## Context

### What was studied

- **DeepSeek's dsh-superagent prototype** (public, `deepseek-ai/dsh-superagent-prototype`, commit
  `8c32a9d`, read in full: `docs/000`–`008`, `prompts/`, `SETUP.md`). One always-on router session
  takes requests from GitHub or chat, a deterministic gate decides who may ask, a model judges the
  rest, and each accepted request becomes a Ticket with its own worker session and directory. Later
  comments on the ticket's issue or pull request go straight to its worker. Its principle: "Take as
  little human attention as possible, and give as much value as possible." Its weak side: workers
  review their own work (no independent reviewer found in its prompts or tests) and run with the
  operator's full OS access ("These wrappers and directories establish defaults, not a security
  boundary", `docs/003-execution.md`).
- **The DeepSeek essay as reported** (a Medium summary of *Exploring Super-agent Design*, read; the
  essay itself was not found). In a simulated stream of about 300 messages with about 20 real
  requests, a single session with a subagent tool and a neutral prompt delegated in none of five
  runs and took 29.5 minutes to finish 95% of the requests; the router/worker split finished 95% in
  15.7 minutes. DeepSeek calls the test preliminary and it used simulated tools. The lesson taken
  here: the split has to be built into structure (what the router can do), not asked for in a prompt.
- **Two internal design documents** (not public): a comparison of the prototype with an existing
  personal orchestrator, and a v1 specification for an orchestrator plugin for Claude Code. They
  contributed the patterns adopted below that the prototype lacks: a deterministic check of a
  worker's claimed result against git, a single writer for state that commits every change, one
  gated path for everything sent outward with records that are never retried, three-option questions
  with the recommendation first, a rule for when a question may interrupt, and a threat model for
  workers that run unattended (in particular, that git metadata a sandboxed worker can write can make
  git run code when git later runs outside the sandbox).

### What flow has today (each fact checked in the code)

Flow already has strong verification (paired adversarial review, finding critic, verdict judge,
holdout validation, checked descriptions), durable per-issue state (decision journal, FlowGoals,
FlowRuns) and enforced safety tiers. But it assumes a person watches the session:

| Fact | Evidence |
|---|---|
| 74 places involve a person; 47 are `AskUserQuestion` call sites in `commands/`. About 23 are defaults the agent could take itself (the classification is a judgement; several sites sit between "decision" and "default") | a site-by-site inventory of `commands/`, `skills/`, `references/` |
| Every escalation must go through `AskUserQuestion` | `references/escalation-format.md:73` |
| `autonomous` is read by no script or hook; it is prose only | `settings.json:95`; `skills/llm-operator-principles/SKILL.md:66`; no reader in `bin/` or `hooks/` |
| No pending question is stored anywhere; `bin/flow-escalate.sh` only prints the six fields | `bin/flow-escalate.sh:29`; only the outcome is journaled as `escalation-resolved` |
| `/flow:pr` asks the user whenever the goal is not `achieved`, and `/flow:start` never evaluates its goal, so this asks on most runs | `commands/pr.md:621`; no goal evaluation in `commands/start.md` |
| A Tier 2 `confirm` or any Tier 3 action is a refusal in `claude -p` | `hooks/scripts/tier-gate.sh:220` |
| `waiting_for_user` is an allowed goal state but no code sets it; a goal in that state is invisible to the active-goal lookup, so `/flow:merge` reports "gate not applicable" | `bin/flow-goal-record.sh:261`; `bin/flow-active-goal.sh:218`; `commands/merge.md:475-480` |
| The goal Stop hook takes the first active goal file in sorted order, not the current branch's | `hooks/scripts/flow-goal-stop.sh:179` |
| `.flow`, `.decisions` and `.claude/settings.flow*.json` resolve per worktree; the goal trust ledger is keyed by the worktree top | `bin/flow-runtime-dir.sh:12`; `bin/_repo_dir.py`; `bin/flow-goal-trust.sh:25-27` |
| Triggers fire only when a person runs `/flow:run`; the cron, Actions and daemon adapters exist only in the schema | `references/flow-triggers.md:3`; `schemas/v1/trigger.schema.json:5` |

### What Claude Code offers (checked on the installed CLI, 2.1.318)

| Behaviour | How it was checked |
|---|---|
| `--agent flow:<name>` runs a plugin agent as the main session, and its `tools` list is enforced: `flow:verdict-judge` (`tools: []`) started with an empty tool list | `claude -p --plugin-dir plugins/flow --agent flow:verdict-judge`, stream-json `init` event |
| In `claude -p`, `AskUserQuestion` is not among the session's tools | same probe, without `--agent` |
| `claude --bg` starts a background session; `claude agents --json` lists sessions; `attach`, `logs`, `stop`, `rm`, `respawn` manage them | `claude --help`, `claude agents --help` |
| `claude --bg` refuses to start in a folder whose workspace trust was not accepted ("Workspace not trusted") | live probe; trust was not changed to get around it |
| `--permission-prompts none` denies whatever would prompt in `-p` | `claude --help` |
| Plugin modules (mods) exist: panes, `prompt.submit`, timers, `tool.call` and `turn.complete` hooks | the mods type definitions shipped with 2.1.318 |
| Cross-session messages wake an idle session; plugin agents ignore `hooks` and `permissionMode` frontmatter | Claude Code documentation (`cross-session-messaging`, `sub-agents`), not yet tested live |

## Decisions, options and trade-offs

Each decision lists the options considered; the chosen one is marked.

### D1. Shape

| Option | For | Against |
|---|---|---|
| **Router agent on top of a worker mode (chosen)** | the split is structural (the router has no code tools); reuses flow's pipelines as workers; medium build | needs background sessions, a research-preview feature |
| Worker mode only; the person routes | cheapest; uses Claude Code's agent view as the panel | the person stays the router; does not remove tab-switching |
| Full control plane (board, two-model reviewers, sweeps, pane) | most complete | largest build and maintenance surface; duplicates review flow already has |

### D2. Scope

| Option | For | Against |
|---|---|---|
| One repository per router | matches flow's per-repo state | the owner works across repositories |
| **Personal, many repositories (chosen)** | one place for all of the owner's work | needs state outside any repository (D5) |
| One now, many later | small first step | a second migration later |

### D3. Where questions and results reach the owner

| Option | For | Against |
|---|---|---|
| **Inbox first, mirrored to the GitHub thread (chosen)** | the inbox is complete; GitHub reaches the owner's phone | two places to keep consistent |
| Router session only | simplest | the owner must be at that terminal |
| GitHub thread only | asynchronous, team-friendly | noisy; no single list of what waits |

Mirror rule (D3a, chosen over "mirror waits for yes" and "no mirror"): a question is posted
automatically, from a fixed template, only on an issue or pull request in a registered repository
that the owner labelled for the router. Every other comment still waits for the owner's yes (D6).

### D4. Worker isolation

| Option | For | Against |
|---|---|---|
| Tiers only, no sandbox | fastest | a prompt-injected worker has the owner's full access |
| **Sandbox plus one send helper (chosen)** | writes confined to the worker's own clone; GitHub reachable only through the router | medium build; plugin hooks under the sandbox must be proven (S4) |
| No git metadata in the worker folder at all (an external git directory managed by a helper) | strongest | very large build and test surface |

A worker gets its own **clone**, not a linked worktree: a linked worktree shares the main
repository's `.git`, which a sandboxed worker can write, and a later git command outside the sandbox
would read it.

### D5. Router state

| Option | For | Against |
|---|---|---|
| **Private git control folder, one writer script (chosen)** | every change committed: history, audit and recovery | a new folder to set up and back up |
| Per-user state directory (`~/.claude/flow-state/router`) | simple; flow already uses this directory | no history |
| GitHub comment markers (as flow's review-cycle markers) | survives machines | slow; no atomic update; anyone who can comment can forge a marker |

### D6. What a worker may send by itself

| Option | For | Against |
|---|---|---|
| **Its own branch and a draft pull request; every other kind waits for the owner's yes (chosen)** | work becomes reviewable without waiting; nothing reaches people unasked | a comment or "ready for review" waits for the owner |
| Every send waits for the owner | safest | each ticket stalls on the owner |
| Whatever the repository's tiers say | most autonomous | a `confirm` tier stalls an unattended worker |

Merge and release stay with a person in every option (flow's Tier 3 floor is unchanged). A new send
kind starts in shadow: it is recorded, not sent, until the owner promotes it.

### D7. Who may start work

| Option | For | Against |
|---|---|---|
| **Only the owner (chosen)**: requests in the router chat, or issues the owner labels for the router in registered repositories | smallest attack surface | teammates cannot ask |
| Owner plus an allowlist of GitHub logins | team use | needs a permit record per request |
| Either, plus written rules for unrequested work in observe mode | proactive work | more noise to tune |

The ticket record keeps a requester and a scope field, so D7 can widen later without a format change.

### D8. When a question interrupts

| Option | For | Against |
|---|---|---|
| **Only `Blocking: yes`, at most N per day, inside working hours (chosen)** | interruptions stay rare and meaningful | a soft question can wait until review |
| Every question | never misses one | trains the owner to ignore notifications |
| Never; inbox only | quietest | a blocked worker can idle for hours |

`Blocking: soft` questions proceed on their recommendation and appear in the pull request and the
inbox. `Blocking: no` is recorded only.

## The design

### Roles

- **Router** (`flow:router` agent, the main agent of one long-lived session in the control folder).
  Takes requests, checks who asked, creates tickets, starts workers, relays questions and results,
  carries out sends, and checks each worker's claimed result with a script. Its tool list holds no
  edit tools; a role check in flow's hooks is the second layer, because plugin agents ignore `hooks`
  frontmatter. It never reads code to plan and never rewrites a request: a worker gets the original
  request and a routing note of at most 30 words.
- **Worker** (flow's own pipelines, `/flow:start`, `/flow:address`, `/flow:debug`, in worker mode).
  One background session and one clone per ticket. It cannot reach GitHub; it asks the router to send.
- **Watchdog** (a check the router runs on a timer). Finds workers that failed, stalled, or wait on a
  prompt no ticket records.

### Phase 1: worker mode in flow (useful without a router)

**Done in flow 3.15.0** (#342, closing #335–#340): the ask policy is printed by every pipeline's preflight (`bin/flow-ask-policy.sh`, `attended` or `autonomous`) and enforced by a PreToolUse hook on `AskUserQuestion`, with every ask place tagged `[ask: decision|permission|default]`; escalations are stored with id, status and class (`bin/flow-question.sh`); the merge goal gate judges the pull request's own goal and blocks every status but `achieved`; the Stop hook judges the current branch's goal; `/flow:start` evaluates its goal at the end of VERIFY; settings, goals and the journal are read at the repository top. The "What flow has today" table above records the state before these fixes.

**Left:**

1. **Report states and a result block.** A run ends as `ready`, `blocked`, `failed`, `dropped` (nothing
   to do) or `waiting`, with a structured result: head commit, evidence (files, commands with exit
   codes), and what was not verified. The router checks it with a script: the head exists, descends
   from the base, and the evidence paths exist in that commit.
2. **A worker role where `AskUserQuestion` does not exist.** In `claude -p` (this design's workers)
   the tool is absent, so a question must be stored with `flow-question.sh add` and the run must
   stop (`Blocking: yes`) or continue on its recommendation (`soft`) instead of waiting. The ask
   policy has `attended` and `autonomous`; it gains a third value set by the router at launch.
3. **Tier 2 `confirm` in a worker.** In `claude -p` a tier "ask" is a refusal
   (`hooks/scripts/tier-gate.sh`); in a worker it becomes a stored question instead.

Items 2 and 3 exist only because this design runs workers with `claude -p`. Under a host that answers
permission prompts (the Agent SDK, or T3 Code; see the harness record), questions and tier asks reach
the host, so only item 1 is left.

### Phase 2: the router

1. **Control folder.** A private git folder. Its writer script takes a lock, validates, writes, and
   commits each change. It holds:
   - tickets: `owner/repo#N`, requester, scope, the worker binding (clone path, session name and id),
     links to the goal and run, and the subscribed threads
   - an index of open questions
   - the send ledger: `waiting`, `sending`, `sent`, `failed` or `uncertain`. An uncertain send is
     never retried; the owner checks the target.
   - the registered repositories
2. **Workers.** The router clones the repository into a work root whose parent folder the owner
   trusted once (S1). It then starts `claude --bg` with the worker role, a settings file that turns
   the sandbox on, confines writes to the clone, and denies GitHub hosts, and the command
   `/flow:start N`. At most a configured number of workers run at once. One extra slot is kept for a
   reply from the owner, so new work never blocks a reply.
3. **Sends.** A worker requests a send. The router checks it: the branch is the ticket's, and the head
   descends from the base. Pushes of the ticket branch and draft pull requests run at once; every
   other kind waits in the inbox for the owner's yes. Commits leave the worker clone only through the
   intake that S6 proves safe.
4. **Inbox and digest.** `/flow:inbox` lists open questions, sends that wait, and stuck workers.
   Questions use three options with the recommendation first. A `Blocking: yes` question also
   notifies within the daily budget. A daily digest of at most 10 lines starts with "Needs you:".
5. **Follow-ups.** A per-thread cursor watches each ticket's issue and pull request. Review comments,
   CI results and the owner's replies go straight to the owning worker, as a session message or by
   resuming it; the router gets one line.
6. **Watchdog.** Reads `claude agents --json`; restarts nothing that a person parked; reports stalls.

### Phase 0: checks that gate the build

| # | Question | Gates |
|---|---|---|
| S1 | Does trust accepted on a parent folder let `claude --bg` start in fresh clone folders below it? | Phase 2.2 |
| S2 | What does `AskUserQuestion` do in a background session (block, deny, absent)? | Phase 1.1 |
| S3 | Does a cross-session message wake an idle background worker, and which `crossSessionInbound` value does it need? | Phase 2.5 |
| S4 | Do flow's plugin hooks and git/gh shims load in a sandboxed background worker started with `--setting-sources user`? | Phase 1, 2.2 |
| S5 | Does a deny-only PreToolUse hook on `AskUserQuestion` deny as intended, in attended and background sessions? | Phase 1.1 |
| S6 | Can commits leave a worker clone without running anything the worker could have planted in its `.git` (hooks, `core.fsmonitor`, filters, `commondir`, alternates)? Test each vector against a naive command first, so the test can fail | Phase 2.3 |

### Testing

Per `AGENTS.md`, end-to-end tests come first. Phase 1 changes are command blocks, hooks and `bin`
scripts. `plugins/flow/tests/lib/e2e.sh` drives each of these and writes one artifact per scenario.
Each test is run once with the change removed, to show it can fail. Phase 2 needs a real `claude`
(background sessions, sandbox, sends), which `e2e.sh` cannot drive. It gets an integration harness
modelled on `bin/flow-eval-run.sh`, which already runs headless sessions.

## Consequences

- Flow gains a role concept (`attended`, `autonomous`, `worker`, `router`) that hooks read. Until now
  only the goal judge had one (`CLAUDE_HOOK_GOAL_JUDGE_MODE`).
- Questions become data: the inbox, the digest, `/flow:status` and the router can all read them.
- `autonomous: true` changes behaviour by hook, not by the model's memory of a setting.
- The router depends on background sessions and agent view, which are a research preview. If they
  change, Phase 1 still stands on its own, and the router's launch and liveness code is the part to
  adapt.
- A new trust boundary: worker output (commits, result blocks, requested sends) is untrusted input
  to the router. The router checks it with scripts and never executes it.
- Background authentication on some providers is unproven (credentials that expire in long-lived
  background sessions); this is part of S1's environment and is checked per provider.

## Non-goals

- Does not merge or release: Tier 3 stays with a person.
- Does not let anyone but the owner start work in this version.
- Does not do unrequested (proactive) work in this version.
- Does not replace flow's review, verification or goal machinery; workers run them unchanged.
- Does not run workers in the cloud or on another machine.
- Does not guarantee exactly-once sends: an interrupted send is marked `uncertain` and left for the
  owner, never retried.
- Does not isolate a worker from the owner's OS account beyond the Claude Code sandbox; a sandbox
  failure is not covered.
- Does not provide a graphical pane in this version; the inbox is a command.

## Failure modes

| Component | Mode | Expected behaviour |
|---|---|---|
| Ask-policy hook | hook errors or cannot read settings | attended: allow the question (fail open: a person is there to answer it); worker: deny (fail closed) |
| Question store | write fails (lock timeout, disk) | the pipeline stops with the error; a question is never dropped silently |
| Question store | invalid input (missing field, more than 3 options) | refused with the field named |
| Worker launch | folder not trusted | the ticket returns to queued; the inbox shows the one command that accepts trust |
| Worker launch | all slots in use | the ticket stays queued; the reply slot stays free |
| Worker | background session dies | the watchdog marks the ticket stalled; a new worker resumes from the run, journal and goal |
| Worker | waits on a permission prompt | the watchdog reports a setup gap (the allowlist is too narrow), not a question |
| Worker | result block missing or invalid | the ticket stays running until the watchdog or the owner acts; no claim is accepted without the script check |
| Send helper | GitHub times out or refuses | the send is marked `failed` with GitHub's answer; never retried automatically |
| Send helper | process dies while sending | the next writer marks it `uncertain`; the owner checks the target |
| Send helper | requested branch or head not the ticket's | refused; the inbox records the refusal |
| Control-folder writer | lock held | `LOCKED` returned after a timeout; the caller retries the operation |
| Control-folder writer | commit fails | the change stays on disk; the next write commits it |
| Follow-up watcher | GitHub rate limit or outage | the cursor is kept; the next poll reads what was missed |
| Router session | closed | workers keep running and keep their stored results; the reopened router reads state and resumes |

## Related

- `plugins/flow/references/escalation-format.md`: the six fields questions keep
- `plugins/flow/references/three-tier-safety.md`: the tiers sends keep
- `plugins/flow/references/flow-triggers.md`: the trigger layer the router replaces as the way work starts
- `plugins/flow/references/system-one.md`: the shadow-mode pattern new send kinds follow
