"""Per-key sliding-window rate limiter driven by caller-supplied timestamps.

See ISSUE.md for the exact semantics. This file is the starting skeleton for
the task: every method body below raises NotImplementedError and must be
replaced with a real implementation.
"""


class SlidingWindowLimiter:
    """At most ``limit`` accepted requests per key within any ``window`` seconds."""

    def __init__(self, limit, window):
        """``limit`` is an int >= 0; ``window`` is a number > 0. Else ValueError."""
        if not isinstance(limit, int) or limit < 0:
            raise ValueError("limit must be an int >= 0")
        if not isinstance(window, (int, float)) or window <= 0:
            raise ValueError("window must be a number > 0")
        self.limit = limit
        self.window = window
        # key -> list of accepted timestamps for that key, ascending order.
        self._accepted = {}
        # Largest `now` seen so far across all keys and methods (global
        # monotonic watermark). None until the first call.
        self._max_now_seen = None

    def _check_monotonic(self, now):
        """Raise ValueError if ``now`` is smaller than any ``now`` this
        limiter has seen so far, across all keys and methods. Equal is
        fine. Updates the global watermark otherwise."""
        if self._max_now_seen is not None and now < self._max_now_seen:
            raise ValueError(
                "now must be >= the largest now previously seen by this limiter"
            )
        if self._max_now_seen is None or now > self._max_now_seen:
            self._max_now_seen = now

    def _in_window(self, key, now):
        """Prune (and return, ascending) ``key``'s accepted timestamps that
        still satisfy ``now - window < t <= now``."""
        lst = self._accepted.get(key)
        if not lst:
            return []
        cutoff = now - self.window
        i = 0
        while i < len(lst) and lst[i] <= cutoff:
            i += 1
        if i:
            del lst[:i]
        return lst

    def allow(self, key, now):
        """Return True and record the request if fewer than ``limit`` accepted
        requests for ``key`` satisfy ``now - window < t <= now``; else False.

        Denied requests are not recorded. Raises ValueError if ``now`` is
        smaller than any ``now`` previously seen by this limiter.
        """
        self._check_monotonic(now)
        lst = self._accepted.setdefault(key, [])
        self._in_window(key, now)
        if len(lst) < self.limit:
            lst.append(now)
            return True
        return False

    def remaining(self, key, now):
        """``limit`` minus the accepted requests for ``key`` in the window (never negative)."""
        self._check_monotonic(now)
        lst = self._accepted.get(key)
        if lst is None:
            return self.limit
        count = len(self._in_window(key, now))
        return max(self.limit - count, 0)

    def retry_after(self, key, now):
        """0.0 if a request at ``now`` would be accepted; otherwise seconds until the
        oldest in-window accepted request expires (``oldest + window - now``).
        ``float("inf")`` when ``limit`` is 0.
        """
        self._check_monotonic(now)
        if self.limit == 0:
            return float("inf")
        lst = self._in_window(key, now)
        if len(lst) < self.limit:
            return 0.0
        oldest = lst[0]
        return oldest + self.window - now
