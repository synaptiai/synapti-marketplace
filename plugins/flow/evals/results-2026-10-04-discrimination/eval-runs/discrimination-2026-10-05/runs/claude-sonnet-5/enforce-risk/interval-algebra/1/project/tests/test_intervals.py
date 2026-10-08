"""Tests for intervals.py.

Expected values are sourced from ISSUE.md (the spec) and the risk map in
.decisions/issue-1.md (hand-computed, never from running the implementation).
Each test cites its source in a comment.

Note on risk-map row "None (unbounded) ordering": the row's literal example
`normalize([(5,6),(None,3)])` uses a 2-tuple shorthand with a None bound.
Per ISSUE.md's own Representation rule, a 2-tuple always expands to
`(lo, hi, True, True)`, and "None with True raises ValueError" for an
unbounded end. So that literal example is self-contradictory (auto-drafted,
never reviewed by a human per the journal's note). We test the same
*behavior* (None sorts first, no TypeError) with an explicit 4-tuple
instead, and separately test that the 2-tuple-with-None case does raise
ValueError (see test_shorthand_with_none_raises_valueerror_bounds).
"""
import unittest
from decimal import Decimal
from fractions import Fraction

from intervals import normalize, union, intersection, difference


class TestCanonical(unittest.TestCase):
    def test_worked_example_canonical(self):
        # Source: ISSUE.md worked example (lines 68-70).
        result = normalize([
            (5, 6),
            (1, 3, True, False),
            (3, 3, True, True),
            (3, 4, False, True),
            (4, 4, False, False),
        ])
        self.assertEqual(result, [(1, 4, True, True), (5, 6, True, True)])

    def test_shorthand_canonical(self):
        # Source: ISSUE.md Representation, "Shorthand" (line 29).
        self.assertEqual(normalize([(1, 2)]), [(1, 2, True, True)])

    def test_empty_dropped_canonical(self):
        # Source: ISSUE.md rule 1, "lo > hi is empty".
        self.assertEqual(normalize([(5, 3)]), [])

    def test_point_kept_when_both_closed_canonical(self):
        # Source: ISSUE.md rule 1, "lo == hi is empty unless both ends are
        # closed, in which case it is the single point [lo, lo]".
        self.assertEqual(normalize([(3, 3, True, True)]), [(3, 3, True, True)])

    def test_degenerate_point_requires_both_closed_canonical(self):
        # Source: .decisions/issue-1.md risk map, "empty-vs-point degenerate
        # interval (lo == hi)" row. right: [] (all three dropped).
        result = normalize([
            (3, 3, True, False),
            (3, 3, False, True),
            (3, 3, False, False),
        ])
        self.assertEqual(result, [])

    def test_sorted_by_lower_bound_canonical(self):
        # Source: ISSUE.md rule 3, canonical form "sorted by lower bound".
        self.assertEqual(
            normalize([(5, 6), (1, 2)]),
            [(1, 2, True, True), (5, 6, True, True)],
        )

    def test_none_sorts_first_canonical(self):
        # Source: .decisions/issue-1.md risk map, "None (unbounded)
        # ordering" row, behavior adapted to an explicit 4-tuple (see
        # module docstring note).
        result = normalize([(5, 6, True, True), (None, 3, False, True)])
        self.assertEqual(result, [(None, 3, False, True), (5, 6, True, True)])


