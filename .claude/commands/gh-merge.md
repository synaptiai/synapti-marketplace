# Merge PR #$ARGUMENTS

Merge an approved pull request with standardized settings.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to confirm merge options and get explicit approval before executing irreversible actions.

## Process

1. **Fetch PR details**:
   ```bash
   gh pr view $ARGUMENTS --json number,title,state,isDraft,headRefName,baseRefName,mergeable,reviewDecision,statusCheckRollup
   ```

2. **Verify prerequisites**:
   - PR state must be `OPEN`
   - PR must NOT be a draft (`isDraft: false`)
   - PR must be `MERGEABLE`
   - Review decision must be `APPROVED` (or no reviews required)
   - All status checks must pass

3. **If prerequisites not met**: Stop and report what's blocking the merge:
   - Draft PR → "PR is a draft. Mark as ready for review first."
   - Not approved → "PR requires approval before merging"
   - Checks failing → "CI checks are failing: [list failed checks]"
   - Merge conflicts → "PR has merge conflicts that need to be resolved"
   - Already merged/closed → "PR is already [merged/closed]"

4. **Get merge approval using the AskUserQuestion tool**:

   First, display the merge preview:
   ```
   **Merge Preview: PR #X**

   Title: {title}
   Branch: {headRefName} → main
   Strategy: Squash merge
   Branch deletion: Yes

   Linked issue: #{issue} (will auto-close)
   ```

   Then **invoke the AskUserQuestion tool** with these options:
   - **Option 1**: "Merge and delete branch" (Recommended)
   - **Option 2**: "Merge but keep branch"
   - **Option 3**: "Cancel - I need to make changes first"

   **Do not execute merge without explicit approval via the AskUserQuestion tool.**

5. **Execute merge** (based on user choice):
   ```bash
   gh pr merge $ARGUMENTS --squash --delete-branch
   ```

6. **Post-merge actions**:
   - Confirm successful merge
   - Report that branch was deleted
   - Suggest updating local branches if on the merged branch

7. **Update local branches** (if user was on the merged branch):
   ```bash
   git checkout main
   git pull origin main
   git branch -d {headRefName}  # Delete local branch if exists
   ```

## Prerequisite Checks

| Check | Requirement | Error Message |
|-------|-------------|---------------|
| State | `OPEN` | "PR #X is already {state}" |
| Draft | `isDraft: false` | "PR #X is a draft. Mark as ready for review first." |
| Mergeable | `MERGEABLE` | "PR #X has merge conflicts" |
| Review | `APPROVED` or no reviews | "PR #X requires approval" |
| Checks | All passing | "PR #X has failing checks: {list}" |

## Merge Settings

| PR Type | Strategy | Delete Branch | Reason |
|---------|----------|---------------|--------|
| Feature PR (feature/* → main) | `--squash` | Yes | Clean history, single commit per feature |
| Fix PR (fix/* → main) | `--squash` | Yes | Clean history, single commit per fix |
| Docs PR (docs/* → main) | `--squash` | Yes | Clean history, single commit per docs change |

## Output Format

### Success
```
## Merged PR #X

**Title:** {title}
**Branch:** {headRefName} → main
**Strategy:** Squash merge

Branch `{headRefName}` has been deleted.

### Next Steps
- Update local: `git checkout main && git pull`
- The linked issue should auto-close (if using `fixes #X`)
- For version bumps, run `/gh-release` to create a release
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

## Examples

```bash
# Merge PR #42
/gh-merge 42

# Output on success:
## Merged PR #42
**Title:** feat: add new analysis agent (fixes #38)
**Branch:** feature/issue-38-analysis-agent → main
**Strategy:** Squash merge

Branch `feature/issue-38-analysis-agent` has been deleted.
```

## Phase 8: Verification

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
- Use squash merge and delete source branch
- NEVER force merge (skip checks)
- Provide clear, actionable feedback on failures
- ALWAYS verify merge completed successfully
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
- [ ] User informed of next steps (update local, release if needed)
