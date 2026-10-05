# Prompt pilot for the System One filters (2026-10-05)

Four plain-arm (`review-b`) review sessions, run on 2026-10-05 with the prompt that asks each
finding's reviewers and suggested fix, to check that the planned re-run could measure
`review.dedup` and `review.confidence` before it was paid for. It is a pilot, not verdict data.

| Model | Effort | Trap | Cost | Session time |
|---|---|---|---|---|
| claude-opus-5-5 | medium | interval-algebra / point_dropped | $1.71 | 132 s |
| claude-opus-5-5 | medium | sliding-window-limiter / counts_denied | $1.40 | 121 s |
| claude-sonnet-5 | high | interval-algebra / point_dropped | $1.19 | 397 s |
| claude-sonnet-5 | high | sliding-window-limiter / counts_denied | $1.27 | 650 s |

Total $5.57. Plugin at `6aa8797b`. The effort is pinned to what each model ran at on 2026-09-25
(Opus 5.5 medium, Sonnet 5 high, read from those sessions' transcripts). Three sessions dispatched
the five reviewers; the Sonnet 5 session on `point_dropped` dispatched `code-reviewer` twice and
no `test-runner`. Every finding names its reviewers and a suggested fix, and no run is
incomplete.

## The gate

The re-run was to go ahead only if both held:

| Check | Bar | Result |
|---|---|---|
| Share of eligible P1/P2 findings whose reviewers include `security-reviewer` (both sites skip these). Lower is better. | under 30% | 1 of 6, 16.7% |
| Mean number of `review.dedup` candidate pairs per run. Higher means the site has more to decide. | at least 1.0 | 0 pairs in 4 runs, 0.0 |

The second check failed, so the re-run was not started. `pilot-gate.json` has the definitions
and the count per run.

## Why no pair

Of the 21 findings the four sessions reported:

- 8 name `security-reviewer` among their reviewers, and 2 name `convention-checker` or
  `test-runner`. `review.dedup` pairs only findings whose reviewers are all `code-reviewer`,
  `error-handler-inspector` or `integration-verifier`.
- 8 carry a category outside the list the sites accept, and 6 of those are the error-handling
  sub-types `error-handler-inspector` is told it may write (`silent-failure`,
  `missing-validation`, `error-handling/silent-failure` and others). The sites treat any category
  outside the list as a security finding.
- The 3 that remain are in one run, and every two of them share `code-reviewer`. A pair needs
  disjoint reviewer sets.

The session consolidates findings by `file:line` before it reports them, and lists every
reviewer that raised a finding, so two reviewers' findings at one line are already one finding.
If the error-handling sub-types were accepted, the same findings would give 2 pairs in 4 runs
(0.5 per run), still under the bar.

2026-10-05, after this pilot: `review.dedup`'s candidate rule changed. Two findings in one file
are now a candidate pair when neither is a security finding and their reviewer lists are not
identical (they no longer need disjoint reviewer sets), and `error-handling`, its four sub-types
and any category of the form `error-handling/<sub-type>` are accepted. Under that rule these
findings give 5 pairs in 4 runs (1.25 per run, all in one run); the counts and pairs per run
under both rules are in `candidate-pairs-2026-10-05.json`. The counts above are those of the
rule this pilot ran with. The outcome is in `references/review-precision-eval.md`, "Result,
2026-10-05".

## Files

- `findings/<model>/review-b/<case>/<trap>/1.json`: each run's findings as the session reported them.
- `runs.json`, `summary.json`, `summary.md`: the runner's records. The verdict line in
  `summary.md` concerns `review.groundingCritic` and has no meaning here, as only the plain arm ran.
- `pilot-gate.json`: the gate's definitions and counts.
- `candidate-pairs-2026-10-05.json`: the `review.dedup` candidate pairs per run under the rule
  of `932602d5` and under the rule this pilot ran with, with the same definitions.

The session streams are not kept here. To resume this directory as the first replication of the
re-run, put each run's `result.json` back at `runs/<model>/review-b/<case>/<trap>/1/`; the runner
skips a run whose `result.json` exists.
