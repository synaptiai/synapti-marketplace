"""Trap: closed unbounded ends and non-bool flags are accepted (flags coerced
with bool()). Masked by well-formed input."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _Lenient(_ref._Algebra):
    def validate_bounds(self, item, lo, hi, lo_closed, hi_closed):
        return None

    def parse(self, item):
        if isinstance(item, (tuple, list)) and len(item) == 4:
            item = (item[0], item[1], bool(item[2]), bool(item[3]))
        return _ref._Algebra.parse(self, item)


_A = _Lenient()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
