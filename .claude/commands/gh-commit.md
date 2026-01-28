# Context-Aware Commit

Smart commit workflow that classifies changes, flags out-of-context modifications, and supports multiple atomic commits.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive decisions about change inclusion.

## Phase 1: Context Discovery

1. **Get current branch and linked issue**:
   ```bash
   BRANCH=$(git branch --show-current)
   ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
   ```

2. **Fetch linked issue details** (if found):
   ```bash
   gh issue view $ISSUE_NUM --json title,body,labels 2>/dev/null
   ```

3. **Get branch diff summary**:
   ```bash
   git diff --name-only main...HEAD
   ```

## Phase 2: Change Analysis

1. **Get all changes**:
   ```bash
   git status --porcelain
   ```

2. **Classify each change**:

   **In-Context** (confident):
   - Files already in branch diff
   - Files matching issue keywords
   - Same directory as other changes

   **Uncertain** (needs review):
   - Related directories but not in diff
   - Documentation files

   **Out-of-Context** (flagged):
   - Config files (`.env`, editor settings)
   - Unrelated feature directories
   - Auto-generated files

3. **Display classification**:
   ```
   ## Change Classification

   **Context**: Branch `{branch}`, Issue #{issue}: "{title}"

   ### In-Context
   - src/api/users.ts (matches issue keywords)

   ### Uncertain
   - docs/api.md (documentation)

   ### Out-of-Context
   - .vscode/settings.json (editor config)
   ```

## Phase 3: Interactive Planning

**Use the AskUserQuestion tool** if uncertain or out-of-context files exist:

- **Option 1**: "Commit in-context files only" (Recommended)
- **Option 2**: "Include uncertain files"
- **Option 3**: "Select specific files"
- **Option 4**: "Commit all files"

## Phase 4: Commit

1. **Stage selected files**:
   ```bash
   git add {selected_files}
   ```

2. **Generate commit message** following conventional format:
   - `feat:` for features
   - `fix:` for bug fixes
   - `docs:` for documentation
   - `test:` for test changes
   - `refactor:` for refactoring
   - `chore:` for maintenance

3. **Preview and confirm** with AskUserQuestion:
   - **Option 1**: "Use this message" (Recommended)
   - **Option 2**: "Edit message"

4. **Commit**:
   ```bash
   git commit -m "{message}"
   ```

## Phase 5: Summary

```
## Commit Summary

**Committed**: {N} files in commit {hash}
**Message**: {commit message}

### Skipped (Out-of-Context)
- .vscode/settings.json (editor config)

### Next Steps
- `/gh-commit` - Commit more changes
- `/gh-pr` - Create pull request
```

## Arguments

- `$ARGUMENTS`: Optional commit message
  - If provided, uses as message (skips generation)
  - Example: `/gh-commit feat: add validation`

## Rules

- Never commit secrets (`.env`, credentials)
- Warn about large files (> 1MB)
- Always show classification before decisions
- Follow conventional commit format

## Related Commands

- **`/gh-start`**: Start work on an issue
- **`/gh-pr`**: Create PR with full review
