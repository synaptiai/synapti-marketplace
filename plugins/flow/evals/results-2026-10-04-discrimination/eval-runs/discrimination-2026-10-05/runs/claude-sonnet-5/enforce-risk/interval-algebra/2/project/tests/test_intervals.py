"""Tests for intervals.py. See ISSUE.md for the spec these are derived from.

Expected values in each test are hand-derived from the rules in ISSUE.md
(the "Representation"/"Rules" sections and the worked example), not from
running the implementation. Each test name carries the acceptance-criterion
keyword (canonical / touching / intersect / difference / bounds) named in
ISSUE.md so that `python3 -m unittest tests.test_intervals -k <keyword>`
selects exactly the tests for that criterion.
"""
import unittest

from intervals import normalize, union, intersection, difference


class NormalizeCanonicalTests(unittest.TestCase):
    """ISSUE.md rules 1, 3, 4. The worked example (rule 2 merge + rule 1/3/4
    combined) is added alongside the touching-merge behavior below, since it
    requires touch-merge logic; it still carries 'canonical' in its name
    per the acceptance criterion for -k canonical."""

    def test_canonical_shorthand_becomes_closed_interval(self):
        # Source: ISSUE.md Representation "Shorthand" rule.
        result = normalize([(1, 2)])
        self.assertEqual(result, [(1, 2, True, True)])

    def test_canonical_drops_empty_when_lo_greater_than_hi(self):
        # Source: ISSUE.md rule 1: "lo > hi is empty."
        result = normalize([(5, 1, True, True)])
        self.assertEqual(result, [])

    def test_canonical_drops_empty_open_point(self):
        # Source: ISSUE.md rule 1: lo == hi is empty unless both closed.
        result = normalize([(4, 4, False, False)])
        self.assertEqual(result, [])

    def test_canonical_keeps_closed_single_point(self):
        # Source: ISSUE.md rule 1: lo == hi with both ends closed is the
        # single point [lo, lo], not empty.
        result = normalize([(3, 3, True, True)])
        self.assertEqual(result, [(3, 3, True, True)])

    def test_canonical_sorts_by_lower_bound(self):
        # Source: ISSUE.md rule 3: "sorted by lower bound". Disjoint,
        # non-touching intervals given out of order must come back sorted.
        result = normalize([(10, 11), (1, 2)])
        self.assertEqual(result, [(1, 2, True, True), (10, 11, True, True)])


class TouchingMergeTests(unittest.TestCase):
    """ISSUE.md rule 2: touch-merge exactly when a closed end meets the
    meeting point, including the point-fills-the-gap case."""

    def test_canonical_worked_example_merges_via_touching(self):
        # Source: ISSUE.md worked example, verbatim. Carries 'canonical' in
        # its name per the -k canonical acceptance criterion; exercises
        # touch-merge so it lives with the touching tests.
        result = normalize([
            (5, 6),
            (1, 3, True, False),
            (3, 3, True, True),
            (3, 4, False, True),
            (4, 4, False, False),
        ])
        self.assertEqual(result, [(1, 4, True, True), (5, 6, True, True)])

    def test_touching_two_closed_ends_merge(self):
        # Source: ISSUE.md rule 2: "[1, 3] + [3, 5] ... become [1, 5]".
        result = normalize([(1, 3, True, True), (3, 5, True, True)])
        self.assertEqual(result, [(1, 5, True, True)])

    def test_touching_closed_lower_meets_open_upper_merges(self):
        # Source: ISSUE.md rule 2: "[1, 3) + [3, 5] ... become [1, 5]".
        result = normalize([(1, 3, True, False), (3, 5, True, True)])
        self.assertEqual(result, [(1, 5, True, True)])

    def test_touching_closed_upper_meets_open_lower_merges(self):
        # Source: ISSUE.md rule 2: "[1, 3] + (3, 5] ... become [1, 5]".
        result = normalize([(1, 3, True, True), (3, 5, False, True)])
        self.assertEqual(result, [(1, 5, True, True)])

    def test_touching_both_open_ends_do_not_merge(self):
        # Source: ISSUE.md rule 2: "[1, 3) + (3, 5] stay two intervals
        # because 3 belongs to neither."
        result = normalize([(1, 3, True, False), (3, 5, False, True)])
        self.assertEqual(
            result, [(1, 3, True, False), (3, 5, False, True)]
        )

    def test_touching_point_bridges_gap_between_two_open_ends(self):
        # Source: ISSUE.md rule 2: "A point [3, 3] between [1, 3) and (3, 5]
        # closes the gap: the three merge into [1, 5]."
        result = normalize([
            (1, 3, True, False),
            (3, 3, True, True),
            (3, 5, False, True),
        ])
        self.assertEqual(result, [(1, 5, True, True)])


class UnionTests(unittest.TestCase):
    """ISSUE.md rule 5: union(a, b) is the canonical form of all intervals
    of a and b. Named with 'touching' since it exercises the same
    touch-merge rule but across two separate input lists."""

    def test_touching_union_merges_across_both_lists(self):
        # Source: ISSUE.md rule 2 applied across two input lists instead of
        # one: [1, 3) from `a` touches [3, 5] from `b` at a closed end.
        result = union([(1, 3, True, False)], [(3, 5, True, True)])
        self.assertEqual(result, [(1, 5, True, True)])

    def test_touching_union_of_disjoint_lists_keeps_both(self):
        # Source: ISSUE.md rule 5, combined with rule 3 (no merge when the
        # gap isn't touching/overlapping).
        result = union([(1, 2)], [(10, 11)])
        self.assertEqual(
            result, [(1, 2, True, True), (10, 11, True, True)]
        )


