## Review: PR #{pr_number}

### Findings: P1: {p1_count}, P2: {p2_count}, P3: {p3_count}

> **Note**: Confidence/Disposition columns appear only when paired-reviewer mode (`agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) produced the findings. Single-session reviews omit these columns and emit the legacy 5-field FLOW_REVIEW_CYCLE marker.

#### P1 — Critical (Blocks Merge)
| # | Category | Location | Issue | Suggested Fix | Confidence | Disposition |
|---|----------|----------|-------|---------------|------------|-------------|
| {n} | {category} | {file:line} | {issue} | {fix} | {HIGH\|MEDIUM\|LOW} | {consensus\|validated\|refined\|kept\|unchallenged} |

#### P2 — Important
| # | Category | Location | Issue | Suggested Fix | Confidence | Disposition |
|---|----------|----------|-------|---------------|------------|-------------|
| {n} | {category} | {file:line} | {issue} | {fix} | {HIGH\|MEDIUM\|LOW} | {consensus\|validated\|refined\|kept\|unchallenged} |

#### P3 — Suggestions
- {suggestion} {(Confidence: HIGH/MEDIUM/LOW · Disposition: consensus/validated/refined/kept/unchallenged) — paired-reviewer mode only}

#### Requirements Adherence
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| {n} | {criterion} | {status} | {file:line} |

#### What Looks Good
- {positive observation}

#### Follow-Up Issues
- #{issue_number}: {title} — {if any out-of-scope issues were created}

<!--
Marker has two valid forms — see references/finding-ledger-parser.md:
  Legacy 5-field (single-session reviews):
    FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status},...]
  Extended 7-field (paired-reviewer mode only):
    FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status}|{confidence}|{disposition},...]
Parsers tolerate both.
-->
<!-- FLOW_REVIEW_CYCLE:{cycle_number} FINDINGS:[{F1}|{priority}|{category}|{file:line}|{open}{|HIGH|consensus},{F2}|{priority}|{category}|{file:line}|{open}{|LOW|kept}] -->
