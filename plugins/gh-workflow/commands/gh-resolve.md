---
description: Use to resolve merge conflicts on the current branch or for a pull request — detects conflict types, analyzes both sides, applies per-file resolution strategies, and verifies the result
argument-hint: [pr-number-or-branch]
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.

VARIABLE PERSISTENCE NOTE:
Bash variables (like REPO, PR_NUM) do NOT persist across separate tool calls.
Each Bash invocation is an independent process. Store values mentally from output and
substitute them in subsequent commands. When running parallel Bash calls, each must
define any variables it needs inline.
-->

# Resolve Merge Conflicts $ARGUMENTS

Detect, classify, and resolve merge conflicts with per-file strategy selection and full verification.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for conflict resolution decisions (delete-modify, competing changes, strategy overrides), **TaskCreate/TaskUpdate** tools to track per-file resolution progress, and the **Skill tool** for capability discovery.

## Contract

**GOAL**: All merge conflicts resolved with no orphaned markers, quality checks passing, and merge/rebase completed. Testable: `grep -rn '^<<<<<<<\|^=======\|^>>>>>>>' . 2>/dev/null | grep -v '.git/' | grep -v 'node_modules/'` returns zero results AND `git status --porcelain | grep '^[UAD][UAD]'` returns zero results.

**CONSTRAINTS**:
- Never silently drop changes from either side of a conflict
- Always analyze both sides before choosing a resolution strategy
- Never auto-resolve delete-modify conflicts — require user decision
- Run quality checks after resolution to verify nothing broke

**FORMAT**: Conflict analysis table shown first, then per-file resolution with task tracking, then verification summary.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Changes from either side silently dropped without rationale
- Orphaned conflict markers remain in any file
- Delete-modify conflict resolved without user decision via AskUserQuestion
- Quality checks not run after resolution
- Merge/rebase not completed after resolving all files

## Process

### 0. Read conflict resolution settings

```bash
# Read conflictResolution.autoResolveTrivial (local > project > user > default)
AUTO_RESOLVE=$(jq -r '.conflictResolution.autoResolveTrivial // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$AUTO_RESOLVE" ] && AUTO_RESOLVE=$(jq -r '.conflictResolution.autoResolveTrivial // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$AUTO_RESOLVE" ] && AUTO_RESOLVE=$(jq -r '.conflictResolution.autoResolveTrivial // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$AUTO_RESOLVE" ] && AUTO_RESOLVE="true"

# Read conflictResolution.maxConflictFiles
MAX_FILES=$(jq -r '.conflictResolution.maxConflictFiles // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$MAX_FILES" ] && MAX_FILES=$(jq -r '.conflictResolution.maxConflictFiles // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$MAX_FILES" ] && MAX_FILES=$(jq -r '.conflictResolution.maxConflictFiles // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$MAX_FILES" ] && MAX_FILES="20"
```

### 1. Determine invocation mode

`$ARGUMENTS` can be empty, a PR number, or a branch name. Normalize input:

```bash
# Extract PR number if numeric, otherwise treat as branch name
ARG="$ARGUMENTS"
if echo "$ARG" | grep -qE '^[0-9]+$'; then
  echo "MODE: PR number $ARG"
elif [ -n "$ARG" ]; then
  echo "MODE: Branch $ARG"
else
  echo "MODE: Auto-detect"
fi
```

**1a. Check for active merge/rebase state:**

```bash
if [ -f .git/MERGE_HEAD ] || [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  echo "ACTIVE_CONFLICT"
else
  echo "NO_ACTIVE_CONFLICT"
fi
```

**1b. Determine mode:**

- **No args + ACTIVE_CONFLICT** — resolve in-progress merge/rebase
- **No args + NO_ACTIVE_CONFLICT** — report "No active merge conflicts found" and exit
- **PR number** — fetch PR, attempt merge against base, resolve conflicts
- **Branch name** — resolve conflicts for that branch against default branch

**1c. PR mode setup** (if `$ARGUMENTS` is a PR number):

```bash
gh pr view $ARGUMENTS --json headRefName,baseRefName,mergeable,title
```

If `mergeable == "MERGEABLE"` (no conflicts), report "No conflicts found for PR #$ARGUMENTS" and exit.

**1d. Check for uncommitted changes** (if no active conflict):

```bash
git status --porcelain
```

If non-empty and no active conflict, use the **AskUserQuestion tool**:

"You have uncommitted changes that could interfere with conflict resolution."

