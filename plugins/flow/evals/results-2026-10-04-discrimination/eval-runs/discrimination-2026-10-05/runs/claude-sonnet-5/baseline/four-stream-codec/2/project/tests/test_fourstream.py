import struct
import unittest

import fourstream


class SplitTests(unittest.TestCase):
    def test_split_basic_rule(self):
        data = b"0123456789"  # 10 bytes -> seg=2 -> 2,2,2,4
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual(s1, b"01")
        self.assertEqual(s2, b"23")
        self.assertEqual(s3, b"45")
        self.assertEqual(s4, b"6789")

    def test_split_exact_multiple_of_four(self):
        data = b"abcdefgh"  # 8 bytes -> seg=2 -> 2,2,2,2
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual((s1, s2, s3, s4), (b"ab", b"cd", b"ef", b"gh"))

    def test_split_minimum_length(self):
        s1, s2, s3, s4 = fourstream.split(b"abcd")
        self.assertEqual((s1, s2, s3, s4), (b"a", b"b", b"c", b"d"))

    def test_split_rejects_short_input(self):
        for n in (0, 1, 2, 3):
            with self.assertRaises(ValueError):
                fourstream.split(b"x" * n)

    def test_split_total_length_preserved(self):
        for n in range(4, 41):
            data = bytes(range(n % 256)) if n >= 256 else bytes(i % 256 for i in range(n))
            streams = fourstream.split(data)
            self.assertEqual(sum(len(s) for s in streams), n)
            self.assertEqual(b"".join(streams), data)


class JoinTests(unittest.TestCase):
    def test_join_concatenates_in_order(self):
        self.assertEqual(
            fourstream.join((b"ab", b"c", b"def", b"gh")), b"abcdefgh"
        )

    def test_join_rejects_wrong_count(self):
        for streams in ((), (b"a",), (b"a", b"b"), (b"a", b"b", b"c"),
                         (b"a", b"b", b"c", b"d", b"e")):
            with self.assertRaises(ValueError):
                fourstream.join(streams)

    def test_join_is_inverse_of_split(self):
        data = b"0123456789abcdef"
        self.assertEqual(fourstream.join(fourstream.split(data)), data)


class PackTests(unittest.TestCase):
    def test_pack_worked_example(self):
        block = fourstream.pack((b"ab", b"c", b"def", b"gh"))
        expected = (
            b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        )
        self.assertEqual(block, expected)

    def test_pack_jump_table_values(self):
        block = fourstream.pack((b"xx", b"yyy", b"z", b"tail"))
        len1, len2, len3 = struct.unpack("<HHH", block[:6])
        self.assertEqual((len1, len2, len3), (2, 3, 1))

    def test_pack_reverses_each_stream_independently(self):
        block = fourstream.pack((b"abc", b"de", b"f", b""))
        body = block[6:]
        self.assertEqual(body, b"cba" + b"ed" + b"f" + b"")

    def test_pack_all_empty_streams(self):
        block = fourstream.pack((b"", b"", b"", b""))
        self.assertEqual(block, b"\x00\x00\x00\x00\x00\x00")

    def test_pack_empty_stream4_allowed(self):
        block = fourstream.pack((b"a", b"b", b"c", b""))
        self.assertEqual(block, b"\x01\x00\x01\x00\x01\x00" + b"a" + b"b" + b"c")

    def test_pack_rejects_wrong_count(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c"))
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c", b"d", b"e"))

    def test_pack_rejects_oversized_stream1(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"x" * 65536, b"", b"", b""))

    def test_pack_rejects_oversized_stream3(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"", b"", b"x" * 65536, b""))

    def test_pack_allows_max_size_stream(self):
        s = b"x" * 65535
        block = fourstream.pack((s, b"", b"", b""))
        self.assertTrue(block.startswith(b"\xff\xff\x00\x00\x00\x00"))

    def test_pack_allows_huge_stream4(self):
        s4 = b"y" * 100000
        block = fourstream.pack((b"a", b"b", b"c", s4))
        self.assertEqual(block[6:9], b"a" + b"b" + b"c")
        self.assertEqual(block[9:], s4[::-1])


class UnpackTests(unittest.TestCase):
    def test_unpack_hand_built_block(self):
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        streams = fourstream.unpack(block)
        self.assertEqual(streams, (b"ab", b"c", b"def", b"gh"))

    def test_unpack_all_empty(self):
        block = b"\x00\x00\x00\x00\x00\x00"
        self.assertEqual(fourstream.unpack(block), (b"", b"", b"", b""))

    def test_unpack_rejects_short_block(self):
        for n in range(0, 6):
            with self.assertRaises(ValueError):
                fourstream.unpack(b"\x00" * n)

    def test_unpack_rejects_overlong_table_lengths(self):
        # Claims stream1 length of 10 but block body is too short.
        block = struct.pack("<HHH", 10, 0, 0) + b"short"
        with self.assertRaises(ValueError):
            fourstream.unpack(block)

    def test_unpack_exact_minimum_block(self):
        block = b"\x00\x00\x00\x00\x00\x00"
        streams = fourstream.unpack(block)
        self.assertEqual(len(streams), 4)

    def test_unpack_is_inverse_of_pack(self):
        original = (b"abc", b"", b"xyz12", b"tail-of-data")
        block = fourstream.pack(original)
        self.assertEqual(fourstream.unpack(block), original)


class RoundtripTests(unittest.TestCase):
    def test_roundtrip_worked_example(self):
        block = fourstream.pack((b"ab", b"c", b"def", b"gh"))
        expected = (
            b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        )
        self.assertEqual(block, expected)
        self.assertEqual(fourstream.unpack(block), (b"ab", b"c", b"def", b"gh"))

    def test_roundtrip_encode_matches_hand_derived_block(self):
        data = b"0123456789"  # splits to 01,23,45,6789
        block = fourstream.encode(data)
        expected = (
            struct.pack("<HHH", 2, 2, 2)
            + b"10" + b"32" + b"54" + b"9876"
        )
        self.assertEqual(block, expected)

    def test_roundtrip_decode_matches_hand_derived_block(self):
        block = (
            struct.pack("<HHH", 2, 2, 2)
            + b"10" + b"32" + b"54" + b"9876"
        )
        self.assertEqual(fourstream.decode(block), b"0123456789")

    def test_roundtrip_all_lengths_4_to_40(self):
        for n in range(4, 41):
            data = bytes((i * 7 + 3) % 256 for i in range(n))
            block = fourstream.encode(data)
            self.assertEqual(fourstream.decode(block), data)

    def test_roundtrip_encode_decode_are_inverse_functions(self):
        data = b"The quick brown fox jumps over the lazy dog!"
        self.assertEqual(fourstream.decode(fourstream.encode(data)), data)


if __name__ == "__main__":
    unittest.main()
