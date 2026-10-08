import unittest
from decimal import Decimal
from fractions import Fraction

from intervals import normalize, union, intersection, difference


class CanonicalFormTests(unittest.TestCase):
    def test_canonical_drops_empty_intervals(self):
        self.assertEqual(normalize([(5, 3)]), [])
        self.assertEqual(normalize([(3, 3, False, True)]), [])
        self.assertEqual(normalize([(3, 3, True, False)]), [])
        self.assertEqual(normalize([(3, 3, False, False)]), [])

    def test_canonical_keeps_closed_point(self):
        self.assertEqual(normalize([(3, 3, True, True)]), [(3, 3, True, True)])

    def test_canonical_sorts_by_lower_bound_none_first(self):
        self.assertEqual(
            normalize([(10, 12), (None, -5, False, True), (0, 1)]),
            [(None, -5, False, True), (0, 1, True, True), (10, 12, True, True)],
        )

    def test_canonical_accepts_shorthand(self):
        self.assertEqual(normalize([(1, 2)]), [(1, 2, True, True)])

    def test_canonical_flags_are_bool_type(self):
        result = normalize([(1, 2)])
        lo, hi, lo_closed, hi_closed = result[0]
        self.assertIs(lo_closed, True)
        self.assertIs(hi_closed, True)

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

    def test_canonical_preserves_bound_type(self):
        result = normalize([(Fraction(1, 2), Decimal("2.5"))])
        self.assertEqual(result, [(Fraction(1, 2), Decimal("2.5"), True, True)])
        lo, hi, _, _ = result[0]
        self.assertIsInstance(lo, Fraction)
        self.assertIsInstance(hi, Decimal)

    def test_canonical_is_idempotent(self):
        once = normalize([(1, 5), (2, 3)])
        twice = normalize(once)
        self.assertEqual(once, twice)


class TouchingMergeTests(unittest.TestCase):
    def test_touching_closed_both_sides_merge(self):
        self.assertEqual(normalize([(1, 3), (3, 5)]), [(1, 5, True, True)])

    def test_touching_closed_left_open_right_merge(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_closed_right_open_left_merge(self):
        self.assertEqual(
            normalize([(1, 3, True, True), (3, 5, False, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_both_open_do_not_merge(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, False, True)]),
            [(1, 3, True, False), (3, 5, False, True)],
        )

    def test_touching_point_fills_the_gap(self):
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 3, True, True), (3, 5, False, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_point_fills_the_gap_regardless_of_input_order(self):
        # Same three intervals as above but listed with the bridging point last.
        self.assertEqual(
            normalize([(3, 5, False, True), (1, 3, True, False), (3, 3, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_overlap_merges(self):
        self.assertEqual(normalize([(1, 4), (2, 6)]), [(1, 6, True, True)])


class IntersectionTests(unittest.TestCase):
    def test_intersect_both_closed_rule_at_equal_endpoints(self):
        self.assertEqual(
            intersection([(1, 5)], [(1, 5, False, False)]), [(1, 5, False, False)]
        )
        self.assertEqual(
            intersection([(1, 5, True, False)], [(1, 5, False, True)]),
            [(1, 5, False, False)],
        )

    def test_intersect_touching_closed_ends_yield_point(self):
        self.assertEqual(
            intersection([(1, 3)], [(3, 5)]), [(3, 3, True, True)]
        )

    def test_intersect_touching_open_end_is_empty(self):
        self.assertEqual(intersection([(1, 3, True, False)], [(3, 5)]), [])

    def test_intersect_normalizes_inputs(self):
        self.assertEqual(
            intersection([(1, 5)], [(1, 2), (2, 5)]), [(1, 5, True, True)]
        )

    def test_intersect_disjoint_is_empty(self):
        self.assertEqual(intersection([(1, 2)], [(3, 4)]), [])

    def test_intersect_multiple_pieces(self):
        self.assertEqual(
            intersection([(0, 10)], [(1, 2), (4, 5), (12, 13)]),
            [(1, 2, True, True), (4, 5, True, True)],
        )


class DifferenceTests(unittest.TestCase):
    def test_difference_closed_subtrahend_opens_cut(self):
        self.assertEqual(
            difference([(1, 5)], [(2, 3)]),
            [(1, 2, True, False), (3, 5, False, True)],
        )

    def test_difference_open_subtrahend_leaves_closed_cut(self):
        self.assertEqual(
            difference([(1, 5)], [(2, 3, False, False)]),
            [(1, 2, True, True), (3, 5, True, True)],
        )

    def test_difference_leaves_a_point(self):
        self.assertEqual(
            difference([(1, 5)], [(1, 3, True, False), (3, 5, False, True)]),
            [(3, 3, True, True)],
        )

    def test_difference_with_empty_list_returns_normalized_a(self):
        self.assertEqual(difference([(5, 6), (1, 3)], []), normalize([(5, 6), (1, 3)]))

    def test_difference_removing_everything_is_empty(self):
        self.assertEqual(difference([(1, 5)], [(0, 10)]), [])

    def test_difference_disjoint_subtrahend_is_unchanged(self):
        self.assertEqual(difference([(1, 5)], [(10, 20)]), [(1, 5, True, True)])


class UnboundedAndValidationTests(unittest.TestCase):
    def test_bounds_union_of_half_lines_is_everything(self):
        self.assertEqual(
            union([(None, 3, False, True)], [(2, None, False, False)]),
            [(None, None, False, False)],
        )

    def test_bounds_difference_punches_hole_in_everything(self):
        self.assertEqual(
            difference([(None, None, False, False)], [(0, 1)]),
            [(None, 0, False, False), (1, None, False, False)],
        )

    def test_bounds_intersection_with_unbounded(self):
        self.assertEqual(
            intersection([(None, None, False, False)], [(1, 5)]),
            [(1, 5, True, True)],
        )

    def test_bounds_none_closed_raises_value_error(self):
        with self.assertRaises(ValueError):
            normalize([(None, 3, True, True)])
        with self.assertRaises(ValueError):
            normalize([(0, None, False, True)])

    def test_bounds_wrong_length_tuple_raises_value_error(self):
        with self.assertRaises(ValueError):
            normalize([(1, 2, 3)])
        with self.assertRaises(ValueError):
            normalize([(1,)])

    def test_bounds_non_tuple_raises_value_error(self):
        with self.assertRaises(ValueError):
            normalize([[1, 2]])

    def test_bounds_non_bool_flag_raises_value_error(self):
        with self.assertRaises(ValueError):
            normalize([(1, 2, 1, True)])

    def test_bounds_non_number_bound_raises_value_error(self):
        with self.assertRaises(ValueError):
            normalize([("a", 2, True, True)])

    def test_bounds_unbounded_both_sides_is_valid(self):
        self.assertEqual(normalize([(None, None, False, False)]), [(None, None, False, False)])


if __name__ == "__main__":
    unittest.main()