class IntersectionTests(unittest.TestCase):
    """ISSUE.md rule 6: intersection contains exactly the points in both
    inputs; at an equal endpoint the result is closed only if both inputs
    are closed there."""

    def test_intersect_both_closed_rule_closed_and_open(self):
        # Source: ISSUE.md rule 6: "[1, 5] ∩ (1, 5) is (1, 5)".
        result = intersection([(1, 5, True, True)], [(1, 5, False, False)])
        self.assertEqual(result, [(1, 5, False, False)])

    def test_intersect_both_closed_rule_mixed_sides(self):
        # Source: ISSUE.md rule 6: "[1, 5) ∩ (1, 5] is (1, 5)".
        result = intersection([(1, 5, True, False)], [(1, 5, False, True)])
        self.assertEqual(result, [(1, 5, False, False)])

    def test_intersect_touching_closed_ends_yield_point(self):
        # Source: ISSUE.md rule 6: "[1, 3] ∩ [3, 5] is the point [3, 3]".
        result = intersection([(1, 3, True, True)], [(3, 5, True, True)])
        self.assertEqual(result, [(3, 3, True, True)])

    def test_intersect_touching_open_end_is_empty(self):
        # Source: ISSUE.md rule 6: "[1, 3) ∩ [3, 5] is empty".
        result = intersection([(1, 3, True, False)], [(3, 5, True, True)])
        self.assertEqual(result, [])

    def test_intersect_normalizes_inputs_first(self):
        # Source: ISSUE.md rule 6: "Inputs are normalized first, so
        # [1, 5] ∩ ([1, 2] + [2, 5]) is [1, 5], one interval."
        result = intersection(
            [(1, 5, True, True)],
            [(1, 2, True, True), (2, 5, True, True)],
        )
        self.assertEqual(result, [(1, 5, True, True)])


class DifferenceTests(unittest.TestCase):
    """ISSUE.md rule 7: difference contains exactly the points in ``a``
    not in ``b``; removing an interval opens the cut."""

    def test_difference_closed_cut_opens_both_ends(self):
        # Source: ISSUE.md rule 7: "[1, 5] - [2, 3] is [1, 2) + (3, 5]".
        result = difference([(1, 5, True, True)], [(2, 3, True, True)])
        self.assertEqual(
            result, [(1, 2, True, False), (3, 5, False, True)]
        )

    def test_difference_open_cut_leaves_both_ends_closed(self):
        # Source: ISSUE.md rule 7: "[1, 5] - (2, 3) is [1, 2] + [3, 5]".
        result = difference([(1, 5, True, True)], [(2, 3, False, False)])
        self.assertEqual(
            result, [(1, 2, True, True), (3, 5, True, True)]
        )

    def test_difference_leaves_single_point(self):
        # Source: ISSUE.md rule 7: "[1, 5] - ([1, 3) + (3, 5]) is the point
        # [3, 3]".
        result = difference(
            [(1, 5, True, True)],
            [(1, 3, True, False), (3, 5, False, True)],
        )
        self.assertEqual(result, [(3, 3, True, True)])

    def test_difference_empty_subtrahend_returns_normalized_a(self):
        # Source: ISSUE.md rule 7: "Subtracting an empty list returns
        # normalize(a)."
        result = difference([(5, 6), (1, 2)], [])
        self.assertEqual(
            result, [(1, 2, True, True), (5, 6, True, True)]
        )


class BoundsAndValidationTests(unittest.TestCase):
    """ISSUE.md rule 8 (unbounded ends participate in every operation) and
    the Representation section (malformed interval shapes raise ValueError)."""

    def test_bounds_union_of_unbounded_ends(self):
        # Source: ISSUE.md rule 8: "(None, 3] ∪ (2, None) is (None, None)".
        result = union([(None, 3, False, True)], [(2, None, False, False)])
        self.assertEqual(result, [(None, None, False, False)])

    def test_bounds_difference_splits_around_removed_middle(self):
        # Source: ISSUE.md rule 8: "(None, None) - [0, 1] is
        # (None, 0) + (1, None)".
        result = difference(
            [(None, None, False, False)], [(0, 1, True, True)]
        )
        self.assertEqual(
            result, [(None, 0, False, False), (1, None, False, False)]
        )

    def test_bounds_non_2_or_4_tuple_raises_valueerror(self):
        # Source: ISSUE.md Representation: "Anything that is not a 2- or
        # 4-tuple ... raises ValueError."
        with self.assertRaises(ValueError):
            normalize([(1, 2, 3)])

    def test_bounds_non_bool_flag_raises_valueerror(self):
        # Source: ISSUE.md Representation: "a non-bool flag ... raises
        # ValueError." 1 is not a bool even though bool is an int subclass.
        with self.assertRaises(ValueError):
            normalize([(1, 2, 1, True)])

    def test_bounds_non_number_bound_raises_valueerror(self):
        # Source: ISSUE.md Representation: "a non-number bound raises
        # ValueError."
        with self.assertRaises(ValueError):
            normalize([("a", 2, True, True)])

    def test_bounds_none_marked_closed_raises_valueerror(self):
        # Source: ISSUE.md Representation: "An unbounded end must be open:
        # None with True raises ValueError."
        with self.assertRaises(ValueError):
            normalize([(None, 2, True, True)])


if __name__ == "__main__":
    unittest.main()
