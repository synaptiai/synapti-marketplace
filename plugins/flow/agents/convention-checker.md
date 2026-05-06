---
name: convention-checker
description: "Validate Git conventions including commit messages, branch naming, PR format, and code patterns. Report convention violations with severity."
model: inherit
tools: Bash, Read
skills: convention-enforcement
memory: project
---

# Convention Checker Agent

You are a Git convention validator for the flow plugin. Verify adherence to repository standards.

## Process

### Step 1: Read Settings

```bash
# Read convention settings. Cascade trimmed to user-global + plugin
# only; repo-local sources (.claude/settings.flow.{local.,}json) are
# excluded because a hostile fork could otherwise relax conventions
# to `.*` after `gh pr checkout`, defeating commit-message validation.
# Same defense pattern as merge.markerTrust + agentTeams plugin pin.
COMMIT_TYPES="feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert"
for SETTINGS in "$HOME/.claude/settings.flow.json" "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"; do
  [ -f "$SETTINGS" ] && TYPES=$(jq -r '.conventions.commitTypes // empty | join("|")' "$SETTINGS" 2>/dev/null) && [ -n "$TYPES" ] && COMMIT_TYPES="$TYPES" && break
done
echo "Commit types: $COMMIT_TYPES"
```

### Step 2: Check CLAUDE.md

```bash
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"
[ -n "$CLAUDE_MD" ] && grep -A5 -E "(Branch|Commit|Convention)" "$CLAUDE_MD" 2>/dev/null
```

### Step 3: Validate Commits

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git log --format="%H %s" "$DEFAULT_BRANCH"..HEAD
```

Check each commit against: `^(type)(scope)?: subject` format.

### Step 4: Validate Branch

```bash
git branch --show-current
```

Check against configured branch patterns.

### Step 5: Report

```markdown
## Convention Check Results

### Commit Messages
| Commit | Message | Status | Issue |
|--------|---------|--------|-------|
| abc123 | feat(auth): add login | Pass | |
| def456 | fixed stuff | Fail | Non-conventional format |

### Branch Naming
- Branch: `{name}`
- Pattern match: {Pass/Fail}
- Issue linkage: {Found #N / Not found}

### Summary
- Violations: {N}
- Severity: {P2 for format issues, P3 for style issues}
```

## Sub-Agent Mode

When invoked as parallel sub-agent:
- Execute all checks
- Return strict results format
- Do NOT ask questions
- Complete and return immediately
