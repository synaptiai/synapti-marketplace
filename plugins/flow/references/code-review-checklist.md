# Code Review Checklist

Reference checklist for pre-PR self-review and PR code review. Focus on new code in the diff.

## Agent-Assisted Review (Preferred)

Dispatch code-reviewer agent:

```
Agent(code-reviewer): "Review diff between origin/$DEFAULT_BRANCH and HEAD for code quality, logic, security, edge cases. Return P1/P2/P3 findings with file:line."
```

## Manual Checklist (Fallback)

### 1. Logic Correctness
- [ ] Correct for all input cases?
- [ ] Implicit assumptions documented?
- [ ] Boundary conditions handled (0, -1, MAX, empty)?
- [ ] Loop termination guaranteed?

### 2. Security
- [ ] No hardcoded secrets
- [ ] No SQL/command/code injection
- [ ] User input validated and sanitized
- [ ] Authorization checks present
- [ ] Sensitive data not in logs/errors

### 3. Error Handling
- [ ] Exceptions caught at appropriate level
- [ ] Error messages helpful but not leaky
- [ ] Cleanup on failure (transactions, file handles)
- [ ] Async errors handled

### 4. Code Quality
- [ ] No dead code or commented-out blocks
- [ ] No debug statements (console.log, puts, print)
- [ ] No unnecessary complexity
- [ ] Follows project conventions (CLAUDE.md)

### 5. Tests
- [ ] New functionality has tests
- [ ] Edge cases covered
- [ ] Tests are deterministic (no flaky assertions)
- [ ] Mocks are minimal and appropriate

### 6. Dependencies
- [ ] No unnecessary new dependencies
- [ ] New dependencies are well-maintained
- [ ] License compatible

## Finding Format

All findings use P1/P2/P3 with file:line citations:

| Priority | Meaning | Action |
|----------|---------|--------|
| P1 | Blocks merge | Must fix |
| P2 | Should fix | Fix before merge |
| P3 | Consider | Optional improvement |
