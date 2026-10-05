"""Four-stream block codec. See ISSUE.md for the wire format and splitting rule.

This file is the starting skeleton for the task: every function body below
raises NotImplementedError and must be replaced with a real implementation.
"""

import struct

TABLE_SIZE = 6
MAX_TABLE_LENGTH = 0xFFFF
MIN_SPLIT_SIZE = 4


def split(data):
    """Split ``data`` (bytes, at least 4 bytes) into four streams.

    ``seg = len(data) // 4``; streams 1-3 get ``seg`` bytes each in order and
    stream 4 gets the rest. Returns a 4-tuple of bytes. Raises ValueError if
    ``data`` is shorter than 4 bytes.
    """
    if len(data) < MIN_SPLIT_SIZE:
        raise ValueError(
            f"data must be at least {MIN_SPLIT_SIZE} bytes, got {len(data)}"
        )
    seg = len(data) // 4
    return (
        data[0:seg],
        data[seg : 2 * seg],
        data[2 * seg : 3 * seg],
        data[3 * seg :],
    )


def join(streams):
    """Concatenate exactly four streams in order. Raises ValueError otherwise."""
    streams = tuple(streams)
    if len(streams) != 4:
        raise ValueError(f"join() requires exactly 4 streams, got {len(streams)}")
    return b"".join(streams)


def pack(streams):
    """Pack four streams into one block.

    Layout: three u16 little-endian lengths (streams 1-3), then the four
    bodies in order 1, 2, 3, 4, each body holding its stream reversed.
    Raises ValueError if there are not exactly four streams or if any of
    streams 1-3 is longer than 65535 bytes.
    """
    streams = tuple(streams)
    if len(streams) != 4:
        raise ValueError(f"pack() requires exactly 4 streams, got {len(streams)}")
    s1, s2, s3, s4 = streams
    for i, s in enumerate((s1, s2, s3), start=1):
        if len(s) > MAX_TABLE_LENGTH:
            raise ValueError(
                f"stream {i} is {len(s)} bytes, exceeds max of {MAX_TABLE_LENGTH}"
            )
    header = struct.pack("<HHH", len(s1), len(s2), len(s3))
    body = s1[::-1] + s2[::-1] + s3[::-1] + s4[::-1]
    return header + body


def unpack(block):
    """Inverse of :func:`pack`. Returns a 4-tuple of bytes.

    Raises ValueError if ``block`` is shorter than the 6-byte jump table or
    if the table lengths exceed the block.
    """
    if len(block) < TABLE_SIZE:
        raise ValueError(
            f"block must be at least {TABLE_SIZE} bytes, got {len(block)}"
        )
    l1, l2, l3 = struct.unpack("<HHH", block[:TABLE_SIZE])
    if TABLE_SIZE + l1 + l2 + l3 > len(block):
        raise ValueError(
            "jump-table lengths exceed block: "
            f"{TABLE_SIZE} + {l1} + {l2} + {l3} > {len(block)}"
        )
    off1 = TABLE_SIZE
    off2 = off1 + l1
    off3 = off2 + l2
    off4 = off3 + l3
    s1 = block[off1:off2][::-1]
    s2 = block[off2:off3][::-1]
    s3 = block[off3:off4][::-1]
    s4 = block[off4:][::-1]
    return (s1, s2, s3, s4)


def encode(data):
    """``pack(split(data))``."""
    return pack(split(data))


def decode(block):
    """``join(unpack(block))``."""
    return join(unpack(block))
