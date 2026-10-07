import unittest

from ratelimit import SlidingWindowLimiter


class TestLimitAcceptance(unittest.TestCase):
    def test_limit_accepts_exactly_limit_requests(self):
        lim = SlidingWindowLimiter(limit=3, window=10)
        results = [lim.allow("k", t) for t in (0, 1, 2, 3)]
        self.assertEqual(results, [True, True, True, False])

    def test_limit_keys_are_independent(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertTrue(lim.allow("b", 0))
        self.assertFalse(lim.allow("a", 0))
        self.assertFalse(lim.allow("b", 0))

    def test_limit_zero_denies_everything(self):
        lim = SlidingWindowLimiter(limit=0, window=10)
        self.assertFalse(lim.allow("k", 0))
        self.assertFalse(lim.allow("k", 5))
        self.assertEqual(lim.remaining("k", 5), 0)

    def test_limit_unseen_key_remaining_equals_limit(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        self.assertEqual(lim.remaining("never-seen", 0), 5)


class TestBoundarySemantics(unittest.TestCase):
    def test_boundary_request_stops_counting_at_exactly_t_plus_window(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("k", 0))
        # Still counts just before expiry.
        self.assertFalse(lim.allow("k", 9.999))
        # Expires exactly at t + window.
        self.assertTrue(lim.allow("k", 10))

    def test_boundary_remaining_reflects_half_open_window(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        lim.allow("k", 0)
        self.assertEqual(lim.remaining("k", 9.999), 0)
        self.assertEqual(lim.remaining("k", 10), 1)

    def test_boundary_sliding_not_fixed_buckets(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(lim.allow("k", 5))
        self.assertTrue(lim.allow("k", 8))
        # At now=10, request at t=5 expired (10 >= 5+10? no, 10<15, still
        # counts) -- use larger gap to actually test sliding behavior.
        self.assertFalse(lim.allow("k", 9))
        # Advance past first request's expiry (5 + 10 = 15) but not second's.
        self.assertTrue(lim.allow("k", 15))
        # Now both the second (t=8) and third (t=15) are in window; full.
        self.assertFalse(lim.allow("k", 16))
        # Second request (t=8) expires at 18.
        self.assertTrue(lim.allow("k", 18))

    def test_boundary_does_not_reset_on_fixed_window_multiples(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("k", 3))
        # Crossing a multiple-of-window boundary (10) does not reset the
        # window; it is anchored to the accepted request's own timestamp.
        self.assertFalse(lim.allow("k", 11))
        self.assertTrue(lim.allow("k", 13))


class TestDeniedRequests(unittest.TestCase):
    def test_denied_requests_not_recorded(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("k", 0))
        self.assertFalse(lim.allow("k", 1))  # denied, must not be recorded
        self.assertFalse(lim.allow("k", 2))  # still denied (only t=0 counts)
        self.assertEqual(lim.remaining("k", 2), 0)

    def test_denied_requests_do_not_affect_retry_after(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        lim.allow("k", 0)
        lim.allow("k", 5)  # denied
        # retry_after should still be based on the original accepted t=0,
        # not the denied attempt at t=5.
        self.assertAlmostEqual(lim.retry_after("k", 5), 5.0)

    def test_denied_requests_leave_remaining_unchanged(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        lim.allow("k", 0)
        self.assertEqual(lim.remaining("k", 0), 1)
        lim.allow("k", 0)
        self.assertEqual(lim.remaining("k", 0), 0)
        lim.allow("k", 0)  # denied, third request
        self.assertEqual(lim.remaining("k", 0), 0)


class TestRetryAfterAndRemaining(unittest.TestCase):
    def test_retry_after_zero_when_allow_would_succeed(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertEqual(lim.retry_after("k", 0), 0.0)
        lim.allow("k", 0)
        self.assertEqual(lim.retry_after("k", 0), 0.0)

    def test_retry_after_measured_from_oldest_in_window_request(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        lim.allow("k", 0)
        lim.allow("k", 3)
        # Full now; oldest is t=0, expires at 10, so retry_after(now=4) = 6.
        self.assertAlmostEqual(lim.retry_after("k", 4), 6.0)

    def test_retry_after_inf_when_limit_zero(self):
        lim = SlidingWindowLimiter(limit=0, window=10)
        self.assertEqual(lim.retry_after("k", 0), float("inf"))
        self.assertEqual(lim.retry_after("k", 100), float("inf"))

    def test_retry_after_agrees_with_allow_and_remaining(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        lim.allow("k", 0)
        for t in (1, 4, 9.999):
            self.assertEqual(lim.remaining("k", t), 0)
            self.assertGreater(lim.retry_after("k", t), 0.0)
            self.assertFalse(lim.allow("k", t))
        self.assertEqual(lim.remaining("k", 10), 1)
        self.assertEqual(lim.retry_after("k", 10), 0.0)
        self.assertTrue(lim.allow("k", 10))

    def test_retry_after_unseen_key(self):
        lim = SlidingWindowLimiter(limit=3, window=10)
        self.assertEqual(lim.retry_after("unseen", 0), 0.0)


class TestConstructorAndMonotonicRejection(unittest.TestCase):
    def test_reject_negative_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=-1, window=10)

    def test_reject_non_int_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1.5, window=10)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit="3", window=10)

    def test_reject_bool_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=True, window=10)

    def test_reject_zero_or_negative_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=0)
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=-5)

    def test_reject_non_numeric_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window="10")

    def test_reject_non_monotonic_now_on_allow(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("k", 5)
        with self.assertRaises(ValueError):
            lim.allow("k", 4)

    def test_reject_non_monotonic_now_across_keys(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("a", 10)
        with self.assertRaises(ValueError):
            lim.allow("b", 9)

    def test_reject_non_monotonic_now_across_methods(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.remaining("k", 10)
        with self.assertRaises(ValueError):
            lim.retry_after("k", 9)

    def test_equal_now_is_fine(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("k", 5)
        # Equal now should not raise.
        lim.allow("k", 5)


if __name__ == "__main__":
    unittest.main()
