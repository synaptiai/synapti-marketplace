---
description: Use after PR is approved to merge with safe defaults, verification checks, and optional branch cleanup
argument-hint: <pr-number>
allowed-tools: Bash, AskUserQuestion, Skill
---

# Merge PR #$ARGUMENTS

Merge an approved pull request with standardized settings.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to confirm merge options and get explicit approval before executing irreversible actions.

## Contract

**GOAL**: PR merged with all prerequisites verified and branch cleaned up. Testable: `gh pr view $ARGUMENTS --json state` shows `MERGED`.

**CONSTRAINTS**:
- Never force merge (skip checks)
- Never merge without verifying all prerequisites
- Always detect default branch dynamically
- Always get explicit user approval before executing merge

**FORMAT**: Merge preview shown first, then user approval, then execution with verification.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Merged without checking approval status
- Merged with failing CI checks
- Merged with unresolved conversation threads (without acknowledgment)
- Merge executed without explicit user approval via AskUserQuestion
- Stale approval not flagged (PR updated since last approval)
- Failed merge not detected or reported

## Process

0. **Read merge settings**:
   ```bash
   # Read merge.strategy (local > project > user > default)
   MERGE_STRATEGY=$(jq -r '.merge.strategy // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
   [ -z "$MERGE_STRATEGY" ] && MERGE_STRATEGY=$(jq -r '.merge.strategy // empty' .claude/settings.gh-workflow.json 2>/dev/null)
   [ -z "$MERGE_STRATEGY" ] && MERGE_STRATEGY=$(jq -r '.merge.strategy // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
   [ -z "$MERGE_STRATEGY" ] && MERGE_STRATEGY="squash"

   # Validate merge strategy (prevent command injection)
   case "$MERGE_STRATEGY" in squash|merge|rebase) ;; *) echo "ERROR: Invalid merge strategy: $MERGE_STRATEGY"; exit 1;; esac

   # Read merge.deleteBranch (boolean — use 'has' check to preserve false)
   DELETE_BRANCH=$(jq -r 'if .merge | has("deleteBranch") then .merge.deleteBranch else empty end' .claude/settings.gh-workflow.local.json 2>/dev/null)
   [ -z "$DELETE_BRANCH" ] && DELETE_BRANCH=$(jq -r 'if .merge | has("deleteBranch") then .merge.deleteBranch else empty end' .claude/settings.gh-workflow.json 2>/dev/null)
   [ -z "$DELETE_BRANCH" ] && DELETE_BRANCH=$(jq -r 'if .merge | has("deleteBranch") then .merge.deleteBranch else empty end' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
   [ -z "$DELETE_BRANCH" ] && DELETE_BRANCH="true"
   ```

1. **Fetch PR details**:
   ```bash
   gh pr view $ARGUMENTS --json number,title,state,isDraft,headRefName,baseRefName,mergeable,reviewDecision,statusCheckRollup
   ```

2. **Check for unresolved conversations**:
   ```bash
   # Get owner/repo dynamically
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   # Get review threads with pending status
   gh api repos/$REPO/pulls/$ARGUMENTS/comments --jq '[.[] | select(.in_reply_to_id == null)] | length'
   ```

   **If unresolved threads exist**, warn user before proceeding.

3. **Check for stale approval** (commits since last approval):
   ```bash
   # Check if PR was updated after last approval
   gh pr view $ARGUMENTS --json reviews,commits --jq '{last_approval: [.reviews[] | select(.state == "APPROVED")] | last | .submittedAt, last_commit: .commits | last | .committedDate}'
   ```

   **If PR was updated since approval**, warn: "PR #X has been updated since last approval - may need re-review"

4. **Verify prerequisites**:
   - PR state must be `OPEN`
   - PR must NOT be a draft (`isDraft: false`)
   - PR must be `MERGEABLE`
   - Review decision must be `APPROVED` (or no reviews required)
   - All status checks must pass
   - All conversation threads resolved (or acknowledged)

