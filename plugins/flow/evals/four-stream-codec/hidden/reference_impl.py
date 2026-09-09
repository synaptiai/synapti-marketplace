"""Reference implementation of the four-stream block codec (spec: scaffold/ISSUE.md).

The hidden suite (hidden/test_hidden.py) was written from the spec and then
checked against this file. Keep the two in sync: any change to the spec must
be mirrored here and re-verified with `flow-eval-run.sh --check-cases`.
"""

TABLE_SIZE = 6
MAX_TABLE_LENGTH = 0xFFFF
MIN_SPLIT_SIZE = 4


def split(data):
    data = bytes(data)
    n = len(data)
    if n < MIN_SPLIT_SIZE:
        raise ValueError("split needs at least %d bytes, got %d" % (MIN_SPLIT_SIZE, n))
    seg = n // 4
    return (data[0:seg], data[seg:2 * seg], data[2 * seg:3 * seg], data[3 * seg:])


def join(streams):
    streams = tuple(bytes(s) for s in streams)
    if len(streams) != 4:
        raise ValueError("join expects exactly 4 streams, got %d" % len(streams))
    return b"".join(streams)


def pack(streams):
    streams = tuple(bytes(s) for s in streams)
    if len(streams) != 4:
        raise ValueError("pack expects exactly 4 streams, got %d" % len(streams))
    table = bytearray()
    for s in streams[:3]:
        if len(s) > MAX_TABLE_LENGTH:
            raise ValueError("stream length %d exceeds jump-table maximum %d" % (len(s), MAX_TABLE_LENGTH))
        table += len(s).to_bytes(2, "little")
    body = b"".join(s[::-1] for s in streams)
    return bytes(table) + body


def unpack(block):
    block = bytes(block)
    if len(block) < TABLE_SIZE:
        raise ValueError("block shorter than the %d-byte jump table" % TABLE_SIZE)
    lengths = [int.from_bytes(block[i:i + 2], "little") for i in (0, 2, 4)]
    if TABLE_SIZE + sum(lengths) > len(block):
        raise ValueError("jump table lengths exceed block size")
    out = []
    pos = TABLE_SIZE
    for length in lengths:
        out.append(block[pos:pos + length][::-1])
        pos += length
    out.append(block[pos:][::-1])
    return tuple(out)


def encode(data):
    return pack(split(data))


def decode(block):
    return join(unpack(block))
