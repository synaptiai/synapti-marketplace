# Issue #1: Implement the four-stream block codec (`fourstream.py`)

## Description

We need a small codec that splits a byte string into four streams and packs
them into one block with a jump table, in the style of Zstandard's
four-stream Huffman literals. Downstream tools already produce and consume
this block layout, so the byte layout below is a wire contract: a block
produced by `pack` must be readable by those tools, and a block they produce
must decode here. Round-tripping through our own code is not sufficient
evidence of correctness.

`fourstream.py` in this directory contains the public API with docstrings
and `raise NotImplementedError` bodies. That skeleton is the starting point
of this task, not a placeholder to keep: replace every body with a working
implementation. Standard library only, Python 3.

## Wire format

- A block is a 6-byte **jump table** followed by the four stream bodies.
- The jump table holds the lengths of streams 1, 2 and 3 as three unsigned
  16-bit **little-endian** integers, in that order. Stream 4 has no table
  entry: its length is whatever remains after the first three bodies.
- The bodies follow the table in stream order 1, 2, 3, 4.
- Each body stores its stream's bytes in **reverse order** (last byte first).
  Each stream is reversed on its own; the block body as a whole is not.
- Streams 1-3 may each be at most 65535 bytes (`pack` raises `ValueError`
  otherwise). Stream 4 is unbounded. Any stream, including stream 4, may be
  empty.

Worked example: `pack((b"ab", b"c", b"def", b"gh"))` is
`b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"`.

## Splitting rule

`split(data)` cuts `data` (at least 4 bytes, else `ValueError`) into four
streams: `seg = len(data) // 4`; streams 1-3 receive `seg` bytes each, in
order, and stream 4 receives all remaining bytes (so stream 4 is never
shorter than the others). Example: 10 bytes split as 2, 2, 2, 4. `join` is
the inverse: it concatenates exactly four streams in order (`ValueError`
for any other count).

## API

See the docstrings in `fourstream.py`: `split`, `join`, `pack`, `unpack`,
`encode` (= `pack(split(data))`) and `decode` (= `join(unpack(block))`).
`unpack` raises `ValueError` when the block is shorter than 6 bytes or when
the jump-table lengths exceed the block.

## Non-goals

- No compression, no entropy coding: bodies are raw bytes.
- No streaming interface; whole blocks in memory.

## Acceptance Criteria

Write your tests in `tests/test_fourstream.py` (standard-library
`unittest`). Each criterion names a `-k` keyword; the tests that verify it
must contain that keyword in their name so the command selects them.

- [ ] `split` follows the `len // 4` rule with the remainder in stream 4 and rejects inputs shorter than 4 bytes — verify: `python3 -m unittest tests.test_fourstream -k split`
- [ ] `pack` produces the documented jump table and per-stream reversed bodies for hand-written inputs, and rejects streams 1-3 over 65535 bytes — verify: `python3 -m unittest tests.test_fourstream -k pack`
- [ ] `unpack` reads a hand-built block into the right streams and rejects short blocks and over-long table lengths — verify: `python3 -m unittest tests.test_fourstream -k unpack`
- [ ] `encode` and `decode` match hand-derived blocks and round-trip data of every length from 4 to 40 — verify: `python3 -m unittest tests.test_fourstream -k roundtrip`
- [ ] The whole suite passes — verify: `python3 -m unittest discover -s tests -t . -v`
