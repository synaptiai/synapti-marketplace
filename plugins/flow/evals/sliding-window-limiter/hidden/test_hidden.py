"""Hidden reference suite for the sliding-window rate limiter.

Never shown to the agent. Expected values are hand-derived from the spec in
scaffold/ISSUE.md (timelines written out in comments) and checked against
hidden/reference_impl.py. Comments name the trap each test discriminates
(see hidden/traps.json and expected.md).

Run: PYTHONPATH=<project dir> python3 hidden/test_hidden.py -v
"""
import math
import unittest

from ratelimit import SlidingWindowLimiter


class Counting(unittest.TestCase):

    def test_allows_exactly_limit_then_denies(self):
        # trap: limit-off-by-one lets a fourth request through
        lim = SlidingWindowLimiter(limit=3, window=10)
        self.assertEqual([lim.allow("k", t) for t in (0, 1, 2, 3)], [True, True, True, False])

    def test_limit_one(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("k", 0))
        self.assertFalse(lim.allow("k", 0))

    def test_limit_zero_denies_everything(self):
        lim = SlidingWindowLimiter(limit=0, window=10)
        self.assertFalse(lim.allow("k", 0))
        self.assertFalse(lim.allow("k", 100))

    def test_denied_requests_are_not_recorded(self):
        # limit 2, window 10: accepted 0,1; denied 2,3,4. At 10.5 the window is
        # (0.5, 10.5]: only the accepted request at 1 remains -> allowed.
        # trap: counts-denied would still see 2,3,4 and deny.
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertEqual([lim.allow("k", t) for t in (0, 1, 2, 3, 4)], [True, True, False, False, False])
        self.assertTrue(lim.allow("k", 10.5))

    def test_keys_are_independent(self):
        # trap: shared-counter denies b after a used the limit
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertTrue(lim.allow("a", 1))
        self.assertFalse(lim.allow("a", 2))
        self.assertTrue(lim.allow("b", 2))
        self.assertTrue(lim.allow("b", 3))
        self.assertFalse(lim.allow("b", 4))

    def test_interleaved_keys_count_separately(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        seq = [("a", 0), ("b", 0), ("a", 1), ("b", 1), ("a", 2), ("b", 2)]
        self.assertEqual([lim.allow(k, t) for k, t in seq], [True, True, True, True, False, False])


class Boundaries(unittest.TestCase):

    def test_request_at_exactly_window_edge_has_expired(self):
        # accepted at 0 with window 10 stops counting at now = 10 (window is (0, 10])
        # trap: inclusive-boundary still counts it and denies
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("k", 0))
        self.assertTrue(lim.allow("k", 10))

    def test_request_just_inside_window_is_denied(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("k", 0))
        self.assertFalse(lim.allow("k", 9.999))

    def test_capacity_frees_one_entry_at_a_time(self):
        # accepted 0 and 1 (limit 2). At 10: 0 expired -> allow (records 10).
        # At 10.5: window (0.5, 10.5] holds 1 and 10 -> deny. At 11: 1 expired -> allow.
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(lim.allow("k", 0))
        self.assertTrue(lim.allow("k", 1))
        self.assertFalse(lim.allow("k", 5))
        self.assertTrue(lim.allow("k", 10))
        self.assertFalse(lim.allow("k", 10.5))
        self.assertTrue(lim.allow("k", 11))

    def test_sliding_window_not_fixed_buckets(self):
        # accepted at 9 and 9.5 (limit 2, window 10). A fixed [10, 20) bucket would
        # reset at 10.5; the sliding window (0.5, 10.5] still holds both -> deny.
        # trap: fixed-window
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(lim.allow("k", 9))
        self.assertTrue(lim.allow("k", 9.5))
        self.assertFalse(lim.allow("k", 10.5))
        self.assertFalse(lim.allow("k", 18.9))
        self.assertTrue(lim.allow("k", 19))

    def test_fractional_window(self):
        lim = SlidingWindowLimiter(limit=1, window=0.5)
        self.assertTrue(lim.allow("k", 0.25))
        self.assertFalse(lim.allow("k", 0.7))
        self.assertTrue(lim.allow("k", 0.75))

    def test_same_timestamp_twice_is_not_an_error(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        self.assertTrue(lim.allow("k", 3))
        self.assertTrue(lim.allow("k", 3))


class Remaining(unittest.TestCase):

    def test_remaining_for_unseen_key_is_limit(self):
        lim = SlidingWindowLimiter(limit=4, window=10)
        self.assertEqual(lim.remaining("new", 0), 4)

    def test_remaining_counts_down_and_recovers(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        lim.allow("k", 0)
        self.assertEqual(lim.remaining("k", 0), 1)
        lim.allow("k", 4)
        self.assertEqual(lim.remaining("k", 4), 0)
        self.assertEqual(lim.remaining("k", 10), 1)
        self.assertEqual(lim.remaining("k", 14), 2)

    def test_remaining_ignores_denied_requests(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        lim.allow("k", 0)
        lim.allow("k", 1)
        lim.allow("k", 2)
        self.assertEqual(lim.remaining("k", 10), 1)


class RetryAfter(unittest.TestCase):

    def test_retry_after_is_zero_when_a_request_would_be_allowed(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertEqual(lim.retry_after("k", 0), 0.0)
        lim.allow("k", 0)
        self.assertEqual(lim.retry_after("k", 1), 0.0)

    def test_retry_after_measures_from_oldest_in_window(self):
        # accepted 1, 2, 3 (limit 3, window 10); at now=5 the oldest (1) expires at 11 -> 6.0
        # trap: retry-from-newest would answer 3 + 10 - 5 = 8.0
        lim = SlidingWindowLimiter(limit=3, window=10)
        for t in (1, 2, 3):
            self.assertTrue(lim.allow("k", t))
        self.assertAlmostEqual(lim.retry_after("k", 5), 6.0)

    def test_retry_after_agrees_with_allow(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        lim.allow("k", 2)
        lim.allow("k", 7)
        wait = lim.retry_after("k", 8)
        self.assertAlmostEqual(wait, 4.0)
        self.assertFalse(lim.allow("k", 8 + wait - 0.001))
        self.assertTrue(lim.allow("k", 8 + wait))

    def test_retry_after_with_single_request_in_window(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        lim.allow("k", 4)
        self.assertAlmostEqual(lim.retry_after("k", 9), 5.0)

    def test_retry_after_limit_zero_is_infinite(self):
        lim = SlidingWindowLimiter(limit=0, window=10)
        self.assertTrue(math.isinf(lim.retry_after("k", 0)))


class Validation(unittest.TestCase):

    def test_time_going_backwards_raises(self):
        # trap: no-monotonic-check
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("k", 5)
        with self.assertRaises(ValueError):
            lim.allow("k", 4)

    def test_time_going_backwards_across_keys_raises(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("a", 5)
        with self.assertRaises(ValueError):
            lim.remaining("b", 4.5)

    def test_constructor_rejects_bad_limit_and_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=-1, window=10)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=0)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=-3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
