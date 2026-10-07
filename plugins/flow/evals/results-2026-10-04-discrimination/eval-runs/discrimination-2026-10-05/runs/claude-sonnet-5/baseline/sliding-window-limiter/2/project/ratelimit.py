"""Per-key sliding-window rate limiter driven by caller-supplied timestamps.

See ISSUE.md for the exact semantics. This file is the starting skeleton for
the task: every method body below raises NotImplementedError and must be
replaced with a real implementation.
"""

from collections import deque


class SlidingWindowLimiter:
    """At most ``limit`` accepted requests per key within any ``window`` seconds."""

    def __init__(self, limit, window):
        """``limit`` is an int >= 0; ``window`` is a number > 0. Else ValueError."""
        if not isinstance(limit, int) or limit < 0:
            raise ValueError("limit must be an int >= 0")
        if not isinstance(window, (int, float)) or window <= 0:
            raise ValueError("window must be a number > 0")
        self.limit = limit
        self.window = window
        self._requests = {}
        self._max_now = None

    def _check_time(self, now):
        if self._max_now is not None and now < self._max_now:
            raise ValueError("now must be >= the largest now seen so far")
        self._max_now = now if self._max_now is None else max(self._max_now, now)

    def _prune(self, key, now):
        dq = self._requests.get(key)
        if dq is None:
            return deque()
        while dq and now - self.window >= dq[0]:
            dq.popleft()
        return dq

    def allow(self, key, now):
        """Return True and record the request if fewer than ``limit`` accepted
        requests for ``key`` satisfy ``now - window < t <= now``; else False.

        Denied requests are not recorded. Raises ValueError if ``now`` is
        smaller than any ``now`` previously seen by this limiter.
        """
        self._check_time(now)
        dq = self._prune(key, now)
        if len(dq) < self.limit:
            dq.append(now)
            self._requests[key] = dq
            return True
        return False

    def remaining(self, key, now):
        """``limit`` minus the accepted requests for ``key`` in the window (never negative)."""
        self._check_time(now)
        dq = self._prune(key, now)
        return max(self.limit - len(dq), 0)

    def retry_after(self, key, now):
        """0.0 if a request at ``now`` would be accepted; otherwise seconds until the
        oldest in-window accepted request expires (``oldest + window - now``).
        ``float("inf")`` when ``limit`` is 0.
        """
        self._check_time(now)
        if self.limit == 0:
            return float("inf")
        dq = self._prune(key, now)
        if len(dq) < self.limit:
            return 0.0
        return dq[0] + self.window - now
