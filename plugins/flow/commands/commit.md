---
description: "Classify changes and create atomic commits with conventional messages. Flags out-of-context modifications and red-flag patterns before committing."
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

- `llm-operator-principles` — foundational operator stance: convergence = zero findings, in-PR fixes by default, no calendar-time estimates, narrow escalation triggers. MUST be consulted before any other phase
- `change-classification` — signal-based change analysis
- `convention-enforcement` — commit message validation

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 3's uncertain/out-of-context-files escalation

## Phase 1: EXPLORE

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

echo "### Branch Context"
BRANCH=$(git branch --show-current 2>/dev/null)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
echo "BRANCH=$BRANCH"
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"

echo ""
echo "### Uncommitted Changes"
UNCOMMITTED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "UNCOMMITTED_COUNT=$UNCOMMITTED_COUNT"
if [ "$UNCOMMITTED_COUNT" = "0" ]; then
  echo "STATE=empty"
else
  git status --porcelain 2>/dev/null | sed 's/^/UNCOMMITTED_LINE=/'
fi

echo ""
echo "### Branch Files (vs default)"
BRANCH_FILES=$(git diff --name-only "$DEFAULT_BRANCH"...HEAD 2>/dev/null)
# `grep -c '.' || echo 0` produces multi-line `0\n0` on empty input (grep
# exits 1, the `||` ALSO fires). Use explicit empty-check.
if [ -z "$BRANCH_FILES" ]; then
  BRANCH_FILE_COUNT=0
else
  BRANCH_FILE_COUNT=$(printf '%s\n' "$BRANCH_FILES" | wc -l | tr -d ' ')
fi
echo "BRANCH_FILE_COUNT=$BRANCH_FILE_COUNT"
if [ "$BRANCH_FILE_COUNT" = "0" ]; then
  echo "STATE=empty"
else
  printf '%s\n' "$BRANCH_FILES" | sed 's/^/BRANCH_FILE=/'
fi

echo ""
echo "### Issue Context"
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
# Quote parenthesized fallback per command-output-format.md rule 2.
echo "ISSUE_NUM=${ISSUE_NUM:-\"(none)\"}"
if [ -n "$ISSUE_NUM" ]; then
  gh issue view "$ISSUE_NUM" --json title,body --jq '"ISSUE_TITLE=\"\(.title)\"\nISSUE_BODY_LENGTH=\(.body | length)"' 2>/dev/null
fi

echo ""
echo "### Recent Commits (for style)"
# Capture so an empty log (new repo) emits STATE=empty rather than silent
# heading.
RECENT_COMMITS=$(git log --oneline -10 2>/dev/null)
if [ -z "$RECENT_COMMITS" ]; then
  echo "STATE=empty"
else
  printf '%s\n' "$RECENT_COMMITS" | sed 's/^/COMMIT=/'
fi

true
```

**Grep** — search branch diff and issue body for task-related context.

## Phase 2: CLASSIFY (cross-check)

**Note**: When running after `/flow:start`, per-task change classification already happened during the CODE phase (step 8 of the per-task verification gate). Commit-time classification is a **final cross-check**, not the primary gate. Out-of-context files should have been flagged and resolved during CODE. If new out-of-context files appear here, it indicates a gap in the per-task gate that should be investigated.

Apply change-classification skill knowledge:

For each changed file, evaluate:
1. **Red flags** — block secrets, warn on lock files and large binaries
2. **Primary signals** — branch diff, issue keywords, task match
3. **Secondary signals** — sibling files, test companions
4. **First-touch detection** — new files with large additions
5. **Boy Scout detection** — if changes are cleanup-only (lint, format, typo, obvious bug fix) in files already on the branch diff, classify as `boy-scout` subtype of in-context

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

Use the AskUserQuestion tool with a Proactive-Autonomy escalation:

> **Situation** — {N} files are classified as uncertain or out-of-context for this branch.
>
> **What I tried** — Applied change-classification signals (branch diff, issue keywords, sibling detection). These files did not match any primary signal.
>
> **Options**:
> 1. Include in this commit with a separate `improve:` or `chore:` commit (Recommended if changes are Boy Scout cleanup)
> 2. Exclude from this commit — leave unstaged for a separate branch
>
> **Recommendation** — Option {1|2} based on whether the changes are cleanup (include) or genuinely unrelated (exclude).
>
> **Blocking?** — Soft. The commit cannot proceed until these files are classified, but no external state depends on the outcome.
>
> **Risk** — Including out-of-context changes clutters the branch history. Excluding them leaves the work unstaged on the worktree until you address it.

## Phase 4: COMMIT

**Group in-context files** into atomic commits by logical unit.

For each commit group:

1. **Generate commit message** following conventional format:
   - Type: inferred from changes (feat, fix, refactor, test, docs, chore, improve)
   - For Boy Scout cleanup changes, use `improve(<scope>): <summary>`
   - Scope: top-level directory or module
   - Subject: imperative, describes what and why
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
- Suggested next step: `/flow:pr` if ready, or continue working

## Edge Cases

- **No changes**: Report "Working tree clean" and exit
- **Only untracked files**: Ask whether to include
- **All out-of-context**: Warn and require explicit confirmation
- **Mixed types**: Create separate commits per type (feat + test)

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git status / branch / changed files | 1 | Autonomous, read-only |
| Classify changes via `change-classification` skill | 1 | Autonomous |
| `AskUserQuestion` for uncertain/out-of-context files | n/a | User-driven escalation per `references/escalation-format.md` |
| `git add <specific-files>` (per-group atomic staging) | 1 | Autonomous |
| `git commit -m "<conventional-message>"` | 1 | Autonomous, logged by `log-commits.sh` PostToolUse hook |
