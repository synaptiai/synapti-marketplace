"""Trap: denied requests are recorded too, so a burst of rejections keeps the key locked out.
Masked when tests never send more than `limit` requests per window."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def allow(self, key, now):
        self._observe(now)
        q = self._in_window(key, now)
        allowed = len(q) < self.limit
        q.append(now)
        return allowed
