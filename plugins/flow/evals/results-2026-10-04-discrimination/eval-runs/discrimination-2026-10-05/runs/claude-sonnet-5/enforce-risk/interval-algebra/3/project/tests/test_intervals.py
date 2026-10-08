"""Tests for intervals.py. Sources for expected values are cited in each
test's comment/docstring: ISSUE.md section/rule number, or hand computation
from the stated rules.
"""
import unittest

from intervals import normalize, union, intersection, difference


class TestCanonical(unittest.TestCase):
    """Keyword: canonical. Source: ISSUE.md 'Representation' and Rule #1/#3,
    plus the literal worked example given in ISSUE.md."""

    def test_canonical_shorthand_becomes_closed_4tuple(self):
        # Source: ISSUE.md Representation, "Shorthand" bullet:
        # (lo, hi) means (lo, hi, True, True).
        self.assertEqual(normalize([(1, 2)]), [(1, 2, True, True)])

    def test_canonical_drops_empty_lo_greater_than_hi(self):
        # Source: ISSUE.md Rule #1: "lo > hi is empty ... dropped."
        self.assertEqual(normalize([(5, 2, True, True)]), [])

    def test_canonical_drops_empty_point_not_both_closed(self):
        # Source: ISSUE.md Rule #1: "lo == hi is empty unless both ends
        # are closed". (3, 3, False, True) has lo_closed=False -> empty.
        self.assertEqual(normalize([(3, 3, False, True)]), [])

    def test_canonical_keeps_closed_point(self):
        # Source: ISSUE.md Rule #1: lo==hi with both ends closed is the
        # single point [lo, lo].
        self.assertEqual(normalize([(3, 3, True, True)]), [(3, 3, True, True)])

    def test_canonical_sorts_by_lower_bound(self):
        # Source: ISSUE.md Rule #3: "sorted by lower bound".
        # Chosen input is non-degenerate: three disjoint, non-touching,
        # out-of-order intervals so a wrong (e.g. no-op / reverse-sort)
        # implementation is distinguishable from the right one.
        result = normalize([(10, 11), (1, 2), (5, 6)])
        self.assertEqual(
            result,
            [(1, 2, True, True), (5, 6, True, True), (10, 11, True, True)],
        )

    def test_canonical_worked_example(self):
        # Source: ISSUE.md, literal worked example:
        # normalize([(5, 6), (1, 3, True, False), (3, 3, True, True),
        # (3, 4, False, True), (4, 4, False, False)])
        # -> [(1, 4, True, True), (5, 6, True, True)].
        result = normalize([
            (5, 6),
            (1, 3, True, False),
            (3, 3, True, True),
            (3, 4, False, True),
            (4, 4, False, False),
        ])
        self.assertEqual(
            result,
            [(1, 4, True, True), (5, 6, True, True)],
        )


