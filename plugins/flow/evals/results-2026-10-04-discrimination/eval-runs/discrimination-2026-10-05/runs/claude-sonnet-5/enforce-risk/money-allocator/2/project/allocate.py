"""Largest-remainder money allocation. See ISSUE.md for the algorithm and input contract."""
from decimal import Decimal
from fractions import Fraction


def _validate_places(places):
    # bool is a subclass of int; reject it like any other non-int.
    if isinstance(places, bool) or not isinstance(places, int):
        raise ValueError("places must be an int >= 0")
    if places < 0:
        raise ValueError("places must be an int >= 0")


def _validate_amount(amount, places):
    if isinstance(amount, bool) or isinstance(amount, float):
        raise TypeError("amount must be int, str or Decimal, not float")
    if not isinstance(amount, (int, str, Decimal)):
        raise TypeError("amount must be int, str or Decimal")
    try:
        dec_amount = Decimal(amount)
    except Exception as exc:
        raise ValueError(f"amount is not a valid decimal number: {amount!r}") from exc
    if dec_amount < 0:
        raise ValueError("amount must be >= 0")
    # -as_tuple().exponent is the number of fractional digits for a finite
    # Decimal, regardless of whether it was built from an int, a plain
    # string, a "." string, or exponential notation (e.g. Decimal("1E+2")
    # has exponent +2, i.e. 0 fractional digits).
    exponent = dec_amount.as_tuple().exponent
    if not isinstance(exponent, int):
        raise ValueError(f"amount must be finite: {amount!r}")
    fractional_digits = max(0, -exponent)
    if fractional_digits > places:
        raise ValueError(
            f"amount {amount!r} has more than {places} fractional digits"
        )
    return dec_amount


def _validate_weights(weights):
    if not isinstance(weights, (list, tuple)):
        raise ValueError("weights must be a non-empty sequence")
    if len(weights) == 0:
        raise ValueError("weights must not be empty")
    dec_weights = []
    for w in weights:
        if isinstance(w, bool) or isinstance(w, float):
            raise TypeError("each weight must be int, str or Decimal, not float")
        if not isinstance(w, (int, str, Decimal)):
            raise TypeError("each weight must be int, str or Decimal")
        try:
            dec_w = Decimal(w)
        except Exception as exc:
            raise ValueError(f"weight is not a valid decimal number: {w!r}") from exc
        if dec_w <= 0:
            raise ValueError(f"each weight must be > 0, got {w!r}")
        dec_weights.append(dec_w)
    return dec_weights


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
    dec_amount = _validate_amount(amount, places)
    dec_weights = _validate_weights(weights)

    unit = Decimal(1).scaleb(-places)
    total_units = int(dec_amount / unit)  # exact: amount has <= places digits
    total_weight = sum(dec_weights)

    # Exact share in units as a Fraction: multiply before dividing, and use
    # Fraction (not Decimal division, which can round) so the remainder
    # comparison in the tie-break step is exact.
    exact_units = [
        Fraction(total_units * w) / Fraction(total_weight) for w in dec_weights
    ]
    floors = [int(e) for e in exact_units]  # Fraction.__int__ truncates
    # toward zero, which is floor for non-negative values.
    remainders = [e - f for e, f in zip(exact_units, floors)]

    leftover = total_units - sum(floors)

    # Rank indices by largest remainder first, lowest index first on ties.
    order = sorted(range(len(dec_weights)), key=lambda i: (-remainders[i], i))
    shares = list(floors)
    for i in order[:leftover]:
        shares[i] += 1

    return [Decimal(s) * unit for s in shares]
