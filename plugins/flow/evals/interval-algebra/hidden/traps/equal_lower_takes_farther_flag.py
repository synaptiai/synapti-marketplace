"""Trap: when two merged intervals share a lower bound, the one reaching
farther supplies both flags instead of the lower flags being OR-ed, so
[1,2] + (1,5) gives (1,5) rather than [1,5). Seen (combined with a
lower-bound-only sort) in the calibration baseline runs. Masked when merged
intervals never share a lower bound."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


class _FartherFlag(_ref._Algebra):
    def merge(self, ivs):
        out = []
        for lo, hi, lc, hc in self.sort(ivs):
            if out:
                plo, phi, plc, phc = out[-1]
                if phi > lo or (phi == lo and self.touching_merges(phc, lc)):
                    if hi > phi:
                        phi, phc = hi, hc
                        if lo == plo:
                            plc = lc
                    elif hi == phi:
                        phc = phc or hc
                    out[-1] = (plo, phi, plc, phc)
                    continue
            out.append((lo, hi, lc, hc))
        return out


_A = _FartherFlag()
normalize, union, intersection, difference = _A.normalize, _A.union, _A.intersection, _A.difference
