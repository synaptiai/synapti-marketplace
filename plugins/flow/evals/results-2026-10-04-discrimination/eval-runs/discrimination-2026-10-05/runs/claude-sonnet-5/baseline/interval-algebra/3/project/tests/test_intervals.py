import unittest
from decimal import Decimal
from fractions import Fraction

from intervals import normalize, union, intersection, difference


class CanonicalFormTests(unittest.TestCase):
    def test_canonical_drops_empty_intervals(self):
        self.assertEqual(normalize([(1, 1, True, False)]), [])
        self.assertEqual(normalize([(1, 1, False, True)]), [])
        self.assertEqual(normalize([(1, 1, False, False)]), [])
        self.assertEqual(normalize([(5, 1, True, True)]), [])

    def test_canonical_keeps_closed_points(self):
        self.assertEqual(normalize([(1, 1, True, True)]), [(1, 1, True, True)])

    def test_canonical_sorts_by_lower_bound_with_none_first(self):
        self.assertEqual(
            normalize([(10, 20), (None, 0, False, True), (5, 6)]),
            [(None, 0, False, True), (5, 6, True, True), (10, 20, True, True)],
        )

    def test_canonical_accepts_shorthand(self):
        self.assertEqual(normalize([(1, 2)]), [(1, 2, True, True)])

    def test_canonical_worked_example(self):
        result = normalize(
            [
                (5, 6),
                (1, 3, True, False),
                (3, 3, True, True),
                (3, 4, False, True),
                (4, 4, False, False),
            ]
        )
        self.assertEqual(result, [(1, 4, True, True), (5, 6, True, True)])

    def test_canonical_flags_are_bool(self):
        result = normalize([(1, 2)])
        lo, hi, lo_closed, hi_closed = result[0]
        self.assertIs(lo_closed, True)
        self.assertIs(hi_closed, True)

    def test_canonical_two_equal_sets_compare_equal(self):
        a = normalize([(1, 3), (2, 5)])
        b = normalize([(2, 5), (1, 2, True, False), (2, 3)])
        self.assertEqual(a, b)


class TouchingMergeTests(unittest.TestCase):
    def test_touching_closed_closed_merges(self):
        self.assertEqual(normalize([(1, 3), (3, 5)]), [(1, 5, True, True)])

    def test_touching_open_closed_merges(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_closed_open_merges(self):
        self.assertEqual(
            normalize([(1, 3, True, True), (3, 5, False, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_open_open_does_not_merge(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, False, True)]),
            [(1, 3, True, False), (3, 5, False, True)],
        )

    def test_touching_point_fills_the_gap(self):
        result = normalize(
            [(1, 3, True, False), (3, 3, True, True), (3, 5, False, True)]
        )
        self.assertEqual(result, [(1, 5, True, True)])


class IntersectionTests(unittest.TestCase):
    def test_intersect_both_closed_rule_open_open(self):
        self.assertEqual(
            intersection([(1, 5, True, True)], [(1, 5, False, False)]),
            [(1, 5, False, False)],
        )

    def test_intersect_both_closed_rule_mixed(self):
        self.assertEqual(
            intersection([(1, 5, True, False)], [(1, 5, False, True)]),
            [(1, 5, False, False)],
        )

    def test_intersect_closed_touch_yields_point(self):
        self.assertEqual(
            intersection([(1, 3)], [(3, 5)]),
            [(3, 3, True, True)],
        )

    def test_intersect_open_touch_is_empty(self):
        self.assertEqual(intersection([(1, 3, True, False)], [(3, 5)]), [])

    def test_intersect_normalizes_inputs(self):
        self.assertEqual(
            intersection([(1, 5)], [(1, 2), (2, 5)]),
            [(1, 5, True, True)],
        )


class DifferenceTests(unittest.TestCase):
    def test_difference_opens_cut_with_closed_subtrahend(self):
        self.assertEqual(
            difference([(1, 5)], [(2, 3)]),
            [(1, 2, True, False), (3, 5, False, True)],
        )

    def test_difference_closes_cut_with_open_subtrahend(self):
        self.assertEqual(
            difference([(1, 5)], [(2, 3, False, False)]),
            [(1, 2, True, True), (3, 5, True, True)],
        )

    def test_difference_point_result(self):
        self.assertEqual(
            difference([(1, 5)], [(1, 3, True, False), (3, 5, False, True)]),
            [(3, 3, True, True)],
        )

    def test_difference_empty_subtrahend_returns_normalized_a(self):
        self.assertEqual(difference([(2, 1)], []), [])
        self.assertEqual(difference([(5, 6), (1, 3)], []), [(1, 3, True, True), (5, 6, True, True)])

    def test_difference_unbounded_subtrahend(self):
        self.assertEqual(difference([(None, None, False, False)], [(0, 1)]), [(None, 0, False, False), (1, None, False, False)])


class UnboundedAndValidationTests(unittest.TestCase):
    def test_bounds_unbounded_union(self):
        self.assertEqual(
            union([(None, 3, False, True)], [(2, None, True, False)]),
            [(None, None, False, False)],
        )

    def test_bounds_unbounded_difference(self):
        self.assertEqual(
            difference([(None, None, False, False)], [(0, 1)]),
            [(None, 0, False, False), (1, None, False, False)],
        )

    def test_bounds_preserves_fraction_and_decimal(self):
        self.assertEqual(
            normalize([(Fraction(1, 2), Fraction(3, 2))]),
            [(Fraction(1, 2), Fraction(3, 2), True, True)],
        )
        self.assertEqual(
            normalize([(Decimal("1.5"), Decimal("2.5"))]),
            [(Decimal("1.5"), Decimal("2.5"), True, True)],
        )

    def test_bounds_none_with_closed_flag_raises(self):
        with self.assertRaises(ValueError):
            normalize([(None, 1, True, True)])
        with self.assertRaises(ValueError):
            normalize([(0, None, False, True)])

    def test_bounds_non_bool_flag_raises(self):
        with self.assertRaises(ValueError):
            normalize([(0, 1, 1, True)])

    def test_bounds_non_number_bound_raises(self):
        with self.assertRaises(ValueError):
            normalize([("a", 1, True, True)])

    def test_bounds_wrong_tuple_length_raises(self):
        with self.assertRaises(ValueError):
            normalize([(1, 2, 3)])
        with self.assertRaises(ValueError):
            normalize([(1,)])

    def test_bounds_non_tuple_raises(self):
        with self.assertRaises(ValueError):
            normalize([[1, 2]])


if __name__ == "__main__":
    unittest.main()
