"""Four-stream block codec. See ISSUE.md for the wire format and splitting rule."""

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
    stream1 = data[0:seg]
    stream2 = data[seg : 2 * seg]
    stream3 = data[2 * seg : 3 * seg]
    stream4 = data[3 * seg :]
    return (stream1, stream2, stream3, stream4)


def join(streams):
    """Concatenate exactly four streams in order. Raises ValueError otherwise."""
    streams = tuple(streams)
    if len(streams) != 4:
        raise ValueError(f"join requires exactly 4 streams, got {len(streams)}")
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
        raise ValueError(f"pack requires exactly 4 streams, got {len(streams)}")
    for i in range(3):
        if len(streams[i]) > MAX_TABLE_LENGTH:
            raise ValueError(
                f"stream {i + 1} is {len(streams[i])} bytes, "
                f"exceeding the {MAX_TABLE_LENGTH}-byte limit"
            )
    table = b"".join(len(streams[i]).to_bytes(2, "little") for i in range(3))
    bodies = b"".join(stream[::-1] for stream in streams)
    return table + bodies


def unpack(block):
    """Inverse of :func:`pack`. Returns a 4-tuple of bytes.

    Raises ValueError if ``block`` is shorter than the 6-byte jump table or
    if the table lengths exceed the block.
    """
    if len(block) < TABLE_SIZE:
        raise ValueError(
            f"block must be at least {TABLE_SIZE} bytes, got {len(block)}"
        )
    len1 = int.from_bytes(block[0:2], "little")
    len2 = int.from_bytes(block[2:4], "little")
    len3 = int.from_bytes(block[4:6], "little")
    remaining = len(block) - TABLE_SIZE
    if len1 + len2 + len3 > remaining:
        raise ValueError(
            f"table lengths {(len1, len2, len3)} exceed the "
            f"{remaining} bytes remaining in the block"
        )
    offset = TABLE_SIZE
    body1 = block[offset : offset + len1]
    offset += len1
    body2 = block[offset : offset + len2]
    offset += len2
    body3 = block[offset : offset + len3]
    offset += len3
    body4 = block[offset:]
    return (body1[::-1], body2[::-1], body3[::-1], body4[::-1])


def encode(data):
    """``pack(split(data))``."""
    return pack(split(data))


def decode(block):
    """``join(unpack(block))``."""
    return join(unpack(block))
