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

3. **Ensure on latest main**:
   ```bash
   git checkout main && git pull origin main
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
- Follow CLAUDE.md guidelines for content patterns
- For plugin changes, ensure plugin.json and marketplace.json stay in sync
- Review Markdown formatting for consistency

## Phase 3: Finalize & Create PR

1. **Verify** all acceptance criteria in the issue are met

2. **Run plugin validation** (if plugin files changed):
   ```bash
   # Verify plugin structure
   ls plugins/*/  # Check plugin directories exist
   cat plugins/*/.claude-plugin/plugin.json  # Verify plugin.json valid
   ```

3. **Commit** with conventional format:
   - `feat:` for features
   - `fix:` for bug fixes
   - `docs:` for documentation
   - `refactor:` for refactoring
   - `chore:` for maintenance

4. **Push**:
   ```bash
   git push -u origin {branch-name}
   ```

5. **Select labels using the AskUserQuestion tool**:
   ```bash
   gh label list
   ```

   Present recommended labels and **use the AskUserQuestion tool** to confirm:
   - **Option 1**: "Apply suggested labels: [label1, label2]" (Recommended)
   - **Option 2**: "Let me choose different labels"
   - **Option 3**: "No labels needed"

6. **Preview PR and get approval using the AskUserQuestion tool**:

   Show the PR title, body preview, and target branch, then ask:
   - **Option 1**: "Create this PR" (Recommended)
   - **Option 2**: "Edit title or labels first"
   - **Option 3**: "Edit PR body first"
   - **Option 4**: "Cancel PR creation"

   **Do not create the PR without explicit approval.**

7. **Create PR** (target: `main`):
   ```bash
   gh pr create --base main --title "TYPE: description (fixes #ISSUE)" --body "..." --assignee @me --label "relevant-label"
   ```
   - Always assign to `@me`
   - Add relevant labels from the available list (can use `--label` multiple times)
   - Use `(fixes #X)` in title to auto-close the issue on merge (default)
   - Use `(#X)` instead if the issue should remain open (partial work, related but not completing)

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
- [x] Markdown files render correctly
- [x] Plugin structure valid (if applicable)
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

## Plugin Updates
<!-- If plugin files changed -->

**Plugin**: [plugin-name] (or "N/A")
**Version**: [version] (or "unchanged")

## Breaking Changes
<!-- Yes/No - If yes, describe the impact -->

**Breaking**: No

## Screenshots/Examples
<!-- If applicable, add screenshots or example output -->

## Checklist
<!-- Final verification before requesting review -->
- [x] Commit messages follow conventional format
- [x] Content follows CLAUDE.md guidelines
- [x] No uncommitted changes
- [x] Plugin.json and marketplace.json in sync (if applicable)

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
   - [ ] PR targets `main` branch
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
- To override base branch: mention it in your message (e.g., "start 42, target release branch instead of main")

## Rules

- Default PR target is `main`
- Use `(fixes #X)` in PR **title** to auto-close the issue on squash merge
- Use `(#X)` in title if issue should remain open after merge
- Commits must follow conventional format
- Always verify plugin structure before creating PR
- **Use the AskUserQuestion tool** at decision points:
  - Branch type selection (when ambiguous)
  - Label selection for PR
  - PR creation approval

## Success Criteria

Before completing, verify:
- [ ] Issue assigned to user
- [ ] Branch created from latest `main`
- [ ] All acceptance criteria from issue addressed
- [ ] PR created with correct target, labels, and assignee
- [ ] PR verified to exist via `gh pr view`
- [ ] User informed of PR URL and next steps
