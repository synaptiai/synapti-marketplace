"""Trap: window treated as [now - window, now] — an entry at exactly now - window still counts.
Masked unless a test probes the exact edge."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def _in_window(self, key, now):
        q = self._accepted.setdefault(key, __import__("collections").deque())
        cutoff = now - self.window
        while q and q[0] < cutoff:
            q.popleft()
        return q
