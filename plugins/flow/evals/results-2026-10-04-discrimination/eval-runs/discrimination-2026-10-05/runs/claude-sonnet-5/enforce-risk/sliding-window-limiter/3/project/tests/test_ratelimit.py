"""Tests for ratelimit.SlidingWindowLimiter.

Expected values are derived from ISSUE.md ("## Semantics") and the
interface contracts / risk map captured in .decisions/issue-1.md, not from
running the implementation. Each test name carries the acceptance-criterion
keyword (-k limit / boundary / denied / retry / reject) required by
ISSUE.md's Acceptance Criteria section.
"""

import unittest

from ratelimit import SlidingWindowLimiter


class ConstructorRejectTests(unittest.TestCase):
    """ISSUE.md: 'limit is an int >= 0; window is a number > 0. Else
    ValueError.' Source: ISSUE.md ## Semantics, first bullet."""

    def test_reject_negative_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(-1, 10)

    def test_reject_non_int_limit(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1.5, 10)

    def test_reject_zero_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1, 0)

    def test_reject_negative_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1, -5)

    def test_reject_non_number_window(self):
        with self.assertRaises(ValueError):
            SlidingWindowLimiter(1, "10")

    def test_reject_valid_args_construct_without_error(self):
        # Not a rejection case, but pinned here so the ValueError paths
        # above are proven not to be a blanket "always raise".
        SlidingWindowLimiter(1, 10)


class MonotonicityRejectTests(unittest.TestCase):
    """ISSUE.md: 'now passed to any method must be >= the largest now the
    limiter has seen so far (across all keys and methods). A smaller value
    raises ValueError.' Source: ISSUE.md ## Semantics, last bullet, and
    risk-map row 'Monotonicity scope' in .decisions/issue-1.md."""

    def test_reject_smaller_now_same_key(self):
        rl = SlidingWindowLimiter(5, 10)
        rl.allow("a", 10)
        with self.assertRaises(ValueError):
            rl.allow("a", 5)

    def test_reject_smaller_now_across_different_keys(self):
        # Risk-map discriminator: a per-key (not global) watermark would
        # wrongly allow this since key "b" is fresh.
        rl = SlidingWindowLimiter(5, 10)
        rl.allow("a", 10)
        with self.assertRaises(ValueError):
            rl.allow("b", 5)

    def test_reject_smaller_now_via_remaining_or_retry_after(self):
        # The watermark is shared across methods, not just allow().
        rl = SlidingWindowLimiter(5, 10)
        rl.remaining("a", 10)
        with self.assertRaises(ValueError):
            rl.retry_after("b", 5)

    def test_reject_equal_now_is_fine(self):
        rl = SlidingWindowLimiter(5, 10)
        rl.allow("a", 10)
        # Equal is explicitly allowed per spec.
        rl.allow("b", 10)


class LimitTests(unittest.TestCase):
    """ISSUE.md acceptance criterion: 'Exactly limit requests are accepted
    per key per window, keys are independent, and limit = 0 denies
    everything.' Source: ISSUE.md ## Semantics bullets on `allow` and
    `remaining`, hand-derived."""

    def test_limit_accepts_exactly_limit_then_denies(self):
        rl = SlidingWindowLimiter(3, 100)
        results = [rl.allow("k", t) for t in (0, 1, 2, 3)]
        # First 3 requests are within the empty-to-3-accepted budget; the
        # 4th exceeds `limit=3` so must be denied.
        self.assertEqual(results, [True, True, True, False])

    def test_limit_keys_independent(self):
        rl = SlidingWindowLimiter(1, 100)
        # Key "a" uses its one slot; key "b" is untouched and must still
        # get its own independent slot.
        self.assertTrue(rl.allow("a", 0))
        self.assertFalse(rl.allow("a", 1))
        self.assertTrue(rl.allow("b", 1))

    def test_limit_zero_denies_everything(self):
        rl = SlidingWindowLimiter(0, 100)
        self.assertFalse(rl.allow("k", 0))
        self.assertFalse(rl.allow("k", 1))


