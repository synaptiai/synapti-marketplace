# Second prompt pilot for the System One filters (2026-10-05)

The first prompt pilot (`../results-2026-10-05-review-s1/`) found no `review.dedup` candidate
pair, so the site's candidate rule was changed: two findings in one file are now a candidate
pair when neither is a security finding and their reviewer lists are not identical (before, the
lists could share no reviewer), and the error-handling sub-types `error-handler-inspector` may
write are accepted as categories. These four plain-arm (`review-b`) sessions repeat the first
pilot with that rule: the same two traps, models, effort, prompt and gate. It is a pilot, not
verdict data.

| Model | Effort | Trap | Cost | Session time |
|---|---|---|---|---|
| claude-opus-5-5 | medium | interval-algebra / point_dropped | $1.66 | 140 s |
| claude-opus-5-5 | medium | sliding-window-limiter / counts_denied | $1.24 | 103 s |
| claude-sonnet-5 | high | interval-algebra / point_dropped | $1.28 | 179 s |
| claude-sonnet-5 | high | sliding-window-limiter / counts_denied | $1.55 | 259 s |

Total $5.73. Plugin at `932602d5`. Every session dispatched the five reviewers once, every
finding names its reviewers and a suggested fix, and no run is incomplete. The rule change
touched only text about the `review.dedup` step, which is off in these sessions; the prompt and
the reviewers' instructions are the same as in the first pilot.

## The gate

The definitions are the first pilot's (`pilot-gate.json` has them and the count per run).

| Check | Bar | Result |
|---|---|---|
| Share of eligible P1/P2 findings whose reviewers include `security-reviewer` (both sites skip these). Lower is better. | under 30% | 2 of 9, 22.2% |
| Mean number of `review.dedup` candidate pairs per run, new rule. Higher means the site has more to decide. | at least 1.0 | 2 pairs in 4 runs, 0.5 |
| The same, rule of the first pilot, on these findings | | 0 pairs in 4 runs, 0.0 |

The first check passes and the second fails. Under the new rule the first pilot's findings give
5 pairs in 4 runs (1.25 per run, all 5 in one run), so the two pilots together give 7 pairs in
8 runs (0.875 per run), with pairs in 2 of the 8 runs.

## Why so few pairs

Of the 13 findings the four sessions reported:

- 6 count as security findings: 4 name `security-reviewer`, and 2 P3 findings carry a category
  outside the accepted list (`Naming`, `maintainability`).
- 4 name `test-runner` or `convention-checker` among their reviewers. `review.dedup` pairs only
  findings whose reviewers are all `code-reviewer`, `error-handler-inspector` or
  `integration-verifier`.
- The 3 that remain are in one run (Opus 5.5 on `point_dropped`) and give its 2 pairs.

The Sonnet 5 sessions reported 1 and 2 findings, so they have almost nothing to pair.

## Projected cost of the full re-run

The full re-run is 34 traps per model on Opus 5.5 and Sonnet 5. From these four sessions' mean
cost per model ($1.45 Opus 5.5, $1.41 Sonnet 5), one run per trap and model costs about $97:

| Runs per trap and model | Sessions | From these sessions | Adjusted for the other traps |
|---|---|---|---|
| 2 | 136 | $195 | $205 |
| 3 | 204 | $292 | $307 |

The adjusted column scales each model's cost by how much more its 2026-09-25 plain-arm sessions
cost over all 34 traps than over these two (Opus 5.5 1.10 times, Sonnet 5 1.00 times). Both
columns assume no session of either pilot is reused. Sonnet 5 sessions cost about $0.58 on
2026-09-25 and $1.19 to $1.55 with the current prompt.

2026-10-05: the re-run did not run. A verdict under the bar needs three runs per trap and model
(about $307), over the $260 approved, and two runs cannot apply the bar. Both sites stay `off`.
The outcome is in `references/review-precision-eval.md`, "Result".

## Files

- `findings/<model>/review-b/<case>/<trap>/1.json`: each run's findings as the session reported them.
- `runs.json`, `summary.json`, `summary.md`: the runner's records. The verdict line in
  `summary.md` concerns `review.groundingCritic` and has no meaning here, as only the plain arm ran.
- `pilot-gate.json`: the gate's definitions, the counts per run under both rules, the pairs and
  each session's cost.

The session streams are not kept here. To resume this directory as a replication of the re-run,
put each run's `result.json` back at `runs/<model>/review-b/<case>/<trap>/1/`; the runner skips a
run whose `result.json` exists.
