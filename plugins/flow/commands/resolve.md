---
description: "Resolve merge conflicts on the current branch or for a pull request. Detects conflict types, analyzes both sides, applies per-file resolution strategies, and verifies the result compiles and passes tests."
argument-hint: [pr-number-or-branch]
allowed-tools: Bash(git diff *) Bash(git status *) Bash(git merge *) Bash(git fetch *) Bash(git checkout *) Bash(git commit *) Bash(git rebase *) Bash(git add *) Bash(gh pr view *) Bash(gh auth *) Bash(grep *) Bash(echo *) Read Write Edit Agent Skill AskUserQuestion TaskCreate TaskList TaskUpdate TaskGet Grep Glob
---

<!--
EXECUTION MODEL:
Phase 0 conflict-state detection and Phase 1 conflict enumeration are
pre-executed via the `!` prefix at command load — no Bash tool round-trip.
Mutating bash (PR-mode setup with `git fetch`/`checkout`/`merge`, per-file
`git add`, the orphan-marker audit, and `git commit --no-edit` /
`git rebase --continue`) stays inline because it must run conditionally
based on Claude's per-file resolution decisions.
-->

# Resolve Merge Conflicts

4-phase EXPLORE > PLAN > CODE > VERIFY workflow for merge conflict resolution.

## Required Skills

- `merge-conflict-resolution` — conflict detection, classification, and resolution strategies
- `capability-discovery` — discover build/test/lint commands
- `debugging-patterns` — on-demand if resolution breaks the build

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by the max-conflict-files escalation (Phase 1) and any semantic/structural/delete-modify escalation surfaced during resolution

## Phase 0: Pre-Flight

Determine invocation mode from `$ARGUMENTS`:

1. **No args + active conflict markers** → resolve in-progress merge/rebase
2. **PR number** → fetch PR, attempt merge against base, resolve conflicts
3. **Branch name** → resolve conflicts for that branch against default branch

### Validation + Conflict Enumeration

Pre-executed at command load (`!` prefix). Combines Phase 0 active-conflict
detection with Phase 1a (conflicted file list) and Phase 1b (hunk count per
file) so all read-only context arrives in one shot.

```!
# Phase 0: active merge/rebase state
if [ -f .git/MERGE_HEAD ] || [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  echo "ACTIVE_CONFLICT"
else
  echo "NO_ACTIVE_CONFLICT"
fi

# Phase 1a: conflicted files + status type codes
git diff --name-only --diff-filter=U
git status --porcelain | grep "^[UAD][UAD] " || true

# Phase 1b: conflict hunks per file. `|| true` per-line so a missing file
# (delete-modify, codes UD/DU) or a zero-match grep doesn't terminate the
# loop with non-zero exit.
git diff --name-only --diff-filter=U | while IFS= read -r f; do
  [ -f "$f" ] && echo "$f: $(grep -c '<<<<<<<' "$f" || echo 0) hunks" || true
done

true  # explicit success — block exit reflects intent, not the trailing pipeline
```

- If mode is PR: verify `gh auth status` succeeds (run inline as needed)
- Warn if there are uncommitted changes (`git status --porcelain` is non-empty and no active conflict)

### PR Mode Setup

Mutating — runs as inline Bash tool calls, only in PR mode (when `$ARGUMENTS`
is a PR number):

```bash
# Fetch PR details and attempt merge. Validate $ARGUMENTS is numeric (PR mode)
# or a safe branch name before substitution — defensive against shell
# metacharacters in $ARGUMENTS.
case "$ARGUMENTS" in
  '') echo "ERROR: PR number or branch name required in PR/branch mode"; exit 1 ;;
  *[!A-Za-z0-9._/-]*) echo "ERROR: invalid characters in argument"; exit 1 ;;
esac
gh pr view "$ARGUMENTS" --json headRefName,baseRefName,mergeable,title
git fetch origin
# Disambiguate ref vs path — `git checkout <name>` can resolve to a file
# path that matches the ref name. The `--` form forces ref interpretation.
git checkout "refs/heads/<headRefName>" 2>/dev/null || git checkout "<headRefName>" --
git merge "origin/<baseRefName>" --no-commit --no-ff
```

If `mergeable == "MERGEABLE"` (no conflicts), report "No conflicts found" and exit.

