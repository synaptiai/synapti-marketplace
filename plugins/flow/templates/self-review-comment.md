## Self-Review Summary

Performed self-review with fix-forward.

### Verdict Summary

{If verdict.enabled:}

| Overall | Criteria Passed | Criteria Failed | Human Review |
|---------|----------------|-----------------|--------------|
| {PASS/FAIL/NEEDS-HUMAN-REVIEW} | {N} | {N} | {N} |

{If any FAIL or NEEDS-HUMAN-REVIEW — show failures first:}

**Requires attention:**
| # | Criterion | Verdict | Rationale |
|---|-----------|---------|-----------|
{Only FAIL and NEEDS-HUMAN-REVIEW rows}

{If all PASS:}
All criteria verified independently.

{If not verdict.enabled:}
Verdict: N/A (independent verdict not enabled)

### Findings Found & Fixed
| Finding | Fix Applied |
|---------|-------------|
| **{n} · {P1/P2/P3} · `{file:line}`**<br>{issue} _({HIGH\|MEDIUM} · {disposition})_ | {fix description} |

### Needs investigation
{Every LOW-confidence finding raised on this PR and how it ended. A LOW finding counts as a fixed defect only when a test confirmed it; a refuted one is not a defect and is not in the table above.}
| Finding | Outcome |
|---------|---------|
| **{ID} · {P1/P2/P3} · `{file:line}`**<br>{issue} | Confirmed — test `{test path}` failed on the unfixed code; fixed, recorded HIGH, listed above. |
| **{ID} · {P1/P2/P3} · `{file:line}`**<br>{issue} | Refuted — test `{test path}` passes on the current code; recorded as `dropped-finding` (`self-review-refuted`). |
| **{ID} · {P1/P2/P3} · `{file:line}`**<br>{issue} | Unsettled — no test or command could decide it; escalated below and recorded MEDIUM. |

### Escalated for Human Judgment
{Only populated if findings could not be fixed in-PR. Each escalation uses the six-field Proactive-Autonomy structure.}

**{Item summary}**
- **Situation**: {what, file:line}
- **Tried**: {what was considered, why it didn't resolve in-PR}
- **Options**: {2–3 concrete paths}
- **Recommendation**: {recommended option}
- **Blocking?**: {yes / soft / no — no calendar-time language}
- **Risk**: {consequence of deferring}

### Verification
- [x] Quality commands pass after fixes
- [x] No new issues introduced
- [x] All P1/P2/P3 findings in touched files fixed in-PR or escalated
- [x] Every LOW-confidence finding confirmed, refuted or escalated

<!--
Do not write the review-cycle marker (FLOW_REVIEW_CYCLE) into this body. The posting
block in commands/review.md Phase 4 step 7 appends it (what was FOUND, status `open`)
and refuses a body that already carries one. Its rows are 7-field on both review paths,
  {ID}|{priority}|{category}|{file:line}|{status}|{confidence}|{disposition}
and no LOW row is written: a refuted LOW finding is dropped, a confirmed one is HIGH.
Self-review is raise + resolve in one action: the fix-forwarded findings are recorded as
RESOLVED in a separate FLOW_RESOLUTION_CYCLE marker, posted as a PR issue comment via
`gh pr comment` (built from templates/resolution-comment.md) — the same marker/placement
/flow:address uses, and the only surface the merge finding-ledger gate reads RESOLVED from.
An escalated LOW finding (recorded MEDIUM) goes in that marker's ESCALATED list.
Parsers also accept legacy 5-field rows; see references/finding-ledger-parser.md.
-->
