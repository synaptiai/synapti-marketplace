"""Tests for fourstream.py. See ISSUE.md for the wire format / splitting rule
and .decisions/issue-1.md for the captured specification and risk map.

Expected-value sourcing: all expected values below are either taken verbatim
from ISSUE.md / .decisions/issue-1.md (the spec and its worked example), or
hand-computed from the spec's stated rules (noted inline where so derived).
No expected value is obtained by running the implementation.
"""
import unittest

import fourstream


class SplitTests(unittest.TestCase):
    def test_split_len_div_four_rule_remainder_to_stream_four(self):
        # Source: ISSUE.md "Splitting rule" worked example: 10 bytes split as
        # 2, 2, 2, 4. Input is 10 distinct bytes (non-degenerate: order and
        # position matter) so a remainder-to-stream-1 bug (lengths 4,2,2,2)
        # or ceiling-division bug would produce different, distinguishable
        # stream contents, not just different lengths.
        data = b"0123456789"
        streams = fourstream.split(data)
        self.assertEqual(
            streams,
            (b"01", b"23", b"45", b"6789"),
        )
        self.assertEqual(tuple(len(s) for s in streams), (2, 2, 2, 4))

    def test_split_exact_multiple_of_four(self):
        # Hand-derived from the spec's seg = len(data)//4 rule: for 8 bytes,
        # seg = 2, so streams 1-3 get 2 bytes each and stream 4 gets the
        # remaining 2 (not 0), since remainder = len % 4 = 0 is appended to
        # whatever seg already gives stream 4.
        data = b"abcdefgh"
        streams = fourstream.split(data)
        self.assertEqual(streams, (b"ab", b"cd", b"ef", b"gh"))

    def test_split_rejects_input_shorter_than_four_bytes(self):
        # Source: ISSUE.md "split(data) cuts data (at least 4 bytes, else
        # ValueError)". 3 bytes is the largest below-threshold, most
        # discriminating boundary value (not degenerate 0-length).
        with self.assertRaises(ValueError):
            fourstream.split(b"abc")

    def test_split_minimum_four_bytes_one_byte_per_stream(self):
        # Hand-derived: seg = 4 // 4 = 1, so streams 1-3 get 1 byte each and
        # stream 4 gets the remaining 1 byte (remainder = 0, so seg applies
        # uniformly). Confirms the boundary at exactly MIN_SPLIT_SIZE works.
        data = b"wxyz"
        streams = fourstream.split(data)
        self.assertEqual(streams, (b"w", b"x", b"y", b"z"))


class JoinTests(unittest.TestCase):
    def test_join_concatenates_exactly_four_streams_in_order(self):
        # Source: ISSUE.md "join is the inverse [of split]: it concatenates
        # exactly four streams in order". Streams of differing, distinct
        # content (not degenerate/identical) so order-sensitivity is
        # verified, not just concatenation length.
        result = fourstream.join((b"ab", b"c", b"def", b"gh"))
        self.assertEqual(result, b"abcdefgh")

    def test_join_rejects_five_streams(self):
        # Source: .decisions/issue-1.md risk map row "join/pack
        # stream-count validation": the plausible wrong version checks
        # `len(streams) < 4` (accepting more than four) instead of `!= 4`.
        # Five streams is the discriminating input: right raises
        # ValueError; wrong (`< 4` check) returns b"abcde".
        with self.assertRaises(ValueError):
            fourstream.join((b"a", b"b", b"c", b"d", b"e"))

    def test_join_rejects_three_streams(self):
        # Source: ISSUE.md "ValueError for any other count". Below-four
        # count, complementary boundary to the five-stream case above.
        with self.assertRaises(ValueError):
            fourstream.join((b"a", b"b", b"c"))


