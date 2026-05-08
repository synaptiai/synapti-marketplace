---
description: "Merge an approved pull request. Verifies prerequisites (approval, checks, conversations), displays assessment, and requires explicit human confirmation. Tier 3 — never autonomous."
argument-hint: <pr-number>
allowed-tools: Bash, Read, AskUserQuestion, Skill
---

# Merge PR #$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. This is non-negotiable even in autonomous mode.

## Required Skills

- `merge-and-release` — prerequisite verification, merge execution

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 2's conflict-resolution escalation and Phase 3's merge-confirm prompt

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

Parse the latest `FLOW_RESOLUTION_CYCLE` and `FLOW_REVIEW_CYCLE` comments to verify all findings are resolved before merge. Marker schemas and the canonical extraction queries are documented in [`references/finding-ledger-parser.md`](../references/finding-ledger-parser.md); this command applies the merge-blocking subset (ESCALATED non-empty, FINDINGS without matching RESOLVED).

```bash
# Extract the latest FLOW_RESOLUTION_CYCLE comment (issue/PR conversation).
# Capture gh exit code: a silent gh failure (auth, network) must fail the gate
# CLOSED, not pass it open.
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# MARKERTRUST_GATE_BEGIN
# Resolve trust list from the standard Claude Code settings cascade.
# Precedence (highest first — first valid value wins):
#   1. .claude/settings.flow.local.json — project-local; gitignored
#   2. .claude/settings.flow.json — project-shared; committed (visible in PR review)
#   3. $HOME/.claude/settings.flow.json — user-global default
#   4. ${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json — plugin default
# Reviewers of a fork PR will see any change to .claude/settings.flow.json in
# the diff like any other repo file; defense moves from "plugin refuses to
# read" to "maintainer review notices the change."
TRUST_DEFAULT='["OWNER","MEMBER","COLLABORATOR"]'
TRUST_LIST="$TRUST_DEFAULT"
LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"
for SETTINGS_PATH in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS_PATH" ] || continue
  # Capture jq stderr/exit so a parse error in $HOME does not silently mask
  # a typo as "fall through to plugin default" — same pattern as the
  # agentTeams gate in commands/review.md.
  CONFIGURED=$(jq -c '.merge.markerTrust.allowedAssociations // empty' "$SETTINGS_PATH" 2>&1)
  JQ_EXIT=$?
  if [ $JQ_EXIT -ne 0 ]; then
    JQ_ERR=$(printf '%s' "$CONFIGURED" | tr '\n' ' ' | cut -c1-200)
    echo "WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
    continue
  fi
  [ -z "$CONFIGURED" ] && continue
  if echo "$CONFIGURED" | jq -e '. | type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null 2>&1; then
    TRUST_LIST="$CONFIGURED"
    break
  else
    # Fall through to next source. Emit on stderr (NOT stdout) so the
    # downstream "If the finding-ledger check fails" gate that scans stdout
    # for FINDING_LEDGER_BLOCK does not treat this as a block — a typo at
    # one tier should not block merge when a lower tier resolves correctly.
    # If no tier resolves, TRUST_LIST stays at TRUST_DEFAULT (initialized
    # above), which is the safe minimum trust list.
    echo "LEDGER_WARN: invalid markerTrust configuration in $SETTINGS_PATH (must be non-empty JSON array of strings); falling through" >&2
  fi
done
# MARKERTRUST_GATE_END

# Trust filter applied via jq's `index()` exact-match (no regex surface).
# `--paginate` keeps fetching pages so a noisy thread can't hide forgeries.
RESOLUTION_BODY=$(gh api --paginate "repos/$REPO/issues/$ARGUMENTS/comments" 2>/dev/null \
  | jq -s -r --argjson trust "$TRUST_LIST" \
      'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | last | .body // ""')
GH_EXIT_RES=$?
RES_UNTRUSTED=$(gh api --paginate "repos/$REPO/issues/$ARGUMENTS/comments" 2>/dev/null \
  | jq -s -r --argjson trust "$TRUST_LIST" \
      'add | [.[] | select((.author_association as $a | $trust | index($a) | not) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | length')

# Extract ESCALATED array contents (portable POSIX grep+sed; BSD grep has no -P).
# Strip whitespace so reviewer-edited arrays like `[F1, F2]` still match.
ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')

# Extract the latest FLOW_REVIEW_CYCLE — emitted in PR review bodies, not issue comments
REVIEW_BODY=$(gh api --paginate "repos/$REPO/pulls/$ARGUMENTS/reviews" 2>/dev/null \
  | jq -s -r --argjson trust "$TRUST_LIST" \
      'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_REVIEW_CYCLE:")))] | last | .body // ""')
GH_EXIT_REV=$?
REV_UNTRUSTED=$(gh api --paginate "repos/$REPO/pulls/$ARGUMENTS/reviews" 2>/dev/null \
  | jq -s -r --argjson trust "$TRUST_LIST" \
      'add | [.[] | select((.author_association as $a | $trust | index($a) | not) and (.body | test("FLOW_REVIEW_CYCLE:")))] | length')

# Fail closed if either gh call failed — better to block a legitimate merge
# than silently let a regression through when the gate state is unknowable.
if [ $GH_EXIT_RES -ne 0 ] || [ $GH_EXIT_REV -ne 0 ]; then
  echo "FINDING_LEDGER_BLOCK: gh API unavailable — cannot verify finding ledger (resolution exit=$GH_EXIT_RES, review exit=$GH_EXIT_REV)"
fi

# Surface "untrusted-only" markers as a block reason rather than silently
# treating them as no markers at all. This is the #92 forgery defense.
# Render the trust list as a comma-separated string for the user-facing
# message — the `$TRUST_REGEX` variable used to appear here was a leftover
# from PR #93 and never assigned, producing the empty-parens string
# "trusted authors ()" in messages or aborting under `set -u`.
TRUST_LIST_DISPLAY=$(echo "$TRUST_LIST" | jq -r 'join(",")' 2>/dev/null || echo "OWNER,MEMBER,COLLABORATOR")
if [ -z "$RESOLUTION_BODY" ] && [ "${RES_UNTRUSTED:-0}" != "0" ]; then
  echo "FINDING_LEDGER_BLOCK: $RES_UNTRUSTED FLOW_RESOLUTION_CYCLE marker(s) found but none from trusted authors ($TRUST_LIST_DISPLAY)"
fi
if [ -z "$REVIEW_BODY" ] && [ "${REV_UNTRUSTED:-0}" != "0" ]; then
  echo "FINDING_LEDGER_BLOCK: $REV_UNTRUSTED FLOW_REVIEW_CYCLE marker(s) found but none from trusted authors ($TRUST_LIST_DISPLAY)"
fi

# Extract all finding IDs from FINDINGS array (comma-separated, pipe-delimited fields, first field is the ID)
REVIEW_FINDINGS=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' | tr ',' '\n' | sed 's/|.*//' | tr -d ' ' | sort)

# Extract RESOLVED finding IDs from resolution comment
RESOLVED_FINDINGS=$(echo "$RESOLUTION_BODY" | grep -o 'RESOLVED:\[[^]]*\]' | sed 's/^RESOLVED:\[//;s/\]$//' | tr ',' '\n' | tr -d ' ' | sort)

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
| gh API unavailable | {if either GH_EXIT_RES or GH_EXIT_REV is non-zero, list both exit codes; else "N/A"} |
| Untrusted markers only | {if RES_UNTRUSTED or REV_UNTRUSTED is non-zero AND no trusted markers found, list counts} |
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

Use the AskUserQuestion tool with a Proactive-Autonomy escalation:

> **Situation** — PR #$ARGUMENTS has merge conflicts that prevent merging.
>
> **What I tried** — Checked mergeable status via `gh pr view`. Conflicts exist between the PR branch and the base branch.
>
> **Options**:
> 1. Resolve conflicts now — invokes `Skill(flow:resolve)` with $ARGUMENTS (Recommended)
> 2. Cancel merge — address conflicts manually or rebase first
>
> **Recommendation** — Option 1. Automated conflict resolution handles most cases and re-verifies after resolution.
>
> **Time sensitivity** — Blocks merge. Must resolve before proceeding.
>
> **Risk** — Option 1 may produce incorrect resolution for semantic conflicts (caught by post-resolution verification). Option 2 delays merge.

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

**Manifest emit** — if this merge resolved any escalations (a Proactive-Autonomy escalation surfaced via `AskUserQuestion` during Phase 1's finding-ledger check, Phase 2's stale-approval warning, or the conflict-resolution path closed because the user provided one of the six canonical fields), record an `escalation-resolved` artifact for each:

```bash
ISSUE=$(gh pr view $ARGUMENTS --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#')
if [ -n "$ISSUE" ]; then
  # Repeat once per escalation that closed during this merge run.
  "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
    --issue $ISSUE \
    --type escalation-resolved \
    --metadata escalation_field={situation|tried|options|recommendation|time-sensitivity|risk} \
    --metadata outcome="$USER_RESPONSE_SUMMARY"
fi
```

The emit is conditional — most merges run cleanly without escalations, in which case skip this step. When it does fire, the manifest captures both *that* an escalation closed and *which canonical field* was the gate, enabling `/flow:learn` to detect recurring escalation patterns (e.g., the same field gating multiple merges → process or tooling improvement opportunity).

Suggest: `/flow:release {type}` if this completes a milestone.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read PR status / reviews / comments / threads | 1 | Autonomous |
| Finding-ledger gate check (parses `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE`) | 1 | Autonomous; blocks on failure |
| Stale-approval check | 1 | Autonomous; warns on stale |
| Conflict-resolution escalation (`Skill(flow:resolve)` invocation) | 2 | Journal-and-proceed if user accepts; otherwise blocked |
| `gh pr merge` | 3 | **Confirm** — always asks via `AskUserQuestion` |
| Branch deletion (per `merge.deleteBranch` setting, default `true`) | 3 | **Confirm** — bundled into the merge prompt |
| `git checkout <default-branch> && git pull` (post-merge cleanup) | 1 | Autonomous |
