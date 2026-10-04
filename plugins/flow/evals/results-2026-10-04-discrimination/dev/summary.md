# System One test-discrimination measurement

Question: if the module did what the risk row's plausible wrong version describes, would this test fail? p is the provider's probability of yes. A pair is flagged when the provider is confident the test would still pass: confidence |2p - 1| at least t and p below 0.5.

Set: dev. Pairs scored: 1549 (0 unobserved pairs left out). Provider: typesafe jev-1.13.0.

## Measurement checks

Each check says what the result would look like if the harness, not the model, produced it. They are read before any metric.

| Check | Result |
|---|---|
| Records match pairs (name-stripped) | yes: 1549 pairs, 1549 answered, no answer 0, 0 retried |
| Records match pairs (real) | yes: 1549 pairs, 1549 answered, no answer 0, 0 retried |
| Records match pairs (repeat) | yes: 30 pairs, 30 answered, no answer 0, 0 retried |
| Records match pairs (shuffled) | yes: 1549 pairs, 1549 answered, no answer 0, 0 retried |
| Coverage at least 95% | yes (agent 100.0%, author 100.0%) |
| Answers spread out (fail and pass answers not both over 80% in one bin; both classes predicted) | yes (agent largest bin 25.3%, author largest bin 16.5%) |
| Shuffled-wrong-version placebo: within each case and trap, the real-description AUC exceeds the placebo AUC by at least 0.15 (larger is better; a gap of 0 means the description adds nothing to the test alone) | yes (real-description AUC 0.898, placebo AUC 0.560, gap 0.338, over 42 case and trap groups; reported, not judged: 8 groups with a gap under 0.15, smallest gap 0.034 (author/interval-algebra/sort_by_lower_only); placebo AUC reported, not judged: pooled 0.574, standard error with no signal 0.018; agent AUC 0.552, standard error 0.030, author AUC 0.583, standard error 0.023) |
| Real-description AUC, mean within case and trap, not more than 2 standard errors below 0.5 (below means the question is read the wrong way round) | yes (AUC 0.898, standard error with no signal 0.028, over 42 case and trap groups holding 1549 pairs; pooled over all pairs, reported and not judged: AUC 0.852, standard error 0.018) |
| Label-permutation AUC, mean within case and trap, within 0.02 of 0.5 | yes (agent 0.504, author 0.499; pooled agent 0.544, author 0.539) |
| Test name removed, agent pairs (reported, not judged; a drop well above its standard error means the answers lean on the name, not the code) | AUC 0.832 with the name, 0.833 without; drop -0.001, standard error 0.009, over 648 pairs answered both ways |
| Same state sent twice: how far apart the two answers are (smaller is better; reported, not judged) | 30 pairs; the two answers differ by 0.080 at most and 0.031 on average; 20 differ by more than 0.02 |
| States over a provider's cap | 0 over imajev's 7,000 tokens, 0 over TypeSafe's 28,000 (largest 6325 bytes) |
| Threshold fixed on the dev set before the evaluation records | t = 0.60, chosen 2026-10-04T22:23:09Z at commit 77c5601d1d93a6f4726ce28c5241c1c1daf0c3c4 |

## Adoption bar

Verdict: **dev-only-provisional**. A result on the dev set cannot adopt the site.

On agent-written pairs at t = 0.60:

1. Tests that do fail against the wrong version, flagged as if they would pass: 0 of 116 (Wilson 95% upper bound 3.2%; must be at most 5%; lower is better): holds.
2. Hard negatives (tests that pass against this wrong version but fail another) flagged: 153 of 452 (Wilson 95% lower bound 29.6%; must be at least 30%; higher is better): does not hold.

## Results per stratum

Accuracy and balanced accuracy read p at 0.5. AUC: 0.5 is chance, 1.0 is perfect ordering of fail above pass. Brier: lower is better. Brier skill: above 0 beats always answering the base rate.

