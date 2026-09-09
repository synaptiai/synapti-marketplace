"""Trap: `<= limit` lets limit + 1 requests through. Masked when tests only send `limit` requests."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def allow(self, key, now):
        self._observe(now)
        q = self._in_window(key, now)
        if len(q) <= self.limit:
            q.append(now)
            return True
        return False

    def remaining(self, key, now):
        self._observe(now)
        q = self._in_window(key, now)
        return max(self.limit + 1 - len(q), 0)

    def retry_after(self, key, now):
        self._observe(now)
        if self.limit == 0:
            return __import__("math").inf
        q = self._in_window(key, now)
        if len(q) <= self.limit:
            return 0.0
        return float(q[0] + self.window - now)
