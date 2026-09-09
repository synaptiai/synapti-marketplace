"""Hidden reference suite for the four-stream block codec.

Never shown to the agent. Expected values are hand-derived from the spec in
scaffold/ISSUE.md (byte layouts written out longhand in comments), then
checked against hidden/reference_impl.py. Each test carries a comment naming
the trap it discriminates (see hidden/traps.json and expected.md).

Run: PYTHONPATH=<project dir> python3 hidden/test_hidden.py -v
"""
import unittest

import fourstream as fs


class SplitJoin(unittest.TestCase):

    def test_split_remainder_goes_to_fourth_stream(self):
        # n=10: seg = 10 // 4 = 2 -> sizes 2,2,2,4 (trap: ceil-split gives 3,3,3,1)
        data = bytes(range(10))
        s1, s2, s3, s4 = fs.split(data)
        self.assertEqual((s1, s2, s3, s4), (b"\x00\x01", b"\x02\x03", b"\x04\x05", b"\x06\x07\x08\x09"))

    def test_split_n_plus_three_rule_is_wrong(self):
        # n=7: floor rule gives 1,1,1,4; the (n+3)//4 rule would give 2,2,2,1
        s1, s2, s3, s4 = fs.split(b"abcdefg")
        self.assertEqual((s1, s2, s3, s4), (b"a", b"b", b"c", b"defg"))


    def test_split_minimum_size_four(self):
        self.assertEqual(fs.split(b"wxyz"), (b"w", b"x", b"y", b"z"))

    def test_split_rejects_fewer_than_four_bytes(self):
        for short in (b"", b"a", b"ab", b"abc"):
            with self.assertRaises(ValueError):
                fs.split(short)

    def test_split_preserves_order_of_asymmetric_data(self):
        # trap: transposed-order would return streams in the wrong slots
        s1, s2, s3, s4 = fs.split(b"1122334444")
        self.assertEqual(s1, b"11")
        self.assertEqual(s4, b"4444")

    def test_join_concatenates_in_stream_order(self):
        self.assertEqual(fs.join((b"ab", b"c", b"def", b"gh")), b"abcdefgh")

    def test_join_rejects_wrong_stream_count(self):
        with self.assertRaises(ValueError):
            fs.join((b"a", b"b", b"c"))
        with self.assertRaises(ValueError):
            fs.join((b"a", b"b", b"c", b"d", b"e"))


