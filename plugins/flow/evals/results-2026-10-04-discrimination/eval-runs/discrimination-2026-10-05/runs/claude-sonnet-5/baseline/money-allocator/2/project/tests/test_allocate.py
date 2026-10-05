import unittest
from decimal import Decimal

from allocate import allocate


class KnownAllocationTests(unittest.TestCase):
    def test_known_worked_example(self):
        self.assertEqual(
            allocate("1.00", [1, 2, 3]),
            [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")],
        )

    def test_known_equal_weights_with_leftover(self):
        # 100.00 split three ways: floors 33.33 x3 = 99.99, one cent leftover
        # goes to index 0 (lowest index on tie).
        self.assertEqual(
            allocate("100.00", [1, 1, 1]),
            [Decimal("33.34"), Decimal("33.33"), Decimal("33.33")],
        )

    def test_known_exact_split_no_leftover(self):
        self.assertEqual(
            allocate("100.00", [1, 1]),
            [Decimal("50.00"), Decimal("50.00")],
        )

    def test_known_tie_breaks_by_lowest_index(self):
        # 0.03 split across 3 equal weights: exact shares all 1/3 unit with
        # equal remainders -> all three leftover units handed out in index
        # order (0, 1, 2) since leftover == len(weights) - 0... use a case
        # with leftover < len(weights) and tied remainders.
        # 0.02 across 4 equal weights: exact = 0.5 unit each, floors all 0,
        # leftover = 2, remainders all tied at .5 -> indices 0 and 1 win.
        self.assertEqual(
            allocate("0.02", [1, 1, 1, 1]),
            [Decimal("0.01"), Decimal("0.01"), Decimal("0.00"), Decimal("0.00")],
        )

    def test_known_zero_amount(self):
        self.assertEqual(
            allocate("0.00", [1, 2, 3]),
            [Decimal("0.00"), Decimal("0.00"), Decimal("0.00")],
        )

    def test_known_decimal_weights(self):
        # weights 0.5 and 1.5 (ratio 1:3) over 100.00
        self.assertEqual(
            allocate("100.00", [Decimal("0.5"), Decimal("1.5")]),
            [Decimal("25.00"), Decimal("75.00")],
        )

    def test_known_int_amount(self):
        self.assertEqual(
            allocate(1, [1, 1, 1]),
            [Decimal("0.34"), Decimal("0.33"), Decimal("0.33")],
        )


class InvariantTests(unittest.TestCase):
    def test_invariant_sum_equals_amount_many_cases(self):
        cases = [
            ("1.00", [1, 2, 3]),
            ("100.00", [1, 1, 1]),
            ("0.01", [1, 1, 1, 1, 1, 1, 1]),
            ("9999.99", [7, 13, 1, 42, 5]),
            ("50.00", [1]),
            ("0.00", [1, 1]),
            ("123.45", [3, 1, 4, 1, 5, 9, 2, 6]),
        ]
        for amount, weights in cases:
            with self.subTest(amount=amount, weights=weights):
                shares = allocate(amount, weights)
                self.assertEqual(sum(shares), Decimal(amount))

    def test_invariant_order_matches_weights(self):
        shares = allocate("10.00", [5, 1, 1, 1, 1, 1])
        # heaviest weight is first in input order; result must preserve
        # that position, i.e. largest share should be at index 0.
        self.assertEqual(len(shares), 6)
        self.assertEqual(shares.index(max(shares)), 0)

    def test_invariant_length_matches_weights(self):
        shares = allocate("10.00", [1, 2, 3, 4])
        self.assertEqual(len(shares), 4)

    def test_invariant_no_entry_gets_more_than_one_extra_unit(self):
        # leftover must always be < len(weights); check a case with many
        # equal weights and small leftover.
        shares = allocate("1.00", [1] * 7)
        units = [s * 100 for s in shares]
        floor_unit = int(Decimal("100.00") / 7)
        for u in units:
            self.assertLessEqual(u, Decimal(floor_unit) + 1)

    def test_invariant_all_decimal_type(self):
        shares = allocate("10.00", [1, 2, 3])
        for s in shares:
            self.assertIsInstance(s, Decimal)


class PlacesTests(unittest.TestCase):
    def test_places_zero_whole_units(self):
        self.assertEqual(
            allocate("100", [1, 2, 3], places=0),
            [Decimal("17"), Decimal("33"), Decimal("50")],
        )

    def test_places_zero_sum_matches(self):
        shares = allocate("10", [1, 1, 1], places=0)
        self.assertEqual(sum(shares), Decimal("10"))
        self.assertEqual(shares, [Decimal("4"), Decimal("3"), Decimal("3")])

    def test_places_three_decimal_digits(self):
        shares = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(sum(shares), Decimal("1.000"))
        self.assertEqual(
            shares,
            [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")],
        )

    def test_places_three_quantization(self):
        shares = allocate("0.003", [1, 1, 1], places=3)
        for s in shares:
            # quantized to exactly 3 decimal places
            self.assertEqual(-s.as_tuple().exponent, 3)

    def test_places_two_is_default(self):
        self.assertEqual(allocate("1.00", [1, 1]), allocate("1.00", [1, 1], places=2))


class RejectTests(unittest.TestCase):
    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("10.00", [])

    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("10.00", [1, 0])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("10.00", [1, -1])

    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 1])

    def test_reject_excess_precision_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.001", [1, 1])

    def test_reject_float_amount(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 1])

    def test_reject_float_weight(self):
        with self.assertRaises(TypeError):
            allocate("10.00", [1.0, 1])

    def test_reject_negative_places(self):
        with self.assertRaises(ValueError):
            allocate("10.00", [1, 1], places=-1)

    def test_reject_non_int_places(self):
        with self.assertRaises(ValueError):
            allocate("10.00", [1, 1], places=2.0)

    def test_reject_invalid_amount_string(self):
        with self.assertRaises(ValueError):
            allocate("not-a-number", [1, 1])


if __name__ == "__main__":
    unittest.main()
