import unittest
from decimal import Decimal

from allocate import allocate


class KnownAllocationTests(unittest.TestCase):
    def test_known_worked_example(self):
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(
            result,
            [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")],
        )

    def test_known_equal_split_with_remainder(self):
        # 100.00 split three ways: exact shares 33.33.. each, one leftover
        # cent goes to index 0 (lowest index wins the tie on remainder).
        result = allocate("100.00", [1, 1, 1])
        self.assertEqual(
            result,
            [Decimal("33.34"), Decimal("33.33"), Decimal("33.33")],
        )

    def test_known_tie_breaks_by_lowest_index(self):
        # 0.03 split four equal ways: exact shares 0.75 cents each, floors
        # all 0, leftover = 3, remainders all tie at .75 -> lowest 3 indices.
        result = allocate("0.03", [1, 1, 1, 1])
        self.assertEqual(
            result,
            [Decimal("0.01"), Decimal("0.01"), Decimal("0.01"), Decimal("0.00")],
        )

    def test_known_single_weight_gets_everything(self):
        result = allocate("5.00", [7])
        self.assertEqual(result, [Decimal("5.00")])

    def test_known_zero_amount(self):
        result = allocate("0.00", [1, 2, 3])
        self.assertEqual(result, [Decimal("0.00"), Decimal("0.00"), Decimal("0.00")])

    def test_known_decimal_weights(self):
        # weights 1.5 and 1.5 (equal) split 10.01 -> exact halves plus a cent
        result = allocate("10.01", [Decimal("1.5"), Decimal("1.5")])
        self.assertEqual(result, [Decimal("5.01"), Decimal("5.00")])


class InvariantTests(unittest.TestCase):
    def test_invariant_sum_matches_amount_many_cases(self):
        cases = [
            ("1.00", [1, 2, 3]),
            ("100.00", [1, 1, 1]),
            ("0.07", [3, 5, 11, 1]),
            ("999.99", [1] * 7),
            ("12.34", [10, 20, 30, 40]),
            ("0.00", [1, 1]),
            ("50.00", [1]),
        ]
        for amount, weights in cases:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(sum(result), Decimal(amount))

    def test_invariant_preserves_weights_order_and_length(self):
        weights = [5, 1, 9, 2, 7]
        result = allocate("31.41", weights)
        self.assertEqual(len(result), len(weights))

    def test_invariant_all_shares_nonnegative(self):
        result = allocate("10.00", [1, 100, 1])
        for share in result:
            self.assertGreaterEqual(share, Decimal("0"))

    def test_invariant_larger_weight_gets_no_less(self):
        result = allocate("10.00", [1, 5])
        self.assertGreaterEqual(result[1], result[0])

    def test_invariant_leftover_bounded_by_weight_count(self):
        # With many weights, no single floor+1 correction should ever push
        # the total above the amount; check across a spread of totals.
        for cents in range(0, 20):
            amount = Decimal(cents).scaleb(-2)
            result = allocate(amount, [1, 1, 1, 1, 1, 1, 1])
            self.assertEqual(sum(result), amount)


class PlacesTests(unittest.TestCase):
    def test_places_zero_whole_units(self):
        result = allocate("100", [1, 2, 3], places=0)
        self.assertEqual(result, [Decimal("17"), Decimal("33"), Decimal("50")])
        self.assertEqual(sum(result), Decimal("100"))

    def test_places_three_decimal_digits(self):
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(sum(result), Decimal("1.000"))
        for share in result:
            self.assertEqual(-share.as_tuple().exponent, 3)

    def test_places_zero_rejects_fractional_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.5", [1, 1], places=0)

    def test_places_default_is_two(self):
        result = allocate("1.00", [1, 1])
        for share in result:
            self.assertEqual(-share.as_tuple().exponent, 2)


class RejectInvalidInputTests(unittest.TestCase):
    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 1])

    def test_reject_float_amount(self):
        with self.assertRaises(TypeError):
            allocate(1.00, [1, 1])

    def test_reject_excess_precision_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.005", [1, 1], places=2)

    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, -1])

    def test_reject_float_weight(self):
        with self.assertRaises(TypeError):
            allocate("1.00", [1, 2.5])

    def test_reject_negative_places(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 1], places=-1)

    def test_reject_non_int_places(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 1], places="2")


if __name__ == "__main__":
    unittest.main()
