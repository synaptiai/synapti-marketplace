"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""

import numbers


def _validate_and_expand(interval):
    """Return a validated ``(lo, hi, lo_closed, hi_closed)`` 4-tuple."""
    if not isinstance(interval, tuple):
        raise ValueError(f"interval must be a tuple, got {interval!r}")

    if len(interval) == 2:
        lo, hi = interval
        lo_closed, hi_closed = True, True
    elif len(interval) == 4:
        lo, hi, lo_closed, hi_closed = interval
    else:
        raise ValueError(
            f"interval must be a 2- or 4-tuple, got {interval!r}"
        )

    if not isinstance(lo_closed, bool) or not isinstance(hi_closed, bool):
        raise ValueError(
            f"lo_closed/hi_closed must be bool, got {interval!r}"
        )

    for bound in (lo, hi):
        if bound is not None and not isinstance(bound, numbers.Number):
            raise ValueError(f"bounds must be numbers or None, got {interval!r}")
        if isinstance(bound, bool):
            # bool is technically a Number subclass in Python; reject it.
            raise ValueError(f"bounds must be numbers or None, got {interval!r}")

    if lo is None and lo_closed:
        raise ValueError(f"unbounded lo end must be open, got {interval!r}")
    if hi is None and hi_closed:
        raise ValueError(f"unbounded hi end must be open, got {interval!r}")

    return (lo, hi, lo_closed, hi_closed)


def _is_empty(lo, hi, lo_closed, hi_closed):
    if lo is not None and hi is not None:
        if lo > hi:
            return True
        if lo == hi:
            return not (lo_closed and hi_closed)
    return False


def _lo_key(lo, lo_closed):
    """Sort key for a lower bound: None (−∞) first, then by value, with a
    closed end sorting before an open end at the same value (so [x,.. comes
    before (x,.. )."""
    if lo is None:
        return (0, 0)
    return (1, lo, 0 if lo_closed else 1)


def _connects(hi1, hi1_closed, lo2, lo2_closed):
    """True if an interval ending at (hi1, hi1_closed) overlaps or touches-
    and-merges with one starting at (lo2, lo2_closed). ``hi1`` unbounded
    always connects; ``lo2`` is never unbounded here (it is never the
    second-or-later interval in a sorted sweep)."""
    if hi1 is None:
        return True
    if hi1 > lo2:
        return True
    return hi1 == lo2 and (hi1_closed or lo2_closed)


