---
name: code-quality-principles
description: "[flow] Code quality principles with Boy Scout Rule. Leave code better than you found it in files you touch. No secrets in commits. Anti-pattern awareness. No mocks/stubs/TODOs in production. Parallel quality execution."
allowed-tools: Bash, Read, Grep, Glob
---

# Code Quality Principles

Foundation skill governing code quality standards during autonomous development.

## Iron Law

**EVERY CHANGE MUST BE INTENTIONAL. If you can't explain why a line changed, revert it.**

Always leave code better than you found it. Fix issues in files you are already modifying — but only changes that pass the proximity test.

## Before You Write Code

Answer these questions first. If you can't, return to EXPLORE:

1. What is the specific task/criterion this code serves?
2. What files will be modified and why each one?
3. What existing patterns does this project use for this type of change?
4. What could go wrong? (error cases, edge cases, security)
5. How will you verify this works?

## Boy Scout Rule

Leave every file you touch better than you found it. Apply the **proximity test** to decide if a cleanup belongs:

**A cleanup PASSES the proximity test if ALL true:**
1. The file is already being modified for the current task
2. The fix is self-evidently correct (lint, format, typo, obvious bug, missing error handling)
3. The fix is small (under ~10 lines of cleanup)
4. The fix does not change public API signatures or behavior semantics
5. The fix needs no explanation beyond "Boy Scout cleanup"

**A cleanup FAILS the proximity test if ANY true:**
1. Requires modifying files NOT already touched by the task
2. Changes architecture, module boundaries, or public APIs
3. Requires new tests to validate
4. Would need its own issue to explain motivation
5. Is a subjective style preference, not objective improvement

Passing cleanups use `improve:` commits. Failing cleanups get logged as follow-up issues.

## No Secrets in Code

Never commit secrets, credentials, or sensitive values:

- Use environment variables for API keys, tokens, passwords
- Use `.env` files (gitignored) for local development
- Reference secrets by name, never by value
- If you spot a hardcoded secret, flag it as P1 immediately

## Production Code Standards

Code that ships must be complete:

- No `TODO` comments in committed code — track in issues instead
- No `console.log` / `puts` / `print` debugging statements
- No mocked or stubbed implementations ("implement later")
- No commented-out code blocks — delete or use version control
- No placeholder error messages ("Something went wrong")

## Quality Command Execution

Run independent quality commands (lint, test, typecheck) as parallel Bash calls, never chained with `&&`. After quality checks: P1 failures fix immediately, P2 fix before PR, P3 note and proceed.

## Anti-Patterns

Do NOT:
- Modify imports/formatting in files you aren't changing for the task
- Add improvements that fail the proximity test into the same PR
- Commit generated files without verifying they're correct
- Copy-paste code instead of extracting a shared function
- Catch exceptions silently (`catch {}` / `rescue nil`)

## First-Touch Awareness

When a file has 0 prior commits on the branch and you're making large additions:

- Flag it as "first touch" in change classification
- Give it extra review attention — new files have no established patterns
- Ensure it follows the project's conventions (naming, structure, style)

## Atomic Commits

Each commit should be a complete, valuable change:

- Can you describe it without saying "WIP" or "partial"?
- Does it leave the codebase in a working state?
- Would reverting it cleanly undo one logical change?

If yes to all three, commit. Otherwise, keep working.

## Self-Review Checklist

Before marking any task complete:

1. `git diff` — only intended changes present?
2. No debug code or temporary files?
3. New code follows existing patterns in the project?
4. Edge cases considered (null, empty, boundary values)?
5. Error messages are helpful and specific?

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "I'll clean this up while I'm here" | Does it pass the proximity test? If yes, fix it with an `improve:` commit. If no, log it. |
| "This TODO is temporary" | TODOs in commits are permanent. Create an issue instead. |
| "The tests pass, it's fine" | Tests passing is necessary, not sufficient. Run the self-review checklist. |
| "This debug log helps with development" | Remove it. Development aids don't ship. |
| "It's just a small formatting fix" | If the file is already touched for the task and the fix passes the proximity test, use an `improve:` commit. Otherwise, it's not in your commit. |
