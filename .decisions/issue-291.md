---
issue: 291
created: '2026-10-09T06:40:00Z'
artifacts:
- type: specification
  captured_at: '2026-10-09T06:40:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: verdict
  captured_at: '2026-10-09T06:49:32Z'
  result: PASS
---

## Specification

`plugins/flow/references/system-one.md` gives each decision point's measured result under "Shadow comparisons", except for `review.dedup`, `review.confidence` and `review.challenge`, and it does not mention the proposed `verify.discrimination`. This change adds those results, or says plainly that there is none, using only the result files already on main, and rewrites the `address.still_applies` paragraph that describes how the question changed.

### Non-goals
- No change to code, questions, thresholds or modes. Every site stays `off` at its current threshold.
- No new measurement. Every number comes from a file already on main.
- The two eval references (`review-precision-eval.md`, `correctness-eval.md`) keep their full results; `system-one.md` summarises and links to them.

### Failure modes
- A number copied wrongly, or from the wrong row (for example the replication-2 F1 instead of the F1 over both replications).
- A link anchor that does not match its heading, so the link opens the top of the file.
- A summary that claims more than the source: calling the review pilot a verdict, or saying `review.challenge` will be measured.
- Revision-history wording left in, or added.

### Interface contracts
- GitHub heading anchors: `## System One filters: the adoption bar` → `#system-one-filters-the-adoption-bar`; `## System One: does a test catch the wrong version` → `#system-one-does-a-test-catch-the-wrong-version`.
- Sources of numbers: `plugins/flow/evals/results-2026-09-25-review/replay/README.md` (review sites), `plugins/flow/evals/results-2026-10-04-discrimination/eval/summary.md` and `threshold.json` (`verify.discrimination`).

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Review-site numbers | F1 taken from one replication (0.444 / 0.520) instead of both (0.440 / 0.513) | Script compares each number in the new section with the replay README's "both" rows |
| Discrimination numbers | Flag counts from the dev set or another threshold instead of the evaluation set at t = 0.60 | Script compares with the t = 0.60 row of eval/summary.md |
| Links | Anchor misspelled, so the link lands at the top of the file | Script derives each anchor from the target file's headings and checks the link uses it |
| `review.challenge` wording | Text implies a comparison exists or is planned | grep finds "has not been measured" and no "until the shadow comparison" remains |

## Number sources

Every number the change adds to `plugins/flow/references/system-one.md`, with the line it comes from (paths under `plugins/flow/`). The check script matches numbers of three or more digits automatically; this table covers the short ones, checked by reading each line.

| Number in the doc | Source |
|---|---|
| 136 runs, 68 per model, 2026-09-25 | `evals/results-2026-09-25-review/replay/README.md:3-4,91,94` |
| replayed 2026-10-04 | `evals/results-2026-09-25-review/replay/README.md:36` |
| 6 pairs asked; 12 under the shipped rule; 0.09 per run | `evals/results-2026-09-25-review/replay/README.md:14-15`; `references/review-precision-eval.md:394` |
| 4% to 19%; merge at 80%; lowest threshold 0.6 | `evals/results-2026-09-25-review/replay/README.md:69-70` |
| confidence 0.62 and 0.78 at the shipped 0.8 | computed as \|2p − 1\| from p 0.19 and 0.11, the `served` values in `evals/results-2026-09-25-review/replay/on/dedup-0.8/pass.json`; below-threshold answers are marked related in `on` mode by `bin/_flow_s1_dedup.py:453-455` |
| 134 findings; confidence 0.30, 0.26, 0.04 | `evals/results-2026-09-25-review/replay/README.md:36,72-74` |
| F1 0.440 (Opus 5.5), 0.513 (Sonnet 5) | `evals/results-2026-09-25-review/replay/README.md:91,94` |
| thresholds 0.8 (`review.dedup`), 0.9 (`review.confidence`) | `references/review-precision-eval.md:374-375` |
| 5,077 pairs; t = 0.60 | `evals/results-2026-10-04-discrimination/eval/summary.md:5,23` |
| 24 Sonnet 5 runs | `references/correctness-eval.md:595` |
| 10 of 707, upper 95% bound 2.6%, at most 5% | `evals/results-2026-10-04-discrimination/eval/summary.md:31` |
| 638 of 3,169, lower 95% bound 18.8%, at least 30% | `evals/results-2026-10-04-discrimination/eval/summary.md:32` |
| 1.4%, 20.1% | computed: 10 / 707 and 638 / 3,169 |
