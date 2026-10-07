"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract."""
from decimal import Decimal
from fractions import Fraction


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
    if isinstance(places, bool) or not isinstance(places, int):
        raise TypeError("places must be an int")
    if places < 0:
        raise ValueError("places must be >= 0")

    if isinstance(amount, bool) or isinstance(amount, float):
        raise TypeError("amount must be int, str or Decimal, not float")
    try:
        amount = Decimal(amount)
    except Exception as exc:
        raise ValueError(f"invalid amount: {amount!r}") from exc
    if amount < 0:
        raise ValueError("amount must be >= 0")

    exponent = amount.as_tuple().exponent
    if isinstance(exponent, str):
        # 'n' (NaN), 'N' (sNaN), 'F' (Infinity): not a finite decimal number.
        raise ValueError(f"invalid amount: {amount!r}")
    if -exponent > places:
        raise ValueError(
            f"amount {amount} has more than {places} fractional digits"
        )

    if not isinstance(weights, (list, tuple)):
        weights = list(weights)
    if len(weights) == 0:
        raise ValueError("weights must be non-empty")

    checked_weights = []
    for w in weights:
        if isinstance(w, bool) or isinstance(w, float):
            raise TypeError("weights must be int, str or Decimal, not float")
        try:
            w = Decimal(w)
        except Exception as exc:
            raise ValueError(f"invalid weight: {w!r}") from exc
        if w <= 0:
            raise ValueError("weights must be > 0")
        checked_weights.append(w)
    weights = checked_weights

    unit = Decimal(1).scaleb(-places)
    total_units = int(amount / unit)
    weight_sum = sum(weights)

    # Exact shares in units, computed with Fraction so no rounding error
    # creeps in before the floor/remainder split (never binary float).
    exact = [Fraction(total_units) * Fraction(w) / Fraction(weight_sum) for w in weights]
    floors = [e.numerator // e.denominator for e in exact]
    remainders = [e - f for e, f in zip(exact, floors)]

    leftover = total_units - sum(floors)
    # Largest fractional remainder first; ties broken by lowest index
    # first via the stable sort on the (secondary) index key.
    order = sorted(range(len(weights)), key=lambda i: (-remainders[i], i))
    extra = set(order[:leftover])

    shares_units = [f + (1 if i in extra else 0) for i, f in enumerate(floors)]
    return [(Decimal(s) * unit).quantize(unit) for s in shares_units]
