---
description: "[flow] Classify changes and create atomic commits with conventional messages. Flags out-of-context modifications and red-flag patterns before committing."
argument-hint: [message]
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute all independent queries in a single message with parallel tool calls.
-->

# Context-Aware Commit

Classify changes, flag anomalies, and create atomic conventional commits. Follows the Explore > Verify pattern (lightweight — no plan/code phases needed).

## Required Skills

- `change-classification` — signal-based change analysis
- `convention-enforcement` — commit message validation

## Phase 1: EXPLORE

Execute these in parallel:

**Parallel Bash calls:**

```bash
# 1. All changes
git status --porcelain

# 2. Branch context
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
echo "BRANCH=$BRANCH DEFAULT=$DEFAULT_BRANCH"

# 3. Files already on branch
git diff --name-only $DEFAULT_BRANCH...HEAD

# 4. Issue context
ISSUE_NUM=$(echo $BRANCH | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
[ -n "$ISSUE_NUM" ] && gh issue view $ISSUE_NUM --json title,body 2>/dev/null

# 5. Recent commits (for style)
git log --oneline -10

# 6. Task-related context from branch or issue
```

**Grep** — search branch diff and issue body for task-related context.

## Phase 2: CLASSIFY

Apply change-classification skill knowledge:

For each changed file, evaluate:
1. **Red flags** — block secrets, warn on lock files and large binaries
2. **Primary signals** — branch diff, issue keywords, task match
3. **Secondary signals** — sibling files, test companions
4. **First-touch detection** — new files with large additions

## Phase 3: DISPLAY (Finding-First)

Show classification table BEFORE any action:

```markdown
| File | Status | Classification | Signal | Notes |
|------|--------|---------------|--------|-------|
| src/auth/login.rb | M | in-context | branch diff | |
| src/utils/helper.rb | M | uncertain | sibling only | first-touch |
| .env.example | M | RED FLAG | secret pattern | BLOCKED |
```

**If uncertain or out-of-context files exist:**

Use the AskUserQuestion tool with contextual options to ask: "Some files are uncertain or out-of-context. How should they be handled?"

## Phase 4: COMMIT

**Group in-context files** into atomic commits by logical unit.

For each commit group:

1. **Generate commit message** following conventional format:
   - Type: inferred from changes (feat, fix, refactor, test, docs, chore)
   - Scope: top-level directory or module
   - Subject: imperative, ≤72 chars, describes what and why
   - If `$ARGUMENTS` provided, use as message (validate format first)

2. **Stage and commit** (Tier 1 — autonomous):
   ```bash
   git add <specific-files>
   git commit -m "<type>(<scope>): <subject>"
   ```

3. **Verify** — the PostToolUse hook logs the commit to the decision journal.

## Phase 5: SUMMARY

Display:
- Commits created (hash + message)
- Files committed per group
- Any excluded files and why
- Suggested next step: `/flow pr` if ready, or continue working

## Edge Cases

- **No changes**: Report "Working tree clean" and exit
- **Only untracked files**: Ask whether to include
- **All out-of-context**: Warn and require explicit confirmation
- **Mixed types**: Create separate commits per type (feat + test)
