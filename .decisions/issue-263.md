---
issue: 263
created: '2026-10-03T11:58:32Z'
artifacts:
- type: specification
  captured_at: '2026-10-03T11:58:32Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

Question measured: when System One is asked "if the module were the risk map's plausible wrong version, would this test fail?", does its answer agree with what the correctness eval observed when that test ran against the seeded wrong variant?

Decisions (user, 2026-10-03):
- Provider: TypeSafe `jev-1.13.0` only. imajev is not measured (nothing is sent to 127.0.0.1:8765), so no imajev threshold can come from this issue.
- Data: the pairs on disk (901 author-written, 648 agent-written from four Sonnet 5 runs) are the dev set. 24 new Sonnet 5 runs (baseline and enforce-risk, 4 cases x 3 runs, `--effort high`) are the held-out evaluation set.
- Committed from the new runs: each run's pair export, records, `project/` snapshot and `own-test-traps.json`; not whole run directories.
- Adoption bar: written into references/correctness-eval.md before any provider call (two clauses, below).
- If the bar is not met: the harness, its E2E test, the results and the reference section ship; the site `verify.discrimination` is not added to system-one/questions.yaml.

Decisions (lead, this branch):
- Author-written states have their comments removed. The hidden suites' comments name the trap each test discriminates ("trap: ties-last-first gives it to index 2"), which would answer the question inside the state. Agent-written states keep comments, because a live site would see them. Each pair records `comments_stripped`.
- "Flagged" means the model answered "would still pass" with enough confidence: confidence >= t and p < 0.5, which is p <= (1 - t) / 2, with t the questions.yaml confidence threshold.
- Degenerate answers: more than 80% of the fail answers and of the pass answers in the same 0.1-wide bin, or one class always predicted. The agent pairs are about 80% pass, so a share of all answers would mark a confident, correct provider degenerate.
- The permutation check is the mean of the per-(case, trap) AUCs with labels shuffled within each group, which is 0.5 in expectation whatever the provider answers; the AUC pooled over traps is reported, not gated, because differences in p between traps move it.
- (2026-10-04) The direction check is judged on the same kind of number: the mean of the real-description AUCs within each (stratum, case, trap) group that holds both labels, with the standard error of a mean of independent AUCs, √(Σ seᵢ²) / k. The pooled AUC is reported beside it and not judged: two traps each ordered correctly (AUC 1.0) with fail shares of 80/90 and 10/90 pool to 0.21, which would have named a correct provider a harness fault. Chosen before any provider call.
- Labels come from the stored own-test-traps.json (what the correctness eval observed). Re-running the agent's suite only recovers the oracle test ids, which that file does not store.
- (2026-10-03) Clause 2 reads the user's "the non-discriminating tests" as the hard negatives: `pass` pairs whose test fails at least one other trap of the same case in the same run. A `pass` pair whose test fails no trap is left out of clause 2, because nothing shows that the test exercises the code the risk row is about, so its label says little about whether a reviewer would call it relevant. The share of all `pass` pairs flagged is reported beside clause 2 at every t and does not decide the verdict.

### Non-goals
- No answer moves a criterion toward PASS, lifts a FAIL or marks a goal done. This step adds no decision point at all.
- No change to flow-s1.sh, _flow_s1.py or the shipped system-one/questions.yaml.
- No change to the correctness eval's arms, cases, hidden suites, traps or decision rule.
- The 168 runs of 2026-09-09 are not reconstructed; their per-test results no longer exist.
- The trap's code, the reference implementation and the agent's module are never put in a state.
- Python 3.12-3.14 only.

