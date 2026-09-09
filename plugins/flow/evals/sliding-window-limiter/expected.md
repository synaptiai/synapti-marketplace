# sliding-window-limiter: seeded traps and what catches them

Module under test: `ratelimit.py`. Hidden suite: `hidden/test_hidden.py`
(23 tests, standard-library `unittest`). Reference: `hidden/reference_impl.py`.
Wrong variants: `hidden/traps/*.py`. The exact test-id list per trap is in
`hidden/traps.json`; regenerate and re-verify with
`plugins/flow/bin/flow-eval-run.sh --check-cases`.

Every trap passes the "send `limit` requests, see them accepted" happy path
that agents write first. The hidden suite probes the exact window edge,
denied-request bursts, interleaved keys and multi-entry windows.

| Trap | Plausible wrong implementation | Input that masks it | Discriminating hidden tests |
|---|---|---|---|
| `inclusive_boundary` | Window `[now - window, now]` (uses `<`/`>=` at the edge) | Timestamps never landing exactly on `t + window` | `test_request_at_exactly_window_edge_has_expired`, `test_capacity_frees_one_entry_at_a_time`, `test_fractional_window` (+4 more) |
| `fixed_window` | Buckets aligned to multiples of `window` | All requests inside one bucket, or spaced by whole windows | `test_sliding_window_not_fixed_buckets`, `test_capacity_frees_one_entry_at_a_time`, `test_remaining_counts_down_and_recovers` (+2 more) |
| `counts_denied` | Denied requests recorded too | Never sending more than `limit` requests | `test_denied_requests_are_not_recorded`, `test_remaining_ignores_denied_requests` (+4 more) |
| `shared_counter` | One counter for all keys | Every test uses a single key | `test_keys_are_independent`, `test_interleaved_keys_count_separately` |
| `limit_off_by_one` | `<= limit` accepts `limit + 1` | Sending exactly `limit` requests | `test_allows_exactly_limit_then_denies`, `test_limit_zero_denies_everything` (+13 more) |
| `retry_from_newest` | `retry_after` measured from the newest request | A single request in the window | `test_retry_after_measures_from_oldest_in_window`, `test_retry_after_agrees_with_allow` |
| `no_monotonic_check` | Time going backwards accepted silently | Increasing timestamps | `test_time_going_backwards_raises`, `test_time_going_backwards_across_keys_raises` |

Verification record (run at authoring time, repeatable with `--check-cases`):
the reference passes 23/23; each variant fails exactly the tests listed for
it in `hidden/traps.json` (inclusive_boundary 7, fixed_window 5,
counts_denied 6, shared_counter 2, limit_off_by_one 15, retry_from_newest 2,
no_monotonic_check 2).

Degenerate inputs the heuristic flags for this case: timestamp lists with a
single element or all-identical values, and the empty request sequence. A
single request in the window masks `retry_from_newest`; a single key masks
`shared_counter`; timestamps that never touch `t + window` mask
`inclusive_boundary`.
