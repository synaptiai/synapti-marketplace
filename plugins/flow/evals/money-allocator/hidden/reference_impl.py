"""Reference implementation of the largest-remainder money allocator (spec: scaffold/ISSUE.md).

The hidden suite (hidden/test_hidden.py) was written from the spec and then
checked against this file. Keep the two in sync.
"""
from decimal import Decimal
from fractions import Fraction


def _to_decimal(value, what):
    if isinstance(value, bool) or isinstance(value, float):
        raise TypeError("%s must be int, str or Decimal, not %s" % (what, type(value).__name__))
    if isinstance(value, Decimal):
        return value
    if isinstance(value, (int, str)):
        return Decimal(value)
    raise TypeError("%s must be int, str or Decimal, not %s" % (what, type(value).__name__))


def allocate(amount, weights, places=2):
    if isinstance(places, bool) or not isinstance(places, int) or places < 0:
        raise ValueError("places must be a non-negative integer")
    amount = _to_decimal(amount, "amount")
    if not amount.is_finite():
        raise ValueError("amount must be finite")
    if amount < 0:
        raise ValueError("amount must not be negative")
    units = amount.scaleb(places)
    if units != units.to_integral_value():
        raise ValueError("amount has more than %d decimal places" % places)
    total_units = int(units)

    weights = list(weights)
    if not weights:
        raise ValueError("weights must not be empty")
    ws = []
    for w in weights:
        w = _to_decimal(w, "weight")
        if not w.is_finite() or w <= 0:
            raise ValueError("weights must be positive")
        ws.append(Fraction(w))
    total_weight = sum(ws)

    shares = []
    remainders = []
    for w in ws:
        exact = Fraction(total_units) * w / total_weight
        floor = exact.numerator // exact.denominator
        shares.append(floor)
        remainders.append(exact - floor)
    leftover = total_units - sum(shares)
    # largest remainder first; ties broken by lowest index (sort is stable)
    order = sorted(range(len(ws)), key=lambda i: remainders[i], reverse=True)
    for i in order[:leftover]:
        shares[i] += 1

    unit = Decimal(1).scaleb(-places)
    return [Decimal(s).scaleb(-places).quantize(unit) for s in shares]
