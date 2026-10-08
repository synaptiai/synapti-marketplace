"""Tests for allocate.py (largest-remainder money allocator).

Expected values are sourced per-test in a comment: either the ISSUE.md
worked example, a hand computation following the ISSUE.md algorithm
(steps 1-4), or an independent oracle (see `_oracle_allocate` below) that
re-implements the algorithm from the spec using `Fraction` arithmetic,
kept deliberately separate from allocate.py's `Decimal`-based code path.
"""
import unittest
from decimal import Decimal
from fractions import Fraction

from allocate import allocate


class TestReject(unittest.TestCase):
    """Bad inputs are rejected with the documented exception types."""

    # -- amount: float -> TypeError --
    def test_reject_float_amount_raises_type_error(self):
        with self.assertRaises(TypeError):
            allocate(1.0, [1, 1])

    # -- amount: negative -> ValueError --
    def test_reject_negative_amount_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(-1, [1, 1])

    # -- amount: excess fractional precision for places=2 -> ValueError --
    def test_reject_excess_precision_amount_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate("1.001", [1, 1], places=2)

    # -- weights: empty sequence -> ValueError --
    def test_reject_empty_weights_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(1, [])

    # -- weights: zero weight -> ValueError --
    def test_reject_zero_weight_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(1, [1, 0])

    # -- weights: negative weight -> ValueError --
    def test_reject_negative_weight_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(1, [1, -1])

    # -- weights: float entry -> TypeError --
    def test_reject_float_weight_raises_type_error(self):
        with self.assertRaises(TypeError):
            allocate(1, [1.0, 2])

    # -- risk map row: per-element weight validation must check every
    # element, not just the first (or an incorrect boolean reduction that
    # treats the whole list as truthy/falsy). A wrong implementation that
    # only validates weights[0] would accept this list even though the
    # third weight is 0. Source: .decisions/issue-1.md risk map row 4,
    # hand-verified against ISSUE.md input contract.
    def test_reject_zero_weight_in_later_position_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(1, [1, 1, 0], places=0)

    # -- places: negative -> ValueError --
    def test_reject_negative_places_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(1, [1, 1], places=-1)

    # -- places: non-int -> ValueError (spec: "places: int >= 0, else
    # ValueError", so a non-int places value is also a ValueError, not a
    # TypeError) --
    def test_reject_non_int_places_raises_value_error(self):
        with self.assertRaises(ValueError):
            allocate(1, [1, 1], places=2.0)


