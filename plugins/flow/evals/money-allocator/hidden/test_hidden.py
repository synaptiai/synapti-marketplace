"""Hidden reference suite for the largest-remainder money allocator.

Never shown to the agent. Expected values are hand-derived from the spec in
scaffold/ISSUE.md (exact shares, floors, remainders written out in comments)
and checked against hidden/reference_impl.py. Comments name the trap each
test discriminates (see hidden/traps.json and expected.md).

Run: PYTHONPATH=<project dir> python3 hidden/test_hidden.py -v
"""
import unittest
from decimal import Decimal

from allocate import allocate


def D(*xs):
    return [Decimal(x) for x in xs]


class KnownAnswers(unittest.TestCase):

    def test_equal_weights_extra_cent_goes_to_first(self):
        # 100.00 / 3 = 33.333.. each -> floors 33.33 x3 = 99.99, leftover 0.01 -> index 0
        # trap: round-half-up gives 33.33 x3 (sum 99.99); ties-last-first gives it to index 2
        self.assertEqual(allocate("100.00", [1, 1, 1]), D("33.34", "33.33", "33.33"))

    def test_asymmetric_weights_known_answer(self):
        # 1.00 * [1,2,3]/6 = 0.1666.., 0.3333.., 0.5 -> floors 0.16, 0.33, 0.50 (0.99)
        # remainders .66, .33, 0 -> leftover 0.01 to index 0
        self.assertEqual(allocate("1.00", [1, 2, 3]), D("0.17", "0.33", "0.50"))

    def test_tie_goes_to_lowest_index(self):
        # 0.10 / 3 = 0.0333.. -> floors 0.03 x3 (0.09), leftover 0.01, all remainders equal -> index 0
        self.assertEqual(allocate("0.10", [1, 1, 1]), D("0.04", "0.03", "0.03"))

    def test_two_leftover_units_go_to_first_two_on_full_tie(self):
        # 0.05 / 3 = 0.01666.. -> floors 0.01 x3 (0.03), leftover 0.02 -> indexes 0 and 1
        self.assertEqual(allocate("0.05", [1, 1, 1]), D("0.02", "0.02", "0.01"))

    def test_tie_between_different_weights_goes_to_lowest_index(self):
        # 0.10 * [1,3]/4 = 0.025, 0.075 -> floors 0.02, 0.07; remainders .5, .5 -> index 0
        # trap: ties-by-weight gives the cent to the heavier index 1 -> 0.02, 0.08
        self.assertEqual(allocate("0.10", [1, 3]), D("0.03", "0.07"))

    def test_half_remainders_are_not_all_rounded_up(self):
        # 0.01 * [1,1]/2 = 0.005 each -> floors 0.00, 0.00; one leftover cent -> index 0
        # trap: round-half-up yields 0.01 + 0.01 = 0.02 (sum invariant broken)
        self.assertEqual(allocate("0.01", [1, 1]), D("0.01", "0.00"))

    def test_symmetric_weights_asymmetric_result(self):
        # 0.10 * [1,2,1]/4 = 0.025, 0.05, 0.025 -> floors 0.02, 0.05, 0.02 (0.09)
        # remainders .5, 0, .5 -> leftover cent to index 0 (tie with index 2)
        self.assertEqual(allocate("0.10", [1, 2, 1]), D("0.03", "0.05", "0.02"))

    def test_multiply_before_divide(self):
        # 0.13 * [2,3]/5 = 0.052, 0.078 -> floors 0.05, 0.07 (0.12); remainders .2, .8 -> index 1
        # trap: divide-first computes floor(13/5) = 2 units per weight unit -> 0.04, 0.06 and
        # then hands the 0.03 shortfall out round-robin -> 0.06, 0.07
        self.assertEqual(allocate("0.13", [2, 3]), D("0.05", "0.08"))

    def test_output_order_follows_weights_order(self):
        # trap: sorted-output returns shares in descending weight order
        self.assertEqual(allocate("6.00", [1, 3, 2]), D("1.00", "3.00", "2.00"))
        self.assertEqual(allocate("0.10", [1, 3, 2]), D("0.02", "0.05", "0.03"))

    def test_decimal_weights(self):
        self.assertEqual(allocate("1.00", [Decimal("0.5"), Decimal("1.5")]), D("0.25", "0.75"))

    def test_large_amount_is_exact(self):
        # 123456789012345.67 / 2 = 61728394506172.835 -> floors ...83 x2, leftover 0.01 -> index 0
        # trap: float-arithmetic cannot represent 17 significant digits
        self.assertEqual(
            allocate("123456789012345.67", [1, 1]),
            D("61728394506172.84", "61728394506172.83"),
        )


class Invariants(unittest.TestCase):

    def test_sum_equals_amount_for_many_shapes(self):
        cases = [
            ("1.00", [1, 1, 1]), ("0.07", [5, 3, 9, 1]), ("99.99", [7, 11, 13]),
            ("0.10", [1, 3]), ("3.33", [2, 2, 2, 2, 2, 2, 2]), ("1000.01", [1, 999]),
        ]
        for amount, weights in cases:
            result = allocate(amount, weights)
            self.assertEqual(sum(result), Decimal(amount), (amount, weights))
            self.assertEqual(len(result), len(weights))

    def test_no_index_receives_more_than_one_extra_unit(self):
        # 0.09 * [1,1,1,1,1,1,1,1,1,1]/10 = 0.009 each -> floors 0; nine cents to the first nine
        self.assertEqual(allocate("0.09", [1] * 10), D(*(["0.01"] * 9 + ["0.00"])))

    def test_results_are_decimals_quantized_to_places(self):
        result = allocate("1.00", [1, 2])
        for x in result:
            self.assertIsInstance(x, Decimal)
            self.assertEqual(x.as_tuple().exponent, -2)
        self.assertEqual([str(x) for x in result], ["0.33", "0.67"])

    def test_single_weight_gets_everything(self):
        self.assertEqual(allocate("12.34", [5]), D("12.34"))

    def test_zero_amount_gives_zeros(self):
        self.assertEqual(allocate("0.00", [1, 2, 3]), D("0.00", "0.00", "0.00"))

    def test_places_zero_whole_units(self):
        # 10 / 3 = 3.33.. -> floors 3 x3 (9), leftover 1 -> index 0
        # trap: hardcoded-places would return 3.34, 3.33, 3.33
        self.assertEqual(allocate(10, [1, 1, 1], places=0), D("4", "3", "3"))

    def test_places_three(self):
        # 0.010 / 3 = 0.00333.. -> floors 0.003 x3 (0.009), leftover 0.001 -> index 0
        self.assertEqual(allocate("0.010", [1, 1, 1], places=3), D("0.004", "0.003", "0.003"))

    def test_int_and_string_amounts_accepted(self):
        self.assertEqual(allocate(1, [1, 1]), D("0.50", "0.50"))
        self.assertEqual(allocate("2", [1, 1]), D("1.00", "1.00"))


class Rejections(unittest.TestCase):

    def test_zero_weight_rejected(self):
        # trap: accepts-nonpositive-weights returns [1.00, 0.00]
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_negative_weight_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [2, -1])

    def test_empty_weights_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_negative_amount_rejected(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 1])

    def test_amount_with_excess_precision_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.005", [1, 1])
        with self.assertRaises(ValueError):
            allocate("1.5", [1, 1], places=0)

    def test_float_amount_rejected(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
