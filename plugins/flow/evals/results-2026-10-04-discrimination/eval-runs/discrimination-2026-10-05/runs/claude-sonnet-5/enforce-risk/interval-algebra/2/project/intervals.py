"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

This file is the starting skeleton for the task: every function body below
raises NotImplementedError and must be replaced with a real implementation.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""
import numbers


def _validate_bound(value):
    if value is None:
        return
    if isinstance(value, bool) or not isinstance(value, numbers.Number):
        raise ValueError(f"bound must be a number or None, got {value!r}")


def _validate_flag(flag, name):
    if not isinstance(flag, bool):
        raise ValueError(f"{name} must be a bool, got {flag!r}")


def _coerce(interval):
    """Expand shorthand and return a validated ``(lo, hi, lo_closed, hi_closed)`` tuple."""
    if isinstance(interval, tuple) and len(interval) == 2:
        lo, hi = interval
        lo_closed, hi_closed = True, True
    elif isinstance(interval, tuple) and len(interval) == 4:
        lo, hi, lo_closed, hi_closed = interval
    else:
        raise ValueError(f"interval must be a 2- or 4-tuple, got {interval!r}")

    _validate_flag(lo_closed, "lo_closed")
    _validate_flag(hi_closed, "hi_closed")
    _validate_bound(lo)
    _validate_bound(hi)
    if lo is None and lo_closed:
        raise ValueError("unbounded lower end (None) must be open")
    if hi is None and hi_closed:
        raise ValueError("unbounded upper end (None) must be open")

    return (lo, hi, lo_closed, hi_closed)


def _is_empty(lo, hi, lo_closed, hi_closed):
    lo_k, hi_k = _lo_key(lo), _hi_key(hi)
    if lo_k > hi_k:
        return True
    if lo_k == hi_k:
        return not (lo_closed and hi_closed)
    return False


def _lo_key(lo):
    """Sortable/comparable value for a lower bound; unbounded is -infinity."""
    return float("-inf") if lo is None else lo


def _hi_key(hi):
    """Sortable/comparable value for an upper bound; unbounded is +infinity."""
    return float("inf") if hi is None else hi


def _touches_or_overlaps(prev, iv):
    """True if ``iv`` overlaps ``prev`` or touches it at a closed end."""
    prev_hi, iv_lo = _hi_key(prev[1]), _lo_key(iv[0])
    if iv_lo < prev_hi:
        return True
    return iv_lo == prev_hi and (prev[3] or iv[2])


def _merge_into(prev, iv):
    """Return the merge of ``prev`` and the overlapping/touching ``iv``."""
    lo, hi, lo_closed, hi_closed = prev
    if _lo_key(iv[0]) == _lo_key(lo):
        lo_closed = lo_closed or iv[2]
    if _hi_key(iv[1]) > _hi_key(hi):
        hi, hi_closed = iv[1], iv[3]
    elif _hi_key(iv[1]) == _hi_key(hi):
        hi_closed = hi_closed or iv[3]
    return (lo, hi, lo_closed, hi_closed)


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    coerced = [_coerce(iv) for iv in intervals]
    kept = [iv for iv in coerced if not _is_empty(*iv)]
    kept.sort(key=lambda iv: _lo_key(iv[0]))
    merged = []
    for iv in kept:
        if merged and _touches_or_overlaps(merged[-1], iv):
            merged[-1] = _merge_into(merged[-1], iv)
        else:
            merged.append(iv)
    return merged


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    return normalize(list(a) + list(b))


def _pair_intersect(iv1, iv2):
    """Intersection of two single (coerced) intervals, or ``None`` if empty."""
    lo1, hi1, lo1_closed, hi1_closed = iv1
    lo2, hi2, lo2_closed, hi2_closed = iv2

    if _lo_key(lo1) >= _lo_key(lo2):
        lo, lo_closed = lo1, lo1_closed
    else:
        lo, lo_closed = lo2, lo2_closed
    if _lo_key(lo1) == _lo_key(lo2):
        lo_closed = lo1_closed and lo2_closed

    if _hi_key(hi1) <= _hi_key(hi2):
        hi, hi_closed = hi1, hi1_closed
    else:
        hi, hi_closed = hi2, hi2_closed
    if _hi_key(hi1) == _hi_key(hi2):
        hi_closed = hi1_closed and hi2_closed

    if _is_empty(lo, hi, lo_closed, hi_closed):
        return None
    return (lo, hi, lo_closed, hi_closed)


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    norm_a = normalize(a)
    norm_b = normalize(b)
    result = []
    for iv1 in norm_a:
        for iv2 in norm_b:
            pair = _pair_intersect(iv1, iv2)
            if pair is not None:
                result.append(pair)
    return normalize(result)


def _subtract_one(piece, cut):
    """Subtract a single ``cut`` interval from ``piece``; removing a closed
    end opens the remaining cut, removing an open end leaves it closed."""
    overlap = _pair_intersect(piece, cut)
    if overlap is None:
        return [piece]

    lo, hi, lo_closed, hi_closed = piece
    ov_lo, ov_hi, ov_lo_closed, ov_hi_closed = overlap
    pieces = []

    if _lo_key(lo) < _lo_key(ov_lo):
        pieces.append((lo, ov_lo, lo_closed, not ov_lo_closed))
    elif _lo_key(lo) == _lo_key(ov_lo) and lo_closed and not ov_lo_closed:
        pieces.append((lo, lo, True, True))

    if _hi_key(ov_hi) < _hi_key(hi):
        pieces.append((ov_hi, hi, not ov_hi_closed, hi_closed))
    elif _hi_key(ov_hi) == _hi_key(hi) and hi_closed and not ov_hi_closed:
        pieces.append((hi, hi, True, True))

    return pieces


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    pieces = normalize(a)
    for cut in normalize(b):
        next_pieces = []
        for piece in pieces:
            next_pieces.extend(_subtract_one(piece, cut))
        pieces = next_pieces
    return normalize(pieces)
