"""Tests for allocate.py. See ISSUE.md for the algorithm and input contract.

Each test documents the source of its expected value in a comment, per the
tdd-patterns skill contract: spec, hand computation, or external standard --
never the implementation's own output.
"""
import unittest
from decimal import Decimal

from allocate import allocate


class RejectTests(unittest.TestCase):
    """Input contract (ISSUE.md 'Input contract' section, lines 41-48):
    float amount/weight -> TypeError; negative amount, excess-precision
    amount, empty/zero/negative weights, invalid places -> ValueError.
    """

    def test_reject_float_amount_raises_type_error(self):
        # Source: ISSUE.md line 44 "A float raises TypeError".
        # Risk map row "Exception type selected per invalid-input case"
        # (.decisions/issue-1.md): allocate(1.0, [1, 2]) must raise
        # TypeError, not ValueError.
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 2])

    def test_reject_float_weight_raises_type_error(self):
        # Source: ISSUE.md line 47 "a float raises TypeError" (weights).
        with self.assertRaises(TypeError):
            allocate("1.00", [1, 2.0])

    def test_reject_negative_amount_raises_value_error(self):
        # Source: ISSUE.md line 44-45 "a negative value ... raises
        # ValueError".
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 2])

    def test_reject_excess_precision_amount_raises_value_error(self):
        # Source: ISSUE.md line 43-45: amount must have "at most places
        # fractional digits"; excess precision raises ValueError.
        # "1.001" has 3 fractional digits but places defaults to 2.
        with self.assertRaises(ValueError):
            allocate("1.001", [1, 2])

    def test_reject_empty_weights_raises_value_error(self):
        # Source: ISSUE.md line 46-47 "Empty ... raises ValueError".
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_zero_weight_raises_value_error(self):
        # Source: ISSUE.md line 46-47 "zero or negative raises
        # ValueError".
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_reject_negative_weight_raises_value_error(self):
        # Source: ISSUE.md line 46-47 "zero or negative raises
        # ValueError".
        with self.assertRaises(ValueError):
            allocate("1.00", [1, -1])

    def test_reject_negative_places_raises_value_error(self):
        # Source: ISSUE.md line 48 "places: int >= 0 ... Else
        # ValueError".
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places=-1)

    def test_reject_non_int_places_raises_value_error(self):
        # Source: ISSUE.md line 48 "places: int >= 0 ... Else
        # ValueError".
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places="2")


