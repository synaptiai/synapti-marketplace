"""Reference implementation of the interval algebra (scaffold/ISSUE.md).

Written from the spec and verified by hidden/test_hidden.py. The `_Algebra`
class exists so each trap variant under hidden/traps/ can override exactly
one rule; the public surface is `normalize`, `union`, `intersection` and
`difference`.
"""

_NEG = float("-inf")
_POS = float("inf")


class _Algebra(object):

    # -- parsing ---------------------------------------------------------------
    def parse(self, item):
        """Return (lo, hi, lo_closed, hi_closed) with +-inf for None, or raise ValueError."""
        if isinstance(item, (str, bytes)) or not isinstance(item, (tuple, list)):
            raise ValueError("interval must be a 2- or 4-tuple: %r" % (item,))
        if len(item) == 2:
            lo, hi = item
            lo_closed = hi_closed = True
        elif len(item) == 4:
            lo, hi, lo_closed, hi_closed = item
        else:
            raise ValueError("interval must be a 2- or 4-tuple: %r" % (item,))
        for flag in (lo_closed, hi_closed):
            if not isinstance(flag, bool):
                raise ValueError("closed flags must be bool: %r" % (item,))
        self.validate_bounds(item, lo, hi, lo_closed, hi_closed)
        for value in (lo, hi):
            if value is not None and (isinstance(value, bool) or not self.is_number(value)):
                raise ValueError("bounds must be numbers or None: %r" % (item,))
        return (_NEG if lo is None else lo, _POS if hi is None else hi, lo_closed, hi_closed)

    def validate_bounds(self, item, lo, hi, lo_closed, hi_closed):
        if lo is None and lo_closed:
            raise ValueError("an unbounded end must be open: %r" % (item,))
        if hi is None and hi_closed:
            raise ValueError("an unbounded end must be open: %r" % (item,))

    @staticmethod
    def is_number(value):
        try:
            value < value
            value + 0
        except TypeError:
            return False
        return True

    def is_empty(self, lo, hi, lo_closed, hi_closed):
        if lo > hi:
            return True
        if lo == hi:
            return not (lo_closed and hi_closed)
        return False

    def parse_all(self, intervals):
        if isinstance(intervals, (str, bytes)) or not hasattr(intervals, "__iter__"):
            raise ValueError("expected a sequence of intervals")
        out = []
        for item in intervals:
            iv = self.parse(item)
            if not self.is_empty(*iv):
                out.append(iv)
        return out

    # -- canonical form ----------------------------------------------------------
    def sort(self, ivs):
        return sorted(ivs, key=lambda iv: (iv[0], not iv[2]))

    def touching_merges(self, hi_closed, lo_closed):
        """[a,b] meets [b,c] when at least one of the two ends at b is closed."""
        return hi_closed or lo_closed

    def merge(self, ivs):
        out = []
        for lo, hi, lc, hc in self.sort(ivs):
            if out:
                plo, phi, plc, phc = out[-1]
                if phi > lo or (phi == lo and self.touching_merges(phc, lc)):
                    if hi > phi:
                        phi, phc = hi, hc
                    elif hi == phi:
                        phc = phc or hc
                    if lo == plo:
                        plc = plc or lc
                    out[-1] = (plo, phi, plc, phc)
                    continue
            out.append((lo, hi, lc, hc))
        return out

    def export(self, ivs):
        return [(None if lo == _NEG else lo, None if hi == _POS else hi, bool(lc), bool(hc)) for lo, hi, lc, hc in ivs]

    def normalize(self, intervals):
        return self.export(self.merge(self.parse_all(intervals)))

    # -- operations --------------------------------------------------------------
    def intersect_two(self, a, b):
        lo, lc = self.max_lower(a, b)
        hi, hc = self.min_upper(a, b)
        iv = (lo, hi, lc, hc)
        return None if self.is_empty(*iv) else iv

    def max_lower(self, a, b):
        if a[0] > b[0]:
            return a[0], a[2]
        if b[0] > a[0]:
            return b[0], b[2]
        return a[0], self.combine_flags(a[2], b[2])

    def min_upper(self, a, b):
        if a[1] < b[1]:
            return a[1], a[3]
        if b[1] < a[1]:
            return b[1], b[3]
        return a[1], self.combine_flags(a[3], b[3])

    def combine_flags(self, x, y):
        return x and y

    def union(self, a, b):
        return self.export(self.merge(self.parse_all(a) + self.parse_all(b)))

    def intersection(self, a, b):
        return self.export(self.merge(self.pairwise(self.merge(self.parse_all(a)), self.merge(self.parse_all(b)))))

    def pairwise(self, xs, ys):
        out = []
        for x in xs:
            for y in ys:
                iv = self.intersect_two(x, y)
                if iv is not None:
                    out.append(iv)
        return out

    def complement(self, ivs):
        """Gaps of a merged, sorted list; the complement's ends flip closedness."""
        out = []
        prev_hi, prev_hc = _NEG, False
        for lo, hi, lc, hc in ivs:
            gap = (prev_hi, lo, self.flip(prev_hc), self.flip(lc))
            if not self.is_empty(*gap):
                out.append(gap)
            prev_hi, prev_hc = hi, hc
        gap = (prev_hi, _POS, self.flip(prev_hc), False)
        if not self.is_empty(*gap):
            out.append(gap)
        return out

    def flip(self, closed):
        return not closed

    def difference(self, a, b):
        left = self.merge(self.parse_all(a))
        right = self.merge(self.parse_all(b))
        return self.export(self.merge(self.pairwise(left, self.complement(right))))


_ALGEBRA = _Algebra()


def normalize(intervals):
    """Canonical form: empties dropped, overlapping/touching merged, sorted by lower bound."""
    return _ALGEBRA.normalize(intervals)


def union(a, b):
    return _ALGEBRA.union(a, b)


def intersection(a, b):
    return _ALGEBRA.intersection(a, b)


def difference(a, b):
    return _ALGEBRA.difference(a, b)
