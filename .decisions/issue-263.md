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
- Labels come from the stored own-test-traps.json (what the correctness eval observed). Re-running the agent's suite only recovers the oracle test ids, which that file does not store.

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
- Own suite does not finish on re-run during export, or the re-run oracle set differs from the stored one: that run is excluded and listed with the reason.
- A stored failing list shorter than its count (the 50-entry cap): the run is refused unless the export is told to re-score it.
- Settings refused (plugin copy inside a repository, settings file refused): the replay's first call writes no record and the replay stops before sending anything else.
- A test that uses helpers from another file: the state builder includes same-file helpers (module-level ones and methods of the test's class reached through `self`) only and marks `helpers_missing`.

### Interface contracts
- `flow-test-state.sh --test-file F --test-id ID|--line N --area A --wrong-version W --spec-file S [--strip-comments] [--rename-test NAME]`: prints one JSON object `{"spec", "risk": {"area", "plausible_wrong_version"}, "test": {"id", "source"}, "meta": {...}}` with `test.source` the test function whole, its class's setUp/setUpClass and class attributes, and the module-level helpers it names, capped at 12 KB. Exit 0, or 2 on a usage error or a test that cannot be found.
- `_flow_eval.py s1-pairs --evals-dir E --dest D [--out R]... [--set dev|eval] [--rescore] [--seed N]`: writes `D/pairs.jsonl` (one line per pair: ref, set, source, case, run, trap, test id, stratum, label fail|pass|unobserved, hn_behavioral, comments_stripped, helpers_missing, and per ablation the state path and sha256), `D/states/<ablation>/...json` and `D/export.json` (counts, excluded runs with reasons, the seed). Offline; no model call.
- `flow-s1-eval-replay.sh --pairs D/pairs.jsonl --records R --provider-settings F [--ablation real|name-stripped|shuffled] [--workers N<=8] [--only-set dev|eval] [--repeat N]`: copies the plugin to a scratch directory outside any repository, installs evals/s1-discrimination/questions.yaml as its system-one/questions.yaml, and calls `flow-s1.sh ask --site verify.discrimination --state-format json --ref <pair ref> --current <label>` once per pair with FLOW_USER_SETTINGS=F and FLOW_STATE_DIR=R/<ablation>. A temporary scratch directory it made is removed when it ends. Exit 0 when every sent pair has a record, 3 when the first call wrote no record (nothing else is sent), 4 when a sent pair has no record afterwards.
- `_flow_eval.py s1-score --pairs P --records R --dest D [--set dev|eval] [--threshold-file T] [--choose-threshold] [--seed N]`: joins records to pairs by ref, runs the measurement checks first, then writes `D/summary.json` and `D/summary.md` with counts, coverage, accuracy, balanced accuracy, AUC, Brier and Brier skill, a 10-bin reliability table, the false-alarm rate and hard-negative flag recall with Wilson 95% bounds at t = 0.50 ... 0.95, and the verdict. `--choose-threshold` (dev only, agent and author pairs both present) writes T with the chosen t, the commit, the time and the provider and model that answered. Exit 1 on `harness-error`: records and pairs not one to one, answers from more than one provider and model, or evaluation answers from another one than T's.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Join of records to pairs | joined by order or by state_sha256, so two pairs with the same state collapse or swap labels | fixture: two pairs with byte-identical states and opposite labels come out as two rows with their own labels; a missing record gives harness-error |
| Direction of the answer and of the flag | true read as "the test is weak", so the flag fires on confident catches | p=0.03 on a fail pair counts as one false alarm; p=0.97 on a pass pair as one missed flag; stub rules answer high only for the catch states |
| Leakage into the state | risk text taken from traps.json description or expected.md columns 3-4, or hidden-test comments naming the trap | every state is checked: no description string, no discriminating test name other than its own, and in author states no trap name in any spelling and no word "trap" |
| Oracle set on re-export | every discovered test labelled, including ones that fail on the reference or never ran | re-run oracle set must equal own_passing_tests and the stored failing sets; a fixture run whose test fails on the reference is not a pair |
| No-answer counted as a negative | a timeout record scored as "won't fail" | fixture with a timeout record on a fail pair: false-alarm count unchanged, coverage drops |
| Bar met by the base rate | constant answers pass because 80% of pairs are pass | p=0.01 everywhere and p=0.99 everywhere both fail the bar; all p=0.5 is marked degenerate |

### Placebo check (2026-10-03, user decision)
- The shuffled-wrong-version placebo is judged on the pooled AUC only (all pairs, within 0.05 of 0.5). The agent-written and author-written placebo AUCs are reported with their standard errors and do not decide the check. With no signal the pooled AUC's standard error on the dev set (316 fail, 1,233 pass pairs) is about 0.018.

### Linux CI run before any provider call (2026-10-03)
- Draft PR #288, head 910f9d792d499d87f9c7203bc7fd3418bf245fcf: `test (ubuntu-latest)` passed, TOTAL pass=9621 fail=0 (18m11s). `test (macos-latest)` also passed (14m56s).
- No TypeSafe call was made before this run.
