"""Trap: one counter for all keys. Masked when every test uses a single key."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def _in_window(self, key, now):
        return _ref.SlidingWindowLimiter._in_window(self, "", now)
