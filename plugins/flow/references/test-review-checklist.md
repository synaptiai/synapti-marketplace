# Test Review Checklist

Reference checklist for reviewing test quality during PR review.

## Test Coverage

- [ ] Every new public function/method has at least one test
- [ ] Happy path tested
- [ ] Error/failure path tested
- [ ] Edge cases covered (empty, null, boundary values)

## Test Quality

- [ ] Tests are independent (no shared mutable state)
- [ ] Tests are deterministic (same result every run)
- [ ] Test names describe the behavior being tested
- [ ] Assertions are specific (not just "no error")
- [ ] Each test tests one thing

## Test Patterns

### Good
```
test "returns error when input is empty" do
  result = process("")
  assert_error(result, :empty_input)
end
```

### Bad
```
test "it works" do
  result = process("hello")
  assert result  # What exactly are we testing?
end
```

## Integration Tests

For changes that touch multiple layers:

- [ ] At least one test exercises the full chain (no mocks for interacting layers)
- [ ] Database transactions tested with real database
- [ ] API endpoints tested with real HTTP requests
- [ ] Callback chains verified end-to-end

## What to Flag

| Issue | Priority |
|-------|----------|
| No tests for new functionality | P2 |
| Only happy path tested | P2 |
| Flaky test (timing, random, external) | P2 |
| Test mocks the thing being tested | P1 |
| Test doesn't actually assert anything | P1 |
| Shared mutable state between tests | P2 |
