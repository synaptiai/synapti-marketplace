"""Trap: lo == hi is always empty, so the closed point [3,3] disappears from
normalize, intersection ([1,3] ∩ [3,5]) and difference results. Masked unless
a point interval appears."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _NoPoints(_ref._Algebra):
    def is_empty(self, lo, hi, lo_closed, hi_closed):
        return lo >= hi


_A = _NoPoints()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
