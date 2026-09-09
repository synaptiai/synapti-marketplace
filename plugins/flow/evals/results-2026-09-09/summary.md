# Flow correctness eval — summary

Runs: 63 across 7 arm(s) and 3 case(s). Total cost: $68.12. Run-to-run spread (mean per-cell max−min of hidden pass rate): 0%.

## Reading

Hidden pass rate under tddMode=enforce (100%) is not below the best non-enforce plugin arm (suggest, 100%) by more than the run-to-run spread (0.0 points vs 0.0), so the rule keeps testing.tddMode=enforce. Arms with specFirst.riskMap=true average 100% hidden pass rate against 100% without it (+0.0 points, within the spread). The no-plugin baseline scores 100% against a plugin-arm average of 100%.

Verdict: `keep-enforce`

## Per arm

| Arm | Runs | Hidden pass rate | All-pass runs | Own tests (mean) | Degenerate share | Cost (mean) | Turns (mean) | Errors |
|---|---|---|---|---|---|---|---|---|
| baseline | 9 | 100% | 100% | 24.3 | 38% | $0.17 | 7.9 | 0 |
| enforce-risk | 9 | 100% | 100% | 18.8 | 28% | $1.59 | 40.0 | 0 |
| enforce-norisk | 9 | 100% | 100% | 15.7 | 11% | $1.84 | 26.3 | 0 |
| suggest-risk | 9 | 100% | 100% | 18.0 | 34% | $1.40 | 19.1 | 0 |
| suggest-norisk | 9 | 100% | 100% | 18.8 | 33% | $1.31 | 15.4 | 0 |
| off-risk | 9 | 100% | 100% | 20.6 | 36% | $0.64 | 15.3 | 0 |
| off-norisk | 9 | 100% | 100% | 19.7 | 30% | $0.61 | 16.7 | 0 |

## Per arm × case

| Arm | Case | Runs | Hidden pass rate (min–max) | All-pass | Own tests | Degenerate share | Cost | Turns | Errors |
|---|---|---|---|---|---|---|---|---|---|
| baseline | four-stream-codec | 3 | 100% (100%–100%) | 100% | 27.3 | 27% | $0.16 | 7.3 | 0 |
| baseline | money-allocator | 3 | 100% (100%–100%) | 100% | 23.0 | 49% | $0.20 | 8.3 | 0 |
| baseline | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 22.7 | - | $0.16 | 8.0 | 0 |
| enforce-risk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 20.7 | 26% | $1.33 | 44.0 | 0 |
| enforce-risk | money-allocator | 3 | 100% (100%–100%) | 100% | 16.3 | 29% | $2.14 | 26.3 | 0 |
| enforce-risk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 19.3 | - | $1.31 | 49.7 | 0 |
| enforce-norisk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 15.3 | 10% | $1.63 | 21.0 | 0 |
| enforce-norisk | money-allocator | 3 | 100% (100%–100%) | 100% | 16.0 | 13% | $1.62 | 26.0 | 0 |
| enforce-norisk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 15.7 | - | $2.28 | 32.0 | 0 |
| suggest-risk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 18.7 | 26% | $1.25 | 25.0 | 0 |
| suggest-risk | money-allocator | 3 | 100% (100%–100%) | 100% | 16.0 | 42% | $1.77 | 17.3 | 0 |
| suggest-risk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 19.3 | - | $1.18 | 15.0 | 0 |
| suggest-norisk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 17.3 | 24% | $0.89 | 15.7 | 0 |
| suggest-norisk | money-allocator | 3 | 100% (100%–100%) | 100% | 15.3 | 42% | $1.70 | 14.7 | 0 |
| suggest-norisk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 23.7 | - | $1.34 | 16.0 | 0 |
| off-risk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 22.3 | 30% | $0.56 | 13.3 | 0 |
| off-risk | money-allocator | 3 | 100% (100%–100%) | 100% | 19.3 | 42% | $0.75 | 16.7 | 0 |
| off-risk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 20.0 | - | $0.61 | 16.0 | 0 |
| off-norisk | four-stream-codec | 3 | 100% (100%–100%) | 100% | 19.0 | 20% | $0.63 | 17.0 | 0 |
| off-norisk | money-allocator | 3 | 100% (100%–100%) | 100% | 20.0 | 40% | $0.65 | 15.0 | 0 |
| off-norisk | sliding-window-limiter | 3 | 100% (100%–100%) | 100% | 20.0 | - | $0.55 | 18.0 | 0 |

## Trap catch rate (share of runs whose implementation fell into the trap; lower is better)

### four-stream-codec

| Arm | big_endian_table | ceil_split | no_reverse | no_validation | reverse_whole_body | transposed_order |
|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% |

### money-allocator

| Arm | accepts_nonpositive_weights | divide_first | float_arithmetic | hardcoded_places | round_half_up | sorted_output | ties_by_weight | ties_last_first |
|---|---|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |

### sliding-window-limiter

| Arm | counts_denied | fixed_window | inclusive_boundary | limit_off_by_one | no_monotonic_check | retry_from_newest | shared_counter |
|---|---|---|---|---|---|---|---|
| baseline | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| enforce-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| suggest-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-risk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| off-norisk | 0% | 0% | 0% | 0% | 0% | 0% | 0% |

Skills invoked per cell are listed in summary.json (`per_cell.*.skills_invoked`); a plugin arm with no `flow:*` skill invocation did not exercise the plugin.
