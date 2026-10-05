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
            "data must be at least %d bytes, got %d" % (MIN_SPLIT_SIZE, len(data))
        )
    seg = len(data) // 4
    s1 = data[0:seg]
    s2 = data[seg:2 * seg]
    s3 = data[2 * seg:3 * seg]
    s4 = data[3 * seg:]
    return (s1, s2, s3, s4)


def join(streams):
    """Concatenate exactly four streams in order. Raises ValueError otherwise."""
    if len(streams) != 4:
        raise ValueError("expected exactly 4 streams, got %d" % len(streams))
    return b"".join(streams)


def pack(streams):
    """Pack four streams into one block.

    Layout: three u16 little-endian lengths (streams 1-3), then the four
    bodies in order 1, 2, 3, 4, each body holding its stream reversed.
    Raises ValueError if there are not exactly four streams or if any of
    streams 1-3 is longer than 65535 bytes.
    """
    if len(streams) != 4:
        raise ValueError("expected exactly 4 streams, got %d" % len(streams))
    s1, s2, s3, s4 = streams
    for i, s in enumerate((s1, s2, s3), start=1):
        if len(s) > MAX_TABLE_LENGTH:
            raise ValueError(
                "stream %d is too long (%d > %d)" % (i, len(s), MAX_TABLE_LENGTH)
            )
    table = struct.pack("<HHH", len(s1), len(s2), len(s3))
    bodies = b"".join(s[::-1] for s in (s1, s2, s3, s4))
    return table + bodies


def unpack(block):
    """Inverse of :func:`pack`. Returns a 4-tuple of bytes.

    Raises ValueError if ``block`` is shorter than the 6-byte jump table or
    if the table lengths exceed the block.
    """
    if len(block) < TABLE_SIZE:
        raise ValueError(
            "block must be at least %d bytes, got %d" % (TABLE_SIZE, len(block))
        )
    len1, len2, len3 = struct.unpack("<HHH", block[:TABLE_SIZE])
    body = block[TABLE_SIZE:]
    if len1 + len2 + len3 > len(body):
        raise ValueError("jump-table lengths exceed the block")
    pos = 0
    s1 = body[pos:pos + len1][::-1]
    pos += len1
    s2 = body[pos:pos + len2][::-1]
    pos += len2
    s3 = body[pos:pos + len3][::-1]
    pos += len3
    s4 = body[pos:][::-1]
    return (s1, s2, s3, s4)


def encode(data):
    """``pack(split(data))``."""
    return pack(split(data))


def decode(block):
    """``join(unpack(block))``."""
    return join(unpack(block))
