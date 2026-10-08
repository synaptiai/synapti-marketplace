"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""

from decimal import Decimal
from fractions import Fraction

_NUMBER_TYPES = (int, float, Fraction, Decimal)


def _is_number(value):
    return isinstance(value, _NUMBER_TYPES) and not isinstance(value, bool)


def _parse(iv):
    if not isinstance(iv, tuple) or len(iv) not in (2, 4):
        raise ValueError("interval must be a 2-tuple or 4-tuple: {!r}".format(iv))

    if len(iv) == 2:
        lo, hi = iv
        lo_closed, hi_closed = True, True
    else:
        lo, hi, lo_closed, hi_closed = iv

    if type(lo_closed) is not bool or type(hi_closed) is not bool:
        raise ValueError("closed flags must be bool: {!r}".format(iv))

    for bound in (lo, hi):
        if bound is not None and not _is_number(bound):
            raise ValueError("bound must be a number or None: {!r}".format(iv))

    if lo is None and lo_closed:
        raise ValueError("unbounded lower end cannot be closed: {!r}".format(iv))
    if hi is None and hi_closed:
        raise ValueError("unbounded upper end cannot be closed: {!r}".format(iv))

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


def _lo_lt(a, b):
    """True if lower bound a < lower bound b, treating None as -inf."""
    if a is None and b is None:
        return False
    if a is None:
        return True
    if b is None:
        return False
    return a < b


def _lo_eq(a, b):
    if a is None and b is None:
        return True
    if a is None or b is None:
        return False
    return a == b


def _hi_lt(a, b):
    """True if upper bound a < upper bound b, treating None as +inf."""
    if a is None and b is None:
        return False
    if a is None:
        return False
    if b is None:
        return True
    return a < b


def _lo_sortkey(lo):
    return (0,) if lo is None else (1, lo)


def _should_merge(cur, nxt):
    cur_hi = cur[1]
    nlo = nxt[0]
    if cur_hi is None:
        return True
    if nlo is None:
        return True
    if nlo < cur_hi:
        return True
    if nlo == cur_hi:
        return cur[3] or nxt[2]
    return False


def _merge_into(cur, nxt):
    nlo, nhi, nlc, nhc = nxt

    if _lo_eq(cur[0], nlo):
        cur[2] = cur[2] or nlc

    if cur[1] is None:
        pass
    elif nhi is None:
        cur[1] = None
        cur[3] = False
    elif nhi > cur[1]:
        cur[1] = nhi
        cur[3] = nhc
    elif nhi == cur[1]:
        cur[3] = cur[3] or nhc


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    parsed = [_parse(iv) for iv in intervals]
    kept = [iv for iv in parsed if not _is_empty(iv)]
    if not kept:
        return []

    kept.sort(key=lambda iv: _lo_sortkey(iv[0]))

    merged = []
    cur = list(kept[0])
    for nxt in kept[1:]:
        if _should_merge(cur, nxt):
            _merge_into(cur, nxt)
        else:
            merged.append(tuple(cur))
            cur = list(nxt)
    merged.append(tuple(cur))
    return merged


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    return normalize(list(a) + list(b))


def _pair_intersect(a, b):
    """Intersection of two single (already-parsed) intervals, or None if empty."""
    alo, ahi, alc, ahc = a
    blo, bhi, blc, bhc = b

    if _lo_lt(alo, blo):
        lo, lo_closed = blo, blc
    elif _lo_lt(blo, alo):
        lo, lo_closed = alo, alc
    else:
        lo, lo_closed = alo, (alc and blc)

    if _hi_lt(ahi, bhi):
        hi, hi_closed = ahi, ahc
    elif _hi_lt(bhi, ahi):
        hi, hi_closed = bhi, bhc
    else:
        hi, hi_closed = ahi, (ahc and bhc)

    candidate = (lo, hi, lo_closed, hi_closed)
    if _is_empty(candidate):
        return None
    return candidate


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    A = normalize(a)
    B = normalize(b)

    result = []
    i = j = 0
    while i < len(A) and j < len(B):
        cand = _pair_intersect(A[i], B[j])
        if cand is not None:
            result.append(cand)

        if _hi_lt(A[i][1], B[j][1]):
            i += 1
        elif _hi_lt(B[j][1], A[i][1]):
            j += 1
        else:
            i += 1
            j += 1

    return normalize(result)


def _subtract_one(a, b):
    """Subtract single interval ``b`` from single interval ``a``; returns a list of pieces."""
    overlap = _pair_intersect(a, b)
    if overlap is None:
        return [a]

    ilo, ihi, ilo_closed, ihi_closed = overlap
    pieces = []
    if ilo is not None:
        pieces.append((a[0], ilo, a[2], not ilo_closed))
    if ihi is not None:
        pieces.append((ihi, a[1], not ihi_closed, a[3]))
    return pieces


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    A = normalize(a)
    B = normalize(b)
    if not B:
        return A

    pieces = A
    for b_iv in B:
        next_pieces = []
        for piece in pieces:
            next_pieces.extend(_subtract_one(piece, b_iv))
        pieces = next_pieces

    return normalize(pieces)
