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
| Local paths | a path identifying the machine that ran it is committed | no `/Users/`, `scratchpad`, `/private/tmp` or `/var/folders/` in the three files; the per-user temporary directory in denied commands is written `$TMPDIR`, and the generic `/tmp/…` names sessions chose are kept |

## The run

- Approved by the owner on 2026-09-25: both models, both arms, every case and trap, twice;
  $10 a run; the total cap was set at $400 and raised by the owner to $475 when the running
  cost pointed past $400.
- Ran 2026-09-25T17:53Z to 2026-09-26T01:46Z (the runner's log, not committed) against `d7d8fc4`: 272 runs, $297.65, none
  incomplete, no errors.

| Model | Arm | F1 | Spread |
|---|---|---|---|
| `claude-opus-5-5` | plain | 0.440 | 0.009 |
| `claude-opus-5-5` | critic | 0.335 | 0.033 |
| `claude-sonnet-5` | plain | 0.510 | 0.012 |
| `claude-sonnet-5` | critic | 0.471 | 0.016 |

Verdict: `keep-off`. `review.groundingCritic` stays off.

## Reading

The grounding pass can only remove findings, yet the critic arm scores more P1/P2 findings per
run (Opus 4.97 against 3.54, Sonnet 3.25 against 2.87). Counting every priority, the arms raise
about as many findings in total (Sonnet 3.90 and 3.87, Opus 5.34 and 5.94, from `runs.json`'s
`findings_total`); with the critic fewer are P3 (`ignored_findings`: Sonnet 1.03 to 0.62, Opus
1.79 to 0.97), so more are scored. On Sonnet this shift is the whole rise in scored findings; on
Opus most of it. Why the priorities move is not measured. One pair of sessions compared by hand
(Opus, `four-stream-codec`, `big_endian_table`, run 1: `0f1239d1…` plain, `d2b3260a…` critic)
shows the critic session keeping the reviewers' findings apart where the plain session merged
them; one pair shows that this can happen, not how often. So the result measures what turning the
setting on does to the review as a whole, not the critic's verdicts alone.