- **Option 1**: "Stash changes and continue" — run `git stash`
- **Option 2**: "Abort — I'll commit first"

If Option 2: stop execution.

**1e. PR mode: attempt merge** (if `$ARGUMENTS` is a PR number and no active conflict):

```bash
git fetch origin
git checkout {headRefName}
git merge origin/{baseRefName} --no-commit --no-ff
```

After the merge command, verify conflicts actually materialized:

```bash
git diff --name-only --diff-filter=U
```

If empty (no conflicts despite stale `mergeable` status), report "No conflicts found after merge attempt" and complete the merge: `git commit --no-edit`.

### 2. Explore conflicts (Parallel)

**Execute in parallel** (single message, multiple tool calls):

**2a. List conflicted files and classify types:**

```bash
git diff --name-only --diff-filter=U
git status --porcelain | grep "^[UAD][UAD] "
```

**2b. Count conflict hunks per file:**

```bash
git diff --name-only --diff-filter=U | while IFS= read -r f; do
  echo "$f: $(grep -c '<<<<<<<' "$f") hunks"
done
```

**2c. Invoke capability-discovery skill** via Skill tool to discover build/test commands for verification in Step 5.

**2d. Max file check:**

If conflicted file count exceeds `MAX_FILES` (default: 20), use the **AskUserQuestion tool**:

"There are {N} conflicted files (limit: {max}). This may indicate the branches have diverged significantly."

- **Option 1**: "Proceed anyway"
- **Option 2**: "Abort — I'll rebase in smaller steps"

### 3. Plan resolution

For each conflicted file, create a tracking task:

```
TaskCreate:
  subject: "Resolve: {filename}"
  description: |
    **Type**: {UU|AA|UD|DU|AU|UA}
    **Complexity**: {trivial|semantic|structural|delete-modify}
    **Strategy**: {accept-ours|accept-theirs|manual-merge|ask-user}
    **Hunks**: {N}
```

Display conflict analysis table:

```markdown
## Conflict Analysis

| File | Type | Complexity | Strategy | Hunks |
|------|------|------------|----------|-------|
| src/foo.ts | UU | trivial | manual-merge | 2 |
| src/bar.ts | UU | semantic | manual-merge | 1 |
| README.md | UD | delete-modify | ask-user | 1 |
```

**Auto-proceed** for trivial conflicts if `AUTO_RESOLVE` is `true`.

**Use the AskUserQuestion tool** for semantic, structural, or delete-modify conflicts — show both sides and proposed strategy before proceeding.

### 4. Resolve conflicts

Resolve in order: trivial first, then semantic/structural, then delete-modify.

For each conflicted file:

1. **Mark in progress**: `TaskUpdate: taskId={id}, status=in_progress`

2. **Read the file** with conflict markers using the Read tool

3. **Parse** ours/theirs blocks per hunk:
   - Ours: content between `<<<<<<<` and `=======`
   - Theirs: content between `=======` and `>>>>>>>`

4. **Apply strategy**:
   - `accept-ours`: keep ours block, remove theirs block and all markers
   - `accept-theirs`: keep theirs block, remove ours block and all markers
   - `manual-merge`: combine both sides, removing markers
     - For **compatible changes**: merge both
     - For **competing changes**: use the **AskUserQuestion tool** showing both sides with surrounding context

5. **For delete-modify conflicts**: use the **AskUserQuestion tool**:

   "File `{name}` was deleted on one side and modified on the other."

   - **Option 1**: "Keep the modified version"
   - **Option 2**: "Accept the deletion"
   - **Option 3**: "I need to see more context first"

6. **Verify** no orphaned conflict markers remain in the file:

   ```bash
   grep -n '<<<<<<<\|=======\|>>>>>>>' "$FILE"
   ```

7. **Stage** the resolved file:

   ```bash
   git add "$FILE"
   ```

8. **Mark complete**: `TaskUpdate: taskId={id}, status=completed`

### 5. Verify resolution

#### 5.1 Orphaned Marker Audit

```bash
# Must return zero results — anchor to line start to avoid false positives
grep -rn '^<<<<<<<\|^=======\|^>>>>>>>' . 2>/dev/null | grep -v '.git/' | grep -v 'node_modules/'
```

If any markers found, go back to Step 4 for those files.

#### 5.2 Complete Merge/Rebase

```bash
if [ -f .git/MERGE_HEAD ]; then
  git commit --no-edit
elif [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  GIT_EDITOR=true git rebase --continue
fi
```

