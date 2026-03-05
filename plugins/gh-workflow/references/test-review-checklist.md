# Test Review Checklist (Self-Review)

Reference checklist for reviewing tests in the current diff before PR creation.

## Coverage Check
- Missing tests for new behavior/branches?
- Edge cases, boundary values, error paths?
- Negative cases, invalid inputs, failure modes?

## Assertion Quality
- Checking behavior, not implementation details?
- Weak assertions (too generic, no failure message)?
- Over-asserting unimportant details?

## Test Design
- Descriptive names (given/when/then or AAA)?
- Clear intent, minimal mental overhead?
- Magic values replaced with constants/factories/helpers?
- Duplicated setup moved to fixtures/parametrized tests?

## Output Format

```
## Test Review Findings

### Missing Coverage
| Behavior | Suggested Test |
|----------|----------------|
| [behavior] | [test name and approach] |

### Issues Found
| # | Type | Test | Issue | Fix |
|---|------|------|-------|-----|
| 1 | Weak assertion | test_foo | [desc] | [fix] |

### Fixes Applied
- [x] Added: test_edge_case_X
- [x] Fixed: improved assertions in test_Y
```

## After Review

1. Create tasks for missing coverage and significant issues
2. Implement new/improved tests
3. Run test suite
4. Verify all tests pass
