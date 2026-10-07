import struct
import unittest

import fourstream


class SplitTests(unittest.TestCase):
    def test_split_follows_len_div_4_rule_with_remainder_in_stream4(self):
        data = bytes(range(10))
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual(s1, data[0:2])
        self.assertEqual(s2, data[2:4])
        self.assertEqual(s3, data[4:6])
        self.assertEqual(s4, data[6:10])
        self.assertEqual(len(s4), 4)

    def test_split_exact_multiple_of_4(self):
        data = bytes(range(8))
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual((s1, s2, s3, s4), (data[0:2], data[2:4], data[4:6], data[6:8]))

    def test_split_minimum_size_4_bytes(self):
        data = b"abcd"
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual((s1, s2, s3), (b"a", b"b", b"c"))
        self.assertEqual(s4, b"d")

    def test_split_rejects_input_shorter_than_4_bytes(self):
        for n in (0, 1, 2, 3):
            with self.assertRaises(ValueError):
                fourstream.split(b"x" * n)


class JoinTests(unittest.TestCase):
    def test_join_concatenates_four_streams_in_order(self):
        self.assertEqual(
            fourstream.join((b"ab", b"c", b"def", b"gh")), b"abcdefgh"
        )

    def test_join_rejects_wrong_count(self):
        for streams in ((), (b"a",), (b"a", b"b"), (b"a", b"b", b"c"),
                         (b"a", b"b", b"c", b"d", b"e")):
            with self.assertRaises(ValueError):
                fourstream.join(streams)


class PackTests(unittest.TestCase):
    def test_pack_produces_documented_jump_table_and_reversed_bodies(self):
        block = fourstream.pack((b"ab", b"c", b"def", b"gh"))
        expected = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        self.assertEqual(block, expected)

    def test_pack_empty_streams(self):
        block = fourstream.pack((b"", b"", b"", b""))
        self.assertEqual(block, b"\x00\x00\x00\x00\x00\x00")

    def test_pack_only_stream4_nonempty(self):
        block = fourstream.pack((b"", b"", b"", b"xyz"))
        self.assertEqual(block, b"\x00\x00\x00\x00\x00\x00" + b"zyx")

    def test_pack_rejects_wrong_stream_count(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c"))

    def test_pack_rejects_stream1_over_65535_bytes(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"x" * 65536, b"", b"", b""))

    def test_pack_rejects_stream2_over_65535_bytes(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"", b"x" * 65536, b"", b""))

    def test_pack_rejects_stream3_over_65535_bytes(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"", b"", b"x" * 65536, b""))

    def test_pack_allows_stream_of_exactly_65535_bytes(self):
        block = fourstream.pack((b"x" * 65535, b"", b"", b""))
        self.assertEqual(block[:6], struct.pack("<HHH", 65535, 0, 0))

    def test_pack_allows_stream4_over_65535_bytes(self):
        block = fourstream.pack((b"", b"", b"", b"x" * 70000))
        self.assertEqual(len(block), 6 + 70000)


class UnpackTests(unittest.TestCase):
    def test_unpack_reads_hand_built_block_into_right_streams(self):
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        streams = fourstream.unpack(block)
        self.assertEqual(streams, (b"ab", b"c", b"def", b"gh"))

    def test_unpack_empty_streams(self):
        block = b"\x00\x00\x00\x00\x00\x00"
        self.assertEqual(fourstream.unpack(block), (b"", b"", b"", b""))

    def test_unpack_rejects_short_block(self):
        for n in range(6):
            with self.assertRaises(ValueError):
                fourstream.unpack(b"x" * n)

    def test_unpack_rejects_over_long_table_lengths(self):
        block = struct.pack("<HHH", 5, 0, 0) + b"abc"
        with self.assertRaises(ValueError):
            fourstream.unpack(block)

    def test_unpack_accepts_exact_fit_table_lengths(self):
        block = struct.pack("<HHH", 1, 1, 1) + b"abc"
        streams = fourstream.unpack(block)
        self.assertEqual(streams, (b"a", b"b", b"c", b""))


class RoundtripTests(unittest.TestCase):
    def test_roundtrip_matches_hand_derived_block(self):
        data = b"abcdefgh"
        block = fourstream.encode(data)
        expected = b"\x02\x00\x02\x00\x02\x00" + b"ba" + b"dc" + b"fe" + b"hg"
        self.assertEqual(block, expected)
        self.assertEqual(fourstream.decode(block), data)

    def test_roundtrip_every_length_from_4_to_40(self):
        for n in range(4, 41):
            data = bytes((i * 7 + 3) % 256 for i in range(n))
            block = fourstream.encode(data)
            self.assertEqual(fourstream.decode(block), data)

    def test_roundtrip_pack_unpack_matches_split_join(self):
        data = bytes(range(37))
        streams = fourstream.split(data)
        block = fourstream.pack(streams)
        self.assertEqual(fourstream.unpack(block), streams)
        self.assertEqual(fourstream.join(fourstream.unpack(block)), data)


if __name__ == "__main__":
    unittest.main()
