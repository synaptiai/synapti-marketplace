---
issue: 271
created: '2026-10-03T06:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-10-03T06:00:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

System One decision point `review.challenge`: on a Path A run of `/flow:review`, each finding that went through the challenge round (A.3) is sent to System One with the code it cites, and the answer is a third voice: it supports the finding or disputes it. In on mode the answer is shown next to the finding as a note and recorded; it never changes a confidence, a disposition, routing or the review decision, and never counts as one of the two DISAGREE answers that drop a finding. Ships `off`. With it off, with no provider, on a Path B run, or with no answer, the review is what it is today. In shadow mode the answer is recorded and nothing the review shows changes.

Decisions (epic #258, 2026-10-03): in on mode the answer is a note only; on a security finding the note is recorded but never shown; the shadow data is a replay of past Path A reviews, labelled by how each finding was resolved, plus live records only when Path A runs anyway, with no extra Path A runs, and a shortfall closes the pull request with the site off and the shortfall stated; the order inside one review is deduplication (#260), then confidence demotion (#261), then (Path A only) this challenge voice; #261 and #271 are separate sites with their own questions, thresholds and modes, and build their state with one shared script, `bin/flow-finding-state.sh`.

Corrections to the accepted spec, made against the code at 8001206d (main 5496f00c plus #260 and #261):
- Placement. The decided order puts this step after deduplication, so it runs in Phase 4 step 2, after the `review.confidence` step (which skips Path A), not at A.4. Its input is the finding set after the same-defect merge: a merged finding is asked once, under its kept id, with its `locations`. The spec's requirement that #260 carry each merged member's note is moot.
- Probe. A marked block `S1_CHALLENGE_MODE_BLOCK` inside the Path A gate fence, after `AGENTTEAM_MODEL_END`, where `USE_PATH_A` is known. It prints `S1_CHALLENGE=shadow|on` only when `USE_PATH_A=1`; on a Path B run the expanded text is unchanged whatever the user set. It finds `flow-s1-mode.sh` with the lookup that skips a copy inside the repository, between `USER_FILES` markers, as `S1_REVIEW_MODES_BLOCK` does.
- Input. As #260 and #261: `CHALLENGE_DIR` is a directory from `mktemp -d` holding `findings.json`, a JSON list written with the Write tool, never a here-document. The session writes the whole finding set; the script decides which findings are asked (consensus, holdout and re-dispatched Path B findings are skipped by rule, not left out by the session). The challenger's answer is derived from the disposition (`validated` AGREE, `refined` REFINE, `kept` DISAGREE, `unchallenged` none), the mapping the spec's replay uses, so the session writes no separate field.
- Script. `bin/flow-s1-challenge.sh` with its Python half `_flow_s1_challenge.py`, as #260 and #261 did, so a replay runs the same code. `REVIEW_CHALLENGE_BLOCK` is a thin wrapper. It uses the request, record and state-keeping code in `_flow_s1_common.py`, shared by the three review sites, and the security rule of `_flow_s1_confidence.py`.
- State. The shared builder's format (`{"finding": {"priority", "category", "problem"}, "code": [...]}`, 30 lines either side, at most three locations, read as files), not the spec's format with `id` and `suggested_fix` and 40 lines read with `git cat-file`. One builder means one format; the facet, the variants, the challenger's answer and the reason are not sent, as the spec requires.
- Output. One line per finding, `S1_CHALLENGE_RESULT=<id> STATE=... CONFIDENCE=<finding's> DISPOSITION=<finding's>`, as `S1_CONFIDENCE_RESULT` is, with the provider's confidence under `ANSWER_CONFIDENCE` so it cannot be read as the finding's. A note is a separate `S1_NOTE=<id> <text>` line.
- Ref `pr:<N>/review-cycle:<C>/<id>`, as the two sibling sites; the kept state is `.flow/runs/<RUN_ID>/system-one-state/challenge-<id>.json`. No copy of the input is kept (`system-one-input/`): each record's `current` (`<challenger answer>:<confidence>:<disposition>`) and `ref`, with the kept state, carry what the comparison reads.
- Cost limits as the siblings: at most 25 findings asked, stop after two `timeout` or `connection` results in a row (`provider-down`), stop at 90 seconds (`budget`). Configuration reasons that would repeat for every finding are asked once.

### Non-goals
- Does not change Path B, `/flow:pr`, the grounding pass, `review.dedup`, `review.confidence` or the review-precision eval.
- Does not replace or reduce the challenge round (A.3); the answer is added to it.
- Never changes a finding's confidence, disposition, priority or category in any mode, and never drops a finding.
- A System One answer never counts toward the A.4 DROPPED row, and the way that row is read today does not change.
- Does not ask about consensus findings, holdout-validation findings, or findings of a facet re-dispatched on Path B.
- Does not ask about a file-level finding, a cited file that is missing or outside the tree, or a line past the end.
- Adds no disposition value, no marker field, nothing to a resolution marker's DISPUTED array or a finding's `status`. The word "contradicts" appears only in the rendered note.
- Runs nothing from the tree under review.
- Does not switch the site on by default.
- No keyword or regex pre-filter on finding text.
- Python 3.12 to 3.14 only.

### Failure modes
- Timeout, HTTP error, redirect, connection failure, malformed reply, missing answer, abstention, below threshold: `STATE=no-answer REASON=<reason>`; no note; confidence and disposition as A.4 left them.
- Provider slow or down: two `timeout`/`connection` results in a row stop the asking (`provider-down`); 90 s stops it (`budget`); at most 25 asked (`cap`).
- Configuration reasons (settings-refused, provider-none, mode-off, ...): asked once, then repeated for each eligible finding with no request.
- Cited path absolute, with `..`, through a symlink, or not a regular file: `path-refused`. Missing file, line past the end, non-UTF-8 or NUL: `file-missing`, `line-out-of-range`, `not-text`. No line: `no-line`.
- Malformed entry (not an object, missing field, id outside `^[A-Za-z][A-Za-z0-9_-]*$`, duplicate id, no reviewers, disposition outside the controlled set): `invalid-finding`, and the loop continues. A findings file that is not a JSON list, a missing tree, a bad ref prefix or run id: exit 2 with `STATE=blocked`, nothing asked.
- Hostile finding text: read by Python from JSON, never interpolated into shell; the output line carries no finding text.
- No run id or no run directory: records go to the per-user state directory and no state is kept.
- The plugin only inside the repository: the probe prints nothing; the block prints `REASON=plugin-missing`; the script run from that copy reports `settings-refused`.
- A repository setting above the user's mode is lowered to the user's by `flow-s1-mode.sh`.
- python3 missing: `S1_CHALLENGE_STATE=no-answer REASON=python-missing`.
- The lead reads a System One dispute as the second DISAGREE and drops the finding: the A.4 table, the protocol reference and the team-coordination skill say an answer never counts toward a drop, and the output carries no drop line and echoes the finding's own confidence and disposition.

### Interface contracts
- `S1_CHALLENGE_MODE_BLOCK` (inside the Path A gate fence): prints `S1_CHALLENGE=shadow` or `S1_CHALLENGE=on` only when `USE_PATH_A=1` and `flow-s1-mode.sh review.challenge` prints that; nothing otherwise. Sends nothing, writes nothing, never reads `systemOne.uses` itself.
- `REVIEW_CHALLENGE_BLOCK` (review.md Phase 4 step 2, after `S1_CONFIDENCE_BLOCK`): env `S1_CHALLENGE`, `CHALLENGE_DIR`, `PR_NUM`, `CYCLE_NUMBER`, `REVIEW_TREE`, `USE_PATH_A` (0 or 1), `RUN_ID` (optional). Skips with `S1_CHALLENGE_STATE=skipped REASON=not-active|path-b|plugin-missing`; refuses a bad input with `STATE=blocked`, exit 2.
- `bin/flow-s1-challenge.sh --findings <file> --tree <dir> --ref-prefix <ref> [--run-id <id>]`: one `S1_CHALLENGE_RESULT=<id> STATE=answered|no-answer|skipped ...` line per finding in input order. Answered adds `ANSWER=support|dispute P= ANSWER_CONFIDENCE= MODEL= CHECKED=<path>:<start>-<end>@<7-char head>[,...] TRUNCATED=0|1`; otherwise `REASON=`. Every line ends with `CONFIDENCE=<finding's> DISPOSITION=<finding's>`. In on mode an answered non-security finding is followed by `S1_NOTE=<id> <text>`; an answered security finding's line carries `NOTE=withheld`. Then `S1_CHALLENGE_MODE=`, `S1_ASKED=`, `S1_CHALLENGE_SUMMARY=answered:<n> no-answer:<n> skipped:<n>`. Exit 0, or 2 with `STATE=blocked` and `ERROR=`. No line drops or re-rates a finding.
- Note text: dispute `System One: the cited code (<CHECKED>) contradicts this finding (confidence <c>, <model>).`; support `System One: nothing in the cited code (<CHECKED>) contradicts this finding (confidence <c>, <model>).`
- Asked: disposition `validated`, `refined`, `kept` or `unchallenged`, and every reviewer a Path A variant (`code-reviewer`, `convention-checker`, `error-handler-inspector`, `security-reviewer`, `test-runner`, each with `-skeptic` or `-verifier`). Skipped: `consensus`, `not-challenged` (any other reviewer: holdout-validation, a re-dispatched Path B agent).
- Call per finding: `flow-s1.sh ask --site review.challenge --state-format json --state-file <f> --current <challenger answer>:<confidence>:<disposition> --ref <prefix>/<id> [--run-id <id>]`.
- Security finding (a reviewer whose name contains `security`, an id starting `SEC-` or `DEP-`, or a category outside the non-security categories of `references/finding-schema.md`): asked and recorded like any other, in shadow and in on mode, so its problem text and the cited code are sent to the provider; no note is ever shown (`NOTE=withheld`). The user confirmed this on 2026-10-08.
- The marker keeps its seven fields and controlled dispositions; `bin/flow-finding-route.sh` is unchanged.
- questions.yaml holds the only threshold (provisional 0.9).

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| The third voice drops or re-rates a finding | a dispute is mapped to LOW, or a support to HIGH, or a dispute plus a challenger DISAGREE drops the finding | on mode, each cell (validated HIGH, refined MEDIUM, kept LOW, unchallenged MEDIUM) at p=0.03 and p=0.97: `CONFIDENCE` and `DISPOSITION` equal the input in all eight lines, no drop line; the "never counts toward a drop" sentence is in review.md A.4, the protocol reference and the skill |
| Direction of the answer | p >= 0.5 printed as dispute | p=0.03 gives `ANSWER=dispute` and the "contradicts this finding" note; p=0.97 gives `support` and "nothing in the cited code contradicts" |
| Shadow or security shows a note | the note follows the exit reason, or ignores the security rule | shadow p=0.03: no `S1_NOTE`, record mode shadow; a client that exits 0 in shadow mode still gives no note; on mode, category auth or a security-reviewer variant: `NOTE=withheld`, no `S1_NOTE`, one request |
| Off or Path B is not identical | the probe prints on a Path B run or with the site off, or the block asks with no provider | the whole gate fence with the site on and Path A off, with the site off, with no provider, and with the plugin only inside the repository: no `S1_CHALLENGE` line, 0 requests, no record |
| The note reaches parsed fields | the note becomes a disposition or a marker field | the on-mode lines routed through `bin/flow-finding-route.sh` give the same output as the rows without System One, with no `LEDGER_WARN` |
| Wrong findings asked, or the reviewers' view sent | consensus, holdout or Path B findings are asked; the challenger answer, the variant or the id reaches the state | consensus, holdout-validation and plain `code-reviewer` findings skipped with 0 requests; the state sent names no id, variant, disposition or challenger answer, and the record's `current` carries them |
