# Design record: a separate harness that orchestrates Claude Code with flow built in

**Date**: 2026-11-06
**Status**: Decided on 2026-11-08 by the maintainer: **H1-b**, T3 Code as the runtime with a thin deterministic layer of our own, plus a review step by a model from a different vendor. The decision was made on the condition that check C6 passed, and it did (see "C6 results"). The own-harness design below is kept as the fallback, and its decisions (H2–H5, the carried-over decisions) still apply to the thin layer where they fit. Nothing is built.
**Alternative to**: `2026-11-06-flow-router-and-worker-mode.md` (the plugin-only router). Both records are kept so they can be compared; its Phase 1 (flow fixes) applies to both, and most of it shipped in flow 3.15.0.
**Layout**: the decision-record layout of `plugins/flow/references/architecture-decision-record.md`

## Summary

**Chosen (H1-b):** T3 Code runs the Claude Code sessions, with flow installed. Our thin deterministic layer runs beside it and signs in to T3 once with OAuth. It decides what work starts, launches one worktree thread per ticket through T3's MCP, and answers questions it is allowed to answer. It routes everything else to the owner, owns the path to GitHub, and adds a review by a different vendor's model before work is offered for review. See "The thin layer on T3 Code" below. The rest of this summary describes the own-harness fallback.

A separate program in its own repository, run by each person on their own machine, orchestrates Claude Code sessions with the flow plugin bundled at a pinned version. Its router is deterministic code, not a model session. Each ticket runs as one Claude Agent SDK session in its own clone with flow loaded. Every question flow asks (`AskUserQuestion`) and every approval flow's tier gate asks for reaches the harness as a callback, without changing flow. The harness stores them, shows them in a local web panel and a CLI, and resumes the worker with the answer. The harness holds the GitHub credentials and does all sending; workers have none.

## Context

The plugin-only record puts the router inside Claude Code: a tool-restricted `flow:router` session that starts `claude --bg` workers. That design depends on features that are a research preview (background sessions, agent view, cross-session messages), needs workspace trust for every worker folder, and requires flow itself to store questions because `AskUserQuestion` does not exist in headless runs. A harness built on the Claude Agent SDK avoids those dependencies. This was checked by running the SDK, not only by reading its documentation.

### What was verified by running it (Agent SDK `@anthropic-ai/claude-agent-sdk` 0.3.319, Claude Code 2.1.318)

| Behaviour | Probe and result |
|---|---|
| The SDK loads flow as a local plugin | `plugins: [{type: 'local', path: 'plugins/flow'}]`; the init message listed flow 3.14.0 and 55 `flow:` commands |
| Flow's own command hooks run under the SDK | `SessionStart` and `Stop` hook events were emitted for flow's hooks |
| `AskUserQuestion` reaches the host and is answered by it | the host's `canUseTool` received the question, waited 3 seconds (standing in for a person), returned `answers`; the model continued with the answer |
| Flow's Tier 3 gate reaches the host as an approval request, even when the tool was pre-allowed | `git push origin refs/tags/v9.9.9` reached `canUseTool` with the reason "Flow tier gate. Creating a release or pushing a tag is a Tier 3 action (tiers.release)…"; the host denied it and nothing was pushed |
| A tool call can be parked durably | the SDK types define the hook decision `defer` and the terminal reason `tool_deferred`; resuming the session fires the same call again (documented in the hooks reference; not yet run) |
| Permission callbacks have no deadline | SDK type comment: "permission prompts have no park deadline" |

### What the documentation says (code.claude.com, read 2026-11-06)

