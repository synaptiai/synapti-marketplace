"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract.

This file is the starting skeleton for the task: the function body below
raises NotImplementedError and must be replaced with a real implementation.
"""
from decimal import Decimal, InvalidOperation
from fractions import Fraction


def _to_decimal_amount(amount):
    if isinstance(amount, bool) or isinstance(amount, float):
        raise TypeError("amount must be int, str or Decimal, not float")
    if isinstance(amount, (int, Decimal, str)):
        try:
            value = Decimal(amount)
        except InvalidOperation:
            raise ValueError(f"invalid amount: {amount!r}")
        return value
    raise TypeError("amount must be int, str or Decimal")


def _to_decimal_weight(weight):
    if isinstance(weight, bool) or isinstance(weight, float):
        raise TypeError("weight must be int, str or Decimal, not float")
    if isinstance(weight, (int, Decimal, str)):
        try:
            value = Decimal(weight)
        except InvalidOperation:
            raise ValueError(f"invalid weight: {weight!r}")
        return value
    raise TypeError("weight must be int, str or Decimal")


def allocate(amount, weights, places=2):
    """Split ``amount`` across ``weights`` by the largest-remainder method.

    Returns a list of ``Decimal`` values quantized to ``places`` decimal
    places, in the same order as ``weights``, summing exactly to ``amount``.
    Leftover units go one each to the entries with the largest fractional
    remainder, lowest index first on ties.

    ``amount``: int, str or Decimal >= 0 with at most ``places`` fractional
    digits (float -> TypeError; negative or excess precision -> ValueError).
    ``weights``: non-empty sequence of int, str or Decimal, each > 0
    (float -> TypeError; empty, zero or negative -> ValueError).
    ``places``: int >= 0, else ValueError.
    """
    if not isinstance(places, int) or isinstance(places, bool) or places < 0:
        raise ValueError("places must be a non-negative int")

    amount_dec = _to_decimal_amount(amount)
    if amount_dec < 0:
        raise ValueError("amount must be >= 0")

    scaled = amount_dec.scaleb(places)
    if scaled != scaled.to_integral_value():
        raise ValueError(f"amount has more than {places} fractional digits")

    if not weights:
        raise ValueError("weights must be a non-empty sequence")

    weight_decs = [_to_decimal_weight(w) for w in weights]
    for w in weight_decs:
        if w <= 0:
            raise ValueError("weights must all be > 0")

    unit = Decimal(1).scaleb(-places)
    total_units = scaled.to_integral_value()

    total_weight = sum(Fraction(str(w)) for w in weight_decs)

    exacts = [Fraction(int(total_units)) * Fraction(str(w)) / total_weight for w in weight_decs]
    floors = [e.numerator // e.denominator for e in exacts]
    remainders = [e - f for e, f in zip(exacts, floors)]

    leftover = int(total_units) - sum(floors)

    order = sorted(range(len(weight_decs)), key=lambda i: (-remainders[i], i))
    extra = set(order[:leftover])

    shares_units = [f + (1 if i in extra else 0) for i, f in enumerate(floors)]

    return [Decimal(s) * unit for s in shares_units]
