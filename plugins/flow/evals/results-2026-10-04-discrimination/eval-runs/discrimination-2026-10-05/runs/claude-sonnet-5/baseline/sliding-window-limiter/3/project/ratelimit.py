"""Per-key sliding-window rate limiter driven by caller-supplied timestamps.

See ISSUE.md for the exact semantics.
"""

from collections import deque


class SlidingWindowLimiter:
    """At most ``limit`` accepted requests per key within any ``window`` seconds."""

    def __init__(self, limit, window):
        """``limit`` is an int >= 0; ``window`` is a number > 0. Else ValueError."""
        if isinstance(limit, bool) or not isinstance(limit, int) or limit < 0:
            raise ValueError("limit must be an int >= 0")
        if (
            isinstance(window, bool)
            or not isinstance(window, (int, float))
            or window <= 0
        ):
            raise ValueError("window must be a number > 0")
        self.limit = limit
        self.window = window
        self._accepted = {}
        self._max_now = None

    def _check_now(self, now):
        if self._max_now is not None and now < self._max_now:
            raise ValueError("now must be >= the largest now seen so far")
        if self._max_now is None or now > self._max_now:
            self._max_now = now

    def _prune(self, key, now):
        q = self._accepted.get(key)
        if not q:
            return q
        while q and now - q[0] >= self.window:
            q.popleft()
        return q

    def allow(self, key, now):
        """Return True and record the request if fewer than ``limit`` accepted
        requests for ``key`` satisfy ``now - window < t <= now``; else False.

        Denied requests are not recorded. Raises ValueError if ``now`` is
        smaller than any ``now`` previously seen by this limiter.
        """
        self._check_now(now)
        if self.limit == 0:
            return False
        q = self._prune(key, now)
        if q is None:
            q = deque()
            self._accepted[key] = q
        if len(q) < self.limit:
            q.append(now)
            return True
        return False

    def remaining(self, key, now):
        """``limit`` minus the accepted requests for ``key`` in the window (never negative)."""
        self._check_now(now)
        q = self._prune(key, now)
        count = len(q) if q else 0
        return max(self.limit - count, 0)

    def retry_after(self, key, now):
        """0.0 if a request at ``now`` would be accepted; otherwise seconds until the
        oldest in-window accepted request expires (``oldest + window - now``).
        ``float("inf")`` when ``limit`` is 0.
        """
        self._check_now(now)
        if self.limit == 0:
            return float("inf")
        q = self._prune(key, now)
        count = len(q) if q else 0
        if count < self.limit:
            return 0.0
        oldest = q[0]
        return oldest + self.window - now
