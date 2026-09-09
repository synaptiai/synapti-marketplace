"""Trap: no input validation — short data splits into empty streams, oversized
streams silently truncate their table entry, and undersized blocks unpack to
whatever bytes are present. Masked whenever inputs are well-formed."""
from reference_impl import *  # noqa: F401,F403


def split(data):
    data = bytes(data)
    seg = len(data) // 4
    return (data[0:seg], data[seg:2 * seg], data[2 * seg:3 * seg], data[3 * seg:])


def pack(streams):
    streams = tuple(bytes(s) for s in streams)
    table = b"".join((len(s) & 0xFFFF).to_bytes(2, "little") for s in streams[:3])
    return table + b"".join(s[::-1] for s in streams)


def unpack(block):
    block = bytes(block)
    lengths = [int.from_bytes(block[i:i + 2], "little") for i in (0, 2, 4)]
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
