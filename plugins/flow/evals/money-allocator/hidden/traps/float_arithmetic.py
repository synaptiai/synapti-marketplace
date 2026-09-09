"""Trap: amounts converted through float. Masked while amounts fit in ~15 significant digits."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref
from decimal import Decimal


def allocate(amount, weights, places=2):
    _ref.allocate(amount, weights, places)  # keep the reference's validation
    total_units = int(round(float(amount) * 10 ** places))
    ws = [float(w) for w in weights]
    total_weight = sum(ws)
    exact = [total_units * w / total_weight for w in ws]
    shares = [int(e) for e in exact]
    leftover = total_units - sum(shares)
    order = sorted(range(len(ws)), key=lambda i: exact[i] - shares[i], reverse=True)
    for i in order[:leftover]:
        shares[i] += 1
    unit = Decimal(1).scaleb(-places)
    return [Decimal(s).scaleb(-places).quantize(unit) for s in shares]
