"""Trap: time going backwards is silently accepted. Masked whenever timestamps are increasing."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class SlidingWindowLimiter(_ref.SlidingWindowLimiter):

    def _observe(self, now):
        self._last_now = now
