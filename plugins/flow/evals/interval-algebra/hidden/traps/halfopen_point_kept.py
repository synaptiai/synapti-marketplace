"""Trap: lo == hi counts as non-empty when either end is closed, so (2,2]
and [2,2) survive normalize and a difference by a half-open "point" removes
a point. Masked unless degenerate half-open intervals appear."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _LoosePoints(_ref._Algebra):
    def is_empty(self, lo, hi, lo_closed, hi_closed):
        if lo > hi:
            return True
        if lo == hi:
            return not (lo_closed or hi_closed)
        return False


_A = _LoosePoints()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
