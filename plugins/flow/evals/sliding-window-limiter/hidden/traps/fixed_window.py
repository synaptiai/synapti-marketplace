"""Trap: fixed buckets [k*window, (k+1)*window) instead of a sliding window.
Masked when all requests of a test fall inside one bucket or are spaced by whole windows."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def _in_window(self, key, now):
        q = self._accepted.setdefault(key, __import__("collections").deque())
        bucket_start = (now // self.window) * self.window
        while q and q[0] < bucket_start:
            q.popleft()
        return q
