import unittest
from decimal import Decimal
from fractions import Fraction

from allocate import allocate


class KnownAllocationTests(unittest.TestCase):
    def test_known_worked_example(self):
        self.assertEqual(
            allocate("1.00", [1, 2, 3]),
            [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")],
        )

    def test_known_equal_split_with_remainder(self):
        # 100.00 split three equal ways: 33.33 x3 loses a cent without
        # largest-remainder; the first index gets the extra cent.
        self.assertEqual(
            allocate("100.00", [1, 1, 1]),
            [Decimal("33.34"), Decimal("33.33"), Decimal("33.33")],
        )

    def test_known_tie_breaks_by_lowest_index(self):
        # Equal weights, amount with remainder -> ties go to lowest index.
        self.assertEqual(
            allocate("1.00", [1, 1, 1, 1]),
            [Decimal("0.25"), Decimal("0.25"), Decimal("0.25"), Decimal("0.25")],
        )
        self.assertEqual(
            allocate("1.01", [1, 1, 1, 1]),
            [Decimal("0.26"), Decimal("0.25"), Decimal("0.25"), Decimal("0.25")],
        )
        self.assertEqual(
            allocate("1.02", [1, 1, 1, 1]),
            [Decimal("0.26"), Decimal("0.26"), Decimal("0.25"), Decimal("0.25")],
        )

    def test_known_zero_amount(self):
        self.assertEqual(
            allocate("0.00", [1, 2, 3]),
            [Decimal("0.00"), Decimal("0.00"), Decimal("0.00")],
        )

    def test_known_single_weight_gets_everything(self):
        self.assertEqual(allocate("5.00", [1]), [Decimal("5.00")])

    def test_known_decimal_and_string_weights(self):
        self.assertEqual(
            allocate("10.00", [Decimal("0.5"), "1.5"]),
            [Decimal("2.50"), Decimal("7.50")],
        )


class InvariantTests(unittest.TestCase):
    def test_invariant_sum_matches_amount_and_order_preserved(self):
        cases = [
            ("1.00", [1, 2, 3]),
            ("0.01", [1, 1, 1]),
            ("100.00", [7, 11, 13, 17]),
            ("9.99", [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]),
            ("50.00", [1]),
            ("123.45", [3, 1, 4, 1, 5, 9, 2, 6]),
        ]
        for amount, weights in cases:
            with self.subTest(amount=amount, weights=weights):
                result = allocate(amount, weights)
                self.assertEqual(len(result), len(weights))
                self.assertEqual(sum(result), Decimal(amount))
                for value in result:
                    self.assertIsInstance(value, Decimal)

    def test_invariant_no_entry_gets_more_than_one_extra_unit(self):
        amount = "10.07"
        weights = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        result = allocate(amount, weights)
        base = Decimal("1.00")
        for value in result:
            self.assertIn(value, (base, base + Decimal("0.01")))

    def test_invariant_matches_fraction_floor_sum(self):
        amount = "77.77"
        weights = [2, 3, 5, 7, 11]
        result = allocate(amount, weights)
        total_units = Fraction(Decimal(amount)) * 100
        total_weight = sum(Fraction(w) for w in weights)
        floors = [
            (Fraction(int(total_units)) * Fraction(w) / total_weight).numerator
            // (Fraction(int(total_units)) * Fraction(w) / total_weight).denominator
            for w in weights
        ]
        for value, floor in zip(result, floors):
            units = int(value * 100)
            self.assertIn(units - floor, (0, 1))


class PlacesTests(unittest.TestCase):
    def test_places_zero_whole_units(self):
        result = allocate(10, [1, 2, 3], places=0)
        self.assertEqual(result, [Decimal("2"), Decimal("3"), Decimal("5")])
        self.assertEqual(sum(result), Decimal(10))

    def test_places_three_decimal_digits(self):
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(sum(result), Decimal("1.000"))
        self.assertEqual(result, [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")])

    def test_places_default_is_two(self):
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(result, allocate("1.00", [1, 2, 3], places=2))

    def test_places_negative_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places=-1)

    def test_places_non_int_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 2], places=2.0)


class RejectBadInputTests(unittest.TestCase):
    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, -1])

    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 2])

    def test_reject_excess_precision_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.005", [1, 2])

    def test_reject_float_amount(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 2])

    def test_reject_float_weight(self):
        with self.assertRaises(TypeError):
            allocate("1.00", [1.0, 2])


if __name__ == "__main__":
    unittest.main()
