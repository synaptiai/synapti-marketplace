# Factory phase 0: probe results

These are the results of the go/no-go probes for every platform behaviour the factory depends on. The results in the record ran on 2026-11-15 and 2026-11-16 on one Mac (macOS, Apple silicon); earlier runs from 2026-11-12 count only toward the spend. Every `claude -p` run used Claude Opus 5.5 (`claude-opus-5-5`); the probes name the model because Claude Code's own default changes between releases. The two P9 sessions ran in the person's own Claude Code session, and their captures do not record its model. The full record is in `probes.json` in this folder, with the evidence for each probe under `evidence/`.

## What the results ran against

| Group | Probes | Claude Code | gh | git | Other |
|---|---|---|---|---|---|
| Environment | P3, P7, P11, P15 | 2.1.325 | 2.101.0 | 2.55.0 | Python 3.14.7 |
| Environment, launchd | P13 | 2.1.325 | 2.101.0 | 2.55.0 | ran from a launchd agent |
| Platform | P1, P2, P4, P5, P10, P16 | 2.1.325 | 2.101.0 | 2.55.0 | |
| GitHub writes | P3 (sandbox part), P6 | 2.1.325 | 2.101.0 | 2.55.0 | sandbox danielbentes/flow-factory-sandbox |
| Interactive | P9, P14 | 2.1.325 | 2.101.0 | 2.55.0 | auto and default permission modes |

A probe recorded under other tool versions than its group's, or on another model, is out of date and has to be run again; `flow-factory.sh probe --verify-record` names each one. Every group ran on Claude Code 2.1.325; after a Claude Code update, run each group again (`flow-factory.sh probe --platform`, and likewise `--environment`, `--github-write` and `--interactive`) before a phase depends on it.

Model spend in the record is $16.58 of the $25 cap. That figure is more than was spent, by $0.95 and an amount that is not known. The $0.95: P5's two earlier runs each counted its first session again in each resumed run, which charged $0.47 too much each time; the probe now charges each run its own cost. The unknown amount: a run that is killed reports no cost, so it is charged its whole budget limit. P5 kills its first session on purpose in every run, so each P5 run was charged $0.50 for a session that cost less; P5's last run was charged $0.73, $0.50 of it for that session. Not in the record: $0.85 on three hand-run sandbox checks before P16 existed, and the use of the interactive P9 sessions, which run on the person's own Claude Code account.

## What the writes check covers

Every probe that runs Claude ran it with the person's own home folder, so its runs could reach the person's saved GitHub and git logins; only P16's two runs ran inside Claude Code's sandbox, which keeps them out. The check that no probe wrote to GitHub outside the sandbox repository reads two things: the log of gh and git calls made through the probe's wrappers on PATH, and the commands each recorded run made, for gh or git run by its full path and for HTTP clients that name a GitHub host. Across the recorded runs it found four such calls, all in P16 and all reads: `gh auth token`, `git credential fill`, a local `git commit`, and a GET of api.github.com/zen. A write hidden from both, inside a script a command ran, would not be found. Workers in phase 1c start inside the sandbox P16 checked and receive none of the person's GitHub logins.

## Results

