---
issue: 212
created: '2026-09-15T17:59:32Z'
artifacts:
- type: specification
  captured_at: '2026-09-15T17:59:32Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-15T18:07:16Z'
  goal_id: issue-212
  source: github_issue
  ac_count: 7
- type: workflow-run
  captured_at: '2026-09-15T18:07:57Z'
  workflow: start-issue
  run_id: 2026-09-15T172641Z-issue-212
  status: active
- type: stranger-test
  captured_at: '2026-09-15T19:00:16Z'
  result: PASS
  task_count: 7
---
# Issue #212 — finding confidence is display-only, and the review rules disagree about whether it blocks

## Design decisions (user-confirmed 2026-09-15)

- **Confidence on every path.** Path B's `FLOW_REVIEW_CYCLE` marker becomes 7-field like Path A's, with disposition `unchallenged`, and the rendered finding tables carry the `_(CONFIDENCE · disposition)_` suffix on both paths. Chosen over a render-only suffix and over routing without rendering.
- **LOW at any priority** goes to `Needs investigation`; priority is shown there for triage and is never changed by confidence.
- **External review with only LOW findings** posts APPROVE with the `Needs investigation` section, as the issue is written.
- **Confirming a LOW finding on the agent's own PR** means a test (or, for prose, a command) that fails on the current code. Fails → fixed and recorded HIGH. Passes → refuted, the test stays and is cited as evidence for `dropped-finding` with `reason=self-review-refuted`.
- **Reason spelling** is `self-review-refuted` (hyphen), matching #214's closed set; the issue body was edited to match.
- **The routing rule is a script, and the prose calls it.** `bin/flow-finding-route.sh` reads the consolidated finding rows and the review mode and prints the per-priority counts, the `Needs investigation` ids, the decision, the 7-field marker rows and any `LEDGER_WARN` lines. `commands/review.md` steps 6 and 7 run it. Chosen over prose-only (the ACs as written) and over prose plus a table-parsing test, because the risk-map rows for absent confidence, marker exclusion, header counts and the only-LOW decision can then be tested as input → output rather than as wording.

## Specification

_Captured by specification-capture skill on 2026-09-15. Source: mixed._

### Non-goals

