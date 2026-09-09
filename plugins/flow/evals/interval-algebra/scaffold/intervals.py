"""Interval algebra with independently open/closed endpoints. See ISSUE.md.

This file is the starting skeleton for the task: every function body below
raises NotImplementedError and must be replaced with a real implementation.

An interval is ``(lo, hi, lo_closed, hi_closed)``; ``(lo, hi)`` is shorthand
for the closed interval. ``None`` is an unbounded (and necessarily open)
end. Every function returns a list of 4-tuples in canonical form: empties
dropped, overlapping and touching-with-a-closed-end intervals merged,
sorted by lower bound with ``None`` first, flags as ``bool``.
"""


def normalize(intervals):
    """Return the canonical form of ``intervals`` (any order, overlaps, empties, shorthand)."""
    raise NotImplementedError


def union(a, b):
    """Canonical form of all intervals in ``a`` and ``b``."""
    raise NotImplementedError


def intersection(a, b):
    """Points in both ``a`` and ``b``; an equal endpoint is closed only if closed in both."""
    raise NotImplementedError


def difference(a, b):
    """Points in ``a`` not in ``b``; removing a closed end opens the cut, an open end leaves it closed."""
    raise NotImplementedError
