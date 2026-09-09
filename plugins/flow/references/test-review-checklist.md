# Test Review Checklist

Reference checklist for reviewing test quality during PR review. Before reading the tests, derive the expected behavior from the issue/spec; then check each test against that derivation. The tests are not the spec.

## Test Coverage

- [ ] Every new public function/method has at least one test
- [ ] Happy path tested
- [ ] Error/failure path tested
- [ ] Edge cases covered (empty, null, boundary values)
- [ ] Each `Risk areas:` row of the task has a test whose input distinguishes the right implementation from that row's plausible wrong version

## Test Quality

- [ ] Tests are independent (no shared mutable state)
- [ ] Tests are deterministic (same result every run)
- [ ] Test names describe the behavior being tested
- [ ] Assertions are specific (not just "no error")
- [ ] Each test tests one thing
- [ ] Every expected value has a stated source: spec/criterion text, reference implementation, hand computation, existing fixture, or external standard (comment in the test, or the evidence bundle's `Source of expected` column). A literal that only the implementation could have produced is a copied output, not an expectation.
- [ ] Inputs are non-degenerate for order-, position-, or value-sensitive behavior: no identical elements, symmetric/palindromic data, zero, a single repeated value, or the simplest possible case as the only input. Such inputs pass under a reversed, transposed, or off-by-one implementation.
- [ ] For transformations, at least one input is not a fixed point of the transformation
- [ ] For validation/rejection logic, at least one input reaches the success path

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
| Expected value copied from implementation output, or has no stated source and the criterion is behavioral | P1 |
| Degenerate input for order/position/value-sensitive behavior | P1 |
| A `Risk areas:` row with no discriminating test | P2 |
| Shared mutable state between tests | P2 |
