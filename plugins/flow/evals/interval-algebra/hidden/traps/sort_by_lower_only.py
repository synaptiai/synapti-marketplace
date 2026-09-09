"""Trap: the sweep sorts by lower bound only (input order on ties), so a
closed point [3,3] listed after (3,5] is visited after it and the gap
between [1,3) and (3,5] is never closed. Seen in the calibration baseline
runs. Masked when equal lower bounds arrive closed-first."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _LowerOnly(_ref._Algebra):
    def sort(self, ivs):
        return sorted(ivs, key=lambda iv: iv[0])


_A = _LowerOnly()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
