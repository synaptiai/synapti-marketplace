# Flow correctness eval — summary

Runs: 105 across 2 model(s), 7 arm(s) and 4 case(s). Total cost: $184.65. Models: `claude-opus-5`, `claude-sonnet-5`.

## Reading

**claude-opus-5** (21 runs, $88.70, run-to-run spread 0%, own-test spread 9%): Hidden pass rate under tddMode=enforce (100%) is not below the best non-enforce plugin arm (suggest, 100%) by more than the run-to-run spread (0.0 points vs 0.0), so on the primary signal the rule keeps testing.tddMode=enforce. The arms tie within the spread, so the secondary signal decides: the agent's own tests catch 95% of the trap variants under enforce against 95% under suggest (-0.0 points for suggest, own-test spread 8.8), so the rule keeps testing.tddMode=enforce. Arms with specFirst.riskMap=true average 100% hidden pass rate against 100% without it (+0.0 points, within the spread). The no-plugin baseline scores 100% against a plugin-arm average of 100%. Own tests catch 97% of the trap variants on the baseline against 95% on the plugin arms. The comparison is incomplete (not every arm has >= 3 runs on every case); treat the reading as provisional.

Verdict for `claude-opus-5`: `keep-enforce` (decided by the secondary signal)

**claude-sonnet-5** (84 runs, $95.95, run-to-run spread 1%, own-test spread 6%): Hidden pass rate under tddMode=enforce (99%) is not below the best non-enforce plugin arm (off, 99%) by more than the run-to-run spread (0.3 points vs 1.3), so on the primary signal the rule keeps testing.tddMode=enforce. The arms tie within the spread, so the secondary signal decides: the agent's own tests catch 92% of the trap variants under enforce against 91% under off (-0.3 points for off, own-test spread 5.7), so the rule keeps testing.tddMode=enforce. Arms with specFirst.riskMap=true average 99% hidden pass rate against 99% without it (+0.3 points, within the spread). The no-plugin baseline scores 99% against a plugin-arm average of 99%. Own tests catch 90% of the trap variants on the baseline against 91% on the plugin arms.

Verdict for `claude-sonnet-5`: `keep-enforce` (decided by the secondary signal)

## Per model × arm

| Model | Arm | Runs | Hidden pass rate | All-pass runs | Own tests catch traps | Own tests (mean) | Degenerate share | Cost (mean) | Turns (mean) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5 | baseline | 3 | 100% | 100% | 97% (3/3) | 57.7 | 73% | $1.13 | 11.7 | 0 |
| claude-opus-5 | enforce-risk | 3 | 100% | 100% | 95% (3/3) | 56.0 | 69% | $5.61 | 25.7 | 0 |
| claude-opus-5 | enforce-norisk | 3 | 100% | 100% | 95% (3/3) | 44.3 | 69% | $5.03 | 28.7 | 0 |
| claude-opus-5 | suggest-risk | 3 | 100% | 100% | 97% (3/3) | 45.3 | 69% | $5.31 | 33.3 | 0 |
| claude-opus-5 | suggest-norisk | 3 | 100% | 100% | 92% (3/3) | 47.3 | 71% | $5.30 | 36.7 | 0 |
| claude-opus-5 | off-risk | 3 | 100% | 100% | 95% (3/3) | 50.3 | 72% | $4.46 | 31.3 | 0 |
| claude-opus-5 | off-norisk | 3 | 100% | 100% | 95% (3/3) | 47.7 | 75% | $2.72 | 23.7 | 0 |
| claude-sonnet-5 | baseline | 12 | 99% | 75% | 90% (12/12) | 26.3 | 56% | $0.27 | 9.3 | 0 |
| claude-sonnet-5 | enforce-risk | 12 | 99% | 92% | 92% (12/12) | 19.5 | 44% | $1.89 | 28.9 | 0 |
| claude-sonnet-5 | enforce-norisk | 12 | 99% | 83% | 91% (12/12) | 19.0 | 41% | $1.55 | 28.8 | 0 |
| claude-sonnet-5 | suggest-risk | 12 | 99% | 83% | 89% (12/12) | 21.5 | 45% | $1.62 | 26.6 | 0 |
| claude-sonnet-5 | suggest-norisk | 12 | 99% | 75% | 93% (12/12) | 19.3 | 38% | $1.15 | 21.5 | 0 |
| claude-sonnet-5 | off-risk | 12 | 100% | 92% | 91% (12/12) | 22.2 | 45% | $0.79 | 16.2 | 0 |
| claude-sonnet-5 | off-norisk | 12 | 99% | 83% | 91% (12/12) | 22.6 | 42% | $0.73 | 15.7 | 0 |

