"""Trap: bounds are converted to float internally, so Fraction and Decimal
values come back changed. Masked while tests use ints."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _Floats(_ref._Algebra):
    def parse(self, item):
        lo, hi, lc, hc = _ref._Algebra.parse(self, item)
        return (float(lo), float(hi), lc, hc)


_A = _Floats()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
