---
name: merge-and-release
description: "Guide PR merges and releases through prerequisite verification (approval, checks, resolved conversations), semantic versioning, changelog generation, and release notes. Tier 3 — always requires human confirmation. Use when merging PRs or creating releases."
allowed-tools: Bash, Read
context: fork
agent: Explore
disable-model-invocation: true
---

# Merge and Release

Domain skill for merge and release operations. Both are Tier 3 — **always require human confirmation**, even in autonomous mode. This is non-negotiable.

## Iron Law

**MERGE IS IRREVERSIBLE IN PRACTICE. Treat every merge as permanent. Every prerequisite must be verified with fresh evidence, not memory.**

Reverting a merge is possible in git but disruptive in practice. Prevention is the only reliable strategy.

## Merge Prerequisites

Before merging, verify ALL of these:

```bash
PR_NUM=$ARGUMENTS
# All checks in parallel
gh pr view $PR_NUM --json reviewDecision,statusCheckRollup,mergeable,mergeStateStatus

# Review status
gh pr view $PR_NUM --json reviews --jq '.reviews[] | "\(.state) by \(.author.login)"'

# Unresolved conversations (reviewThreads requires GraphQL API)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo $REPO | cut -d/ -f1)
NAME=$(echo $REPO | cut -d/ -f2)
gh api graphql -f query="query { repository(owner: \"$OWNER\", name: \"$NAME\") { pullRequest(number: $PR_NUM) { reviewThreads(first: 100) { nodes { isResolved } } } } }" --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
```

### Prerequisite Checklist

| Check | Requirement | Detection |
|-------|-------------|-----------|
| Approval | At least 1 approval, no outstanding request-changes | `reviewDecision == "APPROVED"` |
| CI Checks | All status checks pass | `statusCheckRollup` all success |
| Mergeable | No merge conflicts | `mergeable == "MERGEABLE"` |
| Conversations | All review threads resolved | Unresolved count == 0 |
| Stale approval | No commits after last approval | Compare approval date vs last commit |

### Merge Stop Conditions

- ANY prerequisite fails — stop, do not ask "merge anyway?"
- Stale approval detected — stop, request re-review
- Unresolved conversations > 0 — stop, resolve first

### Stale Approval Detection

```bash
# Last approval timestamp
gh pr view $PR_NUM --json reviews --jq '[.reviews[] | select(.state == "APPROVED")] | sort_by(.submittedAt) | last | .submittedAt'

# Last commit timestamp
gh pr view $PR_NUM --json commits --jq '.commits | last | .committedDate'
```

If commits exist after the last approval, warn: "Approval may be stale."

## Merge Execution

After prerequisites pass, display assessment and **require confirmation**:

```markdown
## Merge Assessment for PR #N

- Approvals: {N} (latest: @{reviewer})
- CI Checks: {all pass / N failing}
- Conversations: {all resolved / N unresolved}
- Stale approval: {no / yes — warn}

**Strategy**: {squash | merge | rebase} (from settings)
**Delete branch**: {yes | no} (from settings)
```

Then ask user to confirm. Only after explicit "yes":

```bash
gh pr merge $PR_NUM --{strategy} --delete-branch
```

## Release Process

### Changelog Generation

```bash
# Get merged PRs since last release
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
[ -n "$LAST_TAG" ] && gh pr list --state merged --search "merged:>=$(git log -1 --format=%ai $LAST_TAG)" --json number,title,labels --limit 50
```

### Version Calculation

| Type | Bump | When |
|------|------|------|
| patch | 0.0.X | Bug fixes only |
| minor | 0.X.0 | New features, no breaking changes |
| major | X.0.0 | Breaking changes |

### Release Execution

Display changelog and version, **require confirmation**, then:

```bash
TAG="${TAG_PREFIX}${VERSION}"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"
gh release create "$TAG" --title "$TAG" --notes "$CHANGELOG"
```

## Post-Merge/Release

```bash
# Verify
gh pr view $PR_NUM --json state  # should be MERGED
# or
gh release view $TAG
```

Suggest cleanup: switch to default branch, pull latest.