## Per model × arm × case

| Model | Arm | Case | Runs | Hidden pass rate (min–max) | All-pass | Own tests catch traps | Own tests | Degenerate share | Cost | Turns | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-opus-5 | baseline | interval-algebra | 3 | 100% (100%–100%) | 100% | 97% (3/3) | 57.7 | 73% | $1.13 | 11.7 | 0 |
| claude-opus-5 | enforce-risk | interval-algebra | 3 | 100% (100%–100%) | 100% | 95% (3/3) | 56.0 | 69% | $5.61 | 25.7 | 0 |
| claude-opus-5 | enforce-norisk | interval-algebra | 3 | 100% (100%–100%) | 100% | 95% (3/3) | 44.3 | 69% | $5.03 | 28.7 | 0 |
| claude-opus-5 | suggest-risk | interval-algebra | 3 | 100% (100%–100%) | 100% | 97% (3/3) | 45.3 | 69% | $5.31 | 33.3 | 0 |
| claude-opus-5 | suggest-norisk | interval-algebra | 3 | 100% (100%–100%) | 100% | 92% (3/3) | 47.3 | 71% | $5.30 | 36.7 | 0 |
| claude-opus-5 | off-risk | interval-algebra | 3 | 100% (100%–100%) | 100% | 95% (3/3) | 50.3 | 72% | $4.46 | 31.3 | 0 |
| claude-opus-5 | off-norisk | interval-algebra | 3 | 100% (100%–100%) | 100% | 95% (3/3) | 47.7 | 75% | $2.72 | 23.7 | 0 |
| claude-sonnet-5 | baseline | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 25.0 | 32% | $0.18 | 9.3 | 0 |
| claude-sonnet-5 | baseline | interval-algebra | 3 | 97% (97%–97%) | 0% | 85% (3/3) | 36.3 | 77% | $0.52 | 11.3 | 0 |
| claude-sonnet-5 | baseline | money-allocator | 3 | 100% (100%–100%) | 100% | 75% (3/3) | 22.7 | 58% | $0.19 | 8.0 | 0 |
| claude-sonnet-5 | baseline | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 21.3 | - | $0.18 | 8.7 | 0 |
| claude-sonnet-5 | enforce-risk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 17.7 | 21% | $1.59 | 23.3 | 0 |
| claude-sonnet-5 | enforce-risk | interval-algebra | 3 | 96% (87%–100%) | 67% | 90% (3/3) | 22.0 | 75% | $2.15 | 38.0 | 0 |
| claude-sonnet-5 | enforce-risk | money-allocator | 3 | 100% (100%–100%) | 100% | 79% (3/3) | 17.0 | 37% | $1.98 | 15.7 | 0 |
| claude-sonnet-5 | enforce-risk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 21.3 | - | $1.82 | 38.7 | 0 |
| claude-sonnet-5 | enforce-norisk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 17.7 | 18% | $1.80 | 26.7 | 0 |
| claude-sonnet-5 | enforce-norisk | interval-algebra | 3 | 98% (97%–100%) | 33% | 85% (3/3) | 28.3 | 74% | $2.20 | 33.7 | 0 |
| claude-sonnet-5 | enforce-norisk | money-allocator | 3 | 100% (100%–100%) | 100% | 79% (3/3) | 16.3 | 31% | $1.02 | 16.0 | 0 |
| claude-sonnet-5 | enforce-norisk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 13.7 | - | $1.17 | 38.7 | 0 |
| claude-sonnet-5 | suggest-risk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 20.0 | 17% | $1.21 | 26.3 | 0 |
| claude-sonnet-5 | suggest-risk | interval-algebra | 3 | 98% (97%–100%) | 33% | 82% (3/3) | 29.0 | 74% | $2.19 | 30.3 | 0 |
| claude-sonnet-5 | suggest-risk | money-allocator | 3 | 100% (100%–100%) | 100% | 75% (3/3) | 15.7 | 44% | $1.47 | 23.3 | 0 |
| claude-sonnet-5 | suggest-risk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 21.3 | - | $1.63 | 26.3 | 0 |
| claude-sonnet-5 | suggest-norisk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 18.3 | 4% | $0.98 | 16.0 | 0 |
| claude-sonnet-5 | suggest-norisk | interval-algebra | 3 | 94% (90%–97%) | 0% | 85% (3/3) | 27.3 | 71% | $1.46 | 25.7 | 0 |
| claude-sonnet-5 | suggest-norisk | money-allocator | 3 | 100% (100%–100%) | 100% | 88% (3/3) | 16.3 | 38% | $1.28 | 26.0 | 0 |
| claude-sonnet-5 | suggest-norisk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 15.3 | - | $0.89 | 18.3 | 0 |
| claude-sonnet-5 | off-risk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 19.3 | 15% | $0.66 | 16.3 | 0 |
| claude-sonnet-5 | off-risk | interval-algebra | 3 | 99% (97%–100%) | 67% | 87% (3/3) | 28.0 | 73% | $0.94 | 16.0 | 0 |
| claude-sonnet-5 | off-risk | money-allocator | 3 | 100% (100%–100%) | 100% | 83% (3/3) | 22.7 | 47% | $0.76 | 16.3 | 0 |
| claude-sonnet-5 | off-risk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 95% (3/3) | 18.7 | - | $0.80 | 16.0 | 0 |
| claude-sonnet-5 | off-norisk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 27.0 | 22% | $0.61 | 17.0 | 0 |
| claude-sonnet-5 | off-norisk | interval-algebra | 3 | 97% (93%–100%) | 33% | 90% (3/3) | 29.0 | 75% | $0.92 | 15.3 | 0 |
| claude-sonnet-5 | off-norisk | money-allocator | 3 | 100% (100%–100%) | 100% | 75% (3/3) | 17.3 | 28% | $0.68 | 16.0 | 0 |
| claude-sonnet-5 | off-norisk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 100% (3/3) | 17.0 | - | $0.71 | 14.3 | 0 |

