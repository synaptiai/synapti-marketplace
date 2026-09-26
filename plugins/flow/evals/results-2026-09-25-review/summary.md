# Flow review-precision eval — summary

Runs: 272 across 2 model(s), 2 arm(s) and 4 case(s). Total cost: $297.65. Models: `claude-opus-5-5`, `claude-sonnet-5`. Effort: `unpinned`.

## Reading

[claude-opus-5-5] 0 of 68 critic runs and 0 of 68 plain runs were incomplete. [claude-opus-5-5] F1 is 0.335 with the critic against 0.440 without it, a change of -0.105 against a run-to-run spread of 0.021, which does not clear the spread. [claude-sonnet-5] 0 of 68 critic runs and 0 of 68 plain runs were incomplete. [claude-sonnet-5] F1 is 0.471 with the critic against 0.510 without it, a change of -0.039 against a run-to-run spread of 0.014, which does not clear the spread. Not every model improves by more than its spread, so the rule says review.groundingCritic stays off.

Adoption rule: `review.groundingCritic` becomes the default only when the critic arm's F1 beats the plain arm's by more than that model's run-to-run spread on every model that ran, with at least two models. No improvement is a valid recorded outcome, not a failed run. Incomplete runs are not in F1, so when the critic arm leaves more runs incomplete than the plain arm by more than one run's worth on any model, a result that would adopt the critic is inconclusive instead.

Verdict: `keep-off`

## Per model × arm

| Model | Arm | Effort | Runs | Scored | Precision | Recall | F1 | Findings per run | Cost (mean) | Cache hits | Output tokens | Spread | Errors | Incomplete |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | review-b | unpinned | 68 | 68 | 28% | 100% | 0.440 | 3.5 | $1.48 | 84% (68/68) | 26763 (68/68) | 0.009 | 0 | 0 |
| claude-opus-5-5 | review-b-critic | unpinned | 68 | 68 | 20% | 100% | 0.335 | 5.0 | $1.65 | 85% (68/68) | 28773 (68/68) | 0.033 | 0 | 0 |
| claude-sonnet-5 | review-b | unpinned | 68 | 68 | 34% | 99% | 0.510 | 2.9 | $0.58 | 81% (68/68) | 13978 (68/68) | 0.012 | 0 | 0 |
| claude-sonnet-5 | review-b-critic | unpinned | 68 | 68 | 31% | 100% | 0.471 | 3.2 | $0.68 | 83% (68/68) | 16274 (68/68) | 0.016 | 0 | 0 |

Precision is the share of scored P1/P2 findings that were a run's hit — the first finding to land on a changed line of the seeded defect. Every other scored finding is false, including a further finding on a hunk the run already hit, so a run contributes at most one hit however many findings it raises. Recall is the share of runs that found the defect at all. Higher is better for both, and for F1. Findings per run counts only P1/P2 findings. Incomplete runs — no findings block, unparseable JSON, or a timeout — are excluded from precision, recall and F1 and counted on their own, so a broken run never reads as a clean miss.

Spread is how much F1 moves between repeats of the same matrix. Run 1 of every case and trap is one replication, run 2 is the next, and so on; each replication gets its own F1, and an arm's spread is the largest of those minus the smallest. A model's spread is the mean over its arms. A single run is not a replication, so a matrix run once has no spread and the adoption rule cannot be applied to it.

## Per model × arm × case × trap

