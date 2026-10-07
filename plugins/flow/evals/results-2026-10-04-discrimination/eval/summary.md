# System One test-discrimination measurement

Question: if the module did what the risk row's plausible wrong version describes, would this test fail? p is the provider's probability of yes. A pair is flagged when the provider is confident the test would still pass: confidence |2p - 1| at least t and p below 0.5.

Set: eval. Pairs scored: 5077 (0 unobserved pairs left out). Provider: typesafe jev-1.13.0.

## Measurement checks

Each check says what the result would look like if the harness, not the model, produced it. They are read before any metric.

| Check | Result |
|---|---|
| Records match pairs (name-stripped) | yes: 5077 pairs, 5077 answered, no answer 0, 0 retried |
| Records match pairs (real) | yes: 5077 pairs, 5077 answered, no answer 0, 0 retried |
| Coverage at least 95% | yes (agent 100.0%) |
| Answers spread out (fail and pass answers not both over 80% in one bin; both classes predicted) | yes (agent largest bin 24.0%) |
| Shuffled-wrong-version placebo: averaged over the case-and-trap groups, the mean real-description AUC exceeds the mean placebo AUC by at least 0.15; per-group gaps are reported, not judged (larger is better; a gap of 0 means the description adds nothing to the test alone) | not run |
| Real-description AUC, mean within case and trap, not more than 2 standard errors below 0.5 (below means the question is read the wrong way round) | yes (AUC 0.907, standard error with no signal 0.019, over 32 case and trap groups holding 4833 pairs; pooled over all pairs, reported and not judged: AUC 0.878, standard error 0.012) |
| Label-permutation AUC, mean within case and trap, within 0.02 of 0.5 | yes (agent 0.500; pooled agent 0.513) |
| Test name removed, agent pairs (reported, not judged; a drop well above its standard error means the answers lean on the name, not the code) | AUC 0.878 with the name, 0.872 without; drop 0.006, standard error 0.003, over 5077 pairs answered both ways |
| Same state sent twice: how far apart the two answers are (smaller is better; reported, not judged) | not measured: no pair was answered twice |
| States over a provider's cap | 0 over imajev's 7,000 tokens, 0 over TypeSafe's 28,000 (largest 6380 bytes) |
| Threshold fixed on the dev set before the evaluation records | t = 0.60, chosen 2026-10-05T05:47:39Z at commit 8943ec76a27ff60b1ed37dbe5bb40a9fb8c02c1d |

## Adoption bar

Verdict: **not-adopted**. A clause of the bar does not hold at t=0.60.

On agent-written pairs at t = 0.60:

1. Tests that do fail against the wrong version, flagged as if they would pass: 10 of 707 (Wilson 95% upper bound 2.6%; must be at most 5%; lower is better): holds.
2. Hard negatives (tests that pass against this wrong version but fail another) flagged: 638 of 3169 (Wilson 95% lower bound 18.8%; must be at least 30%; higher is better): does not hold.

## Results per stratum

Accuracy and balanced accuracy read p at 0.5. AUC: 0.5 is chance, 1.0 is perfect ordering of fail above pass. Brier: lower is better. Brier skill: above 0 beats always answering the base rate.

| Stratum | Ablation | Pairs | Coverage | Fail / pass (hard negatives) | Accuracy (constant) | Balanced accuracy | AUC | Brier (constant) | Brier skill |
|---|---|---|---|---|---|---|---|---|---|
| agent | name-stripped | 5077 | 100.0% | 707 / 4370 (3169) | 78.1% (86.1%) | 78.0% | 0.872 | 0.154 (0.120) | -0.284 |
| agent | real | 5077 | 100.0% | 707 / 4370 (3169) | 76.9% (86.1%) | 79.7% | 0.878 | 0.160 (0.120) | -0.335 |

## Per case (real descriptions)

