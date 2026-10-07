import unittest
from decimal import Decimal

from allocate import allocate


class KnownAllocationTests(unittest.TestCase):
    def test_known_worked_example(self):
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(result, [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")])

    def test_known_equal_weights_remainder_split(self):
        # 100.00 split three ways: 33.33 x3 = 99.99, one cent leftover.
        # exact shares are all 33.3333..., tied remainders -> lowest index wins.
        result = allocate("100.00", [1, 1, 1])
        self.assertEqual(result, [Decimal("33.34"), Decimal("33.33"), Decimal("33.33")])

    def test_known_tie_break_lowest_index(self):
        # Equal weights across four parties on an amount not divisible by 4:
        # remainders all tie at 0.25 -> leftover units go to lowest indices first.
        result = allocate("10.00", [1, 1, 1, 1])
        self.assertEqual(
            result,
            [Decimal("2.50"), Decimal("2.50"), Decimal("2.50"), Decimal("2.50")],
        )
        result2 = allocate("10.01", [1, 1, 1, 1])
        self.assertEqual(
            result2,
            [Decimal("2.51"), Decimal("2.50"), Decimal("2.50"), Decimal("2.50")],
        )

    def test_known_decimal_weights(self):
        result = allocate("1.00", [Decimal("0.5"), Decimal("1.5")])
        self.assertEqual(result, [Decimal("0.25"), Decimal("0.75")])

    def test_known_single_weight_gets_everything(self):
        result = allocate("5.00", [1])
        self.assertEqual(result, [Decimal("5.00")])

    def test_known_zero_amount(self):
        result = allocate("0.00", [1, 2, 3])
        self.assertEqual(result, [Decimal("0.00"), Decimal("0.00"), Decimal("0.00")])


class InvariantTests(unittest.TestCase):
    def test_invariant_sum_matches_amount_and_order_preserved(self):
        cases = [
            ("1.00", [1, 2, 3]),
            ("100.00", [1, 1, 1]),
            ("99.99", [7, 5, 3, 1]),
            ("0.07", [1, 1, 1, 1, 1, 1, 1]),
            ("1234.56", [10, 20, 7, 3, 1]),
            ("50.00", [1]),
            ("17.77", [1, 1]),
        ]
        for amount, weights in cases:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(len(result), len(weights))
                self.assertEqual(sum(result), Decimal(amount))
                for share in result:
                    self.assertEqual(share, share.quantize(Decimal("0.01")))

    def test_invariant_no_entry_gets_more_than_one_extra_unit(self):
        amount = "10.00"
        weights = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]  # 11 equal weights
        result = allocate(amount, weights)
        unit = Decimal("0.01")
        floor_share = (Decimal(amount) / unit / len(weights)).to_integral_value(
            rounding="ROUND_FLOOR"
        ) * unit
        for share in result:
            self.assertIn(share, (floor_share, floor_share + unit))

    def test_invariant_returns_list_in_weights_order(self):
        result = allocate("1.00", [3, 2, 1])
        reversed_result = allocate("1.00", [1, 2, 3])
        self.assertEqual(result, list(reversed(reversed_result)))


class PlacesTests(unittest.TestCase):
    def test_places_zero_whole_units(self):
        result = allocate(10, [1, 2, 3], places=0)
        self.assertEqual(result, [Decimal("2"), Decimal("3"), Decimal("5")])
        self.assertEqual(sum(result), Decimal(10))

    def test_places_three_decimal_digits(self):
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(sum(result), Decimal("1.000"))
        for share in result:
            self.assertEqual(share.as_tuple().exponent, -3)

    def test_places_three_matches_expected_split(self):
        result = allocate("1.000", [1, 1, 1], places=3)
        self.assertEqual(result, [Decimal("0.334"), Decimal("0.333"), Decimal("0.333")])

    def test_places_zero_rejects_fractional_amount(self):
        with self.assertRaises(ValueError):
            allocate("10.5", [1, 1], places=0)


class RejectInvalidInputTests(unittest.TestCase):
    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, -1])

    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 1])

    def test_reject_excess_precision_amount(self):
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
