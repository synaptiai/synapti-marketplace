import unittest

from ratelimit import SlidingWindowLimiter


class TestLimitBasics(unittest.TestCase):
    def test_limit_accepts_exactly_limit_requests_per_key(self):
        limiter = SlidingWindowLimiter(limit=3, window=10)
        results = [limiter.allow("a", t) for t in (0, 1, 2, 3)]
        self.assertEqual(results, [True, True, True, False])

    def test_limit_zero_denies_everything(self):
        limiter = SlidingWindowLimiter(limit=0, window=10)
        self.assertFalse(limiter.allow("a", 0))
        self.assertFalse(limiter.allow("a", 100))

    def test_limit_keys_are_independent(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 0))
        self.assertFalse(limiter.allow("a", 1))
        # a different key has its own budget
        self.assertTrue(limiter.allow("b", 1))

    def test_limit_remaining_counts_against_limit_independently_per_key(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)
        limiter.allow("a", 0)
        self.assertEqual(limiter.remaining("a", 0), 1)
        self.assertEqual(limiter.remaining("b", 0), 2)


class TestBoundarySemantics(unittest.TestCase):
    def test_boundary_request_still_counts_just_before_expiry(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 0))
        # just before expiry, still counts -> denied
        self.assertFalse(limiter.allow("a", 9.999))

    def test_boundary_request_stops_counting_at_exactly_t_plus_window(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 0))
        # exactly at expiry, no longer counts -> accepted
        self.assertTrue(limiter.allow("a", 10))

    def test_boundary_half_open_left_edge(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 5))
        # now - window < t <= now; at now=15, t=5 => 15-10=5 < 5 is False, so expired
        self.assertTrue(limiter.allow("a", 15))

    def test_boundary_window_slides_not_fixed_buckets(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(limiter.allow("a", 1))
        self.assertTrue(limiter.allow("a", 9))
        # at now=11, request at t=1 expired (11-10=1, 1<=1 cutoff), t=9 still counts
        self.assertEqual(limiter.remaining("a", 11), 1)
        self.assertTrue(limiter.allow("a", 11))
        self.assertFalse(limiter.allow("a", 11))


class TestDeniedRequests(unittest.TestCase):
    def test_denied_requests_not_recorded(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 0))
        self.assertFalse(limiter.allow("a", 1))  # denied, should not be recorded
        self.assertFalse(limiter.allow("a", 2))  # still denied due to t=0 in window

    def test_denied_requests_do_not_affect_remaining(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 0))
        self.assertEqual(limiter.remaining("a", 1), 0)
        limiter.allow("a", 1)  # denied
        self.assertEqual(limiter.remaining("a", 2), 0)
        # once the only accepted request expires, remaining resets fully
        self.assertEqual(limiter.remaining("a", 10), 1)

    def test_denied_requests_do_not_affect_retry_after(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(limiter.allow("a", 0))
        ra_before = limiter.retry_after("a", 1)
        limiter.allow("a", 1)  # denied, should not reset the window
        ra_after = limiter.retry_after("a", 1)
        self.assertEqual(ra_before, ra_after)


class TestRemainingAndRetryAfter(unittest.TestCase):
    def test_retry_after_zero_when_allowed(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)
        self.assertEqual(limiter.retry_after("a", 0), 0.0)
        limiter.allow("a", 0)
        self.assertEqual(limiter.retry_after("a", 0), 0.0)

    def test_retry_after_measured_from_oldest_request(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)
        limiter.allow("a", 0)
        limiter.allow("a", 5)
        # both in window now, limit reached -> retry_after based on oldest (t=0)
        self.assertEqual(limiter.retry_after("a", 6), 0 + 10 - 6)

    def test_retry_after_infinite_when_limit_zero(self):
        limiter = SlidingWindowLimiter(limit=0, window=10)
        self.assertEqual(limiter.retry_after("a", 0), float("inf"))
        self.assertEqual(limiter.retry_after("a", 1000), float("inf"))

    def test_retry_after_agrees_with_allow_decision(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        limiter.allow("a", 0)
        ra = limiter.retry_after("a", 5)
        self.assertGreater(ra, 0.0)
        self.assertFalse(limiter.allow("a", 5))
        # moving to exactly the retry_after point should now be allowed
        self.assertTrue(limiter.allow("a", 5 + ra))

    def test_retry_after_unseen_key(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        self.assertEqual(limiter.retry_after("unseen", 0), 0.0)

    def test_remaining_unseen_key_is_limit(self):
        limiter = SlidingWindowLimiter(limit=5, window=10)
        self.assertEqual(limiter.remaining("unseen", 100), 5)

    def test_remaining_never_negative(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        limiter.allow("a", 0)
        self.assertGreaterEqual(limiter.remaining("a", 0), 0)


class TestRejectInvalidInput(unittest.TestCase):
    def test_reject_negative_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=-1, window=10)

    def test_reject_non_int_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1.5, window=10)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit="3", window=10)

    def test_reject_zero_or_negative_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=0)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=-5)

    def test_reject_non_numeric_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window="10")

    def test_reject_non_monotonic_time(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        limiter.allow("a", 5)
        with self.assertRaises(ValueError):
            limiter.allow("a", 4)

    def test_reject_non_monotonic_time_across_keys(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        limiter.allow("a", 5)
        with self.assertRaises(ValueError):
            limiter.allow("b", 4)

    def test_reject_non_monotonic_time_across_methods(self):
        limiter = SlidingWindowLimiter(limit=1, window=10)
        limiter.remaining("a", 5)
        with self.assertRaises(ValueError):
            limiter.retry_after("a", 4)

    def test_reject_equal_time_is_allowed(self):
        limiter = SlidingWindowLimiter(limit=2, window=10)
        limiter.allow("a", 5)
        # equal now is fine, should not raise
        self.assertTrue(limiter.allow("a", 5))


if __name__ == "__main__":
    unittest.main()
