"""Trap: zero and negative weights accepted (and empty lists, negative amounts, floats).
Masked whenever inputs are well-formed."""
from reference_impl import *  # noqa: F401,F403
from decimal import Decimal
from fractions import Fraction


def allocate(amount, weights, places=2):
    amount = Decimal(str(amount))
    total_units = int(amount.scaleb(places))
    ws = [Fraction(Decimal(str(w))) for w in weights]
    total_weight = sum(ws) or Fraction(1)
    shares, remainders = [], []
    for w in ws:
        exact = Fraction(total_units) * w / total_weight
        floor = exact.numerator // exact.denominator
        shares.append(floor)
        remainders.append(exact - floor)
    leftover = total_units - sum(shares)
    order = sorted(range(len(ws)), key=lambda i: remainders[i], reverse=True)
    for i in order[:max(leftover, 0)]:
        shares[i] += 1
    unit = Decimal(1).scaleb(-places)
    return [Decimal(s).scaleb(-places).quantize(unit) for s in shares]
