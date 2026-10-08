import unittest
from decimal import Decimal

from allocate import allocate


class TestKnownAllocations(unittest.TestCase):
    def test_known_worked_example(self):
        result = allocate("1.00", [1, 2, 3])
        self.assertEqual(
            result, [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")]
        )

    def test_known_equal_weights_remainder(self):
        # 100 cents / 3 equal weights -> 33.33.. each, one leftover cent.
        result = allocate("1.00", [1, 1, 1])
        self.assertEqual(
            result, [Decimal("0.34"), Decimal("0.33"), Decimal("0.33")]
        )

    def test_known_tie_break_lowest_index(self):
        # 101 cents / 2 equal weights -> 50.5 each, exact tie on remainder;
        # the extra cent must go to index 0.
        result = allocate("1.01", [1, 1])
        self.assertEqual(result, [Decimal("0.51"), Decimal("0.50")])

    def test_known_three_way_tie(self):
        # 10 units / 3 equal weights -> 3.33.. each, tie broken by index.
        result = allocate("10", [1, 1, 1], places=0)
        self.assertEqual(result, [Decimal("4"), Decimal("3"), Decimal("3")])

    def test_known_string_and_decimal_weights(self):
        result = allocate(Decimal("1.00"), ["1", Decimal("2"), 3])
        self.assertEqual(
            result, [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")]
        )


class TestInvariants(unittest.TestCase):
    CASES = [
        ("1.00", [1, 2, 3]),
        ("1.00", [1, 1, 1]),
        ("100.00", [1, 1, 1]),
        ("0.01", [1, 1, 1]),
        ("0.00", [1, 2, 3]),
        ("9999.99", [7, 13, 5, 1, 42]),
        ("1.00", [1]),
        ("50.00", [1, 1]),
    ]

    def test_invariant_sums_to_amount(self):
        for amount, weights in self.CASES:
            with self.subTest(amount=amount, weights=weights):
                shares = allocate(amount, weights)
                self.assertEqual(sum(shares), Decimal(amount))

    def test_invariant_matches_weights_order_and_length(self):
        for amount, weights in self.CASES:
            with self.subTest(amount=amount, weights=weights):
                shares = allocate(amount, weights)
                self.assertEqual(len(shares), len(weights))

    def test_invariant_each_share_within_one_unit_of_exact(self):
        for amount, weights in self.CASES:
            with self.subTest(amount=amount, weights=weights):
                shares = allocate(amount, weights)
                unit = Decimal("0.01")
                total = Decimal(amount)
                total_weight = sum(weights)
                for share, w in zip(shares, weights):
                    exact = total * w / total_weight
                    self.assertLessEqual(abs(share - exact), unit)

    def test_invariant_preserves_order_when_weights_reversed(self):
        amount = "1.00"
        weights = [1, 2, 3]
        forward = allocate(amount, weights)
        backward = allocate(amount, list(reversed(weights)))
        self.assertEqual(backward, list(reversed(forward)))


class TestPlaces(unittest.TestCase):
    def test_places_zero(self):
        result = allocate(100, [1, 2, 3], places=0)
        self.assertEqual(result, [Decimal("17"), Decimal("33"), Decimal("50")])
        self.assertEqual(sum(result), Decimal(100))

    def test_places_three(self):
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(
            result, [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")]
        )
        self.assertEqual(sum(result), Decimal("1.000"))

    def test_places_zero_rejects_fractional_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.50", [1, 1], places=0)

    def test_places_quantization_exponent(self):
        result = allocate("1.000", [1, 1], places=3)
        for share in result:
            self.assertEqual(share.as_tuple().exponent, -3)


class TestRejections(unittest.TestCase):
    def test_reject_empty_weights(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [])

    def test_reject_zero_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [0, 1])

    def test_reject_negative_weight(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [-1, 1])

    def test_reject_negative_amount(self):
        with self.assertRaises(ValueError):
            allocate("-1.00", [1, 1])

    def test_reject_excess_precision_amount(self):
        with self.assertRaises(ValueError):
            allocate("1.001", [1, 1], places=2)

    def test_reject_float_amount(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 1])

    def test_reject_float_weight(self):
        with self.assertRaises(TypeError):
            allocate("1.00", [1.0, 1])

    def test_reject_negative_places(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 1], places=-1)


if __name__ == "__main__":
    unittest.main()
