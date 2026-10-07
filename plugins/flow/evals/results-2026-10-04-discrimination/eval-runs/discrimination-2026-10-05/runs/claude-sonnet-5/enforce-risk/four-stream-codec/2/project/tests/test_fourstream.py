"""Tests for fourstream.py. See ISSUE.md for the wire format and splitting rule.

Expected values in these tests are sourced from ISSUE.md / .decisions/issue-1.md
(the spec), hand computation per the documented rules, or the worked example
in ISSUE.md -- never from running fourstream.py and pasting its output.
"""
import unittest

import fourstream


class SplitTests(unittest.TestCase):
    def test_split_divides_len_over_4_with_remainder_in_stream_4(self):
        # Source: ISSUE.md splitting rule, seg = len(data) // 4; remainder
        # goes to stream 4. 10 bytes -> seg = 10 // 4 = 2, so streams 1-3
        # get 2 bytes each (6 total) and stream 4 gets the remaining 4.
        # Hand-derived expected streams (not run through the implementation):
        # data = b"abcdefghij"
        #   stream1 = data[0:2]  = b"ab"
        #   stream2 = data[2:4]  = b"cd"
        #   stream3 = data[4:6]  = b"ef"
        #   stream4 = data[6:10] = b"ghij"
        # This input discriminates against a wrong implementation that gives
        # the remainder to stream 1 (which would produce lengths 4,2,2,2
        # instead of the right 2,2,2,4), since byte values differ per
        # position (not a degenerate repeated-byte input).
        data = b"abcdefghij"
        result = fourstream.split(data)
        self.assertEqual(result, (b"ab", b"cd", b"ef", b"ghij"))
        self.assertEqual([len(s) for s in result], [2, 2, 2, 4])

    def test_split_rejects_input_shorter_than_4_bytes(self):
        # Source: ISSUE.md -- "split(data) ... (at least 4 bytes, else
        # ValueError)". 3 bytes is the largest rejected size (discriminates
        # an off-by-one boundary from the 4-byte minimum).
        with self.assertRaises(ValueError):
            fourstream.split(b"abc")


class JoinTests(unittest.TestCase):
    def test_join_concatenates_four_streams_in_order(self):
        # Source: ISSUE.md -- "join is the inverse [of split]: it
        # concatenates exactly four streams in order". Hand-derived
        # expected value: concatenating b"ab", b"c", b"def", b"gh" in
        # order gives b"ab" + b"c" + b"def" + b"gh" = b"abcdefgh".
        # Streams have distinct content and different lengths, so an
        # implementation that reordered or dropped a stream would not
        # produce this exact value.
        result = fourstream.join((b"ab", b"c", b"def", b"gh"))
        self.assertEqual(result, b"abcdefgh")

    def test_join_rejects_stream_count_other_than_four(self):
        # Source: ISSUE.md -- "join ... ValueError for any other count".
        with self.assertRaises(ValueError):
            fourstream.join((b"a", b"b", b"c"))
        with self.assertRaises(ValueError):
            fourstream.join((b"a", b"b", b"c", b"d", b"e"))


class PackTests(unittest.TestCase):
    def test_pack_worked_example_jump_table_and_reversed_bodies(self):
        # Source: ISSUE.md worked example, verbatim:
        #   pack((b"ab", b"c", b"def", b"gh")) ==
        #   b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        # Table: len(stream1)=2 -> u16 LE b"\x02\x00";
        #        len(stream2)=1 -> u16 LE b"\x01\x00";
        #        len(stream3)=3 -> u16 LE b"\x03\x00".
        # Bodies: each stream reversed independently:
        #   b"ab"[::-1]  = b"ba"
        #   b"c"[::-1]   = b"c"
        #   b"def"[::-1] = b"fed"
        #   b"gh"[::-1]  = b"hg"
        # This discriminates two risk areas at once:
        #  - per-stream reversal: a wrong impl that reverses the whole
        #    concatenated body (b"ab"+b"c"+b"def"+b"gh")[::-1] would give
        #    b"hgfedcba", not the per-stream-reversed b"ba"+b"c"+b"fed"+b"hg".
        #  - endianness: a wrong big-endian table would start b"\x00\x02"
        #    instead of the right b"\x02\x00" (length 2 is non-zero and
        #    under 256, so the two encodings differ).
        expected = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        result = fourstream.pack((b"ab", b"c", b"def", b"gh"))
        self.assertEqual(result, expected)

    def test_pack_rejects_stream_count_other_than_four(self):
        # Source: ISSUE.md -- "Raises ValueError if there are not exactly
        # four streams".
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c"))
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c", b"d", b"e"))

    def test_pack_accepts_65535_byte_stream_and_rejects_65536(self):
        # Source: ISSUE.md -- "Streams 1-3 may each be at most 65535 bytes
        # (pack raises ValueError otherwise)". This discriminates an
        # off-by-one boundary check (>= used where > is meant, or vice
        # versa): exactly 65535 must succeed (table entry 0xFFFF), exactly
        # 65536 must raise.
        max_stream = b"x" * 0xFFFF
        result = fourstream.pack((max_stream, b"", b"", b""))
        self.assertEqual(result[0:2], b"\xff\xff")
        # 6-byte jump table (ISSUE.md) + the 65535-byte stream 1 body +
        # three empty bodies.
        self.assertEqual(len(result), 6 + 0xFFFF)

        over_max_stream = b"x" * (0xFFFF + 1)
        with self.assertRaises(ValueError):
            fourstream.pack((over_max_stream, b"", b"", b""))