class TestKnown(unittest.TestCase):
    """Hand-derived allocations, including the worked example and ties."""

    # Source: ISSUE.md "Worked example". exact shares in cents are
    # 16.66.., 33.33.., 50; floors 16, 33, 50 (sum 99); the single leftover
    # cent goes to index 0 (largest remainder, .66..).
    def test_known_worked_example_from_issue(self):
        self.assertEqual(
            allocate("1.00", [1, 2, 3]),
            [Decimal("0.17"), Decimal("0.33"), Decimal("0.50")],
        )

    # Source: .decisions/issue-1.md risk map row 1 (tie-break order), hand
    # computed per ISSUE.md algorithm: unit=1 (places=0), total_units=1,
    # sum(weights)=2, exact_i = 1*1/2 = 0.5 for both entries, floor=0 for
    # both (sum 0), leftover=1. Both remainders are exactly 0.5 (a tie);
    # ISSUE.md step 3 says ties break lowest-index-first, so index 0 gets
    # the extra unit. A wrong implementation breaking ties by highest
    # index (or an unstable sort) would give [0, 1] instead.
    def test_known_tie_break_breaks_lowest_index_first(self):
        self.assertEqual(
            allocate(1, [1, 1], places=0),
            [Decimal("1"), Decimal("0")],
        )

    # Source: .decisions/issue-1.md risk map row 2 (floor + largest
    # remainder vs independent rounding), hand computed: unit=0.01 (places
    # default 2), total_units=10000, sum(weights)=3, exact_i =
    # 10000/3 = 3333.333... for all three, floor=3333 each (sum 9999),
    # leftover=1. All three remainders tie at .333...; lowest index (0)
    # gets the extra unit: [3334, 3333, 3333] -> [33.34, 33.33, 33.33],
    # summing to exactly 100.00. Independent per-share rounding (round each
    # 33.333... to 33.33 without redistributing the leftover) would instead
    # give [33.33, 33.33, 33.33], summing to 99.99 -- breaking the sum
    # invariant that this method exists to preserve.
    def test_known_floor_and_largest_remainder_not_independent_rounding(self):
        result = allocate("100.00", [1, 1, 1])
        self.assertEqual(
            result,
            [Decimal("33.34"), Decimal("33.33"), Decimal("33.33")],
        )
        self.assertEqual(sum(result), Decimal("100.00"))

    # Source: .decisions/issue-1.md risk map row 3 (fractional-digit
    # counting across int/str/Decimal). amount=5 as a plain int has 0
    # fractional digits, which is <= places=2, so it must be accepted (not
    # crash looking for a "." in str(5)). Hand computed: unit=0.01,
    # total_units=500, sum(weights)=2, exact_i=250 for both (exact, no
    # remainder), leftover=0 -> [2.50, 2.50].
    def test_known_amount_as_plain_int_is_accepted(self):
        self.assertEqual(
            allocate(5, [1, 1], places=2),
            [Decimal("2.50"), Decimal("2.50")],
        )

    # Source: same risk-map row 3, but for the Decimal exponential-notation
    # edge: Decimal("1E+2") is the value 100 with 0 fractional digits, but
    # str(Decimal("1E+2")) == "1E+2" contains no "." -- a wrong
    # implementation that splits str(amount) on "." to count fractional
    # digits would misparse this. Hand computed like amount=100: unit=0.01,
    # total_units=10000, sum(weights)=2, exact_i=5000 each (exact),
    # leftover=0 -> [50.00, 50.00].
    def test_known_amount_as_decimal_exponential_notation_is_accepted(self):
        self.assertEqual(
            allocate(Decimal("1E+2"), [1, 1], places=2),
            [Decimal("50.00"), Decimal("50.00")],
        )

    # Source: same risk-map row 3, amount given as a Decimal built from a
    # string with a fractional part. Hand computed: unit=0.01,
    # total_units=250, sum(weights)=3, exact_i = 250*1/3=83.33.., for
    # weight 1 entries and 250*1/3 for the third too (all equal weights),
    # floor=83 each (sum 249), leftover=1, all remainders tie at .333...,
    # lowest index (0) wins: [84, 83, 83] -> [0.84, 0.83, 0.83].
    def test_known_amount_as_decimal_with_fraction_is_accepted(self):
        self.assertEqual(
            allocate(Decimal("2.50"), [1, 1, 1], places=2),
            [Decimal("0.84"), Decimal("0.83"), Decimal("0.83")],
        )


