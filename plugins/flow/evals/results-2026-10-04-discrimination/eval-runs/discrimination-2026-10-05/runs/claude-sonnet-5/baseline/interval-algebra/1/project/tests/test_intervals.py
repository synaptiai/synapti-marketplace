import unittest
from decimal import Decimal
from fractions import Fraction

from intervals import normalize, union, intersection, difference


class CanonicalFormTests(unittest.TestCase):
    def test_canonical_drops_empty_intervals(self):
        self.assertEqual(normalize([(5, 3)]), [])
        self.assertEqual(normalize([(3, 3, True, False)]), [])
        self.assertEqual(normalize([(3, 3, False, True)]), [])
        self.assertEqual(normalize([(3, 3, False, False)]), [])

    def test_canonical_keeps_closed_point(self):
        self.assertEqual(normalize([(3, 3, True, True)]), [(3, 3, True, True)])

    def test_canonical_sorts_by_lower_bound_with_none_first(self):
        self.assertEqual(
            normalize([(5, 6), (None, 0, False, True), (10, 12)]),
            [(None, 0, False, True), (5, 6, True, True), (10, 12, True, True)],
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
        self.assertEqual(
            result,
            [(1, 4, True, True), (5, 6, True, True)],
        )

    def test_canonical_flags_are_bool(self):
        result = normalize([(1, 2)])
        lo, hi, lo_closed, hi_closed = result[0]
        self.assertIs(lo_closed, True)
        self.assertIs(hi_closed, True)

    def test_canonical_preserves_bound_type(self):
        result = normalize([(Fraction(1, 2), Fraction(3, 2))])
        self.assertEqual(result, [(Fraction(1, 2), Fraction(3, 2), True, True)])
        self.assertIsInstance(result[0][0], Fraction)

        result = normalize([(Decimal("1.5"), Decimal("2.5"))])
        self.assertIsInstance(result[0][0], Decimal)

    def test_canonical_no_touching_leftovers(self):
        # Two intervals that don't actually share or touch stay separate.
        result = normalize([(1, 3, True, False), (3, 5, False, True)])
        self.assertEqual(
            result,
            [(1, 3, True, False), (3, 5, False, True)],
        )


class TouchingMergeTests(unittest.TestCase):
    def test_touching_closed_both_sides_merges(self):
        self.assertEqual(
            normalize([(1, 3), (3, 5)]),
            [(1, 5, True, True)],
        )

    def test_touching_closed_left_open_right_merges(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_open_left_closed_right_merges(self):
        self.assertEqual(
            normalize([(1, 3, True, True), (3, 5, False, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_both_open_does_not_merge(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, False, True)]),
            [(1, 3, True, False), (3, 5, False, True)],
        )

    def test_touching_point_fills_gap(self):
        result = normalize(
            [(1, 3, True, False), (3, 3, True, True), (3, 5, False, True)]
        )
        self.assertEqual(result, [(1, 5, True, True)])

    def test_touching_overlapping_intervals_merge(self):
        self.assertEqual(
            normalize([(1, 4), (2, 6)]),
            [(1, 6, True, True)],
        )

    def test_touching_merge_or_combines_lower_closedness(self):
        # Two intervals starting at the same point: merge keeps it closed
        # if *either* contributing interval was closed there.
        result = normalize([(1, 3, False, True), (1, 5, True, True)])
        self.assertEqual(result, [(1, 5, True, True)])


class IntersectionTests(unittest.TestCase):
    def test_intersect_both_closed_rule(self):
        self.assertEqual(
            intersection([(1, 5, True, True)], [(1, 5, False, False)]),
            [(1, 5, False, False)],
        )
        self.assertEqual(
            intersection([(1, 5, True, False)], [(1, 5, False, True)]),
            [(1, 5, False, False)],
        )

    def test_intersect_touching_closed_ends_yields_point(self):
        self.assertEqual(
            intersection([(1, 3)], [(3, 5)]),
            [(3, 3, True, True)],
        )

    def test_intersect_touching_open_end_is_empty(self):
        self.assertEqual(intersection([(1, 3, True, False)], [(3, 5)]), [])

    def test_intersect_normalizes_inputs(self):
        self.assertEqual(
            intersection([(1, 5)], [(1, 2), (2, 5)]),
            [(1, 5, True, True)],
        )

    def test_intersect_disjoint_is_empty(self):
        self.assertEqual(intersection([(1, 2)], [(3, 4)]), [])

    def test_intersect_unbounded(self):
        self.assertEqual(
            intersection([(None, 5, False, True)], [(0, None, True, False)]),
            [(0, 5, True, True)],
        )

    def test_intersect_is_commutative(self):
        a = [(1, 4, True, False), (6, 9)]
        b = [(2, 7, False, True)]
        self.assertEqual(intersection(a, b), intersection(b, a))


class DifferenceTests(unittest.TestCase):
    def test_difference_opens_cut_ends_closed_subtrahend(self):
        self.assertEqual(
            difference([(1, 5)], [(2, 3)]),
            [(1, 2, True, False), (3, 5, False, True)],
        )

    def test_difference_open_subtrahend_keeps_ends_closed(self):
        self.assertEqual(
            difference([(1, 5)], [(2, 3, False, False)]),
            [(1, 2, True, True), (3, 5, True, True)],
        )

    def test_difference_leaves_single_point(self):
        result = difference(
            [(1, 5)], [(1, 3, True, False), (3, 5, False, True)]
        )
        self.assertEqual(result, [(3, 3, True, True)])

    def test_difference_empty_subtrahend_returns_normalized_minuend(self):
        self.assertEqual(difference([(2, 1), (1, 3)], []), [(1, 3, True, True)])

    def test_difference_unbounded_subtrahend(self):
        self.assertEqual(
            difference([(None, None, False, False)], [(0, 1)]),
            [(None, 0, False, False), (1, None, False, False)],
        )

    def test_difference_full_removal_is_empty(self):
        self.assertEqual(difference([(1, 5)], [(0, 6)]), [])

    def test_difference_no_overlap_is_unchanged(self):
        self.assertEqual(difference([(1, 2)], [(5, 6)]), [(1, 2, True, True)])


class UnboundedAndValidationTests(unittest.TestCase):
    def test_bounds_union_of_touching_unbounded(self):
        self.assertEqual(
            union([(None, 3, False, True)], [(2, None, False, False)]),
            [(None, None, False, False)],
        )

    def test_bounds_fully_unbounded_roundtrip(self):
        self.assertEqual(
            normalize([(None, None, False, False)]),
            [(None, None, False, False)],
        )

    def test_bounds_none_closed_raises(self):
        with self.assertRaises(ValueError):
            normalize([(None, 3, True, True)])
        with self.assertRaises(ValueError):
            normalize([(0, None, False, True)])

    def test_bounds_wrong_arity_raises(self):
        with self.assertRaises(ValueError):
            normalize([(1, 2, 3)])
        with self.assertRaises(ValueError):
            normalize([(1,)])
        with self.assertRaises(ValueError):
            normalize([(1, 2, 3, 4, 5)])

    def test_bounds_non_tuple_raises(self):
        with self.assertRaises(ValueError):
            normalize([[1, 2]])
        with self.assertRaises(ValueError):
            normalize(["not an interval"])

    def test_bounds_non_bool_flag_raises(self):
        with self.assertRaises(ValueError):
            normalize([(1, 2, 1, 1)])

    def test_bounds_non_number_bound_raises(self):
        with self.assertRaises(ValueError):
            normalize([("a", 2, True, True)])

    def test_bounds_difference_unbounded_both_sides(self):
        result = difference(
            [(None, None, False, False)], [(None, 0, False, True)]
        )
        self.assertEqual(result, [(0, None, False, False)])

    def test_bounds_intersection_with_unbounded_input(self):
        self.assertEqual(
            intersection([(None, None, False, False)], [(1, 2)]),
            [(1, 2, True, True)],
        )


if __name__ == "__main__":
    unittest.main()
