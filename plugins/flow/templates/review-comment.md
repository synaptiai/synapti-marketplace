## Review: PR #{pr_number}

### Findings: P1: {p1_count}, P2: {p2_count}, P3: {p3_count} · Needs investigation: {needs_investigation_count}

### Checks not run
{checks_not_run — `Tests, advisory audit, duplication scan: not run: someone else's pull request` unless the session opted in with FLOW_REVIEW_RUN_PR_COMMANDS=1; otherwise `none`}

> **Note**: Take the counts from the `FINDINGS_HEADER` printed by `commands/review.md` Phase 4 step 7; LOW-confidence findings are not in P1/P2/P3 and appear only under Needs investigation. Every counted finding ends with a `_(CONFIDENCE · disposition)_` suffix on both review paths (Path B's disposition is `unchallenged`), and names its trigger (`references/review-scope.md`). Escape any literal `|` in a cell as `\|`.

#### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
| **{ID} · {category} · `{file:line}`**<br>{issue}<br>Trigger: {input or condition} → {what goes wrong} _({HIGH\|MEDIUM} · {consensus\|validated\|refined\|kept\|unchallenged})_ | {fix} |

#### P2 — Important
| Finding | Suggested Fix |
|---------|---------------|
| **{ID} · {category} · `{file:line}`**<br>{issue}<br>Trigger: {input or condition} → {what goes wrong} _({HIGH\|MEDIUM} · {consensus\|validated\|refined\|kept\|unchallenged})_ | {fix} |

#### P3 — Suggestions
- **{ID} · {category} · `{file:line}`** — {suggestion}. Trigger: {input or condition} _({HIGH|MEDIUM} · {consensus|validated|refined|kept|unchallenged})_

#### Needs investigation
{LOW-confidence findings, at any priority. They are not counted above, do not decide the review, and are not in the review-cycle marker, so they never block the merge. One entry per finding:}
- **{ID} · {priority} · {category} · `{file:line}`** — {problem}
  Pattern: {what triggered the finding}. Confirm or refute: {the test or check that would settle it}.
{For a finding System One demoted (`review.confidence`), the Pattern line is `Pattern: System One: the cited code does not show this defect (p={p}, {model}).`}
{For a finding in `NO_TRIGGER`, the Pattern line is `Pattern: names no trigger.` and Confirm or refute names the input that would show it.}

#### Not counted in this cycle
{Only from cycle 2: every id in the router's `NOT_COUNTED` (P3 from cycle 2, P2 from cycle 3). They decide nothing and are not in the review-cycle marker; the author fixes them in the P3 batch, which starts no new cycle. A plain bullet, never the bold shape of a counted finding:}
- {ID} ({priority}, {category}, `{file:line}`) — {problem}
{On a Path A run with `review.challenge` on, a finding with an `S1_NOTE` line shows that note as plain text: in its cell after the issue and before the suffix, or for a LOW finding at the end of its Pattern line. Never in the suffix or the review-cycle marker.}

#### Dropped as out of scope
{Only when a finding was dropped with `REASON=out-of-scope`: one plain bullet each, `- {ID} ({priority}, {category}, `{file:line}`) — {problem}: {the review-scope rule its trigger falls under}`, so a reader can disagree with the rule rather than never see the finding. Omit the section when nothing was dropped.}

#### Blast radius

{Only when the diff changes a contract — an exported signature, or a file `bin/flow-contract-files.sh`
names (openapi, graphql, protobuf, migration, schema, goal-contract), or a symbol in the goal's
interface contracts. One row per consumer found. A consumer absent from the diff is a
`breaking-change` P1 above, and this row cites the same location. Say which tool found the consumers;
omit the section entirely when no contract changed.}

| Contract changed | Consumer | In this PR? | Found by |
|---|---|---|---|
| `{file:line}` ({kind}) | `{consumer file:line}` | {yes / no — F{n}} | {findReferences \| incomingCalls \| grep} |

#### Requirements Adherence
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| {n} | {criterion} | {status} | {file:line} |

#### What Looks Good
- {positive observation}

#### Follow-Up Issues
- #{issue_number}: {title} — {if any out-of-scope issues were created}

<!--
Do not write the review-cycle marker (FLOW_REVIEW_CYCLE) into this body. The posting
block in commands/review.md Phase 4 step 7 appends it from bin/flow-finding-route.sh
and refuses a body that already carries one. Its rows are 7-field on both review paths,
  {ID}|{priority}|{category}|{file:line}|{status}|{confidence}|{disposition}
and no LOW row is ever written. Parsers also accept legacy 5-field rows; see
references/finding-ledger-parser.md.
-->