class Pack(unittest.TestCase):

    def test_pack_known_answer_distinct_streams(self):
        # table: len 2,1,3 as u16 LE -> 02 00 01 00 03 00
        # bodies reversed per stream: "ab"->"ba", "c"->"c", "def"->"fed", "gh"->"hg"
        block = fs.pack((b"ab", b"c", b"def", b"gh"))
        self.assertEqual(block, b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg")

    def test_pack_reverses_each_stream_not_whole_body(self):
        # correct: "ba" "dc" "fe" "hg"; reverse-whole-body would give "hg" "fe" "dc" "ba"
        block = fs.pack((b"ab", b"cd", b"ef", b"gh"))
        self.assertEqual(block[6:], b"badcfehg")

    def test_pack_stream_order_with_equal_lengths(self):
        # equal lengths make the jump table identical under transposition; only
        # the body order distinguishes s1..s4 from s4..s1
        block = fs.pack((b"11", b"22", b"33", b"44"))
        self.assertEqual(block, b"\x02\x00\x02\x00\x02\x00" + b"11223344")

    def test_pack_length_258_is_little_endian(self):
        # 258 = 0x0102 -> LE bytes 02 01 (big-endian would be 01 02)
        block = fs.pack((b"x" * 258, b"", b"", b""))
        self.assertEqual(block[0:2], b"\x02\x01")
        self.assertEqual(block[2:6], b"\x00\x00\x00\x00")

    def test_pack_length_five_is_little_endian(self):
        block = fs.pack((b"", b"12345", b"", b"9"))
        self.assertEqual(block[0:6], b"\x00\x00\x05\x00\x00\x00")

    def test_pack_allows_empty_streams(self):
        self.assertEqual(fs.pack((b"", b"", b"", b"q")), b"\x00\x00\x00\x00\x00\x00q")
        self.assertEqual(fs.pack((b"", b"", b"", b"")), b"\x00\x00\x00\x00\x00\x00")

    def test_pack_rejects_first_three_over_65535(self):
        with self.assertRaises(ValueError):
            fs.pack((b"x" * 65536, b"", b"", b""))
        with self.assertRaises(ValueError):
            fs.pack((b"", b"", b"x" * 65536, b""))

    def test_pack_fourth_stream_may_exceed_65535(self):
        block = fs.pack((b"a", b"b", b"c", b"z" * 70000))
        self.assertEqual(len(block), 6 + 3 + 70000)
        self.assertEqual(block[0:6], b"\x01\x00\x01\x00\x01\x00")



class Unpack(unittest.TestCase):

    def test_unpack_known_answer(self):
        block = b"\x02\x00\x01\x00\x03\x00" + b"ba" + b"c" + b"fed" + b"hg"
        self.assertEqual(fs.unpack(block), (b"ab", b"c", b"def", b"gh"))

    def test_unpack_foreign_block_with_long_fourth_stream(self):
        # lengths 1,1,1 then bodies "A" "B" "C" and fourth "gnirts" (reversed "string")
        block = b"\x01\x00\x01\x00\x01\x00" + b"ABC" + b"gnirts"
        self.assertEqual(fs.unpack(block), (b"A", b"B", b"C", b"string"))

    def test_unpack_fourth_stream_may_be_empty(self):
        block = b"\x01\x00\x02\x00\x01\x00" + b"a" + b"cb" + b"d"
        self.assertEqual(fs.unpack(block), (b"a", b"bc", b"d", b""))

    def test_unpack_little_endian_table(self):
        # 0x0102 = 258 bytes in stream 1; a big-endian reader sees 0x0201 = 513 and overruns
        block = b"\x02\x01\x00\x00\x00\x00" + bytes(range(256)) + b"\x00\x01" + b"tail"
        s1, s2, s3, s4 = fs.unpack(block)
        self.assertEqual(len(s1), 258)
        self.assertEqual(s1[0:2], b"\x01\x00")
        self.assertEqual(s4, b"liat")

    def test_unpack_rejects_block_shorter_than_table(self):
        for short in (b"", b"\x00", b"\x00\x00\x00\x00\x00"):
            with self.assertRaises(ValueError):
                fs.unpack(short)

    def test_unpack_rejects_table_lengths_exceeding_block(self):
        with self.assertRaises(ValueError):
            fs.unpack(b"\x05\x00\x00\x00\x00\x00" + b"abcd")
        with self.assertRaises(ValueError):
            fs.unpack(b"\x01\x00\x01\x00\x03\x00" + b"abcd")

    def test_unpack_accepts_table_lengths_exactly_filling_block(self):
        block = b"\x02\x00\x02\x00\x02\x00" + b"abcdef"
        self.assertEqual(fs.unpack(block), (b"ba", b"dc", b"fe", b""))


class RoundTrip(unittest.TestCase):

    def test_encode_known_answer(self):
        # "abcdefghij" -> split 2,2,2,4: ab cd ef ghij -> bodies ba dc fe jihg
        self.assertEqual(fs.encode(b"abcdefghij"), b"\x02\x00\x02\x00\x02\x00" + b"badcfejihg")

    def test_decode_known_answer(self):
        self.assertEqual(fs.decode(b"\x02\x00\x02\x00\x02\x00" + b"badcfejihg"), b"abcdefghij")

    def test_roundtrip_asymmetric_data_all_sizes(self):
        for n in range(4, 41):
            data = bytes((i * 37 + 11) % 256 for i in range(n))
            self.assertEqual(fs.decode(fs.encode(data)), data, "n=%d" % n)



if __name__ == "__main__":
    unittest.main(verbosity=2)
