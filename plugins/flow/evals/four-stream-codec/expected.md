# four-stream-codec: seeded traps and what catches them

Module under test: `fourstream.py`. Hidden suite: `hidden/test_hidden.py`
(25 tests, standard-library `unittest`). Reference: `hidden/reference_impl.py`.
Wrong variants: `hidden/traps/*.py`. The exact test-id list per trap is in
`hidden/traps.json`; regenerate and re-verify with
`plugins/flow/bin/flow-eval-run.sh --check-cases`.

Every trap below round-trips cleanly (`decode(encode(x)) == x`), so an agent
that only tests its own encoder against its own decoder cannot see any of
them. The hidden suite uses hand-derived byte layouts as an independent
oracle.

| Trap | Plausible wrong implementation | Input that masks it | Discriminating hidden tests |
|---|---|---|---|
| `transposed_order` | Bodies written/read in order 4,3,2,1 | All four streams identical | `test_pack_known_answer_distinct_streams`, `test_pack_stream_order_with_equal_lengths`, `test_unpack_known_answer`, `test_encode_known_answer`, `test_decode_known_answer` (+5 more) |
| `no_reverse` | Bodies stored forwards | Every stream a palindrome | `test_pack_reverses_each_stream_not_whole_body`, `test_pack_known_answer_distinct_streams`, `test_unpack_foreign_block_with_long_fourth_stream` (+6 more) |
| `reverse_whole_body` | Whole body reversed instead of each stream | `s1 == s4` and `s2 == s3` | `test_pack_reverses_each_stream_not_whole_body`, `test_pack_stream_order_with_equal_lengths` (+8 more) |
| `big_endian_table` | Jump-table lengths big-endian | Lengths with symmetric bytes (0, 257, 514, ...) | `test_pack_length_258_is_little_endian`, `test_pack_length_five_is_little_endian`, `test_unpack_little_endian_table` (+9 more) |
| `ceil_split` | Segment size `(n + 3) // 4` (Zstandard's rule) | `len(data) % 4 == 0` | `test_split_remainder_goes_to_fourth_stream`, `test_split_n_plus_three_rule_is_wrong`, `test_split_preserves_order_of_asymmetric_data`, `test_encode_known_answer` |
| `no_validation` | No length checks anywhere | Well-formed inputs | `test_split_rejects_fewer_than_four_bytes`, `test_pack_rejects_first_three_over_65535`, `test_unpack_rejects_block_shorter_than_table`, `test_unpack_rejects_table_lengths_exceeding_block` |

Verification record (run at authoring time, repeatable with `--check-cases`):
the reference passes 25/25; each variant fails exactly the tests listed for
it in `hidden/traps.json` (transposed_order 10, no_reverse 9,
reverse_whole_body 10, big_endian_table 12, ceil_split 4, no_validation 4).

Degenerate inputs the heuristic flags for this case: identical streams
(`(b"aa", b"aa", b"aa", b"aa")`), palindromic streams (`b"abba"`), empty
streams, single-byte streams, and lengths that are multiples of four. They
are legitimate boundary tests but do not discriminate the traps above.