class PackTests(unittest.TestCase):
    def test_pack_worked_example_from_issue(self):
        # Source: ISSUE.md "Worked example" verbatim:
        # pack((b"ab", b"c", b"def", b"gh")) ==
        #   b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        # This single example simultaneously discriminates the two
        # plausible-wrong versions in the risk map:
        #   - per-stream reversal vs whole-body reversal: streams have
        #     different lengths (2,1,3,2) and non-palindromic content, so a
        #     whole-body reverse produces a different byte sequence than
        #     reversing each stream independently.
        #   - endianness: stream lengths 2, 1, 3 are distinct non-zero,
        #     non-byte-swap-invariant values, so little- vs big-endian
        #     encodings differ.
        result = fourstream.pack((b"ab", b"c", b"def", b"gh"))
        expected = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        self.assertEqual(result, expected)

    def test_pack_jump_table_is_little_endian(self):
        # Source: .decisions/issue-1.md risk map row "jump-table integer
        # endianness": right encodes length 1 as table bytes starting
        # b"\x01\x00"; wrong (big-endian) would start b"\x00\x01". Using
        # length 1 (not 0, which is endianness-invariant) discriminates.
        result = fourstream.pack((b"a", b"", b"", b""))
        self.assertEqual(result[0:2], b"\x01\x00")

    def test_pack_reverses_each_stream_independently_not_whole_body(self):
        # Source: .decisions/issue-1.md risk map row "per-stream byte
        # reversal in pack/unpack". Streams of equal length 2 with distinct
        # content so a whole-body reverse (which would also swap the
        # *order* of the stream bytes across boundaries) is distinguishable
        # from independent per-stream reversal.
        result = fourstream.pack((b"AB", b"CD", b"EF", b"GH"))
        body = result[fourstream.TABLE_SIZE:]
        # Right: each 2-byte stream reversed on its own, concatenated in
        # order 1,2,3,4: "BA"+"DC"+"FE"+"HG".
        self.assertEqual(body, b"BADCFEHG")
        # Sanity: this must differ from the whole-body-reverse bug, which
        # would reverse "ABCDEFGH" as one unit -> "HGFEDCBA".
        self.assertNotEqual(body, b"HGFEDCBA")

    def test_pack_rejects_stream_over_65535_bytes(self):
        # Source: ISSUE.md "Streams 1-3 may each be at most 65535 bytes
        # (pack raises ValueError otherwise)". 65536 is the smallest
        # over-limit value, the most discriminating boundary case.
        too_long = b"x" * (fourstream.MAX_TABLE_LENGTH + 1)
        with self.assertRaises(ValueError):
            fourstream.pack((too_long, b"", b"", b""))

    def test_pack_accepts_stream_at_exactly_65535_bytes(self):
        # Complementary boundary: the spec says "at most 65535", so exactly
        # 65535 must be accepted, not rejected.
        max_len = b"x" * fourstream.MAX_TABLE_LENGTH
        result = fourstream.pack((max_len, b"", b"", b""))
        self.assertEqual(result[0:2], b"\xff\xff")

    def test_pack_rejects_five_streams(self):
        # Source: .decisions/issue-1.md risk map row "join/pack
        # stream-count validation" — same discriminating input class as
        # join's test: five streams must raise, not silently pack via a
        # `< 4` check.
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c", b"d", b"e"))

    def test_pack_empty_streams_all_round(self):
        # Hand-derived from the wire format: all-empty streams still
        # produce a full 6-byte table of zero lengths and an empty body.
        result = fourstream.pack((b"", b"", b"", b""))
        self.assertEqual(result, b"\x00\x00\x00\x00\x00\x00")


