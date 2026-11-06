# Design record: a separate harness that orchestrates Claude Code with flow built in

**Date**: 2026-11-06
**Status**: Proposed (decisions taken by the maintainer on 2026-11-06; nothing built)
**Alternative to**: `2026-11-06-flow-router-and-worker-mode.md` (the plugin-only router). Both records are kept so they can be compared; its Phase 1 (flow fixes) applies to both.
**Layout**: the decision-record layout of `plugins/flow/references/architecture-decision-record.md`

## Summary

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

## Decisions, options and trade-offs

### H1. How flow gets orchestration

| Option | For | Against |
|---|---|---|
| **Own harness on the Agent SDK (chosen)** | the router is deterministic code; every flow question and approval arrives as a callback with no flow change; no research-preview dependency; one process owns state, credentials and sends | a new product to build and maintain; SDK is 0.x and releases often |
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

```
 your CLI / web panel ─┐                                  ┌─> worker t42: SDK session, clone of acme/web,
 labelled GitHub issues ┼─> ENGINE (deterministic) ─> EXECUTOR ┤     flow pinned, sandbox, no GitHub creds
 ticket PR activity ───┘    state in control folder      └─> worker t43: …
          ▲                          │
          │      INBOX (questions, approvals, sends that wait) <── canUseTool / defer from workers
          └── OUTBOX (push, draft PR, comment) ── the only path to GitHub, run by the harness
```

### Components

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

### What flow needs

Flow runs unchanged inside the harness: questions and approvals are intercepted. Phase 1 of the router record still improves the result:

- Report states and a result block let the harness check a worker's claim against git.
- The four defects matter in any mode.
- A mechanical ask policy (`FLOW_ROLE=worker` or `autonomous` takes the recommendation for questions that are only defaults) cuts the number of questions the inbox receives.

Flow's own question store is not needed by the harness, but still serves attended use.

### Bundling flow

The harness pins a marketplace release tag, for example the one that ships flow 3.14.0. At install, it fetches `plugins/flow` from that tag into its data directory. It records the tag and a hash of the plugin's files in each ticket, so a run can be traced to the exact flow it used. Upgrading flow is a harness release that moves the pin after the harness's tests pass on the new version.

### Phases

| Phase | Delivers | Gated by |
|---|---|---|
| 0 | the checks below | — |
| 1 | flow fixes from the router record's Phase 1 (report states, result block, four defects, ask policy) | — |
| 2 | harness MVP: daemon, control folder, executor, inbox and outbox in the CLI, one repository, owner's typed requests | C1–C5 |
| 3 | GitHub sources and mirror, web panel, notifications, watchdog, several repositories | 2 |
| 4 | allowlisted requesters, proactive rules in observe mode, remote or cloud runners | 3 |

### Phase 0 checks

| # | Question |
|---|---|
| C1 | A flow `AskUserQuestion` parked with `defer`, the harness stopped and restarted, the session resumed with the answer: does flow continue at the same step, with the answer applied? |
| C2 | Which SDK `sandbox` fields confine writes to the clone and deny network to GitHub, and do flow's hooks and git/gh shims still work inside the sandbox? |
| C3 | With `env` built by the harness (no `GH_TOKEN`), does flow's pipeline run to a ready result, with every GitHub action turned into a send request? |
| C4 | Can commits leave a worker clone without running anything the worker could have planted in its `.git` (hooks, `core.fsmonitor`, filters, `commondir`, alternates)? Each vector is tested against a naive command first, so the test can fail. |
| C5 | Personal mode: does a session started by the SDK on the person's own login behave as with an API key, and is the policy question settled? If not, personal mode stays off. |

## Testing

Per `AGENTS.md`, end-to-end tests come first, each producing a repeatable artifact. The harness's tests run real SDK sessions against a scratch repository and a scripted GitHub fixture. They cover a question parked and answered, a Tier 3 approval denied, a send refused, a restart while a question waits, and a worker that dies. Each test is run once with its safeguard removed, to show it can fail. Flow changes keep using `plugins/flow/tests/lib/e2e.sh`.

## Consequences

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
