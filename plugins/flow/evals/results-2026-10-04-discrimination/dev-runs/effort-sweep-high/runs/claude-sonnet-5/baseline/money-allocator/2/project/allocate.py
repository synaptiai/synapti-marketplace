"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract.

This file is the starting skeleton for the task: the function body below
raises NotImplementedError and must be replaced with a real implementation.
"""
import math
from decimal import Decimal, InvalidOperation
from fractions import Fraction


def _to_decimal_amount(amount):
    if isinstance(amount, float):
        raise TypeError("amount must not be a float")
    if isinstance(amount, Decimal):
        return amount
    if isinstance(amount, int):
        return Decimal(amount)
    if isinstance(amount, str):
        try:
            return Decimal(amount)
        except InvalidOperation:
            raise ValueError("amount is not a valid decimal string") from None
    raise TypeError("amount must be int, str or Decimal")


def _to_decimal_weight(weight):
    if isinstance(weight, float):
        raise TypeError("weight must not be a float")
    if isinstance(weight, Decimal):
        return weight
    if isinstance(weight, int):
        return Decimal(weight)
    if isinstance(weight, str):
        try:
            return Decimal(weight)
        except InvalidOperation:
            raise ValueError("weight is not a valid decimal string") from None
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
    if isinstance(places, bool) or not isinstance(places, int) or places < 0:
        raise ValueError("places must be a non-negative integer")

    amt = _to_decimal_amount(amount)
    if amt < 0:
        raise ValueError("amount must be >= 0")

    exponent = amt.as_tuple().exponent
    if isinstance(exponent, int) and exponent < -places:
        raise ValueError(f"amount must have at most {places} fractional digits")

    weights = list(weights)
    if len(weights) == 0:
        raise ValueError("weights must not be empty")

    weight_fractions = []
    for w in weights:
        wd = _to_decimal_weight(w)
        if wd <= 0:
            raise ValueError("weights must be > 0")
        weight_fractions.append(Fraction(wd))

    total_units = int(Fraction(amt) * (10 ** places))
    total_weight = sum(weight_fractions)

    exacts = [total_units * wf / total_weight for wf in weight_fractions]
    floors = [math.floor(e) for e in exacts]
    remainders = [e - f for e, f in zip(exacts, floors)]

    leftover = total_units - sum(floors)

    order = sorted(range(len(weights)), key=lambda i: remainders[i], reverse=True)
    shares = list(floors)
    for i in order[:leftover]:
        shares[i] += 1

    unit = Decimal(1).scaleb(-places)
    return [(Decimal(s) * unit).quantize(unit) for s in shares]
