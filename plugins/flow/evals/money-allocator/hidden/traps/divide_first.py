"""Trap: floor(units / total_weight) * weight — division before multiplication — with the
integer-division remainder handed out round-robin from index 0.
Masked when total_units is a multiple of the weight sum."""
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
    per_weight = Fraction(total_units) / total_weight
    per_weight = per_weight.numerator // per_weight.denominator
    shares = [int(per_weight * w) for w in ws]
    leftover = total_units - sum(shares)
    for k in range(leftover):
        shares[k % len(ws)] += 1
    unit = Decimal(1).scaleb(-places)
    return [Decimal(s).scaleb(-places).quantize(unit) for s in shares]
