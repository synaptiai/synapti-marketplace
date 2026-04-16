---
description: "Merge an approved pull request. Verifies prerequisites (approval, checks, conversations), displays assessment, and requires explicit human confirmation. Tier 3 — never autonomous."
argument-hint: <pr-number>
allowed-tools: Bash, Read, AskUserQuestion, Skill
---

# Merge PR #$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. This is non-negotiable even in autonomous mode.

## Required Skills

- `merge-and-release` — prerequisite verification, merge execution

## Phase 1: Verify Prerequisites

**Parallel checks:**

```bash
# 1. PR status
gh pr view $ARGUMENTS --json reviewDecision,statusCheckRollup,mergeable,mergeStateStatus,title,headRefName

# 2. Reviews
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | "\(.state) by \(.author.login) at \(.submittedAt)"'

# 3. Unresolved conversations (reviewThreads requires GraphQL API)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo $REPO | cut -d/ -f1)
NAME=$(echo $REPO | cut -d/ -f2)
gh api graphql -f query="query { repository(owner: \"$OWNER\", name: \"$NAME\") { pullRequest(number: $ARGUMENTS) { reviewThreads(first: 100) { nodes { isResolved } } } } }" --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'

# 4. Stale approval check
gh pr view $ARGUMENTS --json reviews,commits --jq '{
  last_approval: [.reviews[] | select(.state == "APPROVED")] | sort_by(.submittedAt) | last | .submittedAt,
  last_commit: .commits | last | .committedDate
}'

# 5. Finding-ledger check
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
COMMENTS=$(gh api "repos/$REPO/issues/$ARGUMENTS/comments" --jq '.[] | select(.body | test("FLOW_RESOLUTION_CYCLE|FLOW_REVIEW_CYCLE")) | {id: .id, body: .body}')
```

### Finding-Ledger Check

Parse the latest `FLOW_RESOLUTION_CYCLE` and `FLOW_REVIEW_CYCLE` comments to verify all findings are resolved before merge.

```bash
# Extract the latest FLOW_RESOLUTION_CYCLE comment
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
RESOLUTION_BODY=$(gh api "repos/$REPO/issues/$ARGUMENTS/comments" \
  --jq '[.[] | select(.body | test("FLOW_RESOLUTION_CYCLE:"))] | last | .body // ""')

# Extract ESCALATED array contents
ESCALATED=$(echo "$RESOLUTION_BODY" | grep -oP 'ESCALATED:\[\K[^\]]*' || echo "")

# Extract the latest FLOW_REVIEW_CYCLE comment
REVIEW_BODY=$(gh api "repos/$REPO/issues/$ARGUMENTS/comments" \
  --jq '[.[] | select(.body | test("FLOW_REVIEW_CYCLE:"))] | last | .body // ""')

# Extract all finding IDs from FINDINGS array (comma-separated, pipe-delimited fields, first field is the ID)
REVIEW_FINDINGS=$(echo "$REVIEW_BODY" | grep -oP 'FINDINGS:\[\K[^\]]*' | tr ',' '\n' | sed 's/|.*//' | sort || echo "")

# Extract RESOLVED finding IDs from resolution comment
RESOLVED_FINDINGS=$(echo "$RESOLUTION_BODY" | grep -oP 'RESOLVED:\[\K[^\]]*' | tr ',' '\n' | sort || echo "")

# Check 1: ESCALATED must be empty
if [ -n "$ESCALATED" ]; then
  echo "FINDING_LEDGER_BLOCK: ESCALATED array is non-empty: [$ESCALATED]"
fi

# Check 2: Every finding in REVIEW_FINDINGS must have a matching RESOLVED entry
UNRESOLVED=$(comm -23 <(echo "$REVIEW_FINDINGS") <(echo "$RESOLVED_FINDINGS") | grep -v '^$' || true)
if [ -n "$UNRESOLVED" ]; then
  echo "FINDING_LEDGER_BLOCK: Unresolved findings: $UNRESOLVED"
fi
```

**If the finding-ledger check fails**, stop immediately and display:

```markdown
## BLOCKED: Unresolved Findings

PR #$ARGUMENTS cannot be merged — the finding ledger has unresolved items.

| Issue | Details |
|-------|---------|
| Non-empty ESCALATED | {list of escalated finding IDs, if any} |
| Unmatched FINDINGS | {list of finding IDs with no RESOLVED entry, if any} |

### Remediation

1. Run `/flow:address $ARGUMENTS` to resolve remaining findings
2. Ensure every finding in `FLOW_REVIEW_CYCLE:FINDINGS` has a matching `RESOLVED` entry in `FLOW_RESOLUTION_CYCLE`
3. Ensure `ESCALATED:[]` is empty (all escalated items must be resolved or have explicit human override)
4. Re-run `/flow:merge $ARGUMENTS`

This gate enforces the "no incomplete shipments" hard boundary.
```

Do NOT proceed to Phase 2. Exit here.

## Phase 2: Display Assessment

```markdown
## Merge Assessment for PR #$ARGUMENTS

| Check | Status | Details |
|-------|--------|---------|
| Approval | {Pass/Fail} | {N approvals, latest by @X} |
| CI Checks | {Pass/Fail} | {N passed, M failed} |
| Mergeable | {Pass/Fail} | {No conflicts / Has conflicts} |
| Conversations | {Pass/Fail} | {All resolved / N unresolved} |
| Stale Approval | {OK/Warning} | {Fresh / Commits after approval} |
| Finding Ledger | {Pass/Fail} | {All resolved / N unresolved, M escalated} |

**Merge strategy**: {from settings.merge.strategy, default: squash}
**Delete branch**: {from settings.merge.deleteBranch, default: true}
```

If any check fails, explain what needs to be fixed and suggest actions.

### Conflict Resolution Path

If the Mergeable check fails (has conflicts):

Use the AskUserQuestion tool: "PR #$ARGUMENTS has merge conflicts. Would you like to resolve them now?"
- Option 1: "Resolve conflicts now" — invokes Skill flow:resolve with $ARGUMENTS
- Option 2: "Cancel merge"

If Option 1: after resolution completes, re-run Phase 1 to verify PR is now mergeable.

## Phase 3: Confirm and Execute

Use the AskUserQuestion tool with contextual options to confirm: "PR #$ARGUMENTS is ready to merge. Proceed with squash merge and branch deletion?"

Only after the user confirms via the tool:

```bash
# Read merge settings
STRATEGY="squash"  # or from settings
DELETE_FLAG="--delete-branch"  # or from settings

gh pr merge $ARGUMENTS --$STRATEGY $DELETE_FLAG
```

## Phase 4: Post-Merge

```bash
# Verify merge
gh pr view $ARGUMENTS --json state --jq '.state'

# Switch to default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git checkout $DEFAULT_BRANCH
git pull origin $DEFAULT_BRANCH
```

Suggest: `/flow:release {type}` if this completes a milestone.
