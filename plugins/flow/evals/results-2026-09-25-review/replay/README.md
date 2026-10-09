# Pilot replay over recovered findings (not verdict data)

This directory is a pilot of the System One replay harness. It replays `review.dedup` and
`review.confidence` over the 136 plain-arm (`review-b`) runs of 2026-09-25, whose findings were
recovered from the session transcripts. It tests the harness. It is not evidence for either
site's verdict: a verdict needs the run described in `references/review-precision-eval.md`,
"System One filters", which has not been made. The result is in that section, "Result".

Why it cannot be the verdict:

- The recovered findings name no reviewers. Each finding is credited to every subagent whose
  report cites its exact line, so the reviewer lists are inferred, not stated by the session.
- Under the candidate rule this replay ran with, 133 of the 136 runs have no `review.dedup`
  candidate pair (6 pairs in all), so `review.dedup` is not exercised. Under the shipped rule,
  131 runs have none (12 pairs in all; `../candidate-pairs-2026-10-05.json`), and the 6 are
  among the 12. The 6 this replay asked about:
  - Opus 5.5, interval-algebra `merge_only_overlapping` run 2: F1+F3 and F3+F5.
  - Opus 5.5, interval-algebra `unsorted_output` run 1: F2+F5 and F3+F5.
  - Sonnet 5, money-allocator `accepts_nonpositive_weights` run 2: F2+F4 and F2+F6.
- The 2026-09-25 runs have two replications, not three. The threshold is chosen on
  replication 1 and judged on replication 2 alone, so no spread can be computed and the bar
  cannot be applied.

The rule this replay ran with paired two findings in one file only when their reviewer lists
shared no reviewer, and did not accept the error-handling sub-types as categories. The shipped
rule pairs them when the lists are not identical and accepts the sub-types, which gives these
findings 12 pairs in 5 runs instead of 6 in 3.

## What ran

| Step | Result |
|---|---|
| Plugin code | the replay harness (`bin/flow-eval-s1-replay.sh`) with the earlier candidate rule; the report was written after the threshold check was changed to count only answers that a finding is not supported |
| Export | 136 runs, 628 findings; every run re-scores to its recorded score |
| Scratch trees | 34, built with the pinned commit date; a rebuild in another directory gave the same 34 HEADs (`trees.json`) |
| Shadow pass | TypeSafe `jev-1.13.0`, 2026-10-04 22:27-22:32 UTC, timeout 10 s: 6 pairs and 134 findings asked, every one answered, every record names `jev-1.13.0` (`shadow/base/`) |
| Representatives pass | nothing to ask: no threshold point merged a pair (`shadow/reps/`) |
| Answer table | 140 states, no conflicts, none unanswered (`table.json`) |
| On passes | off, 4 dedup points, 4 confidence points, 16 dedup-then-confidence points, all answered by the replay server with 0 misses (`on/<point>/pass.json`) |
| Merge inspection | no merged pair to label (`merged-pairs.json` is empty) |
| Report | `report.md`, `report.json` |

## Files kept

- `trees.json`: the HEAD of each scratch tree.
- `shadow/base/pass.json` and `shadow/reps/pass.json`: each shadow pass's state, totals and
  per-run counts.
- `shadow/base/<model>/review-b/<case>/<trap>/<n>/`: per run, `in.json` (the findings the site
  scripts were given), `dedup.out` and `confidence.out` (the scripts' output), and under `run/`
  the client's records (`system-one.jsonl`, one per call, with the answer and the model) and
  the states it sent (`system-one-state/`). `table.json` is built from these two.
- `table.json`: every kept state's recorded answer, per run.
- `on/<point>/pass.json`: each on pass's state, server counts, the answers it was served, and per
  run the merged pairs and demoted findings.
- `merged-pairs.json`, `report.json`, `report.md`.

Not kept: the per-run output of the on passes (about 56 MB; each on pass rebuilds it from
`table.json` with no provider call, and git ignores it), the shadow runs' stderr, review.dedup's
unchanged copy of the findings and the confidence script's demoted list (the shadow pass
writes these under `<work>/logs/`; shadow mode demotes nothing, so no demoted list is written),
and the client's lock files (not copied, and ignored by git). Machine paths in the kept script
output are written as `<replay>`, `<work>` and `<findings>`. The `DEDUP_OUT=` line of each kept
`dedup.out` names `<replay>/shadow/base/.../dedup-out.json`: this pass wrote that copy into the
run directory, and the copy was not kept.

## Answers

- `review.dedup`: all 6 pairs answered "different defect": the provider put the chance that
  the two findings were one defect at 4% to 19% (p from 0.04 to 0.19), and a pair merges only
  when that chance is at least 80% (at the lowest threshold point, 0.6). No pair merged at any
  threshold.
- `review.confidence`: 134 findings asked, p from 0.35 to 0.95, median 0.81. Three answers were
  below 0.5 (the finding is not supported): p 0.35, 0.37 and 0.48, which is confidence 0.30,
  0.26 and 0.04, below every threshold point (0.6 to 0.95). No finding was demoted at any threshold.
- Of the 274 P1 and P2 findings in a category the sites accept, 139 were not asked because a
  `security-reviewer` subagent also cites their line, which makes them security findings under
  the shipped rule. With reviewers inferred from cited lines this exclusion is larger than it
  would be with reviewers the session names.

## Scores

Precision is the share of scored findings that point at the seeded defect; recall is the share
of runs that found it; F1 combines the two. Higher is better for all three. LOW findings are left
out. Every filter at every threshold point scored exactly as the plain findings, because nothing
was merged or demoted.

| Model | Replication | Runs | Precision | Recall | F1 |
|---|---|---|---|---|---|
| claude-opus-5-5 | 1 | 34 | 0.279 | 1.000 | 0.436 |
| claude-opus-5-5 | 2 | 34 | 0.286 | 1.000 | 0.444 |
| claude-opus-5-5 | both | 68 | 0.282 | 1.000 | 0.440 |
| claude-sonnet-5 | 1 | 34 | 0.340 | 1.000 | 0.507 |
| claude-sonnet-5 | 2 | 34 | 0.355 | 0.971 | 0.520 |
| claude-sonnet-5 | both | 68 | 0.347 | 0.985 | 0.513 |

The verdict lines in `report.md` read `not-exercised` (`review.dedup`) and
`insufficient-replications` (`review.confidence`). Neither is a result about the sites.
