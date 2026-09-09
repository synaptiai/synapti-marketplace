# Review Cycle Parsing

Reference document for `skills/code-review-methodology/SKILL.md` § Review cycle awareness. Parses the `FLOW_REVIEW_CYCLE` and `FLOW_RESOLUTION_CYCLE` markers that `commands/review.md` and `commands/address.md` post on a PR, so a reviewer on cycle 2+ can focus on the delta and verify claimed resolutions. Marker row grammar is in `references/finding-ledger-parser.md`.

## Counting cycles

Count CHANGES_REQUESTED reviews on the PR to determine the cycle number. The `FLOW_REVIEW_CYCLE:N` marker in each review body gives the same number authoritatively when present.

## Parsing prior markers

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# Parse prior review findings (from review bodies)
gh api repos/$REPO/pulls/$PR_NUM/reviews --jq '
  [.[] | select(.body | test("FLOW_REVIEW_CYCLE")) | {
    cycle: (.body | capture("FLOW_REVIEW_CYCLE:(?<n>[0-9]+)") | .n),
    findings: (.body | capture("FINDINGS:\\[(?<f>[^\\]]+)\\]") | .f)
  }]'

# Parse prior resolution outcomes (from issue comments posted via gh pr comment)
gh api repos/$REPO/issues/$PR_NUM/comments --jq '
  [.[] | select(.body | test("FLOW_RESOLUTION_CYCLE")) | {
    cycle: (.body | capture("FLOW_RESOLUTION_CYCLE:(?<n>[0-9]+)") | .n),
    resolved: (.body | capture("RESOLVED:\\[(?<r>[^\\]]*?)\\]") | .r),
    escalated: (.body | capture("ESCALATED:\\[(?<e>[^\\]]*?)\\]") | .e)
  }]'
```

## Cross-referencing

For each prior finding:

1. Was it marked as resolved in a resolution comment?
2. Has the code at that location changed in `git diff`?
3. Record the result in a **Previous Feedback Status** table:

```markdown
### Previous Feedback Status
| Cycle | Finding | Priority | Claimed Status | Verified |
|-------|---------|----------|----------------|----------|
```

If a finding was claimed resolved but the code at that location is unchanged, flag it as "Not verified — code unchanged".

## Cycle rules

- Focus on the delta since the last review — findings on unchanged code from prior cycles are noise
- On the 3rd+ cycle: only flag NEW P1 findings, note persistent P2s, suggest synchronous discussion for unresolved items
- Note the convergence signal when findings shrink each cycle — this is healthy progress