| Model | Arm | Case | Trap | Runs | Scored | Hits | False findings | Precision | Recall | F1 | Cost | Incomplete |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | review-b-critic | four-stream-codec | big_endian_table | 2 | 2 | 2 | 11 | 15% | 100% | 0.267 | $1.80 | 0 |
| claude-opus-5-5 | review-b-critic | four-stream-codec | ceil_split | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $1.46 | 0 |
| claude-opus-5-5 | review-b-critic | four-stream-codec | no_reverse | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $1.51 | 0 |
| claude-opus-5-5 | review-b-critic | four-stream-codec | no_validation | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.67 | 0 |
| claude-opus-5-5 | review-b-critic | four-stream-codec | reverse_whole_body | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.78 | 0 |
| claude-opus-5-5 | review-b-critic | four-stream-codec | transposed_order | 2 | 2 | 2 | 13 | 13% | 100% | 0.235 | $1.75 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | difference_keeps_closedness | 2 | 2 | 2 | 10 | 17% | 100% | 0.286 | $1.65 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | equal_lower_takes_farther_flag | 2 | 2 | 2 | 2 | 50% | 100% | 0.667 | $1.53 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | float_endpoints | 2 | 2 | 2 | 13 | 13% | 100% | 0.235 | $2.16 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | halfopen_point_kept | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.49 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | intersection_closed_or | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $1.67 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | intersection_not_normalized | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $1.59 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | merge_any_touching | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.61 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | merge_only_overlapping | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $1.62 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | no_validation | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.78 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | point_dropped | 2 | 2 | 2 | 11 | 15% | 100% | 0.267 | $1.62 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | shorthand_halfopen | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.82 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | sort_by_lower_only | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $1.70 | 0 |
| claude-opus-5-5 | review-b-critic | interval-algebra | unsorted_output | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $1.64 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | accepts_nonpositive_weights | 2 | 2 | 2 | 12 | 14% | 100% | 0.250 | $1.71 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | divide_first | 2 | 2 | 2 | 11 | 15% | 100% | 0.267 | $1.78 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | float_arithmetic | 2 | 2 | 2 | 11 | 15% | 100% | 0.267 | $1.86 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | hardcoded_places | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $1.56 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | round_half_up | 2 | 2 | 2 | 11 | 15% | 100% | 0.267 | $1.74 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | sorted_output | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.54 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | ties_by_weight | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.74 | 0 |
| claude-opus-5-5 | review-b-critic | money-allocator | ties_last_first | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.66 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | counts_denied | 2 | 2 | 2 | 11 | 15% | 100% | 0.267 | $1.44 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | fixed_window | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.40 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | inclusive_boundary | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.53 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | limit_off_by_one | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.45 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | no_monotonic_check | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.61 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | retry_from_newest | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.65 | 0 |
| claude-opus-5-5 | review-b-critic | sliding-window-limiter | shared_counter | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $1.46 | 0 |
| claude-opus-5-5 | review-b | four-stream-codec | big_endian_table | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.50 | 0 |
| claude-opus-5-5 | review-b | four-stream-codec | ceil_split | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.47 | 0 |
| claude-opus-5-5 | review-b | four-stream-codec | no_reverse | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $1.55 | 0 |
| claude-opus-5-5 | review-b | four-stream-codec | no_validation | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.49 | 0 |
| claude-opus-5-5 | review-b | four-stream-codec | reverse_whole_body | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.58 | 0 |
| claude-opus-5-5 | review-b | four-stream-codec | transposed_order | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.46 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | difference_keeps_closedness | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $1.35 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | equal_lower_takes_farther_flag | 2 | 2 | 2 | 2 | 50% | 100% | 0.667 | $1.32 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | float_endpoints | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $2.07 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | halfopen_point_kept | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $1.43 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | intersection_closed_or | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $1.40 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | intersection_not_normalized | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $1.36 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | merge_any_touching | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $1.30 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | merge_only_overlapping | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $1.34 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | no_validation | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $1.93 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | point_dropped | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $1.39 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | shorthand_halfopen | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $1.73 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | sort_by_lower_only | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $1.69 | 0 |
| claude-opus-5-5 | review-b | interval-algebra | unsorted_output | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $1.39 | 0 |
| claude-opus-5-5 | review-b | money-allocator | accepts_nonpositive_weights | 2 | 2 | 2 | 13 | 13% | 100% | 0.235 | $1.50 | 0 |
| claude-opus-5-5 | review-b | money-allocator | divide_first | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.64 | 0 |
| claude-opus-5-5 | review-b | money-allocator | float_arithmetic | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $1.71 | 0 |
| claude-opus-5-5 | review-b | money-allocator | hardcoded_places | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.44 | 0 |
| claude-opus-5-5 | review-b | money-allocator | round_half_up | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $1.52 | 0 |
| claude-opus-5-5 | review-b | money-allocator | sorted_output | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.39 | 0 |
| claude-opus-5-5 | review-b | money-allocator | ties_by_weight | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.57 | 0 |
| claude-opus-5-5 | review-b | money-allocator | ties_last_first | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.65 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | counts_denied | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.30 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | fixed_window | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $1.45 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | inclusive_boundary | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $1.35 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | limit_off_by_one | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $1.19 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | no_monotonic_check | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $1.21 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | retry_from_newest | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $1.21 | 0 |
| claude-opus-5-5 | review-b | sliding-window-limiter | shared_counter | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $1.32 | 0 |
| claude-sonnet-5 | review-b-critic | four-stream-codec | big_endian_table | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $0.80 | 0 |
| claude-sonnet-5 | review-b-critic | four-stream-codec | ceil_split | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.61 | 0 |
| claude-sonnet-5 | review-b-critic | four-stream-codec | no_reverse | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.73 | 0 |
| claude-sonnet-5 | review-b-critic | four-stream-codec | no_validation | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $0.58 | 0 |
| claude-sonnet-5 | review-b-critic | four-stream-codec | reverse_whole_body | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.74 | 0 |
| claude-sonnet-5 | review-b-critic | four-stream-codec | transposed_order | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $0.63 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | difference_keeps_closedness | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.65 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | equal_lower_takes_farther_flag | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.68 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | float_endpoints | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.77 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | halfopen_point_kept | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.66 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | intersection_closed_or | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.61 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | intersection_not_normalized | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $0.66 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | merge_any_touching | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.61 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | merge_only_overlapping | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.64 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | no_validation | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $0.65 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | point_dropped | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.67 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | shorthand_halfopen | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $0.74 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | sort_by_lower_only | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.74 | 0 |
| claude-sonnet-5 | review-b-critic | interval-algebra | unsorted_output | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.72 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | accepts_nonpositive_weights | 2 | 2 | 2 | 10 | 17% | 100% | 0.286 | $0.69 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | divide_first | 2 | 2 | 2 | 8 | 20% | 100% | 0.333 | $0.75 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | float_arithmetic | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $0.72 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | hardcoded_places | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $0.66 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | round_half_up | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $0.73 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | sorted_output | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.75 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | ties_by_weight | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $0.68 | 0 |
| claude-sonnet-5 | review-b-critic | money-allocator | ties_last_first | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $0.77 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | counts_denied | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.54 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | fixed_window | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $0.73 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | inclusive_boundary | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.66 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | limit_off_by_one | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $0.62 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | no_monotonic_check | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $0.65 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | retry_from_newest | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.62 | 0 |
| claude-sonnet-5 | review-b-critic | sliding-window-limiter | shared_counter | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.61 | 0 |
| claude-sonnet-5 | review-b | four-stream-codec | big_endian_table | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.59 | 0 |
| claude-sonnet-5 | review-b | four-stream-codec | ceil_split | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.54 | 0 |
| claude-sonnet-5 | review-b | four-stream-codec | no_reverse | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $0.61 | 0 |
| claude-sonnet-5 | review-b | four-stream-codec | no_validation | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $0.58 | 0 |
| claude-sonnet-5 | review-b | four-stream-codec | reverse_whole_body | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.67 | 0 |
| claude-sonnet-5 | review-b | four-stream-codec | transposed_order | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.63 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | difference_keeps_closedness | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $0.54 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | equal_lower_takes_farther_flag | 2 | 2 | 2 | 2 | 50% | 100% | 0.667 | $0.62 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | float_endpoints | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.60 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | halfopen_point_kept | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.53 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | intersection_closed_or | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $0.59 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | intersection_not_normalized | 2 | 2 | 2 | 2 | 50% | 100% | 0.667 | $0.52 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | merge_any_touching | 2 | 2 | 1 | 2 | 33% | 50% | 0.400 | $0.57 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | merge_only_overlapping | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $0.58 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | no_validation | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.64 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | point_dropped | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.59 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | shorthand_halfopen | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $0.61 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | sort_by_lower_only | 2 | 2 | 2 | 2 | 50% | 100% | 0.667 | $0.63 | 0 |
| claude-sonnet-5 | review-b | interval-algebra | unsorted_output | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.56 | 0 |
| claude-sonnet-5 | review-b | money-allocator | accepts_nonpositive_weights | 2 | 2 | 2 | 13 | 13% | 100% | 0.235 | $0.58 | 0 |
| claude-sonnet-5 | review-b | money-allocator | divide_first | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.64 | 0 |
| claude-sonnet-5 | review-b | money-allocator | float_arithmetic | 2 | 2 | 2 | 9 | 18% | 100% | 0.308 | $0.61 | 0 |
| claude-sonnet-5 | review-b | money-allocator | hardcoded_places | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.54 | 0 |
| claude-sonnet-5 | review-b | money-allocator | round_half_up | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $0.58 | 0 |
| claude-sonnet-5 | review-b | money-allocator | sorted_output | 2 | 2 | 2 | 6 | 25% | 100% | 0.400 | $0.51 | 0 |
| claude-sonnet-5 | review-b | money-allocator | ties_by_weight | 2 | 2 | 2 | 5 | 29% | 100% | 0.444 | $0.59 | 0 |
| claude-sonnet-5 | review-b | money-allocator | ties_last_first | 2 | 2 | 2 | 2 | 50% | 100% | 0.667 | $0.63 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | counts_denied | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.56 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | fixed_window | 2 | 2 | 2 | 7 | 22% | 100% | 0.364 | $0.54 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | inclusive_boundary | 2 | 2 | 2 | 3 | 40% | 100% | 0.571 | $0.52 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | limit_off_by_one | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $0.51 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | no_monotonic_check | 2 | 2 | 2 | 1 | 67% | 100% | 0.800 | $0.53 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | retry_from_newest | 2 | 2 | 2 | 0 | 100% | 100% | 1.000 | $0.52 | 0 |
| claude-sonnet-5 | review-b | sliding-window-limiter | shared_counter | 2 | 2 | 2 | 4 | 33% | 100% | 0.500 | $0.56 | 0 |

## Confidence against where the finding landed

| Model | Arm | Confidence | On a changed line | Elsewhere |
|---|---|---|---|---|
| claude-opus-5-5 | review-b | HIGH | 142 | 50 |
| claude-opus-5-5 | review-b | MEDIUM | 31 | 18 |
| claude-opus-5-5 | review-b-critic | HIGH | 163 | 127 |
| claude-opus-5-5 | review-b-critic | MEDIUM | 34 | 14 |
| claude-sonnet-5 | review-b | HIGH | 132 | 15 |
| claude-sonnet-5 | review-b | LOW | 1 | 1 |
| claude-sonnet-5 | review-b | MEDIUM | 34 | 12 |
| claude-sonnet-5 | review-b-critic | HIGH | 127 | 27 |
| claude-sonnet-5 | review-b-critic | LOW | 2 | 0 |
| claude-sonnet-5 | review-b-critic | MEDIUM | 34 | 31 |