## Trap catch rate (share of runs whose implementation fell into the trap; lower is better)

### claude-opus-5 — interval-algebra

| Arm | difference_keeps_closedness | equal_lower_takes_farther_flag | float_endpoints | halfopen_point_kept | intersection_closed_or | intersection_not_normalized | merge_any_touching | merge_only_overlapping | no_validation | point_dropped | shorthand_halfopen | sort_by_lower_only | unsorted_output |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |

### claude-sonnet-5 — four-stream-codec

| Arm | big_endian_table | ceil_split | no_reverse | no_validation | reverse_whole_body | transposed_order |
|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% |

### claude-sonnet-5 — interval-algebra

| Arm | difference_keeps_closedness | equal_lower_takes_farther_flag | float_endpoints | halfopen_point_kept | intersection_closed_or | intersection_not_normalized | merge_any_touching | merge_only_overlapping | no_validation | point_dropped | shorthand_halfopen | sort_by_lower_only | unsorted_output |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 100% | 0% |
| enforce-risk | 0% | 33% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 33% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 33% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 67% | 0% |
| suggest-norisk | 0% | 33% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 100% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 33% | 0% |
| off-norisk | 0% | 33% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 67% | 0% |

### claude-sonnet-5 — money-allocator

| Arm | accepts_nonpositive_weights | divide_first | float_arithmetic | hardcoded_places | round_half_up | sorted_output | ties_by_weight | ties_last_first |
|---|---|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |

### claude-sonnet-5 — sliding-window-limiter

| Arm | counts_denied | fixed_window | inclusive_boundary | limit_off_by_one | no_monotonic_check | retry_from_newest | shared_counter |
|---|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |

