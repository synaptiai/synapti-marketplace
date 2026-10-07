"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""

import numbers


def _validate(iv):
    if not isinstance(iv, tuple):
        raise ValueError(f"interval must be a 2- or 4-tuple, got {iv!r}")
    if len(iv) == 2:
        lo, hi = iv
        lo_closed, hi_closed = True, True
    elif len(iv) == 4:
        lo, hi, lo_closed, hi_closed = iv
    else:
        raise ValueError(f"interval must be a 2- or 4-tuple, got {iv!r}")
    if not isinstance(lo_closed, bool) or not isinstance(hi_closed, bool):
        raise ValueError(f"closed flags must be bool, got {iv!r}")
    for bound in (lo, hi):
        if bound is not None and not isinstance(bound, numbers.Number):
            raise ValueError(f"bounds must be numbers or None, got {iv!r}")
    if lo is None and lo_closed:
        raise ValueError("an unbounded lower end cannot be closed")
    if hi is None and hi_closed:
        raise ValueError("an unbounded upper end cannot be closed")
    return (lo, hi, lo_closed, hi_closed)


def _is_empty(iv):
    lo, hi, lo_closed, hi_closed = iv
    if lo is None or hi is None:
        return False
    if lo > hi:
        return True
    if lo == hi:
        return not (lo_closed and hi_closed)
    return False


def _max_end(hi1, c1, hi2, c2):
    """Combine two upper bounds, taking the greater (None is +inf)."""
    if hi1 is None or hi2 is None:
        return None, False
    if hi1 > hi2:
        return hi1, c1
    if hi2 > hi1:
        return hi2, c2
    return hi1, c1 or c2


def _max_lo(lo1, c1, lo2, c2):
    """More restrictive (greater) lower bound, for intersection (None is -inf)."""
    if lo1 is None and lo2 is None:
        return None, False
    if lo1 is None:
        return lo2, c2
    if lo2 is None:
        return lo1, c1
    if lo1 > lo2:
        return lo1, c1
    if lo2 > lo1:
        return lo2, c2
    return lo1, c1 and c2


def _min_hi(hi1, c1, hi2, c2):
    """Less restrictive... i.e. smaller upper bound, for intersection (None is +inf)."""
    if hi1 is None and hi2 is None:
        return None, False
    if hi1 is None:
        return hi2, c2
    if hi2 is None:
        return hi1, c1
    if hi1 < hi2:
        return hi1, c1
    if hi2 < hi1:
        return hi2, c2
    return hi1, c1 and c2


def _overlap(a, b):
    lo_a, hi_a, lc_a, hc_a = a
    lo_b, hi_b, lc_b, hc_b = b
    lo, lo_closed = _max_lo(lo_a, lc_a, lo_b, lc_b)
    hi, hi_closed = _min_hi(hi_a, hc_a, hi_b, hc_b)
    return (lo, hi, lo_closed, hi_closed)


def _touches_or_overlaps(last_hi, last_hi_closed, lo, lo_closed):
    if last_hi is None or lo is None:
        return True
    if last_hi > lo:
        return True
    if last_hi == lo and (last_hi_closed or lo_closed):
        return True
    return False


def _same_lo(a, b):
    if a is None or b is None:
        return a is None and b is None
    return a == b


def _sort_key(iv):
    lo = iv[0]
    return (0,) if lo is None else (1, lo)


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    parsed = [_validate(iv) for iv in intervals]
    parsed = [iv for iv in parsed if not _is_empty(iv)]
    parsed.sort(key=_sort_key)

    # Fold intervals that share the exact same lower bound into one, since
    # processing them in an arbitrary (but stable) order can otherwise hide
    # a closed endpoint that would bridge an earlier gap (the "point fills
    # the gap" case).
    groups = []
    for lo, hi, lo_closed, hi_closed in parsed:
        if groups and _same_lo(groups[-1][0], lo):
            g = groups[-1]
            g[2] = g[2] or lo_closed
            g[1], g[3] = _max_end(g[1], g[3], hi, hi_closed)
        else:
            groups.append([lo, hi, lo_closed, hi_closed])

    result = []
    for g in groups:
        if result and _touches_or_overlaps(result[-1][1], result[-1][3], g[0], g[2]):
            last = result[-1]
            last[1], last[3] = _max_end(last[1], last[3], g[1], g[3])
        else:
            result.append(list(g))
    return [tuple(iv) for iv in result]


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    return normalize(list(a) + list(b))


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    A = normalize(a)
    B = normalize(b)
    result = []
    i = j = 0
    while i < len(A) and j < len(B):
        ov = _overlap(A[i], B[j])
        if not _is_empty(ov):
            result.append(ov)
        hi_a, hc_a = A[i][1], A[i][3]
        hi_b, hc_b = B[j][1], B[j][3]
        if hi_a is None and hi_b is None:
            i += 1
            j += 1
        elif hi_a is None:
            j += 1
        elif hi_b is None:
            i += 1
        elif hi_a < hi_b:
            i += 1
        elif hi_b < hi_a:
            j += 1
        else:
            i += 1
            j += 1
    return normalize(result)


def _subtract_one(iv, sub):
    ov = _overlap(iv, sub)
    if _is_empty(ov):
        return [iv]
    lo, hi, lo_closed, hi_closed = iv
    olo, ohi, olo_closed, ohi_closed = ov
    pieces = []
    # When both ends being compared are unbounded there is nothing left (or
    # right) of "infinity" to keep; building a piece would need a closed
    # None bound, which is invalid.
    if not (lo is None and olo is None):
        left = (lo, olo, lo_closed, not olo_closed)
        if not _is_empty(left):
            pieces.append(left)
    if not (hi is None and ohi is None):
        right = (ohi, hi, not ohi_closed, hi_closed)
        if not _is_empty(right):
            pieces.append(right)
    return pieces


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    pieces = normalize(a)
    for sub in normalize(b):
        next_pieces = []
        for iv in pieces:
            next_pieces.extend(_subtract_one(iv, sub))
        pieces = next_pieces
    return normalize(pieces)