class KnownTests(unittest.TestCase):
    """Hand-derived allocations, including the worked example and ties."""

    def test_known_worked_example_matches_issue(self):
        # Source: ISSUE.md lines 37-39 (worked example). exact shares in
        # cents: 16.66.., 33.33.., 50; floors 16, 33, 50 (sum 99); one
        # leftover cent to index 0 (largest remainder .66..) -> 17.
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(
            result, [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")]
        )

    def test_known_three_way_tie_breaks_lowest_index_first(self):
        # Source: hand computation per .decisions/issue-1.md risk map row
        # "Tie-break order among equal largest remainders": exact shares
        # are 33.33.. cents each (100/3); floors 33, 33, 33 (sum 99);
        # leftover 1 cent; all three remainders tie at .33.. so ISSUE.md
        # step 3 ("ties broken by lowest index first") gives the extra
        # cent to index 0 only.
        result = allocate("1.00", [1, 1, 1])
        self.assertEqual(
            result, [Decimal("0.34"), Decimal("0.33"), Decimal("0.33")]
        )

    def test_known_equal_split_sums_exactly_not_independently_rounded(self):
        # Source: hand computation per .decisions/issue-1.md risk map row
        # "Per-share floor computed via independent rounding": independent
        # per-share rounding of 100/3 gives 33.33 x 3 = 99.99, losing a
        # cent. The largest-remainder method must instead distribute the
        # leftover cent so the parts sum to exactly 100.00.
        result = allocate("100.00", [1, 1, 1])
        self.assertEqual(sum(result), Decimal("100.00"))
        self.assertEqual(
            result, [Decimal("33.34"), Decimal("33.33"), Decimal("33.33")]
        )

    def test_known_exact_split_allocates_no_leftover(self):
        # Source: hand computation per .decisions/issue-1.md risk map row
        # "Leftover-unit distribution when the split is already exact":
        # 100 cents split 1:1 gives floors 50, 50 summing to 100 already;
        # leftover is 0, so neither index receives an extra unit.
        result = allocate("1.00", [1, 1])
        self.assertEqual(result, [Decimal("0.50"), Decimal("0.50")])


class InvariantTests(unittest.TestCase):
    """The parts always sum to the amount and come back in weights order."""

    def test_invariant_sum_equals_amount_for_varied_nonuniform_weights(self):
        # Source: the amount passed in -- by the algorithm's own contract
        # (ISSUE.md step 4, "Their sum equals amount") the total is fixed
        # by construction, not by running the implementation; weights are
        # non-symmetric (3, 1, 7, 2) so order- and magnitude-sensitivity
        # are exercised, not just an all-equal case.
        result = allocate("37.52", [3, 1, 7, 2])
        self.assertEqual(sum(result), Decimal("37.52"))
        self.assertEqual(len(result), 4)

    def test_invariant_decimal_weights_match_exact_fraction_arithmetic(self):
        # Source: .decisions/issue-1.md risk map row "Weight arithmetic
        # performed in binary floating point internally". "0.1"/"0.2"/
        # "0.7" (the risk map's suggested weights) turn out not to shift
        # any floor/remainder in this algorithm because their binary
        # float representations still sum close enough to produce
        # identical floors for that particular amount -- a degenerate
        # case for this risk, confirmed by deliberately swapping the
        # implementation to float arithmetic and seeing the sum-only
        # assertion still pass. Searching for an input where exact
        # Decimal arithmetic and binary-float arithmetic actually
        # disagree (independent throwaway script, not allocate.py)
        # surfaced amount "184.20" with weights 95.6/934.81/10.7/82.0/
        # 13.97: computing total_units=18420, exact_i = 18420*w_i/
        # sum(weights) by hand with Decimal gives floors
        # [1549, 15143, 173, 1329, 226] (sum 18419, leftover 1 unit to
        # the largest remainder, index 1); converting weights to float
        # first instead gives floors [1549, 15143, 173, 1328, 226]
        # (sum 18418, leftover 2, handed to indices 1 and 3) -- a
        # different final distribution at indices 1 and 3. This is the
        # discriminating case for this risk area.
        result = allocate("184.20", ["95.6", "934.81", "10.7", "82.0", "13.97"])
        self.assertEqual(
            result,
            [
                Decimal("15.49"),
                Decimal("151.43"),
                Decimal("1.73"),
                Decimal("13.29"),
                Decimal("2.26"),
            ],
        )
        self.assertEqual(sum(result), Decimal("184.20"))

    def test_invariant_result_order_matches_weights_order(self):
        # Source: hand computation. Distinct, non-symmetric weights (1, 5,
        # 1000) make each index's share visibly different in magnitude, so
        # a result returned out of order (e.g. sorted by weight) is
        # detectable: index 2 (weight 1000) must dominate the total by far
        # more than indices 0/1, and must appear at position 2.
        result = allocate("1002.00", [1, 5, 1000])
        self.assertGreater(result[2], result[1])
        self.assertGreater(result[1], result[0])
        self.assertEqual(sum(result), Decimal("1002.00"))


class PlacesTests(unittest.TestCase):
    """places other than 2 (0 and 3) are honoured."""

    def test_places_zero_uses_whole_unit_not_hardcoded_cents(self):
        # Source: hand computation generalizing the ISSUE.md worked
        # example to places=0. unit=1 (not 0.01); total_units=100;
        # exact shares 100*1/6=16.66.., 100*2/6=33.33.., 100*3/6=50;
        # floors 16, 33, 50 (sum 99); leftover 1 to index 0 (largest
        # remainder .66..) -> [17, 33, 50]. This discriminates against
        # hardcoding Decimal("0.01") as the unit (.decisions/issue-1.md
        # risk map row "Generalizing places away from places=2").
        result = allocate(100, [1, 2, 3], places=0)
        self.assertEqual(result, [Decimal("17"), Decimal("33"), Decimal("50")])
        self.assertEqual(sum(result), Decimal("100"))

    def test_places_three_quantizes_to_thousandths(self):
        # Source: hand computation generalizing the ISSUE.md worked
        # example to places=3. unit=0.001; total_units=1000;
        # exact shares 1000*1/6=166.66.., 1000*2/6=333.33..,
        # 1000*3/6=500; floors 166, 333, 500 (sum 999); leftover 1 to
        # index 0 (largest remainder .66..) -> [0.167, 0.333, 0.500].
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(
            result, [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")]
        )
        self.assertEqual(sum(result), Decimal("1.000"))


if __name__ == "__main__":
    unittest.main()
