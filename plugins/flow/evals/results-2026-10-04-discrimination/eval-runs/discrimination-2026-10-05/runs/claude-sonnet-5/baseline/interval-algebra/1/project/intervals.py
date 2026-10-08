"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""

import numbers


def _parse(iv):
    if isinstance(iv, tuple) and len(iv) == 2:
        lo, hi = iv
        lo_closed, hi_closed = True, True
    elif isinstance(iv, tuple) and len(iv) == 4:
        lo, hi, lo_closed, hi_closed = iv
    else:
        raise ValueError(f"not a 2- or 4-tuple interval: {iv!r}")

    if not isinstance(lo_closed, bool) or not isinstance(hi_closed, bool):
        raise ValueError(f"interval flags must be bool: {iv!r}")

    for bound in (lo, hi):
        if bound is not None and not isinstance(bound, numbers.Number):
            raise ValueError(f"interval bound must be a number or None: {iv!r}")

    if lo is None and lo_closed:
        raise ValueError(f"unbounded lower end must be open: {iv!r}")
    if hi is None and hi_closed:
        raise ValueError(f"unbounded upper end must be open: {iv!r}")

    return (lo, hi, bool(lo_closed), bool(hi_closed))


def _is_empty(lo, hi, lo_closed, hi_closed):
    if lo is None or hi is None:
        return False
    if lo > hi:
        return True
    if lo == hi:
        return not (lo_closed and hi_closed)
    return False


def _lo_value_cmp(lo1, lo2):
    """Compare two lower bounds, treating ``None`` as -infinity."""
    if lo1 is None and lo2 is None:
        return 0
    if lo1 is None:
        return -1
    if lo2 is None:
        return 1
    if lo1 < lo2:
        return -1
    if lo1 > lo2:
        return 1
    return 0


def _hi_value_cmp(hi1, hi2):
    """Compare two upper bounds, treating ``None`` as +infinity."""
    if hi1 is None and hi2 is None:
        return 0
    if hi1 is None:
        return 1
    if hi2 is None:
        return -1
    if hi1 < hi2:
        return -1
    if hi1 > hi2:
        return 1
    return 0


def _lo_sort_key(lo):
    return (0,) if lo is None else (1, lo)


def _touches_or_overlaps(prev, iv):
    _, phi, _, phic = prev
    lo, _, loc, _ = iv
    if lo is None or phi is None:
        return True
    if phi > lo:
        return True
    if phi == lo:
        return phic or loc
    return False


def _merge_pair(iv1, iv2):
    """Union of two overlapping/touching intervals; closed if either side was closed."""
    lo1, hi1, loc1, hic1 = iv1
    lo2, hi2, loc2, hic2 = iv2

    c = _lo_value_cmp(lo1, lo2)
    if c < 0:
        lo, loc = lo1, loc1
    elif c > 0:
        lo, loc = lo2, loc2
    else:
        lo, loc = lo1, (loc1 or loc2)

    c = _hi_value_cmp(hi1, hi2)
    if c > 0:
        hi, hic = hi1, hic1
    elif c < 0:
        hi, hic = hi2, hic2
    else:
        hi, hic = hi1, (hic1 or hic2)

    return (lo, hi, loc, hic)


def _intersect_pair(iv1, iv2):
    """Intersection of two intervals, or ``None`` if they share no point."""
    lo1, hi1, loc1, hic1 = iv1
    lo2, hi2, loc2, hic2 = iv2

    c = _lo_value_cmp(lo1, lo2)
    if c > 0:
        lo, loc = lo1, loc1
    elif c < 0:
        lo, loc = lo2, loc2
    else:
        lo, loc = lo1, (loc1 and loc2)

    c = _hi_value_cmp(hi1, hi2)
    if c < 0:
        hi, hic = hi1, hic1
    elif c > 0:
        hi, hic = hi2, hic2
    else:
        hi, hic = hi1, (hic1 and hic2)

    if _is_empty(lo, hi, loc, hic):
        return None
    return (lo, hi, loc, hic)


def _subtract_one(piece, cut):
    """``piece`` minus ``cut`` (a single interval), as a list of 0-2 pieces."""
    if _intersect_pair(piece, cut) is None:
        return [piece]

    p_lo, p_hi, p_loc, p_hic = piece
    c_lo, c_hi, c_loc, c_hic = cut
    out = []

    if c_lo is not None:
        left = (p_lo, c_lo, p_loc, not c_loc)
        if not _is_empty(*left):
            out.append(left)

    if c_hi is not None:
        right = (c_hi, p_hi, not c_hic, p_hic)
        if not _is_empty(*right):
            out.append(right)

    return out


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    parsed = [_parse(iv) for iv in intervals]
    nonempty = [iv for iv in parsed if not _is_empty(*iv)]
    nonempty.sort(key=lambda iv: _lo_sort_key(iv[0]))

    result = []
    for iv in nonempty:
        if result and _touches_or_overlaps(result[-1], iv):
            result[-1] = _merge_pair(result[-1], iv)
        else:
            result.append(iv)
    return result


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    return normalize(list(a) + list(b))


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    na = normalize(a)
    nb = normalize(b)

    pieces = []
    for iv1 in na:
        for iv2 in nb:
            r = _intersect_pair(iv1, iv2)
            if r is not None:
                pieces.append(r)
    return normalize(pieces)


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    na = normalize(a)
    nb = normalize(b)
    if not nb:
        return na

    pieces = list(na)
    for cut in nb:
        next_pieces = []
        for piece in pieces:
            next_pieces.extend(_subtract_one(piece, cut))
        pieces = next_pieces
    return normalize(pieces)