def _merge_sorted(expanded):
    """Merge a list of validated, non-empty 4-tuples into canonical form.
    Input need not be sorted."""

    def sort_key(iv):
        lo, hi, lo_closed, hi_closed = iv
        return _lo_key(lo, lo_closed)

    items = sorted(expanded, key=sort_key)

    merged = []
    for iv in items:
        lo, hi, lo_closed, hi_closed = iv
        if not merged:
            merged.append(list(iv))
            continue
        cur = merged[-1]
        cur_lo, cur_hi, cur_lo_closed, cur_hi_closed = cur
        if _connects(cur_hi, cur_hi_closed, lo, lo_closed):
            # Extend cur's upper end if this interval reaches further.
            if hi is None:
                new_hi, new_hi_closed = None, False
            elif cur_hi is None:
                new_hi, new_hi_closed = None, False
            elif hi > cur_hi:
                new_hi, new_hi_closed = hi, hi_closed
            elif hi == cur_hi:
                new_hi, new_hi_closed = hi, (cur_hi_closed or hi_closed)
            else:
                new_hi, new_hi_closed = cur_hi, cur_hi_closed
            cur[1] = new_hi
            cur[3] = new_hi_closed
        else:
            merged.append(list(iv))

    return [tuple(iv) for iv in merged]


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    expanded = []
    for interval in intervals:
        lo, hi, lo_closed, hi_closed = _validate_and_expand(interval)
        if _is_empty(lo, hi, lo_closed, hi_closed):
            continue
        expanded.append((lo, hi, lo_closed, hi_closed))

    if not expanded:
        return []

    # One sweep over the lower-bound-sorted list suffices: each step only
    # ever extends the running interval's upper end, so a point like [3,3]
    # that bridges two open neighbors is absorbed into the same running
    # interval as soon as it is reached, and the interval after it is then
    # compared against that already-extended upper end.
    return _merge_sorted(expanded)


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    return normalize(list(a) + list(b))


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    na = normalize(a)
    nb = normalize(b)
    result = []
    i = j = 0
    while i < len(na) and j < len(nb):
        a_lo, a_hi, a_lo_closed, a_hi_closed = na[i]
        b_lo, b_hi, b_lo_closed, b_hi_closed = nb[j]

        # lower bound of the overlap = the greater of the two starts
        if a_lo is None:
            lo, lo_closed = b_lo, b_lo_closed
        elif b_lo is None:
            lo, lo_closed = a_lo, a_lo_closed
        elif a_lo > b_lo:
            lo, lo_closed = a_lo, a_lo_closed
        elif b_lo > a_lo:
            lo, lo_closed = b_lo, b_lo_closed
        else:
            lo, lo_closed = a_lo, (a_lo_closed and b_lo_closed)

        # upper bound of the overlap = the lesser of the two ends
        if a_hi is None:
            hi, hi_closed = b_hi, b_hi_closed
        elif b_hi is None:
            hi, hi_closed = a_hi, a_hi_closed
        elif a_hi < b_hi:
            hi, hi_closed = a_hi, a_hi_closed
        elif b_hi < a_hi:
            hi, hi_closed = b_hi, b_hi_closed
        else:
            hi, hi_closed = a_hi, (a_hi_closed and b_hi_closed)

        if not _is_empty(lo, hi, lo_closed, hi_closed):
            result.append((lo, hi, lo_closed, hi_closed))

        # advance whichever interval ends first
        if a_hi is None:
            j += 1
        elif b_hi is None:
            i += 1
        elif a_hi < b_hi:
            i += 1
        elif b_hi < a_hi:
            j += 1
        else:
            i += 1
            j += 1

    return normalize(result)


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    na = normalize(a)
    nb = normalize(b)
    if not nb:
        return na

    result = []
    for a_lo, a_hi, a_lo_closed, a_hi_closed in na:
        # Cursor tracking the start of the not-yet-cut remainder of this
        # a-interval. nb is sorted and disjoint, so a single forward-moving
        # cursor suffices.
        cur_lo, cur_lo_closed = a_lo, a_lo_closed
        consumed = False

        for b_lo, b_hi, b_lo_closed, b_hi_closed in nb:
            # b entirely before the cursor: no effect, keep scanning.
            if b_hi is not None and cur_lo is not None:
                if b_hi < cur_lo or (b_hi == cur_lo and not (b_hi_closed and cur_lo_closed)):
                    continue

            # b entirely after a_hi: no more cuts possible for this a.
            if b_lo is not None and a_hi is not None:
                if b_lo > a_hi or (b_lo == a_hi and not (b_lo_closed and a_hi_closed)):
                    break

            # Emit the surviving piece [cur_lo, b_lo) (cut inverts b_lo's closedness).
            if b_lo is None:
                gap_nonempty = False
            elif cur_lo is not None and cur_lo > b_lo:
                gap_nonempty = False
            elif cur_lo is not None and cur_lo == b_lo:
                gap_nonempty = cur_lo_closed and not b_lo_closed
            else:
                gap_nonempty = True

            if gap_nonempty:
                piece = (cur_lo, b_lo, cur_lo_closed, not b_lo_closed)
                if not _is_empty(*piece):
                    result.append(piece)

            # Advance the cursor past b's upper end.
            if b_hi is None:
                consumed = True
                break
            cur_lo, cur_lo_closed = b_hi, not b_hi_closed

        if consumed:
            continue

        tail = (cur_lo, a_hi, cur_lo_closed, a_hi_closed)
        if not _is_empty(*tail):
            result.append(tail)

    return normalize(result)
