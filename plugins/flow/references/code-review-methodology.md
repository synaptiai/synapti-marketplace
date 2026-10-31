# Code Review Methodology Detail

Detail for `skills/code-review-methodology/SKILL.md`.

## System One duplicate check (`review.dedup`)

A System One provider is asked whether two remaining findings in one file, whose reviewer lists differ, describe the same defect (`review.dedup`, off by default; `references/system-one.md`). In on mode a confident yes merges them under the finding with the highest priority, listing every location and reviewer. A security finding, a LOW finding paired with a HIGH or MEDIUM one, and two findings with the same reviewer list are never merged.

## System One confidence check (`review.confidence`)

A P1/P2 finding that a confident System One answer says its cited code does not show is LOW (`review.confidence`, off by default; `references/system-one.md`). On someone else's pull request such a P1 stays counted, with the answer as a note.

## Grounding pass

`review.groundingCritic: on` inserts one step into a **Path B** fan-out, between synthesis and display: `Agent(finding-critic)` answers each P1/P2 finding in a three-verdict grammar, and on a disagreement the reviewer that raised it cites code or drops it. **Path A is unchanged** and keeps its own challenge round; the grammar and both placements are in `references/paired-review-protocol.md`. Default off until `references/review-precision-eval.md`.
