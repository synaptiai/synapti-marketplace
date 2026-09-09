"""Four-stream block codec. See ISSUE.md for the wire format and splitting rule.

This file is the starting skeleton for the task: every function body below
raises NotImplementedError and must be replaced with a real implementation.
"""

TABLE_SIZE = 6
MAX_TABLE_LENGTH = 0xFFFF
MIN_SPLIT_SIZE = 4


def split(data):
    """Split ``data`` (bytes, at least 4 bytes) into four streams.

    ``seg = len(data) // 4``; streams 1-3 get ``seg`` bytes each in order and
    stream 4 gets the rest. Returns a 4-tuple of bytes. Raises ValueError if
    ``data`` is shorter than 4 bytes.
    """
    raise NotImplementedError


def join(streams):
    """Concatenate exactly four streams in order. Raises ValueError otherwise."""
    raise NotImplementedError


def pack(streams):
    """Pack four streams into one block.

    Layout: three u16 little-endian lengths (streams 1-3), then the four
    bodies in order 1, 2, 3, 4, each body holding its stream reversed.
    Raises ValueError if there are not exactly four streams or if any of
    streams 1-3 is longer than 65535 bytes.
    """
    raise NotImplementedError


def unpack(block):
    """Inverse of :func:`pack`. Returns a 4-tuple of bytes.

    Raises ValueError if ``block`` is shorter than the 6-byte jump table or
    if the table lengths exceed the block.
    """
    raise NotImplementedError


def encode(data):
    """``pack(split(data))``."""
    raise NotImplementedError


def decode(block):
    """``join(unpack(block))``."""
    raise NotImplementedError
