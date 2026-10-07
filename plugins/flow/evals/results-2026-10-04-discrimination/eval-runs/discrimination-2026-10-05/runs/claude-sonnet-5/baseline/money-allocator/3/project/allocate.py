"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract.

This file is the starting skeleton for the task: the function body below
raises NotImplementedError and must be replaced with a real implementation.
"""
from decimal import Decimal  # noqa: F401  (the return type)
from fractions import Fraction


def _to_decimal(value, what):
    if isinstance(value, float):
        raise TypeError(f"{what} must be int, str, or Decimal, not float")
    if isinstance(value, (int, Decimal, str)):
        return Decimal(value)
    raise TypeError(f"{what} must be int, str, or Decimal")


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
    if not isinstance(places, int) or places < 0:
        raise ValueError("places must be a non-negative int")

    amount_dec = _to_decimal(amount, "amount")
    if amount_dec < 0:
        raise ValueError("amount must not be negative")

    total_units_frac = Fraction(amount_dec) * (10 ** places)
    if total_units_frac.denominator != 1:
        raise ValueError(f"amount has more than {places} fractional digits")
    total_units = total_units_frac.numerator

    weights = list(weights)
    if not weights:
        raise ValueError("weights must not be empty")

    weight_fracs = []
    for w in weights:
        w_dec = _to_decimal(w, "weight")
        if w_dec <= 0:
            raise ValueError("weights must be positive")
        weight_fracs.append(Fraction(w_dec))

    total_weight = sum(weight_fracs)

    exact = [Fraction(total_units) * wf / total_weight for wf in weight_fracs]
    floors = [e.numerator // e.denominator for e in exact]
    remainders = [e - f for e, f in zip(exact, floors)]
    leftover = total_units - sum(floors)

    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    extra = set(order[:leftover])

    shares_units = [f + (1 if i in extra else 0) for i, f in enumerate(floors)]

    return [Decimal(su).scaleb(-places) for su in shares_units]
