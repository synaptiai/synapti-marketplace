---
name: branch-and-task-management
description: "[flow] Use when starting work on an issue. Guides branch creation with naming conventions, issue context loading, impact analysis, task decomposition from acceptance criteria, and parallel task detection."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TaskCreate, TaskList, TaskUpdate, TaskGet
context: fork
agent: Explore
---

# Branch and Task Management

Domain skill for starting work: branch setup, context loading, and task decomposition.

## Branch Creation

Follow project conventions from settings or CLAUDE.md:

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
git fetch origin "$DEFAULT_BRANCH"
git checkout -b "feature/issue-{N}-{desc}" "origin/$DEFAULT_BRANCH"
```

Branch naming patterns (from `settings.json` → `conventions.branchPatterns`):
- `feature/issue-{N}-{desc}` — New features
- `fix/issue-{N}-{desc}` — Bug fixes
- `docs/issue-{N}-{desc}` — Documentation

Keep `{desc}` to 3-5 words, kebab-case, meaningful.

## Issue Context Loading

Fetch issue details in parallel:

```bash
# Parallel: issue details + comments + linked issues
gh issue view $N --json title,body,labels,assignees,milestone
gh issue view $N --comments
```

Extract from issue body:
- **Title**: One-line summary
- **Acceptance criteria**: Each `- [ ]` item becomes a task
- **Labels**: Inform implementation approach
- **Related issues**: Cross-references for context

## Impact Analysis

Before implementation, identify affected areas:

```bash
# Search for related code
grep -r "keyword_from_issue" --include="*.{rb,js,ts,py}" -l
# Check recent changes in related areas
git log --oneline -10 -- "path/to/related/"
```

Map acceptance criteria to likely file changes. Flag if the issue touches:
- Multiple modules (coordination needed)
- Shared utilities (risk of side effects)
- Test fixtures (may need updates across suites)

## Task Decomposition

Convert acceptance criteria to tasks using TaskCreate:

```
For each acceptance criterion:
  TaskCreate(
    subject: "Implement: {criterion summary}",
    description: "Acceptance criterion: {full text}\nLikely files: {paths}\nVerification: {how to check}"
  )
```

Rules:
- One task per acceptance criterion (minimum)
- Add infrastructure tasks if needed (migrations, config)
- Add a verification task at the end
- Set dependencies with addBlockedBy for sequential work

## Parallel Task Detection

Identify tasks that can run concurrently:

- Tasks touching **different files** with **no shared imports** → parallelizable
- Tasks in **different directories** → likely parallelizable
- Tasks modifying **the same file** → sequential (dependency)

If agent teams are enabled and >5 acceptance criteria with independent file sets → suggest team dispatch.

## Decision Journal Init

Create journal at branch creation:

```bash
JOURNAL_DIR=".decisions"
mkdir -p "$JOURNAL_DIR"
```

Write header to `{JOURNAL_DIR}/issue-{N}.md`:

```markdown
# Decision Journal: Issue #{N} — {title}

**Issue**: #{N}
**Branch**: {branch-name}
**Started**: {YYYY-MM-DD}

---
```

## Verification

Branch setup is valid when:
- Branch name matches convention pattern
- Issue details loaded successfully
- At least one task created per acceptance criterion
- Dependencies set correctly (no circular deps)
- Journal initialized
