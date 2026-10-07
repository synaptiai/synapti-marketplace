import unittest
from decimal import Decimal

from allocate import allocate


class KnownAllocationTests(unittest.TestCase):
    def test_known_worked_example(self):
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(
            result, [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")]
        )

    def test_known_tie_breaks_lowest_index_first(self):
        # total_units = 3, weights [1, 1] -> exact shares 1.5 / 1.5,
        # both remainders tie at 0.5, so index 0 wins the leftover cent.
        result = allocate("0.03", [1, 1])
        self.assertEqual(result, [Decimal("0.02"), Decimal("0.01")])

    def test_known_evenly_divisible_no_leftover(self):
        result = allocate("3.00", [1, 1, 1])
        self.assertEqual(
            result, [Decimal("1.00"), Decimal("1.00"), Decimal("1.00")]
        )

    def test_known_decimal_weights(self):
        # total_units = 1000, weights [0.5, 1.5] -> exact 250 / 750, no leftover
        result = allocate("10.00", [Decimal("0.5"), Decimal("1.5")])
        self.assertEqual(result, [Decimal("2.50"), Decimal("7.50")])


class InvariantTests(unittest.TestCase):
    CASES = [
        ("1.00", [1, 2, 3]),
        ("0.01", [1, 1, 1]),
        ("100.00", [1, 1, 1]),
        ("9.99", [7, 3, 5, 1]),
        ("50.00", [1]),
        ("0.00", [1, 2, 3]),
        ("123.45", [10, 20, 7, 3]),
    ]

    def test_invariant_sum_matches_amount(self):
        for amount, weights in self.CASES:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(sum(result), Decimal(amount))

    def test_invariant_result_order_matches_weights(self):
        for amount, weights in self.CASES:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(len(result), len(weights))

    def test_invariant_no_negative_shares(self):
        for amount, weights in self.CASES:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                for share in result:
                    self.assertGreaterEqual(share, Decimal("0"))

    def test_invariant_larger_weight_gets_at_least_as_much(self):
        result = allocate("10.00", [1, 3])
        self.assertLessEqual(result[0], result[1])


class PlacesTests(unittest.TestCase):
    def test_places_zero_whole_units(self):
        result = allocate(10, [1, 2, 3], places=0)
        self.assertEqual(result, [Decimal("2"), Decimal("3"), Decimal("5")])
        self.assertEqual(sum(result), Decimal(10))

    def test_places_three_decimal_digits(self):
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(
            result, [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")]
        )
        self.assertEqual(sum(result), Decimal("1.000"))

    def test_places_negative_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places=-1)

    def test_places_non_int_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places="2")


class RejectInvalidInputTests(unittest.TestCase):
    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, -2])

    def test_reject_float_weight(self):
        with self.assertRaises(TypeError):
            allocate("1.00", [1, 2.5])

    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 2])

    def test_reject_excess_precision_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.005", [1, 2])

    def test_reject_float_amount(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 2])


if __name__ == "__main__":
    unittest.main()
