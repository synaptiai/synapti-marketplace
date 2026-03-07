---
description: Use after making changes to commit with context-aware classification that flags out-of-context modifications before committing
argument-hint: [message]
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, TaskList, TaskGet, Skill
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Context-Aware Commit

Smart commit workflow that classifies changes, flags out-of-context modifications, and supports multiple atomic commits.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for interactive decisions about change inclusion and commit grouping.

## Contract

**GOAL**: Atomic commits with conventional messages that accurately describe the actual changes. Testable: `git log -1 --pretty=%B` matches conventional format regex `^(feat|fix|docs|refactor|test|chore|style|perf|ci|build|revert)(\(.+\))?: .+`.

**CONSTRAINTS**:
- Never commit secrets (.env, credentials, API keys, tokens)
- Never silently include out-of-context files without user awareness
- Always show change classification before asking for decisions
- Follow conventional commit format

**FORMAT**: Classification table shown first, then commit preview with message, then execution.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Secrets or credential files committed
- Generic commit message ("update code", "fix stuff", "various changes")
- Commit type doesn't match actual changes (says "feat:" but only refactoring)
- Message references files or behaviors not in the diff
- Out-of-context files silently included without flagging
- Large binary files committed without warning

## Overview

This command analyzes all staged and unstaged changes, classifies them based on the current context (branch, issue, tasks), and helps create well-organized commits.

**Key Features**:
- Classifies changes as in-context, uncertain, or out-of-context
- Flags unrelated changes before committing
- Supports multiple atomic commits for large changesets
- Integrates with TaskList for context awareness

## Phase 1: Context Discovery

**Execute in parallel** (single message, multiple tool calls):

1. **Get current branch and linked issue**:
   ```bash
   # Current branch
   BRANCH=$(git branch --show-current)

   # Extract issue number from branch name (e.g., feature/issue-42-desc)
   ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')

   # Get default branch
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   ```

2. **Fetch linked issue details** (if issue number found):
   ```bash
   gh issue view $ISSUE_NUM --json title,body,labels 2>/dev/null
   ```

3. **Get active tasks** (if TaskList available):
   ```
   TaskList
   ```
   Extract task subjects and descriptions for context matching.

4. **Get branch diff summary** (files changed since branching):
   ```bash
   git diff --name-only $DEFAULT_BRANCH...HEAD
   ```

5. **Get recent commit messages** (for style consistency):
   ```bash
   git log --oneline -10
   ```

## Phase 2: Change Analysis

### Step 2.1: Get All Changes

```bash
# All changes (staged + unstaged + untracked)
git status --porcelain

# Separate staged changes
git diff --cached --name-only

# Separate unstaged changes
git diff --name-only

# Untracked files
git ls-files --others --exclude-standard
```

### Step 2.2: Classify Each Change

For each changed file, apply the classification algorithm:

**Primary Signals (Strong - in-context)**:
| Signal | Weight | Detection |
|--------|--------|-----------|
| File in branch diff | High | File already modified in this branch |
| File matches issue keywords | High | File path contains keywords from issue title/body |
| File in task-related directory | High | Directory matches task subject |
| File matches active task | High | File path mentioned in task description |

**Secondary Signals (Supporting)**:
| Signal | Weight | Detection |
|--------|--------|-----------|
| Same directory as other changes | Medium | Related to other in-context files |
| Same file extension | Low | Same type as other changes |

**Red Flags (Likely out-of-context)**:
| Signal | Detection |
|--------|-----------|
| Config files | `.env`, `.gitignore`, editor configs, IDE settings |
| Unrelated directories | `node_modules/`, `__pycache__/`, `.git/` |
| Auto-generated files | `package-lock.json`, `*.pyc`, `*.o` |
| Different feature area | Directory unrelated to issue scope |

### Step 2.3: Classification Output

```markdown
## Change Classification

**Context**: Branch `{branch}`, Issue #{issue_num}: "{issue_title}"

### In-Context (Confident)
| File | Reason |
|------|--------|
| src/api/users.ts | Matches issue keywords, branch diff |
| src/api/users.test.ts | Same directory as changed files |

### Uncertain (Needs Review)
| File | Signal | Concern |
|------|--------|---------|
| src/utils/format.ts | Related directory | Not in branch diff |
| docs/api.md | Documentation | May or may not be related |

### Out-of-Context (Flagged)
| File | Reason |
|------|--------|
| .vscode/settings.json | Editor config |
| unrelated/feature.ts | Different feature area |

### Summary
- **In-context**: {N} files
- **Uncertain**: {M} files
- **Out-of-context**: {K} files
```

