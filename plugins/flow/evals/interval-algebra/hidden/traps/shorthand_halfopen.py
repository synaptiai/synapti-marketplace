"""Trap: the 2-tuple shorthand is read as the half-open [lo, hi) like
Python's range. Masked when tests use 4-tuples only."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _HalfOpenShorthand(_ref._Algebra):
    def parse(self, item):
        if isinstance(item, (tuple, list)) and len(item) == 2:
            item = (item[0], item[1], True, False)
        return _ref._Algebra.parse(self, item)


_A = _HalfOpenShorthand()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
