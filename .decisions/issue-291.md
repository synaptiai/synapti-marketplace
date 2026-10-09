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
