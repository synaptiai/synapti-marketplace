"""Tests for fourstream.py.

Expected values are sourced from ISSUE.md (the wire-format spec and its
worked example) or hand-derived from the documented splitting/packing
rules, as noted in each test's docstring/comment. None are captured by
running the implementation and pasting its output.
"""
import unittest

import fourstream


class TestSplit(unittest.TestCase):
    def test_split_divides_into_four_with_remainder_in_stream_four(self):
        # Source: ISSUE.md splitting rule, hand-derived. 10 bytes, seg=2:
        # streams 1-3 get 2 bytes each in order, stream 4 gets the rest (4).
        # Discriminates against the plausible wrong version that gives the
        # remainder to stream 1 instead, which would yield
        # (b"0123", b"45", b"67", b"89").
        data = b"0123456789"
        self.assertEqual(
            fourstream.split(data),
            (b"01", b"23", b"45", b"6789"),
        )

    def test_split_rejects_input_shorter_than_four_bytes(self):
        # Source: ISSUE.md -- "split(data) ... at least 4 bytes, else ValueError".
        with self.assertRaises(ValueError):
            fourstream.split(b"abc")


class TestJoin(unittest.TestCase):
    def test_join_concatenates_four_streams_in_order(self):
        # Source: hand-derived inverse of the split() example above.
        self.assertEqual(
            fourstream.join((b"01", b"23", b"45", b"6789")),
            b"0123456789",
        )

    def test_join_rejects_wrong_stream_count(self):
        # Source: ISSUE.md -- "join is the inverse: it concatenates exactly
        # four streams in order (ValueError for any other count)."
        with self.assertRaises(ValueError):
            fourstream.join((b"01", b"23", b"45"))
        with self.assertRaises(ValueError):
            fourstream.join((b"01", b"23", b"45", b"67", b"89"))


class TestPack(unittest.TestCase):
    def test_pack_builds_little_endian_table_and_reverses_each_stream(self):
        # Source: ISSUE.md worked example, verbatim:
        # pack((b"ab", b"c", b"def", b"gh")) is
        #   b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        # This single assertion discriminates two risk-map rows at once:
        #  - whole-block reversal instead of per-stream reversal would
        #    produce b"hgfedcba" as the body (reverse of b"abcdefgh") rather
        #    than b"ba"+b"c"+b"fed"+b"hg";
        #  - big-endian table encoding would start b"\x00\x02" rather than
        #    b"\x02\x00" for a stream-1 length of 2.
        self.assertEqual(
            fourstream.pack((b"ab", b"c", b"def", b"gh")),
            b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg",
        )

    def test_pack_accepts_stream_at_exactly_max_length(self):
        # Source: ISSUE.md -- "Streams 1-3 may each be at most 65535 bytes."
        # Discriminates an off-by-one boundary check (`>=` vs `>` 65535):
        # a stream of exactly 65535 bytes must be accepted.
        s1 = bytes(i % 251 for i in range(65535))  # len == 65535, varied bytes
        self.assertEqual(len(s1), 65535)
        block = fourstream.pack((s1, b"c", b"def", b"gh"))
        self.assertEqual(block[0:2], (65535).to_bytes(2, "little"))

    def test_pack_rejects_stream_over_max_length(self):
        # Source: ISSUE.md -- "pack raises ValueError otherwise" for streams
        # 1-3 over 65535 bytes.
        s1 = b"\x00" * 65536
        with self.assertRaises(ValueError):
            fourstream.pack((s1, b"c", b"def", b"gh"))

    def test_pack_rejects_wrong_stream_count(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"ab", b"c", b"def"))


class TestUnpack(unittest.TestCase):
    def test_unpack_reads_body_after_the_six_byte_header(self):
        # Source: ISSUE.md worked example (same block as test_pack above),
        # hand-built directly rather than produced via pack(), so this test
        # does not depend on pack()'s correctness. Discriminates the "no
        # header skip" bug: reading bodies from offset 0 would make the
        # first element derive from table bytes (b"\x02\x00...") instead of
        # the real stream-1 body at offset 6.
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        self.assertEqual(
            fourstream.unpack(block),
            (b"ab", b"c", b"def", b"gh"),
        )

    def test_unpack_rejects_block_shorter_than_header(self):
        # Source: ISSUE.md -- "unpack raises ValueError when the block is
        # shorter than 6 bytes."
        with self.assertRaises(ValueError):
            fourstream.unpack(b"\x01\x02\x03")

    def test_unpack_rejects_table_lengths_exceeding_block(self):
        # Source: ISSUE.md -- "...or when the jump-table lengths exceed the
        # block." Table claims lengths 2, 1, 3 (needs 6+6=12 bytes total)
        # but the block supplies only 7 bytes total.
        block = b"\x02\x00\x01\x00\x03\x00" + b"x"
        with self.assertRaises(ValueError):
            fourstream.unpack(block)


class TestRoundtrip(unittest.TestCase):
    def test_roundtrip_encode_matches_hand_derived_block(self):
        # Source: hand-derived from ISSUE.md's splitting rule and worked
        # pack example. data = b"abcdefgh" (8 bytes, non-degenerate: all
        # distinct bytes). seg = 8 // 4 = 2, so split gives
        # (b"ab", b"cd", b"ef", b"gh"). Table = lengths (2, 2, 2) LE.
        # Bodies reversed per-stream (every stream, including stream 4, per
        # ISSUE.md's own worked example where b"gh" becomes b"hg"):
        # b"ba" + b"dc" + b"fe" + b"hg".
        data = b"abcdefgh"
        expected_block = (
            (2).to_bytes(2, "little")
            + (2).to_bytes(2, "little")
            + (2).to_bytes(2, "little")
            + b"ba"
            + b"dc"
            + b"fe"
            + b"hg"
        )
        self.assertEqual(fourstream.encode(data), expected_block)
        self.assertEqual(fourstream.decode(expected_block), data)

    def test_roundtrip_decode_of_encode_for_lengths_four_to_forty(self):
        # Non-degenerate inputs: strictly varied byte values (not all-equal,
        # not palindromic), one for every length from 4 to 40 inclusive, per
        # ISSUE.md's split domain (data must be >= 4 bytes).
        for length in range(4, 41):
            data = bytes((i * 7 + 3) % 256 for i in range(length))
            with self.subTest(length=length):
                self.assertEqual(fourstream.decode(fourstream.encode(data)), data)


if __name__ == "__main__":
    unittest.main()
