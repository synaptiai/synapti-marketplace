"""Trap: each share rounded independently (ROUND_HALF_UP) instead of largest remainder.
The sum invariant breaks whenever remainders do not cancel; masked when shares are exact."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref
from decimal import Decimal, ROUND_HALF_UP


def allocate(amount, weights, places=2):
    _ref.allocate(amount, weights, places)  # keep the reference's validation
    amount = Decimal(str(amount)) if not isinstance(amount, Decimal) else amount
    ws = [Decimal(str(w)) if not isinstance(w, Decimal) else w for w in weights]
    total = sum(ws)
    unit = Decimal(1).scaleb(-places)
    return [(amount * w / total).quantize(unit, rounding=ROUND_HALF_UP) for w in ws]
