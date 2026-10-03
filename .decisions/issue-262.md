---
issue: 262
created: '2026-10-03T12:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-10-03T12:00:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

Measure `review.dedup` (#260) and `review.confidence` (#261) with the review-precision eval. The plain review arm (`review-b`) is re-run with a prompt that also asks, per finding, for the reviewers that raised it and a suggested fix, and every run's parsed findings are kept. The shipped site scripts are then replayed offline over those findings: one shadow pass against TypeSafe `jev-1.13.0` records each answer's p, and on-mode passes at each threshold point ask a local replay server that answers with the recorded p. The scorer reports precision, recall and F1 per review model and filter (dedup, confidence, dedup then confidence), and the verdict follows the adoption bar written into `references/review-precision-eval.md` before any result exists.

Decisions (epic #258, 2026-10-03), which take precedence over the accepted spec:
- Provider: TypeSafe `jev-1.13.0` only. imajev is not used: nothing is sent to 127.0.0.1:8765, and the reference says imajev was not measured and why. No imajev threshold is set. One verdict, for `jev-1.13.0`.
- Data: first the 136 plain-arm runs recovered from the 2026-09-25 transcripts, replayed as a pilot of the harness (provider calls only); then a fresh re-run of the plain arm on Opus 5.5 and Sonnet 5 with the new prompt, N=3 per model (204 sessions). Raw findings of every run are kept.
- Adoption bar: the eval's rule (filter F1 beats plain F1 by more than that model's spread, on both models), plus a recall guard (recall may not drop by more than one run's worth on any model) and a merge guard (no merge of two defects hand-judged different counts as a gain); the threshold is chosen on replication 1 and judged on replications 2 and 3.
- This change builds on #287's branch (`feature/issue-260-261-271-review-s1`), because the replay runs the shipped dedup and confidence scripts.

This step ships the harness and the pre-registered bar. It runs no paid session and makes no real provider call; the measurement and the verdict records (`questions.yaml` models entries, `settings.json` defaults, the `system-one.md` status table) follow it.

### Non-goals
- Does not change the merge rule, eligibility rule, questions or state shape of `review.dedup` or `review.confidence`. A defect the replay exposes in them is fixed on #260/#261.
- Does not re-run the critic arm or revisit `review.groundingCritic`.
- Does not measure `review.challenge` (#271) or the correctness eval (#263).
- Does not add review cases or rewrite trap variants.
- Does not use live shadow records from real pull requests for the verdict.
- Does not tune the questions' wording against this eval.
- Does not re-implement the threshold, the merge rule or the eligibility rule in the harness: every decision comes from `flow-s1-dedup.sh`, `flow-s1-confidence.sh` and `flow-s1.sh`.
- Python 3.12 to 3.14 only.

### Failure modes
- The prompt change alters reviewer behaviour, so the new baseline F1 differs from 0.440/0.510. The comparison is paired within the new runs; both baselines are stated.
- A session drops or invents reviewers. `finalize-review-run` checks each P1/P2 finding's `reviewers` against `agents_dispatched` and marks the run incomplete with `reviewers-missing`.
- The scratch tree's HEAD is not reproducible (dates not pinned), so a rebuild changes the state bytes and nothing matches. The driver exports `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`, records each tree's HEAD, and refuses a rebuilt tree whose HEAD differs.
- The plugin copy inside the repository answers `settings-refused`. The driver runs a copy of the plugin outside every tree, with the scratch tree as the working directory, and fails the pass when any run reports a configuration reason.
- The client shortens a state over its cap, so the replay server receives a state that is not the kept file. The replay settings set `stateTokenCap` above any state the two sites build, and a `truncated` record fails the pass.
- The replay server answers a state it has no record of. It refuses with HTTP 500, and the on pass fails on any `NO_ANSWER_HTTP_500` or `http-500` result.
- A record's model is not the pinned one (provider moved `jev-latest`). The pass fails.
- The 90 s budget, the 24-pair cap or the 25-finding cap cuts asking short. `UNASKED`, `STOPPED` and `REASON=cap|budget|provider-down` are counted per run and reported.
- A merge absorbs the hit under a representative outside the hunk. Representative-location and any-location scores are both reported.
- A confidence demotion removes the hit. Recall is reported, and the recall guard weighs it.
- Recovered 2026-09-25 findings carry no reviewers. The exporter attributes them from the subagent transcripts by cited line; a finding no subagent cited gets the reviewer `unattributed` (never an empty list, which dedup refuses), and the attribution rate is reported per run.

### Interface contracts
- `evals/review-prompt.md`: each finding also carries `reviewers` (the dispatched agents that raised it, a non-empty list) and `suggested_fix`; the five-agent fan-out and the file:line consolidation are unchanged.
- `_flow_eval.py score-review --case --trap --findings [--any-location] [--exclude-low] [--demoted <file>]`: accepts findings with `file`+`line` or `location` (`<file>:<line>[-<line>]`). A merged finding (with `locations`) is scored at its own `location`; `--any-location` scores it at any of its `locations`. `--exclude-low` leaves P1/P2 findings at LOW out of scoring (`low_excluded`). `--demoted` re-records the listed ids LOW first. Without the flags the record is the same as before for a `file`+`line` finding list.
- `_flow_eval.py finalize-review-run ... [--findings-out <file>]`: writes the parsed findings list there; checks reviewers when the findings carry the field or the arm is `review-b` with the new prompt.
- `flow-eval-run.sh --mode review`: passes `--findings-out "$OUT_DIR/findings/<model>/<arm>/<case>/<trap>/<n>.json"`.
- `bin/flow-eval-s1-replay.sh <subcommand>` (Python half `bin/_flow_eval_s1_replay.py`): `export-recovered`, `trees`, `shadow`, `table`, `serve`, `on`, `inspect`, `aggregate`. The on passes and the shadow pass call the shipped `flow-s1-dedup.sh` and `flow-s1-confidence.sh` from a plugin copy; the replay server keys on sha256 of the received state serialized with sorted keys and compact separators, refuses an unknown key with HTTP 500, and reports the recorded model.
- `_flow_eval.py replay-aggregate --replay <dir>`: the same report as `flow-eval-s1-replay.sh aggregate`.
- Replay layout under the results directory: `replay/trees.json`, `replay/shadow/...`, `replay/table.json`, `replay/on/<filter>/<point>/...`, `replay/merged-pairs.json`, `replay/report.json`, `replay/report.md`.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Scoring of merged findings | a merged finding is a hit when any member is in the hunk, so a merge of two distinct defects reads as a gain | fixture: H in the hunk merged under R (higher priority) cited outside it: representative-location gives a miss with 0 false findings, any-location gives a hit |
| LOW handling | demoted findings dropped only in the filter arm, baseline keeps reviewer-LOW | a baseline with one reviewer-LOW P2: `--exclude-low` drops `scored_findings` by 1 in both arms |
| Replay runs the shipped code | the driver merges in Python, so complete linkage is lost | A~B, B~C same, A~C different: the on pass prints the same MERGED lines as a direct `flow-s1-dedup.sh` call, never A+B+C |
| Shadow-to-on matching | the server keys on the record's `state_sha256`, or answers a default p | the server's hits equal the requests with 0 refusals; one changed character in a kept state gives HTTP 500 and a failed pass |
| Threshold chosen on the judged data | the best sweep point is chosen and judged on the same runs | the report states the replication behind each number; the chosen point comes from replication 1 alone |
| Inspection before scores | merged pairs labelled after the table is read | `aggregate` refuses the verdict while any merged pair has no label |