| Stratum | Ablation | Pairs | Coverage | Fail / pass (hard negatives) | Accuracy (constant) | Balanced accuracy | AUC | Brier (constant) | Brier skill |
|---|---|---|---|---|---|---|---|---|---|
| agent | name-stripped | 648 | 100.0% | 116 / 532 (452) | 78.1% (82.1%) | 71.1% | 0.833 | 0.155 (0.147) | -0.058 |
| agent | real | 648 | 100.0% | 116 / 532 (452) | 77.5% (82.1%) | 73.8% | 0.832 | 0.161 (0.147) | -0.095 |
| agent | shuffled | 648 | 100.0% | 116 / 532 (452) | 75.3% (82.1%) | 53.3% | 0.552 | 0.178 (0.147) | -0.213 |
| author | name-stripped | 901 | 100.0% | 200 / 701 (606) | 70.5% (77.8%) | 75.5% | 0.855 | 0.188 (0.173) | -0.087 |
| author | real | 901 | 100.0% | 200 / 701 (606) | 70.1% (77.8%) | 76.7% | 0.877 | 0.188 (0.173) | -0.090 |
| author | shuffled | 901 | 100.0% | 200 / 701 (606) | 71.8% (77.8%) | 52.2% | 0.583 | 0.193 (0.173) | -0.116 |

## Per case (real descriptions)

| Stratum | Case | Pairs | Coverage | Fail pairs | AUC | Note |
|---|---|---|---|---|---|---|
| agent | money-allocator | 648 | 100.0% | 116 | 0.832 |  |
| author | four-stream-codec | 150 | 100.0% | 49 | 0.927 |  |
| author | interval-algebra | 390 | 100.0% | 69 | 0.855 |  |
| author | money-allocator | 200 | 100.0% | 43 | 0.843 |  |
| author | sliding-window-limiter | 161 | 100.0% | 39 | 0.888 |  |

## Threshold sweep, agent pairs

| t | Fail pairs flagged (lower is better) | Wilson upper | Hard negatives flagged (higher is better) | Wilson lower | All pass pairs flagged (reported) | Wilson lower, upper |
|---|---|---|---|---|---|---|
| 0.50 | 9 of 116 | 14.1% | 209 of 452 | 41.7% | 252 of 532 | 43.2%, 51.6% |
| 0.55 | 3 of 116 | 7.3% | 177 of 452 | 34.8% | 213 of 532 | 36.0%, 44.3% |
| 0.60 | 0 of 116 | 3.2% | 153 of 452 | 29.6% | 185 of 532 | 30.8%, 38.9% |
| 0.65 | 0 of 116 | 3.2% | 105 of 452 | 19.6% | 125 of 532 | 20.1%, 27.3% |
| 0.70 | 0 of 116 | 3.2% | 74 of 452 | 13.2% | 86 of 532 | 13.3%, 19.5% |
| 0.75 | 0 of 116 | 3.2% | 7 of 452 | 0.8% | 17 of 532 | 2.0%, 5.1% |
| 0.80 | 0 of 116 | 3.2% | 0 of 452 | 0.0% | 5 of 532 | 0.4%, 2.2% |
| 0.85 | 0 of 116 | 3.2% | 0 of 452 | 0.0% | 0 of 532 | 0.0%, 0.7% |
| 0.90 | 0 of 116 | 3.2% | 0 of 452 | 0.0% | 0 of 532 | 0.0%, 0.7% |
| 0.95 | 0 of 116 | 3.2% | 0 of 452 | 0.0% | 0 of 532 | 0.0%, 0.7% |

Reliability, agent pairs (a calibrated provider has fail rate close to mean p in each bin):

| p bin | Pairs | Mean p | Fail rate |
|---|---|---|---|
| 0.0-0.1 | 0 | n/a | n/a |
| 0.1-0.2 | 164 | 0.154 | 0.000 |
| 0.2-0.3 | 160 | 0.243 | 0.075 |
| 0.3-0.4 | 93 | 0.341 | 0.150 |
| 0.4-0.5 | 43 | 0.439 | 0.256 |
| 0.5-0.6 | 35 | 0.546 | 0.286 |
| 0.6-0.7 | 49 | 0.645 | 0.367 |
| 0.7-0.8 | 50 | 0.737 | 0.300 |
| 0.8-0.9 | 28 | 0.846 | 0.679 |
| 0.9-1.0 | 26 | 0.939 | 0.654 |

