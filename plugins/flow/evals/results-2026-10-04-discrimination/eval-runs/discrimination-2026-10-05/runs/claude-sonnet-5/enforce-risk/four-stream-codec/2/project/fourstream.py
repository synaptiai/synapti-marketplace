"""Four-stream block codec. See ISSUE.md for the wire format and splitting rule."""

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
    stream1 = data[0:seg]
    stream2 = data[seg : 2 * seg]
    stream3 = data[2 * seg : 3 * seg]
    stream4 = data[3 * seg :]
    return (stream1, stream2, stream3, stream4)


def join(streams):
    """Concatenate exactly four streams in order. Raises ValueError otherwise."""
    streams = tuple(streams)
    if len(streams) != 4:
        raise ValueError(
            "join requires exactly 4 streams, got %d" % len(streams)
        )
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
        raise ValueError(
            "pack requires exactly 4 streams, got %d" % len(streams)
        )
    stream1, stream2, stream3, stream4 = streams
    for index, stream in enumerate((stream1, stream2, stream3), start=1):
        if len(stream) > MAX_TABLE_LENGTH:
            raise ValueError(
                "stream %d is %d bytes, exceeds max of %d"
                % (index, len(stream), MAX_TABLE_LENGTH)
            )
    table = struct.pack("<HHH", len(stream1), len(stream2), len(stream3))
    bodies = b"".join(
        stream[::-1] for stream in (stream1, stream2, stream3, stream4)
    )
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
    len1, len2, len3 = struct.unpack("<HHH", block[0:TABLE_SIZE])
    body = block[TABLE_SIZE:]
    if len1 + len2 + len3 > len(body):
        raise ValueError(
            "jump table lengths (%d, %d, %d) exceed available block data (%d bytes)"
            % (len1, len2, len3, len(body))
        )
    body1 = body[0:len1]
    body2 = body[len1 : len1 + len2]
    body3 = body[len1 + len2 : len1 + len2 + len3]
    body4 = body[len1 + len2 + len3 :]
    return tuple(b[::-1] for b in (body1, body2, body3, body4))


def encode(data):
    """``pack(split(data))``."""
    return pack(split(data))


def decode(block):
    """``join(unpack(block))``."""
    return join(unpack(block))
