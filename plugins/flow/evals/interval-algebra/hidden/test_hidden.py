"""Hidden reference suite for the interval algebra.

Never shown to the agent. Expected values are hand-derived from the rules in
scaffold/ISSUE.md, then checked against hidden/reference_impl.py. Each test
carries a comment naming the trap it discriminates (see hidden/traps.json
and expected.md).

Run: PYTHONPATH=<project dir> python3 hidden/test_hidden.py -v
"""
import unittest
from decimal import Decimal
from fractions import Fraction

import intervals as iv

T, F = True, False


class Canonical(unittest.TestCase):

    def test_canonical_sorts_by_lower_bound(self):
        # trap: unsorted_output keeps input order
        self.assertEqual(iv.normalize([(5, 6), (1, 2)]), [(1, 2, T, T), (5, 6, T, T)])
        data = [(7, 8), (3, 4), (5, 6), (1, 2)]
        self.assertEqual(iv.normalize(data), [(1, 2, T, T), (3, 4, T, T), (5, 6, T, T), (7, 8, T, T)])
        self.assertEqual(data, [(7, 8), (3, 4), (5, 6), (1, 2)], "input must not be mutated")

    def test_canonical_merges_overlapping(self):
        self.assertEqual(iv.normalize([(1, 4), (3, 6)]), [(1, 6, T, T)])
        self.assertEqual(iv.normalize([(3, 6, F, F), (1, 4, T, F)]), [(1, 6, T, F)])

    def test_canonical_drops_reversed_bounds(self):
        self.assertEqual(iv.normalize([(5, 1)]), [])
        self.assertEqual(iv.normalize([(5, 1, F, F), (2, 3)]), [(2, 3, T, T)])

    def test_canonical_drops_open_points(self):
        # lo == hi is empty unless both ends are closed
        # trap: halfopen_point_kept keeps (2,2] and [2,2)
        self.assertEqual(iv.normalize([(2, 2, T, F), (2, 2, F, T), (2, 2, F, F)]), [])

    def test_canonical_keeps_closed_point(self):
        # trap: point_dropped treats every lo == hi as empty
        self.assertEqual(iv.normalize([(2, 2, T, T)]), [(2, 2, T, T)])
        self.assertEqual(iv.normalize([(4, 4), (1, 2)]), [(1, 2, T, T), (4, 4, T, T)])

    def test_canonical_shorthand_pairs_are_closed(self):
        # trap: shorthand_halfopen reads (1, 3) as [1, 3)
        self.assertEqual(iv.normalize([(1, 3)]), [(1, 3, T, T)])
        self.assertEqual(iv.normalize([(1, 3), (3, 5)]), [(1, 5, T, T)])
        self.assertEqual(iv.normalize([(1, 3), (3, 5, F, T)]), [(1, 5, T, T)])

    def test_canonical_flags_are_bool_and_bounds_keep_type(self):
        # trap: float_endpoints converts bounds; Fraction(1, 3) != 1/3
        out = iv.normalize([(Fraction(1, 3), 1), (1, 2)])
        self.assertEqual(out, [(Fraction(1, 3), 2, T, T)])
        self.assertIsInstance(out[0][0], Fraction)
        self.assertIs(type(out[0][2]), bool)
        self.assertIs(type(out[0][3]), bool)
        out = iv.normalize([(Decimal("0.1"), Decimal("0.3"))])
        self.assertEqual(out, [(Decimal("0.1"), Decimal("0.3"), T, T)])
        self.assertIsInstance(out[0][1], Decimal)

    def test_canonical_worked_example_from_issue(self):
        data = [(5, 6), (1, 3, T, F), (3, 3, T, T), (3, 4, F, T), (4, 4, F, F)]
        self.assertEqual(iv.normalize(data), [(1, 4, T, T), (5, 6, T, T)])

    def test_canonical_merged_upper_end_takes_farther_interval(self):
        # [1,5) contains [2,3]; the upper end stays open
        self.assertEqual(iv.normalize([(1, 5, T, F), (2, 3)]), [(1, 5, T, F)])
        # equal upper bounds: closed if any is closed
        self.assertEqual(iv.normalize([(1, 5, T, F), (2, 5)]), [(1, 5, T, T)])
        # equal lower bounds: closed if any is closed
        self.assertEqual(iv.normalize([(1, 5, F, F), (1, 2)]), [(1, 5, T, F)])


