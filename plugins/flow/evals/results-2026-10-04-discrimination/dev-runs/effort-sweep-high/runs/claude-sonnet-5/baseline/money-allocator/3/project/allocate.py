"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract.

This file is the starting skeleton for the task: the function body below
raises NotImplementedError and must be replaced with a real implementation.
"""
from decimal import Decimal
from fractions import Fraction


def _to_decimal_amount(amount, places):
    if isinstance(amount, bool) or isinstance(amount, float):
        raise TypeError("amount must be int, str or Decimal, not float")
    if not isinstance(amount, (int, str, Decimal)):
        raise TypeError("amount must be int, str or Decimal")
    try:
        dec = Decimal(amount)
    except Exception as exc:
        raise ValueError(f"invalid amount: {amount!r}") from exc
    if dec < 0:
        raise ValueError("amount must not be negative")
    scale = Decimal(10) ** places
    scaled = dec * scale
    if scaled != scaled.to_integral_value():
        raise ValueError(
            f"amount has more than {places} fractional digits: {amount!r}"
        )
    return dec


def _to_decimal_weight(weight):
    if isinstance(weight, bool) or isinstance(weight, float):
        raise TypeError("weights must be int, str or Decimal, not float")
    if not isinstance(weight, (int, str, Decimal)):
        raise TypeError("weights must be int, str or Decimal")
    try:
        dec = Decimal(weight)
    except Exception as exc:
        raise ValueError(f"invalid weight: {weight!r}") from exc
    if dec <= 0:
        raise ValueError("weights must be > 0")
    return dec


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
    if isinstance(places, bool) or not isinstance(places, int) or places < 0:
        raise ValueError("places must be a non-negative int")

    dec_amount = _to_decimal_amount(amount, places)

    weights = list(weights)
    if not weights:
        raise ValueError("weights must not be empty")
    dec_weights = [_to_decimal_weight(w) for w in weights]

    unit = Decimal(10) ** -places
    total_units = int((dec_amount / unit).to_integral_value())

    frac_weights = [Fraction(w) for w in dec_weights]
    sum_weights = sum(frac_weights)

    exacts = [Fraction(total_units) * w / sum_weights for w in frac_weights]
    floors = [int(e) for e in exacts]  # exact values are non-negative
    remainders = [e - f for e, f in zip(exacts, floors)]

    leftover = total_units - sum(floors)

    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    extra = set(order[:leftover])

    share_units = [f + (1 if i in extra else 0) for i, f in enumerate(floors)]

    return [
        (Decimal(units) * unit).quantize(unit) for units in share_units
    ]
