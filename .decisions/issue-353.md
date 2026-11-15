---
issue: 353
created: '2026-11-12T12:32:55Z'
artifacts:
- type: specification
  captured_at: '2026-11-12T12:32:55Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-11-12T12:34:32Z'
  goal_id: issue-353
  source: issue
- type: workflow-run
  captured_at: '2026-11-12T12:34:39Z'
  workflow: start-issue
  run_id: 2026-11-12T122249Z-issue-353
  status: active
- type: stranger-test
  captured_at: '2026-11-12T12:40:24Z'
  result: PASS
  task_count: 10
- type: goal-evaluation
  captured_at: '2026-11-12T12:50:16Z'
  goal_id: issue-353
  result: waiting_for_user
  reason: code-workflow-running-and-probe-runs-need-user
- type: design-decision
  captured_at: '2026-11-12T14:13:46Z'
  decision: workers run in Claude Code's sandbox (probe P16)
  category: architecture
- type: goal-evaluation
  captured_at: '2026-11-14T17:26:25Z'
  goal_id: issue-353
  result: active
  reason: probe runs finished; resuming for evaluation and PR
- type: goal-evaluation
  captured_at: '2026-11-14T17:28:27Z'
  goal_id: issue-353
  result: active
  evidence_bundle: .flow/runs/2026-11-12T122249Z-issue-353
  failures: none
- type: goal-evaluation
  captured_at: '2026-11-14T17:29:03Z'
  goal_id: issue-353
  result: achieved
  reason: user confirmed; five of five checks pass at d1d6989b
- type: escalation-asked
  captured_at: '2026-11-15T13:31:19Z'
  question_id: q-20261115T133118Z-125c40
  blocking: 'yes'
  class: decision
  command: /flow:pr step 6
  situation:
  - Review found that P13
  - P14 and P9's auto-mode parts carry no tool-version stamp (P13 ran on Claude Code
    2.1.322)
  - and P9's auto-mode evidence (session P9-2) is not in the export. Claude Code is
    now 2.
- type: escalation-asked
  captured_at: '2026-11-15T13:31:20Z'
  question_id: q-20261115T133119Z-58aa2e
  blocking: 'yes'
  class: decision
  command: /flow:pr step 9
  situation:
  - Earlier
  - unpushed commits on this branch hold about 20 lines with the dashed home path
    (-Users-danielbentes-) and one lower-case macOS temp path in exported evidence;
    the current export holds none. A
- type: escalation-resolved
  captured_at: '2026-11-15T13:33:21Z'
  escalation_field: options
  outcome: Squash the branch into one commit on top of origin/main before the first
    push (rewrites unpushed local history only)
  question_id: q-20261115T133119Z-58aa2e
- type: escalation-resolved
  captured_at: '2026-11-15T13:33:27Z'
  escalation_field: options
  outcome:
  - 'Re-run after the code fixes: P13 under launchd (loads the LaunchAgent again)'
  - then the environment and GitHub write groups so their stamps agree
  - P14 (up to $1)
  - and both P9 sessions in tmux; all on the installed Claude Code
  question_id: q-20261115T133118Z-125c40
---
## Specification

_Captured by specification-capture skill on 2026-11-12. Source: user-confirmed._

### Non-goals

- No job engine, queue, job state or worker launching (phase 1a and later). Only the flow-factory.sh wrapper skeleton and the probe module.
- No change to existing flow commands, hooks or tier-gate behaviour.
- No GitHub writes outside danielbentes/flow-factory-sandbox; P1 makes none at all (gh is stubbed and logged).
- No `go` for a condition that needs a phase 1 part: it is recorded `deferred` and added to that phase's issue.
- P8 is not run (no second GitHub account available).
- No support for Python older than 3.14.

### Failure modes

- **Timeouts** — every `claude -p` run has a turn limit, a budget limit and a hard kill; a timed-out probe is recorded no-go with reason timeout, never go.
- **Partial failures** — each probe is recorded on its own. A failed prerequisite (P11 interpreter, P3 auth) marks its dependents not_run. When the $25 model-spend cap would be passed, the remaining model probes are recorded not_run with reason budget.
- **Invalid input** — a missing sandbox, a token with write access or the wrong repository is refused with a named reason; a token that can write makes P3 no-go.
- **Missing context** — no claude, gh, jq, timeout/gtimeout or Python 3.14 with PyYAML: refuse and name the tool. Keychain token (service flow-factory-gh-token) absent: P3's token part is not_run with reason token-missing.

### Interface contracts

- `flow-factory.sh context --mode`: with FLOW_FACTORY_JOB and FLOW_FACTORY_DIRECTIVE unset, prints exactly `FACTORY_MODE=off`, exits 0, starts no Python.
- `flow-factory.sh probe --platform | --environment | --github-write --sandbox <owner/repo>`: writes `<runtime dir>/factory/probes.json`.
- probes.json validates against `schemas/v1/factory-probes.schema.json`: per group the values it was keyed on and when it ran; per probe id, result (go | no-go | deferred | not_run), reason, fallback, deferred_to, evidence path, cost.
- Every other subcommand exits 5 with `FACTORY_REFUSED=<reason>`.
- Committed copies: `docs/flow-factory/probes.json` and `docs/flow-factory/probe-results.md`, with the tool versions each probe ran against.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Result classification of stand-in probes | a probe run against a stand-in is recorded `go` | P2 with the stub deny rule firing → right: `deferred` (to 1b); wrong: `go` |
| Interpreter resolution | a pyenv shim is accepted as the interpreter | probe run from a worktree with `.python-version` = 3.12 → right: records ~/.pyenv/versions/3.14.7/bin/python3.14; wrong: records a shim that runs 3.12 |
| Worker token write check | any 4xx is read as "cannot write" | invalid-body POST with a write-capable token returns 422 → right: no-go (token can write); wrong: go |
| Model spend cap | the cap is checked after a run starts | $24 spent, next run limit $2 → right: not_run (budget); wrong: run starts, total reaches $26 |
| context --mode independence | the wrapper starts Python or reads probes.json for `context --mode` | python3 removed from PATH → right: `FACTORY_MODE=off`, exit 0; wrong: error, non-zero exit |