class Touching(unittest.TestCase):

    def test_touching_closed_ends_merge(self):
        # trap: merge_only_overlapping needs hi1 > lo2
        self.assertEqual(iv.normalize([(1, 3, T, T), (3, 5, T, T)]), [(1, 5, T, T)])

    def test_touching_one_closed_end_merges(self):
        self.assertEqual(iv.normalize([(1, 3, T, F), (3, 5, T, T)]), [(1, 5, T, T)])
        self.assertEqual(iv.normalize([(1, 3, T, T), (3, 5, F, T)]), [(1, 5, T, T)])

    def test_touching_open_ends_stay_apart(self):
        # trap: merge_any_touching merges on hi1 == lo2 regardless of flags
        self.assertEqual(iv.normalize([(1, 3, T, F), (3, 5, F, T)]), [(1, 3, T, F), (3, 5, F, T)])
        self.assertEqual(iv.union([(1, 3, T, F)], [(3, 5, F, T)]), [(1, 3, T, F), (3, 5, F, T)])

    def test_touching_point_fills_the_gap(self):
        self.assertEqual(iv.normalize([(1, 3, T, F), (3, 3, T, T), (3, 5, F, T)]), [(1, 5, T, T)])
        self.assertEqual(iv.normalize([(3, 5, F, T), (3, 3, T, T), (1, 3, T, F)]), [(1, 5, T, T)])

    def test_touching_chain_merges_transitively(self):
        # trap: unsorted_output only merges neighbours in input order
        self.assertEqual(iv.normalize([(1, 2), (5, 6), (2, 3, F, T), (3, 5, F, F)]), [(1, 6, T, T)])


class Union(unittest.TestCase):

    def test_union_basic_and_unnormalized_inputs(self):
        self.assertEqual(iv.union([(1, 3)], [(2, 5)]), [(1, 5, T, T)])
        self.assertEqual(iv.union([(4, 6), (1, 2)], [(2, 4, F, F)]), [(1, 6, T, T)])
        self.assertEqual(iv.union([], [(3, 1), (2, 2, T, F)]), [])


class Intersect(unittest.TestCase):

    def test_intersect_equal_endpoints_closed_only_if_both(self):
        # trap: intersection_closed_or
        self.assertEqual(iv.intersection([(1, 5, T, T)], [(1, 5, F, F)]), [(1, 5, F, F)])
        self.assertEqual(iv.intersection([(1, 5, T, F)], [(1, 5, F, T)]), [(1, 5, F, F)])
        self.assertEqual(iv.intersection([(1, 5)], [(1, 5)]), [(1, 5, T, T)])

    def test_intersect_touching_closed_ends_give_point(self):
        # trap: point_dropped
        self.assertEqual(iv.intersection([(1, 3)], [(3, 5)]), [(3, 3, T, T)])

    def test_intersect_touching_open_end_is_empty(self):
        self.assertEqual(iv.intersection([(1, 3, T, F)], [(3, 5)]), [])
        self.assertEqual(iv.intersection([(1, 3)], [(3, 5, F, T)]), [])
        self.assertEqual(iv.intersection([(1, 2)], [(3, 4)]), [])

    def test_intersect_normalizes_inputs(self):
        # trap: intersection_not_normalized returns [1,2] and [2,5] separately
        self.assertEqual(iv.intersection([(1, 5)], [(1, 2), (2, 5)]), [(1, 5, T, T)])
        self.assertEqual(iv.intersection([(2, 5), (1, 2)], [(0, 9)]), [(1, 5, T, T)])
        self.assertEqual(iv.intersection([(6, 9), (1, 4)], [(0, 10)]), [(1, 4, T, T), (6, 9, T, T)])

    def test_intersect_partial_overlap_keeps_inner_flags(self):
        self.assertEqual(iv.intersection([(1, 4, T, F)], [(2, 6, F, T)]), [(2, 4, F, F)])
        self.assertEqual(iv.intersection([(1, 4, F, T)], [(2, 6, T, F)]), [(2, 4, T, T)])


