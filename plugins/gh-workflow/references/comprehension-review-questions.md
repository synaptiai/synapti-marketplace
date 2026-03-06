# Comprehension Review Questions

Question templates for reviewers to probe understanding of AI-generated code. Organized by code pattern type, focused on **intent** and **failure modes** — not trivia.

## Usage

The `gh-review` command (Facet 6: Comprehension Assessment) selects 2-3 questions from this reference based on the diff's complexity areas. Questions are added as P3 findings (suggestions, never blocking).

## Question Categories

### New Module Creation

Questions for when the diff introduces entirely new files, classes, or modules.

| Question | Reveals | When to Use |
|----------|---------|-------------|
| "What responsibility does this module own that no existing module covers?" | Whether the author understands the module boundary | New file in a new directory |
| "If this module fails entirely, what's the blast radius? What stops working?" | Understanding of system dependencies | New module with integration points |
| "Why is this a separate module rather than an extension of {existing module}?" | Architectural reasoning behind the boundary | New module near similar existing code |
| "Walk through the lifecycle: how is this initialized, used, and cleaned up?" | Understanding of the full execution path | New module with state or resources |

### Refactored Module

Questions for when existing code is restructured or reorganized.

| Question | Reveals | When to Use |
|----------|---------|-------------|
| "What behavior changed vs. what was purely structural?" | Whether author distinguishes behavior changes from refactoring | Large refactor diffs |
| "What callers of this code were affected, and how did you verify they still work?" | Understanding of downstream impact | Public API changes |
| "What was the problem with the previous structure that motivated this refactor?" | Whether the refactor has clear purpose | Refactoring without obvious motivation |

### Dependency / Library Integration

Questions for when new packages, gems, crates, or modules are added.

| Question | Reveals | When to Use |
|----------|---------|-------------|
| "What happens if {dependency} is unavailable at runtime? Walk through the error path." | Understanding of failure modes | New external dependency |
| "What alternatives were considered, and why was this one chosen?" | Decision quality and awareness of options | New dependency in a crowded space |
| "What's the upgrade/migration path if this dependency is abandoned or has breaking changes?" | Long-term maintainability awareness | New dependency with deep integration |
| "What data does this dependency have access to?" | Security and privacy awareness | Dependencies handling user data or credentials |

### Configuration Change

Questions for when config files, environment variables, or feature flags change.

| Question | Reveals | When to Use |
|----------|---------|-------------|
| "What happens if this configuration value is missing or invalid in production?" | Error handling and defaults understanding | New config keys |
| "Who or what process sets this value, and how is it validated?" | Understanding of the configuration lifecycle | New environment variables or secrets |
| "What's the rollback path if this configuration causes problems?" | Operational awareness | Config changes affecting runtime behavior |

### Error Handling Path

Questions for when error handling, retry logic, or fallback behavior changes.

| Question | Reveals | When to Use |
|----------|---------|-------------|
| "Walk through what happens when {operation} fails. Where does the error surface to the user?" | Understanding of error propagation | New try/catch, rescue, or error handling |
| "Can this error handler mask a deeper problem? What signals would you look for?" | Debugging awareness | Catch-all or broad error handlers |
| "What's the retry strategy, and what happens if all retries are exhausted?" | Understanding of failure escalation | New retry logic |

### Performance-Sensitive Code

Questions for when changes touch hot paths, queries, or resource-intensive operations.

| Question | Reveals | When to Use |
|----------|---------|-------------|
| "What's the expected load on this code path? How does it scale?" | Performance awareness | New database queries, API calls, loops |
| "What happens under 10x the expected load?" | Capacity planning awareness | Code in request hot paths |
| "Are there caching, batching, or pagination strategies that apply here?" | Optimization awareness | New data access patterns |

## Selection Guidelines

When selecting questions for a review:

1. **Match pattern type** — Identify which categories the diff touches
2. **Pick 2-3 questions max** — More than 3 creates review fatigue
3. **Prioritize failure modes** — Questions about what goes wrong are more valuable than questions about happy paths
4. **Avoid trivia** — Never ask "What does line X do?" or questions answerable by reading the code
5. **Target uncertainty** — If the comprehension report flags an area as "Interpreted" or author flagged low confidence, prioritize questions for that area

## Anti-Patterns

Do NOT ask questions that:
- Can be answered by reading the code (`"What does this function return?"`)
- Test memorization rather than understanding (`"What's the default value of X?"`)
- Are generic and not specific to the diff (`"Did you consider edge cases?"`)
- Block the review — comprehension questions are always P3 (suggestions)