### Step 2.4: First-Touch Flagging (Conditional)

**Check configuration** — read `.commands.ghCommitFirstTouch` from settings. Default: `true`. If `false`, skip this step.

Analyze commit patterns on the current branch to flag first-touch and AI-pattern files:

```bash
# For each file in the staged changes, check commit history on this branch
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
for FILE in $(git diff --cached --name-only); do
  COMMITS=$(git log "$DEFAULT_BRANCH"..HEAD --oneline -- "$FILE" | wc -l | tr -d ' ')
  echo "$FILE: $COMMITS commits on branch"
done
```

Read the first-touch threshold from settings (default: 50):
```bash
FIRST_TOUCH_THRESHOLD=$(jq -r '.review.firstTouchLineThreshold // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$FIRST_TOUCH_THRESHOLD" ] && FIRST_TOUCH_THRESHOLD=$(jq -r '.review.firstTouchLineThreshold // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$FIRST_TOUCH_THRESHOLD" ] && FIRST_TOUCH_THRESHOLD=$(jq -r '.review.firstTouchLineThreshold // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$FIRST_TOUCH_THRESHOLD" ] && FIRST_TOUCH_THRESHOLD="50"
```

For files with **0 prior commits on this branch** (first touch) that also have **large additions** (FIRST_TOUCH_THRESHOLD+ lines added in a single diff), flag as potential AI-pattern:

```markdown
### Comprehension Confidence
| File | Commits on Branch | First Touch? | AI-Pattern? |
|------|-------------------|--------------|-------------|
| src/api/users.ts | 4 | No | No |
| src/middleware/auth.ts | 0 | Yes | Yes |
```

**If any files flagged as first-touch + AI-pattern**, use the **AskUserQuestion tool**:
- **Option 1**: "I understand these changes well enough to debug them" (Proceed)
- **Option 2**: "Let me review these files before committing" (list flagged files)
- **Option 3**: "Proceed anyway — I'll study these later"

### Step 2.5: Decision Logging

Invoke the **decision-journal** skill in `log` mode using the **Skill tool**:

```
Skill: decision-journal —
  "Mode: log
   Phase: staged changes for commit
   Description: Changes staged for commit on branch {BRANCH}"
```

The skill returns decision entries, gate triggers, and the resolved journal directory. Append entries to `{journal-dir}/issue-{ISSUE_NUM}.md` (where `journal-dir` is returned by the skill, default `.decisions`). If gate triggers fire with config `on`, present them via **AskUserQuestion** using the gate format (see `references/gate-configuration.md`).

## Phase 3: Interactive Planning

**IMPORTANT**: Display the classification table BEFORE asking for decisions.

1. **Present the classification** (from Step 2.3)

2. **If uncertain or out-of-context files exist**, use the **AskUserQuestion tool**:

   **Options**:
   - **Option 1**: "Commit in-context files only" (Recommended) - Proceed with confident files
   - **Option 2**: "Include uncertain files" - Add uncertain to in-context
   - **Option 3**: "Select specific files" - Manual file selection
   - **Option 4**: "Commit all files" - Include everything

3. **If user selects "Select specific files"**, present file list:
   ```
   AskUserQuestion (multiSelect: true):
   - src/api/users.ts
   - src/api/users.test.ts
   - src/utils/format.ts
   - docs/api.md
   ```

4. **Stage selected files**:
   ```bash
   git add {selected_files}
   ```

## Phase 4: Atomic Commits

### Step 4.1: Analyze for Multiple Commits

If many files are selected, analyze for logical groupings:

**Grouping Heuristics**:
| Pattern | Suggested Group |
|---------|-----------------|
| `*.test.*` files | "test: ..." commit |
| Same directory | Single feature commit |
| Different feature areas | Separate commits |
| Documentation files | "docs: ..." commit |

```markdown
## Suggested Commit Groups

**Option A: Single Commit**
All {N} files in one commit

**Option B: Multiple Commits** (Recommended for large changes)
1. `feat: add user validation` - 3 files (src/api/...)
2. `test: add user validation tests` - 2 files (src/api/*.test.ts)
3. `docs: update API documentation` - 1 file (docs/api.md)
```

### Step 4.2: Commit Strategy Selection

Use the **AskUserQuestion tool**:
- **Option 1**: "Single commit" - All files in one commit
- **Option 2**: "Multiple commits" (Recommended for {N}+ files) - Grouped commits
- **Option 3**: "Interactive grouping" - Choose grouping manually

### Step 4.3: Execute Commits

For each commit group:

