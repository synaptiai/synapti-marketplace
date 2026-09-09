"""Trap: retry_after measured from the newest accepted request instead of the oldest.
Masked when only one request sits in the window."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def retry_after(self, key, now):
        self._observe(now)
        if self.limit == 0:
            return __import__("math").inf
        q = self._in_window(key, now)
        if len(q) < self.limit:
            return 0.0
        return float(q[-1] + self.window - now)
