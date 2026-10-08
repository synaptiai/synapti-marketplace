"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract."""
import math
from decimal import Decimal, InvalidOperation
from fractions import Fraction


def _validate_places(places):
    if isinstance(places, bool) or not isinstance(places, int) or places < 0:
        raise ValueError(f"places must be a non-negative int, got {places!r}")


def _to_amount_decimal(amount, places):
    if isinstance(amount, float):
        raise TypeError("amount must not be a float; use int, str, or Decimal")
    try:
        dec = Decimal(amount)
    except (InvalidOperation, ValueError, TypeError) as exc:
        raise ValueError(f"invalid amount: {amount!r}") from exc
    if dec < 0:
        raise ValueError(f"amount must be >= 0, got {amount!r}")
    exponent = dec.as_tuple().exponent
    if isinstance(exponent, int) and exponent < -places:
        raise ValueError(
            f"amount {amount!r} has more than {places} fractional digits"
        )
    return dec


def _to_weight_decimal(weight):
    if isinstance(weight, float):
        raise TypeError("weights must not contain floats; use int, str, or Decimal")
    try:
        dec = Decimal(weight)
    except (InvalidOperation, ValueError, TypeError) as exc:
        raise ValueError(f"invalid weight: {weight!r}") from exc
    if dec <= 0:
        raise ValueError(f"weights must be > 0, got {weight!r}")
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
    # Validate before any allocation arithmetic runs.
    _validate_places(places)
    try:
        weights = list(weights)
    except TypeError as exc:
        raise ValueError(f"weights must be a sequence, got {weights!r}") from exc
    if len(weights) == 0:
        raise ValueError("weights must be a non-empty sequence")

    amount_dec = _to_amount_decimal(amount, places)
    weight_decs = [_to_weight_decimal(w) for w in weights]

    total_units = int(amount_dec.scaleb(places))
    weight_fracs = [Fraction(w) for w in weight_decs]
    weight_sum = sum(weight_fracs)

    exact = [Fraction(total_units) * w / weight_sum for w in weight_fracs]
    floors = [math.floor(e) for e in exact]
    remainders = [e - f for e, f in zip(exact, floors)]

    leftover = total_units - sum(floors)

    # Largest remainder first; ties broken by lowest index first.
    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    extra = set(order[:leftover])

    shares_units = [f + (1 if i in extra else 0) for i, f in enumerate(floors)]

    unit = Decimal(1).scaleb(-places)
    return [Decimal(su) * unit for su in shares_units]