1. **Preview the commit**:
   ```markdown
   ## Commit Preview

   **Type**: feat/fix/docs/test/refactor/chore
   **Files**:
   - file1.ts
   - file2.ts

   **Suggested Message**:
   ```
   feat: add user input validation

   - Add validation for email format
   - Add validation for password strength
   ```
   ```

2. **Message Accuracy Check** — Before presenting to user, cross-check the suggested message against the actual diff:
   - Does the type (`feat`/`fix`/`docs`/`refactor`/`test`/`chore`) match the actual nature of changes?
   - Does the description accurately reflect what changed?
   - Is anything in the message NOT reflected in the diff?
   - Is anything significant in the diff NOT mentioned in the message?
   - If inaccurate, revise the message before presenting to user

3. **Get message approval** with AskUserQuestion:
   - **Option 1**: "Use this message" (Recommended)
   - **Option 2**: "Edit message"
   - **Option 3**: "Skip this group"

4. **Stage and commit**:
   ```bash
   git add {group_files}
   git commit -m "{message}"
   ```

### Commit Message Guidelines

Follow conventional commit format:

| Prefix | Usage | Example |
|--------|-------|---------|
| `feat:` | New feature | `feat: add date filtering to search` |
| `fix:` | Bug fix | `fix: resolve null pointer in parser` |
| `docs:` | Documentation | `docs: update API reference` |
| `test:` | Test changes | `test: add unit tests for validator` |
| `refactor:` | Code refactoring | `refactor: extract validation logic` |
| `chore:` | Maintenance | `chore: update dependencies` |

**Message Structure**:
```
type: short description (imperative mood)

- Detail 1
- Detail 2
```

## Phase 5: Summary

After all commits complete:

```markdown
## Commit Summary

### Committed
| Commit | Message | Files |
|--------|---------|-------|
| abc123 | feat: add user validation | 3 files |
| def456 | test: add validation tests | 2 files |

**Total**: {N} files in {M} commits

### Skipped (Out-of-Context)
| File | Reason |
|------|--------|
| .vscode/settings.json | Editor config |

**Note**: Skipped files remain as unstaged changes.

### Next Steps
- **Create PR**: Run `/gh-pr` to create a pull request
- **Continue working**: Make more changes, then run `/gh-commit` again
- **Review changes**: Run `git status` to see remaining changes
```

## Arguments

- `$ARGUMENTS`: Optional commit message for single-commit mode
  - If provided, skips message generation for simple commits
  - Example: `/gh-commit fix: resolve login bug`

## Special Modes

### Quick Commit (Message Provided)

If user provides a message: `/gh-commit feat: add new feature`

1. Skip multi-commit analysis
2. Stage all in-context files
3. Use provided message
4. Still flag out-of-context files

### No Active Tasks

If TaskList is empty or unavailable:
1. Rely on branch name and issue for context
2. Use file proximity heuristics
3. Be more conservative with classifications

### Detached HEAD / No Branch

If not on a feature branch:
1. Warn user about detached HEAD state
2. Classify all files as "uncertain"
3. Require explicit confirmation

## Rules

- **Never commit secrets** - Flag `.env`, credentials files, API keys
- **Warn about large files** - Flag files > 1MB
- **Preserve unstaged changes** - Don't auto-stage everything
- **Show before asking** - Always display classification before decisions
- **Conventional commits** - Follow commit message conventions
- **No auto-push** - Commits are local until user runs `/gh-pr`

## Error Handling

### No Changes Detected

```markdown
**No changes to commit.**

Working tree is clean. Make changes first, then run `/gh-commit`.
```

### All Changes Out-of-Context

```markdown
**All changes appear out-of-context.**

{N} files changed, but none match the current branch context:
- Branch: {branch}
- Issue: #{issue_num}

**Options**:
1. Commit anyway (override classification)
2. Review changes and reclassify
3. Stash changes for later (`git stash`)
```

### Merge Conflicts Present

```markdown
**Merge conflicts detected.**

Resolve conflicts before committing:
{list of conflicted files}

Run `git status` for details.
```

## Integration with gh-workflow

This command integrates with the broader gh-workflow:

- **After `/gh-start`**: Commit implementation progress
- **Before `/gh-pr`**: Finalize changes for PR
- **After `/gh-address`**: Commit fixes from review feedback

**Workflow Example**:
```
/gh-start 42        # Create branch, start implementation
# ... make changes ...
/gh-commit          # Commit in-context changes
# ... make more changes ...
/gh-commit          # Additional commit
/gh-pr              # Create PR with all commits
```
