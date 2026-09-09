"""Trap: segment size (n + 3) // 4 (Zstd's rule) instead of n // 4 with the remainder in stream 4.
Round-trips cleanly; masked when len(data) % 4 == 0."""
from reference_impl import *  # noqa: F401,F403


def split(data):
    data = bytes(data)
    n = len(data)
    if n < 4:
        raise ValueError("too short")
    seg = (n + 3) // 4
    return (data[0:seg], data[seg:2 * seg], data[2 * seg:3 * seg], data[3 * seg:])


def encode(data):
    return pack(split(data))
