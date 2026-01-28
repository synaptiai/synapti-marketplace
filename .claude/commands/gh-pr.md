# Create Pull Request

Create a pull request with full code review, quality gates, and reviewer suggestions.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive decisions.

## Phase 1: Pre-flight

1. **Verify current branch**:
   ```bash
   BRANCH=$(git branch --show-current)
   # Ensure not on main
   ```

2. **Check for uncommitted changes**:
   ```bash
   git status --porcelain
   ```
   If changes exist, **use AskUserQuestion**:
   - **Option 1**: "Run /gh-commit first" (Recommended)
   - **Option 2**: "Continue without committing"

3. **Extract issue from branch**:
   ```bash
   ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
   gh issue view $ISSUE_NUM --json title,body
   ```

## Phase 2: Code Review

Run systematic code review on the diff:

```bash
git diff main..HEAD
```

**Review Checklist**:
- Logic correctness and edge cases
- Security (no hardcoded secrets)
- No TODO/FIXME comments
- No debug statements (console.log)
- Type safety

**Categorize findings**:
- **P1 (Critical)**: Blocks PR
- **P2 (Important)**: Should fix
- **P3 (Suggestions)**: Nice to have

If P1 issues found, **use AskUserQuestion**:
- **Option 1**: "Fix issues now" (Recommended)
- **Option 2**: "Proceed anyway"

## Phase 3: Quality Checks

```bash
# Run plugin validation
ls plugins/*/.claude-plugin/plugin.json
cat plugins/*/.claude-plugin/plugin.json
```

## Phase 4: Reviewer Suggestion

1. **Get collaborators**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
   gh api repos/$REPO/collaborators --jq '.[] | select(.permissions.push) | .login'
   ```

2. **Get file contributors**:
   ```bash
   CHANGED_FILES=$(git diff --name-only main..HEAD)
   git log --format='%an' --since="30 days ago" -- $CHANGED_FILES | sort | uniq -c | sort -rn
   ```

3. **Present suggestions** with AskUserQuestion:
   - **Option 1**: "@{top_contributor}" (Recommended)
   - **Option 2**: "@{other_contributor}"
   - **Option 3**: "No reviewer"

## Phase 5: Push & Create PR

1. **Push**:
   ```bash
   git push -u origin $BRANCH
   ```

2. **Select labels** with AskUserQuestion:
   ```bash
   gh label list
   ```
   - **Option 1**: "Apply suggested: {labels}" (Recommended)
   - **Option 2**: "Choose different labels"

3. **Preview PR** and get approval:
   ```
   ## PR Preview

   **Title**: feat: description (fixes #{issue})
   **Target**: {branch} → main
   **Reviewer**: @{selected}
   **Labels**: {labels}

   ---
   [PR body]
   ---
   ```

   **Use AskUserQuestion**:
   - **Option 1**: "Create this PR" (Recommended)
   - **Option 2**: "Edit title"
   - **Option 3**: "Edit body"
   - **Option 4**: "Cancel"

4. **Create PR**:
   ```bash
   gh pr create --base main --title "{title}" --body "{body}" --assignee @me --reviewer "{reviewer}" --label "{labels}"
   ```

## Phase 6: Verification

```bash
gh pr view --json number,title,url
```

```
## PR Created

**PR**: #{number}
**URL**: {url}

### Next Steps
1. Wait for review
2. Address comments with `/gh-address {pr}`
3. Merge with `/gh-merge {pr}`
```

## Arguments

- `$ARGUMENTS`: Optional PR title
  - Example: `/gh-pr feat: add new validation`

## Rules

- Full code review is mandatory
- Always preview before creating
- Show findings before asking decisions
- Never force push to main

## Related Commands

- **`/gh-start`**: Start work on an issue
- **`/gh-commit`**: Commit changes
- **`/gh-review`**: Review a PR
- **`/gh-address`**: Address review comments