| Stratum | Case | Pairs | Coverage | Fail pairs | AUC | Note |
|---|---|---|---|---|---|---|
| agent | four-stream-codec | 756 | 100.0% | 157 | 0.883 |  |
| agent | interval-algebra | 2470 | 100.0% | 251 | 0.909 |  |
| agent | money-allocator | 976 | 100.0% | 172 | 0.828 |  |
| agent | sliding-window-limiter | 875 | 100.0% | 127 | 0.900 |  |

## Threshold sweep, agent pairs

| t | Fail pairs flagged (lower is better) | Wilson upper | Hard negatives flagged (higher is better) | Wilson lower | All pass pairs flagged (reported) | Wilson lower, upper |
|---|---|---|---|---|---|---|
| 0.50 | 30 of 707 | 6.0% | 1123 of 3169 | 33.8% | 1857 of 4370 | 41.0%, 44.0% |
| 0.55 | 15 of 707 | 3.5% | 843 of 3169 | 25.1% | 1485 of 4370 | 32.6%, 35.4% |
| 0.60 | 10 of 707 | 2.6% | 638 of 3169 | 18.8% | 1185 of 4370 | 25.8%, 28.5% |
| 0.65 | 1 of 707 | 0.8% | 335 of 3169 | 9.5% | 709 of 4370 | 15.2%, 17.3% |
| 0.70 | 1 of 707 | 0.8% | 185 of 3169 | 5.1% | 395 of 4370 | 8.2%, 9.9% |
| 0.75 | 0 of 707 | 0.5% | 17 of 3169 | 0.3% | 69 of 4370 | 1.2%, 2.0% |
| 0.80 | 0 of 707 | 0.5% | 3 of 3169 | 0.0% | 17 of 4370 | 0.2%, 0.6% |
| 0.85 | 0 of 707 | 0.5% | 0 of 3169 | 0.0% | 0 of 4370 | 0.0%, 0.1% |
| 0.90 | 0 of 707 | 0.5% | 0 of 3169 | 0.0% | 0 of 4370 | 0.0%, 0.1% |
| 0.95 | 0 of 707 | 0.5% | 0 of 3169 | 0.0% | 0 of 4370 | 0.0%, 0.1% |

Reliability, agent pairs (a calibrated provider has fail rate close to mean p in each bin):

| p bin | Pairs | Mean p | Fail rate |
|---|---|---|---|
| 0.0-0.1 | 1 | 0.090 | 0.000 |
| 0.1-0.2 | 1046 | 0.161 | 0.007 |
| 0.2-0.3 | 1216 | 0.240 | 0.037 |
| 0.3-0.4 | 700 | 0.341 | 0.051 |
| 0.4-0.5 | 465 | 0.443 | 0.060 |
| 0.5-0.6 | 461 | 0.543 | 0.115 |
| 0.6-0.7 | 418 | 0.646 | 0.266 |
| 0.7-0.8 | 325 | 0.741 | 0.329 |
| 0.8-0.9 | 195 | 0.842 | 0.651 |
| 0.9-1.0 | 250 | 0.934 | 0.772 |

## Appendix: five states

Each state below is what the provider received for that pair. It should show the test and the risk row's wrong version, and no hidden test name other than the test's own.

### eval:agent/money-allocator/discrimination-2026-10-05/claude-sonnet-5/baseline/money-allocator/2/hardcoded_places/539804ec9996

sha256 2683552215706085662552e3aa346e5f22c31e3ad7f4efd1df1e1066f1356e8e, record matches: yes

```json
{
  "risk": {
    "area": "hardcoded places",
    "plausible_wrong_version": "`places` ignored, always 2"
  },
  "test": {
    "id": "PlacesTests.test_places_three_quantization",
    "source": "import unittest\nfrom allocate import allocate\n\n\nclass PlacesTests(unittest.TestCase):\n    def test_places_three_quantization(self):\n        shares = allocate(\"0.003\", [1, 1, 1], places=3)\n        for s in shares:\n            # quantized to exactly 3 decimal places\n            self.assertEqual(-s.as_tuple().exponent, 3)\n"
  }
}
```

### eval:agent/interval-algebra/discrimination-2026-10-05/claude-sonnet-5/enforce-risk/interval-algebra/2/shorthand_halfopen/99aa2adc1d30

