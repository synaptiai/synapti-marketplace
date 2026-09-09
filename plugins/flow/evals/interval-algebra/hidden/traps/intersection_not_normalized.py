"""Trap: intersection is the raw pairwise product of the inputs, neither the
inputs nor the result normalized, so [1,5] ∩ ([1,2] + [2,5]) comes back as
two intervals. Masked when both inputs are already canonical."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _RawPairs(_ref._Algebra):
    def intersection(self, a, b):
        return self.export(self.pairwise(self.parse_all(a), self.parse_all(b)))


_A = _RawPairs()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
