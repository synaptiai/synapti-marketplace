---
name: code-quality-principles
description: "[flow] Code quality principles for surgical, safe development. Only change what's needed. No secrets in commits. Anti-pattern awareness. No mocks/stubs/TODOs in production. Parallel quality execution."
allowed-tools: Bash, Read, Grep, Glob
---

# Code Quality Principles

Foundation skill governing code quality standards during autonomous development.

## Iron Law

**EVERY CHANGE MUST BE INTENTIONAL. If you can't explain why a line changed, revert it.**

No drive-by refactors. No "while I'm here" improvements. No formatting changes in files you aren't modifying for the task.

## Before You Write Code

Answer these questions first. If you can't, return to EXPLORE:

1. What is the specific task/criterion this code serves?
2. What files will be modified and why each one?
3. What existing patterns does this project use for this type of change?
4. What could go wrong? (error cases, edge cases, security)
5. How will you verify this works?

## Surgical Changes

Only modify what the task requires. Measure every edit against: "Does this directly serve the current task?"

- Don't refactor adjacent code while fixing a bug
- Don't add features while addressing review feedback
- Don't update formatting in files you're not changing
- If you notice something worth improving, log it — don't fix it now

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
- Add "improvements" discovered during review into the same PR
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
| "I'll clean this up while I'm here" | Log it. Don't fix it. Surgical changes only. |
| "This TODO is temporary" | TODOs in commits are permanent. Create an issue instead. |
| "The tests pass, it's fine" | Tests passing is necessary, not sufficient. Run the self-review checklist. |
| "This debug log helps with development" | Remove it. Development aids don't ship. |
| "It's just a small formatting fix" | If it's not in your task, it's not in your commit. |