class BoundaryTests(unittest.TestCase):
    """ISSUE.md acceptance criterion: half-open window, sliding not
    fixed-bucket. Inputs and expected values are taken verbatim from the
    risk map in .decisions/issue-1.md ('Risk map' table), which states the
    plausible wrong implementation each input discriminates against."""

    def test_boundary_left_exclusive_expired_request_not_counted(self):
        # Risk map row "Left-boundary of the window test": window=10,
        # accepted at t=0; wrong version (`now - window <= t`) still counts
        # it at now=10, right version does not.
        rl = SlidingWindowLimiter(1, 10)
        self.assertTrue(rl.allow("k", 0))
        self.assertEqual(rl.remaining("k", 10), 1)

    def test_boundary_left_exclusive_still_counts_just_before_expiry(self):
        # Same risk-map row, other side: at now=9.999 the t=0 request must
        # still count, so a second request is denied.
        rl = SlidingWindowLimiter(1, 10)
        self.assertTrue(rl.allow("k", 0))
        self.assertFalse(rl.allow("k", 9.999))

    def test_boundary_right_inclusive_self_counts(self):
        # Risk map row "Right-boundary of the window test": limit=1,
        # allow(key, 5) then remaining(key, 5) immediately after; wrong
        # version (`t < now`) reports remaining=1, right version reports 0.
        rl = SlidingWindowLimiter(1, 10)
        rl.allow("k", 5)
        self.assertEqual(rl.remaining("k", 5), 0)

    def test_boundary_sliding_not_fixed_bucket(self):
        # Risk map row "'Sliding' vs fixed buckets": window=10, limit=1,
        # requests at t=9 and t=11. A fixed-bucket version (floor(t/10))
        # puts t=9 in bucket 0 and t=11 in bucket 1, allowing both. The
        # sliding version must deny the second: at now=11, t=9 is still in
        # (1, 11].
        rl = SlidingWindowLimiter(1, 10)
        self.assertTrue(rl.allow("k", 9))
        self.assertFalse(rl.allow("k", 11))


class DeniedTests(unittest.TestCase):
    """ISSUE.md acceptance criterion: 'Denied requests are not recorded
    and do not affect later decisions.' Source: risk map row 'Recording
    order around denial' in .decisions/issue-1.md."""

    def test_denied_request_leaves_no_trace(self):
        rl = SlidingWindowLimiter(1, 10)
        self.assertTrue(rl.allow("k", 0))
        self.assertFalse(rl.allow("k", 1))  # denied, must not be recorded
        # remaining must still reflect only the single accepted request,
        # not a phantom second entry from the denied attempt.
        self.assertEqual(rl.remaining("k", 1), 0)
        # Repeating the denied attempt must behave identically: still
        # denied, not accepted because the limit was "already" miscounted.
        self.assertFalse(rl.allow("k", 1))

    def test_denied_attempt_does_not_block_later_slot(self):
        # Stronger discriminator for the same risk-map row: once the only
        # accepted request (t=0) ages out of the window, a fresh request
        # must be accepted. A buggy implementation that records the denied
        # t=1 attempt keeps that phantom entry alive past t=0's expiry
        # (window=10 means the phantom expires only after t=11), wrongly
        # denying the request at t=10.999.
        rl = SlidingWindowLimiter(1, 10)
        self.assertTrue(rl.allow("k", 0))
        self.assertFalse(rl.allow("k", 1))
        self.assertTrue(rl.allow("k", 10.999))


class RetryTests(unittest.TestCase):
    """ISSUE.md acceptance criterion: 'remaining and retry_after agree with
    allow, and retry_after is measured from the oldest in-window request.'
    Source: ISSUE.md ## Semantics (retry_after bullet) and the risk-map row
    'retry_after source request' in .decisions/issue-1.md."""

    def test_retry_zero_when_allow_would_succeed(self):
        rl = SlidingWindowLimiter(2, 10)
        rl.allow("k", 0)
        # One slot still free, so a request at now=0 would succeed.
        self.assertEqual(rl.retry_after("k", 0), 0.0)

    def test_retry_infinite_when_limit_zero(self):
        rl = SlidingWindowLimiter(0, 10)
        self.assertEqual(rl.retry_after("k", 0), float("inf"))

    def test_retry_after_measured_from_oldest_request(self):
        # Risk map row 'retry_after source request': limit=2, accepted at
        # t=0 and t=5, window=10. At now=5 the slot is full; a wrong
        # version basing retry on the newest (t=5) reports retry=10, the
        # right version bases it on the oldest (t=0) and reports retry=5
        # (oldest + window - now = 0 + 10 - 5).
        rl = SlidingWindowLimiter(2, 10)
        rl.allow("k", 0)
        rl.allow("k", 5)
        self.assertEqual(rl.retry_after("k", 5), 5)

    def test_retry_agrees_with_allow_decision(self):
        rl = SlidingWindowLimiter(1, 10)
        rl.allow("k", 0)
        # Slot full: allow would fail, so retry_after must be > 0.
        self.assertFalse(rl.allow("k", 1))
        self.assertGreater(rl.retry_after("k", 1), 0)
        # oldest(0) + window(10) - now(1) = 9.
        self.assertEqual(rl.retry_after("k", 1), 9)


if __name__ == "__main__":
    unittest.main()
