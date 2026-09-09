"""Trap: no sort; only neighbours in input order are merged and the output
keeps input order. Masked when inputs arrive sorted."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _Unsorted(_ref._Algebra):
    def sort(self, ivs):
        return list(ivs)


_A = _Unsorted()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
