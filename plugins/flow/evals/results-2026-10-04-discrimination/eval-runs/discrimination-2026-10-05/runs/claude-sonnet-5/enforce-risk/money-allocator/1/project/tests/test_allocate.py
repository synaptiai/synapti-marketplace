"""Tests for allocate.allocate(). See ISSUE.md for the algorithm/contract
and .decisions/issue-1.md for the specification (non-goals, failure modes,
interface contracts, risk map) these tests are derived from.
"""
import unittest
from decimal import Decimal

from allocate import allocate


class TestAllocateKnown(unittest.TestCase):
    """Hand-derived allocations, including the worked example and ties.

    Each expected value is computed by hand from the largest-remainder
    algorithm in ISSUE.md (floor the exact share, then hand out the
    `leftover` units to the largest fractional remainders, lowest index
    first on ties); the risk-map-driven cases are cross-checked against
    .decisions/issue-1.md "Risk map".
    """

    def test_known_worked_example(self):
        # ISSUE.md worked example: total_units=100, weights sum=6.
        # exact shares 16.66.., 33.33.., 50 -> floors 16,33,50 (99) ->
        # leftover 1 cent goes to index 0 (largest remainder .66..).
        self.assertEqual(
            allocate("1.00", [1, 2, 3]),
            [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")],
        )

    def test_known_tie_break_lowest_index_first(self):
        # .decisions/issue-1.md risk map row "leftover tie-break order":
        # total_units=100, weights sum=3, exact=33.33.. each, floors 33
        # each (99), leftover 1, all three remainders tied -> lowest index
        # (0) gets the extra cent, not the highest.
        self.assertEqual(
            allocate("1.00", [1, 1, 1]),
            [Decimal("0.34"), Decimal("0.33"), Decimal("0.33")],
        )

    def test_known_exact_vs_float_arithmetic_trap(self):
        # .decisions/issue-1.md risk map row "exact vs. float arithmetic".
        # Hand-verified this input actually discriminates (many small
        # integer total_units/weight combos round-trip cleanly through
        # float64 and do NOT expose the bug): converting "0.29" to a float
        # cents count the naive way is where real implementations trip --
        # float(Decimal("0.29")) / 0.01 == 28.999999999999996 in IEEE-754
        # double precision, so int()-truncating that naive float division
        # gives total_units=28 instead of 29, silently losing a cent before
        # the largest-remainder split even starts. Exact (Decimal/Fraction)
        # arithmetic must get total_units=29.
        # total_units=29, weights sum=2: exact shares 14.5, 14.5 -> floors
        # 14, 14 (28), leftover 1, remainders tied -> lowest index (0)
        # gets the extra cent.
        self.assertEqual(
            allocate("0.29", [1, 1]),
            [Decimal("0.15"), Decimal("0.14")],
        )

    def test_known_largest_remainder_vs_naive_independent_rounding(self):
        # .decisions/issue-1.md risk map row "independent per-weight
        # rounding vs. largest-remainder": total_units=1000, weights sum=3,
        # exact=333.33.. each, floors 333 each (999), leftover 1 -> index 0
        # gets the extra cent: [3.34, 3.33, 3.33], summing to 10.00. Naive
        # independent rounding of 333.33.. to the nearest cent would give
        # 333 each, summing to 9.99 (fails to sum to amount).
        result = allocate("10.00", [1, 1, 1])
        self.assertEqual(
            result,
            [Decimal("3.34"), Decimal("3.33"), Decimal("3.33")],
        )
        self.assertEqual(sum(result), Decimal("10.00"))

    def test_known_leftover_distribution_cap(self):
        # .decisions/issue-1.md risk map row "leftover distribution cap":
        # total_units=100, 7 equal weights, exact=100/7=14.2857.. each,
        # floors 14 each (98), leftover 2 -> the two lowest-index entries
        # (0 and 1) each get exactly one extra unit, never both units to a
        # single entry.
        self.assertEqual(
            allocate("1.00", [1, 1, 1, 1, 1, 1, 1]),
            [
                Decimal("0.15"),
                Decimal("0.15"),
                Decimal("0.14"),
                Decimal("0.14"),
                Decimal("0.14"),
                Decimal("0.14"),
                Decimal("0.14"),
            ],
        )


class TestAllocatePlaces(unittest.TestCase):
    """``places`` other than the default 2 (0 and 3) are honoured.

    Expected values hand-derived the same way as the worked example in
    ISSUE.md, just with unit = 10**-places instead of 10**-2, using
    non-degenerate weights [1, 2, 3] so an implementation that silently
    hardcodes places=2 or quantizes to the wrong exponent is caught.
    """

    def test_places_zero_whole_units(self):
        # places=0: unit=1, total_units=100 (same magnitude as the ISSUE.md
        # worked example). exact shares 16.66.., 33.33.., 50 -> floors
        # 16,33,50 (99), leftover 1 -> index 0 gets the extra unit: 17,33,50.
        self.assertEqual(
            allocate(100, [1, 2, 3], places=0),
            [Decimal("17"), Decimal("33"), Decimal("50")],
        )

    def test_places_three_thousandths(self):
        # places=3: unit=0.001, total_units=1000. exact shares 166.66..,
        # 333.33.., 500 -> floors 166,333,500 (999), leftover 1 -> index 0
        # gets the extra unit: 167,333,500 thousandths.
        self.assertEqual(
            allocate("1.000", [1, 2, 3], places=3),
            [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")],
        )


class TestAllocateInvariant(unittest.TestCase):
    """The parts always sum to the amount and come back in weights order."""

    def test_invariant_order_matches_weights_not_weight_magnitude(self):
        # Hand-derived, non-symmetric weights so an implementation that
        # (incorrectly) sorts its output by weight magnitude is caught:
        # the largest weight (10) is at index 1, not index 0.
        # total_units=100, weight_sum=16. exact_0=100*1/16=6.25 (floor 6,
        # rem .25); exact_1=100*10/16=62.5 (floor 62, rem .5); exact_2=
        # 100*5/16=31.25 (floor 31, rem .25). floors sum=99, leftover=1,
        # largest remainder is index 1 (.5) -> gets the extra cent: 63.
        # Correct order keeps the small share first: [0.06, 0.63, 0.31].
        # A buggy sort-by-weight-descending implementation would instead
        # produce [0.63, 0.31, 0.06].
        self.assertEqual(
            allocate("1.00", [1, 10, 5]),
            [Decimal("0.06"), Decimal("0.63"), Decimal("0.31")],
        )

    def test_invariant_sum_equals_amount_across_cases(self):
        # Source of the expected sum: the function's own documented
        # contract (ISSUE.md step 4, "Their sum equals amount") applied to
        # each case's input amount -- not derived from running allocate()
        # itself. Weights are varied and non-degenerate (distinct values,
        # different counts) so this isn't exercising a single code path.
        cases = [
            ("123.45", [7, 13, 2, 9, 1]),
            ("0.01", [3, 1, 4, 1, 5, 9, 2, 6]),
            ("999.99", [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]),
            ("50.00", [1]),
            ("0.00", [1, 1, 1]),
            ("7.77", ["2.5", "1.5", 4]),
        ]
        for amount, weights in cases:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(len(result), len(weights))
                self.assertEqual(sum(result), Decimal(amount))


class TestAllocateReject(unittest.TestCase):
    """Bad inputs are rejected with the documented exception types.

    Source of expected exception types: ISSUE.md "Input contract" section /
    .decisions/issue-1.md "Interface contracts".
    """

    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [0, 1])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [-1, 1])

    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 1])

    def test_reject_excess_precision(self):
        # places=2 (default) but amount carries 3 fractional digits.
        with self.assertRaises(ValueError):
            allocate("1.001", [1, 1])

    def test_reject_float_amount(self):
        with self.assertRaises(TypeError):
            allocate(1.00, [1, 1])

    def test_reject_float_weight(self):
        with self.assertRaises(TypeError):
            allocate("1.00", [1.0, 1])

    def test_reject_negative_places(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 1], places=-1)


if __name__ == "__main__":
    unittest.main()
