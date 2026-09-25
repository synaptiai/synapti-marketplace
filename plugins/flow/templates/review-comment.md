## Review: PR #{pr_number}

### Findings: P1: {p1_count}, P2: {p2_count}, P3: {p3_count} · Needs investigation: {needs_investigation_count}

### Checks not run
{checks_not_run — `Tests, advisory audit, duplication scan: not run: someone else's pull request` unless the session opted in with FLOW_REVIEW_RUN_PR_COMMANDS=1; otherwise `none`}

> **Note**: Take the counts from the `FINDINGS_HEADER` printed by `commands/review.md` Phase 4 step 7; LOW-confidence findings are not in P1/P2/P3 and appear only under Needs investigation. Every counted finding ends with a `_(CONFIDENCE · disposition)_` suffix on both review paths (Path B's disposition is `unchallenged`). Escape any literal `|` in a cell as `\|`.

#### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
| **{ID} · {category} · `{file:line}`**<br>{issue} _({HIGH\|MEDIUM} · {consensus\|validated\|refined\|kept\|unchallenged})_ | {fix} |

#### P2 — Important
| Finding | Suggested Fix |
|---------|---------------|
| **{ID} · {category} · `{file:line}`**<br>{issue} _({HIGH\|MEDIUM} · {consensus\|validated\|refined\|kept\|unchallenged})_ | {fix} |

#### P3 — Suggestions
- **{ID} · {category} · `{file:line}`** — {suggestion} _({HIGH|MEDIUM} · {consensus|validated|refined|kept|unchallenged})_

#### Needs investigation
{LOW-confidence findings, at any priority. They are not counted above, do not decide the review, and are not in the review-cycle marker, so they never block the merge. One entry per finding:}
- **{ID} · {priority} · {category} · `{file:line}`** — {problem}
  Pattern: {what triggered the finding}. Confirm or refute: {the test or check that would settle it}.

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
