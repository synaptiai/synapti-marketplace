"""Tests for allocate.py. See ISSUE.md for the algorithm and acceptance criteria.

Expected values are sourced from ISSUE.md's worked example, the risk map in
.decisions/issue-1.md, ISSUE.md's input contract, or hand computation per the
largest-remainder algorithm -- never from running the implementation. Each
test comment states its source.
"""
import unittest
from decimal import Decimal

from allocate import allocate


class KnownAllocationTests(unittest.TestCase):
    def test_known_worked_example(self):
        # Source: ISSUE.md worked example (lines 37-39).
        # allocate("1.00", [1, 2, 3]): exact shares in cents are
        # 16.66.., 33.33.., 50; floors 16, 33, 50 (sum 99); leftover cent
        # goes to index 0 (largest remainder .66) -> [0.17, 0.33, 0.50].
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(
            result, [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")]
        )

    def test_known_tie_break_lowest_index(self):
        # Source: .decisions/issue-1.md risk map row "remainder tie-break
        # order" (hand-derived). allocate("1.00", [1, 1, 1]): floors
        # 33, 33, 33 (sum 99), leftover 1, all remainders tied at .33 ->
        # lowest index (0) gets the extra cent -> [0.34, 0.33, 0.33].
        # A highest-index-first (or arbitrary stable-sort) implementation
        # would instead produce [0.33, 0.33, 0.34].
        result = allocate("1.00", [1, 1, 1])
        self.assertEqual(
            result, [Decimal("0.34"), Decimal("0.33"), Decimal("0.33")]
        )

    def test_known_tie_break_lowest_index_nonuniform_weights(self):
        # Hand-derived, non-degenerate weights so the tie-break check does
        # not rely on all-identical weights: allocate("1.00", [1, 1, 4]):
        # total_units=100, weight sum=6, exact shares 16.66.., 16.66..,
        # 66.66..; floors 16, 16, 66 (sum 98), leftover 2, all three
        # remainders tied at .66.. -> lowest two indices (0, 1) each get
        # +1 -> [0.17, 0.17, 0.66]. A highest-index-first implementation
        # would instead produce [0.16, 0.17, 0.67] (same sum, different
        # distribution).
        result = allocate("1.00", [1, 1, 4])
        self.assertEqual(
            result, [Decimal("0.17"), Decimal("0.17"), Decimal("0.66")]
        )


class InvariantAllocationTests(unittest.TestCase):
    def test_invariant_leftover_count_exact(self):
        # Source: .decisions/issue-1.md risk map row "leftover unit count"
        # (hand-derived). allocate("10.00", [1]*7): total_units=1000,
        # weight sum=7, exact_i = 1000/7 = 142.857.. each, floor=142 each
        # (sum 994), leftover = 1000 - 994 = 6. Exactly 6 of the 7 entries
        # (lowest indices, since remainders are tied) get +1: indices 0-5
        # -> 1.43, index 6 stays 1.42. An off-by-one implementation that
        # gives +1 to every entry with remainder > 0 would return all 7 as
        # 1.43, summing to 10.01 instead of 10.00.
        result = allocate("10.00", [1, 1, 1, 1, 1, 1, 1])
        expected = [Decimal("1.43")] * 6 + [Decimal("1.42")]
        self.assertEqual(result, expected)
        self.assertEqual(sum(result), Decimal("10.00"))

    def test_invariant_result_order_matches_weights(self):
        # Source: .decisions/issue-1.md risk map row "result ordering"
        # (hand-derived). allocate("1.00", [3, 2, 1]): total_units=100,
        # weight sum=6, exact shares 50, 33.33.., 16.66..; floors
        # 50, 33, 16 (sum 99), leftover 1 to index 2 (largest remainder
        # .66) -> [0.50, 0.33, 0.17], i.e. in the original weights order,
        # not sorted by remainder (which would put the largest-remainder
        # entry first: [0.17, 0.50, 0.33]).
        result = allocate("1.00", [3, 2, 1])
        self.assertEqual(
            result, [Decimal("0.50"), Decimal("0.33"), Decimal("0.17")]
        )
        self.assertEqual(sum(result), Decimal("1.00"))

    def test_invariant_sum_and_length_varied_weights(self):
        # Property from ISSUE.md step 4: "Their sum equals amount" and the
        # result has one entry per weight, in weights order. Uses a
        # structured set of non-uniform weight vectors (not all-identical,
        # not palindromic) so length- and value-sensitivity are exercised.
        cases = [
            ("5.00", [1, 1, 1, 1, 1, 1]),
            ("7.77", [5, 3, 2, 9, 1]),
            ("100.00", [1]),
            ("0.03", [1, 1, 1]),
        ]
        for amount, weights in cases:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(len(result), len(weights))
                self.assertEqual(sum(result), Decimal(amount))


class PlacesAllocationTests(unittest.TestCase):
    def test_places_zero_honoured(self):
        # Source: .decisions/issue-1.md risk map row "places handling"
        # (hand-derived). allocate(10, [1, 1, 1], places=0): unit=1,
        # total_units=10, floor=3 each (sum 9), leftover=1 to index 0 ->
        # [4, 3, 3], as whole-unit Decimals (no fractional digits). A
        # hardcoded places=2 implementation would return 4.00/3.00/3.00.
        result = allocate(10, [1, 1, 1], places=0)
        self.assertEqual(result, [Decimal("4"), Decimal("3"), Decimal("3")])

    def test_places_three_honoured(self):
        # Hand-derived from the ISSUE.md algorithm with places=3.
        # allocate("1.000", [1, 2], places=3): unit=0.001,
        # total_units=1000, weight sum=3, exact shares 333.33.., 666.66..,
        # floors 333, 666 (sum 999), leftover 1 to index 1 (larger
        # remainder .66..) -> [0.333, 0.667].
        result = allocate("1.000", [1, 2], places=3)
        self.assertEqual(result, [Decimal("0.333"), Decimal("0.667")])


class RejectInvalidInputTests(unittest.TestCase):
    # Source: ISSUE.md "Input contract" section (lines 41-48) and
    # .decisions/issue-1.md "Invalid input" failure mode.

    def test_reject_float_amount_raises_type_error(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 2])

    def test_reject_negative_amount_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 2])

    def test_reject_excess_precision_amount_raises_value_error(self):
        # "1.005" has 3 fractional digits but places defaults to 2.
        with self.assertRaises(ValueError):
            allocate("1.005", [1, 2])

    def test_reject_empty_weights_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_zero_weight_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_reject_negative_weight_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, -1])

    def test_reject_float_weight_raises_type_error(self):
        with self.assertRaises(TypeError):
            allocate("1.00", [1, 2.0])

    def test_reject_negative_places_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places=-1)

    def test_reject_non_int_places_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places="2")


if __name__ == "__main__":
    unittest.main()