def _oracle_allocate(amount, weights, places=2):
    """Independent re-derivation of ISSUE.md's algorithm (steps 1-4), using
    plain ``Fraction``/``int`` arithmetic throughout instead of allocate.py's
    ``Decimal`` scaling. This is deliberately a separate code path from
    allocate.py (different types, no shared helper functions) so that the
    invariant tests below are not just allocate() checking its own output.
    """
    unit = Fraction(1, 10 ** places)
    total_units = int(Fraction(amount) / unit)
    total_weight = sum(Fraction(w) for w in weights)
    exact = [Fraction(total_units * Fraction(w)) / total_weight for w in weights]
    floors = [e.numerator // e.denominator for e in exact]  # floor for e >= 0
    remainders = [e - f for e, f in zip(exact, floors)]
    leftover = total_units - sum(floors)
    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    shares = list(floors)
    for i in order[:leftover]:
        shares[i] += 1
    return [Decimal(s) * (Decimal(1).scaleb(-places)) for s in shares]


class TestInvariant(unittest.TestCase):
    """The parts always sum to the amount and come back in weights order."""

    # Structured cases chosen to be order- and value-sensitive: distinct,
    # non-sorted weights (so an implementation that silently reorders by
    # weight size or returns sorted output would be caught), and amounts
    # that force a non-trivial leftover-unit distribution (not all evenly
    # divisible). Expected values come from `_oracle_allocate`, an
    # independent re-derivation of the ISSUE.md algorithm (see its
    # docstring), not from calling allocate() and recording the result.
    STRUCTURED_CASES = [
        ("100.00", [5, 1, 3], 2),       # weights out of order, has leftover
        ("0.10", [3, 1], 2),             # small amount, 2 weights
        ("250.37", [7, 3, 5, 2], 2),     # 4 weights, irregular amount
        ("1.00", [1, 2, 3], 2),          # the ISSUE.md worked example
        ("99.99", [1, 1, 1, 1, 1], 2),   # 5 equal weights, non-trivial carry
        ("10", [2, 7, 1, 1], 0),         # whole-unit allocation
        (7, [1, 1, 1], 0),               # int amount, equal weights
    ]

    def test_invariant_sum_and_order_match_structured_cases(self):
        for amount, weights, places in self.STRUCTURED_CASES:
            with self.subTest(amount=amount, weights=weights, places=places):
                expected = _oracle_allocate(amount, weights, places)
                result = allocate(amount, weights, places=places)
                self.assertEqual(result, expected)
                self.assertEqual(len(result), len(weights))
                self.assertEqual(sum(result), Decimal(amount).quantize(
                    Decimal(1).scaleb(-places)
                ))

    # Discriminating order check: weights given out of magnitude order must
    # produce shares in the SAME order as weights, not sorted by magnitude.
    # Hand computed: unit=0.01, total_units=10000, sum(weights)=9,
    # exact = [10000*5/9, 10000*1/9, 10000*3/9] = [5555.55.., 1111.11..,
    # 3333.33..], floors = [5555, 1111, 3333] (sum 9999), leftover=1,
    # largest remainder is index 0 (.555..) -> [5556, 1111, 3333] ->
    # [55.56, 11.11, 33.33]. A wrong implementation returning shares
    # sorted by weight size would give [55.56, 33.33, 11.11] instead.
    def test_invariant_order_follows_weights_not_magnitude(self):
        result = allocate("100.00", [5, 1, 3])
        self.assertEqual(
            result,
            [Decimal("55.56"), Decimal("11.11"), Decimal("33.33")],
        )


class TestPlaces(unittest.TestCase):
    """``places`` other than the default 2 (0 and 3) are honoured."""

    # Source: hand computation per ISSUE.md algorithm with places=0
    # (unit=1). total_units=10, sum(weights)=3, exact_i = 10/3 = 3.333..
    # for each, floor=3 each (sum 9), leftover=1, all remainders tie at
    # .333.., lowest index (0) wins: [4, 3, 3].
    def test_places_zero_whole_units_honoured(self):
        self.assertEqual(
            allocate(10, [1, 1, 1], places=0),
            [Decimal("4"), Decimal("3"), Decimal("3")],
        )

    # Source: hand computation per ISSUE.md algorithm with places=3
    # (unit=0.001). total_units=1000, sum(weights)=6, exact_0=1000*1/6=
    # 166.666.. (floor 166, remainder .666..), exact_1=1000*2/6=333.333..
    # (floor 333, remainder .333..), exact_2=1000*3/6=500.0 exactly (floor
    # 500, remainder 0). floors sum = 166+333+500 = 999, leftover=1;
    # largest remainder is index 0 -> [167, 333, 500] -> [0.167, 0.333,
    # 0.500]. This also discriminates a hardcoded-places=2 bug: with
    # places=2 the quantized result would show only 2 decimal digits.
    def test_places_three_thousandths_honoured(self):
        result = allocate("1.000", [1, 2, 3], places=3)
        self.assertEqual(
            result,
            [Decimal("0.167"), Decimal("0.333"), Decimal("0.500")],
        )
        for share in result:
            self.assertEqual(share.as_tuple().exponent, -3)


if __name__ == "__main__":
    unittest.main()
