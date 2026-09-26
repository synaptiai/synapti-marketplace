# Issue #216 — the review-precision eval's recorded run

Criteria 1 to 4 and 6 were met by PR #251 (squash `5512bf7`); its journal is
`.decisions/issue-215.md`. This change is criterion 5: one recorded run on two models checked in
under `evals/results-<date>-review/` with its `summary.md`, and the parent issue's decision on
`review.groundingCritic` citing it.

## Specification

### Non-goals
- No change to the eval harness, the scorer or the adoption rule.
- No change to `review.groundingCritic`'s default beyond what the rule's verdict says.
- The raw session transcripts (about 91 MB) are not committed; the results directory holds
  `runs.json`, `summary.json` and `summary.md`, as the correctness eval's results do.

### Failure modes
- A results directory whose summary does not match its records: `summary.md` and
  `summary.json` are the aggregator's output for exactly the 272 records in `runs.json`.
- A reading that credits or blames the critic for something the arm did otherwise: see the
  reading below.

### Interface contracts
- `evals/results-2026-09-25-review/{runs.json,summary.json,summary.md}` in the shape the
  correctness eval's results directories use; `runs.json` is the list of per-run
  `result.json` records.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Records vs summary | summary built from a different or partial run | re-aggregating `runs.json` reproduces the summary's per-arm F1 |
| Local paths | a scratch path from the machine that ran it is committed | no `/private/tmp`, `scratchpad` or `/Users/` in the three files |

## The run

- Approved by the owner on 2026-09-25: both models, both arms, every case and trap, twice;
  $10 a run; the total cap was set at $400 and raised by the owner to $475 when the running
  cost pointed past $400.
- Ran 2026-09-25T17:53Z to 2026-09-26T01:46Z against `d7d8fc4`: 272 runs, $297.65, none
  incomplete, no errors.

| Model | Arm | F1 | Spread |
|---|---|---|---|
| `claude-opus-5-5` | plain | 0.440 | 0.009 |
| `claude-opus-5-5` | critic | 0.335 | 0.033 |
| `claude-sonnet-5` | plain | 0.510 | 0.012 |
| `claude-sonnet-5` | critic | 0.471 | 0.016 |

Verdict: `keep-off`. `review.groundingCritic` stays off.

## Reading

The critic arm reports more P1/P2 findings at more distinct locations than the plain arm (Opus
4.97 against 3.54 per run, Sonnet 3.25 against 2.87), although the critic can only remove
findings. In the one pair of sessions compared by hand, the plain arm merged the reviewers'
findings by location while the critic arm kept each reviewer's findings under their own ids to
hand them to the critic. So the result measures what turning the setting on does to the review
as a whole; how much of the drop the critic's own verdicts cause is not measured.