## Phase 1: EXPLORE

Phase 1a and 1b context (file list + hunk counts) is already loaded by the
Phase 0 `!` block above. Remaining Phase 1 steps:

**1c. Discover build/test commands** via capability-discovery skill.

**1d. Read settings for conflict resolution config:**

Check `settings.json` for `conflictResolution.autoResolveTrivial` and `conflictResolution.maxConflictFiles`.

### Max File Check

If conflicted file count exceeds `maxConflictFiles` (default: 20):

Use AskUserQuestion: "There are {N} conflicted files (limit: {max}). This may indicate the branches have diverged significantly. Options: 1) Proceed anyway, 2) Abort and consider rebasing in smaller steps."

## Phase 2: PLAN

Create a task per conflicted file:

```
TaskCreate: "Resolve {filename}"
  - Type: {UU|AA|UD|DU|AU|UA}
  - Complexity: {trivial|semantic|structural|delete-modify}
  - Strategy: {accept-ours|accept-theirs|manual-merge|ask-user}
  - Hunks: {N}
```

Display conflict analysis table:

```markdown
## Conflict Analysis

| File | Type | Complexity | Strategy | Hunks |
|------|------|------------|----------|-------|
| src/foo.ts | UU | trivial | manual-merge | 2 |
| src/bar.ts | UU | semantic | manual-merge | 1 |
| README.md | UD | delete-modify | ask user | 1 |
```

**Auto-proceed** for trivial conflicts if `autoResolveTrivial` is true (default).

**AskUserQuestion** for semantic, structural, or delete-modify conflicts — show both sides and proposed strategy before proceeding.

## Phase 3: CODE

Resolve conflicts in order: trivial first, then semantic/structural, then delete-modify.

For each conflicted file:

1. **TaskUpdate** → `in_progress`
2. **Read** the file with conflict markers
3. **Parse** ours/theirs blocks per hunk
4. **Apply strategy**:
   - `accept-ours`: keep content between `<<<<<<<` and `=======`
   - `accept-theirs`: keep content between `=======` and `>>>>>>>`
   - `manual-merge`: combine both sides, removing markers
     - For **compatible changes**: merge both
     - For **competing changes**: use AskUserQuestion showing both sides with context
5. For **delete-modify** conflicts: use AskUserQuestion — "File {name} was deleted on one side and modified on the other. Keep modified version or accept deletion?"
6. **Verify** no orphaned conflict markers remain in the file:
   ```bash
   grep -n '<<<<<<<\|=======\|>>>>>>>' "$FILE"
   ```
7. **Stage** the resolved file: `git add "$FILE"`
8. **TaskUpdate** → `completed`

## Phase 4: VERIFY

### 1. Orphaned Marker Audit

```bash
# Must return zero results across entire repo
grep -rn '<<<<<<<\|=======\|>>>>>>>' --include='*' . 2>/dev/null | grep -v '.git/' | grep -v 'node_modules/'
```

If any markers found, go back to Phase 3 for those files.

### 2. Complete Merge/Rebase

```bash
# Complete the merge or rebase
if [ -f .git/MERGE_HEAD ]; then
  git commit --no-edit
elif [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  git rebase --continue
fi
```

### 3. Quality Verification

Run quality commands in parallel (discovered in Phase 1):

- Lint
- Tests
- Type checking

If any fail, use debugging-patterns skill to diagnose and fix. Loop up to `closedLoop.maxBuildIterations` times.

### 4. Resolution Summary

Display a summary table:

```markdown
## Resolution Summary

| File | Strategy | Result |
|------|----------|--------|
| src/foo.ts | manual-merge | Resolved (2 hunks) |
| src/bar.ts | accept-theirs | Resolved (1 hunk) |
| README.md | keep-modified | Resolved |

Quality: lint PASS | tests PASS | typecheck PASS
```

## Tier Classification

| Action | Tier | Behavior |
|--------|------|----------|
| Conflict analysis | 1 | Autonomous |
| Trivial resolution | 1 | Autonomous |
| Semantic/structural resolution | 2 | Journal + show rationale |
| Delete-modify decisions | 2 | Journal + AskUserQuestion |
| Post-resolution commit | 1 | Autonomous |