sha256 a095bbfc888f804a84e96ff2daa4b6efe73568fc9b8d4e3e170619b0780a9eb9, record matches: yes

```json
{
  "risk": {
    "area": "shorthand halfopen",
    "plausible_wrong_version": "2-tuple read as `[lo, hi)`"
  },
  "test": {
    "id": "NormalizeCanonicalTests.test_canonical_shorthand_becomes_closed_interval",
    "source": "import unittest\nfrom intervals import normalize, union, intersection, difference\n\n\nclass NormalizeCanonicalTests(unittest.TestCase):\n    def test_canonical_shorthand_becomes_closed_interval(self):\n        # Source: ISSUE.md Representation \"Shorthand\" rule.\n        result = normalize([(1, 2)])\n        self.assertEqual(result, [(1, 2, True, True)])\n"
  }
}
```

### eval:agent/sliding-window-limiter/discrimination-2026-10-05/claude-sonnet-5/enforce-risk/sliding-window-limiter/3/fixed_window/199bdadb430f

sha256 36ab0c87fd6787ebaf71c1cae9941afe9d2ccb6eaa6336a1be915eba62b8df83, record matches: yes

```json
{
  "risk": {
    "area": "fixed window",
    "plausible_wrong_version": "Buckets aligned to multiples of `window`"
  },
  "test": {
    "id": "ConstructorRejectTests.test_reject_negative_limit",
    "source": "import unittest\nfrom ratelimit import SlidingWindowLimiter\n\n\nclass ConstructorRejectTests(unittest.TestCase):\n    def test_reject_negative_limit(self):\n        with self.assertRaises(ValueError):\n            SlidingWindowLimiter(-1, 10)\n"
  }
}
```

### eval:agent/interval-algebra/discrimination-2026-10-05/claude-sonnet-5/enforce-risk/interval-algebra/3/merge_only_overlapping/576e8cf5a96e

sha256 2c5a1f5e60afa86dd2d31c3c9649adc33b374cac8dd0b2c42b9bc17c4cfae33f, record matches: yes

```json
{
  "risk": {
    "area": "merge only overlapping",
    "plausible_wrong_version": "Merge only when `hi1 > lo2`; touching closed ends stay apart"
  },
  "test": {
    "id": "TestDifference.test_difference_open_subtrahend_leaves_closed_cuts",
    "source": "import unittest\nfrom intervals import normalize, union, intersection, difference\n\n\nclass TestDifference(unittest.TestCase):\n    def test_difference_open_subtrahend_leaves_closed_cuts(self):\n        # Source: ISSUE.md Rule #7: \"[1, 5] - (2, 3) is [1, 2] + [3, 5]\".\n        # Subtrahend open at 2 and 3 -> cuts stay closed.\n        result = difference([(1, 5, True, True)], [(2, 3, False, False)])\n        self.assertEqual(\n            result,\n            [(1, 2, True, True), (3, 5, True, True)],\n        )\n"
  }
}
```

### eval:agent/interval-algebra/discrimination-2026-10-05/claude-sonnet-5/baseline/interval-algebra/3/shorthand_halfopen/ce0c938a40ea

sha256 f6fa685a0ad79b3c0fc6ba65a4a1e0972529ab4b8fdf589dbbc6a8f920b6ee70, record matches: yes

```json
{
  "risk": {
    "area": "shorthand halfopen",
    "plausible_wrong_version": "2-tuple read as `[lo, hi)`"
  },
  "test": {
    "id": "UnboundedAndValidationTests.test_bounds_wrong_tuple_length_raises",
    "source": "import unittest\nfrom intervals import normalize, union, intersection, difference\n\n\nclass UnboundedAndValidationTests(unittest.TestCase):\n    def test_bounds_wrong_tuple_length_raises(self):\n        with self.assertRaises(ValueError):\n            normalize([(1, 2, 3)])\n        with self.assertRaises(ValueError):\n            normalize([(1,)])\n"
  }
}
```

