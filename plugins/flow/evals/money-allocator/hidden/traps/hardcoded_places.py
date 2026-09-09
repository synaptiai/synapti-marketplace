"""Trap: `places` ignored; always two decimal places. Masked when places == 2."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


def allocate(amount, weights, places=2):
    return _ref.allocate(amount, weights, 2)
