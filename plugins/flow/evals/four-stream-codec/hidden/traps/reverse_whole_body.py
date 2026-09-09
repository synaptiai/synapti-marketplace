"""Trap: the concatenated body is reversed as a whole (s4r s3r s2r s1r) instead of per stream.
Round-trips cleanly; masked when s1 == s4 and s2 == s3."""
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
    return bytes(table) + b"".join(streams)[::-1]


def unpack(block):
    block = bytes(block)
    if len(block) < 6:
        raise ValueError("short block")
    lengths = [int.from_bytes(block[i:i + 2], "little") for i in (0, 2, 4)]
    if 6 + sum(lengths) > len(block):
        raise ValueError("lengths exceed block")
    body = block[6:][::-1]
    out, pos = [], 0
    for length in lengths:
        out.append(body[pos:pos + length])
        pos += length
    out.append(body[pos:])
    return tuple(out)


def encode(data):
    return pack(split(data))


def decode(block):
    return join(unpack(block))