class Difference(unittest.TestCase):

    def test_difference_closed_cut_opens_ends(self):
        # trap: difference_keeps_closedness leaves [1,2] and [3,5]
        self.assertEqual(iv.difference([(1, 5)], [(2, 3)]), [(1, 2, T, F), (3, 5, F, T)])
        self.assertEqual(iv.difference([(0, 10)], [(6, 7, F, F), (2, 3)]),
                         [(0, 2, T, F), (3, 6, F, T), (7, 10, T, T)])

    def test_difference_open_cut_leaves_closed_ends(self):
        self.assertEqual(iv.difference([(1, 5)], [(2, 3, F, F)]), [(1, 2, T, T), (3, 5, T, T)])
        self.assertEqual(iv.difference([(1, 5)], [(2, 3, T, F)]), [(1, 2, T, F), (3, 5, T, T)])

    def test_difference_removes_a_point(self):
        self.assertEqual(iv.difference([(1, 5)], [(3, 3, T, T)]), [(1, 3, T, F), (3, 5, F, T)])
        # an open "point" is empty and removes nothing
        self.assertEqual(iv.difference([(1, 5)], [(3, 3, T, F)]), [(1, 5, T, T)])

    def test_difference_leaves_a_point(self):
        self.assertEqual(iv.difference([(1, 5)], [(1, 3, T, F), (3, 5, F, T)]), [(3, 3, T, T)])

    def test_difference_empty_subtrahend_returns_normalized_a(self):
        self.assertEqual(iv.difference([(3, 4), (1, 2)], []), [(1, 2, T, T), (3, 4, T, T)])

    def test_difference_full_cover_is_empty_and_partial_edges(self):
        self.assertEqual(iv.difference([(1, 3)], [(0, 5)]), [])
        self.assertEqual(iv.difference([(1, 3)], [(1, 3, F, T)]), [(1, 1, T, T)])
        self.assertEqual(iv.difference([(1, 3)], [(1, 3, T, F)]), [(3, 3, T, T)])


class Bounds(unittest.TestCase):

    def test_bounds_unbounded_merge_and_sort(self):
        self.assertEqual(iv.normalize([(None, 3, F, T), (2, None, F, F)]), [(None, None, F, F)])
        self.assertEqual(iv.normalize([(4, 5), (None, 1, F, F)]), [(None, 1, F, F), (4, 5, T, T)])

    def test_bounds_unbounded_in_intersection_and_difference(self):
        self.assertEqual(iv.intersection([(None, None, F, F)], [(1, 2)]), [(1, 2, T, T)])
        self.assertEqual(iv.intersection([(None, 5, F, F)], [(3, None, F, F)]), [(3, 5, F, F)])
        self.assertEqual(iv.difference([(1, 5)], [(3, None, F, F)]), [(1, 3, T, T)])
        self.assertEqual(iv.difference([(None, None, F, F)], [(0, 1)]), [(None, 0, F, F), (1, None, F, F)])

    def test_bounds_unbounded_closed_rejected(self):
        # trap: no_validation
        for bad in ((None, 3, T, T), (None, 3, T, F), (3, None, F, T), (None, 3)):
            with self.assertRaises(ValueError, msg=repr(bad)):
                iv.normalize([bad])

    def test_bounds_malformed_rejected(self):
        for bad in ((1, 2, 3), (1, 2, 3, 4, 5), (1, 2, 1, 0), (1, 2, T, "yes"), ("a", 2), (1, None, F, F, F)):
            with self.assertRaises(ValueError, msg=repr(bad)):
                iv.normalize([bad])
        with self.assertRaises(ValueError):
            iv.union([(1, 2)], [(1, 2, T)])


if __name__ == "__main__":
    unittest.main()
