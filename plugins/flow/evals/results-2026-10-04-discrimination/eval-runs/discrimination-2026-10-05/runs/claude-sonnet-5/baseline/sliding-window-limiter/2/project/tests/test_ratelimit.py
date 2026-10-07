import unittest

from ratelimit import SlidingWindowLimiter


class LimitTests(unittest.TestCase):
    def test_limit_accepts_exactly_limit_requests_per_key(self):
        lim = SlidingWindowLimiter(limit=3, window=10)
        for _ in range(3):
            self.assertTrue(lim.allow("a", 0))
        self.assertFalse(lim.allow("a", 0))

    def test_limit_keys_are_independent(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertFalse(lim.allow("a", 0))
        self.assertTrue(lim.allow("b", 0))
        self.assertFalse(lim.allow("b", 0))

    def test_limit_zero_denies_everything(self):
        lim = SlidingWindowLimiter(limit=0, window=10)
        self.assertFalse(lim.allow("a", 0))
        self.assertFalse(lim.allow("a", 100))

    def test_limit_resets_after_window_slides_past_all_requests(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertTrue(lim.allow("a", 1))
        self.assertFalse(lim.allow("a", 2))
        # both requests have now fully expired by t=11
        self.assertTrue(lim.allow("a", 11))
        self.assertTrue(lim.allow("a", 12))


class BoundaryTests(unittest.TestCase):
    def test_boundary_request_still_counts_just_before_expiry(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertFalse(lim.allow("a", 9.999))

    def test_boundary_request_stops_counting_at_exactly_window(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertTrue(lim.allow("a", 10))

    def test_boundary_accepted_at_t_counts_at_t_itself(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 5))
        self.assertFalse(lim.allow("a", 5))

    def test_boundary_sliding_not_fixed_buckets(self):
        # With fixed buckets aligned to multiples of window=10, requests at
        # t=5 and t=14 would fall in different "buckets" and both be allowed
        # with limit=1. A true sliding window must deny the second because
        # 14 - 10 = 4 < 5, so the t=5 request still counts at t=14.
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 5))
        self.assertFalse(lim.allow("a", 14))
        self.assertTrue(lim.allow("a", 15))


class DeniedTests(unittest.TestCase):
    def test_denied_requests_not_recorded(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertFalse(lim.allow("a", 1))
        self.assertFalse(lim.allow("a", 2))
        # still only the original request at t=0 counts
        self.assertEqual(lim.remaining("a", 2), 0)
        self.assertTrue(lim.allow("a", 10))

    def test_denied_requests_do_not_affect_remaining(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertTrue(lim.allow("a", 0))
        self.assertEqual(lim.remaining("a", 0), 1)
        self.assertTrue(lim.allow("a", 1))
        self.assertFalse(lim.allow("a", 2))
        self.assertFalse(lim.allow("a", 3))
        self.assertEqual(lim.remaining("a", 3), 0)


class RetryTests(unittest.TestCase):
    def test_retry_after_zero_when_request_would_be_accepted(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertEqual(lim.retry_after("a", 0), 0.0)
        lim.allow("a", 0)
        self.assertEqual(lim.retry_after("a", 0), 0.0)

    def test_retry_after_measured_from_oldest_request(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        lim.allow("a", 0)
        lim.allow("a", 3)
        self.assertEqual(lim.retry_after("a", 5), 5.0)  # oldest=0: 0+10-5

    def test_retry_after_agrees_with_allow(self):
        lim = SlidingWindowLimiter(limit=1, window=10)
        lim.allow("a", 0)
        self.assertEqual(lim.retry_after("a", 5), 5.0)
        self.assertFalse(lim.allow("a", 5))
        self.assertEqual(lim.retry_after("a", 10), 0.0)
        self.assertTrue(lim.allow("a", 10))

    def test_retry_after_infinite_when_limit_zero(self):
        lim = SlidingWindowLimiter(limit=0, window=10)
        self.assertEqual(lim.retry_after("a", 0), float("inf"))
        self.assertEqual(lim.retry_after("a", 100), float("inf"))

    def test_remaining_agrees_with_allow(self):
        lim = SlidingWindowLimiter(limit=2, window=10)
        self.assertEqual(lim.remaining("a", 0), 2)
        lim.allow("a", 0)
        self.assertEqual(lim.remaining("a", 0), 1)
        lim.allow("a", 0)
        self.assertEqual(lim.remaining("a", 0), 0)
        self.assertFalse(lim.allow("a", 0))

    def test_remaining_unseen_key_is_limit(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        self.assertEqual(lim.remaining("never-seen", 0), 5)


class RejectTests(unittest.TestCase):
    def test_reject_negative_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=-1, window=10)

    def test_reject_non_int_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1.5, window=10)

    def test_reject_zero_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=0)

    def test_reject_negative_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window=-5)

    def test_reject_non_numeric_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(limit=1, window="10")

    def test_reject_non_monotonic_time(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("a", 10)
        with self.assertRaises(ValueError):
            lim.allow("a", 9)

    def test_reject_non_monotonic_time_across_keys_and_methods(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("a", 10)
        lim.remaining("b", 20)
        with self.assertRaises(ValueError):
            lim.retry_after("a", 15)

    def test_reject_equal_time_is_fine(self):
        lim = SlidingWindowLimiter(limit=5, window=10)
        lim.allow("a", 10)
        try:
            lim.allow("a", 10)
        except ValueError:
            self.fail("equal now should not raise ValueError")


if __name__ == "__main__":
    unittest.main()
