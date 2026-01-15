# Start Work on Issue #$ARGUMENTS

Complete workflow from issue to PR creation.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive dialogues at key decision points. Use it to clarify requirements, confirm branch naming, and approve PR creation.

## Phase 1: Setup

1. **Fetch the issue**:
   ```bash
   gh issue view $ARGUMENTS
   ```

2. **Assign the issue to yourself**:
   ```bash
   gh issue edit $ARGUMENTS --add-assignee @me
   ```

3. **Detect default branch and ensure on latest**:
   ```bash
   # Get default branch dynamically
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
   ```

4. **Determine branch type** - If ambiguous, **use the AskUserQuestion tool**:

   When issue type is unclear (could be feature or fix), ask:
   - **Option 1**: "feature/issue-{number}-{desc}" - New functionality
   - **Option 2**: "fix/issue-{number}-{desc}" - Bug fix
   - **Option 3**: "docs/issue-{number}-{desc}" - Documentation only

   ```bash
   git checkout -b {branch-name}
   ```

5. **Confirm setup** with user before beginning implementation

## Phase 2: Implementation

- Work through the issue requirements systematically
- Follow project guidelines (check CLAUDE.md if present)
- Review formatting for consistency
- Make commits with conventional format as you work

## Phase 3: Finalize & Create PR

1. **Verify** all acceptance criteria in the issue are met

2. **Commit** with conventional format:
   - `feat:` for features
   - `fix:` for bug fixes
   - `docs:` for documentation
   - `refactor:` for refactoring
   - `chore:` for maintenance
   - `test:` for test changes

3. **Push**:
   ```bash
   git push -u origin {branch-name}
   ```

4. **Select labels using the AskUserQuestion tool**:
   ```bash
   # Fetch labels dynamically - never hardcode
   gh label list
   ```

   Present recommended labels and **use the AskUserQuestion tool** to confirm:
   - **Option 1**: "Apply suggested labels: [label1, label2]" (Recommended)
   - **Option 2**: "Let me choose different labels"
   - **Option 3**: "No labels needed"

5. **Preview PR and get approval using the AskUserQuestion tool**:

   Show the PR title, body preview, and target branch, then ask:
   - **Option 1**: "Create this PR" (Recommended)
   - **Option 2**: "Edit title or labels first"
   - **Option 3**: "Edit PR body first"
   - **Option 4**: "Cancel PR creation"

   **Do not create the PR without explicit approval.**

6. **Get default branch for PR target**:
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   ```

7. **Create PR**:
   ```bash
   gh pr create --base $DEFAULT_BRANCH --title "TYPE: description (fixes #ISSUE)" --body "..." --assignee @me --label "relevant-label"
   ```
   - Always assign to `@me`
   - Add relevant labels (can use `--label` multiple times)
   - Use `(fixes #X)` in title to auto-close the issue on merge (default)
   - Use `(#X)` instead if the issue should remain open (partial work)

## PR Template

Use this structure for the PR body:

```markdown
## Closes Issue

closes #{X}

## Summary
<!-- Brief description of what was changed and why (2-3 sentences) -->

[SUMMARY]

## Changes
<!-- List key changes made -->
- [Change 1]
- [Change 2]
- [Change 3]

## Verification
<!-- How the changes were verified -->

**Checks:**
- [x] Code/content reviewed
- [x] Links and references work
- [x] All acceptance criteria met

## Acceptance Criteria
<!-- Copy from issue and check off each item -->

**From issue:**
- [x] [Criterion 1]
- [x] [Criterion 2]
- [x] [Criterion 3]

## Files Changed
<!-- List key files modified with brief description -->

**Created:**
- [file1] - [description]

**Modified:**
- [file2] - [description]

**Deleted:**
- None (or list files)

## Breaking Changes
<!-- Yes/No - If yes, describe the impact -->

**Breaking**: No

## Screenshots/Examples
<!-- If applicable, add screenshots or example output -->

## Checklist
<!-- Final verification before requesting review -->
- [x] Commit messages follow conventional format
- [x] No uncommitted changes
- [x] All tests pass (if applicable)

## Reviewer Notes
<!-- Any special instructions for reviewers -->

**Review Focus:**
- [Key areas to review]
```

## Phase 4: Verification

After PR creation, verify it was created correctly:

1. **Fetch the PR** to confirm it exists:
   ```bash
   gh pr view {pr-number} --json number,title,body,labels,assignees
   ```

2. **Verify checklist**:
   - [ ] PR exists and is in OPEN state
   - [ ] PR targets correct default branch
   - [ ] Labels applied correctly
   - [ ] Issue linked in body (`closes #X`)
   - [ ] Assigned to creator

3. **If verification fails**, report specific issue and how to fix it

4. **Report success** with:
   - PR URL
   - PR number
   - Next steps (request review, wait for CI, etc.)

## Arguments

- `$ARGUMENTS`: Issue number (required)
- To override base branch: mention it in your message (e.g., "start 42, target release branch")

## Rules

- **Always detect default branch dynamically** - never assume `main` or `master`
- Use `(fixes #X)` in PR **title** to auto-close the issue on squash merge
- Use `(#X)` in title if issue should remain open after merge
- Commits must follow conventional format
- **Always fetch labels dynamically** - never hardcode label lists
- **Use the AskUserQuestion tool** at decision points:
  - Branch type selection (when ambiguous)
  - Label selection for PR
  - PR creation approval

## Success Criteria

Before completing, verify:
- [ ] Issue assigned to user
- [ ] Branch created from latest default branch
- [ ] All acceptance criteria from issue addressed
- [ ] PR created with correct target, labels, and assignee
- [ ] PR verified to exist via `gh pr view`
- [ ] User informed of PR URL and next steps
