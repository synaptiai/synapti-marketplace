"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract."""
from decimal import Decimal, InvalidOperation
from fractions import Fraction


def _to_decimal(value, what):
    if isinstance(value, bool):
        raise TypeError(f"{what} must not be a bool")
    if isinstance(value, float):
        raise TypeError(f"{what} must not be a float")
    if isinstance(value, Decimal):
        return value
    if isinstance(value, (int, str)):
        try:
            return Decimal(value)
        except InvalidOperation:
            raise ValueError(f"invalid {what}: {value!r}")
    raise TypeError(f"unsupported type for {what}: {type(value)!r}")


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
        raise ValueError(f"places must be a non-negative int, got {places!r}")

    amount_dec = _to_decimal(amount, "amount")
    if amount_dec < 0:
        raise ValueError(f"amount must be >= 0, got {amount_dec}")

    exponent = amount_dec.normalize().as_tuple().exponent
    if isinstance(exponent, int) and exponent < -places:
        raise ValueError(
            f"amount has more than {places} fractional digits: {amount_dec}"
        )

    scale = Decimal(10) ** places
    total_units = int(amount_dec * scale)

    weights = list(weights)
    if not weights:
        raise ValueError("weights must not be empty")

    weight_fracs = []
    for w in weights:
        w_dec = _to_decimal(w, "weight")
        if w_dec <= 0:
            raise ValueError(f"weights must be > 0, got {w_dec}")
        weight_fracs.append(Fraction(w_dec))

    total_weight = sum(weight_fracs)

    exacts = [Fraction(total_units) * wf / total_weight for wf in weight_fracs]
    floors = [exact.numerator // exact.denominator for exact in exacts]
    remainders = [exact - floor for exact, floor in zip(exacts, floors)]

    leftover = total_units - sum(floors)

    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    bump = set(order[:leftover])

    unit = Decimal(1).scaleb(-places)
    shares = []
    for i, floor in enumerate(floors):
        units = floor + (1 if i in bump else 0)
        shares.append((Decimal(units) * unit).quantize(unit))

    return shares