class UnpackTests(unittest.TestCase):
    def test_unpack_worked_example_from_issue(self):
        # Source: ISSUE.md worked example, used in reverse: the packed
        # block for pack((b"ab", b"c", b"def", b"gh")) must unpack back to
        # those exact (non-palindromic, distinct-length) streams.
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        result = fourstream.unpack(block)
        self.assertEqual(result, (b"ab", b"c", b"def", b"gh"))

    def test_unpack_rejects_block_shorter_than_table(self):
        # Source: ISSUE.md "unpack raises ValueError when the block is
        # shorter than 6 bytes". 5 bytes is the largest below-threshold
        # boundary value.
        with self.assertRaises(ValueError):
            fourstream.unpack(b"\x00\x00\x00\x00\x00")

    def test_unpack_rejects_table_lengths_exceeding_block(self):
        # Source: ISSUE.md "...or when the jump-table lengths exceed the
        # block". Table claims stream 1 is 10 bytes but no body follows.
        block = b"\x0a\x00\x00\x00\x00\x00"
        with self.assertRaises(ValueError):
            fourstream.unpack(block)

    def test_unpack_accepts_block_where_table_exactly_consumes_remainder(self):
        # Source: .decisions/issue-1.md risk map row "unpack block-length
        # boundary check": the plausible wrong version uses `>=` instead of
        # `>`, rejecting a block where stream 4 is legitimately empty and
        # the table lengths exactly equal the remaining bytes. Built via
        # pack((b"ab", b"cd", b"ef", b"")) per the spec's own worked
        # mechanism (not a literal from running unpack itself).
        block = fourstream.pack((b"ab", b"cd", b"ef", b""))
        result = fourstream.unpack(block)
        self.assertEqual(result, (b"ab", b"cd", b"ef", b""))

    def test_unpack_rejects_table_lengths_summing_one_over_block(self):
        # Hand-derived boundary adjacent to the case above: truncating the
        # last byte of a valid block makes the table claim one more byte
        # than is actually present, which must raise. Both the correct
        # (`>`) and off-by-one (`>=`) comparisons reject this particular
        # input; it is supplementary boundary coverage, not the
        # discriminating case -- that is
        # test_unpack_accepts_block_where_table_exactly_consumes_remainder
        # above, where only the correct comparison succeeds.
        block = fourstream.pack((b"ab", b"cd", b"ef", b""))
        truncated = block[:-1]
        with self.assertRaises(ValueError):
            fourstream.unpack(truncated)


class RoundtripTests(unittest.TestCase):
    def test_roundtrip_encode_matches_hand_derived_block(self):
        # Hand-derived from ISSUE.md's own rules composed together:
        # encode = pack(split(data)). For data = b"0123456789ab" (12
        # bytes, distinct non-repeating content so byte order matters):
        # seg = 12 // 4 = 3 -> streams (b"012", b"345", b"678", b"9ab").
        # pack: table = lengths 3,3,3 little-endian = b"\x03\x00\x03\x00\x03\x00"
        # bodies reversed per-stream: b"210"+b"543"+b"876"+b"ba9".
        data = b"0123456789ab"
        expected = (
            b"\x03\x00\x03\x00\x03\x00" + b"210" + b"543" + b"876" + b"ba9"
        )
        self.assertEqual(fourstream.encode(data), expected)

    def test_roundtrip_decode_matches_hand_derived_data(self):
        # Inverse of the above, built independently from the spec's rules
        # rather than by calling encode: decode(block) == join(unpack(block)).
        block = b"\x03\x00\x03\x00\x03\x00" + b"210" + b"543" + b"876" + b"ba9"
        self.assertEqual(fourstream.decode(block), b"0123456789ab")

    def test_roundtrip_every_length_from_four_to_forty(self):
        # Source: ISSUE.md acceptance criterion "round-trip data of every
        # length from 4 to 40". Uses non-repeating byte sequences (0..N-1
        # mod 256) rather than a degenerate constant-byte or palindromic
        # input, so a bug that mixes up stream order, reverses the wrong
        # scope, or mis-slices boundaries would produce wrong bytes rather
        # than accidentally matching through symmetry.
        for length in range(4, 41):
            data = bytes(range(length))
            with self.subTest(length=length):
                self.assertEqual(fourstream.decode(fourstream.encode(data)), data)


if __name__ == "__main__":
    unittest.main()
