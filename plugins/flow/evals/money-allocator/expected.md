# money-allocator: seeded traps and what catches them

Module under test: `allocate.py`. Hidden suite: `hidden/test_hidden.py`
(25 tests, standard-library `unittest`). Reference: `hidden/reference_impl.py`.
Wrong variants: `hidden/traps/*.py`. The exact test-id list per trap is in
`hidden/traps.json`; regenerate and re-verify with
`plugins/flow/bin/flow-eval-run.sh --check-cases`.

Most traps produce the right answer on the inputs agents reach for first:
equal weights, amounts that divide evenly, `places=2`, sorted weights. The
hidden suite uses hand-computed shares with tied remainders, unsorted and
symmetric weights, other precisions and a 17-significant-digit amount.

| Trap | Plausible wrong implementation | Input that masks it | Discriminating hidden tests |
|---|---|---|---|
| `round_half_up` | Each share rounded independently (ROUND_HALF_UP) | Shares that are exact at `places` | `test_half_remainders_are_not_all_rounded_up`, `test_equal_weights_extra_cent_goes_to_first`, `test_sum_equals_amount_for_many_shapes` (+8 more) |
| `ties_last_first` | Remainder ties go to the highest index | No tied remainders | `test_tie_goes_to_lowest_index`, `test_symmetric_weights_asymmetric_result`, `test_two_leftover_units_go_to_first_two_on_full_tie` (+7 more) |
| `ties_by_weight` | Remainder ties go to the larger weight | Tied entries with equal weights | `test_tie_between_different_weights_goes_to_lowest_index` |
| `sorted_output` | Result ordered by descending weight | Weights already sorted descending, or all equal | `test_output_order_follows_weights_order`, `test_asymmetric_weights_known_answer` (+5 more) |
| `float_arithmetic` | Amount and shares computed in binary float | Amounts within ~15 significant digits | `test_large_amount_is_exact` |
| `divide_first` | `floor(units / sum(weights)) * w`, leftover handed out round-robin | `total_units` a multiple of `sum(weights)` | `test_multiply_before_divide`, `test_asymmetric_weights_known_answer` (+2 more) |
| `hardcoded_places` | `places` ignored, always 2 | `places == 2` | `test_places_zero_whole_units`, `test_places_three`, `test_amount_with_excess_precision_rejected` |
| `accepts_nonpositive_weights` | No input validation | Well-formed inputs | `test_zero_weight_rejected`, `test_negative_weight_rejected`, `test_empty_weights_rejected` (+3 more) |

Verification record (run at authoring time, repeatable with `--check-cases`):
the reference passes 25/25; each variant fails exactly the tests listed for
it in `hidden/traps.json` (round_half_up 11, ties_last_first 10,
ties_by_weight 1, sorted_output 7, float_arithmetic 1, divide_first 4,
hardcoded_places 3, accepts_nonpositive_weights 6).

Degenerate inputs the heuristic flags for this case: all-equal weight lists
(`[1, 1, 1]`), single-weight lists, palindromic weight lists (`[1, 2, 1]`)
and empty lists. Equal weights mask `ties_by_weight` and `sorted_output`; a
single weight masks everything except validation.
