---
name: tdd-patterns
description: "Guide test-driven development through the Red-Green-Refactor cycle, test quality standards, and test runner discipline. Enforce test-first when tddMode is 'enforce'. Use when implementing features or fixing bugs."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TaskCreate, TaskList, TaskUpdate
context: fork
agent: general-purpose
---

# TDD Patterns

Domain skill for test-driven development: Red-Green-Refactor cycle, test quality, and runner discipline.

## Iron Law

**IF YOU DIDN'T WATCH THE TEST FAIL, YOU DON'T KNOW IF IT TESTS THE RIGHT THING.**

A test that has never failed might pass for the wrong reason. The RED phase exists to prove the test is valid.

## Red-Green-Refactor Cycle

For each feature or fix, track the TDD cycle with tasks:

```
TaskCreate("RED: Write failing test for {behavior}", "Minimal test describing desired behavior. MUST fail on first run.")
TaskCreate("GREEN: Implement {behavior}", "Simplest code to make the test pass. No cleverness.")
TaskCreate("REFACTOR: Clean up {behavior}", "Improve quality. All tests must still pass after each step.")
```

### RED: Write a Failing Test

TaskUpdate(RED task, status: "in_progress")

1. Write the **minimal** test that describes the desired behavior
2. Run it — it MUST fail
3. Verify it fails for the **right reason** (not a syntax error, not wrong import)

TaskUpdate(RED task, status: "completed")

### GREEN: Make It Pass

TaskUpdate(GREEN task, status: "in_progress")

1. Write the **simplest** code that makes the test pass
2. No cleverness. No optimization. No "while I'm here" improvements.
3. Run the test — it MUST pass now

TaskUpdate(GREEN task, status: "completed")

### REFACTOR: Clean Up

TaskUpdate(REFACTOR task, status: "in_progress")

1. Improve code quality (naming, structure, duplication)
2. Run ALL tests after each refactor step — they must still pass
3. No new functionality during refactor — that's a new RED phase

TaskUpdate(REFACTOR task, status: "completed")
Use TaskList to confirm the full cycle completed before moving to the next behavior.

**The cycle is non-negotiable.** RED → GREEN → REFACTOR. Always in this order.

## Test Runner Discipline

**Always use `run` mode, never `watch` mode:**

| Framework | Correct | Wrong |
|-----------|---------|-------|
| Vitest | `vitest run` | `vitest` (watch) |
| Jest | `CI=true jest` or `jest --watchAll=false` | `jest` (watch) |
| Pytest | `pytest` | — |
| RSpec | `rspec` | `guard` (watch) |

Watch mode leaves orphan processes. Verify cleanup:

```bash
pgrep -f "vitest|jest|pytest" && echo "ORPHAN PROCESS — kill it"
```

## Test Quality Standards

### One Behavior Per Test

```
# GOOD: Each test verifies one thing
test "returns empty array when no items match"
test "returns matching items sorted by relevance"

# BAD: Multiple behaviors in one test
test "search works correctly"  # What does "correctly" mean?
```

### Descriptive Names

Test names should read as specifications:
- "creates user with valid email"
- "rejects duplicate usernames"
- "returns 404 when resource not found"

### Real Code Over Mocks

- Mock ONLY at external boundaries (APIs, databases, file system)
- Never mock the code under test
- Never mock internal collaborators unless they have side effects
- If you need many mocks, the design needs improvement

### No Testing Implementation Details

- Test behavior (what), not implementation (how)
- Don't assert on internal state, private methods, or call counts
- If refactoring breaks tests but not behavior, the tests are wrong

## When TDD Applies

| Scenario | TDD? | Notes |
|----------|------|-------|
| New feature | **Always** | Define behavior before implementing |
| Bug fix | **Always** | Write reproducing test first |
| Refactor | Existing tests | Ensure tests pass before AND after |
| Prototype/spike | Optional | But write tests before merging |
| Config changes | No | Unless behavior changes |

## Process Enforcement

Check `settings.json` → `testing.tddMode`:

| Mode | Default? | Behavior |
|------|----------|----------|
| `enforce` | **Yes** | Block implementation without a failing test. No exceptions. The RED phase must produce a failing test before any production code is written. |
| `suggest` | No (opt-in) | Recommend TDD. Allow override with explicit user decision. |
| `off` | No (opt-in) | No TDD guidance. Tests still run in verification. |

### Opt-out mechanism

`enforce` is the default because skipping the RED phase is the #1 source of tests that pass for the wrong reason. Teams that need the old `suggest` behavior can opt out:

```json
{
  "testing": {
    "tddMode": "suggest",
    "tddModeOptOut": true
  }
}
```

Set `testing.tddModeOptOut` to `true` in `settings.json` to switch `tddMode` back to `suggest`. When `tddModeOptOut` is `false` (the default), `tddMode` must remain `enforce`. This two-field design ensures the opt-out is an explicit, auditable decision rather than a silent default change.

## Coverage Targets

Aim for meaningful coverage, not vanity metrics:

- **80%+** for branches, functions, lines, statements
- **100%** for critical paths (auth, payments, data mutations)
- **0%** is acceptable for generated code, config files, type definitions

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "Skip TDD just this once" | Delete the code. Start over. The cycle is the discipline. |
| "This is too simple to test" | Simple code, simple test. Write it in 30 seconds. |
| "I'll write tests after" | You won't. And if you do, they'll test what you wrote, not what you should have written. |
| "Tests slow me down" | Tests slow you down NOW. Bugs slow you down FOREVER. |
| "The test passes on first try" | That's a red flag. It should have failed first. Check: is it testing the right thing? |

## Stop Conditions

| Trigger | Action |
|---------|--------|
| Test passes immediately on first write | Test is suspect. Verify it fails when you break the code intentionally. |
| >3 tests needed for one function | Function may be doing too much. Consider splitting. |
| Mocking >2 dependencies | Design smell. Refactor to reduce coupling. |
| Test is harder to write than the code | Step back. Either the interface is wrong or the test is testing implementation. |