| Probe | What it checks | Result | What follows |
|---|---|---|---|
| P1 | Flow's commands run headless in a worker: `!` blocks, writes to the worktree and the io folder | **no-go** on one part | All five runs completed, every `!` block's output reached the first turn, and writes to the worktree and the io folder worked. A headless `/flow:pr` tried to create the pull request itself. The workers' gh stand-in refused it, so nothing reached GitHub. Phase 1d must give `/flow:pr` a factory mode that leaves the pull request to the engine. Detecting factory mode is also checked in 1d. |
| P2 | Hooks fire in workers, and person-only commands are refused there | deferred to 1b | Stop, SessionEnd and TaskCompleted fire under `-p`. All 72 spellings of the person-only commands were refused by a stand-in deny rule. Tier-gate's own rule (1b) and the factory's Stop, SessionEnd and stage rules are checked when they exist. |
| P3 | Login and signing in the engine's cleaned environment; a push and a draft PR on the sandbox | **go** | gh and git authenticate. Commits are unsigned, as the person's own are. The worker token reads the sandbox, and GitHub refused all three write requests made with it. |
| P4 | The plugin loads once when passed with `--plugin-dir` | **go** | |
| P5 | Session ids, resume, turn and budget limits, cost reporting | **no-go** on one part | A resumed run reports the token use and `total_cost_usd` of the whole session, not its own: a one-turn resume reported the four-step run's tokens plus its own. Its result's `model_usage_since_last_result` holds the run's own cost, which is what the engine must charge; otherwise it charges a job twice. The other parts passed: session ids, kill, turn limit, budget limit and no re-run of `!` blocks on resume. |
| P6 | Review markers on the factory's own pull request | **go** | A COMMENT review returns its id, its author counts as OWNER, and markers can be found again by key. GitHub refuses APPROVE and REQUEST_CHANGES on your own pull request with a 422 ("Can not approve your own pull request", "Can not request changes on your own pull request"), so sending work back uses the `/flow-factory rework` comment. `gh pr ready` and `--undo` started or cancelled no CI on the sandbox. |
| P7 | Each job's trust ledger is separate | deferred to 1c | Two jobs writing at once kept separate ledgers. The launcher that sets each job's ledger is built in 1c. |
| P8 | GitHub event fields for edits by another account | not run | No second GitHub account was available. Comments and edits from unknown editors are treated as untrusted. |
| P9 | The interactive session wakes on its own when a worker needs it, in auto and default mode | deferred to 1b | In both modes the session woke with no one typing, 3 s (auto) and 8 s (default) after the background step ended. Every hook input carried the session's mode: 2 in each session. In the default session each command was approved with a plain "Yes". Tier-gate's mode-specific rule (1b) and the interactive executor (1c) are checked when they exist. |
| P10 | `--disallowedTools` holds in `-p`, including subagents | **go** | |
| P11 | The engine runs a real Python 3.14 with PyYAML, not a version-manager shim | **go** | A planted `.python-version` and `PYENV_VERSION` did not change the interpreter. |
| P13 | The factory works when started by launchd | deferred to 1c | Every check passed under launchd, including a `claude -p` run. Refusing runs from a launch context that does not match is part of the scheduled runner (1c). |
| P14 | A worker waits for a person's answer and continues in the same run | deferred to 1c | The stand-in worker got the answer and finished without a relaunch. One poll costs about $0.011, about $0.20 per 30 minutes against a $1 limit. The real `await` is built in 1c. |
| P15 | Git config planted in a job's clone is caught before the engine runs git there | deferred to 1e | Every planted key was found before git ran in the clone: fsmonitor, hooks path, credential helper, insteadOf, push URL, a key in `.git/config.worktree` and a key on no list. A worker's git config in the job clone left the main checkout's config unchanged, and the job clone still read every object after the main checkout ran `git gc --prune=now`. The engine checks that use this, and the check that a moved origin ref changes nothing the gate reads, are built in 1e. |
| P16 | Workers run in Claude Code's sandbox | deferred to 1c | Inside the sandbox, the person's GitHub token could not be read through gh, the macOS Keychain, git's credential helper or the environment. Writes outside the clone and connections to other hosts were refused. A commit in the clone and api.github.com worked. A repository's own settings did not widen the sandbox. A worker that refuses to start when the sandbox cannot start is part of the 1c launcher. |

## Points the next phases must handle

- **Workers and GitHub writes (1d).** Without factory mode, `/flow:pr` creates the pull request itself. In factory mode it must leave that to the engine.
- **Commit messages (1d).** A worker's commits end with a `Co-Authored-By: Claude` trailer, which Claude Code adds. A repository whose rules forbid it, as this one's do, needs factory mode to keep it out.
- **Model (1a launcher).** Claude Code's default model changes between releases, so the launcher names the model for every worker.
- **Cost (1a launcher, 1g cost cap).** Claude Code reports a resumed session's total cost on each run. The engine charges each run the cost in its result's `model_usage_since_last_result`.
- **Budget limit (1a launcher, 1g cost cap).** `--max-budget-usd` stops a run only after the turn that passes it, so it is not an upper bound: a one-turn run reported $0.148 against a $0.10 limit. The cost cap must allow for each run passing its limit by up to one turn.
- **Claude Code's own git fetch (1c).** In P14's worker on 2.1.325, Claude Code ran four `git fetch --upload-pack=git-upload-pack` calls against origin (`--depth 1`, then `--unshallow`). The probe's git shim refused them, as it refuses any `--upload-pack`, and the worker still finished. The worker's git guard must decide whether to let these fetches through.
- **Sandbox settings (1c).** The settings must deny `~/Library/Keychains`. Denying gh's config alone leaves the token readable through `security`.
- **Blocked hosts (1c).** Under `-p`, a blocked host shows up as a network permission request that is denied automatically. In an interactive session the same request would ask the person, so the interactive executor must not let it reach them.
- **Sending work back (1g).** GitHub does not allow REQUEST_CHANGES on your own pull request, so the `/flow-factory rework` comment is the way to send work back.