## Threshold sweep, author pairs

| t | Fail pairs flagged (lower is better) | Wilson upper | Hard negatives flagged (higher is better) | Wilson lower | All pass pairs flagged (reported) | Wilson lower, upper |
|---|---|---|---|---|---|---|
| 0.50 | 3 of 200 | 4.3% | 122 of 606 | 17.1% | 173 of 701 | 21.6%, 28.0% |
| 0.55 | 3 of 200 | 4.3% | 82 of 606 | 11.0% | 127 of 701 | 15.4%, 21.1% |
| 0.60 | 1 of 200 | 2.8% | 59 of 606 | 7.6% | 101 of 701 | 12.0%, 17.2% |
| 0.65 | 1 of 200 | 2.8% | 29 of 606 | 3.4% | 54 of 701 | 6.0%, 9.9% |
| 0.70 | 0 of 200 | 1.9% | 19 of 606 | 2.0% | 34 of 701 | 3.5%, 6.7% |
| 0.75 | 0 of 200 | 1.9% | 2 of 606 | 0.1% | 8 of 701 | 0.6%, 2.2% |
| 0.80 | 0 of 200 | 1.9% | 0 of 606 | 0.0% | 2 of 701 | 0.1%, 1.0% |
| 0.85 | 0 of 200 | 1.9% | 0 of 606 | 0.0% | 0 of 701 | 0.0%, 0.5% |
| 0.90 | 0 of 200 | 1.9% | 0 of 606 | 0.0% | 0 of 701 | 0.0%, 0.5% |
| 0.95 | 0 of 200 | 1.9% | 0 of 606 | 0.0% | 0 of 701 | 0.0%, 0.5% |

Reliability, author pairs (a calibrated provider has fail rate close to mean p in each bin):

| p bin | Pairs | Mean p | Fail rate |
|---|---|---|---|
| 0.0-0.1 | 0 | n/a | n/a |
| 0.1-0.2 | 84 | 0.160 | 0.012 |
| 0.2-0.3 | 149 | 0.244 | 0.027 |
| 0.3-0.4 | 140 | 0.338 | 0.050 |
| 0.4-0.5 | 105 | 0.444 | 0.105 |
| 0.5-0.6 | 105 | 0.540 | 0.124 |
| 0.6-0.7 | 108 | 0.646 | 0.278 |
| 0.7-0.8 | 97 | 0.743 | 0.412 |
| 0.8-0.9 | 72 | 0.845 | 0.819 |
| 0.9-1.0 | 41 | 0.927 | 0.854 |

## Appendix: five states

Each state below is what the provider received for that pair. It should show the test and the risk row's wrong version, and no hidden test name other than the test's own.

### eval:author/sliding-window-limiter/hidden/retry_from_newest/65cc221c1c7e

sha256 d625ac19a79cc7105d6591555df67e59c797c94ce579d0a6a3350befb96375b3, record matches: yes

```json
{
  "risk": {
    "area": "retry from newest",
    "plausible_wrong_version": "`retry_after` measured from the newest request"
  },
  "test": {
    "id": "RetryAfter.test_retry_after_measures_from_oldest_in_window",
    "source": "import unittest\nfrom ratelimit import SlidingWindowLimiter\n\n\nclass RetryAfter(unittest.TestCase):\n    def test_retry_after_measures_from_oldest_in_window(self):\n        lim = SlidingWindowLimiter(limit=3, window=10)\n        for t in (1, 2, 3):\n            self.assertTrue(lim.allow(\"k\", t))\n        self.assertAlmostEqual(lim.retry_after(\"k\", 5), 6.0)\n"
  }
}
```

### eval:author/sliding-window-limiter/hidden/no_monotonic_check/009a892c6dd9

