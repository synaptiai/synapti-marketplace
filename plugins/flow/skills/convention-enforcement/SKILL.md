---
name: convention-enforcement
description: "Validate git conventions (commit messages, branch naming, PR format, issue linkage) by detecting project-specific rules from CLAUDE.md and settings, inferring patterns from recent history. Use when creating commits, preparing PRs, or reviewing for convention compliance. This skill MUST be consulted because convention-violating history is a defect that every future contributor must question and work around."
allowed-tools: Bash, Read
context: fork
agent: Explore
---

# Convention Enforcement

Domain skill for validating git conventions across the development workflow.

## Iron Law

**CONVENTIONS ARE NOT OPTIONAL. A commit that violates project conventions is a defective commit, regardless of code quality.**

History that violates conventions is history that every future contributor must question and work around.

## Convention Sources (Priority Order)

1. **CLAUDE.md** — Project-specific overrides (highest priority)
2. **settings.flow.json** — Plugin configuration
3. **Defaults** — Built-in conventions (lowest priority)

```bash
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"
```

## Commit Message Validation

### Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Rules

- **Type**: Must be one of configured `conventions.commitTypes` (default: feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert, improve)
- **Scope**: Optional, parenthesized, lowercase
- **Subject**: Imperative mood, no period
- **Body**: Separated by blank line

### Validation

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git log --format="%s" "$DEFAULT_BRANCH"..HEAD
```

Check each commit subject against the format regex:
`^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert|improve)(\(.+\))?: .+$`

## Branch Naming Validation

Check current branch against configured patterns:

```bash
BRANCH=$(git branch --show-current)
```

Valid patterns (from `conventions.branchPatterns`):
- `feature/issue-{N}-{desc}` — alphanumeric + hyphens
- `fix/issue-{N}-{desc}`
- `docs/issue-{N}-{desc}`

Invalid:
- Spaces or special characters
- Missing issue number (unless explicitly configured)
- Direct commits to default branch

## PR Format Validation

A valid PR must have:
- Title matching conventional commit format
- Body with at least: Summary section, linked issue reference
- Labels (at least one)
- No draft status when requesting review

## Issue Linkage

Every branch should link to an issue:

```bash
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
[ -n "$ISSUE_NUM" ] && gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null
```

Warn if:
- Branch has no issue number
- Linked issue is closed
- Linked issue is assigned to someone else

## Project-Specific Detection

Infer conventions from existing patterns:

```bash
# Infer from recent commits
git log --oneline -20 --format="%s"
# Infer from existing branches
git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin/ | head -10
```

If project uses different conventions (e.g., `feat/123-description` instead of `feature/issue-123-description`), adapt validation accordingly and note in output.

## Output

Report all violations with severity:

| Violation | Severity | Fix |
|-----------|----------|-----|
| Non-conventional commit message | P2 | Amend or reword |
| Wrong branch naming | P3 | Note only (too late to rename) |
| Missing issue linkage | P2 | Add `Closes #N` to PR body |
| Missing PR labels | P3 | Add during PR creation |

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "The convention doesn't apply to this type of change" | Check the config. If the convention is configured, it applies. |
| "I'll fix the commit message later" | Later doesn't exist in git history. Fix it now. |
