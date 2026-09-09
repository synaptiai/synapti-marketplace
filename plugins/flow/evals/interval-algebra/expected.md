# interval-algebra: seeded traps and what catches them

Module under test: `intervals.py`. Hidden suite: `hidden/test_hidden.py`
(30 tests, standard-library `unittest`). Reference: `hidden/reference_impl.py`.
Wrong variants: `hidden/traps/*.py`. The exact test-id list per trap is in
`hidden/traps.json`; regenerate and re-verify with
`plugins/flow/bin/flow-eval-run.sh --check-cases`.

The signature says nothing about when touching intervals merge, what a
degenerate `lo == hi` interval is, which flag wins at an equal endpoint, that
a difference flips the cut's closedness, that inputs may be non-canonical, or
that a 2-tuple is closed. Every trap passes the strictly-overlapping,
integer, sorted, 4-tuple inputs an agent writes first; the hidden suite uses
touching ends of every open/closed combination, closed and open points, a
point that fills a gap, unnormalized inputs to `intersection`, `Fraction` and
`Decimal` bounds, unbounded ends, and the 2-tuple shorthand.

| Trap | Plausible wrong implementation | Input that masks it | Discriminating hidden tests |
|---|---|---|---|
| `merge_only_overlapping` | Merge only when `hi1 > lo2`; touching closed ends stay apart | Inputs that overlap by more than a point | `test_canonical_flags_are_bool_and_bounds_keep_type`, `test_canonical_shorthand_pairs_are_closed`, `test_canonical_worked_example_from_issue` (+6 more) |
| `merge_any_touching` | Merge whenever `hi1 == lo2`, flags ignored | Touching ends with at least one closed side | `test_difference_leaves_a_point`, `test_difference_removes_a_point`, `test_touching_open_ends_stay_apart` |
| `point_dropped` | `lo == hi` always empty | No point intervals, no closed touching ends in intersection | `test_canonical_keeps_closed_point`, `test_canonical_worked_example_from_issue`, `test_difference_full_cover_is_empty_and_partial_edges` (+4 more) |
| `halfopen_point_kept` | `lo == hi` kept when either end is closed | No degenerate half-open intervals | `test_canonical_drops_open_points`, `test_difference_full_cover_is_empty_and_partial_edges`, `test_difference_leaves_a_point` (+2 more) |
| `intersection_closed_or` | Equal endpoint closed if either input is closed | Endpoints that never coincide | `test_bounds_unbounded_in_intersection_and_difference`, `test_intersect_equal_endpoints_closed_only_if_both` |
| `difference_keeps_closedness` | Complement keeps the subtrahend's flags instead of flipping them | Subtrahends with open ends | `test_bounds_unbounded_in_intersection_and_difference`, `test_difference_closed_cut_opens_ends`, `test_difference_full_cover_is_empty_and_partial_edges` (+3 more) |
| `intersection_not_normalized` | Raw pairwise product; inputs and result not normalized | Canonical inputs | `test_intersect_normalizes_inputs` |
| `unsorted_output` | No sort; only input-order neighbours merge | Sorted inputs | `test_bounds_unbounded_merge_and_sort`, `test_canonical_keeps_closed_point`, `test_canonical_merges_overlapping` (+8 more) |
| `sort_by_lower_only` | Sweep sorted by lower bound only; a point after `(3,5]` never closes the gap (seen in calibration) | Equal lower bounds arriving closed-first | `test_touching_point_fills_the_gap` |
| `equal_lower_takes_farther_flag` | At an equal lower bound the farther interval supplies both flags instead of OR (seen in calibration) | Merged intervals with distinct lower bounds | `test_canonical_merged_upper_end_takes_farther_interval` |
| `shorthand_halfopen` | 2-tuple read as `[lo, hi)` | 4-tuple inputs only | `test_bounds_unbounded_in_intersection_and_difference`, `test_bounds_unbounded_merge_and_sort`, `test_canonical_drops_reversed_bounds` (+17 more) |
| `no_validation` | Closed unbounded ends and `1`/`0` flags accepted | Well-formed input | `test_bounds_malformed_rejected`, `test_bounds_unbounded_closed_rejected` |
| `float_endpoints` | Bounds converted to `float` | Integer bounds | `test_canonical_flags_are_bool_and_bounds_keep_type` |

Verification record (run at authoring time, repeatable with `--check-cases`):
the reference passes 30/30; each variant fails exactly the tests listed for
it in `hidden/traps.json` (merge_only_overlapping 9, merge_any_touching 3, point_dropped 7, halfopen_point_kept 5, intersection_closed_or 2, difference_keeps_closedness 6, intersection_not_normalized 1, unsorted_output 11, sort_by_lower_only 1, equal_lower_takes_farther_flag 1, shorthand_halfopen 20, no_validation 2, float_endpoints 1).

Degenerate inputs the heuristic flags for this case: single-interval lists,
lists of identical intervals, empty lists, and 4-tuples such as `(1, 1, True,
True)` whose elements repeat. A single interval masks every merge and sort
trap; a list of identical intervals masks `unsorted_output` and
`intersection_not_normalized`.

## Calibration (no-plugin baseline, claude-sonnet-5, 3 runs)

Recorded from `results/calibration` on 2026-09-09 (Claude Code 2.1.266, `--model claude-sonnet-5`, `--max-turns 60`, `--max-budget-usd 4`).

| Run | Hidden pass rate | Hidden tests failed | Own tests | Own tests catch traps | Cost | Turns | Session |
|---|---|---|---|---|---|---|---|
| 1 | 30/30 (100.0%) | none | 39 | 85% | $0.61 | 21 | `6c3c44b5-93f7-4cfa-9c40-e611ba9aa09a` |
| 2 | 28/30 (93.3%) | `test_canonical_merged_upper_end_takes_farther_interval`, `test_touching_point_fills_the_gap` | 38 | 85% | $0.50 | 14 | `5fb9d43d-9407-4b14-992c-e53b9ec952da` |
| 3 | 29/30 (96.7%) | `test_touching_point_fills_the_gap` | 33 | 85% | $0.47 | 8 | `42a9952d-c1e9-44b6-a0e5-1a99a7eab3c2` |

Bar (the baseline fails at least one hidden test in at least one of three runs): **cleared**. Mean baseline cost $0.53 per run.

Runs 2 and 3 failed on the sweep-order rules (a closed point listed after the open-ended interval it should join, and the OR of closed flags at an equal lower bound); those two failure modes were then added as the `sort_by_lower_only` and `equal_lower_takes_farther_flag` variants, so the trap columns above reflect a re-scoring of the same snapshots. Own tests caught 100% of the other eleven variants and 0% of those two, which is the pattern the eval exists to measure: the agents tested sorted inputs only.
