---
name: change-classification
description: "[flow] Use when classifying code changes for commits. Applies primary and secondary signals to determine if changes are in-context, uncertain, or out-of-context relative to the current branch/issue/tasks. Flags first-touch files and red-flag patterns."
allowed-tools: Bash, Read, Grep
context: fork
agent: Explore
---

# Change Classification

Domain skill for analyzing and classifying code changes before committing.

## Classification Algorithm

For each changed file, evaluate signals to classify as: **in-context**, **uncertain**, or **out-of-context**.

### Primary Signals (Strong)

| Signal | Classification | Detection |
|--------|---------------|-----------|
| File already in branch diff | in-context | `git diff --name-only $DEFAULT_BRANCH...HEAD` includes file |
| File matches issue keywords | in-context | File path contains words from issue title/body |
| File in active task | in-context | File path matches TaskList task descriptions |
| File matches task directory | in-context | Same top-level directory as task-related files |

### Secondary Signals (Supporting)

| Signal | Classification | Detection |
|--------|---------------|-----------|
| Same directory as other changes | lean in-context | Sibling of already-classified in-context file |
| Test file for changed module | lean in-context | Naming convention match (e.g., `foo.rb` → `foo_test.rb`) |
| Config in project root | uncertain | Changes to dotfiles, config, package manifests |
| Unrelated directory | out-of-context | No connection to issue or tasks |

### Red Flags

These always get flagged regardless of context:

| Pattern | Action |
|---------|--------|
| `.env*`, `credentials*`, `*secret*` | Block — never commit |
| `*.lock`, `package-lock.json` | Warn — verify intentional |
| Large binary files (>1MB) | Warn — verify intentional |
| Auto-generated files | Note — may need regeneration |

### First-Touch Detection

A file is "first touch" when:
- 0 commits on the current branch modify it (`git log $DEFAULT_BRANCH..HEAD -- file` is empty)
- Large additions (>50 lines added)

First-touch files get extra review attention.

## Output Format

Display classification as a table (finding-first pattern):

```markdown
| File | Classification | Signal | Notes |
|------|---------------|--------|-------|
| src/auth/login.rb | in-context | matches issue keywords | |
| src/utils/format.rb | out-of-context | unrelated directory | first-touch |
| .env.example | RED FLAG | secret pattern | NEVER COMMIT |
```

## Atomic Commit Grouping

After classification, group in-context files into atomic commits:

1. **By logical unit**: Related files that form one change (model + migration + test)
2. **By type**: feat files separate from refactor files
3. **By directory**: When in doubt, group by top-level directory

Each group gets one conventional commit with an accurate message.

## Integration

This skill is invoked by:
- `/flow:commit` — Phase 1 (classify all changes)
- `/flow:address` — After fixes (verify no out-of-context changes)
- `/flow:pr` — Pre-flight (verify committed changes match intent)

See `references/classification-signals.md` for the complete signal reference.
