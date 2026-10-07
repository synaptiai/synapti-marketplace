"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract."""
from decimal import Decimal


def _validate_places(places):
    if isinstance(places, bool) or not isinstance(places, int):
        raise ValueError("places must be a non-negative int")
    if places < 0:
        raise ValueError("places must be a non-negative int")


def _validate_amount(amount, places):
    if isinstance(amount, float):
        raise TypeError("amount must not be a float")
    value = Decimal(amount)
    if value < 0:
        raise ValueError("amount must not be negative")
    exponent = value.as_tuple().exponent
    if isinstance(exponent, int) and exponent < -places:
        raise ValueError(
            "amount must not carry more than %d fractional digits" % places
        )
    return value


def _validate_weights(weights):
    if len(weights) == 0:
        raise ValueError("weights must not be empty")
    values = []
    for w in weights:
        if isinstance(w, float):
            raise TypeError("weights must not contain floats")
        value = Decimal(w)
        if value <= 0:
            raise ValueError("weights must be > 0")
        values.append(value)
    return values


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
    _validate_places(places)
    amount_value = _validate_amount(amount, places)
    weight_values = _validate_weights(weights)

    unit = Decimal(1).scaleb(-places)
    total_units = int((amount_value / unit).to_integral_exact())
    total_weight = sum(weight_values)

    floors = []
    remainders = []
    for w in weight_values:
        exact = Decimal(total_units) * w / total_weight
        floor = int(exact.to_integral_value(rounding="ROUND_FLOOR"))
        floors.append(floor)
        remainders.append(exact - floor)

    leftover = total_units - sum(floors)
    # Largest remainder first; lowest index first on ties (stable sort on
    # index since Python's sort is stable, so sorting by -remainder alone
    # preserves original index order among equal remainders).
    order = sorted(range(len(weight_values)), key=lambda i: remainders[i], reverse=True)
    extra = set(order[:leftover])

    shares = [
        Decimal(floors[i] + (1 if i in extra else 0)) * unit
        for i in range(len(weight_values))
    ]
    return [share.quantize(unit) for share in shares]
