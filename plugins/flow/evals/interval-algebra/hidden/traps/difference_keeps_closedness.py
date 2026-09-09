"""Trap: the complement keeps the subtrahend's closedness instead of flipping
it, so [1,5] − [2,3] gives [1,2] + [3,5]. Masked when the subtrahend's ends
are open."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _NoFlip(_ref._Algebra):
    def flip(self, closed):
        return closed


_A = _NoFlip()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
