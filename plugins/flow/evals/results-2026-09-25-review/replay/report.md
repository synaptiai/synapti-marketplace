# System One filters: replay report

Provider model `jev-1.13.0`. The threshold is chosen on replication 1 and judged on replications 2. Precision, recall and F1: higher is better. LOW findings are left out of scoring in every row except the LOW-kept columns.

These findings were recovered from earlier review sessions, with each finding's reviewers taken from the subagents that cite its exact line. They do not exercise review.dedup (133 of 136 runs have no dedup candidate pair): this replay tests the conversion, review.confidence, the answer table and the replay server only. review.dedup is first tested on the fresh re-run, and its row here is not a verdict.

## Checks before the bar

| Check | Status |
|---|---|
| answers | ok |
| ceiling | ok |
| coverage | ok |
| demotions | ok |
| different-merges | ok |
| off-identity | ok |
| pairs-candidate | not-exercised |
| partition | ok |
| rescore | ok |
| table-identity | ok |
| thresholds | ok |
| unasked | ok |

## Judged replications

| Model | Filter | Precision | Recall | F1 | Raw F1 | Any-location F1 | LOW-kept F1 | Spread | Demoted (hits) |
|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | plain | 29% | 100% | 0.444 | - | - | 0.444 | - | - |
| claude-opus-5-5 | confidence-0.6 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | confidence-0.8 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | confidence-0.9 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | confidence-0.95 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.6 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.6-confidence-0.6 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.6-confidence-0.8 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.6-confidence-0.9 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.6-confidence-0.95 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.7 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.7-confidence-0.6 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.7-confidence-0.8 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.7-confidence-0.9 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.7-confidence-0.95 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.8 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.8-confidence-0.6 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.8-confidence-0.8 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.8-confidence-0.9 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.8-confidence-0.95 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.9 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.9-confidence-0.6 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.9-confidence-0.8 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.9-confidence-0.9 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | dedup-0.9-confidence-0.95 | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-opus-5-5 | off | 29% | 100% | 0.444 | 0.444 | 0.444 | 0.444 | - | 0 (0) |
| claude-sonnet-5 | plain | 35% | 97% | 0.520 | - | - | 0.516 | - | - |
| claude-sonnet-5 | confidence-0.6 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | confidence-0.8 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | confidence-0.9 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | confidence-0.95 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.6 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.6-confidence-0.6 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.6-confidence-0.8 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.6-confidence-0.9 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.6-confidence-0.95 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.7 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.7-confidence-0.6 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.7-confidence-0.8 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.7-confidence-0.9 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.7-confidence-0.95 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.8 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.8-confidence-0.6 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.8-confidence-0.8 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.8-confidence-0.9 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.8-confidence-0.95 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.9 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.9-confidence-0.6 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.9-confidence-0.8 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.9-confidence-0.9 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | dedup-0.9-confidence-0.95 | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |
| claude-sonnet-5 | off | 35% | 97% | 0.520 | 0.520 | 0.520 | 0.516 | - | 0 (0) |

## Verdict

- `review.confidence`: insufficient-replications at 0.95. [claude-opus-5-5] the judged replications give no spread.
- `review.dedup`: not-exercised. [claude-opus-5-5] the judged replications give no spread.
