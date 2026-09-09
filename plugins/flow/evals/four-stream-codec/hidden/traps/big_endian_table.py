"""Trap: jump-table lengths written big-endian.
Round-trips cleanly; masked when every table length has symmetric bytes (0, 257, 514, ...)."""
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
        table += len(s).to_bytes(2, "big")
    return bytes(table) + b"".join(s[::-1] for s in streams)


def unpack(block):
    block = bytes(block)
    if len(block) < 6:
        raise ValueError("short block")
    lengths = [int.from_bytes(block[i:i + 2], "big") for i in (0, 2, 4)]
    if 6 + sum(lengths) > len(block):
        raise ValueError("lengths exceed block")
    out, pos = [], 6
    for length in lengths:
        out.append(block[pos:pos + length][::-1])
        pos += length
    out.append(block[pos:][::-1])
    return tuple(out)


def encode(data):
    return pack(split(data))


def decode(block):
    return join(unpack(block))
