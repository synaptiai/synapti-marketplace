# Issue #1: Implement a sliding-window rate limiter (`ratelimit.py`)

## Description

Our API gateway needs a per-key sliding-window rate limiter that callers
drive with explicit timestamps (no wall-clock reads inside the class, so it
is deterministic and testable). The class must answer three questions for a
key at a given time: may this request proceed, how many more may proceed
right now, and if not, how long until one may.

`ratelimit.py` in this directory contains the class with docstrings and
`raise NotImplementedError` bodies. That skeleton is the starting point of
this task, not a placeholder to keep: replace every body with a working
implementation. Standard library only, Python 3.

## Semantics

- `SlidingWindowLimiter(limit, window)`: at most `limit` accepted requests
  per key within any `window` seconds. `limit` is an `int >= 0`; `window`
  is a number `> 0`. Anything else raises `ValueError`.
- The window is **half-open on the left**: at time `now`, an accepted
  request at time `t` counts if and only if `now - window < t <= now`.
  Equivalently a request accepted at `t` stops counting exactly when
  `now >= t + window`. So with `window = 10`, a request accepted at `0`
  no longer counts at `now = 10`, but still counts at `now = 9.999`.
- It is a *sliding* window over the actual timestamps of accepted requests,
  not fixed buckets aligned to multiples of `window`.
- **Only accepted requests are recorded.** A denied request leaves no trace
  and never counts against the key.
- Keys are fully independent.
- `allow(key, now) -> bool`: accept (and record) the request if fewer than
  `limit` accepted requests are in the window for `key`; otherwise deny.
  With `limit = 0` every request is denied.
- `remaining(key, now) -> int`: `limit` minus the number of accepted
  requests in the window (never negative). For an unseen key it is `limit`.
- `retry_after(key, now) -> float`: `0.0` if a request at `now` would be
  accepted; otherwise the seconds until the **oldest** in-window accepted
  request expires, i.e. `oldest + window - now`. With `limit = 0` return
  `float("inf")`.
- Time is monotonic: `now` passed to any method must be `>=` the largest
  `now` the limiter has seen so far (across all keys and methods). A smaller
  value raises `ValueError`. Equal values are fine.

## Non-goals

- No thread safety, no persistence, no background eviction.
- No wall-clock access: `now` is always supplied by the caller.

## Acceptance Criteria

Write your tests in `tests/test_ratelimit.py` (standard-library
`unittest`). Each criterion names a `-k` keyword; the tests that verify it
must contain that keyword in their name so the command selects them.

- [ ] Exactly `limit` requests are accepted per key per window, keys are independent, and `limit = 0` denies everything — verify: `python3 -m unittest tests.test_ratelimit -k limit`
- [ ] Boundary semantics: a request accepted at `t` stops counting at exactly `t + window` and still counts just before it; the window slides rather than resetting on fixed buckets — verify: `python3 -m unittest tests.test_ratelimit -k boundary`
- [ ] Denied requests are not recorded and do not affect later decisions — verify: `python3 -m unittest tests.test_ratelimit -k denied`
- [ ] `remaining` and `retry_after` agree with `allow`, and `retry_after` is measured from the oldest in-window request — verify: `python3 -m unittest tests.test_ratelimit -k retry`
- [ ] Constructor arguments and non-monotonic time are rejected with `ValueError` — verify: `python3 -m unittest tests.test_ratelimit -k reject`
- [ ] The whole suite passes — verify: `python3 -m unittest discover -s tests -t . -v`
