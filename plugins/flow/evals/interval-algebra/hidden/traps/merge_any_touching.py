"""Trap: intervals that touch (hi1 == lo2) always merge, even when both ends
at the meeting point are open, so [1,3) + (3,5] becomes [1,5]. Masked when a
closed end meets the point."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _AnyTouch(_ref._Algebra):
    def touching_merges(self, hi_closed, lo_closed):
        return True


_A = _AnyTouch()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
