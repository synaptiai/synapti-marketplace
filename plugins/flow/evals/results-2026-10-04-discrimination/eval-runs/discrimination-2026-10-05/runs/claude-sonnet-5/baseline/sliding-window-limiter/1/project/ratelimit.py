"""Per-key sliding-window rate limiter driven by caller-supplied timestamps.

See ISSUE.md for the exact semantics. This file is the starting skeleton for
the task: every method body below raises NotImplementedError and must be
replaced with a real implementation.
"""

from collections import defaultdict, deque


class SlidingWindowLimiter:
    """At most ``limit`` accepted requests per key within any ``window`` seconds."""

    def __init__(self, limit, window):
        """``limit`` is an int >= 0; ``window`` is a number > 0. Else ValueError."""
        if not isinstance(limit, int) or isinstance(limit, bool) or limit < 0:
            raise ValueError("limit must be an int >= 0")
        if (
            not isinstance(window, (int, float))
            or isinstance(window, bool)
            or window <= 0
        ):
            raise ValueError("window must be a number > 0")
        self._limit = limit
        self._window = window
        self._history = defaultdict(deque)
        self._last_now = None

    def _check_now(self, now):
        if self._last_now is not None and now < self._last_now:
            raise ValueError("now must not go backwards")
        self._last_now = now

    def _purge(self, key, now):
        history = self._history[key]
        cutoff = now - self._window
        while history and history[0] <= cutoff:
            history.popleft()
        return history

    def allow(self, key, now):
        """Return True and record the request if fewer than ``limit`` accepted
        requests for ``key`` satisfy ``now - window < t <= now``; else False.

        Denied requests are not recorded. Raises ValueError if ``now`` is
        smaller than any ``now`` previously seen by this limiter.
        """
        self._check_now(now)
        history = self._purge(key, now)
        if len(history) < self._limit:
            history.append(now)
            return True
        return False

    def remaining(self, key, now):
        """``limit`` minus the accepted requests for ``key`` in the window (never negative)."""
        self._check_now(now)
        history = self._purge(key, now)
        return max(self._limit - len(history), 0)

    def retry_after(self, key, now):
        """0.0 if a request at ``now`` would be accepted; otherwise seconds until the
        oldest in-window accepted request expires (``oldest + window - now``).
        ``float("inf")`` when ``limit`` is 0.
        """
        self._check_now(now)
        if self._limit == 0:
            return float("inf")
        history = self._purge(key, now)
        if len(history) < self._limit:
            return 0.0
        oldest = history[0]
        return oldest + self._window - now