sha256 01a260b65872ea6b1442689d0131f797b7472e58fe57f89e7bae17f9e52104b5, record matches: yes

```json
{
  "risk": {
    "area": "no monotonic check",
    "plausible_wrong_version": "Time going backwards accepted silently"
  },
  "test": {
    "id": "Validation.test_time_going_backwards_raises",
    "source": "import unittest\nfrom ratelimit import SlidingWindowLimiter\n\n\nclass Validation(unittest.TestCase):\n    def test_time_going_backwards_raises(self):\n        lim = SlidingWindowLimiter(limit=5, window=10)\n        lim.allow(\"k\", 5)\n        with self.assertRaises(ValueError):\n            lim.allow(\"k\", 4)\n"
  }
}
```

### eval:author/interval-algebra/hidden/unsorted_output/780dd138cca2

sha256 835ec40fdfbacf1f5b002bf8ef60e644a76808669c9e9509baf499e51ae82dd5, record matches: yes

```json
{
  "risk": {
    "area": "unsorted output",
    "plausible_wrong_version": "No sort; only input-order neighbours merge"
  },
  "test": {
    "id": "Canonical.test_canonical_drops_reversed_bounds",
    "source": "import unittest\nimport intervals as iv\n\n\nT, F = True, False\n\n\nclass Canonical(unittest.TestCase):\n    def test_canonical_drops_reversed_bounds(self):\n        self.assertEqual(iv.normalize([(5, 1)]), [])\n        self.assertEqual(iv.normalize([(5, 1, F, F), (2, 3)]), [(2, 3, T, T)])\n"
  }
}
```

### eval:author/four-stream-codec/hidden/no_reverse/a0b66af28b91

sha256 77030dbec1c92bb148fe0e07a352c04b42eeb97adc8e7eaff0b63f75b1b18aca, record matches: yes

```json
{
  "risk": {
    "area": "no reverse",
    "plausible_wrong_version": "Bodies stored forwards"
  },
  "test": {
    "id": "Pack.test_pack_stream_order_with_equal_lengths",
    "source": "import unittest\nimport fourstream as fs\n\n\nclass Pack(unittest.TestCase):\n    def test_pack_stream_order_with_equal_lengths(self):\n        block = fs.pack((b\"11\", b\"22\", b\"33\", b\"44\"))\n        self.assertEqual(block, b\"\\x02\\x00\\x02\\x00\\x02\\x00\" + b\"11223344\")\n"
  }
}
```

### eval:author/money-allocator/hidden/accepts_nonpositive_weights/09796db3e6d4

sha256 37b8dc4a17d12948d04449738d6577ccc078c530e07c89b9e2501c5a411d2aea, record matches: yes

```json
{
  "risk": {
    "area": "accepts nonpositive weights",
    "plausible_wrong_version": "No input validation"
  },
  "test": {
    "id": "Invariants.test_sum_equals_amount_for_many_shapes",
    "source": "import unittest\nfrom decimal import Decimal\nfrom allocate import allocate\n\n\nclass Invariants(unittest.TestCase):\n    def test_sum_equals_amount_for_many_shapes(self):\n        cases = [\n            (\"1.00\", [1, 1, 1]), (\"0.07\", [5, 3, 9, 1]), (\"99.99\", [7, 11, 13]),\n            (\"0.10\", [1, 3]), (\"3.33\", [2, 2, 2, 2, 2, 2, 2]), (\"1000.01\", [1, 999]),\n        ]\n        for amount, weights in cases:\n            result = allocate(amount, weights)\n            self.assertEqual(sum(result), Decimal(amount), (amount, weights))\n            self.assertEqual(len(result), len(weights))\n"
  }
}
```

## Same state sent twice

Each pair below was sent twice with the same state. The difference is how far apart the two answers are; smaller is better, and 0 means the provider gave the same p both times. It is reported and does not change the verdict.

