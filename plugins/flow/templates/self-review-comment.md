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
| **{n} · {P1/P2/P3} · `{file:line}`**<br>{issue} | {fix description} |

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

<!--
This review body carries the FLOW_REVIEW_CYCLE marker (what was FOUND, status `open`).
Self-review is raise + resolve in one action: the fix-forwarded findings are recorded as
RESOLVED in a separate FLOW_RESOLUTION_CYCLE marker, posted as a PR issue comment via
`gh pr comment` (built from templates/resolution-comment.md) — the same marker/placement
/flow:address uses, and the only surface the merge finding-ledger gate reads RESOLVED from.
Marker has two valid forms — see references/finding-ledger-parser.md:
  Legacy 5-field (single-session reviews):
    FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status},...]
  Extended 7-field (paired-reviewer mode only):
    FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status}|{confidence}|{disposition},...]
Parsers tolerate both.
-->
<!-- FLOW_REVIEW_CYCLE:{cycle_number} FINDINGS:[{F1}|{priority}|{category}|{file:line}|{open}{|HIGH|consensus},{F2}|{priority}|{category}|{file:line}|{open}{|LOW|kept}] -->
