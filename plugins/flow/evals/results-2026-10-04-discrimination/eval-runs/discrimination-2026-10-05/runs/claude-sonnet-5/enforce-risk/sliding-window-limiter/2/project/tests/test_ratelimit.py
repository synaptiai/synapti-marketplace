"""Tests for SlidingWindowLimiter (see ISSUE.md for semantics).

Each expected value in these tests is sourced either directly from
ISSUE.md's prose semantics (cited by line range) or from the risk map
captured in .decisions/issue-1.md (cited by row name), or is hand-derived
from those rules. None are taken from running the implementation.
"""

import unittest

from ratelimit import SlidingWindowLimiter


class RejectConstructorArgsTests(unittest.TestCase):
    """ISSUE.md lines 18-20 / 59: bad constructor args raise ValueError."""

    def test_reject_invalid_constructor_args(self):
        # Valid construction must not raise (positive control).
        SlidingWindowLimiter(limit=1, window=1)
        SlidingWindowLimiter(limit=0, window=0.5)

        # limit must be an int >= 0.
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=-1, window=10)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1.5, window=10)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit="1", window=10)

        # window must be a number > 0.
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=0)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=-5)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window="10")


class LimitEnforcementTests(unittest.TestCase):
    """ISSUE.md lines 18, 31-33, 55: exactly `limit` requests per key per
    window; keys independent; limit=0 denies everything."""

    def test_limit_enforced_per_key_and_zero_denies_all(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)

        # Two distinct, non-degenerate timestamps within the window.
        self.assertTrue(limiter.allow("k1", 0))
        self.assertTrue(limiter.allow("k1", 1))
        # Third request within the same still-open window is over limit.
        self.assertFalse(limiter.allow("k1", 2))

        # A different key is fully independent (ISSUE.md line 30) even at
        # the same instant the first key is already exhausted.
        self.assertTrue(limiter.allow("k2", 2))

        # limit = 0 denies every request (ISSUE.md line 33).
        zero_limiter = SlidingWindowLimiter(limit=0, window=10)
        self.assertFalse(zero_limiter.allow("k1", 0))


class BoundaryTests(unittest.TestCase):
    """ISSUE.md lines 21-25 / risk map rows "left boundary of window" and
    "right boundary of window" in .decisions/issue-1.md: the window is
    half-open, now - window < t <= now."""

    def test_boundary_half_open_window(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("k", 0))

        # Just before expiry (t=0, window=10): still counts.
        # Hand-derived from 0 - 10 < 0 <= 9.999 -> True, so remaining is 0.
        self.assertEqual(limiter.remaining("k", 9.999), 0)

        # Exactly at expiry instant (now = t + window = 10): no longer
        # counts, because the left bound is exclusive (now - window < t).
        # 10 - 10 = 0, and 0 < 0 is False, so t=0 has expired.
        self.assertEqual(limiter.remaining("k", 10), 1)

        # Right boundary: a request accepted at exactly `now` counts
        # against itself immediately (t <= now is inclusive).
        limiter2 = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter2.allow("k2", 5))
        self.assertEqual(limiter2.remaining("k2", 5), 0)


class DeniedNotRecordedTests(unittest.TestCase):
    """ISSUE.md lines 28-29 / risk map row "recording on denial" in
    .decisions/issue-1.md: a denied request leaves no trace."""

    def test_denied_requests_not_recorded(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("k", 0))
        # Over limit while t=0 is still in-window: denied.
        self.assertFalse(limiter.allow("k", 1))
        # At now=10, t=0 has expired (10 - 10 = 0, not < 0). If the denied
        # attempt at t=1 had been recorded, 10 - 10 = 0 < 1 would still be
        # in-window and this would wrongly be denied.
        self.assertTrue(limiter.allow("k", 10))


class RetryAfterTests(unittest.TestCase):
    """ISSUE.md lines 34-39 / risk map rows "retry_after anchor point" and
    the second half of "limit = 0 edge cases" in .decisions/issue-1.md."""

    def test_retry_after_and_remaining_agree_with_allow(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)
        # Two distinct accepted timestamps, not the same instant.
        self.assertTrue(limiter.allow("k", 0))
        self.assertTrue(limiter.allow("k", 5))

        # remaining is now 0 (both slots used) -> retry_after must be > 0,
        # anchored on the OLDEST accepted request (t=0): 0 + 10 - 5 = 5.0.
        # A wrong implementation anchored on the newest (t=5) would give
        # 5 + 10 - 5 = 10.0.
        self.assertEqual(limiter.remaining("k", 5), 0)
        self.assertEqual(limiter.retry_after("k", 5), 5.0)

        # Agreement: once remaining > 0 again (t=0 has expired by now=10),
        # retry_after must be 0.0.
        self.assertEqual(limiter.remaining("k", 10), 1)
        self.assertEqual(limiter.retry_after("k", 10), 0.0)

        # limit = 0 special case: retry_after is +inf, not the generic
        # "no in-window requests -> 0.0" value.
        zero_limiter = SlidingWindowLimiter(limit=0, window=10)
        self.assertEqual(zero_limiter.retry_after("k", 0), float("inf"))


class RejectNonMonotonicTimeTests(unittest.TestCase):
    """ISSUE.md lines 40-42 / risk map row "monotonic-clock scope" in
    .decisions/issue-1.md: the high-water mark is global across all keys
    and all three methods, including read-only ones."""

    def test_reject_non_monotonic_time(self):
        limiter = SlidingWindowLimiter(limit=5, window=10)
        self.assertTrue(limiter.allow("A", 10))

        # A different, previously-unseen key with a smaller `now`, on a
        # read-only method, must still raise ValueError: the mark is
        # global, not per-key or allow()-only.
        with self.assertRaises(ValueError):
            limiter.remaining("B", 5)

        # Equal `now` is fine (monotonic, not strictly increasing).
        self.assertEqual(limiter.remaining("A", 10), 4)

        with self.assertRaises(ValueError):
            limiter.retry_after("A", 9)


if __name__ == "__main__":
    unittest.main()
