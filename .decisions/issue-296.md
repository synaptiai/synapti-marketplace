---
issue: 296
created: '2026-10-09T09:50:00Z'
artifacts:
- type: specification
  captured_at: '2026-10-09T09:38:08Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-10-09T09:38:37Z'
  goal_id: issue-296
  source: github_issue
- type: workflow-run
  captured_at: '2026-10-09T09:38:58Z'
  workflow: start-issue
  run_id: 2026-10-09T093426Z-issue-296
  status: active
- type: stranger-test
  captured_at: '2026-10-09T09:46:16Z'
  result: PASS
  task_count: 8
---

## Specification

The `address.category` question over-raises review feedback to P1 on jev-1.13.0 (2026-10-07 replay: 22% agreement with the reviewer, 96 of 200 items raised at the shipped rule and 0.8). This issue measures one alternative wording, in which each level is described by what happens if the pull request is merged as it is, on the same 200 labelled items, next to the current wording run again in the same session. The alternative replaces the current wording only if it meets the bars below, written before any provider call.

### Non-goals
- The site stays `off`; no mode or threshold changes. Choosing a threshold for the alternative is not part of this issue.
- The question stays a `choice` with option ids P1, P2, P3 and Question, so the block in `/flow:address` that ranks the answer is unchanged. A `score` question was not used: Question has no place on an ordered scale, and a score would change how the block reads the answer.
- No new labelled items, and no ruling on whether a raise is right: the labels are the priorities Flow's review sessions gave, and "raised above its label" does not mean "wrong".
- One alternative wording is measured. No wording is revised after seeing answers; a further wording would be a new, disclosed round.

### Failure modes
- Fewer raises because fewer items were answered (no answer, timeout, truncation): raises are counted over all 200 items, and the answered, no-answer and truncated counts are reported per form.
- Drift between 2026-10-07 and today: the current wording is run again in the same session, and its agreement with the 2026-10-07 answers is reported.
- The label leaking into the state: an item whose text contains P1, P2 or P3 is refused by the harness before sending.
- Replay records mixing with live records: the replay writes to its own state directory, never to `~/.claude/flow-state`.
- Running the plugin from inside the repository: the client refuses user settings there, so the harness runs a copy outside it.

### Interface contracts
- Items: `plugins/flow/evals/results-2026-10-07-address-s1/address-category.jsonl` (200 rows: ref, pr, finding_id, path, line, text, reviewer_priority).
- The block run: `COMMENT_CATEGORY_BLOCK` extracted unchanged from `commands/address.md` of the copy, with SESSION_CATEGORY = the label, PR_NUM, ITEM_KIND and ITEM_ID from the item's ref, and ITEM_FILE = a mktemp file holding `{text, path, line, finding}`.
- Records: one JSON line per request in `<state dir>/system-one.jsonl`, matched to items by `ref` = `pr:<pr>/<kind>:<id>/<finding>`.
- The shipped raise rule: raise when the answer's confidence is at or above the threshold and its option ranks above the label (P1 > P2 > P3 > Question).

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Raise count | Counting raises over answered items only, so a form with more no-answers looks better | Summary counts over all 200; a test feeds 3 items, one unanswered and two raised, and expects 2 raises of 3 |
| Raise rule | Using the probability of P1 instead of the answer's confidence, or `>` instead of `>=` at the threshold | Test item with confidence exactly 0.8 and choice above the label counts as a raise at 0.8 |
| Which form was run | The alternative run reading the current wording (copy not patched), giving identical answers | Harness prints the sha256 of the question block it sent; summary checks it equals the registered alternative's |
| P1 placed lower | Counting every lower answer, not only those on items labelled P1 | Test: a P2 item answered P3 does not count; a P1 item answered P2 does |

## Pre-registration (written before any provider call)

**Alternative wording** (choice, ids unchanged):

- instructions: "`comment.text` is one item of review feedback on a pull request, written by a reviewer about the file `comment.path` near line `comment.line` (either may be empty). Most items describe something that is wrong; the levels differ in what happens if the pull request is merged without the change. Judge from what the item says happens and when, not from how serious its wording sounds or whether it calls the problem a bug."
- P1: "If merged as it is, someone using the changed feature in the normal way gets a wrong result, a crash or a hang, loses or exposes data, or can get past a security check."
- P2: "If merged as it is, normal use works, but something goes wrong in an unusual case or on an unusual input, an error goes unreported, a test or document is missing or wrong, or the code breaks a project convention."
- P3: "Nothing goes wrong if merged as it is: the item is about wording, naming, style, readability or an optional improvement."
- Question: "The item asks for an explanation or a decision and does not say that anything is wrong."

**Runs**, both on jev-1.13.0 over the same 200 items in one session: the current wording (control) and the alternative.

**Bars** (at the shipped rule, threshold 0.8, raises counted over all 200 items):
1. The alternative's raises are at most half of the current wording's raises in the same session.
2. The alternative places no more labelled P1 items lower than the current wording does in the same session.
3. The alternative answers at least 195 of the 200 items.

The alternative replaces the current wording only if all three hold. Agreement with the label, the full matrices and the raises at every threshold are reported for both forms but are not bars.

**Measurement check.** A spurious pass would look like: many fewer answers, or the alternative run sending the current wording. Bar 3 and the sent-question hash cover these. If the current wording today agrees with its 2026-10-07 answers on fewer than 90% of items, that is reported as drift before any comparison is read.

**Settled before the run (2026-10-09, from the plan's open questions).**
- Bar 2 counts a labelled P1 item as placed lower when the answer's choice ranks below P1, at any confidence; the count at 0.8 is reported next to it. The site never lowers an item, so this reading is the stricter one.
- "Answered" means a record that carries an answer (`answered` or `below-threshold`). A truncated item stays in the denominator and is never a raise, because the block does not act on it.
- The control runs first and the alternative second, from one commit on the same day; each form's record time span is reported. A ref with several records uses the last one, and retries are reported.
- `current.yaml` (the shipped wording at b3866e96) is committed beside `alternative.yaml`, so the control's sent wording can be checked after `questions.yaml` changes.

## Stranger Test

PASS — 8 tasks reviewed (register wordings; summary counting test; summarize.py; harness E2E test; run.sh; provider run; report and conditional replacement; quality checks). Each names its files, interface, discriminating tests with sources, verification command and Reuses line.
