"""Trap: at an equal endpoint the intersection is closed when either input is
closed (or instead of and). Masked when endpoints differ."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _OrFlags(_ref._Algebra):
    def combine_flags(self, x, y):
        return x or y


_A = _OrFlags()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
