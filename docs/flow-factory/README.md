# Flow factory design inputs

These files are the inputs to the flow factory design. The factory takes GitHub issues that carry a queue label and drives each one to a ready pull request without a person starting each step. The plan is in `plan.md`.

| File | What it holds |
|---|---|
| `plan.md` | The approved plan: decisions, design summary, probes, phases and verification |
| `design.json` | The full design, one section per key. `states_and_transitions` explains the state machine and points at `transitions.json`. `person_channels` says who may act for a person and how the engine checks it; `worker_github_access` sets out the two options for how workers reach GitHub. `__open_before_fix` lists the items that were open before an earlier revision |
| `design-check-2026-11-11.json` | The last check of `design.json`: which of those items the final text closes, and the contradictions the check found |
| `design-critic.json` | The critic's findings on the first synthesized design |
| `gaps.md` | The 24 gaps between flow 3.16.0 and an unattended factory, each checked against flow's code |
| `research-zazen-factory-v2.md` | Analysis of the ZazenCodes software factory v2 (GPLv3: ideas only, no code or prompt text is reused) |
| `research-aidlc-v2.md` | Analysis of AWS AI-DLC v2 |
| `research-flow-lifecycle.md`, `research-flow-runtime.md` | How flow's commands, state and safety checks work today, read at aab0d132 |
| `transitions.json` | The job state machine as data: states, events, facts, fact dependencies and rows, each row with the blocking GitHub writes it makes. It also holds, as data, the rules the design states in prose (`rules`) and the outcome each of 30 situations must have (`expectations`). It is the only source for the state table |
| `check_transitions.py` | Checks `transitions.json`: schema and allowed keys, duplicate JSON keys, where each fact is defined, which states each event must occur in, guard coverage, precedence ties, rows that never win, resume targets, reachability from the creation row to a terminal state and to ready, and exits from parked states into active states. It also enforces the rules and expectations: a person action needs its confirmation, a blocking write whose key is confirm parks first, a move out of a state where the PR is marked ready undoes the mark, and a person's cancel, merge or rejection ends the job. It prints the entry and exit lists. `--markdown` writes `transitions.md` |
| `transitions.md` | Generated from `transitions.json` by the checker. Not edited by hand |
| `test_check_transitions.sh` | Applies broken edits to a copy of `transitions.json`, at least one for each rule and kind of expectation, and checks that the checker rejects each one with that rule's own message. It also checks that `transitions.md` matches the JSON and that every row id `design.json` cites exists. By default it runs under `/usr/bin/python3` (3.9) and `python3` |

`transitions.json` is the only source for the job state machine; `design.json` describes it and cites its row ids. If they disagree, `transitions.json` is correct. `design.json`'s `finding_closure` names the section that addresses each defect listed in `plan.md` Step 1. Two of them are closed only if the user adopts the machine-account rule for comments: the GitHub comment channel, and the comment path in the auto-mode defect. Under the other answer they stay open, and `residual_risks` says so. The rule is the user's decision because it changes how a settled decision works: the person's own `/flow-factory rework` comment would need a second confirm. Four items remain for the user, listed in the `phasing` section of `design.json`: approve the sandbox repository, create the read-only token workers use (the design chooses that option, as the plan directs; without the token, workers get no credential), decide the machine-account rule for comments, and decide re-intake on retry. The plan's decision table settles the rest.
