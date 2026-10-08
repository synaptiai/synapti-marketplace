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
- Data: the 136 plain-arm runs recovered from the 2026-09-25 transcripts, replayed as a pilot of the harness (provider calls only), and two pilots of four new plain-arm sessions; raw findings of every run are kept. The planned re-run of every trap (N=3 per model, 204 sessions) is not made: see "Scope" below.
- Adoption bar: the eval's rule (filter F1 beats plain F1 by more than that model's spread, on both models), plus a recall guard (recall may not drop by more than one run's worth on any model) and a merge guard (no merge of two defects hand-judged different counts as a gain); the threshold is chosen on replication 1 and judged on replications 2 and 3.
- The replay runs the shipped dedup and confidence scripts of #287, which is merged; this branch is based on main after it.

#262 ships the harness, the pre-registered bar and the pilot measurements; the scope is set by the user's decision of 2026-10-05 under "Scope" below.

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
- The client shortens a state over its cap, so the replay server receives a state that is not the kept file. The replay settings set `stateTokenCap` above any state the two sites build, and `table` fails when a kept state is larger than that cap (the client's records carry no truncated field, so the size of the kept state is what is checked).
- The replay server answers a state it has no record of. It refuses with HTTP 500, and the on pass fails on any `NO_ANSWER_HTTP_500` or `http-500` result.
- A record's model is not the pinned one (provider moved `jev-latest`). The pass fails.
- The 90 s budget, the 24-pair cap or the 25-finding cap cuts asking short. `UNASKED`, `STOPPED` and `REASON=cap|budget|provider-down` are counted per run and reported.
- A merge absorbs the hit under a representative outside the hunk. Representative-location and any-location scores are both reported.
- A confidence demotion removes the hit. Recall is reported, and the recall guard weighs it.
- Recovered 2026-09-25 findings carry no reviewers. The exporter attributes them from the subagent transcripts by cited line; a finding no subagent cited gets the reviewer `unattributed` (never an empty list, which dedup refuses), and the attribution rate is reported per run.

### Interface contracts
- `evals/review-prompt.md`: each finding also carries `reviewers` (the dispatched agents that raised it, a non-empty list) and `suggested_fix`; the five-agent fan-out and the file:line consolidation are unchanged.
- `_flow_eval.py score-review --case --trap --findings [--any-location] [--exclude-low] [--demoted <file>]`: accepts findings with `file`+`line` or `location` (`<file>:<line>[-<line>]`). A merged finding (with `locations`) is scored at its own `location`; `--any-location` scores it at any of its `locations`. `--exclude-low` leaves P1/P2 findings at LOW out of scoring (`low_excluded`). `--demoted` re-records the listed ids LOW first. Without the flags the record is the same as before for a `file`+`line` finding list.
- `_flow_eval.py finalize-review-run ... [--findings-out <file>] [--require-reviewers]`: writes the parsed findings list there; with `--require-reviewers`, a run whose P1/P2 findings do not each name a non-empty list of dispatched agents (compared without the plugin prefix) is incomplete with `reviewers-missing`.
- `flow-eval-run.sh --mode review`: passes `--findings-out "$OUT_DIR/findings/<model>/<arm>/<case>/<trap>/<n>.json" --require-reviewers`.
- `bin/flow-eval-s1-replay.sh <subcommand>` (Python half `bin/_flow_eval_s1_replay.py`): `export-recovered`, `convert`, `score`, `trees`, `shadow`, `table`, `serve`, `on`, `inspect`, `aggregate`. Each prints KEY=value lines; a pass prints `PASS_STATE=ok|failed` and exits 1 when failed. The on passes run from a plugin copy whose `questions.yaml` has the sweep value as the default and no per-model entry. The on passes and the shadow pass call the shipped `flow-s1-dedup.sh` and `flow-s1-confidence.sh` from a plugin copy; the replay server keys on sha256 of the received state serialized with sorted keys and compact separators, refuses an unknown key with HTTP 500, and reports the recorded model.
- `_flow_eval.py replay-aggregate --replay <dir>`: the same report as `flow-eval-s1-replay.sh aggregate`.
- Replay layout: `trees.json`, `shadow/<base|reps>/pass.json` and `shadow/<set>/<model>/<arm>/<case>/<trap>/<n>/` (input, script output, kept records and states), `table.json`, `on/<point>/pass.json` and per-run `in.json`, `out.json`, `demoted.txt`, script output, `merged-pairs.json`, `report.json`, `report.md`. `export-recovered` also writes `export-report.json` beside the findings.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Scoring of merged findings | a merged finding is a hit when any member is in the hunk, so a merge of two distinct defects reads as a gain | fixture: H in the hunk merged under R (higher priority) cited outside it: representative-location gives a miss with 0 false findings, any-location gives a hit |
| LOW handling | demoted findings dropped only in the filter arm, baseline keeps reviewer-LOW | a baseline with one reviewer-LOW P2: `--exclude-low` drops `scored_findings` by 1 in both arms |
| Replay runs the shipped code | the driver merges in Python, so complete linkage is lost | A~B, B~C same, A~C different: the on pass prints the same MERGED lines as a direct `flow-s1-dedup.sh` call, never A+B+C |
| Shadow-to-on matching | the server keys on the record's `state_sha256`, or answers a default p | the server's hits equal the requests with 0 refusals; one changed character in a kept state gives HTTP 500 and a failed pass |
| Threshold chosen on the judged data | the best sweep point is chosen and judged on the same runs | the report states the replication behind each number; the chosen point comes from replication 1 alone |
| Inspection before scores | merged pairs labelled after the table is read | `aggregate` refuses the verdict while any merged pair has no label |

## Pilot attribution (2026-10-03)

Decision (lead, 2026-10-03): for the free pilot over the recovered 2026-09-25 runs, credit a finding only to subagents that cite its exact line as `<module>.py:<line>`, never through a range or prose, and never to a single nearest subagent; if most findings still carry 4-5 reviewers, the pilot covers the converter, confidence, the table and the server only.

Re-export of the 136 plain-arm runs with the exact-line rule (code of commit f36d830e, no provider call). The export's counts are committed as `plugins/flow/evals/results-2026-09-25-review/export-report.json`:

| Reviewers per finding | 0 (unattributed) | 1 | 2 | 3 | 4 | 5 | All |
|---|---|---|---|---|---|---|---|
| All findings, ranges and prose (before) | 12 | 44 | 69 | 102 | 157 | 244 | 628 |
| All findings, exact line | 171 | 105 | 72 | 95 | 107 | 78 | 628 |
| P1/P2 findings, exact line | 89 | 65 | 42 | 81 | 91 | 68 | 436 |

- Four or five reviewers: 185 of 628 findings (29%) and 159 of 436 P1/P2 findings (36%), so the lead's trigger (most findings at 4-5) does not fire.
- Dedup candidate pairs by the rule of `flow-s1-dedup.sh`: 6 in all, and 133 of 136 runs have none. A finding that `convention-checker`, `test-runner` or `security-reviewer` also cites is never a candidate, and the five agents cite the same lines.
- So the pilot still cannot test `review.dedup`. `export-recovered` prints `DEDUP_HALF=not-exercised` when more than half the findings carry four or more reviewers or more than half the runs have no candidate pair; `aggregate` then reports the pair check as `not-exercised`, gives `review.dedup` the verdict `not-exercised`, and the report says the replay tests the conversion, `review.confidence`, the table and the server only. `review.dedup` is first tested on the fresh N=3 re-run.
- RESCORE_MISMATCH=0, MISSING_TRANSCRIPTS=0, UNPARSED=0.

Type check: basedpyright at error level on every changed `bin/*.py` gives 0 errors (`_flow_eval.py` had 201 on main). One was a real crash path: `python3 -OO bin/_flow_eval.py` with no subcommand raised TypeError on the empty usage text; the scenario `helper-no-docstrings` takes that path.

## Pilot replay (2026-10-05)

Decision (user, 2026-10-05): run the free pilot over the recovered 2026-09-25 runs only, then stop; the paid re-run waits for the user's answer.

Outcome (passes at `3a126eb7`, report at `ea3d3063`), shadow pass 2026-10-04 22:27-22:32 UTC against TypeSafe `jev-1.13.0`:
- 140 TypeSafe calls (6 dedup pairs, 134 confidence findings), all answered, all from `jev-1.13.0`; about 0.1 million input tokens, under $0.01 at $0.042 per million.
- Every check passed; the candidate-pair check reports `not-exercised`. The 25 on passes were answered by the replay server with 0 misses.
- No pair merged (p 0.04-0.19, all "different") and no finding demoted (lowest p 0.35, confidence 0.30) at any threshold point, so every filter scored as the plain findings: F1 0.440 (Opus 5.5) and 0.513 (Sonnet 5) over both replications.
- 139 of 274 accepted-category P1/P2 findings were not asked because a `security-reviewer` subagent cites their line.
- The threshold check flagged `review.confidence` because it counted supported answers, which demote nothing at any threshold. It now counts only answers that a finding is not supported (scenario `threshold-direction`).
- Results: `evals/results-2026-09-25-review/findings/` and `replay/`, with a README marking them as the pilot.

## Scope (decision of 2026-10-05)

Decision (user, 2026-10-05): #262 ends with the recovered-run pilot and the two prompt pilots as its recorded result. No paid verdict run is made: a verdict under the bar needs three runs per trap and model (204 sessions, about $307), over the $260 cap, and two runs cannot apply the bar. Both sites stay `off` at their provisional thresholds (`review.dedup` 0.8, `review.confidence` 0.9); no `models:` entry and no settings change.

What #262 delivers against its acceptance criteria:

| Criterion | Delivered | Waived by the decision |
|---|---|---|
| AC1: the plain arm re-run on at least two models, raw findings of every run kept | The runner keeps every run's findings. Eight new plain-arm sessions (Opus 5.5 and Sonnet 5, two traps, four each in two pilots) with their findings; the 136 runs of 2026-09-25 recovered from transcripts. | The full re-run of every trap. |
| AC2: both filters replayed offline against TypeSafe Jev (pinned) and imajev-4b, per model, provider and filter | The replay harness, and a replay of the 136 recovered runs against TypeSafe `jev-1.13.0`, reported per model and filter. | imajev-4b: nothing is sent to the local imajev server, so it was not measured and has no threshold. A replay over a full re-run. |
| AC3: the report states what a scoring-rule F1 gain would look like and checks merged pairs | Written into the reference before any result, with a check per artefact; `aggregate` refuses to report while a merged pair has no hand label. | Nothing. |
| AC4: a verdict by the eval's rule, recorded in the reference and in each filter's default | The bar is written in the reference. The result recorded there is that neither site has a verdict and both stay `off`. | The verdict itself. |

Result, written into `references/review-precision-eval.md`, "Result":
- `review.dedup` candidate pairs under the shipped rule: 12 in the 136 recovered runs (0.09 per run, in 5 runs), 7 in the 8 new sessions (0.875 per run, in 2 runs).
- Eligible P1/P2 findings that name `security-reviewer`: 139 of 274 (51%) in the recovered runs, where reviewers are inferred from cited lines; 3 of 15 in the new sessions.
- `review.confidence` demoted nothing in the replay of the recovered runs (134 asked, lowest confidence on a "not supported" answer 0.30, below the lowest threshold point 0.6), and the 6 pairs that replay asked were all answered "different defect".
- Meaning: on the current plugin duplicate findings are rare, so the expected gain from either site is small.
- Spent: $11.30 on Claude sessions; TypeSafe under $0.01.