class TestTouching(unittest.TestCase):
    """Keyword: touching. Source: ISSUE.md Rule #2 (Merging) literal examples
    and the risk-map rows for touch-merge-at-closed-endpoint and
    point-interval-closing-a-gap."""

    def test_touching_closed_closed_merges_via_union(self):
        # Source: ISSUE.md Rule #2: "[1, 3] + [3, 5] ... become [1, 5]".
        # Exercised through union() of two separate lists (not just
        # normalize() of one list) since union must also merge across
        # its two inputs.
        self.assertEqual(
            union([(1, 3, True, True)], [(3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_open_closed_start_merges(self):
        # Source: ISSUE.md Rule #2: "[1, 3) + [3, 5] ... become [1, 5]".
        self.assertEqual(
            union([(1, 3, True, False)], [(3, 5, True, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_closed_open_start_merges(self):
        # Source: ISSUE.md Rule #2: "[1, 3] + (3, 5] ... become [1, 5]".
        self.assertEqual(
            union([(1, 3, True, True)], [(3, 5, False, True)]),
            [(1, 5, True, True)],
        )

    def test_touching_open_open_does_not_merge(self):
        # Source: ISSUE.md Rule #2: "[1, 3) + (3, 5] stay two intervals
        # because 3 belongs to neither." Discriminates a wrong
        # implementation that merges on any adjacency (hi1 == lo2) instead
        # of requiring at least one closed end at the meeting point.
        self.assertEqual(
            union([(1, 3, True, False)], [(3, 5, False, True)]),
            [(1, 3, True, False), (3, 5, False, True)],
        )

    def test_touching_point_bridges_gap(self):
        # Source: ISSUE.md Rule #2: "A point [3, 3] between [1, 3) and
        # (3, 5] closes the gap: the three merge into [1, 5]." Also
        # risk-map row "point interval closing a gap": a wrong
        # implementation drops/ignores the degenerate point before
        # checking adjacency and the three pieces stay disjoint.
        result = normalize([(1, 3, True, False), (3, 3, True, True), (3, 5, False, True)])
        self.assertEqual(result, [(1, 5, True, True)])


class TestIntersect(unittest.TestCase):
    """Keyword: intersect. Source: ISSUE.md Rule #6 literal examples and the
    'intersection endpoint closedness' risk-map row."""

    def test_intersect_both_open_wins_over_either_closed(self):
        # Source: ISSUE.md Rule #6: "[1, 5] ∩ (1, 5) is (1, 5)". Discriminates
        # a wrong implementation that uses OR instead of AND: a wrong
        # version would produce a closed-at-1 result since [1,5] is closed
        # there, but the right rule requires BOTH closed, and (1,5) is open
        # at 1, so the result must be open at 1.
        self.assertEqual(
            intersection([(1, 5, True, True)], [(1, 5, False, False)]),
            [(1, 5, False, False)],
        )

    def test_intersect_mixed_open_closed_ends_both_open(self):
        # Source: ISSUE.md Rule #6: "[1, 5) ∩ (1, 5] is (1, 5)". At lo=1:
        # left is closed, right is open -> AND is open. At hi=5: left is
        # open, right is closed -> AND is open.
        self.assertEqual(
            intersection([(1, 5, True, False)], [(1, 5, False, True)]),
            [(1, 5, False, False)],
        )

    def test_intersect_closed_touch_yields_point(self):
        # Source: ISSUE.md Rule #6: "[1, 3] ∩ [3, 5] is the point [3, 3]".
        self.assertEqual(
            intersection([(1, 3, True, True)], [(3, 5, True, True)]),
            [(3, 3, True, True)],
        )

    def test_intersect_open_touch_is_empty(self):
        # Source: ISSUE.md Rule #6: "[1, 3) ∩ [3, 5] is empty".
        self.assertEqual(
            intersection([(1, 3, True, False)], [(3, 5, True, True)]),
            [],
        )

    def test_intersect_normalizes_inputs_first(self):
        # Source: ISSUE.md Rule #6: "Inputs are normalized first, so
        # [1, 5] ∩ ([1, 2] + [2, 5]) is [1, 5], one interval." Discriminates
        # an implementation that intersects against the raw (unmerged)
        # second list and produces two touching output pieces instead of
        # recognizing [1,2]+[2,5] normalizes to one interval [1,5] first.
        result = intersection([(1, 5, True, True)], [(1, 2, True, True), (2, 5, True, True)])
        self.assertEqual(result, [(1, 5, True, True)])


class TestDifference(unittest.TestCase):
    """Keyword: difference. Source: ISSUE.md Rule #7 literal examples and the
    'difference cut-end polarity' risk-map row."""

    def test_difference_cut_flips_polarity_at_both_ends(self):
        # Source: ISSUE.md Rule #7: "[1, 5] - [2, 3] is [1, 2) + (3, 5]".
        # Discriminates a wrong implementation that keeps the original
        # interval's closedness at the cut point (would give [1,2]+[3,5])
        # instead of flipping to the opposite of the subtrahend's
        # closedness there (subtrahend closed at 2 and 3 -> cuts open).
        result = difference([(1, 5, True, True)], [(2, 3, True, True)])
        self.assertEqual(
            result,
            [(1, 2, True, False), (3, 5, False, True)],
        )

    def test_difference_open_subtrahend_leaves_closed_cuts(self):
        # Source: ISSUE.md Rule #7: "[1, 5] - (2, 3) is [1, 2] + [3, 5]".
        # Subtrahend open at 2 and 3 -> cuts stay closed.
        result = difference([(1, 5, True, True)], [(2, 3, False, False)])
        self.assertEqual(
            result,
            [(1, 2, True, True), (3, 5, True, True)],
        )

    def test_difference_leaves_a_single_point(self):
        # Source: ISSUE.md Rule #7: "[1, 5] - ([1, 3) + (3, 5]) is the point
        # [3, 3]".
        result = difference([(1, 5, True, True)], [(1, 3, True, False), (3, 5, False, True)])
        self.assertEqual(result, [(3, 3, True, True)])

    def test_difference_empty_subtrahend_returns_normalized_minuend(self):
        # Source: ISSUE.md Rule #7: "Subtracting an empty list returns
        # normalize(a)." Non-degenerate input: an unsorted, shorthand list
        # so the result is observably normalize(a), not just an echo of a.
        result = difference([(5, 6), (1, 2)], [])
        self.assertEqual(result, [(1, 2, True, True), (5, 6, True, True)])


class TestBounds(unittest.TestCase):
    """Keyword: bounds. Source: ISSUE.md Rule #8 (unbounded ends) and the
    Representation section (malformed-input ValueError), plus the
    'unbounded (None) ordering/comparison' risk-map row."""

    def test_bounds_union_of_unbounded_ends_spans_everything(self):
        # Source: ISSUE.md Rule #8: "(None, 3] ∪ (2, None) is (None, None)".
        # Discriminates an implementation that raises TypeError comparing
        # None to a number, or treats None identically on both sides
        # instead of -inf for lo / +inf for hi (which would keep two
        # separate intervals instead of merging into one unbounded span).
        result = union([(None, 3, False, True)], [(2, None, False, False)])
        self.assertEqual(result, [(None, None, False, False)])

    def test_bounds_difference_from_fully_unbounded(self):
        # Source: ISSUE.md Rule #8: "(None, None) - [0, 1] is (None, 0) +
        # (1, None)".
        result = difference([(None, None, False, False)], [(0, 1, True, True)])
        self.assertEqual(
            result,
            [(None, 0, False, False), (1, None, False, False)],
        )

    def test_bounds_none_with_closed_true_raises_value_error(self):
        # Source: ISSUE.md Representation: "An unbounded end must be open:
        # None with True raises ValueError." Applies to lo and hi
        # independently.
        with self.assertRaises(ValueError):
            normalize([(None, 5, True, True)])
        with self.assertRaises(ValueError):
            normalize([(0, None, True, True)])

    def test_bounds_wrong_tuple_length_raises_value_error(self):
        # Source: ISSUE.md Representation: "Anything that is not a 2- or
        # 4-tuple ... raises ValueError."
        with self.assertRaises(ValueError):
            normalize([(1, 2, True)])

    def test_bounds_non_bool_flag_raises_value_error(self):
        # Source: ISSUE.md Representation: "a non-bool flag ... raises
        # ValueError." 1 is truthy but not a bool, and must not be silently
        # accepted as True.
        with self.assertRaises(ValueError):
            normalize([(1, 2, 1, True)])

    def test_bounds_non_number_bound_raises_value_error(self):
        # Source: ISSUE.md Representation: "a non-number bound ... raises
        # ValueError."
        with self.assertRaises(ValueError):
            normalize([("a", 2, True, True)])


if __name__ == "__main__":
    unittest.main()