class UnpackTests(unittest.TestCase):
    def test_unpack_worked_example_inverse_of_pack(self):
        # Source: ISSUE.md worked example (inverse direction). The block
        # bytes are taken verbatim from ISSUE.md's pack example; the
        # expected streams are the original (pre-reversal) stream values
        # from that same example, not derived by calling pack/unpack.
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        result = fourstream.unpack(block)
        self.assertEqual(result, (b"ab", b"c", b"def", b"gh"))

    def test_unpack_rejects_block_shorter_than_6_bytes(self):
        # Source: ISSUE.md -- "unpack raises ValueError when the block is
        # shorter than 6 bytes". 5 bytes is the largest rejected size
        # (discriminates an off-by-one on the 6-byte minimum).
        with self.assertRaises(ValueError):
            fourstream.unpack(b"\x00\x00\x00\x00\x00")

    def test_unpack_minimal_6_byte_block_with_zero_lengths(self):
        # Source: hand computation from the spec: a block of exactly 6
        # bytes with all three table lengths 0 is valid (streams 1-3 are
        # empty, and stream 4 is "whatever remains" = nothing). This
        # discriminates an off-by-one that rejects the valid 6-byte
        # minimum (e.g. checking len(block) > 6 instead of >= 6).
        block = b"\x00\x00\x00\x00\x00\x00"
        result = fourstream.unpack(block)
        self.assertEqual(result, (b"", b"", b"", b""))

    def test_unpack_rejects_table_lengths_exceeding_block(self):
        # Source: ISSUE.md -- "unpack raises ValueError ... when the
        # jump-table lengths exceed the block". Table claims stream 1 is
        # 10 bytes (u16 LE 10 = b"\x0a\x00") but only 2 bytes of body
        # follow in total, so the claimed length exceeds the available
        # block data.
        block = b"\x0a\x00\x00\x00\x00\x00" + b"xy"
        with self.assertRaises(ValueError):
            fourstream.unpack(block)


class RoundtripTests(unittest.TestCase):
    def test_roundtrip_encode_matches_hand_derived_block(self):
        # Source: hand computation per the ISSUE.md rules (not run through
        # the implementation). data = b"abcdefghij" (10 bytes).
        # split: seg = 10 // 4 = 2 ->
        #   stream1=b"ab", stream2=b"cd", stream3=b"ef", stream4=b"ghij"
        # pack: table = u16 LE lengths (2, 2, 2) = b"\x02\x00\x02\x00\x02\x00"
        #   bodies (each stream reversed independently):
        #     b"ab"[::-1]   = b"ba"
        #     b"cd"[::-1]   = b"dc"
        #     b"ef"[::-1]   = b"fe"
        #     b"ghij"[::-1] = b"jihg"
        data = b"abcdefghij"
        expected = (
            b"\x02\x00\x02\x00\x02\x00" + b"ba" + b"dc" + b"fe" + b"jihg"
        )
        self.assertEqual(fourstream.encode(data), expected)

    def test_roundtrip_decode_matches_hand_derived_data(self):
        # Inverse of the block built above: decoding it must recover the
        # original 10-byte data, derived by hand, not by calling encode.
        block = b"\x02\x00\x02\x00\x02\x00" + b"ba" + b"dc" + b"fe" + b"jihg"
        self.assertEqual(fourstream.decode(block), b"abcdefghij")

    def test_roundtrip_encode_decode_every_length_4_to_40(self):
        # Covers every length ISSUE.md requires (4 to 40 inclusive).
        # Uses bytes(range(n)) rather than a repeated/uniform byte so that
        # position- and order-sensitive bugs (e.g. reversing the whole
        # body instead of each stream, or misrouting the split remainder)
        # would be caught by a mismatch; a same-byte-repeated input would
        # not discriminate those bugs since reversal/reordering would be
        # invisible.
        for n in range(4, 41):
            data = bytes(range(n))
            with self.subTest(n=n):
                self.assertEqual(fourstream.decode(fourstream.encode(data)), data)


if __name__ == "__main__":
    unittest.main()