- Merge gate Check 1 (ESCALATED) and Check 2 (FINDINGS − RESOLVED) and `DISPUTED` semantics are unchanged; dismissals belong to #214.
- The marker parsers in `commands/merge.md`, `commands/status.md` and `references/finding-ledger-parser.md` are unchanged: they already accept 7-field rows and read only ID and priority. LOW routing happens where the marker is written, not where it is read.
- Confidence never changes a finding's priority or category; a LOW P1 stays P1 inside `Needs investigation`.
- No numeric or calibrated confidence score and no threshold setting: three words only (#211 rejected `min_confidence_score`).
- Path A's consolidation table (which disposition earns which confidence) is unchanged.
- `convention-checker` and `test-runner` are not moved onto the confidence rule; they are not on the finding schema.
- `/flow:address` resolution handling is unchanged.

### Failure modes

- **Timeouts** — none — the change adds no network or agent call; Path A reviewer timeouts keep today's fallback (`MEDIUM|unchallenged`).
- **Partial failures** — an agent gives confidence on some findings and not others: each missing one becomes MEDIUM with its own `LEDGER_WARN` naming the agent, and the rest keep their values. A self-review LOW finding that no test or command can reproduce or refute is escalated with the six-field structure and listed in `ESCALATED` of the resolution marker; it is never left LOW and never recorded HIGH.
- **Invalid input** — a confidence other than HIGH, MEDIUM or LOW (matched case-insensitively, so `high` is HIGH, while `0.8`, `maybe` and `Medium-High` are invalid) is treated as absent: MEDIUM plus a `LEDGER_WARN` naming the agent and the value.
- **Missing context** — `PR_AUTHOR` or `CURRENT_USER` resolves empty (gh auth or network failure): Phase 4 step 4 halts with an error instead of comparing two empty strings as equal and taking the self-review path, which would fix-forward onto someone else's branch.

### Interface contracts

- Agent finding row (`code-reviewer`, `security-reviewer`, `error-handler-inspector`, `integration-verifier`): Finding cell `**{ID} · {category} · `{location}`**<br>{problem} _({HIGH|MEDIUM|LOW})_`; the confidence suffix is required. The orchestrator renders `_({CONFIDENCE} · {disposition})_` on both paths.
- `FLOW_REVIEW_CYCLE` marker: 7-field on Path A and Path B, `ID|priority|category|location|status|confidence|disposition`; Path B disposition is `unchallenged`. No LOW row is written: on an external review LOW findings are excluded, and on the agent's own PR each is re-recorded HIGH or dropped. Legacy 5-field rows still parse.
- External review body: a `#### Needs investigation` section after P3 with one entry per LOW finding: id · priority · category · location, the problem, `Pattern:` (what triggered it) and `Confirm or refute:` (what would settle it). Header line `P1: X, P2: Y, P3: Z · Needs investigation: N`, with LOW findings excluded from X, Y and Z.
- Decision table: any HIGH or MEDIUM P1 → REQUEST_CHANGES; any HIGH or MEDIUM P2 → REQUEST_CHANGES; HIGH or MEDIUM P3 only → COMMENT; none, or LOW only → APPROVE.
- `dropped-finding` journal artifact: `cycle`, `finding_id`, `facet`, `reason=self-review-refuted`, `pr`, written with `bin/journal-record.sh`.
- `LEDGER_WARN: PR#<N> finding '<id>' from <agent> has no confidence — treated as MEDIUM` and `LEDGER_WARN: PR#<N> finding '<id>' from <agent> has invalid confidence '<value>' — treated as MEDIUM`.
- `review-cycle` journal `path` metadata names the orchestration that ran (`A` or `B`); it is no longer inferred from marker width.
- `templates/pr-body.md` and `templates/self-review-comment.md`: a `Needs investigation` section listing each LOW finding and its outcome (confirmed → fixed with a test; refuted → evidence), separate from the P1/P2/P3 counts.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| absent confidence | treats a missing confidence as LOW (demotion by omission) | external PR, one P1 with no confidence → right: MEDIUM, REQUEST_CHANGES, marker row present, `LEDGER_WARN` naming the agent; wrong: listed under Needs investigation, APPROVE, no marker row |
| exclusion scope | excludes LOW findings on the agent's own PR too | own PR, one LOW P2 → right: ends fixed and HIGH with a test, or `dropped-finding` `reason=self-review-refuted`; wrong: listed as an open investigation |
| marker vs decision | drops LOW from the decision but still writes its marker row | external PR, F1 HIGH P2 and F2 LOW P1 → right: `FINDINGS:[F1|…]` only; wrong: F2 in the marker, so merge Check 2 blocks on it |
| header counts | counts LOW findings in the P1/P2/P3 counts | same PR → right: `P1: 0, P2: 1, P3: 0 · Needs investigation: 1`; wrong: `P1: 1, P2: 1` |
| contradiction test | the test can only confirm (checks the phrase's absence only) | fixture with the phrase and an `Any P1` row → fires; fixture with conditional rows and one rule → silent; fixture with no decision table → fails |
| only-LOW decision | posts COMMENT or REQUEST_CHANGES when every finding is LOW | external PR, only F1 LOW P1 → right: `--approve` with the section; wrong: `--request-changes` |

<!-- auto-log: 2026-09-15 19:59 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-212.md -->

<!-- auto-log: 2026-09-15 20:05 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-212.md -->

<!-- auto-log: 2026-09-15 20:25 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-implementation-planner/project_no_task_tools_in_planner.md -->

<!-- auto-log: 2026-09-15 20:25 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-implementation-planner/feedback_serialize_shared_test_files.md -->

<!-- auto-log: 2026-09-15 20:25 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-implementation-planner/MEMORY.md -->

<!-- auto-log: 2026-09-15 20:27 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-implementation-planner/project_no_task_tools_in_planner.md -->

<!-- auto-log: 2026-09-15 20:28 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-implementation-planner/MEMORY.md -->

## Plan decisions (2026-09-15)

User-confirmed:

- **`/flow:pr` applies the same LOW rule as self-review.** Phase 4 step 6 confirms each LOW finding with a failing test (fixed, HIGH), refutes it with a passing test, or escalates it; its reviewer prompts ask for confidence; refuted drops are journaled once `gh pr create` returns the PR number; `pr-body.md` lists each outcome.
- **Rows from producers outside the finding schema** (holdout-validation, convention-checker, test-runner) are stamped MEDIUM by the orchestrator before routing, so `LEDGER_WARN` fires only when one of the four schema agents omits confidence.
- **Marker-breaking characters are percent-encoded in the marker row only.** In category and location, `%` → `%25`, `,` → `%2C`, `]` → `%5D`, and an escaped `\|` in the input → `%7C`. Parsers read only ID and priority; the rendered body keeps the real text. A row is never rejected for these characters.

Settled from the specification and the code:

- An escalated self-review LOW finding is written as MEDIUM, status `open`, and listed in `ESCALATED` (merge Check 1 blocks on it).
- A Path A `kept` finding confirmed in self-review keeps disposition `kept`; confidence records the verification, disposition the challenge history.
- `tests/finding-schema/row-schema.json` keeps `confidence` optional (the runtime rule tolerates absence); only its description changes.
- The real methodology file is also asserted free of "Only High-confidence P1s block merge", which is wrong on its own now that a MEDIUM P1 blocks.
- `facet` on a Path B `dropped-finding` is the name of the agent that raised the finding.
- `findings_count` in the `review-cycle` artifact is `COUNT_P1+COUNT_P2+COUNT_P3`, the number of marker rows.

## Plan

Route script contract: `flow-finding-route.sh --mode external|self --pr <N> [--input <file>] [--allow-empty]`; rows `ID|PRIORITY|category|location|CONFIDENCE|disposition|agent` on stdin or file; exit 0 routed, 1 usage/validation/zero rows without `--allow-empty`, 2 unreadable input, 3 self mode with unresolved LOW rows (stdout then carries only `ROWS_READ` and `UNRESOLVED_LOW`, no marker). Stdout keys in order: `ROWS_READ`, `COUNT_P1`, `COUNT_P2`, `COUNT_P3`, `COUNT_NEEDS_INVESTIGATION`, `NEEDS_INVESTIGATION`, `DECISION`, `MARKER_ROWS`. Bash 3.2 compatible.

1. Route script and `tests/flow-finding-route.test.sh` (AC7; risk rows absent confidence, exclusion scope, marker vs decision, header counts, only-LOW decision).
2. One confidence rule in `code-review-methodology` and a contradiction checker with must-fire, must-stay-silent and input-removal fixtures (AC1; contradiction test).
3. Confidence required in `finding-schema.md` and the four agents; 7-field on both paths in `finding-ledger-parser.md`, `paired-review-protocol.md`, `row-schema.json` description and README (AC4; absent confidence).
4. `review.md` A.6, Path B prompts, step 3 header, steps 6 and 7 run the script through an extractable block; non-schema rows stamped MEDIUM; `path` metadata names the orchestration (AC2, AC7; marker vs decision, header counts, only-LOW decision).
5. `review.md` step 4 identity guard, step 5 LOW protocol with an extractable `dropped-finding` block; `decision-journal-schema.md` documents `self-review-refuted`; `pr.md` Phase 4 step 6 and step 13 carry the same protocol (AC3; exclusion scope).
6. Needs investigation sections in the three templates and a sweep for retired wording and LOW marker rows (AC5; header counts).
7. Full suite, root tests, bash 3.2 syntax check, read-through of review.md Phase 4, CI on both OS jobs (AC6).

## Stranger Test

PASS — 7 tasks reviewed. Each task names its files, contract, failure modes, risk rows with a discriminating input and the source of its expected value, and the verification command from the goal. Gaps found in the planner's draft and closed before this result: `/flow:pr` had no LOW protocol (added to task 5), rows from non-schema producers had no confidence source (task 4), and bracketed locations had no marker encoding (task 1).

<!-- auto-log: 2026-09-15 21:04 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-finding-route.test.sh -->

<!-- auto-log: 2026-09-15 21:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-finding-route.test.sh -->

<!-- auto-log: 2026-09-15 21:05 Write /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-finding-route.sh -->

<!-- auto-log: 2026-09-15 21:17 commit "fix(flow): add flow-finding-route.sh so confidence decides what a review finding may demand" -->

<!-- auto-log: 2026-09-15 21:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/code-review-methodology/SKILL.md -->

<!-- auto-log: 2026-09-15 21:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/code-review-methodology/SKILL.md -->

<!-- auto-log: 2026-09-15 21:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/finding-confidence.test.sh -->

<!-- auto-log: 2026-09-15 21:36 commit "fix(flow): give code-review-methodology one confidence rule and a decision table that agrees with it" -->

<!-- auto-log: 2026-09-15 21:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/finding-ledger-parser.md -->

<!-- auto-log: 2026-09-15 21:47 commit "fix(flow): require confidence of the four reviewer agents and write 7-field markers on both paths" -->

<!-- auto-log: 2026-09-15 21:54 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/finding-confidence.test.sh -->

<!-- auto-log: 2026-09-15 22:02 commit "fix(flow): route and post /flow:review findings through flow-finding-route.sh" -->

<!-- auto-log: 2026-09-15 22:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-09-15 22:08 commit "fix(flow): end every own-PR LOW finding fixed, refuted or escalated, and stop empty identities choosing self-review" -->

<!-- auto-log: 2026-09-15 22:13 commit "fix(flow): give the review templates a Needs investigation section apart from the counts" -->

<!-- auto-log: 2026-09-15 22:32 commit "fix(flow): tidy the #212 review blocks after shellcheck and a read-through" -->

<!-- auto-log: 2026-09-15 22:54 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-15 23:02 commit "fix(flow): close the posting-block gaps the #212 self-review found" -->

## Phase 4 self-review, round 1 (code-reviewer, reviewed at 1ac4203)

P1: 0, P2: 4, P3: 8 — all fixed in 4118d39, each with a test that failed on 1ac4203.

- The posting block let a body quote `FINDINGS:[…]`; the merge gate reads ids from the whole body, so a LOW id could reach Check 2 that way. The block now refuses any quoted ledger array.
- The header check matched a substring (`Needs investigation: 12` passed for 1); it now matches the whole `### Findings:` line.
- `CYCLE_NUMBER` was only checked for being non-empty and could close the HTML comment; it must now be a positive integer.
- A LOW finding could also appear in a priority table; the block refuses one outside Needs investigation.
- The route script matched ids with locale-dependent ranges (`Fé1` passed under UTF-8); ids are checked under the C locale.
- The dropped-finding block required an `ISSUE` nothing set; it resolves the linked issue and skips when there is none.
- `findings_count=$TOTAL` read an unset variable; both blocks print `COUNT_TOTAL` and the manifest uses it.
- Stamping MEDIUM on holdout findings would have overwritten Path A's HIGH `consensus`; the stamp now applies only when the producer gave none.
- `/flow:pr` could loop on an escalated LOW finding; escalated findings stay in the PR body and do not re-enter the fix loop.
- The parser reference, finding schema and a merge.md comment still described the first draft; corrected, and marker percent-encoding is documented.
- An assertion (`assert_contains "MEDIUM"`) could only confirm; it now asserts the absent-confidence sentence.

<!-- auto-log: 2026-09-15 23:24 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-15 23:24 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

## Phase 4 self-review, round 2 (targeted re-review of 4118d39)

P1: 0, P2: 2, P3: 7 — all fixed, each with a test that failed before the fix.

The same defect class appeared twice: posting guards that check less than a review body can contain. The cause was that each guard matched lines against an assumed body shape (a section ends at `####`; the first `#N` is the linked issue), and each had one hand-written test body built from the same assumption. The fixes address the cause as well as the instances:

- The Needs investigation section is found by splitting the body at markdown headings of any level, skipping code fences, so a `###` table after it is outside it.
- A body rendered from `templates/review-comment.md` itself is posted through the block in the tests, so the real template's structure and closing comment are exercised.
- The linked issue is the one a closing keyword names (`Closes #N`), in both the dropped-finding and review-cycle manifest blocks; a failed `gh pr view` is an error, not "no linked issue".
- The review-cycle manifest block refuses a non-numeric `PR_NUM`, `CYCLE_NUMBER` or `COUNT_TOTAL`.
- The ledger-syntax refusal covers only `FINDINGS:[`: `RESOLVED`, `ESCALATED` and `DISPUTED` are read only from issue comments, so a self-review body may name them.
- `/flow:pr` step 7's condition excludes escalated findings.
- Tests: the id-outside check is tested on its own (a LOW id relabelled HIGH), `COUNT_TOTAL` is checked across P1, P3 and a LOW P2, and the merge.md comment check reads the whole file.

<!-- auto-log: 2026-09-15 23:31 commit "fix(flow): parse review-body headings and closing keywords instead of assuming their shape" -->


## Phase 4 self-review, round 3 (targeted re-review of 2f52452)

P1: 0, P2: 5, P3: 1 — all fixed, each with a test that failed before the fix.

Cause: the guard parsed structure it only needed to shape-match. Three rounds ran on the same
defect — a posting guard that has to know where the Needs investigation section ends, and an issue
lookup that has to know which `#N` in free text is the linked one. Each round taught the parser one
more markdown construct (code fences, then heading levels, then setext headings, blockquote
headings and `<h1-6>`), and each round the next construct got past it. What the guard has to enforce
never needed a section: a LOW finding is rendered as a Needs investigation entry and nowhere else.

- The posting block no longer splits the body. It refuses any line carrying a `_(LOW` suffix, and
  requires each LOW id to appear exactly once, in the entry shape `- **{ID} · {priority} · ` at the
  priority it was routed with. A counted finding opens `**{ID} · {category} · `, so a second
  occurrence of `**{ID} · ` is that finding rendered as a counted one, whatever surrounds it.
  `bin/flow-finding-route.sh` prints `NEEDS_INVESTIGATION_PRIORITIES` (`F2:P1`) for the priority check.
- P3 bullets in `templates/review-comment.md` now carry the finding id, so the same count covers them.
- The linked issue comes from GitHub, not from body text: `bin/flow-pr-linked-issue.sh` reads the
  pull request's `closingIssuesReferences`, keeps the issues in the same repository, and prints the
  lowest number (a NOTE on stderr names them all when there are several). Every call site uses it:
  `/flow:review` Phase 1, the A.4 dropped-finding record, the step 5 dropped-finding record, the
  review-cycle manifest, the workflow-run record, and `/flow:merge`'s escalation-resolved record. A
  pull request into a branch other than the default closes no issue, so GitHub lists none and the
  record is skipped; a failed `gh` call is an error, never "no issue".
- The A.4 record was a snippet referencing an `$ISSUE` nothing set; it is now a block that validates
  its inputs, resolves the issue and skips cleanly, like the step 5 one.
- `CYCLE_NUMBER` and `PR_NUM` must be positive integers in the manifest and dropped-finding blocks
  (`0`, `08` and `-1` are refused); `COUNT_TOTAL` still accepts `0`, which is a clean review.
- Tests: the eight round-3 bodies (odd fences, setext, blockquote and HTML headings) are posted
  through the block and refused; the five body texts that fooled a keyword regex (`hotfix #210`,
  `unresolved #210`, a quoted `Closes #12`, a fenced `Fixes #12`, a mention before the keyword) are
  recorded against the issue GitHub lists; a sweep over `commands/` finds no lookup that greps an
  issue number out of text, and fires on a fixture that plants both retired lookups. Ten mutants
  were run against the new checks and the helper — all ten were caught.

<!-- auto-log: 2026-09-15 23:58 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-15 23:58 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-16 00:17 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-pr-linked-issue.test.sh -->

<!-- auto-log: 2026-09-16 00:19 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/edit_fc_tests.py -->

<!-- auto-log: 2026-09-16 00:22 Write /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-pr-linked-issue.sh -->

<!-- auto-log: 2026-09-16 00:23 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 00:26 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/finding-confidence.test.sh -->

<!-- auto-log: 2026-09-16 00:27 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/mutants.sh -->

<!-- auto-log: 2026-09-16 00:51 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/journal_round3.py -->