#### 5.3 Quality Verification

Run quality commands discovered in Step 2c in parallel. Apply a bounded fix-verify loop:

Read max iterations from settings:
```bash
MAX_ITERATIONS=$(jq -r '.timeouts.qualityCheckMaxIterations // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$MAX_ITERATIONS" ] && MAX_ITERATIONS=$(jq -r '.timeouts.qualityCheckMaxIterations // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$MAX_ITERATIONS" ] && MAX_ITERATIONS=$(jq -r '.timeouts.qualityCheckMaxIterations // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$MAX_ITERATIONS" ] && MAX_ITERATIONS="3"
```

**Iteration 1 (and up to MAX_ITERATIONS total):**

1. **Run all quality commands in parallel** (multiple Bash tool calls):
   ```
   - Bash call 1: {lint_cmd}
   - Bash call 2: {test_cmd}
   - Bash call 3: {typecheck_cmd}
   ```

2. **If ALL pass** — proceed to 5.4

3. **If ANY fail**:
   - Parse error output to identify root cause
   - Fix the issue immediately (Edit tool)
   - Commit the fix: `git commit -m "fix: resolve quality issue after conflict resolution"`
   - Re-run ALL checks (go back to step 1)

4. **After MAX_ITERATIONS failed iterations** — escalate via **AskUserQuestion tool**:
   - **Option 1**: "Show me the failures, I'll fix manually"
   - **Option 2**: "Push with known failures"
   - **Option 3**: "Abort — I need to investigate"

#### 5.4 Resolution Summary

Display a summary table:

```markdown
## Resolution Summary

| File | Strategy | Result |
|------|----------|--------|
| src/foo.ts | manual-merge | Resolved (2 hunks) |
| src/bar.ts | accept-theirs | Resolved (1 hunk) |
| README.md | keep-modified | Resolved |

Quality: lint {PASS/FAIL} | tests {PASS/FAIL} | typecheck {PASS/FAIL}
```

## Output Format

### Success
```
## Conflicts Resolved

**Files resolved:** {N}
**Strategy breakdown:** {N} trivial, {N} manual-merge, {N} user-decided

| File | Strategy | Result |
|------|----------|--------|
| {file} | {strategy} | Resolved ({N} hunks) |

Quality: lint PASS | tests PASS | typecheck PASS

### Next Steps
- Push changes: `git push`
- Continue with merge: `/gh-merge {PR}`
```

### Failure
```
## Conflict Resolution Failed

**Reason:** {specific reason}

### How to Fix
{actionable steps to resolve the issue}
```

### Failure (Too Many Conflicts)
```
## Too Many Conflicts ({N} files)

This exceeds the configured limit of {max} conflicting files.

### Alternatives
- Rebase in smaller steps against the target branch
- Split the PR into smaller, focused PRs
- Resolve manually: `git mergetool`
```

## Arguments

- `$ARGUMENTS`: PR number, branch name, or empty (optional)
  - Empty: resolve active merge/rebase conflicts
  - PR number (e.g., `42`): fetch PR and resolve conflicts against base branch
  - Branch name (e.g., `feature/foo`): resolve conflicts against default branch

## Rules

- ALWAYS analyze both sides of every conflict before resolving
- NEVER silently drop changes from either side
- NEVER auto-resolve delete-modify conflicts — always use AskUserQuestion
- ALWAYS run quality checks after resolution
- ALWAYS verify no orphaned conflict markers remain
- **Always detect default branch dynamically** — never assume `main` or `master`
- **Use the AskUserQuestion tool** for:
  - Delete-modify conflict decisions
  - Competing changes (mutually exclusive implementations)
  - Max conflict file threshold exceeded
  - Quality check escalation after max iterations

## Success Criteria

Before completing, verify:
- [ ] All conflicted files resolved (zero UU/AA/UD/DU entries in `git status`)
- [ ] No orphaned conflict markers in any file
- [ ] Merge/rebase completed successfully
- [ ] Quality checks pass (lint, test, typecheck)
- [ ] Resolution summary displayed to user
- [ ] All TaskCreate items marked completed

## Related Commands

- **`/gh-merge`**: Merge PR (suggests gh-resolve when conflicts detected)
- **`/gh-address`**: Address PR review feedback
- **`/gh-start`**: Start work on an issue
- **`/gh-commit`**: Context-aware commits with change classification
