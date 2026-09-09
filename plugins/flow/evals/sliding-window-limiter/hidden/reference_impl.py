"""Reference implementation of the sliding-window rate limiter (spec: scaffold/ISSUE.md).

The hidden suite (hidden/test_hidden.py) was written from the spec and then
checked against this file. Keep the two in sync.
"""
import math
from collections import deque


class SlidingWindowLimiter:

    def __init__(self, limit, window):
        if isinstance(limit, bool) or not isinstance(limit, int) or limit < 0:
            raise ValueError("limit must be a non-negative integer")
        if isinstance(window, bool) or not isinstance(window, (int, float)) or not window > 0:
            raise ValueError("window must be a positive number of seconds")
        self.limit = limit
        self.window = window
        self._accepted = {}
        self._last_now = None

    def _observe(self, now):
        if self._last_now is not None and now < self._last_now:
            raise ValueError("time went backwards: %r < %r" % (now, self._last_now))
        self._last_now = now

    def _in_window(self, key, now):
        # window is (now - window, now]: an entry at t stops counting once now >= t + window
        q = self._accepted.get(key)
        if q is None:
            q = deque()
            self._accepted[key] = q
        cutoff = now - self.window
        while q and q[0] <= cutoff:
            q.popleft()
        return q

    def allow(self, key, now):
        self._observe(now)
        q = self._in_window(key, now)
        if len(q) < self.limit:
            q.append(now)
            return True
        return False

    def remaining(self, key, now):
        self._observe(now)
        q = self._in_window(key, now)
        return max(self.limit - len(q), 0)

    def retry_after(self, key, now):
        self._observe(now)
        if self.limit == 0:
            return math.inf
        q = self._in_window(key, now)
        if len(q) < self.limit:
            return 0.0
        return float(q[0] + self.window - now)
