# Issue #1: Implement an interval algebra with open/closed endpoints (`intervals.py`)

## Description

The scheduling service stores availability as sets of intervals whose two
ends are **independently** open or closed, because a booking that ends at
10:00 and one that starts at 10:00 must not count as overlapping while two
maintenance windows `[8, 10]` and `[10, 12]` must merge. The service needs
set union, intersection and difference over such interval lists, and every
result must come back in one canonical form so that two equal sets compare
equal with `==`.

`intervals.py` in this directory contains the four functions with docstrings
and `raise NotImplementedError` bodies. That skeleton is the starting point
of this task, not a placeholder to keep: replace every body with a working
implementation. Standard library only, Python 3 (`fractions` and `decimal`
are available and their values must survive unchanged; do not convert
bounds to `float`).

## Representation

An interval is a tuple `(lo, hi, lo_closed, hi_closed)`:

- `lo`, `hi`: numbers (`int`, `Fraction`, `Decimal`; `float` is accepted)
  or `None`. `None` means unbounded (`lo = None` is −∞, `hi = None` is +∞).
- `lo_closed`, `hi_closed`: `bool`. `True` means the end point belongs to
  the interval. An unbounded end must be open: `None` with `True` raises
  `ValueError`.
- **Shorthand:** a 2-tuple `(lo, hi)` means the closed interval
  `(lo, hi, True, True)`. Anything that is not a 2- or 4-tuple, a non-`bool`
  flag, or a non-number bound raises `ValueError`.

Every function returns a **list of 4-tuples** in canonical form (below) and
accepts inputs that are not canonical (unsorted, overlapping, empty
intervals, shorthand).

## Rules

1. **Empty intervals.** `lo > hi` is empty. `lo == hi` is empty unless both
   ends are closed, in which case it is the single point `[lo, lo]`. Empty
   intervals are dropped; they are valid input, not an error.
2. **Merging.** Two intervals are merged when they overlap (`hi1 > lo2`) or
   **touch** with at least one closed end at the meeting point: `[1, 3]` +
   `[3, 5]`, `[1, 3)` + `[3, 5]` and `[1, 3]` + `(3, 5]` all become `[1, 5]`,
   but `[1, 3)` + `(3, 5]` stay two intervals because `3` belongs to neither.
   A point `[3, 3]` between `[1, 3)` and `(3, 5]` closes the gap: the three
   merge into `[1, 5]`. A merged interval's lower end is closed if any merged
   interval starting there was closed, and likewise for the upper end.
3. **Canonical form.** No empty intervals, no two intervals that overlap or
   touch-and-merge, sorted by lower bound (`None` first). Flags are `bool`
   (`True`/`False`, not `1`/`0`); bounds keep their input type and value.
4. **`normalize(intervals)`** returns the canonical form of the input.
5. **`union(a, b)`** is the canonical form of all intervals of `a` and `b`.
6. **`intersection(a, b)`** contains exactly the points in both `a` and `b`.
   At an equal endpoint the result is closed only if **both** inputs are
   closed there: `[1, 5]` ∩ `(1, 5)` is `(1, 5)`, `[1, 5)` ∩ `(1, 5]` is
   `(1, 5)`. `[1, 3]` ∩ `[3, 5]` is the point `[3, 3]`; `[1, 3)` ∩ `[3, 5]`
   is empty. Inputs are normalized first, so `[1, 5]` ∩ (`[1, 2]` + `[2, 5]`)
   is `[1, 5]`, one interval.
7. **`difference(a, b)`** contains exactly the points in `a` that are not
   in `b`. Removing an interval opens the cut: `[1, 5]` − `[2, 3]` is
   `[1, 2)` + `(3, 5]`, `[1, 5]` − `(2, 3)` is `[1, 2]` + `[3, 5]`, and
   `[1, 5]` − (`[1, 3)` + `(3, 5]`) is the point `[3, 3]`. Subtracting an
   empty list returns `normalize(a)`.
8. **Unbounded ends** take part in every operation: `(None, 3]` ∪ `(2, None)`
   is `(None, None)`; `(None, None)` − `[0, 1]` is `(None, 0)` + `(1, None)`.

Worked example: `normalize([(5, 6), (1, 3, True, False), (3, 3, True,
True), (3, 4, False, True), (4, 4, False, False)])` → `[(1, 4, True, True),
(5, 6, True, True)]`.

## Non-goals

- No symmetric difference, no membership query, no string parsing.
- No multi-dimensional intervals.

## Acceptance Criteria

Write your tests in `tests/test_intervals.py` (standard-library `unittest`).
Each criterion names a `-k` keyword; the tests that verify it must contain
that keyword in their name so the command selects them.

- [ ] `normalize` drops empty intervals, keeps closed points, sorts by lower bound and handles the shorthand and the worked example — verify: `python3 -m unittest tests.test_intervals -k canonical`
- [ ] Touching intervals merge exactly when a closed end meets the point, including the point-fills-the-gap case — verify: `python3 -m unittest tests.test_intervals -k touching`
- [ ] `intersection` applies the both-closed rule at equal endpoints, yields points for closed touching ends, and normalizes its inputs — verify: `python3 -m unittest tests.test_intervals -k intersect`
- [ ] `difference` opens the cut ends, handles points and unbounded subtrahends — verify: `python3 -m unittest tests.test_intervals -k difference`
- [ ] Unbounded ends work in every operation and malformed intervals raise `ValueError` — verify: `python3 -m unittest tests.test_intervals -k bounds`
- [ ] The whole suite passes — verify: `python3 -m unittest discover -s tests -t . -v`
