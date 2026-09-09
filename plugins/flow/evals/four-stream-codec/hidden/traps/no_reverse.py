"""Trap: stream bodies stored forwards instead of reversed.
Round-trips cleanly; masked when every stream is a palindrome."""
from reference_impl import *  # noqa: F401,F403
import reference_impl as _ref


def pack(streams):
    streams = tuple(bytes(s) for s in streams)
    if len(streams) != 4:
        raise ValueError("pack expects exactly 4 streams")
    table = bytearray()
    for s in streams[:3]:
        if len(s) > _ref.MAX_TABLE_LENGTH:
            raise ValueError("stream too long")
        table += len(s).to_bytes(2, "little")
    return bytes(table) + b"".join(streams)


def unpack(block):
    return tuple(s[::-1] for s in _ref.unpack(block))


def encode(data):
    return pack(split(data))


def decode(block):
    return join(unpack(block))
