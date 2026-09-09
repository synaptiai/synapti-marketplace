"""Trap: only strictly overlapping intervals (hi1 > lo2) merge; [1,3] + [3,5]
stays two intervals. Masked when inputs overlap by more than a point."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _StrictOverlap(_ref._Algebra):
    def touching_merges(self, hi_closed, lo_closed):
        return False


_A = _StrictOverlap()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
