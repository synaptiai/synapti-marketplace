"""Tests for ratelimit.SlidingWindowLimiter.

Expected values are sourced from ISSUE.md's Semantics section and from the
risk map captured in .decisions/issue-1.md (discriminating checks chosen to
distinguish the specified behavior from plausible wrong implementations).
"""

import unittest

from ratelimit import SlidingWindowLimiter


class RejectTests(unittest.TestCase):
    """Keyword 'reject': constructor arg validation and non-monotonic time.

    Source: ISSUE.md Semantics -- "limit is an int >= 0; window is a number
    > 0. Anything else raises ValueError." and "Time is monotonic: now ...
    must be >= the largest now ... A smaller value raises ValueError."
    """

    def test_reject_negative_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(-1, 10)

    def test_reject_non_int_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1.5, 10)

    def test_reject_non_int_limit_string(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter("1", 10)

    def test_reject_zero_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1, 0)

    def test_reject_negative_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1, -5)

    def test_reject_non_number_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1, "10")


class LimitTests(unittest.TestCase):
    """Keyword 'limit': exactly `limit` accepted per key, independence, limit=0.

    Source: ISSUE.md Semantics -- "accept (and record) the request if fewer
    than limit accepted requests are in the window for key; otherwise deny.
    With limit = 0 every request is denied." and the risk-map
    'accept/deny threshold' discriminating check in .decisions/issue-1.md.
    """

    def test_limit_accept_deny_threshold(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertTrue(limiter.allow("k", 0))
        # count is now 1, which is not < limit(1): must deny, not accept
        # (a count <= limit implementation would wrongly accept here).
        self.assertFalse(limiter.allow("k", 0))

    def test_limit_zero_denies_everything(self):
        limiter = SlidingWindowLimiter(0, 10)
        self.assertFalse(limiter.allow("k", 0))
        self.assertFalse(limiter.allow("k", 1))

    def test_limit_keys_are_independent(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertTrue(limiter.allow("A", 0))
        self.assertTrue(limiter.allow("B", 0))


class BoundaryTests(unittest.TestCase):
    """Keyword 'boundary': half-open window edge; sliding, not fixed buckets.

    Source: ISSUE.md Semantics -- "The window is half-open on the left: at
    time now, an accepted request at time t counts iff now - window < t <=
    now ... with window = 10, a request accepted at 0 no longer counts at
    now = 10, but still counts at now = 9.999." and "It is a sliding window
    over the actual timestamps ... not fixed buckets." Also the risk-map
    rows 'window half-open boundary' and 'sliding window vs fixed buckets'
    in .decisions/issue-1.md.
    """

    def test_boundary_entry_expires_exactly_at_t_plus_window(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertTrue(limiter.allow("k", 0))
        # Right at now=10 the t=0 entry must have expired (now - window ==
        # t, not > t, so it no longer satisfies now - window < t).
        self.assertTrue(limiter.allow("k", 10))

    def test_boundary_entry_still_counts_just_before_expiry(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertTrue(limiter.allow("k", 0))
        # Just before now=10 the t=0 entry still counts, so this is denied.
        self.assertFalse(limiter.allow("k", 9.999))

    def test_boundary_slides_from_accepted_timestamp_not_fixed_bucket(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertTrue(limiter.allow("k", 5))
        # 5 + 10 = 15 > 11, so the t=5 entry is still in-window at now=11.
        # A fixed-bucket-of-10 implementation would start a new bucket at
        # now=10 and wrongly accept here.
        self.assertFalse(limiter.allow("k", 11))


class DeniedTests(unittest.TestCase):
    """Keyword 'denied': a denied request leaves no trace.

    Source: ISSUE.md Semantics -- "Only accepted requests are recorded. A
    denied request leaves no trace and never counts against the key." and
    the risk-map 'denied requests must not be recorded' discriminating
    check in .decisions/issue-1.md.
    """

    def test_denied_request_is_not_recorded(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertTrue(limiter.allow("k", 0))  # accepted, recorded at t=0
        self.assertFalse(limiter.allow("k", 5))  # denied: t=0 still in-window
        # At now=10 the t=0 entry has expired. If the denied t=5 attempt had
        # been recorded too, it would still be in-window (5+10=15>10) and
        # wrongly deny here.
        self.assertTrue(limiter.allow("k", 10))


class RetryTests(unittest.TestCase):
    """Keyword 'retry': remaining/retry_after agree with allow; oldest-based.

    Source: ISSUE.md Semantics -- "remaining: limit minus the number of
    accepted requests in the window (never negative). For an unseen key it
    is limit." and "retry_after: 0.0 if a request at now would be accepted;
    otherwise ... oldest + window - now. With limit = 0 return
    float('inf')." Also the risk-map 'retry_after uses oldest, not newest'
    discriminating check in .decisions/issue-1.md.
    """

    def test_retry_remaining_for_unseen_key_is_limit(self):
        limiter = SlidingWindowLimiter(3, 10)
        self.assertEqual(limiter.remaining("k", 0), 3)

    def test_retry_remaining_decreases_on_accept(self):
        limiter = SlidingWindowLimiter(3, 10)
        limiter.allow("k", 0)
        self.assertEqual(limiter.remaining("k", 0), 2)

    def test_retry_after_zero_when_request_would_be_accepted(self):
        limiter = SlidingWindowLimiter(1, 10)
        self.assertEqual(limiter.retry_after("k", 0), 0.0)

    def test_retry_after_uses_oldest_not_newest_in_window_request(self):
        limiter = SlidingWindowLimiter(2, 10)
        self.assertTrue(limiter.allow("k", 0))
        self.assertTrue(limiter.allow("k", 5))
        self.assertEqual(limiter.remaining("k", 6), 0)
        # oldest-based: 0 + 10 - 6 = 4.0 (a newest-based wrong implementation
        # would compute 5 + 10 - 6 = 9.0).
        self.assertEqual(limiter.retry_after("k", 6), 4.0)

    def test_retry_after_is_infinite_when_limit_is_zero(self):
        limiter = SlidingWindowLimiter(0, 10)
        self.assertEqual(limiter.retry_after("k", 0), float("inf"))


class RejectNonMonotonicTests(unittest.TestCase):
    """Keyword 'reject': global monotonic clock across all keys and methods.

    Source: ISSUE.md Semantics -- "Time is monotonic: now passed to any
    method must be >= the largest now the limiter has seen so far (across
    all keys and methods). A smaller value raises ValueError. Equal values
    are fine." Also the risk-map 'monotonic clock scope' discriminating
    check in .decisions/issue-1.md.
    """

    def test_reject_smaller_now_across_different_keys(self):
        limiter = SlidingWindowLimiter(1, 10)
        limiter.allow("A", 5)
        # Fresh key "B" has no prior now of its own; a per-key-scoped check
        # would wrongly allow this. The global max (5) must still apply.
        with self.assertRaises(ValueError):
            limiter.remaining("B", 3)

    def test_reject_smaller_now_same_method_same_key(self):
        limiter = SlidingWindowLimiter(1, 10)
        limiter.allow("A", 5)
        with self.assertRaises(ValueError):
            limiter.allow("A", 4)

    def test_reject_equal_now_is_allowed(self):
        limiter = SlidingWindowLimiter(2, 10)
        limiter.allow("A", 5)
        # Equal values are fine -- must not raise.
        self.assertTrue(limiter.allow("A", 5))


if __name__ == "__main__":
    unittest.main()
