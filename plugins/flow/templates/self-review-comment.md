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
| # | Priority | Location | Issue | Fix Applied |
|---|----------|----------|-------|-------------|
| {n} | {P1/P2/P3} | {file:line} | {issue} | {fix description} |

### Escalated for Human Judgment
{Only populated if findings could not be fixed in-PR. Each escalation uses the six-field Proactive-Autonomy structure.}

**{Item summary}**
- **Situation**: {what, file:line}
- **Tried**: {what was considered, why it didn't resolve in-PR}
- **Options**: {2–3 concrete paths}
- **Recommendation**: {recommended option}
- **Time sensitivity**: {blocking / urgent / safe to wait}
- **Risk**: {consequence of deferring}

### Verification
- [x] Quality commands pass after fixes
- [x] No new issues introduced
- [x] All P1/P2/P3 findings in touched files fixed in-PR or escalated