- The SDK accepts an Anthropic API key, Amazon Bedrock, Google Vertex AI and Microsoft Foundry credentials. "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK" (Agent SDK overview). The legal and compliance page adds that the rule "does not prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription".
- Order of permission checks: hooks, deny rules, ask rules, mode, allow rules, then `canUseTool`. A call an allow rule approves never reaches `canUseTool`, so policy gates belong in a PreToolUse hook. (The probe showed a hook's "ask" still reaches `canUseTool` over an allow rule.)
- `env` replaces the session's environment, so the harness decides exactly which variables a worker gets.
- Sessions resume by id (`resume`); a resumed session reports the session's total spend.

### Existing orchestrators considered

Several open-source orchestrators run coding agents in parallel git worktrees. The closest is Agent Orchestrator (`OrchestratorInc/agent-orchestrator`, Apache-2.0, Go daemon, desktop and mobile apps, routes CI and review feedback to the owning agent). Its own status page says its modes "are not OS or network isolation". It documents no plugin or extension API and no mapping of `AskUserQuestion` to its approval flow. Its roadmap is its own.

### T3 Code, tested with flow (2026-11-07)

T3 Code (`pingdotgg/t3code`, MIT, TypeScript) is a local server that runs coding agents, with desktop, web, iOS and Android clients. Its README says it is "very very early" and "(mostly) not accepting contributions yet", and its releases are nightly pre-releases. Its Claude driver is built on the Claude Agent SDK, found by searching its source: `ClaudeAdapterV2.ts` imports `@anthropic-ai/claude-agent-sdk` and passes `canUseTool`. It adds MCP tools that let one agent thread start, message and wait on others. Its documentation calls this "orchestration v2".

Tested on the npm release `t3` 0.1.7 (Claude Code 2.1.319 inside T3). Flow 3.14.0 was installed in a separate Claude config directory that T3's Claude sessions used, and threads ran in a scratch repository. Each result was read from T3's own thread state, from the file system, or from its web UI, not from the agent's reply.

| # | Question | Result |
|---|---|---|
| T1 | Does flow load in a T3 Claude thread? | Yes. T3's Claude provider listed 58 `flow:` slash commands and 32 flow skills; the thread confirmed it had them |
| T2 | Does a question surface, and can it be answered later from outside the thread? | Yes. `t3 thread start --wait` exited 2 with status `waiting`. About two minutes later, a second thread used T3's `t3_pending_request` tool (`list`, `read`, `respond`) to answer it, and the first thread went on with the answer |
| T3 | Does flow's Tier 3 gate reach a person? | Yes. This held even in T3's default "full access" mode, which runs the SDK in `bypassPermissions`. The web UI showed flow's reason ("Flow tier gate… Tier 3 action (tiers.release)") with Approve and Decline. Decline made the tool call fail with "User declined tool execution"; no tag was created |
| T4 | Does a pending question survive a server restart? | Partly. The restart cancelled the run, but the question stayed listed. Answering it afterwards started a new turn with the answer as a message, and the thread finished with it. The original tool call was not resumed |
| T5 | Does Claude Code's sandbox apply to T3's workers? | Yes, with `sandbox.enabled` in the settings T3 loads. A write to the home directory failed with "Read-only file system", even in full-access mode. (Writes under the temporary directory are allowed by design.) |
| T6 | Can the sandbox deny a host to a T3 worker? | Yes. A host that answered 200 outside the sandbox returned a 403 to the worker once it was on `sandbox.network.deniedDomains` |
| T7 | Can a thread delegate to a child thread? | Yes. `delegate_task` in wait mode created a child thread, recorded as a subagent of its parent, and returned its reply |

What the tests did not settle:

- T3's MCP tools state that `t3_pending_request` "cannot approve a permission request": approvals need a person in a T3 client.
- An outside program could not reach T3's MCP endpoint with a scoped bearer token; it asks for an OAuth client or an agent session's token. Driving T3 from a deterministic program, through OAuth or the WebSocket API its clients use, is untested.
- A full `/flow:start` run inside T3, worktree-per-thread, and webhook-triggered tasks (`schedule_task`) were not tested.
- T3 has no gated path to GitHub: with GitHub denied in the sandbox, something other than the worker has to push. It has no intake from GitHub issues and no mirroring of questions to GitHub.

### C6 results (2026-11-08, T3 Code 0.1.7, flow 3.15.0)

**C6a: a separate program drives T3. Passed.** A plain Node program (no model) did all of the following:

- registered itself at T3's OAuth endpoint (`/oauth/mcp/register`, PKCE, scopes `orchestration:read orchestration:operate`)
- was approved once by a person on T3's approval page, which offers access levels from read-only to full access. With full access it received `orchestration:read orchestration:operate settings:write source-control:write`.
- exchanged the code for a bearer token that lasts 30 days, with no refresh token, so the owner approves again each month. The token survived a T3 restart.
- over MCP:
  - launched a thread with `t3_thread_launch`
  - listed and read its pending question with `t3_pending_request` (question id, header and labelled options)
  - answered it
  - waited with `t3_thread_wait`; the thread completed with the answer, confirmed with `t3 thread show`

Limits found:

- `create_threads` refuses a client signed in from outside a thread ("thread_credential_required"); `t3_thread_launch` works.
- Approvals are not listed or answerable over MCP; the thread's `pendingRequestCount` shows one is waiting.

**C6b: `/flow:start` in a T3 worktree thread with the sandbox on. Passed, after four setup steps that belong to the thin layer.**

The setup:

- A fixture project: a small Python module, a local bare `origin`, and `autonomous: true` in its flow settings.
- A stub `gh` on T3's PATH that answered `/flow:start`'s GitHub calls from a fixture issue with three acceptance criteria and logged every call. No real GitHub issue was touched.
- The program launched `/flow:start 1` with `workspaceStrategy: worktree`, on Sonnet 5.5, in full-access mode. Claude Code's sandbox was on, with `api.github.com` and `github.com` denied.
- A supervisor loop (a stand-in for the thin layer) answered each question with its recommended option and logged approvals.

Outcome, checked on disk and not taken from the agent's summary:

- the branch `feature/issue-1-add-subtract-function`, with `subtract` and its tests staged
- 4 tests pass and every acceptance-criteria command passes
- the goal is `achieved` with evaluation `pass`
- flow's independent verdict judge returned PASS for 3 of 3 criteria
- 2 question rounds, both answered by the layer: the specification's failure modes, interface contract and risk map; then an environment question
- 1 approval, answered by a person in T3's web UI. It was a false positive (flow defect 1 below).

What it took:

1. **Sandbox placeholders.** On Linux, the sandbox shows placeholder files for the paths it protects (`.bashrc`, `.gitconfig`, `.claude/settings.json`, `.mcp.json`, `.vscode` and others, 23 in this run) inside the worktree. They are visible only inside the sandbox, so `git status` there is never clean and flow's preflight stops with "Uncommitted changes". The layer adds them to the project's `.git/info/exclude`.
2. **Flow's per-user directories.** Flow writes `~/.claude/flow-state` (goal trust ledger) and `~/.claude/flow-goal-judge` (the verdict judge), both outside the worktree. The sandbox made them read-only, so the trust-ledger write failed and the judge could not start. The layer adds both to `sandbox.filesystem.allowWrite`. The run then finished.
3. **Commit signing.** The git config used for the run signs every commit (SSH signing). Inside the sandbox the signing agent was unreachable, so the worker left the change staged and did not commit. The layer must either allow the signing agent's socket, or commit and sign outside the sandbox as part of its send path.
4. **Upstream tracking.** In a linked worktree, `.git/config` is outside the sandbox's write area, so `git checkout -b` could not record upstream tracking. This is harmless when the layer pushes.

Also observed: a turn can end while flow's planner subagent still runs in the background. T3 marks the run completed, and starts a new run when the subagent finishes. The layer has to wait with `untilDelegatedWorkSettled: true`, not on the first `completed`.

Flow defects found by the run (flow 3.15.0, reproduced outside T3):

1. **False-positive Tier 3 ask.** `hooks/scripts/tier-gate.sh` asks for Tier 3 approval when a command's program is a variable (`"$FLOW_ROOT/bin/journal-append.sh"`) and its quoted heredoc (`<<'EOF'`) contains markdown code spans with backticks. The gate reads them as substitutions of an unknown program that "may merge a pull request or create a release". Flow's own instructions write journal sections this way, so this interrupts a person in attended use as well. The same text through `cat` is allowed, and so is a heredoc without backticks.
2. **Local imports fail in goal checks.** `hooks/scripts/flow-run-deterministic-checks.sh` exports `PYTHONSAFEPATH=1` (line 51) and runs goal verification commands with it. A criterion such as `python3 -c "import calc; …"` then fails with `ModuleNotFoundError` in a directory where it passes. The worker worked around it by prefixing its goal commands with `PYTHONSAFEPATH=`.

## Decisions, options and trade-offs

### H1. How flow gets orchestration

| Option | For | Against |
|---|---|---|
| Own harness on the Agent SDK (fallback) | the router is deterministic code; every flow question and approval arrives as a callback with no flow change; no research-preview dependency; one process owns state, credentials and sends | a new product to build and maintain; SDK is 0.x and releases often |
| **H1-b: T3 Code as the runtime, with a thin deterministic layer of ours on top for intake, policy, the send path, the GitHub mirror and a different-vendor review (chosen)** | T3 already provides sessions, questions that can be answered later, approvals in desktop and mobile apps, and delegation. Claude Code's sandbox applies to its workers (T1–T7). A separate program drives it over OAuth and MCP, and a full `/flow:start` completed inside it (C6). Much less to build | an approval needs a person in a T3 client; pre-release and not taking contributions, so we follow its roadmap; its orchestrator is an agent session, so our layer, not T3, holds the deterministic routing |
| Plugin-only router (the other record) | no new repository | relies on background sessions and agent view; flow must store questions itself |
| Extend Agent Orchestrator | desktop and mobile apps exist | no sandbox, no plugin API, asynchronous `AskUserQuestion` not shown; not our roadmap |
| Own harness driving `claude -p` processes | any language | reimplements what the SDK wraps; the permission-prompt tool's contract is not documented |

### H2. Authentication

| Option | For | Against |
|---|---|---|
| Bring your own API key or cloud credentials only | clearly within the documented policy | pay per use, even for personal use |
| **API key by default, plus an opt-in personal mode on the person's own login (chosen)** | cheaper for someone running it only for themselves | the documentation does not clearly cover unattended workers on a subscription |
| Cloud provider only | fits organisations that must use their cloud account | narrowest audience |

Personal mode is off by default. Setup turns it on only after showing the two quoted policy passages and the statement that unattended use on a subscription is not clearly covered, and after the person confirms they run the harness only for themselves. The harness never offers it as a service to others.

### H3. Where people see and answer what needs them

| Option | For | Against |
|---|---|---|
| **Local web panel and a CLI (chosen)**; questions also mirrored to the owner's labelled GitHub issues (as decided for the router) | one "needs you" list; answers from the browser or terminal; phone access through GitHub | a web stack to maintain |
| CLI or terminal UI only | smallest build | no shareable view |
| GitHub only | no local UI | no single list of what waits |

### H4. Language

| Option | For | Against |
|---|---|---|
| **TypeScript (chosen)** | the SDK's primary language: `SessionStart` and `SessionEnd` hook callbacks are TypeScript-only, and `interrupt()` is documented for TypeScript | flow's helpers are bash and Python, so two toolchains |
| Python | matches flow's helpers | lags the TypeScript SDK on the features above |
| Go, driving the CLI | single binary | no official SDK (see H1) |

### H5. How a question waits

| Option | For | Against |
|---|---|---|
| Keep the callback waiting in memory | simplest; context stays loaded | holds a worker slot; lost if the harness stops |
| Park every question with `defer` and resume on the answer | survives restarts; frees the slot | one deferred call per turn; resume cost |
| **Wait in memory for a short window, then defer (chosen)** | quick answers stay cheap; long waits survive restarts and free the slot | two paths to test |

### Decisions carried over from the router record

Personal and cross-repository; state in a private git control folder written by one writer (here, the harness daemon) that commits each change; workers sandboxed, each in its own clone; a worker's own branch and a draft pull request go out at once, every other send waits for the owner; only the owner starts work; only `Blocking: yes` questions interrupt, within a daily budget; questions mirrored automatically only on issues the owner labelled for the harness.

## The design

### The thin layer on T3 Code (chosen)

```
 owner's CLI ─────────┐                                    ┌─> T3 worktree thread t42: Claude Code + flow,
 labelled GitHub issues ┼─> THIN LAYER (deterministic) ── MCP ──┤     sandbox on, no GitHub write access
 ticket PR activity ───┘    control folder (git)            └─> T3 review thread t42-r: other vendor's model,
          ▲                         │                             read-only, diff at the pinned head only
          │                         └── send path: commit/sign, push branch, draft PR (only path to GitHub)
          └── questions (answered or routed to the owner) · approvals (owner, in T3's apps)
```

**What T3 provides:**

- sessions and worktrees
- questions that can be answered later
- approvals in its desktop, web and mobile apps, with push notifications
- delegation and restarts
- several model vendors behind one MCP surface

**What the layer does**, in the order a ticket meets it:

1. **Setup, once per machine and per repository.**
   - Sign in to T3 by OAuth: the owner approves once and picks an access level, and approves again every 30 days.
   - Register each repository as a T3 project.
   - Write the sandbox-placeholder names into the project's `.git/info/exclude` (C6b step 1).
   - Write the Claude settings T3 loads:
     - the sandbox on
     - GitHub hosts handled as C7 decides
     - `allowWrite` for flow's per-user directories (C6b step 2)
     - a pinned flow version
   - Set `autonomous: true` in flow's settings for workers.
2. **Intake.** Only the owner starts work: a request typed in the layer's CLI, or an issue the owner labels in a registered repository. Each becomes a ticket in the control folder (git, one writer, one commit per change).
3. **Launch.** One `t3_thread_launch` per ticket, with `workspaceStrategy: worktree`, the message `/flow:start <n>`, and the ticket id as `clientRequestId`, so a retry never starts a second thread.
4. **Supervise.**
   - Wait with `t3_thread_wait` and `untilDelegatedWorkSettled: true`.
   - Read questions with `t3_pending_request`. A question flow marks as a decision or permission goes to the owner's inbox and, on a labelled issue, to its GitHub thread. The layer answers it only under a rule the owner wrote. Only `Blocking: yes` interrupts, within the daily budget.
   - The layer cannot answer approvals. Its inbox shows that one waits and links to the thread in T3's apps.
5. **Different-vendor review.** When the worker reports ready (goal `achieved`), the layer launches a second T3 thread on another vendor's model with:
   - fresh context: the issue, its acceptance criteria and the diff at the pinned head commit, with no pull request body and no history
   - read-only access
   - a fixed verdict format: pass or fail, each finding with `file:line` and a command that shows it

   Flow does not load in non-Claude models, so the review prompt is the layer's own, built from flow's review facets. The work is offered for review only when flow's review and the different-vendor review both pass on the same head. Otherwise the findings go back to the worker thread (`t3_thread_send`). After three failed rounds, the owner gets a question.
6. **Send path.** The only route to GitHub:
   - take the worker's commits out of the worktree without running anything the worker could have planted (C4)
   - sign them outside the sandbox (C6b step 3)
   - push the ticket branch
   - open or update a draft pull request

   Other kinds of send wait for the owner. Merge and release are never sent.
7. **Watchdog and digest.** Threads that stop producing events, tokens nearing their expiry, a daily digest of at most 10 lines starting with "Needs you:".

**What flow needs for this choice:**

- report states and a result block (the one Phase 1 item left)
- fixes for defects 1 and 2 above
- per-user directories that can be redirected or kept inside the repository, so a sandboxed worker needs no `allowWrite` outside it

**Phases for H1-b:**

| Phase | Delivers | Gated by |
|---|---|---|
| 0 | C4, C5, C7, C8 below | — |
| 1 | the flow items above | — |
| 2 | layer MVP: OAuth setup, control folder, CLI intake, launch and supervise, inbox in the CLI, send path, different-vendor review; one repository | 0, 1 |
| 3 | GitHub intake and mirror, notifications beyond T3's own, several repositories | 2 |
| 4 | allowlisted requesters, proactive rules in observe mode | 3 |

**New checks for H1-b:**

| # | Question |
|---|---|
| C7 | How does a sandboxed worker read GitHub (`/flow:start` reads the issue and assigns it) while writing nothing? Options: allow GitHub hosts and give workers a read-only token, with writes going through the layer; or put a layer-provided `gh` on the worker's PATH that answers reads and turns writes into send requests (the C6b stub, made real). |
| C8 | Which other-vendor provider is available in T3 on the owner's machine, does a read-only review thread on it return the fixed verdict format, and does it catch a seeded defect that flow's own review was told to miss? |

C4 (safe intake of commits) and C5 (the auth policy for unattended use on a personal login) still apply. T3 signs in to Claude with the owner's own login, so C5's question now concerns T3.

### The own-harness design (fallback)

```
 your CLI / web panel ─┐                                  ┌─> worker t42: SDK session, clone of acme/web,
 labelled GitHub issues ┼─> ENGINE (deterministic) ─> EXECUTOR ┤     flow pinned, sandbox, no GitHub creds
 ticket PR activity ───┘    state in control folder      └─> worker t43: …
          ▲                          │
          │      INBOX (questions, approvals, sends that wait) <── canUseTool / defer from workers
          └── OUTBOX (push, draft PR, comment) ── the only path to GitHub, run by the harness
```

#### Components

1. **Engine.** The only writer of tickets, questions, approvals and the send ledger, through a lock and one git commit per change in the control folder. Tickets go `queued → running → waiting (person) → ready → done`, or `failed` or `dropped`. A ticket's stage is computed from stored facts, first match wins: waiting on an answer, an approval or a send; ready for review; failed; working; idle.
2. **Sources.** Requests the owner types in the CLI or the panel; issues the owner labels in registered repositories; and activity on a ticket's pull request. A per-thread cursor (last comment id and timestamp) means a restart never replays events.
3. **Router.** Deterministic rules, with one optional model call. It turns a typed request into tickets using structured output, a small model, and no tools. It never plans the work. A worker receives the original request and a routing note of at most 30 words.
4. **Executor.** One SDK `query()` per ticket:
   - `cwd` is the ticket's clone, and `plugins` loads the pinned flow.
   - `env` is built by the harness: no GitHub or cloud credentials, and `FLOW_ROLE=worker`.
   - The sandbox is on; the permission mode is `dontAsk` with an explicit tool allowlist.
   - An in-process PreToolUse hook enforces the send policy.
   - `canUseTool` routes questions and approvals to the inbox (H5).
   - An in-process tool, `report`, records the run's state and result block.

   A cap limits how many workers run at once. One slot is reserved for resuming a worker with an answer.
5. **Inbox.** Questions keep the six escalation fields, with three options, the recommendation first, and the blocking level. Approvals keep the command and flow's reason. Both appear in the panel and the CLI. A `Blocking: yes` question also notifies within the daily budget, and is mirrored to a labelled issue. An answer resumes the worker.
6. **Outbox.** Every outward action goes through it, with a ledger state of `waiting`, `sending`, `sent`, `failed` or `uncertain`. An `uncertain` send is never retried.
   - A push takes the worker's commits out of its clone through the intake that check C4 proves safe, then pushes the ticket branch.
   - A draft pull request runs at once (see the carried-over decisions); every other kind waits for the owner.
   - Merge and release are never sent by the harness. Flow's Tier 3 approvals arrive in the inbox for the owner to decide.
7. **Watchdog.** Finds workers that have stopped producing events, the remaining budget per ticket, and stale clones. It never restarts a ticket the owner parked.

#### What flow needs

Flow runs unchanged inside the harness: questions and approvals are intercepted. Flow 3.15.0 (#342) already has most of what the router record's Phase 1 asked for:

- the ask policy, enforced by a hook. Workers run with `autonomous: true`, so a question that only asks for a default is not asked, and fewer questions reach the inbox.
- stored questions (`bin/flow-question.sh`)
- the goal-gate, Stop-hook, goal-evaluation and repository-top fixes

One item is left: **report states and a result block**, so the harness can check a worker's claim against git (head commit, evidence, what was not verified).

#### Bundling flow

The harness pins a marketplace release tag, for example the one that ships flow 3.14.0. At install, it fetches `plugins/flow` from that tag into its data directory. It records the tag and a hash of the plugin's files in each ticket, so a run can be traced to the exact flow it used. Upgrading flow is a harness release that moves the pin after the harness's tests pass on the new version.

#### Phases

| Phase | Delivers | Gated by |
|---|---|---|
| 0 | the checks below | — |
| 1 | report states and a result block in flow (the rest of the router record's Phase 1 shipped in flow 3.15.0) | — |
| 2 | harness MVP: daemon, control folder, executor, inbox and outbox in the CLI, one repository, owner's typed requests | C1–C5 |
| 3 | GitHub sources and mirror, web panel, notifications, watchdog, several repositories | 2 |
| 4 | allowlisted requesters, proactive rules in observe mode, remote or cloud runners | 3 |

### Phase 0 checks (both designs)

| # | Question |
|---|---|
| C1 | A flow `AskUserQuestion` parked with `defer`, the harness stopped and restarted, the session resumed with the answer: does flow continue at the same step, with the answer applied? |
| C2 | Which SDK `sandbox` fields confine writes to the clone and deny network to GitHub, and do flow's hooks and git/gh shims still work inside the sandbox? |
| C3 | With `env` built by the harness (no `GH_TOKEN`), does flow's pipeline run to a ready result, with every GitHub action turned into a send request? |
| C4 | Can commits leave a worker clone without running anything the worker could have planted in its `.git` (hooks, `core.fsmonitor`, filters, `commondir`, alternates)? Each vector is tested against a naive command first, so the test can fail. |
| C5 | Personal mode: does a session started by the SDK on the person's own login behave as with an API key, and is the policy question settled? If not, personal mode stays off. |
| C6 | For H1-b only: can a separate program create threads, read pending questions and answer them through T3's OAuth or WebSocket API? Does a full `/flow:start` run complete in a T3 worktree thread with the sandbox on? **Done, passed: see "C6 results".** |

## Testing

Per `AGENTS.md`, end-to-end tests come first, each producing a repeatable artifact. The harness's tests run real SDK sessions against a scratch repository and a scripted GitHub fixture. They cover a question parked and answered, a Tier 3 approval denied, a send refused, a restart while a question waits, and a worker that dies. Each test is run once with its safeguard removed, to show it can fail. Flow changes keep using `plugins/flow/tests/lib/e2e.sh`.

## Consequences

With H1-b chosen:

- Flow's orchestration depends on T3 Code, a pre-release project that is not taking contributions. The layer talks to it only through its OAuth and MCP surface, and pins the T3 version it was tested on, so the own-harness design stays a fallback.
- Approvals need a person in T3's apps; the layer can see that one waits but not answer it. Defect 1 must be fixed, or flow's own journal writes keep producing approvals.
- The owner approves the layer's access to T3 once per 30 days.
- Sandbox setup (placeholders, flow's per-user directories, commit signing) is the layer's job until flow itself needs none of it.
- Model costs and auth follow T3's Claude sign-in; C5 decides whether unattended use on a personal login is acceptable.

Either way:

- A second product with its own releases, issues and documentation; flow stays usable without it.
- The trust boundary is the harness process. Workers' output (commits, result blocks, requested sends) is untrusted input that the harness checks with code. GitHub credentials never enter a worker.
- Cost is visible per ticket (the SDK reports spend per result; a resumed session reports its total, so the harness records the latest value, not a sum).
- The harness follows SDK releases. A pinned SDK version and the Phase 2 tests keep upgrades deliberate.
- Personal mode depends on a policy reading that the documentation does not settle; it stays opt-in and can be removed without affecting API-key use.

## Non-goals

- Does not merge or release; Tier 3 stays with a person.
- Does not let anyone but the owner start work in this version.
- Does not do unrequested work in this version.
- Does not replace flow's review, verification or goal machinery; workers run flow unchanged.
- Does not run as a hosted service for other people.
- Does not support agents other than Claude Code.
- Does not guarantee exactly-once sends: an interrupted send is marked `uncertain` and left for the owner.
- Does not isolate a worker beyond the Claude Code sandbox and the harness-built environment; a sandbox failure is not covered.

## Failure modes

| Component | Mode | Expected behaviour |
|---|---|---|
| Executor | the model API times out or returns 429/5xx | retried with growing backoff up to three times; then the ticket is `failed` with the error, and the inbox offers a retry |
| Executor | the SDK session ends unexpectedly | the ticket is `failed`; a retry resumes the session by id, or starts a new one that reads flow's run, journal and goal |
| Executor | budget per ticket reached (`maxBudgetUsd`) | the ticket stops as `failed: budget`, and the inbox asks whether to raise it |
| Inbox | the harness stops while a question waits in memory | on restart, the ticket's session is resumed and the question asked again; a deferred question needs nothing (C1) |
| Inbox | an answer does not match the question's options | refused; the question stays open |
| Outbox | GitHub refuses or times out | `failed` with GitHub's answer; never retried automatically |
| Outbox | the process dies while sending | `uncertain` on restart; the owner checks the target |
| Outbox | a send for a branch or head that is not the ticket's | refused and recorded |
| Sources | GitHub rate limit or outage | the cursor is kept; the next poll reads what was missed |
| Engine | control-folder lock held, or a commit fails | the operation is retried; an uncommitted change stays on disk and is committed by the next write |
| Bundled flow | the pinned files' hash does not match | workers do not start; the panel names the mismatch |
| Auth | key missing or rejected | no worker starts; setup and the panel name the credential to fix |

## Related

- `docs/design/2026-11-06-flow-router-and-worker-mode.md`: the plugin-only alternative, and Phase 1
- `plugins/flow/references/escalation-format.md`: the six fields questions keep
- `plugins/flow/references/three-tier-safety.md`: the tier gate whose approvals reach the inbox
- `plugins/flow/tests/lib/e2e.sh`: end-to-end tests for flow changes