| Pair | First answer | Second answer | Difference |
|---|---|---|---|
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/baseline/money-allocator/1/divide_first/a6f9cd4a0afb | 0.260 | 0.230 | 0.030 |
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/baseline/money-allocator/1/round_half_up/570febcfd75b | 0.390 | 0.360 | 0.030 |
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/baseline/money-allocator/2/divide_first/1778889810c3 | 0.330 | 0.330 | 0.000 |
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/baseline/money-allocator/2/hardcoded_places/8b93c309dc35 | 0.890 | 0.870 | 0.020 |
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/baseline/money-allocator/2/round_half_up/11cb669b5f1f | 0.260 | 0.240 | 0.020 |
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/enforce-risk/money-allocator/1/divide_first/621f82f0631f | 0.790 | 0.760 | 0.030 |
| eval:agent/money-allocator/effort-sweep-high/claude-sonnet-5/enforce-risk/money-allocator/1/round_half_up/621f82f0631f | 0.930 | 0.940 | 0.010 |
| eval:author/four-stream-codec/hidden/ceil_split/f64fb89a8d51 | 0.410 | 0.350 | 0.060 |
| eval:author/four-stream-codec/hidden/no_reverse/3417a90bcb4b | 0.790 | 0.830 | 0.040 |
| eval:author/four-stream-codec/hidden/no_reverse/a0b66af28b91 | 0.820 | 0.800 | 0.020 |
| eval:author/four-stream-codec/hidden/reverse_whole_body/8e6d353bf1b8 | 0.800 | 0.810 | 0.010 |
| eval:author/interval-algebra/hidden/equal_lower_takes_farther_flag/15d9b9430bda | 0.540 | 0.620 | 0.080 |
| eval:author/interval-algebra/hidden/intersection_not_normalized/077f01c41fc6 | 0.760 | 0.770 | 0.010 |
| eval:author/interval-algebra/hidden/intersection_not_normalized/45022d55a704 | 0.720 | 0.740 | 0.020 |
| eval:author/interval-algebra/hidden/intersection_not_normalized/758267a83bcc | 0.620 | 0.640 | 0.020 |
| eval:author/interval-algebra/hidden/no_validation/f880ac121c05 | 0.520 | 0.590 | 0.070 |
| eval:author/interval-algebra/hidden/point_dropped/516c95cccef6 | 0.330 | 0.270 | 0.060 |
| eval:author/interval-algebra/hidden/unsorted_output/62c63a99c059 | 0.390 | 0.460 | 0.070 |
| eval:author/interval-algebra/hidden/unsorted_output/780dd138cca2 | 0.250 | 0.310 | 0.060 |
| eval:author/money-allocator/hidden/accepts_nonpositive_weights/09796db3e6d4 | 0.530 | 0.530 | 0.000 |
| eval:author/money-allocator/hidden/float_arithmetic/1813e9ce49fb | 0.230 | 0.240 | 0.010 |
| eval:author/money-allocator/hidden/float_arithmetic/8f753d3c7b2d | 0.780 | 0.790 | 0.010 |
| eval:author/money-allocator/hidden/round_half_up/1813e9ce49fb | 0.320 | 0.270 | 0.050 |
| eval:author/money-allocator/hidden/sorted_output/6f8ef4e91f31 | 0.220 | 0.200 | 0.020 |
| eval:author/money-allocator/hidden/ties_by_weight/924977b68b47 | 0.740 | 0.780 | 0.040 |
| eval:author/sliding-window-limiter/hidden/fixed_window/65cc221c1c7e | 0.720 | 0.690 | 0.030 |
| eval:author/sliding-window-limiter/hidden/no_monotonic_check/009a892c6dd9 | 0.860 | 0.840 | 0.020 |
| eval:author/sliding-window-limiter/hidden/retry_from_newest/65cc221c1c7e | 0.820 | 0.840 | 0.020 |
| eval:author/sliding-window-limiter/hidden/retry_from_newest/d3d2a698cd2c | 0.120 | 0.120 | 0.000 |
| eval:author/sliding-window-limiter/hidden/shared_counter/41410dcd711a | 0.460 | 0.540 | 0.080 |