### Failure modes
- No answer (timeout, HTTP error, malformed, abstained, connection): the record carries the reason and no p. The scorer counts each reason, leaves those pairs out of every rate, and prints coverage next to every number. Coverage below 95% on a stratum makes the verdict `inconclusive-coverage`. A no-answer is never a negative.
- HTTP 429: the replay retries that pair once after a pause; a pair that fails twice counts against coverage. The later record for a ref replaces an earlier no-answer.
- Below threshold: p is still in the record (`result: below-threshold`), and the scorer reads it.
- Records missing, duplicated, or naming a ref that is not a pair: the scorer stops with `harness-error` and exit 1 before reading any metric.
- Own suite does not finish on re-run during export, or the re-run does not reproduce what own-test-traps.json stored about the oracle tests (their count, own_impl.total and failed_ids, reference_run.failed_ids, disagree_with_reference, unobserved_on_reference): that run is excluded and listed with the reason.
- Dev pairs exported again as the evaluation set: the threshold file lists every dev ref and run, and the scorer stops with `harness-error` when an evaluation pair or run is among them.
- A stored failing list shorter than its count (the 50-entry cap): the run is refused unless the export is told to re-score it.
- Settings refused (plugin copy inside a repository, settings file refused): the replay's first call writes no record and the replay stops before sending anything else.
- A test that uses helpers from another file: the state builder includes same-file helpers (module-level ones and methods of the test's class reached through `self`) only and marks `helpers_missing`.

### Interface contracts
- `flow-test-state.sh --test-file F --test-id ID|--line N --area A --wrong-version W --spec-file S [--strip-comments] [--rename-test NAME]`: prints one JSON object `{"spec", "risk": {"area", "plausible_wrong_version"}, "test": {"id", "source"}, "meta": {...}}` with `test.source` the test function whole, its class's setUp/setUpClass and class attributes, and the module-level helpers it names, capped at 12 KB. Exit 0, or 2 on a usage error or a test that cannot be found.
- `flow-s1-eval.sh pairs --evals-dir E --dest D [--set dev|eval] [--author] [--out R]... [--rescore] [--seed N] [--timeout S]` (also `_flow_eval.py s1-pairs`): `--author` exports the hidden suites, each `--out` the oracle tests of every run under R/runs. Writes `D/pairs.jsonl` (one line per pair: ref, set, stratum, case, run, model, arm, trap, test id, label fail|pass|unobserved, hn_behavioral, comments_stripped, helpers_missing, and per ablation the state path and sha256), `D/states/<ablation>/...json` and `D/export.json` (counts, excluded and unfinished runs with reasons, state errors, the seed). Exit 2 on a stored failing list cut at 50 without `--rescore`. Offline; no model call.
- `flow-s1-eval.sh replay --pairs P --records R --provider-settings F [--ablation real|name-stripped|shuffled] [--records-name NAME] [--workers N<=8] [--scratch DIR] [--limit N] [--sample N] [--seed N] [--only-set dev|eval] [--backoff S]`: copies the plugin to a scratch directory outside any repository, installs evals/s1-discrimination/questions.yaml as its system-one/questions.yaml, and calls `flow-s1.sh ask --site verify.discrimination --state-format json --ref <pair ref> --current <label>` once per labelled pair not yet answered, with FLOW_USER_SETTINGS=F and FLOW_STATE_DIR=R/<NAME> (NAME defaults to the ablation). `--sample N` sends N pairs drawn with the seed (the repeatability check uses `--sample 30 --records-name repeat`). HTTP 429 is retried once after S seconds. A temporary scratch directory it made is removed when it ends. Exit 0 when every sent pair has a record, 3 when the first call wrote no record (nothing else is sent), 4 when a sent pair has no record afterwards.
- `flow-s1-eval.sh score --pairs P --records R --dest D [--set dev|eval] [--choose-threshold T | --threshold-file T] [--seed N] [--limit N] [--permutations N]`: joins records to pairs by ref, runs the measurement checks first, then writes `D/summary.json` and `D/summary.md` with counts, coverage, accuracy, balanced accuracy, AUC, Brier and Brier skill, a 10-bin reliability table, the false-alarm rate and hard-negative flag recall with Wilson 95% bounds at t = 0.50 ... 0.95, the name-stripped AUC drop on agent pairs with its standard error (reported, not judged), and the verdict. `--choose-threshold` (dev only, agent and author pairs both present, no `--limit`) writes T with the chosen t, the commit, the time, the provider and model that answered, and the refs, run keys and run identities (sha256 of own-test-traps.json, session id) of every dev pair. Exit 1 on `harness-error`: records and pairs not one to one, answers from more than one provider and model, evaluation answers from another one than T's, or an evaluation pair or run that T lists as a dev pair or run (by key or identity). A real-description AUC (the mean of the AUCs within each stratum, case and trap; the pooled AUC is reported beside it and not judged) more than 2 standard errors below 0.5 gives `inconclusive-direction`; `--limit` gives `inconclusive-limited`.
- `flow-s1-eval.sh smoke --pairs P --records R [--refs F]` (before the dev replay; F defaults to evals/s1-discrimination/smoke-refs.txt, five obvious catches and five obvious non-catches): exit 1 naming each problem when a listed `fail` pair has p <= 0.5 or a `pass` pair p >= 0.5, when a listed pair has no answer, or when the records (R/real or R/repeat) do not match the pairs; exit 0 otherwise. It reports each pair answered twice (R/repeat) with both answers and their difference, and over all of them the largest difference, the mean difference and how many differ by more than 0.02; that spread never changes the exit code. `replay --refs F` sends only the listed pairs.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Join of records to pairs | joined by order or by state_sha256, so two pairs with the same state collapse or swap labels | fixture: two pairs with byte-identical states and opposite labels come out as two rows with their own labels; a missing record gives harness-error |
| Direction of the answer and of the flag | true read as "the test is weak", so the flag fires on confident catches | p=0.03 on a fail pair counts as one false alarm; p=0.97 on a pass pair as one missed flag; stub rules answer high only for the catch states |
| Leakage into the state | risk text taken from traps.json description or expected.md columns 3-4, or hidden-test comments naming the trap | every state is checked: no description string, no discriminating test name other than its own, and in author states no trap name in any spelling and no word "trap" |
| Oracle set on re-export | every discovered test labelled, including ones that fail on the reference or never ran | the re-run must reproduce own_passing_tests, own_impl.total and failed_ids, reference_run.failed_ids, disagree_with_reference and unobserved_on_reference; a stored disagree list naming another test, or one more own failing test, excludes the run; a fixture run whose test fails on the reference is not a pair |
| No-answer counted as a negative | a timeout record scored as "won't fail" | fixture with a timeout record on a fail pair: false-alarm count unchanged, coverage drops |
| Bar met by the base rate | constant answers pass because 80% of pairs are pass | p=0.01 everywhere and p=0.99 everywhere both fail the bar; all p=0.5 is marked degenerate |

### Placebo check (2026-10-03, user decision)
- The shuffled-wrong-version placebo is judged on the pooled AUC only (all pairs, within 0.05 of 0.5). The agent-written and author-written placebo AUCs are reported with their standard errors and do not decide the check. With no signal the pooled AUC's standard error on the dev set (316 fail, 1,233 pass pairs) is about 0.018.

### Linux CI run before any provider call (2026-10-04)
- Draft PR #288, head 0cfbcd0a194eeda1375a843913038c3f2f096479: `test (ubuntu-latest)` passed, TOTAL pass=9714 fail=0 (18m38s, run 37219145992). `test (macos-latest)` also passed (18m52s).
- No TypeSafe call was made before this run.
- This run clears a provider call from head 0cfbcd0a only. After any later change to the harness, the new head must be pushed to PR #288 and pass `test (ubuntu-latest)` before the next TypeSafe call, and its SHA and pass count are recorded here.

### Smoke check stopped the measurement (2026-10-04)
- Dev export (offline, no model call): 1,549 pairs, 316 fail and 1,233 pass, 0 unobserved, 0 runs excluded; oracle tests per run 24, 21, 19, 17 and fail pairs 28, 34, 24, 30, as the spec expects.
- First TypeSafe calls at 2026-10-04 17:28 UTC from head 629a892c. Its harness is the same as 0cfbcd0a, which passed Linux CI; 629a892c changes only this file.
- Before the first paid run, checked that no evaluation session can reach a provider: the runner starts each session with `--setting-sources project,local` (the user settings that enable the installed flow plugin are not read) and gives plugin arms a FLOW_USER_SETTINGS file with no `systemOne` key, so the shadow sites in ~/.claude/settings.flow.json are not read.
- Direction: 10 of 10 correct. The five catches got p 0.81 to 0.95 and the five non-catches p 0.12 to 0.34.
- Repeatability: failed. Two of the three pairs sent twice differed by more than 0.02 (0.24 then 0.34, and 0.34 then 0.26), with identical request bodies (the state sha256 matches on every call). The gate says nothing else is sent until this is fixed. Twenty more calls of the same ten pairs were then sent to tell a harness fault from the provider; the gate text did not allow them. Spread of p (largest minus smallest) over 3 or 4 calls of the same state: 0.01, 0.03, 0.06, 0.05, 0.06 on the catches and 0.10, 0.09, 0.05, 0.01, 0.02 on the non-catches. TypeSafe jev-1.13.0 does not return the same p for the same state; this is the provider, not the harness.
- Stopped before the dev replay: no dev, ablation or evaluation record exists, no threshold was chosen, and no paid Claude run was started. Spend: 33 TypeSafe calls (under $0.01 at the list price of $0.042 per million input tokens), $0 in Claude runs.
- Open for the user: keep the 0.02 tolerance (the measurement ends here and the site is not adopted), or change the smoke tolerance to one taken from the spread above, recorded in the reference as a change made after the smoke, and continue. The spec's own measurement checks say differences above 0.02 are reported, while the committed reference makes them a stop.

### Repeatability is reported, not a stop (2026-10-04)
- The user decided that the spec's wording governs: differences between two answers to the same state are reported, and do not stop the measurement. The direction part of the smoke check still stops it, and the adoption bar on held-out data is unchanged.
- The reference change is commit 1ab38ca6, made before any further provider call. The harness change is commit 8e3103d9: the smoke check and the scorer report each pair sent twice with its two answers and their difference, and over all of them the largest difference, the mean difference and how many differ by more than 0.02 (smaller is better).
- The 30-pair repeatability replay runs on dev pairs, after the smoke check and before any evaluation run.
- The new head must pass `test (ubuntu-latest)` on PR #288 before the next TypeSafe call, as recorded above.
