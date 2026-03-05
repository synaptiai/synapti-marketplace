# Code Review Checklist (Self-Review)

Reference checklist for pre-PR self-review. Only analyze new code in the diff.

## Agent-Assisted Review (Preferred)

If the `code-reviewer` agent is available (detected in Capability Discovery), dispatch it using the **Agent tool**:

```
Agent: code-reviewer — "Self-review before PR. Analyze diff between origin/$DEFAULT_BRANCH and HEAD for code quality, logic correctness, security vulnerabilities, edge cases, and error handling. Return P1/P2/P3 findings table with file:line citations."
```

If the agent returns findings, incorporate them. If agent dispatch fails or is unavailable, fall back to the manual review below.

## Manual Review Fallback

```bash
git diff origin/$DEFAULT_BRANCH..HEAD
```

### 1. Unnecessary/Duplicate Code
- Identify redundant logic
- Check for copy-paste duplication
- Look for dead code paths

### 2. Type Safety & Language Gotchas
- TypeScript: proper typing, no unnecessary `any`
- Python: type hints, pyright compliance
- Watch for common footguns

### 3. Code Bloat
- Remove unnecessary comments
- Delete debug code/console.logs
- Remove commented-out code

### 4. Complexity
- Simplify overly complicated logic
- Extract complex conditions into named functions
- Reduce nesting depth

### 5. Naming
- Variable names are clear and descriptive
- Function names describe what they do
- Consistent naming patterns

### 6. Pattern Consistency
- Use established project patterns
- Don't introduce conflicting approaches
- Check CLAUDE.md for conventions

### 7. NO PLACEHOLDERS
- No mocks, demo data, placeholder code, stubs in src
- All implementations must be production-ready

## Output Format

```
## Code Review Findings

### Issues Found
| # | Type | Location | Issue | Fix |
|---|------|----------|-------|-----|
| 1 | Duplicate | file:line | [desc] | [fix] |

### Fixes Applied
- [x] Fixed: [description]
```

## After Review

- **P1/P2 findings**: Create tasks via `TaskCreate: subject="Fix: [issue]"`, implement fixes, re-run quality checks
- **P3 findings**: Fix inline immediately, no task needed
