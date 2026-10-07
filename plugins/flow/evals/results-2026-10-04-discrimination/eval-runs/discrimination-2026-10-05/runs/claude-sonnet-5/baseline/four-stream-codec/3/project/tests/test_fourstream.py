import struct
import unittest

import fourstream


class SplitTests(unittest.TestCase):
    def test_split_basic_remainder_rule(self):
        data = bytes(range(10))
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual(s1, data[0:2])
        self.assertEqual(s2, data[2:4])
        self.assertEqual(s3, data[4:6])
        self.assertEqual(s4, data[6:10])
        self.assertEqual(len(s4), 4)

    def test_split_exact_multiple_of_four(self):
        data = bytes(range(12))
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual((s1, s2, s3, s4), (data[0:3], data[3:6], data[6:9], data[9:12]))

    def test_split_minimum_length(self):
        data = b"abcd"
        s1, s2, s3, s4 = fourstream.split(data)
        self.assertEqual((s1, s2, s3, s4), (b"a", b"b", b"c", b"d"))

    def test_split_rejects_short_input(self):
        for n in (0, 1, 2, 3):
            with self.assertRaises(ValueError):
                fourstream.split(b"x" * n)

    def test_split_all_lengths_four_to_forty(self):
        for n in range(4, 41):
            data = bytes(range(n % 256)) if n <= 256 else bytes(n)
            data = bytes((i % 256 for i in range(n)))
            seg = n // 4
            s1, s2, s3, s4 = fourstream.split(data)
            self.assertEqual(len(s1), seg)
            self.assertEqual(len(s2), seg)
            self.assertEqual(len(s3), seg)
            self.assertEqual(len(s4), n - 3 * seg)
            self.assertEqual(s1 + s2 + s3 + s4, data)


class JoinTests(unittest.TestCase):
    def test_join_concatenates_in_order(self):
        self.assertEqual(fourstream.join((b"ab", b"c", b"def", b"gh")), b"abcdefgh")

    def test_join_rejects_wrong_count(self):
        with self.assertRaises(ValueError):
            fourstream.join((b"a", b"b", b"c"))
        with self.assertRaises(ValueError):
            fourstream.join((b"a", b"b", b"c", b"d", b"e"))
        with self.assertRaises(ValueError):
            fourstream.join(())


class PackTests(unittest.TestCase):
    def test_pack_worked_example(self):
        block = fourstream.pack((b"ab", b"c", b"def", b"gh"))
        expected = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        self.assertEqual(block, expected)

    def test_pack_jump_table_values(self):
        block = fourstream.pack((b"xy", b"", b"z", b"tail"))
        len1, len2, len3 = struct.unpack("<HHH", block[:6])
        self.assertEqual((len1, len2, len3), (2, 0, 1))

    def test_pack_all_empty_streams(self):
        block = fourstream.pack((b"", b"", b"", b""))
        self.assertEqual(block, b"\x00\x00\x00\x00\x00\x00")

    def test_pack_rejects_oversized_stream1(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"x" * 65536, b"", b"", b""))

    def test_pack_rejects_oversized_stream3(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"", b"", b"x" * 65536, b""))

    def test_pack_allows_max_sized_stream(self):
        s1 = b"x" * 65535
        block = fourstream.pack((s1, b"", b"", b""))
        len1 = struct.unpack("<H", block[0:2])[0]
        self.assertEqual(len1, 65535)

    def test_pack_stream4_unbounded(self):
        s4 = b"y" * 70000
        block = fourstream.pack((b"", b"", b"", s4))
        self.assertEqual(block[6:], s4[::-1])

    def test_pack_rejects_wrong_count(self):
        with self.assertRaises(ValueError):
            fourstream.pack((b"a", b"b", b"c"))


class UnpackTests(unittest.TestCase):
    def test_unpack_worked_example(self):
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        streams = fourstream.unpack(block)
        self.assertEqual(streams, (b"ab", b"c", b"def", b"gh"))

    def test_unpack_hand_built_block(self):
        table = struct.pack("<HHH", 3, 0, 2)
        body = b"cba" + b"" + b"ed" + b"ZYX"
        block = table + body
        streams = fourstream.unpack(block)
        self.assertEqual(streams, (b"abc", b"", b"de", b"XYZ"))

    def test_unpack_rejects_short_block(self):
        for n in range(6):
            with self.assertRaises(ValueError):
                fourstream.unpack(b"\x00" * n)

    def test_unpack_rejects_overlong_table(self):
        table = struct.pack("<HHH", 10, 0, 0)
        block = table + b"short"
        with self.assertRaises(ValueError):
            fourstream.unpack(block)

    def test_unpack_all_empty(self):
        block = b"\x00" * 6
        self.assertEqual(fourstream.unpack(block), (b"", b"", b"", b""))

    def test_unpack_exact_length_boundary(self):
        table = struct.pack("<HHH", 1, 1, 1)
        block = table + b"abc"
        streams = fourstream.unpack(block)
        self.assertEqual(streams, (b"a", b"b", b"c", b""))


class RoundtripTests(unittest.TestCase):
    def test_roundtrip_encode_matches_pack_of_split(self):
        data = bytes(range(13))
        self.assertEqual(fourstream.encode(data), fourstream.pack(fourstream.split(data)))

    def test_roundtrip_hand_derived_decode(self):
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        self.assertEqual(fourstream.decode(block), b"abcdefgh")

    def test_roundtrip_lengths_four_to_forty(self):
        for n in range(4, 41):
            data = bytes((i % 256 for i in range(n)))
            block = fourstream.encode(data)
            self.assertEqual(fourstream.decode(block), data)

    def test_roundtrip_pack_unpack_identity(self):
        streams = (b"abc", b"", b"xy", b"tail-data")
        self.assertEqual(fourstream.unpack(fourstream.pack(streams)), streams)


if __name__ == "__main__":
    unittest.main()
