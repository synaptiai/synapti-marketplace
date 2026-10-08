"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""

import functools
import numbers


def _parse(interval):
    """Parse a 2- or 4-tuple into (lo, hi, lo_closed, hi_closed), validating
    shape and types per ISSUE.md Representation."""
    if not isinstance(interval, tuple) or len(interval) not in (2, 4):
        raise ValueError(f"interval must be a 2- or 4-tuple, got {interval!r}")

    if len(interval) == 2:
        lo, hi = interval
        lo_closed, hi_closed = True, True
    else:
        lo, hi, lo_closed, hi_closed = interval

    if not isinstance(lo_closed, bool) or not isinstance(hi_closed, bool):
        raise ValueError(f"lo_closed/hi_closed must be bool, got {interval!r}")
    for bound in (lo, hi):
        if bound is not None and not isinstance(bound, numbers.Number):
            raise ValueError(f"bounds must be a number or None, got {interval!r}")
    if lo is None and lo_closed:
        raise ValueError("an unbounded lo (None) must be open (lo_closed=False)")
    if hi is None and hi_closed:
        raise ValueError("an unbounded hi (None) must be open (hi_closed=False)")

    return lo, hi, lo_closed, hi_closed


def _lo_cmp(x, y):
    """Compare two lower-bound values; ``None`` is -infinity."""
    if x is None and y is None:
        return 0
    if x is None:
        return -1
    if y is None:
        return 1
    return (x > y) - (x < y)


def _hi_cmp(x, y):
    """Compare two upper-bound values; ``None`` is +infinity."""
    if x is None and y is None:
        return 0
    if x is None:
        return 1
    if y is None:
        return -1
    return (x > y) - (x < y)


def _lh_cmp(lo, hi):
    """Compare a lower-bound value against an upper-bound value on the real
    line (``None`` lo is -infinity, ``None`` hi is +infinity)."""
    if lo is None or hi is None:
        return -1
    return (lo > hi) - (lo < hi)


def _is_empty(lo, hi, lo_closed, hi_closed):
    """True if the interval contains no points (ISSUE.md Rule #1)."""
    if lo is not None and hi is not None:
        if lo > hi:
            return True
        if lo == hi and not (lo_closed and hi_closed):
            return True
    return False


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    parsed = [_parse(iv) for iv in intervals]
    parsed = [p for p in parsed if not _is_empty(*p)]
    parsed.sort(key=functools.cmp_to_key(lambda p, q: _lo_cmp(p[0], q[0])))

    result = []
    for lo, hi, lo_closed, hi_closed in parsed:
        if result:
            clo, chi, clo_closed, chi_closed = result[-1]
            cmp = _lh_cmp(lo, chi)
            touches_or_overlaps = cmp < 0 or (cmp == 0 and (chi_closed or lo_closed))
            if touches_or_overlaps:
                if _lo_cmp(lo, clo) == 0:
                    clo_closed = clo_closed or lo_closed
                hcmp = _hi_cmp(hi, chi)
                if hcmp > 0:
                    chi, chi_closed = hi, hi_closed
                elif hcmp == 0:
                    chi_closed = chi_closed or hi_closed
                result[-1] = (clo, chi, bool(clo_closed), bool(chi_closed))
                continue
        result.append((lo, hi, bool(lo_closed), bool(hi_closed)))
    return result


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    return normalize(list(a) + list(b))


def _overlap(lo, hi, lo_closed, hi_closed, blo, bhi, blo_closed, bhi_closed):
    """The intersection of one interval with another: closed at a shared
    endpoint only if both inputs are closed there (ISSUE.md Rule #6)."""
    lcmp = _lo_cmp(lo, blo)
    if lcmp > 0:
        ov_lo, ov_lo_closed = lo, lo_closed
    elif lcmp < 0:
        ov_lo, ov_lo_closed = blo, blo_closed
    else:
        ov_lo, ov_lo_closed = lo, lo_closed and blo_closed

    hcmp = _hi_cmp(hi, bhi)
    if hcmp < 0:
        ov_hi, ov_hi_closed = hi, hi_closed
    elif hcmp > 0:
        ov_hi, ov_hi_closed = bhi, bhi_closed
    else:
        ov_hi, ov_hi_closed = hi, hi_closed and bhi_closed

    return ov_lo, ov_hi, ov_lo_closed, ov_hi_closed, hcmp


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    na = normalize(a)
    nb = normalize(b)
    result = []
    i = j = 0
    while i < len(na) and j < len(nb):
        alo, ahi, alo_closed, ahi_closed = na[i]
        blo, bhi, blo_closed, bhi_closed = nb[j]

        lo, hi, lo_closed, hi_closed, hcmp = _overlap(
            alo, ahi, alo_closed, ahi_closed, blo, bhi, blo_closed, bhi_closed
        )
        if not _is_empty(lo, hi, lo_closed, hi_closed):
            result.append((lo, hi, bool(lo_closed), bool(hi_closed)))

        if hcmp < 0:
            i += 1
        elif hcmp > 0:
            j += 1
        else:
            i += 1
            j += 1
    return result


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    pieces = normalize(a)
    for blo, bhi, blo_closed, bhi_closed in normalize(b):
        new_pieces = []
        for lo, hi, lo_closed, hi_closed in pieces:
            # overlap = piece ∩ (blo, bhi, blo_closed, bhi_closed). piece \ b
            # is then exactly piece \ overlap, since overlap is already a
            # subset of piece.
            ov_lo, ov_hi, ov_lo_closed, ov_hi_closed, _ = _overlap(
                lo, hi, lo_closed, hi_closed, blo, bhi, blo_closed, bhi_closed
            )
            if _is_empty(ov_lo, ov_hi, ov_lo_closed, ov_hi_closed):
                new_pieces.append((lo, hi, lo_closed, hi_closed))
                continue

            left = (lo, ov_lo, lo_closed, not ov_lo_closed)
            if not _is_empty(*left):
                new_pieces.append(left)
            right = (ov_hi, hi, not ov_hi_closed, hi_closed)
            if not _is_empty(*right):
                new_pieces.append(right)
        pieces = new_pieces
    return normalize(pieces)
