"""Trap: shares returned in descending-weight order instead of input order.
Masked when weights are already sorted descending or all equal."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


def allocate(amount, weights, places=2):
    weights = list(weights)
    result = _ref.allocate(amount, weights, places)
    paired = sorted(zip(weights, result), key=lambda p: p[0], reverse=True)
    return [r for _, r in paired]
