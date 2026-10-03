---
issue: 260
created: '2026-10-03T00:18:04Z'
artifacts:
- type: specification
  captured_at: '2026-10-03T00:18:04Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

System One decision point `review.dedup`: at the synthesis step of `/flow:review` (Phase 4 step 2) and `/flow:pr` (Phase 4 step 1), each candidate pair of consolidated findings is asked one yes/no question: do these two findings describe the same defect? Ships `off`. With it off, or with no provider, both commands print and post what they do today.

Decisions (epic #258, 2026-10-03): one noul question per candidate pair; a merged finding's marker row keeps the representative's own location (seven fields, one location), and the rendered review lists every location and every reviewer; the order inside one review is deduplication (#260), then confidence demotion (#261) on the merged set, then the challenge voice (#271, Path A only); live shadow labels are hand judgements of each answered pair from its saved state, made before its answer is read; #262's eval run decides the threshold and the default.

Corrections to the accepted spec, made against the code at main 5496f00c:
- The client checks the threshold before it looks at the mode (`_flow_s1.py` `ask()`), so in shadow mode an unsure answer exits 3 with `below-threshold`, not `shadow`. Following the exit reason alone would put a `related` mark on findings in shadow mode. The script therefore takes the mode once from `bin/flow-s1-mode.sh --all review.dedup` (the one place the mode rule lives; it never reads `systemOne.uses` itself), prints it as `MODE=`, and changes the finding set only when that mode is `on`. Exit 3 `shadow` is also treated as no change.
- Code is read from someone else's pull request, so it is read with `git cat-file -t` and `git cat-file blob` at `HEAD:<path>`, not `git show`: cat-file prints the blob as stored, with no textconv or filter, and a symlink as its target text. Every git call also runs with `GIT_ATTR_SOURCE` set to the tree's own empty-tree hash (`git hash-object -t tree /dev/null`, so a SHA-256 repository works) and `safe.bareRepository=explicit`, as the review dispatches do.
- The blocks take `DEDUP_DIR`, a directory from `mktemp -d` holding `findings.json`, instead of the spec's `FINDINGS_FILE`; the output is written to `dedup-out.json` in the same directory. The directory is private to the user, so the output path cannot be raced in the temporary directory, and the path is the same on every run, so a block's stdout is the same under zsh and bash, which the e2e harness compares. #261 and #271 extend these blocks with the same convention.
- PR #282 (`S1_ADDRESS_MODES_BLOCK`, `STILL_APPLIES_BLOCK`) is not on main. Its patterns are copied from its branch; the shared lines in questions.yaml, system-one.md and CHANGELOG.md use the same wording it uses.
- Counters partition the pairs asked: `PAIRS_ASKED = PAIRS_SAME + PAIRS_DIFFERENT + PAIRS_RELATED + PAIRS_NO_ANSWER`. `PAIRS_RELATED` counts below-threshold answers in on mode. A confident "same" for a LOW and a counted finding is in `PAIRS_SAME` and also prints a `RELATED` line.
- The stop reasons are every reason that sends nothing and would repeat for every pair: settings-refused, provider-none, python-missing, mode-off, invalid-settings, insecure-url, no-api-key, unknown-site, no-threshold, questions-invalid. One of them on the first pair gives `DEDUP_STATE=no-answer REASON=<reason>`.
- Code window: from 20 lines above the lower line to 20 lines below the higher one, at most 120 lines; when the span is longer, it is the 120 lines from 20 above the lower line (the margin above shrinks first when the two lines alone are more than 120 apart, so the lower line is always in it). Then cut at a line boundary to 16 KB. Lines are counted at newline characters only, as git counts them. A file larger than 8 MB is not read, and a window holding a NUL byte or bytes that are not UTF-8 is sent empty, as the shared state builder refuses such a file with not-text. Pairs of one file are asked one after another, so the file is read once for all of them and only that file is held.
- A finding counts as security, and is never asked about, when any of its reviewers contains `security`, its id starts `SEC-` or `DEP-`, or its category is not one of the non-security categories in `references/finding-schema.md`. This is the rule the record steps apply to a grounding-pass drop (`DROPPED_FINDING_BLOCK`), and it covers the listed security categories of review.md's grounding text and every category outside the vocabulary (csrf, ssrf).
- In `/flow:pr` both the probe and `REVIEW_DEDUP_BLOCK` sit inside `USER_FILES` markers, so both use the same install outside the repository.

### Non-goals
- Does not change the exact file:line merge synthesis does today; review.dedup runs after it.
- Does not merge, mark or ask about a pair with a security finding in it.
- Does not ask about a finding raised by a producer outside the finding schema (holdout-validation, convention-checker, test-runner, in either path).
- Does not merge two findings from the same reviewer; reviewer sets are compared, so an A.2 consensus finding is never asked against a finding from either variant.
- Does not merge a LOW finding with a HIGH or MEDIUM one; such a pair is asked, and in on mode a confident "same" only marks it related.
- Does not change Path A's A.2 window or A.3/A.4, demote confidence (#261), touch the GROUNDING_PASS_SHARED text, the seven marker fields, `bin/flow-finding-route.sh`, or the merge, status and address parsers.
- Does not run the precision eval, choose the default, or switch the site on.
- No keyword, line-distance or text-similarity pre-filter. No new journal artifact type.
- Python 3.12 to 3.14 only.

### Failure modes
- Provider slow or down: stop after 2 consecutive `timeout` or `connection` results, and before a call that would start past the budget (90 s; `FLOW_S1_DEDUP_BUDGET_S` may lower it, clamped to whole seconds 1-90, anything else is 90). Pairs not asked are `UNASKED` and stay apart.
- One pair fails, others answer: each pair is its own call; a group forms only from pairs that each answered "same".
- HTTP error, redirect, connection, malformed, missing answer, abstention, internal error: the pair stays apart with no mark. Only below-threshold, in on mode, marks it related.
- Settings refused, provider none, python missing, mode off and the other configuration reasons: the script stops asking, writes DEDUP_OUT equal to the input, and prints `DEDUP_STATE=no-answer REASON=<reason>` when it was the first pair.
- Probe and client disagree: the script follows `flow-s1-mode.sh --all` at call time and the client's reason; the lower mode wins.
- Malformed findings file (not JSON, not a list, an entry without id, priority, category, location or reviewers, an empty reviewers list, an id outside `^[A-Za-z][A-Za-z0-9_-]*$`, a duplicate id, a bad priority or confidence): `STATE=blocked ERROR=<what>`, exit 2, no request.
- Hostile finding text: read from JSON by Python and written to the state as JSON; never in a shell or jq program. Rendered lines are plain text.
- Hostile location: a path with a `..` segment, a leading `/`, a backslash, NUL or a control character gets an empty code window. Code is read only with `git -C <tree> cat-file blob HEAD:<path>`, so a symlink gives its target text and no textconv driver runs.
- Too many candidates: ordered by (file, line distance, id a, id b); the first 24 are asked; the rest are UNASKED.
- Merge chains: complete linkage after all answers are in, over the "same" pairs in asked order.
- No RUN_ID or no run directory: records go to the per-user state directory; pair states are not kept.
- Ref shape: `REF_PREFIX` must match the client's ref grammar; a final ref over 200 characters uses `pair:<16 hex of sha256 of the two ids>`. In /flow:pr the prefix is `branch:<branch>@<12-character head>`, as `review.confidence` names its records there, so the records of reviews of one branch at different commits stay apart; a branch outside the grammar or longer than 130 characters gives `head:<12-character head>`.
- Off is not identical: the probe prints nothing, the block never runs, the stub receives nothing, and no record is written.

### Interface contracts
- `S1_REVIEW_MODES_BLOCK` (`!` fence, review.md and pr.md): prints `S1_DEDUP=shadow` or `S1_DEDUP=on` when `flow-s1-mode.sh review.dedup` prints that, and nothing otherwise. Sends nothing, writes nothing.
- `bin/flow-s1-dedup.sh --findings <file> --out <file> --tree <dir> --ref-prefix <ref> [--run-id <id>]`: exit 0 with KEY=value lines whatever the answers; exit 2 with `STATE=blocked` and `ERROR=` on a usage error or a malformed findings file. Never exit 3.
- Findings file: a JSON list of objects with id, priority (P1|P2|P3), category, location, problem, suggested_fix, confidence (HIGH|MEDIUM|LOW|""), disposition, reviewers (non-empty list). Extra keys are carried through.
- Output lines: `DEDUP_STATE=answered|no-answer|skipped`, `REASON=` (no-answer, skipped), `MODE=`, `BUDGET_S=`, `FINDINGS_IN=`, `FINDINGS_OUT=`, `PAIRS_CANDIDATE=`, `PAIRS_ASKED=`, `PAIRS_SAME=`, `PAIRS_DIFFERENT=`, `PAIRS_RELATED=`, `PAIRS_NO_ANSWER=`, `NO_ANSWER_<REASON>=` per reason seen, `UNASKED=`, `MERGED=<kept>+<absorbed>...`, `RELATED=<id>+<id>`, `DEDUP_OUT=<path>`. Nothing depends on the clock except how many pairs a slow provider leaves unasked.
- DEDUP_OUT: same shape. On mode: absorbed findings removed; the representative gains `locations`, `reviewers` (union), `also_reported_as` [{id, reviewers, location, priority, problem}]; any finding may gain `related` [{id, why: unsure|mixed-confidence}]. Otherwise equal to the input after JSON normalisation. `location` keeps the representative's own.
- Representative: highest priority, then highest confidence (HIGH > MEDIUM > ""), then first in input order. A group never mixes LOW with non-LOW.
- Candidate pair: same file (normalised: leading `./` removed, `.` segments dropped), disjoint reviewer sets, every reviewer a schema reviewer (code-reviewer, error-handler-inspector, integration-verifier, or one of them with `-skeptic` or `-verifier`), neither a security finding, both line-cited or both file-level.
- State per pair: `{"file", "a": {"location","category","problem","suggested_fix"}, "b": {...}, "code": {"head","start","end","text"}}`; problem and suggested_fix cut to 2,000 characters; no reviewer, priority, confidence or disposition.
- Call per pair: `flow-s1.sh ask --site review.dedup --state-file <tmp> --state-format json --current separate --ref <REF_PREFIX>/pair:<a>+<b> [--run-id <RUN_ID>]`.
- Pair states kept at `.flow/runs/<RUN_ID>/system-one-state/dedup-<a>+<b>.json` when that run directory exists and a request was sent; written through `bin/flow-mkdir.sh` and a temporary file moved into place; its sha256 equals the record's `state_sha256`.
- questions.yaml holds the only threshold (provisional 0.8).

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Below-threshold versus no answer | every exit 3 marks the pair related, or none does | on mode, p=0.7 gives RELATED and `related` on both; HTTP 500 gives neither and NO_ANSWER_HTTP_500=1 |
| Shadow changes output | the script follows the exit reason, so a shadow below-threshold answer marks the pair; or shadow applies merges | shadow with p=0.99 and with p=0.7: no MERGED or RELATED line, DEDUP_OUT equal to the input, a record with mode shadow |
| Security exemption | only category=security is checked | DEP-1/dependency, a security-reviewer-skeptic finding with category correctness, a category injection finding, a category csrf finding: 0 requests, no merge |
| Merge drops a blocker | the representative is the first in input order | (P3 first, P1 second) keeps P1; (MEDIUM P2, HIGH P2) keeps HIGH; (LOW P1, HIGH P2) is never merged and both carry related |
| Merge chain | greedy union of "same" pairs | A~B 0.99, B~C 0.99, A~C 0.02: one group of two, C apart; with A and C from one reviewer A~C is never asked |
| Code from someone else's tree | read through the filesystem or with textconv | a `../` location gets an empty window; a symlink gives its target text; a textconv driver named in .gitattributes never runs |
