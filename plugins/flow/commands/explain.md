---
description: "[flow] Interactive Q&A about architecture decisions, implementation rationale, and trade-offs. Loads decision journal and diff context for the current branch/issue."
allowed-tools: Bash, Read, AskUserQuestion, Grep, Glob
---

# Explain Decisions

Interactive Q&A mode for understanding what was built and why. Read-only — no changes made.

## Phase 1: Load Context

**Parallel operations:**

```bash
# 1. Current branch and issue
BRANCH=$(git branch --show-current)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')

# 2. Decision journal
JOURNAL_DIR=".decisions"
for SETTINGS in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "plugins/flow/settings.json"; do
  [ -f "$SETTINGS" ] && DIR=$(jq -r '.journal.dir // empty' "$SETTINGS" 2>/dev/null) && [ -n "$DIR" ] && JOURNAL_DIR="$DIR" && break
done
[ -n "$ISSUE_NUM" ] && cat "$JOURNAL_DIR/issue-$ISSUE_NUM.md" 2>/dev/null

# 3. Issue details
[ -n "$ISSUE_NUM" ] && gh issue view "$ISSUE_NUM" --json title,body 2>/dev/null

# 4. Branch diff summary
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
git diff --stat "$DEFAULT_BRANCH"...HEAD
```

## Phase 2: Present Context

```markdown
## Decision Context

**Branch**: {branch}
**Issue**: #{N} — {title}
**Files changed**: {count}
**Journal entries**: {count}
**Key decisions**: {list from journal}
```

## Phase 3: Interactive Q&A

Use the AskUserQuestion tool with contextual options to ask: "What would you like to understand about this implementation?"

For each question:
1. Search the decision journal for relevant entries
2. Read referenced files for evidence
3. Construct an evidence-based answer with file:line citations
4. Offer follow-up question

## No Context Case

If no decision journal or no branch context:
- "No decision context available for the current branch."
- Offer to explain based on diff analysis alone
- Or suggest running `/flow:start` first to generate context