## Own-test trap catch rate (share of runs whose own tests fail the trap variant; higher is better)

A run is scored only when its `tests/` suite imports the module, passes at least one test against the agent's own implementation, and uses no names the variants lack; `summary.json` lists the reasons for unscored runs (`per_cell.*.own_test_trap_unscored_reasons`).

### claude-opus-5 — interval-algebra

| Arm | scored runs | difference_keeps_closedness | equal_lower_takes_farther_flag | float_endpoints | halfopen_point_kept | intersection_closed_or | intersection_not_normalized | merge_any_touching | merge_only_overlapping | no_validation | point_dropped | shorthand_halfopen | sort_by_lower_only | unsorted_output |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 3/3 | 100% | 67% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| enforce-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 33% | 100% |
| enforce-norisk | 3/3 | 100% | 67% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 67% | 100% |
| suggest-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 67% | 100% |
| suggest-norisk | 3/3 | 100% | 33% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 67% | 100% |
| off-risk | 3/3 | 100% | 33% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| off-norisk | 3/3 | 100% | 33% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

### claude-sonnet-5 — four-stream-codec

| Arm | scored runs | big_endian_table | ceil_split | no_reverse | no_validation | reverse_whole_body | transposed_order |
|---|---|---|---|---|---|---|---|
| baseline | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |
| enforce-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |
| enforce-norisk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |
| suggest-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |
| suggest-norisk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |
| off-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |
| off-norisk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% |

### claude-sonnet-5 — interval-algebra

| Arm | scored runs | difference_keeps_closedness | equal_lower_takes_farther_flag | float_endpoints | halfopen_point_kept | intersection_closed_or | intersection_not_normalized | merge_any_touching | merge_only_overlapping | no_validation | point_dropped | shorthand_halfopen | sort_by_lower_only | unsorted_output |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 3/3 | 100% | 0% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 0% | 100% |
| enforce-risk | 3/3 | 100% | 0% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 67% | 100% |
| enforce-norisk | 3/3 | 100% | 0% | 67% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 33% | 100% |
| suggest-risk | 3/3 | 100% | 33% | 33% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 0% | 100% |
| suggest-norisk | 3/3 | 100% | 33% | 67% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 0% | 100% |
| off-risk | 3/3 | 100% | 33% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 0% | 100% |
| off-norisk | 3/3 | 100% | 33% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 33% | 100% |

### claude-sonnet-5 — money-allocator

| Arm | scored runs | accepts_nonpositive_weights | divide_first | float_arithmetic | hardcoded_places | round_half_up | sorted_output | ties_by_weight | ties_last_first |
|---|---|---|---|---|---|---|---|---|---|
| baseline | 3/3 | 100% | 100% | 0% | 100% | 100% | 100% | 0% | 100% |
| enforce-risk | 3/3 | 100% | 100% | 33% | 100% | 100% | 100% | 0% | 100% |
| enforce-norisk | 3/3 | 100% | 100% | 0% | 100% | 100% | 100% | 33% | 100% |
| suggest-risk | 3/3 | 100% | 100% | 0% | 100% | 100% | 100% | 0% | 100% |
| suggest-norisk | 3/3 | 100% | 100% | 33% | 100% | 100% | 100% | 67% | 100% |
| off-risk | 3/3 | 100% | 100% | 33% | 100% | 100% | 100% | 33% | 100% |
| off-norisk | 3/3 | 100% | 100% | 0% | 100% | 100% | 100% | 0% | 100% |

### claude-sonnet-5 — sliding-window-limiter

| Arm | scored runs | counts_denied | fixed_window | inclusive_boundary | limit_off_by_one | no_monotonic_check | retry_from_newest | shared_counter |
|---|---|---|---|---|---|---|---|---|
| baseline | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| enforce-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| enforce-norisk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| suggest-risk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| suggest-norisk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| off-risk | 3/3 | 67% | 100% | 100% | 100% | 100% | 100% | 100% |
| off-norisk | 3/3 | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

Skills invoked per cell are listed in summary.json (`per_model.<model>.per_cell.*.skills_invoked`); a plugin arm with no `flow:*` skill invocation did not exercise the plugin.
