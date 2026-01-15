# Issue Template

Use this structure when creating GitHub issues with `/gh-workflow:gh-issue`.

---

## Context
<!-- What's the background? Why is this needed? -->

[Describe the background and motivation]

## Current State
<!-- What's happening now? What's the problem? Describe behavior, not implementation. -->

[Describe the current situation or problem]

## Objective
<!-- What should be achieved? What's the desired end state? Focus on outcomes, not methods. -->

[Describe what success looks like]

## Proposed Solution (Optional)
<!--
FOCUS ON "WHAT" NOT "HOW":
- Describe required functionality or behaviors
- List data requirements and success criteria
- Explain business logic and requirements
- Avoid specific file paths
- Avoid specific code structures

Why? Implementation details belong in the PR, not issues.
-->

[If you have a proposed approach, describe it at a high level]

## Tasks
<!-- High-level functional outcomes, not implementation steps -->
- [ ] [Task 1]
- [ ] [Task 2]
- [ ] [Task 3]

## Benefits
<!-- What are the advantages of doing this? -->
- [Benefit 1]
- [Benefit 2]

## Acceptance Criteria
<!-- How do we know this is complete? Describe observable behavior, not file changes. -->
- [ ] [Observable outcome 1]
- [ ] [Observable outcome 2]
- [ ] [Observable outcome 3]

## Related
<!-- Links to related issues, PRs, or discussions -->
- [Related links]

---

## Template Guidelines

### Solution-Agnostic Principles

Issues should survive refactoring. Avoid:
- ❌ Specific file paths (`Update src/components/Button.tsx`)
- ❌ Specific code structures (`Add a new class called X`)
- ❌ Implementation details (`Use Redux for state`)

Instead use:
- ✅ Behavioral descriptions (`Button should show loading state`)
- ✅ Functional outcomes (`User can filter results`)
- ✅ Business requirements (`Support multiple currencies`)

### Why This Matters

- Issues describe WHAT to achieve
- PRs describe HOW it was achieved
- This separation ensures issues remain valid even when implementation changes
