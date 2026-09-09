"""Trap: remainder ties broken in favour of the larger weight.
Masked when tied entries have equal weights."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref
from decimal import Decimal
from fractions import Fraction


def allocate(amount, weights, places=2):
    _ref.allocate(amount, weights, places)  # keep the reference's validation
    amount = _ref._to_decimal(amount, "amount")
    total_units = int(amount.scaleb(places))
    ws = [Fraction(_ref._to_decimal(w, "weight")) for w in weights]
    total_weight = sum(ws)
    shares, remainders = [], []
    for w in ws:
        exact = Fraction(total_units) * w / total_weight
        floor = exact.numerator // exact.denominator
        shares.append(floor)
        remainders.append(exact - floor)
    leftover = total_units - sum(shares)
    order = sorted(range(len(ws)), key=lambda i: (remainders[i], ws[i]), reverse=True)
    for i in order[:leftover]:
        shares[i] += 1
    unit = Decimal(1).scaleb(-places)
    return [Decimal(s).scaleb(-places).quantize(unit) for s in shares]
