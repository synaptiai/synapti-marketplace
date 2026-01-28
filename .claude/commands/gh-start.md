# Start Work on Issue #$ARGUMENTS

Complete workflow from issue assignment through implementation. Ends with option to create PR via `/gh-pr` or continue working.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive dialogues at key decision points.

## Phase 1: Setup

1. **Fetch the issue**:
   ```bash
   gh issue view $ARGUMENTS
   ```

2. **Fetch all issue comments for full context**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '.[] | "---\n**@\(.user.login)** on \(.created_at):\n\(.body)\n"'
   ```

3. **Assign the issue to yourself**:
   ```bash
   gh issue edit $ARGUMENTS --add-assignee @me
   ```

4. **Ensure on latest main**:
   ```bash
   git checkout main && git pull origin main
   ```

5. **Determine branch type** - If ambiguous, **use the AskUserQuestion tool**:

   When issue type is unclear (could be feature or fix), ask:
   - **Option 1**: "feature/issue-{number}-{desc}" - New functionality
   - **Option 2**: "fix/issue-{number}-{desc}" - Bug fix
   - **Option 3**: "docs/issue-{number}-{desc}" - Documentation only

   ```bash
   git checkout -b {branch-name}
   ```

6. **Confirm setup** with user before beginning implementation

## Phase 2: Implementation

- Work through the issue requirements systematically
- Follow CLAUDE.md guidelines for content patterns
- For plugin changes, ensure plugin.json and marketplace.json stay in sync
- Review Markdown formatting for consistency

## Phase 3: Quality Checks

1. **Verify** all acceptance criteria in the issue are met

2. **Run plugin validation** (if plugin files changed):
   ```bash
   ls plugins/*/  # Check plugin directories exist
   cat plugins/*/.claude-plugin/plugin.json  # Verify plugin.json valid
   ```

3. **Commit** with conventional format:
   - `feat:` for features
   - `fix:` for bug fixes
   - `docs:` for documentation
   - `refactor:` for refactoring
   - `chore:` for maintenance

## Phase 4: Ready for PR

**All quality checks passed.** Implementation is complete and ready for pull request.

1. **Display Summary**:
   ```
   ## Implementation Complete

   **Branch**: {branch-name}
   **Issue**: #{issue-number} - {issue-title}
   **Commits**: {N} commits ahead of main

   ### Files Changed
   - {file1} (created)
   - {file2} (modified)
   ```

2. **Use the AskUserQuestion tool** for next step:

   - **Option 1**: "Create PR now" (Recommended) - Run `/gh-pr` for full PR creation with reviewer suggestions
   - **Option 2**: "Defer to /gh-pr later" - End now, create PR manually later
   - **Option 3**: "Make more changes first" - Continue working, commit with `/gh-commit` when ready

### If Option 1 Selected

Inform user to run `/gh-pr` which will:
- Run full code review
- Check conventions
- Suggest reviewers
- Create PR with approval

### If Option 2 or 3 Selected

```
## Ready for PR

When you're ready, run:
- `/gh-commit` - Commit additional changes
- `/gh-pr` - Create PR with full review
```

## Arguments

- `$ARGUMENTS`: Issue number (required)
- To override base branch: mention it in your message (e.g., "start 42, target release branch instead of main")

## Rules

- Default branch is `main` for this repository
- Commits must follow conventional format
- Always verify plugin structure before finishing
- **Use the AskUserQuestion tool** at decision points:
  - Branch type selection (when ambiguous)
  - Next step selection (PR now / defer / continue)
- **Do not create PR directly** - offer choice to run `/gh-pr`

## Success Criteria

Before completing, verify:
- [ ] Issue assigned to user
- [ ] Branch created from latest `main`
- [ ] All acceptance criteria from issue addressed
- [ ] User presented with next step options

## Related Commands

- **`/gh-commit`**: Context-aware commits with change classification
- **`/gh-pr`**: Create PR with full review and reviewer suggestions
- **`/gh-review`**: Review a pull request
- **`/gh-address`**: Address PR review comments
