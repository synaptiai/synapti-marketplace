"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract.
"""
import math
from decimal import Decimal
from fractions import Fraction


def _to_decimal_amount(amount):
    if isinstance(amount, float):
        raise TypeError("amount must be int, str or Decimal, not float")
    if not isinstance(amount, (int, str, Decimal)):
        raise TypeError("amount must be int, str or Decimal")
    return Decimal(amount)


def _to_decimal_weight(weight):
    if isinstance(weight, float):
        raise TypeError("weights must be int, str or Decimal, not float")
    if not isinstance(weight, (int, str, Decimal)):
        raise TypeError("weights must be int, str or Decimal")
    return Decimal(weight)


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

    dec_amount = _to_decimal_amount(amount)
    if dec_amount < 0:
        raise ValueError("amount must be >= 0")

    if not dec_amount.is_finite():
        raise ValueError("amount must be a finite value")

    normalized = dec_amount.normalize()
    exponent = normalized.as_tuple().exponent
    fractional_digits = max(0, -exponent) if isinstance(exponent, int) else 0
    if fractional_digits > places:
        raise ValueError(
            "amount has more than %d fractional digits" % places
        )

    weight_list = list(weights)
    if not weight_list:
        raise ValueError("weights must be a non-empty sequence")

    dec_weights = []
    for w in weight_list:
        dw = _to_decimal_weight(w)
        if dw <= 0:
            raise ValueError("weights must be > 0")
        dec_weights.append(dw)

    total_units_frac = Fraction(dec_amount) * (Fraction(10) ** places)
    total_units = total_units_frac.numerator // total_units_frac.denominator

    sum_weights = sum((Fraction(w) for w in dec_weights), Fraction(0))

    exact_shares = [total_units * Fraction(w) / sum_weights for w in dec_weights]
    floors = [math.floor(e) for e in exact_shares]
    remainders = [e - f for e, f in zip(exact_shares, floors)]

    leftover = total_units - sum(floors)

    order = sorted(range(len(dec_weights)), key=lambda i: (-remainders[i], i))
    extra = set(order[:leftover])

    units = [f + (1 if i in extra else 0) for i, f in enumerate(floors)]

    return [Decimal(u).scaleb(-places) for u in units]
