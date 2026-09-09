# Issue #1: Implement a largest-remainder money allocator (`allocate.py`)

## Description

Billing needs to split a monetary amount across several parties in
proportion to integer or decimal weights so that the parts add up to the
amount exactly, to the cent (or to whatever number of decimal places the
currency uses). Independent rounding of each share does not do this
(`100.00` split three ways as `33.33 x 3` loses a cent), so the function
must use the **largest-remainder method** described below. Results are
compared byte-for-byte against the ledger, so the exact distribution of the
leftover units, and the order of the result, are part of the contract.

`allocate.py` in this directory contains the function with a docstring and a
`raise NotImplementedError` body. That skeleton is the starting point of this
task, not a placeholder to keep: replace it with a working implementation.
Standard library only, Python 3 (`decimal` and `fractions` are available).

## Algorithm

`allocate(amount, weights, places=2) -> list[Decimal]`

1. Let `unit = 10 ** -places` and `total_units = amount / unit` (an integer:
   `amount` must not carry more than `places` fractional digits).
2. For each weight `w_i` compute the exact share in units,
   `exact_i = total_units * w_i / sum(weights)`, and take `floor(exact_i)`.
   Multiply before dividing; do all arithmetic exactly (`Decimal` or
   `Fraction`), never in binary floating point.
3. `leftover = total_units - sum(floors)` units remain (always fewer than
   `len(weights)`). Hand out one unit each to the `leftover` entries with the
   **largest fractional remainder** `exact_i - floor(exact_i)`. Ties are
   broken by **lowest index first**. No entry receives more than one extra
   unit.
4. Return the shares as `Decimal` values quantized to `places` decimal
   places, **in the same order as `weights`**. Their sum equals `amount`.

Worked example: `allocate("1.00", [1, 2, 3])`: exact shares in cents are
`16.66.., 33.33.., 50`; floors `16, 33, 50` (99); one leftover cent goes to
index 0 (remainder `.66`), result `[0.17, 0.33, 0.50]`.

## Input contract

- `amount`: `int`, `str` or `Decimal`, `>= 0`, at most `places` fractional
  digits. A `float` raises `TypeError`; a negative value or excess precision
  raises `ValueError`.
- `weights`: non-empty sequence of `int`, `str` or `Decimal`, each `> 0`.
  Empty, zero or negative raises `ValueError`; a `float` raises `TypeError`.
- `places`: `int >= 0` (0 means whole units). Else `ValueError`.

## Non-goals

- No currency objects, no rounding modes other than the method above.
- No support for negative amounts (refunds are allocated as positive amounts by the caller).

## Acceptance Criteria

Write your tests in `tests/test_allocate.py` (standard-library `unittest`).
Each criterion names a `-k` keyword; the tests that verify it must contain
that keyword in their name so the command selects them.

- [ ] Hand-derived allocations match, including the worked example and cases where remainders tie — verify: `python3 -m unittest tests.test_allocate -k known`
- [ ] The parts always sum to the amount and come back in `weights` order — verify: `python3 -m unittest tests.test_allocate -k invariant`
- [ ] `places` other than 2 (0 and 3) are honoured — verify: `python3 -m unittest tests.test_allocate -k places`
- [ ] Bad inputs (zero/negative/empty weights, negative amount, excess precision, float amount) are rejected with the documented exception types — verify: `python3 -m unittest tests.test_allocate -k reject`
- [ ] The whole suite passes — verify: `python3 -m unittest discover -s tests -t . -v`
