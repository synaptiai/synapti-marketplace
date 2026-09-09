"""Trap: remainder ties broken by highest index (stable sort on the reversed list).
Masked when no two remainders tie."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


def allocate(amount, weights, places=2):
    weights = list(weights)
    result = _ref.allocate(amount, list(reversed(weights)), places)
    return list(reversed(result))
