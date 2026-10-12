# Asking about several items at once: the comparison

- goal set: 178 items in 13 groups, site `goal.judge`, model jev-1.13.0, timeout 3000 ms, 2026-10-12T07:35:24Z to 2026-10-12T07:47:38Z, commit e711abf6.
- review set: 134 items in 78 groups, site `review.confidence`, model jev-1.13.0, timeout 3000 ms, 2026-10-12T07:47:38Z to 2026-10-12T08:01:18Z, commit e711abf6.

## Goal set

| Measure | A1 | A2 | S (items in state) | Q (items in questions) |
|---|---|---|---|---|
| Requests (fewer is cheaper) | 178 | 178 | 26 | 26 |
| Items answered | 178 | 178 | 178 | 178 |
| Crossings of 0.5 against A1 (fewer is closer) |  | 3 | 8 | 6 |
| Crossings of 0.75 against A1 (fewer is closer) |  | 0 | 11 | 11 |
| Crossings of 0.8 against A1 (fewer is closer) |  | 1 | 15 | 10 |
| Answered in A1, not here (fewer is better) |  | 0 | 0 | 0 |
| Median difference in p from A1 (smaller is closer) |  | 0.010 | 0.040 | 0.020 |
| Agree with the label at 0.5 (more is better) | 152 | 155 | 154 | 154 |
| Client calls | 178 | 178 | 13 | 13 |
| Requests per client call | 1.00 | 1.00 | 2.00 | 2.00 |
| Time per call, median ms | 1694.5 | 1686.0 | 1958 | 1911 |
| Time per call, 95th percentile ms | 1865 | 1855 | 2229 | 2068 |
| Time for the whole send, ms | 306401 | 305633 | 25677 | 24864 |
| Timeouts | 0 | 0 | 0 | 0 |

Times are wall time per client call, measured by run.sh around each call, so they include starting bash and Python and reading the settings, not only the request. A1 and A2 make one request per call; S and Q make the number of requests per call shown above. Lower is faster.

S, crossings of 0.5 by position in the request: position 0: 1 of 26, position 1: 0 of 23, position 2: 0 of 18, position 3: 3 of 18, position 4: 1 of 17, position 5: 1 of 17, position 6: 0 of 16, position 7: 0 of 15, position 8: 1 of 15, position 9: 1 of 13.
Q, crossings of 0.5 by position in the request: position 0: 2 of 26, position 1: 0 of 23, position 2: 1 of 18, position 3: 2 of 18, position 4: 0 of 17, position 5: 1 of 17, position 6: 0 of 16, position 7: 0 of 15, position 8: 0 of 15, position 9: 0 of 13.

## Review set

| Measure | A1 | A2 | S (items in state) | Q (items in questions) |
|---|---|---|---|---|
| Requests (fewer is cheaper) | 134 | 134 | 78 | 78 |
| Items answered | 134 | 134 | 134 | 134 |
| Crossings of 0.5 against A1 (fewer is closer) |  | 0 | 4 | 5 |
| Crossings of 0.05 against A1 (fewer is closer) |  | 0 | 0 | 0 |
| Answered in A1, not here (fewer is better) |  | 0 | 0 | 0 |
| Median difference in p from A1 (smaller is closer) |  | 0.010 | 0.030 | 0.030 |
| Client calls | 134 | 134 | 78 | 78 |
| Requests per client call | 1.00 | 1.00 | 1.00 | 1.00 |
| Time per call, median ms | 1691.0 | 1691.0 | 1782.0 | 1797.5 |
| Time per call, 95th percentile ms | 1881 | 1850 | 1918 | 1937 |
| Time for the whole send, ms | 229868 | 229630 | 140507 | 141517 |
| Timeouts | 0 | 0 | 0 | 0 |

Times are wall time per client call, measured by run.sh around each call, so they include starting bash and Python and reading the settings, not only the request. A1 and A2 make one request per call; S and Q make the number of requests per call shown above. Lower is faster.

S, crossings of 0.5 by position in the request: position 0: 2 of 78, position 1: 1 of 37, position 2: 1 of 14, position 3: 0 of 4, position 4: 0 of 1.
Q, crossings of 0.5 by position in the request: position 0: 4 of 78, position 1: 1 of 37, position 2: 0 of 14, position 3: 0 of 4, position 4: 0 of 1.

## Bars

| Layout | 1 | 2 | 3 | 4 | 5 | Passes |
|---|---|---|---|---|---|---|
| items-in-state | not met | met | not met | met | not met | no |
| items-in-questions | not met | met | not met | met | met | no |

Default chosen by the pre-registered rule: `off`.