5. **If prerequisites not met**: Stop and report what's blocking the merge:
   - Draft PR → "PR is a draft. Mark as ready for review first."
   - Not approved → "PR requires approval before merging"
   - Checks failing → "CI checks are failing: [list failed checks]"
   - Merge conflicts → invoke conflict resolution path (see below)
   - Already merged/closed → "PR is already [merged/closed]"
   - Unresolved threads → "PR #X has N unresolved conversation threads"
   - Stale approval → "PR #X has been updated since last approval - may need re-review"

### Conflict Resolution Path

If the Mergeable check fails (PR has merge conflicts):

Use the **AskUserQuestion tool**: "PR #$ARGUMENTS has merge conflicts. Would you like to resolve them now?"

- **Option 1**: "Resolve conflicts now" — suggest the user run `/gh-resolve $ARGUMENTS` to resolve conflicts
- **Option 2**: "Cancel merge — I'll resolve conflicts manually"

If Option 1: after the user runs `/gh-resolve` and resolution completes, re-run Step 1 to verify PR is now mergeable, then continue from Step 4.

6. **Knowledge Checkpoint** (before merge approval):

   **Check configuration** — read `.commands.ghMergeKnowledgeCheckpoint` from settings. Default: `true`. If `false`, skip to Step 7.

   Extract the Comprehension Report from the PR body:
   ```bash
   gh pr view $ARGUMENTS --json body --jq '.body'
   ```

   Parse the Requirements Adherence table. If any criteria have status **"Interpreted"** or **"Partially Met"**, present a knowledge checkpoint using the **AskUserQuestion tool**:

   ```markdown
   ### Knowledge Checkpoint
   - Decision journal: {N} entries ({M} gates triggered, {K} bypassed)
   - Requirements: {X}/{Y} fully met, {Z} interpreted
   - Interpreted criteria: {list — these reflect AI's interpretation, not explicit requirements}
   - Partially met criteria: {list — these have gaps}
   - Comprehension report: {present / absent / stale}
   ```

   **Options:**
   - **Option 1**: "Merge — acceptable knowledge coverage" (Recommended)
   - **Option 2**: "I want to understand the interpreted criteria first" (display details)
   - **Option 3**: "Cancel — request clarification on partial criteria"

   If Option 2: show the interpreted/partial criteria details from the comprehension report, then re-present the merge options.

   If no Comprehension Report found in PR body, skip this step with note: "No comprehension report in PR body — skipping knowledge checkpoint."

7. **Get merge approval using the AskUserQuestion tool**:

   First, display the merge preview:
   ```
   **Merge Preview: PR #X**

   Title: {title}
   Branch: {headRefName} → {baseRefName}
   Strategy: {MERGE_STRATEGY} merge
   Branch deletion: {DELETE_BRANCH}

   Linked issue: #{issue} (will auto-close if using "fixes #X")
   ```

   Then **invoke the AskUserQuestion tool** with these options:
   - **Option 1**: "Merge with {MERGE_STRATEGY} strategy" (Recommended) — includes branch deletion if `DELETE_BRANCH` is `true`
   - **Option 2**: "Merge but change strategy or keep branch" — present sub-options:
     - Strategy: squash / merge / rebase
     - Branch: delete / keep
   - **Option 3**: "Cancel - I need to make changes first"

   **Do not execute merge without explicit approval via the AskUserQuestion tool.**

8. **Execute merge** (based on user choice):
   ```bash
   # Build merge flags from settings
   MERGE_FLAGS="--$MERGE_STRATEGY"
   [ "$DELETE_BRANCH" = "true" ] && MERGE_FLAGS="$MERGE_FLAGS --delete-branch"
   gh pr merge $ARGUMENTS $MERGE_FLAGS
   ```

9. **Post-merge actions**:
   - Confirm successful merge
   - Report that branch was deleted
   - Suggest updating local branches if on the merged branch

