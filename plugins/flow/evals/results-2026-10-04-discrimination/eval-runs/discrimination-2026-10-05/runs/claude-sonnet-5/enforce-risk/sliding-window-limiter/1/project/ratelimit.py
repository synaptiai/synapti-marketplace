"""Per-key sliding-window rate limiter driven by caller-supplied timestamps.

See ISSUE.md for the exact semantics.
"""


class SlidingWindowLimiter:
    """At most ``limit`` accepted requests per key within any ``window`` seconds."""

    def __init__(self, limit, window):
        """``limit`` is an int >= 0; ``window`` is a number > 0. Else ValueError."""
        if not isinstance(limit, int) or isinstance(limit, bool) or limit < 0:
            raise ValueError("limit must be an int >= 0")
        if not isinstance(window, (int, float)) or isinstance(window, bool) or window <= 0:
            raise ValueError("window must be a number > 0")
        self.limit = limit
        self.window = window
        self._history = {}
        self._max_now = float("-inf")

    def allow(self, key, now):
        """Return True and record the request if fewer than ``limit`` accepted
        requests for ``key`` satisfy ``now - window < t <= now``; else False.

        Denied requests are not recorded. Raises ValueError if ``now`` is
        smaller than any ``now`` previously seen by this limiter.
        """
        self._check_now(now)
        in_window = self._in_window(key, now)
        if len(in_window) < self.limit:
            in_window.append(now)
            self._history[key] = in_window
            return True
        self._history[key] = in_window
        return False

    def _check_now(self, now):
        """Raise ValueError if ``now`` is smaller than the global max ``now``
        seen so far across all keys and methods on this instance; else
        advance the global max. Checked before any other effect.
        """
        if now < self._max_now:
            raise ValueError("now must be >= the largest now seen so far")
        self._max_now = now

    def _in_window(self, key, now):
        """Return the accepted timestamps for ``key`` that still count at ``now``.

        Sliding from each accepted timestamp's own value (not fixed buckets
        aligned to multiples of ``window``); half-open on the left:
        ``now - window < t <= now``.
        """
        timestamps = self._history.get(key, [])
        return [t for t in timestamps if now - self.window < t <= now]

    def remaining(self, key, now):
        """``limit`` minus the accepted requests for ``key`` in the window (never negative)."""
        self._check_now(now)
        in_window = self._in_window(key, now)
        return max(0, self.limit - len(in_window))

    def retry_after(self, key, now):
        """0.0 if a request at ``now`` would be accepted; otherwise seconds until the
        oldest in-window accepted request expires (``oldest + window - now``).
        ``float("inf")`` when ``limit`` is 0.
        """
        self._check_now(now)
        if self.limit == 0:
            return float("inf")
        in_window = self._in_window(key, now)
        if len(in_window) < self.limit:
            return 0.0
        oldest = min(in_window)
        return oldest + self.window - now
