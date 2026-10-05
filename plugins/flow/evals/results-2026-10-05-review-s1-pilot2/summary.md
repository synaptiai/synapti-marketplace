# Flow review-precision eval — summary

Runs: 4 across 2 model(s), 1 arm(s) and 2 case(s). Total cost: $5.73. Models: `claude-opus-5-5`, `claude-sonnet-5`. Effort: `high`, `medium`.

## Reading

[claude-opus-5-5] one of the two arms has no scored run, so the rule cannot be applied. [claude-sonnet-5] one of the two arms has no scored run, so the rule cannot be applied. Not every model improves by more than its spread, so the rule says review.groundingCritic stays off.

Adoption rule: `review.groundingCritic` becomes the default only when the critic arm's F1 beats the plain arm's by more than that model's run-to-run spread on every model that ran, with at least two models. No improvement is a valid recorded outcome, not a failed run. Incomplete runs are not in F1, so when the critic arm leaves more runs incomplete than the plain arm by more than one run's worth on any model, a result that would adopt the critic is inconclusive instead.

Verdict: `keep-off`

## Per model × arm

| Model | Arm | Effort | Runs | Scored | Precision | Recall | F1 | Findings per run | Cost (mean) | Cache hits | Output tokens | Spread | Errors | Incomplete |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | review-b | medium | 2 | 2 | 22% | 100% | 0.364 | 4.5 | $1.45 | 83% (2/2) | 26840 (2/2) | - | 0 | 0 |
| claude-sonnet-5 | review-b | high | 2 | 2 | 100% | 100% | 1.000 | 1.0 | $1.41 | 91% (2/2) | 43762 (2/2) | - | 0 | 0 |

Precision is the share of scored P1/P2 findings that were a run's hit — the first finding to land on a changed line of the seeded defect. Every other scored finding is false, including a further finding on a hunk the run already hit, so a run contributes at most one hit however many findings it raises. Recall is the share of runs that found the defect at all. Higher is better for both, and for F1. Findings per run counts only P1/P2 findings. Incomplete runs — no findings block, unparseable JSON, or a timeout — are excluded from precision, recall and F1 and counted on their own, so a broken run never reads as a clean miss.

Spread is how much F1 moves between repeats of the same matrix. Run 1 of every case and trap is one replication, run 2 is the next, and so on; each replication gets its own F1, and an arm's spread is the largest of those minus the smallest. A model's spread is the mean over its arms. A single run is not a replication, so a matrix run once has no spread and the adoption rule cannot be applied to it.

## Per model × arm × case × trap

| Model | Arm | Case | Trap | Runs | Scored | Hits | False findings | Precision | Recall | F1 | Cost | Incomplete |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | review-b | interval-algebra | point_dropped | 1 | 1 | 1 | 4 | 20% | 100% | 0.333 | $1.66 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | counts_denied | 1 | 1 | 1 | 3 | 25% | 100% | 0.400 | $1.24 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | point_dropped | 1 | 1 | 1 | 0 | 100% | 100% | 1.000 | $1.28 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | counts_denied | 1 | 1 | 1 | 0 | 100% | 100% | 1.000 | $1.55 | 0 |

## Confidence against where the finding landed

| Model | Arm | Confidence | On a changed line | Elsewhere |
|---|---|---|---|---|
| claude-opus-5-5 | review-b | HIGH | 3 | 6 |
| claude-sonnet-5 | review-b | HIGH | 2 | 0 |