10. **Update local branches** (if user was on the merged branch):
   ```bash
   # Get default branch dynamically
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH
   git pull origin $DEFAULT_BRANCH
   git branch -d {headRefName}  # Delete local branch if exists
   ```

## Prerequisite Checks

| Check | Requirement | Error Message |
|-------|-------------|---------------|
| State | `OPEN` | "PR #X is already {state}" |
| Draft | `isDraft: false` | "PR #X is a draft. Mark as ready for review first." |
| Mergeable | `MERGEABLE` | "PR #X has merge conflicts — offering resolution" |
| Review | `APPROVED` or no reviews | "PR #X requires approval" |
| Checks | All passing | "PR #X has failing checks: {list}" |
| Threads | All resolved (or acknowledged) | "PR #X has N unresolved conversation threads" |
| Stale approval | Not updated since approval | "PR #X has been updated since last approval - may need re-review" |

## Merge Settings

Configurable via `.merge.strategy` and `.merge.deleteBranch` in `settings.gh-workflow.json`.

| Strategy | Delete Branch | When to Use |
|----------|---------------|-------------|
| `--squash` (default) | Configurable (default: yes) | Clean history, single commit per feature/fix |
| `--merge` | Configurable | Preserve full commit history |
| `--rebase` | Configurable | Linear history without merge commits |

Default: Squash merge with branch deletion for clean history. Override in settings for team preference.

## Output Format

### Success
```
## Merged PR #X

**Title:** {title}
**Branch:** {headRefName} → {baseRefName}
**Strategy:** {MERGE_STRATEGY} merge

Branch `{headRefName}` has been deleted.

### Next Steps
- Update local: `git checkout {default-branch} && git pull`
- The linked issue should auto-close (if using `fixes #X`)
```

### Failure
```
## Cannot Merge PR #X

**Reason:** {specific reason}

### How to Fix
{actionable steps to resolve the blocker}
```

## Special Cases

### PRs Without Required Reviews

If the repository doesn't require reviews:
- `reviewDecision` may be `null`
- Proceed with merge if other checks pass
- Warn user: "Note: This PR has no reviews"

### Draft PRs

Draft PRs cannot be merged:
- Check `isDraft` field
- Error: "PR #X is a draft. Mark as ready for review first."

## Arguments

- `$ARGUMENTS`: PR number (required)

## Phase 5: Verification

After merge execution, verify it completed successfully:

1. **Check PR state**:
   ```bash
   gh pr view $ARGUMENTS --json state,mergedAt,mergeCommit
   ```

2. **Verify checklist**:
   - [ ] PR state is `MERGED`
   - [ ] `mergedAt` timestamp exists
   - [ ] `mergeCommit` SHA exists
   - [ ] Remote branch deleted (if requested)

3. **Check linked issue** (if applicable):
   ```bash
   gh issue view {linked-issue} --json state
   ```
   - [ ] Issue state is `CLOSED` (if using `fixes #X`)

4. **If verification fails**, report specific issue:
   - Merge appeared to succeed but PR still open → Check GitHub status
   - Issue not closed → May need manual close or check link syntax

## Rules

- ALWAYS verify prerequisites before merging
- Use configured merge strategy and branch deletion preference (defaults: squash, delete branch)
- NEVER force merge (skip checks)
- Provide clear, actionable feedback on failures
- ALWAYS verify merge completed successfully
- **Always detect default branch dynamically** - never assume `main` or `master`
- **Use the AskUserQuestion tool** for:
  - Merge approval (required before executing)
  - Branch deletion preference
  - Any blockers that need user decision

## Success Criteria

Before completing, verify:
- [ ] All prerequisites checked before merge attempt
- [ ] User explicitly approved the merge
- [ ] Merge executed with correct strategy
- [ ] PR state confirmed as MERGED via `gh pr view`
- [ ] Linked issue closed (if applicable)
- [ ] User informed of next steps (update local, etc.)
