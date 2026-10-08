"""Per-key sliding-window rate limiter driven by caller-supplied timestamps.

See ISSUE.md for the exact semantics.
"""


class SlidingWindowLimiter:
    """At most ``limit`` accepted requests per key within any ``window`` seconds."""

    def __init__(self, limit, window):
        """``limit`` is an int >= 0; ``window`` is a number > 0. Else ValueError."""
        if isinstance(limit, bool) or not isinstance(limit, int) or limit < 0:
            raise ValueError("limit must be an int >= 0")
        if (
            isinstance(window, bool)
            or not isinstance(window, (int, float))
            or window <= 0
        ):
            raise ValueError("window must be a number > 0")

        self._limit = limit
        self._window = window
        self._accepted = {}  # key -> list of accepted timestamps, oldest first
        self._high_water_mark = None  # largest `now` seen across all keys/methods

    def _check_monotonic(self, now):
        if self._high_water_mark is not None and now < self._high_water_mark:
            raise ValueError(
                f"now={now!r} is smaller than the largest now already seen "
                f"({self._high_water_mark!r})"
            )
        if self._high_water_mark is None or now > self._high_water_mark:
            self._high_water_mark = now

    def _in_window(self, key, now):
        """Prune expired timestamps for ``key`` and return the remaining list.

        A timestamp ``t`` stays in the window iff ``now - window < t <= now``.
        """
        timestamps = self._accepted.get(key, [])
        kept = [t for t in timestamps if now - self._window < t <= now]
        if kept:
            self._accepted[key] = kept
        elif key in self._accepted:
            del self._accepted[key]
        return kept

    def allow(self, key, now):
        """Return True and record the request if fewer than ``limit`` accepted
        requests for ``key`` satisfy ``now - window < t <= now``; else False.

        Denied requests are not recorded. Raises ValueError if ``now`` is
        smaller than any ``now`` previously seen by this limiter.
        """
        self._check_monotonic(now)
        in_window = self._in_window(key, now)
        if len(in_window) < self._limit:
            in_window.append(now)
            self._accepted[key] = in_window
            return True
        return False

    def remaining(self, key, now):
        """``limit`` minus the accepted requests for ``key`` in the window (never negative)."""
        self._check_monotonic(now)
        in_window = self._in_window(key, now)
        return max(self._limit - len(in_window), 0)

    def retry_after(self, key, now):
        """0.0 if a request at ``now`` would be accepted; otherwise seconds until the
        oldest in-window accepted request expires (``oldest + window - now``).
        ``float("inf")`` when ``limit`` is 0.
        """
        self._check_monotonic(now)
        if self._limit == 0:
            return float("inf")
        in_window = self._in_window(key, now)
        if len(in_window) < self._limit:
            return 0.0
        oldest = min(in_window)
        return oldest + self._window - now