class TestTouching(unittest.TestCase):
    def test_touch_merge_both_closed_touching(self):
        # Source: ISSUE.md rule 2, "[1, 3] + [3, 5] ... become [1, 5]".
        self.assertEqual(
            normalize([(1, 3, True, True), (3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touch_merge_left_closed_touching(self):
        # Source: ISSUE.md rule 2, "[1, 3) + [3, 5] ... become [1, 5]".
        self.assertEqual(
            normalize([(1, 3, True, False), (3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touch_merge_right_closed_touching(self):
        # Source: ISSUE.md rule 2, "[1, 3] + (3, 5] ... become [1, 5]".
        self.assertEqual(
            normalize([(1, 3, True, True), (3, 5, False, True)]),
            [(1, 5, True, True)],
        )

    def test_touch_no_merge_both_open_touching(self):
        # Source: ISSUE.md rule 2, "[1, 3) + (3, 5] stay two intervals
        # because 3 belongs to neither"; also risk map row "touch-merge
        # closedness test".
        result = normalize([(1, 3, True, False), (3, 5, False, True)])
        self.assertEqual(result, [(1, 3, True, False), (3, 5, False, True)])

    def test_point_fills_gap_touching(self):
        # Source: ISSUE.md rule 2, "A point [3, 3] between [1, 3) and
        # (3, 5] closes the gap: the three merge into [1, 5]"; also risk
        # map row "point-fills-gap merging".
        result = normalize([
            (1, 3, True, False),
            (3, 3, True, True),
            (3, 5, False, True),
        ])
        self.assertEqual(result, [(1, 5, True, True)])

    def test_merged_closedness_from_any_interval_touching(self):
        # Source: ISSUE.md rule 2, "A merged interval's lower end is closed
        # if any merged interval starting there was closed, and likewise
        # for the upper end."
        result = normalize([(1, 3, False, True), (1, 2, True, True)])
        self.assertEqual(result, [(1, 3, True, True)])

    def test_union_merges_touching_intervals_from_two_lists_touching(self):
        # Source: ISSUE.md rule 2, applied via union() across two separate
        # lists (maintenance windows [8,10] and [10,12] merging example).
        result = union([(8, 10, True, True)], [(10, 12, True, True)])
        self.assertEqual(result, [(8, 12, True, True)])


class TestIntersect(unittest.TestCase):
    def test_both_closed_required_at_equal_endpoint_intersect(self):
        # Source: ISSUE.md rule 6 + risk map row "intersection equal-
        # endpoint closedness". right: (1,5,False,False).
        result = intersection([(1, 5, True, True)], [(1, 5, False, False)])
        self.assertEqual(result, [(1, 5, False, False)])

    def test_and_rule_at_equal_endpoints_intersect(self):
        # Source: ISSUE.md rule 6, "[1, 5) ∩ (1, 5] is (1, 5)".
        result = intersection([(1, 5, True, False)], [(1, 5, False, True)])
        self.assertEqual(result, [(1, 5, False, False)])

    def test_closed_touch_yields_point_intersect(self):
        # Source: ISSUE.md rule 6, "[1, 3] ∩ [3, 5] is the point [3, 3]".
        result = intersection([(1, 3, True, True)], [(3, 5, True, True)])
        self.assertEqual(result, [(3, 3, True, True)])

    def test_open_touch_yields_empty_intersect(self):
        # Source: ISSUE.md rule 6, "[1, 3) ∩ [3, 5] is empty".
        result = intersection([(1, 3, True, False)], [(3, 5, True, True)])
        self.assertEqual(result, [])

    def test_normalizes_inputs_intersect(self):
        # Source: ISSUE.md rule 6, "Inputs are normalized first, so [1, 5]
        # ∩ ([1, 2] + [2, 5]) is [1, 5], one interval."
        result = intersection(
            [(1, 5, True, True)],
            [(1, 2, True, True), (2, 5, True, True)],
        )
        self.assertEqual(result, [(1, 5, True, True)])


class TestDifference(unittest.TestCase):
    def test_cut_opens_ends_difference(self):
        # Source: ISSUE.md rule 7 + risk map row "difference cut-opening".
        # right: [(1,2,True,False),(3,5,False,True)].
        result = difference([(1, 5, True, True)], [(2, 3, True, True)])
        self.assertEqual(result, [(1, 2, True, False), (3, 5, False, True)])

    def test_open_subtrahend_leaves_cut_closed_difference(self):
        # Source: ISSUE.md rule 7, "[1, 5] − (2, 3) is [1, 2] + [3, 5]".
        result = difference([(1, 5, True, True)], [(2, 3, False, False)])
        self.assertEqual(result, [(1, 2, True, True), (3, 5, True, True)])

    def test_leaves_point_difference(self):
        # Source: ISSUE.md rule 7, "[1, 5] − ([1, 3) + (3, 5]) is the point
        # [3, 3]".
        result = difference(
            [(1, 5, True, True)],
            [(1, 3, True, False), (3, 5, False, True)],
        )
        self.assertEqual(result, [(3, 3, True, True)])

    def test_unbounded_subtrahend_difference(self):
        # Source: ISSUE.md rule 8, "(None, None) − [0, 1] is (None, 0) +
        # (1, None)".
        result = difference([(None, None, False, False)], [(0, 1, True, True)])
        self.assertEqual(
            result, [(None, 0, False, False), (1, None, False, False)]
        )

    def test_empty_subtrahend_returns_normalized_a_difference(self):
        # Source: ISSUE.md rule 7, "Subtracting an empty list returns
        # normalize(a)."
        result = difference([(2, 1), (1, 3)], [])
        self.assertEqual(result, normalize([(2, 1), (1, 3)]))
        self.assertEqual(result, [(1, 3, True, True)])


class TestBounds(unittest.TestCase):
    def test_unbounded_union_bounds(self):
        # Source: ISSUE.md rule 8, "(None, 3] ∪ (2, None) is (None, None)".
        result = union([(None, 3, False, True)], [(2, None, False, False)])
        self.assertEqual(result, [(None, None, False, False)])

    def test_unbounded_difference_bounds(self):
        # Source: ISSUE.md rule 8, "(None, None) − [0, 1] is (None, 0) +
        # (1, None)".
        result = difference([(None, None, False, False)], [(0, 1, True, True)])
        self.assertEqual(
            result, [(None, 0, False, False), (1, None, False, False)]
        )

    def test_none_sorts_first_no_typeerror_bounds(self):
        # Source: risk map row "None (unbounded) ordering": must not sort
        # None as greatest, and must not TypeError comparing None to a
        # number.
        result = normalize([(5, 6, True, True), (None, 3, False, True)])
        self.assertEqual(result, [(None, 3, False, True), (5, 6, True, True)])

    def test_fraction_bounds_survive_unchanged_bounds(self):
        # Source: ISSUE.md header, "fractions and decimal are available and
        # their values must survive unchanged; do not convert bounds to
        # float."
        result = normalize([(Fraction(1, 2), Fraction(3, 2))])
        self.assertEqual(result, [(Fraction(1, 2), Fraction(3, 2), True, True)])
        self.assertIsInstance(result[0][0], Fraction)

    def test_decimal_bounds_survive_unchanged_bounds(self):
        # Source: ISSUE.md header, same rule, for Decimal.
        result = normalize([(Decimal("1.5"), Decimal("2.5"))])
        self.assertEqual(
            result, [(Decimal("1.5"), Decimal("2.5"), True, True)]
        )
        self.assertIsInstance(result[0][0], Decimal)

    def test_flags_are_bool_not_int_bounds(self):
        # Source: ISSUE.md rule 3, "Flags are bool (True/False, not 1/0)".
        result = normalize([(1, 2)])
        self.assertIs(result[0][2], True)
        self.assertIs(result[0][3], True)

    def test_malformed_wrong_length_tuple_bounds(self):
        # Source: ISSUE.md Representation, "Anything that is not a 2- or
        # 4-tuple ... raises ValueError."
        with self.assertRaises(ValueError):
            normalize([(1, 2, 3)])

    def test_malformed_non_bool_flag_bounds(self):
        # Source: ISSUE.md Representation, "a non-bool flag ... raises
        # ValueError." (1/1 are int, not bool, even though truthy.)
        with self.assertRaises(ValueError):
            normalize([(1, 2, 1, 1)])

    def test_malformed_non_number_bound_bounds(self):
        # Source: ISSUE.md Representation, "a non-number bound ... raises
        # ValueError."
        with self.assertRaises(ValueError):
            normalize([("a", "b", True, True)])

    def test_unbounded_closed_raises_valueerror_bounds(self):
        # Source: ISSUE.md Representation, "An unbounded end must be open:
        # None with True raises ValueError."
        with self.assertRaises(ValueError):
            normalize([(None, 3, True, True)])

    def test_shorthand_with_none_raises_valueerror_bounds(self):
        # Source: combination of ISSUE.md Representation "Shorthand" rule
        # (2-tuple expands to True/True) and the unbounded-must-be-open
        # rule: a 2-tuple with a None bound is therefore always invalid.
        with self.assertRaises(ValueError):
            normalize([(None, 3)])


if __name__ == "__main__":
    unittest.main()