## Phase 0 decisions

_Recorded 2026-11-12. Answers given by the user through AskUserQuestion._

- sandbox: danielbentes/flow-factory-sandbox (public, created 2026-11-12 for the probes). The probes that write to GitHub (P3 push and draft PR, P6) write only there.
- token: a read-only fine-grained token for workers, scoped to the sandbox, stored in the macOS Keychain under service flow-factory-gh-token and passed to workers as FLOW_FACTORY_GH_TOKEN (worker.ghTokenEnv). Not yet stored as of this entry.
- scope: phase 0 runs the platform half of every probe now, with stand-ins; go conditions that need a phase 1 part are recorded deferred and added to that phase's issue.
- P8: not run for now (no second GitHub account); the fallback applies.
- budget: $25 cap on total model spend for the probes.

## Plan

_Recorded 2026-11-12 from the implementation-planner's 10 tasks._

1. Re-verify AC1 (journal decisions).
2. Probe runner: cleaned-environment `claude -p` launch (ported from flow-eval-run.sh lines 150-169, 753-766, 874, which cannot be called), spend guard checked before each launch ($25 cap), record writer, tool versions, gh/git write-logging shim.
3. `probe --verify-record` with `--dispositions` and `--writes-only-to` (done at 2b0becb5).
4. Environment probes P11, P3 (auth, signing, token write check), P7, P15, P13's checks.
5. Platform probes P1, P2, P4, P5, P10, with stand-ins classified deferred.
6. GitHub-write probes (P3 sandbox push and draft PR, P6) and interactive drivers (P9, P14 stand-in await).
7. Run environment, platform and GitHub-write probes (user present: Keychain token, terminal for signing).
8. Run P9 in auto and default mode, and P14 (user present).
9. Record: committed probes.json and probe-results.md via `probe --export`, deferred go conditions and `P6 result:` lines added to issues #354-#360.
10. Full suite, shellcheck, AC gates, read the results document end to end.

Contract choices made while planning: `probe --interactive` runs P9 and P14; P13 runs as `probe --environment --launch-context`; P13's deferred go condition goes to #356 (1c builds the scheduled runner); `probe --export <dir>` writes the committed copy with evidence paths rewritten and tokens and home paths removed.

## Stranger Test

PASS — 10 tasks reviewed. Each names its files, interface contract, failure modes, risk rows with a discriminating test (all 5 rows assigned), reuse search, and verification command.

## Design Decision: workers run in Claude Code's sandbox (probe P16)
**Date**: 2026-11-12 | **Category**: architecture
**Decision**: Add probe P16 (worker sandbox) to phase 0. Phase 1c launches every worker with sandbox settings passed through `--settings`: sandbox on, failIfUnavailable, no unsandboxed commands, gh's config and `~/Library/Keychains` denied, GH_TOKEN and GITHUB_TOKEN denied, and network limited to the hosts workers need. This replaces the risk accepted earlier today: that workers can reach the person's write token.
**Options considered**: probe now and require it in 1c (chosen); a separate epic child; keep the accepted risk.
**Trade-offs**: phase 0 gets one more probe. Workers lose access to hosts that are not on the allowlist.
**Rationale**: In a pre-check on 2026-11-12 (Claude Code 2.1.322, macOS, one run each, $0.85 spent in total) a sandboxed `claude -p` gave these results:
- With gh's config denied, `gh auth token` returned 0 bytes, but `security find-generic-password` returned the 75-byte keyring token.
- With `~/Library/Keychains` also denied, both the Keychain read and `git credential fill` returned nothing.
- A write to the home folder was blocked.
- A commit inside the worker's own repository worked.
- example.com, which was not on the allowlist, was blocked from curl and from Python. api.github.com was allowed.
- A repository `.claude/settings.json` that tried to widen the sandbox had no effect.
Source of the idea: the person's research note "Securing agent shell commands: what works" (2026-11-12).
**Non-goals**: the flow-wide sandbox and broker; that is #377.
**Failure modes**: the sandbox cannot start → no worker starts. P16 is no-go → the accepted risk stays, and the residual risks say so.
**Consequences**: #353 lists P16, and #356 depends on P16 and has a matching acceptance criterion. #305 has a comment pointing to #377.

## Worker token stored
**Date**: 2026-11-12
- The token is stored in the Keychain under service flow-factory-gh-token. It is a fine-grained token, 93 characters. The person set it to read-only on danielbentes/flow-factory-sandbox.
- **Checked by hand, with no writes made:** it reads the sandbox (200). It is refused for creating a label, creating a pull request and writing a file (403 each). These are the three requests P3 sends.
- **Issue creation is not a usable test.** Sent with an invalid body to the issues endpoint, the request returns 422 even though the token is read-only. GitHub checks the body before the permission on that endpoint, so P3 must not use it. P3 doesn't: it sends the label, pull-request and file requests, which return 403 before the body is checked.

## Notes

**2026-11-15.** After the goal was evaluated as achieved (2026-11-14, at d1d6989b), commit df98b8e9 moved the stream-json reader that the probe module and the eval harness share into plugins/flow/bin/_flow_stream.py, and plugins/flow/bin/_flow_eval.py now imports it from there. Both paths are outside the goal's allowed_paths. The goal file was not changed to add them.
